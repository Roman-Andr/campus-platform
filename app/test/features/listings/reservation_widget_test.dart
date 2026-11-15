import 'dart:async';

import 'package:campus/src/core/router/app_router.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

Map<String, Object?> meetingJson({String? scheduledAt, String? proposedAt}) => {
  'id': 'meeting-1',
  'version': 1,
  'status': proposedAt == null ? 'scheduled' : 'proposed',
  'scheduled_at': scheduledAt,
  'location': scheduledAt == null ? null : 'Library',
  'online': false,
  'scheduled_by_id': scheduledAt == null ? null : 'author',
  'proposed_at': proposedAt,
  'proposed_location': proposedAt == null ? null : 'Cafe',
  'proposed_by_id': proposedAt == null ? null : 'other',
};

Map<String, Object?> participationJson({
  String status = 'accepted',
  String? reservationDueAt,
  Map<String, Object?>? meeting,
  String kind = 'giveaway',
}) => {
  'id': 'interaction-1',
  'listing_id': 'listing-1',
  'participant_id': userJson['id'],
  'participant_name': 'Ivan Ivanov',
  'status': status,
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'reservation_due_at': ?reservationDueAt,
  'offer_description': ?null,
  'meeting': meeting,
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': 'listing-1',
    'kind': kind,
    'title': 'A lamp',
    'status': 'busy',
    'city_timezone': 'Europe/Moscow',
  },
};

Map<String, Object?> eventJson({String status = 'cancelled', String? reason}) =>
    {
      'id': 'event-1',
      'interaction_id': 'interaction-1',
      'waitlist_entry_id': null,
      'actor_id': null,
      'action': 'reservation_expired',
      'previous_status': 'accepted',
      'status': status,
      'version': 1,
      'created_at': '2026-11-14T00:00:00Z',
      'reason': reason,
      'stage': null,
      'details': null,
      'via_assistant': false,
      'offline_qr': false,
    };

FakeHttpAdapter serverWith({
  required Map<String, Object?> participation,
  List<Map<String, Object?>> events = const [],
}) => FakeHttpAdapter(feed: pageJson([]))
  ..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path.endsWith('/reservations/mine')) {
      return jsonBody(200, pageJson([participation]));
    }
    if (options.path.endsWith('/events')) {
      return jsonBody(200, pageJson(events));
    }
    return jsonBody(200, pageJson([]));
  });

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

Future<ProviderContainer> openMy(
  WidgetTester tester,
  FakeHttpAdapter server,
) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
  );
  unawaited(container.read(appRouterProvider).push('/my-listings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('My participation'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('an accepted hold shows the time left and asks for a meeting', (
    tester,
  ) async {
    english(tester);
    final due = DateTime.now().toUtc().add(
      const Duration(hours: 46, minutes: 30),
    );
    final server = serverWith(
      participation: participationJson(reservationDueAt: due.toIso8601String()),
    );
    await openMy(tester, server);

    expect(find.textContaining('Hold ends in 46 h'), findsOneWidget);
    expect(find.text('Schedule a meeting to keep the hold.'), findsOneWidget);
    expect(find.text('No meeting scheduled yet'), findsOneWidget);
    expect(
      find.byKey(const Key('reservation-left-interaction-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reservation-hint-interaction-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reservation-until-interaction-1')),
      findsNothing,
    );
  });

  testWidgets('a scheduled meeting replaces the countdown with its time', (
    tester,
  ) async {
    english(tester);
    final meetingAt = DateTime.now().toUtc().add(const Duration(days: 3));
    final server = serverWith(
      participation: participationJson(
        reservationDueAt: meetingAt.toIso8601String(),
        meeting: meetingJson(scheduledAt: meetingAt.toIso8601String()),
      ),
    );
    await openMy(tester, server);

    expect(find.text('Current meeting'), findsOneWidget);
    expect(
      find.textContaining('The hold is extended until the meeting:'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reservation-until-interaction-1')),
      findsOneWidget,
    );
    expect(find.textContaining('Hold ends in'), findsNothing);
    expect(find.text('Schedule a meeting to keep the hold.'), findsNothing);
  });

  testWidgets('a hold released by the deadline explains itself in My', (
    tester,
  ) async {
    english(tester);
    final server = serverWith(
      participation: participationJson(status: 'cancelled'),
      events: [eventJson(reason: 'reservation_expired')],
    );
    await openMy(tester, server);

    expect(find.text('Cancelled'), findsOneWidget);
    expect(
      find.text('The hold expired: no meeting was scheduled in time.'),
      findsOneWidget,
    );
  });

  testWidgets('a hold cancelled by the participant has no reason', (
    tester,
  ) async {
    english(tester);
    final server = serverWith(
      participation: participationJson(status: 'cancelled'),
    );
    await openMy(tester, server);

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Author rejected the request.'), findsNothing);
    expect(
      find.text('The hold expired: no meeting was scheduled in time.'),
      findsNothing,
    );
  });

  testWidgets('the countdown ticks and refreshes the released hold', (
    tester,
  ) async {
    english(tester);
    var now = DateTime.utc(2027, 1, 15, 12);
    var expired = false;
    final due = now.add(const Duration(seconds: 90));
    final server = FakeHttpAdapter(feed: pageJson([]))
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/reservations/mine')) {
          return jsonBody(
            200,
            pageJson([
              participationJson(
                status: expired ? 'cancelled' : 'accepted',
                reservationDueAt: expired ? null : due.toIso8601String(),
              ),
            ]),
          );
        }
        if (options.path.endsWith('/events')) {
          return jsonBody(
            200,
            pageJson([eventJson(reason: 'reservation_expired')]),
          );
        }
        return jsonBody(200, pageJson([]));
      });
    await withClock(Clock(() => now), () async {
      await openMy(tester, server);
      expect(find.text('Hold ends in 1 min'), findsOneWidget);
      expect(
        find.byKey(const Key('reservation-left-interaction-1')),
        findsOneWidget,
      );

      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('The hold ends in less than a minute.'), findsOneWidget);

      expired = true;
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 20 && find.text('Cancelled').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Cancelled'), findsOneWidget);
      for (
        var i = 0;
        i < 20 &&
            find
                .text('The hold expired: no meeting was scheduled in time.')
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.text('The hold expired: no meeting was scheduled in time.'),
        findsOneWidget,
      );
      expect(
        server.sent
            .where((request) => request.path.endsWith('/reservations/mine'))
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(
        server.sent.where((request) => request.path.endsWith('/events')),
        isNotEmpty,
      );
      expect(
        find.byKey(const Key('reservation-left-interaction-1')),
        findsNothing,
      );
    });
  });
}
