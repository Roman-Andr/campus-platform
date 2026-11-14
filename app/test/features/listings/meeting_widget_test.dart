import 'dart:async';

import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/core/time/city_time.dart';
import 'package:campus/src/features/listings/presentation/meeting_screen.dart';
import 'package:clock/clock.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:dio/dio.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

Map<String, Object?> meetingJson({
  String? scheduledAt,
  String? location,
  String? scheduledBy,
  String? proposedAt,
  String? proposedLocation,
  String? proposedBy,
  bool online = false,
  int version = 1,
}) => {
  'id': 'meeting-1',
  'version': version,
  'status': proposedAt == null ? 'scheduled' : 'proposed',
  'scheduled_at': scheduledAt,
  'location': location,
  'online': online,
  'scheduled_by_id': scheduledBy,
  'proposed_at': proposedAt,
  'proposed_location': proposedLocation,
  'proposed_by_id': proposedBy,
};

Map<String, Object?> interactionJson({
  Map<String, Object?>? meeting,
  String status = 'accepted',
}) => {
  'id': 'request-1',
  'listing_id': 'listing-1',
  'participant_id': 'other',
  'participant_name': 'Boris',
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'status': status,
  'meeting': meeting,
};

Map<String, Object?> participationJson({Map<String, Object?>? meeting}) => {
  ...interactionJson(meeting: meeting),
  'participant_id': userJson['id']! as String,
  'participant_name': 'Ivan Ivanov',
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': 'listing-1',
    'kind': 'giveaway',
    'title': 'A desk',
    'status': 'busy',
    'city_timezone': 'Europe/Moscow',
  },
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

/// A time at [hour] UTC a couple of days ahead, in the future for the test.
DateTime futureAt(int hour) {
  final now = clock.now().toUtc();
  return DateTime.utc(
    now.year,
    now.month,
    now.day,
    hour,
  ).add(const Duration(days: 2));
}

FakeHttpAdapter meetingServer({
  required Map<String, Object?> Function() participation,
  ResponseBody Function(RequestOptions options)? onAccept,
  ResponseBody Function(RequestOptions options)? onPropose,
  ResponseBody Function(RequestOptions options)? onTransition,
}) => FakeHttpAdapter(feed: pageJson([]))
  ..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path.endsWith('/reservations/mine')) {
      return jsonBody(200, pageJson([participation()]));
    }
    if (options.path.endsWith('/meeting/accept')) {
      return (onAccept ?? (_) => problemBody(404, 'not_found'))(options);
    }
    if (options.path.endsWith('/meeting/proposals')) {
      return (onPropose ?? (_) => problemBody(404, 'not_found'))(options);
    }
    if (options.path.endsWith('/transition')) {
      return (onTransition ?? (_) => problemBody(404, 'not_found'))(options);
    }
    if (options.path.endsWith('/cities')) return jsonBody(200, citiesJson);
    return jsonBody(200, listingJson(author: 'other'));
  });

