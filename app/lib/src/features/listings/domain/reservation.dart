import 'package:clock/clock.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';

/// Whether [item] is an accepted item reservation that still runs on its own
/// deadline: the item is held until the participants schedule a meeting.
bool reservationIsOpen(InteractionOutput item) =>
    item.status == InteractionStatus.accepted &&
    item.reservationDueAt != null &&
    !_hasScheduledMeeting(item);

/// Whether a scheduled meeting has extended the hold of [item].
bool reservationEndsAtMeeting(InteractionOutput item) =>
    item.status == InteractionStatus.accepted &&
    item.reservationDueAt != null &&
    _hasScheduledMeeting(item);

/// The meeting is a sealed union of a meeting and null in the generated
/// client, so its time is read through a pattern.
bool _hasScheduledMeeting(InteractionOutput item) => switch (item.meeting) {
  final MeetingOutput meeting => meeting.scheduledAt != null,
  _ => false,
};

/// The time left until the hold of [item] ends; never negative.
///
/// A device clock ahead of the server sees no time left, exactly like the
/// server itself treats the expired hold.
Duration reservationLeft(InteractionOutput item, {DateTime? now}) {
  final due = item.reservationDueAt;
  if (due == null) return Duration.zero;
  final left = due.difference(now ?? clock.now());
  return left.isNegative ? Duration.zero : left;
}

/// The hold time in hours and minutes, with its own wording for the first
/// minute and for an already finished hold. Hours are never split into days,
/// so no plural form of a day count is needed.
String reservationTimeLeft(AppLocalizations l, Duration left) {
  if (left <= Duration.zero) return l.reservationTimeLeftEnded;
  if (left.inMinutes < 1) return l.reservationTimeLeftSoon;
  if (left.inHours < 1) return l.reservationTimeLeftMinutes(left.inMinutes);
  return l.reservationTimeLeft(left.inHours, left.inMinutes.remainder(60));
}
