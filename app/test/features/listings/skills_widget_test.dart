import 'package:campus/src/features/listings/presentation/skill_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';
import 'lesson_fixtures.dart';

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

FakeHttpAdapter skillServer({
  Map<String, Object?>? listing,
  List<Map<String, Object?>> participations = const [],
  List<Map<String, Object?>> incoming = const [],
  ResponseBody Function(RequestOptions options)? onPublish,
  ResponseBody Function(RequestOptions options)? onLesson,
  ResponseBody Function(RequestOptions options)? onAccept,
  ResponseBody Function(RequestOptions options)? onCounter,
  ResponseBody Function(RequestOptions options)? onRepeat,
}) {
  final item = listing ?? skillListingJson(author: 'other');
  return FakeHttpAdapter(
    feed: pageJson([item]),
    categories: skillCategoriesJson,
    photos: const {'items': []},
  )..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path == '/api/v1/university/cities') {
      return jsonBody(200, citiesJson);
    }
    if (options.method == 'GET' &&
        options.path == '/api/v1/listings/reservations/mine') {
      return jsonBody(200, pageJson(participations));
    }
    if (options.method == 'GET' &&
        options.path == '/api/v1/listings/listing-1/interactions') {
      return jsonBody(200, pageJson(incoming));
    }
    if (options.path.endsWith('/lesson/accept')) {
      return (onAccept ?? (_) => problemBody(404, 'not_found'))(options);
    }
    if (options.path.endsWith('/lesson/counter-proposals')) {
      return (onCounter ?? (_) => problemBody(404, 'not_found'))(options);
    }
    if (options.path.endsWith('/repeat')) {
      return (onRepeat ?? (_) => problemBody(404, 'not_found'))(options);
    }
    if (options.method == 'POST' && options.path == '/api/v1/listings/skills') {
      return (onPublish ?? (_) => jsonBody(201, item))(options);
    }
    if (options.method == 'POST' && options.path.endsWith('/lessons')) {
      return (onLesson ?? (_) => jsonBody(201, lessonInteractionJson()))(
        options,
      );
    }
    return jsonBody(200, item);
  });
}

Future<void> openSkillListing(WidgetTester tester) async {
  await tester.tap(find.text('Guitar lessons'));
  await tester.pumpAndSettle();
}

Future<void> openLessonForm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('lesson-propose')));
  await tester.pumpAndSettle();
}

