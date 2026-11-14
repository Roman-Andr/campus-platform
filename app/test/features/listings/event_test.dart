import 'dart:ui' show Locale;

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/l10n/generated/app_localizations.dart';
import 'package:campus/src/features/listings/application/events.dart';
import 'package:campus/src/features/listings/domain/event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

Map<String, Object?> participationJson({
  String status = 'accepted',
  String id = 'interaction-1',
}) => {
  'id': id,
  'listing_id': 'event-1',
  'participant_name': 'Ivan Ivanov',
  'participant_id': userJson['id'],
  'status': status,
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'meeting': null,
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': 'event-1',
    'kind': 'event',
    'title': 'Campus concert',
    'status': 'active',
    'city_timezone': 'Europe/Moscow',
  },
};

Map<String, Object?> ownEntryJson({String status = 'waiting', int? position}) =>
    {
      ...waitlistJson(listingId: 'event-1', status: status, position: position),
      'participant_id': userJson['id'],
    };

/// A server that answers the three requests behind the own seat state.
FakeHttpAdapter seatServer({
  required int remaining,
  List<Object?> reservations = const [],
  Map<String, Object?>? entry,
  int capacity = 3,
}) => FakeHttpAdapter()
  ..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path == '/api/v1/listings/event-1') {
      return jsonBody(
        200,
        eventListingJson(capacity: capacity, remaining: remaining),
      );
    }
    if (options.path == '/api/v1/listings/reservations/mine') {
      return jsonBody(200, pageJson(reservations));
    }
    if (options.path == '/api/v1/listings/event-1/waitlist/me') {
      return entry == null
          ? problemBody(404, 'not_found')
          : jsonBody(200, entry);
    }
    return jsonBody(200, pageJson([]));
  });

