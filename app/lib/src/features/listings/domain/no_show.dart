import 'package:clock/clock.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import 'feed.dart' show FeedKind;

/// Kinds of listings whose personal meeting is judged by the no-show rules.
///
/// An event is judged by its registered participants instead, and a
/// publication or a purchase has no meeting at all.
const personalNoShowKinds = {
  FeedKind.giveaway,
  FeedKind.exchange,
  FeedKind.skill,
  FeedKind.help,
};

/// Whether the no-show rules apply to interactions of [kind].
bool noShowKindSupported(String kind) =>
    personalNoShowKinds.contains(FeedKind.fromApi(kind));

/// The agreed meeting time of an interaction, if one is scheduled.
DateTime? noShowMeetingAt(InteractionOutput item) => switch (item.meeting) {
  final MeetingOutput meeting => meeting.scheduledAt,
  _ => null,
};

/// Whether the no-show action may be offered for [item] of [kind].
///
/// Only an accepted interaction with an agreed meeting can be marked, and a
/// marked "did not take place" one can still be answered with a mutual
/// allegation, so every other state keeps the action away.
bool noShowAvailable(String kind, InteractionOutput item) {
  if (!noShowKindSupported(kind)) return false;
  if (item.status == InteractionStatus.noShow) return true;
  return item.status == InteractionStatus.accepted &&
      noShowMeetingAt(item) != null;
}

/// Where the personal no-show window of an interaction is.
enum NoShowPhase { before, open, closed, unavailable }

/// The phase of the mark window, from the instants of the server.
///
/// The server accepts a mark from `mark_from` inclusive until `auto_after`
/// exclusive; the same bounds switch the form here, so the client never
/// offers a submission the server would refuse for its window.
NoShowPhase noShowPhase(NoShowOutput state, {DateTime? now}) {
  final opensAt = state.markFrom;
  final closesAt = state.autoAfter;
  if (opensAt == null || closesAt == null) return NoShowPhase.unavailable;
  final at = now ?? clock.now();
  if (at.isBefore(opensAt)) return NoShowPhase.before;
  if (!at.isBefore(closesAt)) return NoShowPhase.closed;
  return NoShowPhase.open;
}

/// Whether a moderator is deciding a mutual allegation right now.
bool noShowDisputeOpen(NoShowOutput state) =>
    state.dispute is NoShowDisputeOutput &&
    switch ((state.dispute as NoShowDisputeOutput).status) {
      DisputeStatusKnown(value: DisputeStatusValue.open) => true,
      _ => false,
    };

/// Whether the interaction was completed after a no-show, so the mark was
/// lifted by a late QR code.
///
/// The server keeps the marks as rows with `removed_at` set and resolves the
/// dispute with `late_qr`; the screen must not keep showing the stale mark.
bool noShowLiftedAfterQr(NoShowOutput state) {
  final dispute = state.dispute;
  if (dispute is NoShowDisputeOutput && dispute.resolution == 'late_qr') {
    return true;
  }
  return state.marks.isNotEmpty &&
      state.marks.every((mark) => mark.removedAt != null);
}

/// Marks that still decide the interaction first, suspended and removed ones
/// after them, in the order the server returned.
List<NoShowMarkOutput> noShowSortedMarks(NoShowOutput state) => [
  ...state.marks.where((mark) => mark.removedAt == null && !_suspended(mark)),
  ...state.marks.where(_suspended),
  ...state.marks.where((mark) => mark.removedAt != null),
];

bool _suspended(NoShowMarkOutput mark) =>
    mark.removedAt == null &&
    switch (mark.status) {
      NoShowStatusKnown(value: NoShowStatusValue.disputed) => true,
      _ => false,
    };

/// The label of how the current state was reached.
String noShowBasisName(AppLocalizations l, NoShowOutput state) =>
    switch (state.basis) {
      NoShowOutputBasisKnown(value: NoShowOutputBasisValue.unmarked) =>
        l.noShowBasisUnmarked,
      NoShowOutputBasisKnown(value: NoShowOutputBasisValue.marked) =>
        l.noShowBasisMarked,
      NoShowOutputBasisKnown(value: NoShowOutputBasisValue.automatic) =>
        l.noShowBasisAutomatic,
      NoShowOutputBasisKnown(value: NoShowOutputBasisValue.mutualDispute) =>
        l.noShowBasisMutualDispute,
      NoShowOutputBasisKnown(value: NoShowOutputBasisValue.completed) =>
        l.noShowBasisCompleted,
      _ => l.noShowBasisUnmarked,
    };

