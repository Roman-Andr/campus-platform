import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';

/// How the seats of an event are offered to the current user.
///
/// The server answers a signup with `registered`, `queued` or `full`; the
/// card derives the same three states from its own data so it keeps working
/// offline and after a refresh.
enum EventSeatStatus { open, registered, queued, full }

/// Seats taken by registered participants.
///
/// The server exposes the capacity and the remaining places only; the form
/// needs the taken count to refuse a limit below it before sending.
int? eventRegisteredCount(ListingOutput listing) {
  final capacity = listing.eventCapacity;
  final remaining = listing.remainingPlaces;
  if (capacity == null || remaining == null) return null;
  final registered = capacity - remaining;
  return registered < 0 ? 0 : registered;
}

/// The own seat state of an event: a registration wins over a queue entry.
EventSeatStatus eventSeatStatus({
  required bool registered,
  required bool queued,
  required int? remainingPlaces,
}) {
  if (registered) return EventSeatStatus.registered;
  if (queued) return EventSeatStatus.queued;
  if (remainingPlaces != null && remainingPlaces <= 0) {
    return EventSeatStatus.full;
  }
  return EventSeatStatus.open;
}

/// Whether the event still accepts signups: it has not started and is live.
bool eventSignupOpen(ListingOutput listing, DateTime now) {
  final startsAt = listing.eventStartsAt;
  return listing.status == ListingStatus.active &&
      startsAt != null &&
      startsAt.isAfter(now);
}

/// Whether [capacity] may become the seat limit of an event with
/// [registered] participants.
bool eventCapacityValid({required int? capacity, required int? registered}) {
  if (capacity == null || capacity < 1) return false;
  return registered == null || capacity >= registered;
}

/// Whether the schedule is valid: it starts in the future and ends later.
bool eventScheduleValid({
  required DateTime startsAt,
  required DateTime endsAt,
  required DateTime now,
}) => startsAt.isAfter(now) && endsAt.isAfter(startsAt);

/// Why [capacity] cannot be saved, in the words shown under the field.
String? eventCapacityError(
  AppLocalizations l, {
  required int? capacity,
  required int? registered,
}) {
  if (capacity == null || capacity < 1) return l.eventCapacityInvalid;
  if (registered != null && capacity < registered) {
    return l.eventCapacityBelowRegistered(registered);
  }
  return null;
}

/// Why the schedule cannot be saved, or `null` when it can.
String? eventScheduleError(
  AppLocalizations l, {
  required DateTime startsAt,
  required DateTime endsAt,
  required DateTime now,
}) => eventScheduleValid(startsAt: startsAt, endsAt: endsAt, now: now)
    ? null
    : l.eventTimeInvalid;

/// The seat counter of a card: "Seats left: 3" or "No seats left".
String eventSeatsText(AppLocalizations l, int? remainingPlaces) {
  if (remainingPlaces == null) return '';
  return remainingPlaces <= 0
      ? l.eventNoSeats
      : l.eventSeatsLeft(remainingPlaces);
}

/// Whether the account may publish an event; the server checks it again.
bool canCreateEvent(UserOutput? user) =>
    user?.accountType == UserOutputAccountType.student ||
    user?.accountType == UserOutputAccountType.employee;