Future<EventSeat> readSeat(FakeHttpAdapter server) async {
  final container = ProviderContainer(
    overrides: apiOverrides(adapter: server, secure: signedInStorage),
  );
  addTearDown(container.dispose);
  await container.read(authStatusProvider.future);
  final subscription = container.listen(
    eventSeatProvider('event-1'),
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container.read(eventSeatProvider('event-1').future);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('event seats', () {
    test('taken seats are the difference between capacity and places', () {
      final full = ListingOutput.fromJson(eventListingJson(remaining: 1));
      expect(eventRegisteredCount(full), 2);
      final stale = ListingOutput.fromJson(
        eventListingJson(capacity: 2, remaining: 5),
      );
      expect(eventRegisteredCount(stale), 0);
      final withoutCapacity = ListingOutput.fromJson(
        listingJson(kind: 'event'),
      );
      expect(eventRegisteredCount(withoutCapacity), isNull);
    });

    test('a registration wins over a queue entry', () {
      expect(
        eventSeatStatus(registered: true, queued: true, remainingPlaces: 0),
        EventSeatStatus.registered,
      );
      expect(
        eventSeatStatus(registered: false, queued: true, remainingPlaces: 0),
        EventSeatStatus.queued,
      );
      expect(
        eventSeatStatus(registered: false, queued: false, remainingPlaces: 0),
        EventSeatStatus.full,
      );
      expect(
        eventSeatStatus(registered: false, queued: false, remainingPlaces: 1),
        EventSeatStatus.open,
      );
      expect(
        eventSeatStatus(
          registered: false,
          queued: false,
          remainingPlaces: null,
        ),
        EventSeatStatus.open,
      );
    });

    test('signups close when the event started or is no longer live', () {
      final now = DateTime.utc(2026, 11, 14, 12);
      ListingOutput event({String status = 'active', DateTime? startsAt}) =>
          ListingOutput.fromJson(
            eventListingJson(
              status: status,
              startsAt: (startsAt ?? now.add(const Duration(hours: 1)))
                  .toIso8601String(),
            ),
          );
      expect(eventSignupOpen(event(), now), isTrue);
      expect(
        eventSignupOpen(
          event(startsAt: now.subtract(const Duration(minutes: 1))),
          now,
        ),
        isFalse,
      );
      expect(eventSignupOpen(event(status: 'expired'), now), isFalse);
    });

    test('the seat limit cannot drop below the registered count', () {
      expect(eventCapacityValid(capacity: 2, registered: 2), isTrue);
      expect(eventCapacityValid(capacity: 3, registered: 2), isTrue);
      expect(eventCapacityValid(capacity: 1, registered: 2), isFalse);
      expect(eventCapacityValid(capacity: 0, registered: 0), isFalse);
      expect(eventCapacityValid(capacity: null, registered: 0), isFalse);
      expect(eventCapacityValid(capacity: 1, registered: null), isTrue);
    });

    test('the schedule must start in the future and end later', () {
      final now = DateTime.utc(2026, 11, 14, 12);
      expect(
        eventScheduleValid(
          startsAt: now.add(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 3)),
          now: now,
        ),
        isTrue,
      );
      expect(
        eventScheduleValid(
          startsAt: now,
          endsAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(
        eventScheduleValid(
          startsAt: now.add(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('errors explain the reason in both languages', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final ru = lookupAppLocalizations(const Locale('ru'));
      final now = DateTime.utc(2026, 11, 14, 12);
      expect(
        eventCapacityError(en, capacity: 1, registered: 2),
        'The seat limit cannot be lower than the number of registered '
        'participants: 2.',
      );
      expect(
        eventCapacityError(ru, capacity: 1, registered: 2),
        'Лимит не может быть меньше числа записавшихся: 2.',
      );
      expect(eventCapacityError(en, capacity: 0, registered: 0), isNotEmpty);
      expect(eventCapacityError(en, capacity: 2, registered: 2), isNull);
      expect(
        eventScheduleError(
          en,
          startsAt: now,
          endsAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        'The event must start in the future and end after its start.',
      );
      expect(
        eventScheduleError(
          en,
          startsAt: now.add(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 3)),
          now: now,
        ),
        isNull,
      );
    });

    test('the counter reads no seats left at zero', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final ru = lookupAppLocalizations(const Locale('ru'));
      expect(eventSeatsText(en, 3), 'Seats left: 3');
      expect(eventSeatsText(en, 1), 'Seats left: 1');
      expect(eventSeatsText(en, 0), 'No seats left');
      expect(eventSeatsText(en, null), isEmpty);
      expect(eventSeatsText(ru, 2), 'Осталось 2 места');
      expect(eventSeatsText(ru, 5), 'Осталось 5 мест');
    });

    test('only students and employees may create events', () {
      UserOutput user(String accountType) => UserOutput.fromJson({
        ...userJson,
        ...filledProfileJson,
        'account_type': accountType,
      });
      expect(canCreateEvent(user('student')), isTrue);
      expect(canCreateEvent(user('employee')), isTrue);
      expect(canCreateEvent(user('former_employee')), isFalse);
      expect(canCreateEvent(null), isFalse);
    });
  });

  group('own seat state', () {
    test('an accepted interaction reads as registered', () async {
      final seat = await readSeat(
        seatServer(remaining: 1, reservations: [participationJson()]),
      );
      expect(seat.status, EventSeatStatus.registered);
      expect(seat.interaction?.id, 'interaction-1');
      expect(seat.entry, isNull);
    });

    test('a waiting queue entry reads as queued', () async {
      final seat = await readSeat(
        seatServer(remaining: 0, entry: ownEntryJson(position: 2)),
      );
      expect(seat.status, EventSeatStatus.queued);
      expect(seat.entry?.position, 2);
    });

    test('a negative answer without a queue entry reads as full', () async {
      final seat = await readSeat(seatServer(remaining: 0));
      expect(seat.status, EventSeatStatus.full);
      expect(seat.entry, isNull);
    });

    test('free places without own rows read as open', () async {
      final seat = await readSeat(seatServer(remaining: 2));
      expect(seat.status, EventSeatStatus.open);
    });

    test('a cancelled interaction does not count as registration', () async {
      final seat = await readSeat(
        seatServer(
          remaining: 0,
          reservations: [participationJson(status: 'cancelled')],
        ),
      );
      expect(seat.status, EventSeatStatus.full);
    });
  });
}