Future<void> openMeeting(WidgetTester tester, FakeHttpAdapter adapter) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: adapter,
  );
  unawaited(
    container
        .read(appRouterProvider)
        .push(meetingPath('listing-1', 'request-1')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('My and the listing card show the meeting and the proposal', (
    tester,
  ) async {
    english(tester);
    final scheduled = futureAt(15);
    final proposed = futureAt(17);
    final server = meetingServer(
      participation: () => participationJson(
        meeting: meetingJson(
          scheduledAt: scheduled.toIso8601String(),
          location: 'Library',
          scheduledBy: 'other',
          proposedAt: proposed.toIso8601String(),
          proposedLocation: 'Cafe',
          proposedBy: 'other',
          version: 2,
        ),
      ),
    );
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My participation'));
    await tester.pumpAndSettle();
    expect(find.text('Current meeting'), findsOneWidget);
    // 15:00 UTC is 18:00 in Moscow.
    expect(find.textContaining('18:00'), findsOneWidget);
    expect(find.text('Place: Library'), findsOneWidget);
    expect(find.text('New proposal'), findsOneWidget);
    expect(find.text('Place: Cafe'), findsOneWidget);
    expect(find.text('Waiting for your response'), findsOneWidget);
    expect(find.byKey(const Key('meeting-open-request-1')), findsOneWidget);

    unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
    await tester.pumpAndSettle();
    expect(find.text('Current meeting'), findsOneWidget);
    expect(find.text('New proposal'), findsOneWidget);
  });

  testWidgets('confirming a proposal refreshes the meeting card', (
    tester,
  ) async {
    english(tester);
    final scheduled = futureAt(15);
    final proposed = futureAt(17);
    var confirmed = false;
    final server = meetingServer(
      participation: () => participationJson(
        meeting: confirmed
            ? meetingJson(
                scheduledAt: proposed.toIso8601String(),
                location: 'Cafe',
                scheduledBy: 'other',
                version: 3,
              )
            : meetingJson(
                scheduledAt: scheduled.toIso8601String(),
                location: 'Library',
                scheduledBy: 'other',
                proposedAt: proposed.toIso8601String(),
                proposedLocation: 'Cafe',
                proposedBy: 'other',
                version: 2,
              ),
      ),
      onAccept: (_) {
        confirmed = true;
        return jsonBody(
          200,
          meetingJson(
            scheduledAt: proposed.toIso8601String(),
            location: 'Cafe',
            scheduledBy: 'other',
            version: 3,
          ),
        );
      },
    );
    await openMeeting(tester, server);
    expect(find.text('Confirm'), findsOneWidget);
    await tester.tap(find.byKey(const Key('meeting-accept')));
    await tester.pumpAndSettle();
    final accept = server.sent.singleWhere(
      (request) => request.path.endsWith('/meeting/accept'),
    );
    expect(accept.json, {'version': 2});
    expect(accept.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Meeting confirmed.'), findsOneWidget);
    expect(find.text('Place: Cafe'), findsOneWidget);
    expect(find.text('New proposal'), findsNothing);
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('a stale proposal is explained and the card refreshes', (
    tester,
  ) async {
    english(tester);
    final scheduled = futureAt(15);
    final proposed = futureAt(17);
    var stale = false;
    final server = meetingServer(
      participation: () => participationJson(
        meeting: stale
            ? meetingJson(
                scheduledAt: scheduled.toIso8601String(),
                location: 'Library',
                scheduledBy: 'other',
                proposedAt: proposed
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
                proposedLocation: 'New place',
                proposedBy: 'author',
                version: 3,
              )
            : meetingJson(
                scheduledAt: scheduled.toIso8601String(),
                location: 'Library',
                scheduledBy: 'other',
                proposedAt: proposed.toIso8601String(),
                proposedLocation: 'Old place',
                proposedBy: 'other',
                version: 2,
              ),
      ),
      onAccept: (_) {
        stale = true;
        return problemBody(409, 'meeting_stale');
      },
    );
    await openMeeting(tester, server);
    expect(find.text('Place: Old place'), findsOneWidget);
    await tester.tap(find.byKey(const Key('meeting-accept')));
    await tester.pumpAndSettle();
    expect(
      find.text('The proposal has changed. Check the new time and place.'),
      findsOneWidget,
    );
    expect(find.text('Place: New place'), findsOneWidget);
    expect(find.text('Place: Old place'), findsNothing);
  });

  testWidgets('rescheduling sends a future proposal and shows it', (
    tester,
  ) async {
    english(tester);
    final scheduled = futureAt(15);
    var proposed = false;
    final server = meetingServer(
      participation: () => participationJson(
        meeting: proposed
            ? meetingJson(
                scheduledAt: scheduled.toIso8601String(),
                location: 'Library',
                scheduledBy: 'other',
                proposedAt: scheduled.toIso8601String(),
                proposedLocation: 'Cafe',
                proposedBy: userJson['id']! as String,
                version: 2,
              )
            : meetingJson(
                scheduledAt: scheduled.toIso8601String(),
                location: 'Library',
                scheduledBy: 'other',
              ),
      ),
      onPropose: (_) {
        proposed = true;
        return jsonBody(
          200,
          meetingJson(
            scheduledAt: scheduled.toIso8601String(),
            location: 'Library',
            scheduledBy: 'other',
            proposedAt: scheduled.toIso8601String(),
            proposedLocation: 'Cafe',
            proposedBy: userJson['id']! as String,
            version: 2,
          ),
        );
      },
    );
    await openMeeting(tester, server);
    await tester.tap(find.byKey(const Key('meeting-propose')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('meeting-place')), 'Cafe');
    await tester.tap(find.byKey(const Key('meeting-send')));
    await tester.pumpAndSettle();
    final sent = server.sent.singleWhere(
      (request) => request.path.endsWith('/meeting/proposals'),
    );
    expect(sent.json['location'], 'Cafe');
    expect(
      DateTime.parse(sent.json['time']! as String).isAfter(clock.now()),
      isTrue,
    );
    expect(find.text('Proposal sent.'), findsOneWidget);
    expect(find.text('Your proposal'), findsOneWidget);
    expect(find.text('Place: Cafe'), findsOneWidget);
    expect(
      find.text('Waiting for the other participant to respond'),
      findsOneWidget,
    );
  });

  testWidgets('a time in the past is rejected by the proposal form', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: MeetingProposalForm(
            initialTime: clock.now().subtract(const Duration(hours: 1)),
            timezone: 'Europe/Moscow',
            city: 'Moscow',
            onSubmit: (_, _) => submitted = true,
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('meeting-place')), 'Library');
    await tester.tap(find.byKey(const Key('meeting-send')));
    await tester.pumpAndSettle();
    expect(find.text("The time can't be in the past."), findsOneWidget);
    expect(submitted, isFalse);
  });

  testWidgets('the proposal date picker starts today', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: MeetingProposalForm(
            initialTime: futureAt(12),
            timezone: 'Europe/Moscow',
            city: 'Moscow',
            onSubmit: (_, _) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose date and time'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    final now = tz.TZDateTime.from(clock.now(), cityLocation('Europe/Moscow'));
    expect(dialog.firstDate, DateTime(now.year, now.month, now.day));
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('the participant can withdraw the interaction', (tester) async {
    english(tester);
    final scheduled = futureAt(15);
    final server = meetingServer(
      participation: () => participationJson(
        meeting: meetingJson(
          scheduledAt: scheduled.toIso8601String(),
          location: 'Library',
          scheduledBy: 'other',
        ),
      ),
      onTransition: (_) => jsonBody(200, {
        ...interactionJson(),
        'participant_id': userJson['id'],
        'status': 'cancelled',
      }),
    );
    await openMeeting(tester, server);
    await tester.tap(find.byKey(const Key('meeting-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel the interaction?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel'));
    await tester.pumpAndSettle();
    final sent = server.sent.singleWhere(
      (request) => request.path.endsWith('/transition'),
    );
    expect(sent.json, {'status': 'cancelled'});
    expect(find.byType(MeetingScreen), findsNothing);
  });
}
