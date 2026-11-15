import 'dart:async';

import 'package:campus/src/core/api/network_status.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/listings/presentation/no_meeting_screen.dart';
import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

DateTime futureAt(int hour) {
  final now = clock.now().toUtc();
  return DateTime.utc(
    now.year,
    now.month,
    now.day,
    hour,
  ).add(const Duration(days: 2));
}

Map<String, Object?> meetingJson({
  String? scheduledAt,
  bool online = false,
  int version = 1,
}) => {
  'id': 'meeting-1',
  'version': version,
  'status': 'scheduled',
  'scheduled_at': scheduledAt,
  'location': online ? null : 'Library',
  'online': online,
  'scheduled_by_id': 'author',
  'proposed_at': null,
  'proposed_location': null,
  'proposed_by_id': null,
};

Map<String, Object?> interactionJson({
  String status = 'accepted',
  Map<String, Object?>? meeting,
  String? completionMethod,
  bool withoutMeeting = false,
}) => {
  'id': 'request-1',
  'listing_id': 'listing-1',
  'participant_id': userJson['id']! as String,
  'participant_name': 'Ivan Ivanov',
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'status': status,
  'meeting': meeting,
  'completion_method': completionMethod,
  'without_meeting': withoutMeeting,
};

Map<String, Object?> participationJson({
  String kind = 'skill',
  String status = 'accepted',
  Map<String, Object?>? meeting,
  String? completionMethod,
  bool withoutMeeting = false,
}) => {
  ...interactionJson(
    status: status,
    meeting: meeting,
    completionMethod: completionMethod,
    withoutMeeting: withoutMeeting,
  ),
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': 'listing-1',
    'kind': kind,
    'title': kind == 'skill' ? 'Guitar lessons' : 'A desk',
    'status': status == 'completed' ? 'completed' : 'active',
    'city_timezone': 'Europe/Moscow',
  },
};

Map<String, Object?> noMeetingJson({
  String status = 'accepted',
  String? agreedAt,
  bool confirmedByMe = false,
  bool confirmedByOther = false,
  List<Map<String, Object?>> confirmations = const [],
  bool completed = false,
  String? completedAt,
  Object? completionMethod,
}) => {
  'listing_id': 'listing-1',
  'interaction_id': 'request-1',
  'status': status,
  'method': 'no_meeting',
  'agreed_at': agreedAt,
  'confirmed_by_me': confirmedByMe,
  'confirmed_by_other': confirmedByOther,
  'confirmations': confirmations,
  'completed': completed,
  'completed_at': completedAt,
  'completion_method': completionMethod,
  'rating_weight': completed ? 0.5 : null,
};

Map<String, Object?> confirmationJson(String id, String at) => {
  'participant_id': id,
  'confirmed_at': at,
};

const citiesJson = {
  'items': [
    {
      'id': 'city-moscow',
      'code': 'moscow',
      'name': 'Moscow',
      'timezone': 'Europe/Moscow',
    },
  ],
};

FakeHttpAdapter noMeetingServer({
  required Map<String, Object?> Function() participation,
  required Map<String, Object?> Function() state,
  required Map<String, Object?> Function() listing,
  ResponseBody Function(RequestOptions options)? onConfirm,
  ResponseBody Function(RequestOptions options)? onState,
  ResponseBody Function(RequestOptions options)? onListing,
}) => FakeHttpAdapter(feed: pageJson([]))
  ..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path.endsWith('/reservations/mine')) {
      return jsonBody(200, pageJson([participation()]));
    }
    if (options.path.endsWith('/no-meeting/confirmations')) {
      return (onConfirm ?? (_) => jsonBody(200, state()))(options);
    }
    if (options.path.endsWith('/no-meeting')) {
      return (onState ?? (_) => jsonBody(200, state()))(options);
    }
    if (options.path.endsWith('/cities')) return jsonBody(200, citiesJson);
    if (options.path == '/api/v1/listings/listing-1') {
      return (onListing ?? (_) => jsonBody(200, listing()))(options);
    }
    return jsonBody(200, listing());
  });

