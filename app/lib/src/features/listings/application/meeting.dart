import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import 'listings.dart';

/// The meeting of an interaction; null until someone proposes one.
MeetingOutput? meetingOf(InteractionOutput item) => switch (item.meeting) {
  final MeetingOutput meeting => meeting,
  _ => null,
};

/// Whether the meeting has a proposal that has not been accepted yet.
bool meetingHasProposal(MeetingOutput meeting) => meeting.proposedAt != null;

/// Whether [userId] is the one who made the pending proposal.
bool meetingProposalIsMine(MeetingOutput meeting, String? userId) =>
    userId != null && meeting.proposedById == userId;

/// The time to start the proposal form with: a future pending proposal or
/// effective meeting, otherwise a day from now.
DateTime meetingInitialTime(MeetingOutput? meeting, {DateTime? now}) {
  final at = now ?? clock.now();
  for (final candidate in [meeting?.proposedAt, meeting?.scheduledAt]) {
    if (candidate != null && candidate.isAfter(at)) return candidate;
  }
  return at.add(const Duration(days: 1));
}

/// Rejects a missing or past proposal time.
String? meetingTimeError(AppLocalizations l, DateTime? time, {DateTime? now}) {
  if (time == null) return l.meetingTimeRequired;
  if (!time.isAfter(now ?? clock.now())) return l.meetingTimePast;
  return null;
}

/// Rejects a missing or blank proposal place.
String? meetingPlaceError(AppLocalizations l, String? place) =>
    place == null || place.trim().isEmpty ? l.meetingPlaceRequired : null;

/// Whether a failed request means that the proposal was replaced meanwhile.
bool meetingIsStale(Object error) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.meetingStale),
  ) =>
    true,
  _ => false,
};

/// A message for a failed meeting request; a stale proposal has its own.
String meetingFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.meetingStale),
      ) =>
        l.meetingStale,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.meetingStateConflict),
      ) =>
        l.meetingStateConflict,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.meetingTimeInvalid),
      ) =>
        l.meetingTimeInvalid,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.meetingPlaceInvalid),
      ) =>
        l.meetingPlaceInvalid,
      _ => apiFailureMessage(l, error),
    };

/// The interaction is absent or private to the user.
class MeetingUnavailable implements Exception {
  const MeetingUnavailable();
}

/// Loads one interaction for the meeting screen: the user's own
/// participations first, then the incoming interactions of a listing the
/// user authors. A direct link to a foreign interaction fails.
final meetingInteractionProvider = FutureProvider.autoDispose
    .family<InteractionOutput, (String, String)>((ref, ids) async {
      final api = ref.watch(campusApiProvider).listings;
      String? cursor;
      do {
        final page = await api.myReservations(cursor: cursor);
        for (final item in page.items) {
          if (item.id == ids.$2 && item.listingId == ids.$1) {
            return asInteraction(item);
          }
        }
        cursor = page.nextPage;
      } while (cursor != null);
      try {
        cursor = null;
        do {
          final page = await api.listingInteractions(
            listingId: ids.$1,
            cursor: cursor,
          );
          for (final item in page.items) {
            if (item.id == ids.$2) return item;
          }
          cursor = page.nextPage;
        } while (cursor != null);
      } on Object catch (error) {
        if (ApiFailure.from(error) case ProblemFailure(status: 403)) {
          throw const MeetingUnavailable();
        }
        rethrow;
      }
      throw const MeetingUnavailable();
    }, retry: listingRetry);
