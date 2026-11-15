import 'dart:ui' show Locale;

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations.dart';
import 'package:campus/src/features/listings/application/attendance.dart';
import 'package:campus/src/features/listings/domain/attendance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fixtures.dart';

/// A listing at [startsAt]–[endsAt]; both are UTC instants.
ListingOutput eventListing({
  required DateTime startsAt,
  required DateTime endsAt,
  String? mode = 'self',
}) => ListingOutput.fromJson(
  eventListingJson(
    startsAt: startsAt.toIso8601String(),
    endsAt: endsAt.toIso8601String(),
    attendanceMode: mode,
  ),
);

AttendanceCodeOutput codeOutput({DateTime? serverTime, DateTime? expiresAt}) {
  final now = serverTime ?? DateTime.utc(2026, 11, 15, 20);
  return AttendanceCodeOutput(
    listingId: 'event-1',
    mode: AttendanceMode.self,
    code: 'opaque-code',
    issuedAt: now,
    expiresAt: expiresAt ?? now.add(const Duration(seconds: 30)),
    serverTime: now,
  );
}

ProblemFailure problemFailure(String codeValue, {DateTime? availableAt}) =>
    ProblemFailure(
      Problem(
        type: 'urn:problem:campus:$codeValue',
        title: 'Server title',
        status: 409,
        code: ProblemCodeKnown(
          ProblemCodeValue.values.firstWhere(
            (value) => value.value == codeValue,
          ),
        ),
        availableAt: availableAt,
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });
  final l = lookupAppLocalizations(const Locale('en'));
  final startsAt = DateTime.utc(2026, 12, 1, 18);
  final endsAt = DateTime.utc(2026, 12, 1, 20);

  group('attendance window', () {
    test('opens thirty minutes before the start and closes with the end', () {
      final listing = eventListing(startsAt: startsAt, endsAt: endsAt);
      final window = attendanceWindow(
        listing,
        opensBefore: const Duration(minutes: 30),
      )!;

      expect(window.opensAt, DateTime.utc(2026, 12, 1, 17, 30));
      expect(window.closesAt, endsAt);
    });

    test('takes the lead of the configuration, not a hardcoded one', () {
      final listing = eventListing(startsAt: startsAt, endsAt: endsAt);
      final window = attendanceWindow(
        listing,
        opensBefore: const Duration(hours: 1),
      )!;

      expect(window.opensAt, DateTime.utc(2026, 12, 1, 17));
    });

    test('both ends are inclusive like on the server', () {
      final listing = eventListing(startsAt: startsAt, endsAt: endsAt);
      final window = attendanceWindow(
        listing,
        opensBefore: const Duration(minutes: 30),
      )!;

      expect(
        attendancePhase(
          window,
          window.opensAt.subtract(const Duration(seconds: 1)),
        ),
        AttendancePhase.before,
      );
      expect(attendancePhase(window, window.opensAt), AttendancePhase.open);
      expect(
        attendancePhase(window, startsAt.add(const Duration(minutes: 1))),
        AttendancePhase.open,
      );
      expect(attendancePhase(window, window.closesAt), AttendancePhase.open);
      expect(
        attendancePhase(
          window,
          window.closesAt.add(const Duration(seconds: 1)),
        ),
        AttendancePhase.after,
      );
    });

    test('a listing without event times has no window', () {
      final listing = ListingOutput.fromJson(listingJson(kind: 'event'));
      expect(
        attendanceWindow(listing, opensBefore: const Duration(minutes: 30)),
        isNull,
      );
    });
  });

  group('rotating code', () {
    test('lifetime and refresh are durations from the server instants', () {
      final code = codeOutput();

      expect(attendanceCodeLifetime(code), const Duration(seconds: 30));
      expect(attendanceCodeRefreshAfter(code), const Duration(seconds: 24));
    });

    test('an already expired code has no remaining lifetime', () {
      final now = DateTime.utc(2026, 11, 15, 20);
      final code = codeOutput(
        serverTime: now,
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );

      expect(attendanceCodeLifetime(code), Duration.zero);
      expect(attendanceCodeRefreshAfter(code), Duration.zero);
    });

    test('the remaining time shrinks with the device clock only', () {
      final now = DateTime.utc(2026, 11, 15, 20);
      final state = AttendanceCodeState(
        code: codeOutput(serverTime: now),
        receivedAt: now,
      );

      expect(state.remainingAt(now), const Duration(seconds: 30));
      expect(
        state.remainingAt(now.add(const Duration(seconds: 10))),
        const Duration(seconds: 20),
      );
      expect(
        state.remainingAt(now.add(const Duration(minutes: 1))),
        Duration.zero,
      );
    });
  });

  group('mode', () {
    test('is read from the listing, including an unknown value', () {
      expect(
        attendanceIsSelf(
          listingAttendanceMode(
            eventListing(startsAt: startsAt, endsAt: endsAt),
          ),
        ),
        isTrue,
      );
      expect(
        attendanceIsScan(
          listingAttendanceMode(
            eventListing(startsAt: startsAt, endsAt: endsAt, mode: 'scan'),
          ),
        ),
        isTrue,
      );
      expect(
        listingAttendanceMode(
          eventListing(startsAt: startsAt, endsAt: endsAt, mode: null),
        ),
        isNull,
      );
    });
  });

  group('marks', () {
    test('active marks stay first, removed marks follow in server order', () {
      AttendanceItemOutput item(String id, {bool removed = false}) =>
          AttendanceItemOutput.fromJson({
            'id': id,
            'listing_id': 'event-1',
            'participant_id': 'participant-$id',
            'participant_name': 'Participant $id',
            'interaction_id': 'interaction-$id',
            'status': removed ? 'removed' : 'marked',
            'method': 'self',
            'marked_at': '2026-12-01T18:00:00Z',
            'marked_by_id': 'participant-$id',
            'removed_at': removed ? '2026-12-01T18:05:00Z' : null,
            'removed_by_id': removed ? 'organizer-1' : null,
            'registered': true,
          });

      final sorted = attendanceSortedItems([
        item('a'),
        item('b', removed: true),
        item('c'),
        item('d', removed: true),
      ]);

      expect(sorted.map((entry) => entry.id), ['a', 'c', 'b', 'd']);
    });

    test('the method has a localized name', () {
      expect(attendanceMethodName(l, AttendanceMode.self), 'Self-marking');
      expect(attendanceMethodName(l, AttendanceMode.scan), 'Scanning');
    });
  });

  group('refusals', () {
    test('every attendance problem has its own message', () {
      expect(
        attendanceFailureMessage(
          l,
          problemFailure('event_attendance_forbidden'),
        ),
        'Only the event organizer can do this.',
      );
      expect(
        attendanceFailureMessage(
          l,
          problemFailure('event_attendance_not_registered'),
        ),
        'Only a registered participant can be marked.',
      );
      expect(
        attendanceFailureMessage(
          l,
          problemFailure('event_attendance_mode_conflict'),
        ),
        'The event has switched to another attendance mode.',
      );
      expect(
        attendanceFailureMessage(
          l,
          problemFailure('event_attendance_code_invalid'),
        ),
        'The code does not belong to this event.',
      );
      expect(
        attendanceFailureMessage(
          l,
          problemFailure('event_attendance_code_expired'),
        ),
        'The code has expired. Ask for a new one.',
      );
      expect(
        attendanceFailureMessage(
          l,
          problemFailure('event_attendance_not_found'),
        ),
        'This participant has no mark.',
      );
      expect(
        attendanceFailureMessage(
          l,
          problemFailure('event_attendance_unavailable'),
        ),
        'Only events have attendance.',
      );
    });

    test('an early refusal names the opening in the city of the event', () {
      final listing = eventListing(startsAt: startsAt, endsAt: endsAt);
      final message = attendanceFailureMessage(
        l,
        problemFailure(
          'event_attendance_closed',
          availableAt: DateTime.utc(2026, 12, 1, 17, 30),
        ),
        cityTime: attendanceCityTime(listing, l),
      );

      expect(message, startsWith('Attendance opens at '));
      // Europe/Moscow is three hours ahead of UTC in December.
      expect(message, contains('20:30'));
    });

    test('a closed window without an opening instant says it is closed', () {
      expect(
        attendanceFailureMessage(l, problemFailure('event_attendance_closed')),
        'Attendance is closed: the event has ended.',
      );
    });

    test('the wrong mode is recognized without a message', () {
      expect(
        attendanceIsModeConflict(
          problemFailure('event_attendance_mode_conflict'),
        ),
        isTrue,
      );
      expect(
        attendanceIsModeConflict(problemFailure('event_attendance_forbidden')),
        isFalse,
      );
    });

    test('a repeat of a request keeps the key of its intent', () {
      var counter = 0;
      final keys = AttendanceKeys(generate: () => 'key-${++counter}');

      expect(keys.of('self:code-a'), 'key-1');
      expect(keys.of('self:code-a'), 'key-1');
      expect(keys.of('self:code-b'), 'key-2');
      keys.done('self:code-a');
      // The intent that failed stays unknown: another one keeps its own key.
      expect(keys.of('self:code-b'), 'key-2');
      keys.done('self:code-b');
      expect(keys.of('self:code-b'), 'key-3');
    });
  });
}