Future<ProviderContainer> openNoMeeting(
  WidgetTester tester,
  FakeHttpAdapter adapter,
) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: adapter,
  );
  unawaited(
    container
        .read(appRouterProvider)
        .push(noMeetingPath('listing-1', 'request-1')),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> openMyParticipation(
  WidgetTester tester,
  FakeHttpAdapter adapter,
) async {
  await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: adapter);
  await tester.tap(find.byKey(const Key('home-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('home-my-listings')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('My participation'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the first consent waits and refresh recovers the second', (
    tester,
  ) async {
    english(tester);
    final agreed = futureAt(15);
    var state = noMeetingJson(agreedAt: agreed.toIso8601String());
    final server = noMeetingServer(
      participation: () => participationJson(
        meeting: meetingJson(
          scheduledAt: agreed.toIso8601String(),
          online: true,
        ),
      ),
      state: () => state,
      listing: () => listingJson(kind: 'skill', author: 'other'),
      onConfirm: (_) {
        state = noMeetingJson(
          agreedAt: agreed.toIso8601String(),
          confirmedByMe: true,
          confirmations: [
            confirmationJson(
              userJson['id']! as String,
              futureAt(10).toIso8601String(),
            ),
          ],
        );
        return jsonBody(200, state);
      },
    );
    await openNoMeeting(tester, server);
    expect(find.byKey(const Key('no-meeting-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('no-meeting-confirm')));
    await tester.pumpAndSettle();

    final confirm = server.sent.singleWhere(
      (request) => request.path.endsWith('/no-meeting/confirmations'),
    );
    expect(confirm.method, 'POST');
    expect(confirm.headers['Idempotency-Key'], isNotEmpty);
    expect(find.byKey(const Key('no-meeting-waiting')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('no-meeting-your-consent')),
        matching: find.textContaining('Confirmed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('no-meeting-other-consent')),
        matching: find.text('Not yet'),
      ),
      findsOneWidget,
    );

    // The other participant confirms on another device.
    state = noMeetingJson(
      status: 'completed',
      agreedAt: agreed.toIso8601String(),
      confirmedByMe: true,
      confirmedByOther: true,
      confirmations: [
        confirmationJson(
          userJson['id']! as String,
          futureAt(10).toIso8601String(),
        ),
        confirmationJson('other', futureAt(11).toIso8601String()),
      ],
      completed: true,
      completedAt: futureAt(11).toIso8601String(),
      completionMethod: 'no_meeting',
    );
    await tester.tap(find.byKey(const Key('no-meeting-refresh')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('no-meeting-completed')), findsOneWidget);
    expect(find.text('Completed without a meeting'), findsOneWidget);
    expect(find.byKey(const Key('no-meeting-waiting')), findsNothing);
    expect(find.textContaining('18:00'), findsWidgets);
    expect(find.byKey(const Key('no-meeting-completed-at')), findsOneWidget);
  });

  testWidgets('a help interaction without a meeting can be confirmed', (
    tester,
  ) async {
    english(tester);
    var state = noMeetingJson();
    final server = noMeetingServer(
      participation: () => participationJson(kind: 'help'),
      state: () => state,
      listing: () => listingJson(kind: 'help', author: 'other'),
      onConfirm: (_) {
        state = noMeetingJson(
          agreedAt: futureAt(10).toIso8601String(),
          confirmedByMe: true,
          confirmations: [
            confirmationJson(
              userJson['id']! as String,
              futureAt(10).toIso8601String(),
            ),
          ],
        );
        return jsonBody(200, state);
      },
    );
    await openNoMeeting(tester, server);
    expect(find.byKey(const Key('no-meeting-agreed-at')), findsNothing);

    await tester.tap(find.byKey(const Key('no-meeting-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('no-meeting-waiting')), findsOneWidget);
    expect(find.byKey(const Key('no-meeting-agreed-at')), findsOneWidget);
  });

  testWidgets('a manual retry after network loss keeps the Idempotency-Key', (
    tester,
  ) async {
    english(tester);
    var attempts = 0;
    var state = noMeetingJson();
    final server = noMeetingServer(
      participation: () => participationJson(
        meeting: meetingJson(
          scheduledAt: futureAt(15).toIso8601String(),
          online: true,
        ),
      ),
      state: () => state,
      listing: () => listingJson(kind: 'skill', author: 'other'),
      onConfirm: (options) {
        attempts++;
        if (attempts <= 4) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection reset by peer',
          );
        }
        state = noMeetingJson(
          confirmedByMe: true,
          confirmations: [
            confirmationJson(
              userJson['id']! as String,
              futureAt(10).toIso8601String(),
            ),
          ],
        );
        return jsonBody(200, state);
      },
    );
    await openNoMeeting(tester, server);

    await tester.tap(find.byKey(const Key('no-meeting-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('no-meeting-error')), findsOneWidget);
    expect(
      find.text(
        "Can't reach the server. Check your internet connection and try again.",
      ),
      findsOneWidget,
    );
    expect(
      server.sent
          .where(
            (request) => request.path.endsWith('/no-meeting/confirmations'),
          )
          .length,
      4,
    );

    await tester.tap(find.byKey(const Key('no-meeting-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('no-meeting-waiting')), findsOneWidget);
    final confirmations = server.sent
        .where((request) => request.path.endsWith('/no-meeting/confirmations'))
        .toList();
    expect(confirmations, hasLength(5));
    expect(
      confirmations
          .map((request) => request.headers['Idempotency-Key'])
          .toSet(),
      hasLength(1),
    );
  });

  testWidgets('reconnecting reloads the other consent from the server', (
    tester,
  ) async {
    english(tester);
    var state = noMeetingJson();
    final server = noMeetingServer(
      participation: () => participationJson(
        meeting: meetingJson(
          scheduledAt: futureAt(15).toIso8601String(),
          online: true,
        ),
      ),
      state: () => state,
      listing: () => listingJson(kind: 'skill', author: 'other'),
    );
    final container = await openNoMeeting(tester, server);
    expect(find.byKey(const Key('no-meeting-confirm')), findsOneWidget);

    // The other participant confirms while this device is offline.
    state = noMeetingJson(
      confirmedByOther: true,
      confirmations: [
        confirmationJson('other', futureAt(10).toIso8601String()),
      ],
    );
    container.read(networkStatusProvider.notifier).unreachable();
    await tester.pump();
    container.read(networkStatusProvider.notifier).reachable();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('no-meeting-other-consent')),
        matching: find.textContaining('Confirmed'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('no-meeting-confirm')), findsOneWidget);
  });

  testWidgets('a forbidden interaction shows a localized refusal', (
    tester,
  ) async {
    english(tester);
    final server = noMeetingServer(
      participation: participationJson,
      state: noMeetingJson,
      listing: () => listingJson(kind: 'help', author: 'other'),
      onState: (_) => problemBody(403, 'forbidden'),
    );
    await openNoMeeting(tester, server);

    expect(find.byKey(const Key('no-meeting-load-error')), findsOneWidget);
    expect(find.text('You cannot confirm this interaction.'), findsOneWidget);
  });

  testWidgets('an unavailable interaction explains why confirmation is not '
      'allowed', (tester) async {
    english(tester);
    final server = noMeetingServer(
      participation: () => participationJson(kind: 'help'),
      state: noMeetingJson,
      listing: () => listingJson(kind: 'help', author: 'other'),
      onConfirm: (_) => problemBody(409, 'listing_no_meeting_unavailable'),
    );
    await openNoMeeting(tester, server);

    await tester.tap(find.byKey(const Key('no-meeting-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('no-meeting-error')), findsOneWidget);
    expect(
      find.text('This interaction cannot be completed without a meeting.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed listing load is retried together with the state', (
    tester,
  ) async {
    english(tester);
    var listingAttempts = 0;
    final server = noMeetingServer(
      participation: participationJson,
      state: () => noMeetingJson(agreedAt: futureAt(15).toIso8601String()),
      listing: () => listingJson(kind: 'skill', author: 'other'),
      onListing: (_) {
        listingAttempts++;
        return listingAttempts == 1
            ? problemBody(500, 'internal_error')
            : jsonBody(200, listingJson(kind: 'skill', author: 'other'));
      },
    );
    await openNoMeeting(tester, server);

    expect(find.byKey(const Key('no-meeting-load-error')), findsOneWidget);
    expect(
      find.text('Something went wrong on the server. Please try again later.'),
      findsOneWidget,
    );
    expect(
      server.sent
          .where((request) => request.path.endsWith('/no-meeting'))
          .length,
      1,
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('no-meeting-confirm')), findsOneWidget);
    expect(listingAttempts, 2);
    expect(
      server.sent
          .where((request) => request.path.endsWith('/no-meeting'))
          .length,
      2,
    );
  });

  testWidgets('completion refreshes the participation row label', (
    tester,
  ) async {
    english(tester);
    var completed = false;
    var state = noMeetingJson(agreedAt: futureAt(15).toIso8601String());
    final server = noMeetingServer(
      participation: () => participationJson(
        meeting: meetingJson(
          scheduledAt: futureAt(15).toIso8601String(),
          online: true,
        ),
        status: completed ? 'completed' : 'accepted',
        completionMethod: completed ? 'no_meeting' : null,
        withoutMeeting: completed,
      ),
      state: () => state,
      listing: () => listingJson(kind: 'skill', author: 'other'),
      onConfirm: (_) {
        completed = true;
        state = noMeetingJson(
          status: 'completed',
          agreedAt: futureAt(15).toIso8601String(),
          confirmedByMe: true,
          confirmedByOther: true,
          confirmations: [
            confirmationJson(
              userJson['id']! as String,
              futureAt(10).toIso8601String(),
            ),
            confirmationJson('other', futureAt(11).toIso8601String()),
          ],
          completed: true,
          completedAt: futureAt(11).toIso8601String(),
          completionMethod: 'no_meeting',
        );
        return jsonBody(200, state);
      },
    );
    await openMyParticipation(tester, server);

    expect(find.byKey(const Key('no-meeting-open-request-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('no-meeting-open-request-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-meeting-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('no-meeting-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-meeting-completed')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('interaction-without-meeting-request-1')),
      findsOneWidget,
    );
    expect(find.text('Completed without a meeting'), findsOneWidget);
    expect(find.byKey(const Key('no-meeting-open-request-1')), findsNothing);
  });

  testWidgets('a giveaway does not offer completion without a meeting', (
    tester,
  ) async {
    english(tester);
    final server = noMeetingServer(
      participation: () => participationJson(kind: 'giveaway'),
      state: noMeetingJson,
      listing: () => listingJson(author: 'other'),
    );
    await openMyParticipation(tester, server);

    expect(find.byKey(const Key('no-meeting-open-request-1')), findsNothing);
    expect(find.byKey(const Key('no-meeting-request-1')), findsNothing);
  });
}