/// The label of the current state of a mark.
String noShowMarkStatusName(
  AppLocalizations l,
  NoShowMarkOutput mark,
) => switch (mark.status) {
  NoShowStatusKnown(value: NoShowStatusValue.counted) => l.noShowMarkCounted,
  NoShowStatusKnown(value: NoShowStatusValue.disputed) => l.noShowMarkDisputed,
  NoShowStatusKnown(value: NoShowStatusValue.removed) => l.noShowMarkRemoved,
  _ => l.noShowMarkCounted,
};

/// Who the mark is charged to, in the words of the viewer.
String noShowSubjectName(
  AppLocalizations l,
  NoShowMarkOutput mark, {
  required String? viewerId,
  String? otherName,
}) => mark.subjectId == viewerId
    ? l.noShowChargedYou
    : otherName ?? l.noShowOtherParticipant;

/// Who made the mark, in the words of the viewer.
String noShowReporterName(
  AppLocalizations l,
  NoShowMarkOutput mark, {
  required String? viewerId,
  String? otherName,
}) => switch (mark.reporterId) {
  null => l.noShowMarkAutomatic,
  final id when id == viewerId => l.timelineYou,
  _ => otherName ?? l.noShowOtherParticipant,
};

/// A message for a failed no-show request.
///
/// The server names the first moment a mark is allowed in the refusal of a
/// too-early request; the screen shows it in the city of the listing (#44).
/// Refusals caused by a changed state update the screen from the server.
String noShowFailureMessage(
  AppLocalizations l,
  Object error, {
  String Function(DateTime instant)? cityTime,
}) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowForbidden),
  ) =>
    l.noShowForbidden,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventNoShowForbidden),
  ) =>
    l.noShowForbidden,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowTooEarly),
    :final problem,
  ) =>
    switch (problem.availableAt) {
      final availableAt? when cityTime != null => l.noShowOpensAt(
        cityTime(availableAt),
      ),
      _ => l.noShowTooEarly,
    },
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowClosed),
  ) =>
    l.noShowClosedMessage,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowUnavailable),
  ) =>
    l.noShowUnavailable,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowStateConflict),
  ) =>
    l.noShowStateConflict,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowReasonInvalid),
  ) =>
    l.noShowReasonInvalid,
  // The item of a loan was handed over, so the rules of #286 apply: the loan
  // ends by its return or by the owner's "not returned" mark.
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.loanNoShowUnavailable),
  ) =>
    l.noShowLoanUnavailable,
  _ => apiFailureMessage(l, error),
};

/// A message for a failed event no-show request.
String eventNoShowFailureMessage(
  AppLocalizations l,
  Object error, {
  String Function(DateTime instant)? cityTime,
}) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventNoShowNotRegistered),
  ) =>
    l.eventNoShowNotRegistered,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventNoShowForbidden),
  ) =>
    l.eventNoShowForbidden,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventNoShowUnavailable),
  ) =>
    l.eventNoShowUnavailable,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventNoShowVoteClosed),
  ) =>
    l.eventNoShowVoteClosed,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventNoShowDisputeClosed),
  ) =>
    l.eventNoShowDisputeClosed,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.eventNoShowDisputeForbidden),
  ) =>
    l.eventNoShowDisputeForbidden,
  ProblemFailure(
    code: ProblemCodeKnown(
      value: ProblemCodeValue.eventNoShowDisputeUnavailable,
    ),
  ) =>
    l.eventNoShowDisputeUnavailable,
  _ => apiFailureMessage(l, error),
};

/// Where the event vote window is.
enum EventNoShowPhase { before, open, closed, unavailable }

/// The phase of the vote window, from the instants of the server.
EventNoShowPhase eventNoShowPhase(EventNoShowOutput state, {DateTime? now}) {
  final opensAt = state.voteOpensAt;
  final closesAt = state.voteClosesAt;
  if (opensAt == null || closesAt == null) {
    return EventNoShowPhase.unavailable;
  }
  final at = now ?? clock.now();
  if (at.isBefore(opensAt)) return EventNoShowPhase.before;
  if (at.isAfter(closesAt)) return EventNoShowPhase.closed;
  return EventNoShowPhase.open;
}

/// Whether the organiser's no-show is decided by a moderator right now.
bool eventNoShowDisputeOpen(EventNoShowOutput state) =>
    state.dispute is NoShowDisputeOutput &&
    switch ((state.dispute as NoShowDisputeOutput).status) {
      DisputeStatusKnown(value: DisputeStatusValue.open) => true,
      _ => false,
    };

/// The city clock of a listing, as [formatCityTime] expects it.
String Function(DateTime instant) noShowCityTime(
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
