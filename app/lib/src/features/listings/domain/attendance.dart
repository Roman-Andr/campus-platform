import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';

/// How the organiser marks attendance, when the listing carries a known mode.
AttendanceMode? listingAttendanceMode(ListingOutput listing) =>
    switch (listing.eventAttendanceMode) {
      final ListingOutputEventAttendanceModeAttendanceMode mode => mode.value,
      _ => null,
    };

/// Whether participants mark themselves with the organiser's rotating code.
bool attendanceIsSelf(AttendanceMode? mode) => mode == AttendanceMode.self;

/// Whether the organiser scans the personal codes of participants.
bool attendanceIsScan(AttendanceMode? mode) => mode == AttendanceMode.scan;

/// The inclusive window in which the server accepts attendance marks.
///
/// It opens [opensBefore] before the event starts and closes with the event
/// end; the same rule applies on the server, so the client switches the same
/// states without waiting for a refusal.
class AttendanceWindow {
  const AttendanceWindow({required this.opensAt, required this.closesAt});

  /// The first instant a mark is accepted, in UTC.
  final DateTime opensAt;

  /// The last instant a mark is accepted, in UTC.
  final DateTime closesAt;
}

/// Where the event is relative to its attendance window.
enum AttendancePhase { before, open, after }

/// The window of [listing], or `null` for a listing without event times.
AttendanceWindow? attendanceWindow(
  ListingOutput listing, {
  required Duration opensBefore,
}) {
  final startsAt = listing.eventStartsAt;
  final endsAt = listing.eventEndsAt;
  if (startsAt == null || endsAt == null) return null;
  return AttendanceWindow(
    opensAt: startsAt.subtract(opensBefore),
    closesAt: endsAt,
  );
}

/// The phase of [window] at [now]; both ends are inclusive, like on the server.
AttendancePhase attendancePhase(AttendanceWindow window, DateTime now) {
  if (now.isBefore(window.opensAt)) return AttendancePhase.before;
  if (now.isAfter(window.closesAt)) return AttendancePhase.after;
  return AttendancePhase.open;
}

/// How long the rotating code is valid from the moment it was received.
///
/// The server reports both instants, so a skewed device clock does not cut
/// the code short: the countdown is a duration, not a wall-clock comparison.
Duration attendanceCodeLifetime(AttendanceCodeOutput code) {
  final lifetime = code.expiresAt.difference(code.serverTime);
  return lifetime.isNegative ? Duration.zero : lifetime;
}

/// How long to show a code before requesting the next one.
///
/// The next code is requested a fifth of the lifetime early, so a reader
/// never gets a code that is about to die whatever TTL the server configures.
Duration attendanceCodeRefreshAfter(AttendanceCodeOutput code) =>
    attendanceCodeLifetime(code) * 0.8;

/// Whether [error] is the server saying the code belongs to another mode.
bool attendanceIsModeConflict(Object error) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventAttendanceModeConflict),
  ) =>
    true,
  _ => false,
};

/// A message for a failed attendance request.
///
/// [cityTime] formats an instant in the city of the event; the server names
/// the moment the window opens in the `available_at` extension of its
/// refusal, and that moment is shown in the event's own zone (#44).
String attendanceFailureMessage(
  AppLocalizations l,
  Object error, {
  String Function(DateTime instant)? cityTime,
}) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventAttendanceForbidden),
  ) =>
    l.attendanceForbidden,
  ProblemFailure(
    code: ProblemCodeKnown(
      value: ProblemCodeValue.eventAttendanceNotRegistered,
    ),
  ) =>
    l.attendanceNotRegistered,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventAttendanceClosed),
    :final problem,
  ) =>
    switch (problem.availableAt) {
      final availableAt? when cityTime != null => l.attendanceWindowBefore(
        cityTime(availableAt),
      ),
      _ => l.attendanceWindowAfter,
    },
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventAttendanceUnavailable),
  ) =>
    l.attendanceUnavailable,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventAttendanceModeConflict),
  ) =>
    l.attendanceModeConflict,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventAttendanceCodeInvalid),
  ) =>
    l.attendanceCodeInvalid,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventAttendanceCodeExpired),
  ) =>
    l.attendanceCodeExpired,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventAttendanceNotFound),
  ) =>
    l.attendanceNotFound,
  _ => apiFailureMessage(l, error),
};

/// The label of a mark method.
String attendanceMethodName(AppLocalizations l, AttendanceMode method) =>
    attendanceIsScan(method) ? l.attendanceMethodScan : l.attendanceMethodSelf;

/// Active marks first, in the order the server returned them; removed marks
/// follow, so the organiser sees who is present without scrolling past the
/// marks that were cancelled.
List<AttendanceItemOutput> attendanceSortedItems(
  List<AttendanceItemOutput> items,
) => [
  ...items.where((item) => item.removedAt == null),
  ...items.where((item) => item.removedAt != null),
];

/// The city clock of an event, as [formatCityTime] expects it.
String Function(DateTime instant) attendanceCityTime(
  ListingOutput listing,
  AppLocalizations l,
) =>
    (instant) => formatCityTime(
      instant,
      timezone: listing.cityTimezone,
      city: listing.cityTimezone,
      l10n: l,
      includeDate: true,
    );
