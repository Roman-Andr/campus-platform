import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';

part 'waitlist.g.dart';

// Expected API errors must reach the UI at once: the queue state changes
// through deliberate actions, so a silent repeat would only hide a conflict.
Duration? waitlistRetry(int retryCount, Object error) => null;

/// How often the own queue entry is re-read while the user waits: the server
/// sends no event when somebody ahead leaves, so the position is polled.
const waitlistPollInterval = Duration(seconds: 30);

/// Statuses of an entry that still takes part in a queue.
bool waitlistIsActive(WaitlistStatus status) => switch (status) {
  WaitlistStatusKnown(value: WaitlistStatusValue.waiting) ||
  WaitlistStatusKnown(value: WaitlistStatusValue.offered) => true,
  _ => false,
};

/// Time left until the place offer of [entry] expires.
///
/// The expiry instant is the one the server scheduled the offer with, so the
/// countdown does not depend on how long the card has been on screen.
Duration offerRemaining(WaitlistEntryOutput entry, DateTime now) {
  final expires = entry.offerExpiresAt;
  if (entry.status != WaitlistStatus.offered || expires == null) {
    return Duration.zero;
  }
  final left = expires.difference(now);
  return left.isNegative ? Duration.zero : left;
}

/// Countdown text: `H:MM:SS`, or `MM:SS` within the last hour.
String formatOfferCountdown(Duration remaining) {
  final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
  final hours = seconds ~/ Duration.secondsPerHour;
  final minutes = (seconds % Duration.secondsPerHour) ~/ 60;
  final tail = '${_two(minutes)}:${_two(seconds % 60)}';
  return hours > 0 ? '$hours:$tail' : tail;
}

String _two(int value) => value.toString().padLeft(2, '0');

/// The user's own active entry in the queue of [listingId]; null outside it.
///
/// A 404 is the normal answer when the user is not queued, not an error.
@Riverpod(retry: waitlistRetry)
Future<WaitlistEntryOutput?> myWaitlistEntry(Ref ref, String listingId) async {
  final WaitlistEntryOutput entry;
  try {
    entry = await ref
        .watch(campusApiProvider)
        .listings
        .myWaitlistEntry(listingId: listingId);
  } on Object catch (error) {
    if (ApiFailure.from(error) case ProblemFailure(status: 404)) return null;
    rethrow;
  }
  // A waiting entry is refreshed until it becomes an offer or the user acts.
  if (entry.status == WaitlistStatus.waiting) {
    final timer = Timer(waitlistPollInterval, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return entry;
}