/// A tall screen: long lesson screens fit entirely, so collapsing an inline
/// form does not leave a scrolled lazy list bouncing at the end of the test.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Scrolls [finder] into view and taps it: a jump of the list needs a frame
/// to relayout before hit testing.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the feed shows the skill direction and opens the listing', (
    tester,
  ) async {
    english(tester);
    final server = skillServer();
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    expect(find.text('Guitar lessons'), findsOneWidget);
    expect(find.textContaining('I can teach'), findsOneWidget);
    await openSkillListing(tester);
    expect(find.text('Skill'), findsOneWidget);
    expect(find.byKey(const Key('lesson-propose')), findsOneWidget);
  });

  testWidgets('a skill listing is published with the chosen direction', (
    tester,
  ) async {
    english(tester);
    final server = skillServer();
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await tester.tap(find.byKey(const Key('feed-create-skill')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateSkillScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('skill-publish')));
    await tester.pumpAndSettle();
    expect(find.text('Fill in this field.'), findsNWidgets(2));
    expect(
      server.sent.where((r) => r.path.endsWith('/listings/skills')),
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('skill-title')),
      'Guitar lessons',
    );
    await tester.enterText(
      find.byKey(const Key('skill-description')),
      'I can teach chords',
    );
    await tester.tap(find.byKey(const Key('skill-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Items').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-direction')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I want to learn').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('skill-publish')));
    await tester.tap(find.byKey(const Key('skill-publish')));
    await tester.pumpAndSettle();
    final sent = server.sent.singleWhere(
      (request) => request.path == '/api/v1/listings/skills',
    );
    expect(sent.json, {
      'title': 'Guitar lessons',
      'description': 'I can teach chords',
      'direction': 'learn',
      'visibility': 'city',
      'audience': 'students',
      'category_id': 'category-items',
    });
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
    expect(find.byType(CreateSkillScreen), findsNothing);
    expect(find.text('The skill listing has been published.'), findsOneWidget);
  });

  testWidgets('a rejected skill listing explains the Problem Details', (
    tester,
  ) async {
    english(tester);
    final server = skillServer(
      onPublish: (_) => problemBody(422, 'listing_content_invalid'),
    );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await tester.tap(find.byKey(const Key('feed-create-skill')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('skill-title')),
      'Guitar lessons',
    );
    await tester.enterText(
      find.byKey(const Key('skill-description')),
      'Too long description',
    );
    await tester.tap(find.byKey(const Key('skill-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Items').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-publish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-error')), findsOneWidget);
    expect(
      find.text('Please check the information you entered.'),
      findsOneWidget,
    );
    expect(find.byType(CreateSkillScreen), findsOneWidget);
  });

  testWidgets('the lesson form needs two options and refuses a fourth', (
    tester,
  ) async {
    english(tester);
    final server = skillServer();
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await openSkillListing(tester);
    await openLessonForm(tester);
    expect(find.byKey(const Key('lesson-slot-0')), findsOneWidget);
    expect(find.byKey(const Key('lesson-slot-1')), findsOneWidget);
    expect(find.byKey(const Key('lesson-slot-2')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('lesson-add-option')));
    expect(find.byKey(const Key('lesson-slot-2')), findsOneWidget);
    final add = tester.widget<OutlinedButton>(
      find.byKey(const Key('lesson-add-option')),
    );
    expect(add.onPressed, isNull);
    await tapVisible(tester, find.byKey(const Key('lesson-slot-2-remove')));
    await tapVisible(tester, find.byKey(const Key('lesson-slot-1-remove')));
    expect(find.byKey(const Key('lesson-slot-1')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('lesson-submit')));
    expect(find.text('Add at least 2 time options.'), findsOneWidget);
    expect(server.sent.where((r) => r.path.endsWith('/lessons')), isEmpty);
    await tapVisible(tester, find.byKey(const Key('lesson-add-option')));
    await tester.enterText(
      find.byKey(const Key('lesson-slot-0-place')),
      'Library',
    );
    await tester.enterText(
      find.byKey(const Key('lesson-slot-1-place')),
      'Cafe',
    );
    await tapVisible(tester, find.byKey(const Key('lesson-submit')));
    final sent = server.sent.singleWhere(
      (request) => request.path.endsWith('/lessons'),
    );
    final options = sent.json['options']! as List<Object?>;
    expect(options, hasLength(2));
    expect(sent.json.containsKey('options'), isTrue);
    final first = options.first as Map<String, Object?>;
    expect(first['location'], 'Library');
    expect(first['online'], isFalse);
    expect(
      DateTime.parse(first['time']! as String).isAfter(DateTime.now()),
      isTrue,
    );
    expect(find.text('Lesson offered.'), findsOneWidget);
  });

  testWidgets('the author selects one of the proposed times', (tester) async {
    english(tester);
    final server = skillServer(
      listing: skillListingJson(),
      incoming: [
        lessonInteractionJson(
          options: [
            lessonOptionJson(proposedBy: 'other'),
            lessonOptionJson(
              id: 'option-2',
              position: 1,
              proposedBy: 'other',
              location: 'Cafe',
            ),
          ],
        ),
      ],
      onAccept: (options) => jsonBody(
        200,
        lessonInteractionJson(
          status: 'accepted',
          options: [
            lessonOptionJson(
              id: 'option-2',
              proposedBy: 'other',
              location: 'Cafe',
              status: 'selected',
            ),
          ],
          meeting: {
            'id': 'meeting-1',
            'version': 1,
            'status': 'scheduled',
            'scheduled_at': DateTime.now()
                .toUtc()
                .add(const Duration(days: 2))
                .toIso8601String(),
            'location': 'Cafe',
            'online': false,
            'scheduled_by_id': userJson['id'],
            'proposed_at': null,
            'proposed_location': null,
            'proposed_by_id': null,
          },
        ),
      ),
    );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await openSkillListing(tester);
    expect(find.byKey(const Key('lesson-option-option-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lesson-accept-option-2')));
    await tester.pumpAndSettle();
    final sent = server.sent.singleWhere(
      (request) => request.path.endsWith('/lesson/accept'),
    );
    expect(sent.json, {'option_id': 'option-2'});
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Lesson scheduled.'), findsOneWidget);
  });

  testWidgets('the author offers another time instead of the options', (
    tester,
  ) async {
    english(tester);
    final incoming = [
      lessonInteractionJson(options: [lessonOptionJson(proposedBy: 'other')]),
    ];
    final server = skillServer(
      listing: skillListingJson(),
      incoming: incoming,
      onCounter: (options) {
        final countered = lessonInteractionJson(
          options: [
            lessonOptionJson(proposedBy: 'other'),
            lessonOptionJson(
              id: 'option-2',
              position: 1,
              proposedBy: userJson['id']! as String,
            ),
          ],
        );
        incoming
          ..clear()
          ..add(countered);
        return jsonBody(200, countered);
      },
    );
    tallScreen(tester);
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await openSkillListing(tester);
    await tester.tap(find.byKey(const Key('lesson-counter')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lesson-counter-place')),
      'Cafe',
    );
    await tapVisible(tester, find.byKey(const Key('lesson-counter-send')));
    final sent = server.sent.singleWhere(
      (request) => request.path.endsWith('/lesson/counter-proposals'),
    );
    expect(sent.json['location'], 'Cafe');
    expect(sent.json['online'], isFalse);
    expect(find.text('Another time offered.'), findsOneWidget);
    expect(find.text('Waiting for the participant'), findsOneWidget);
  });

  testWidgets('another lesson opens the form with the same participant', (
    tester,
  ) async {
    english(tester);
    final meeting = {
      'id': 'meeting-1',
      'version': 1,
      'status': 'scheduled',
      'scheduled_at': DateTime.now()
          .toUtc()
          .add(const Duration(days: 1))
          .toIso8601String(),
      'location': null,
      'online': true,
      'scheduled_by_id': 'other',
      'proposed_at': null,
      'proposed_location': null,
      'proposed_by_id': null,
    };
    final participations = [
      lessonParticipationJson(
        status: 'accepted',
        options: [
          lessonOptionJson(online: true, location: null, status: 'selected'),
        ],
        meeting: meeting,
      ),
    ];
    final server = skillServer(
      listing: skillListingJson(author: 'other', authorName: 'Petr Petrov'),
      participations: participations,
      onRepeat: (_) {
        final repeated = lessonInteractionJson(
          id: 'request-2',
          participant: userJson['id']! as String,
          participantName: 'Ivan Ivanov',
          options: [lessonOptionJson(proposedBy: userJson['id']! as String)],
        );
        participations
          ..clear()
          ..add(
            lessonParticipationJson(
              id: 'request-2',
              options: [
                lessonOptionJson(proposedBy: userJson['id']! as String),
              ],
            ),
          );
        return jsonBody(201, repeated);
      },
    );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await openSkillListing(tester);
    expect(find.text('Online meeting'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lesson-repeat-request-1')));
    await tester.pumpAndSettle();
    expect(find.text('Another lesson with Petr Petrov'), findsOneWidget);
    expect(find.text('With: Petr Petrov'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('lesson-slot-0-place')),
      'Library',
    );
    await tester.enterText(
      find.byKey(const Key('lesson-slot-1-place')),
      'Cafe',
    );
    await tapVisible(tester, find.byKey(const Key('lesson-submit')));
    final sent = server.sent.singleWhere(
      (request) => request.path.endsWith('/repeat'),
    );
    expect(sent.json['options'], hasLength(2));
    expect(find.text('Another lesson offered.'), findsOneWidget);
    expect(find.text('Waiting for the author'), findsOneWidget);
  });

  testWidgets('three options lead to a meeting both sides see', (tester) async {
    english(tester);
    tallScreen(tester);
    final meeting = {
      'id': 'meeting-1',
      'version': 1,
      'status': 'scheduled',
      'scheduled_at': DateTime.now()
          .toUtc()
          .add(const Duration(days: 2))
          .toIso8601String(),
      'location': 'Cafe',
      'online': false,
      'scheduled_by_id': userJson['id'],
      'proposed_at': null,
      'proposed_location': null,
      'proposed_by_id': null,
    };
    final options = [
      lessonOptionJson(proposedBy: 'other'),
      lessonOptionJson(
        id: 'option-2',
        position: 1,
        proposedBy: 'other',
        location: 'Cafe',
      ),
      lessonOptionJson(
        id: 'option-3',
        position: 2,
        proposedBy: 'other',
        location: 'Hall',
      ),
    ];
    final accepted = lessonInteractionJson(
      status: 'accepted',
      options: [
        lessonOptionJson(proposedBy: 'other', status: 'declined'),
        lessonOptionJson(
          id: 'option-2',
          position: 1,
          proposedBy: 'other',
          location: 'Cafe',
          status: 'selected',
        ),
        lessonOptionJson(
          id: 'option-3',
          position: 2,
          proposedBy: 'other',
          location: 'Hall',
          status: 'declined',
        ),
      ],
      meeting: meeting,
    );
    final incoming = [lessonInteractionJson(options: options)];
    final server = skillServer(
      listing: skillListingJson(),
      incoming: incoming,
      onAccept: (_) {
        incoming
          ..clear()
          ..add(accepted);
        return jsonBody(200, accepted);
      },
    );

    // The author answers one of the three options and sees the meeting.
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await openSkillListing(tester);
    expect(find.byKey(const Key('lesson-option-option-1')), findsOneWidget);
    expect(find.byKey(const Key('lesson-option-option-2')), findsOneWidget);
    expect(find.byKey(const Key('lesson-option-option-3')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('lesson-accept-option-2')));
    expect(find.text('Lesson scheduled.'), findsOneWidget);
    expect(find.text('Current meeting'), findsOneWidget);
    expect(find.text('Place: Cafe'), findsOneWidget);

    // The same scheduled meeting is shown to the participant.
    final participantServer = skillServer(
      listing: skillListingJson(author: 'other', authorName: 'Petr Petrov'),
      participations: [
        lessonParticipationJson(
          status: 'accepted',
          options: [
            lessonOptionJson(
              id: 'option-2',
              position: 1,
              proposedBy: 'other',
              location: 'Cafe',
              status: 'selected',
            ),
          ],
          meeting: meeting,
        ),
      ],
    );
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: participantServer,
    );
    await openSkillListing(tester);
    expect(find.text('Current meeting'), findsOneWidget);
    expect(find.text('Place: Cafe'), findsOneWidget);
  });

  testWidgets('the author repeats the lesson and waits for the participant', (
    tester,
  ) async {
    english(tester);
    tallScreen(tester);
    final incoming = [
      lessonInteractionJson(
        status: 'accepted',
        options: [lessonOptionJson(proposedBy: 'other', status: 'selected')],
      ),
    ];
    final repeated = lessonInteractionJson(
      id: 'request-2',
      options: [
        lessonOptionJson(proposedBy: userJson['id']! as String),
        lessonOptionJson(
          id: 'option-2',
          position: 1,
          proposedBy: userJson['id']! as String,
        ),
      ],
    );
    final server = skillServer(
      listing: skillListingJson(),
      incoming: incoming,
      onRepeat: (_) {
        incoming
          ..clear()
          ..add(repeated);
        return jsonBody(201, repeated);
      },
    );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await openSkillListing(tester);
    await tapVisible(tester, find.byKey(const Key('lesson-repeat-request-1')));
    expect(find.text('Another lesson with Boris'), findsOneWidget);
    expect(find.text('With: Boris'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('lesson-slot-0-place')),
      'Library',
    );
    await tester.enterText(
      find.byKey(const Key('lesson-slot-1-place')),
      'Cafe',
    );
    await tapVisible(tester, find.byKey(const Key('lesson-submit')));
    final sent = server.sent.singleWhere(
      (request) => request.path.endsWith('/repeat'),
    );
    expect(sent.json['options'], hasLength(2));
    expect(find.text('Another lesson offered.'), findsOneWidget);
    expect(find.text('Waiting for the participant'), findsOneWidget);
  });
}
