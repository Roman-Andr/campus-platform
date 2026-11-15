import 'package:clock/clock.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';

/// The kind of a listing where the author asks the community for help
/// (ТЗ п. 5.1.1, модуль 4, п. 11).
const helpKind = 'help';

/// Whether [listing] is a help request rather than a giveaway or a notice.
bool isHelpRequest(ListingOutput listing) => listing.kind == helpKind;

/// Why a relevance deadline is not acceptable.
enum HelpDeadlineIssue { past, beyondLifetime }

/// The problem of [until] as a relevance deadline; null when it is valid.
///
/// The request must stay relevant in the future and must not outlive the
/// listing itself (ТЗ п. 5.1.1, модуль 4, п. 11).
HelpDeadlineIssue? helpDeadlineIssue(
  DateTime until, {
  required Duration lifetime,
  DateTime? now,
}) {
  final at = now ?? clock.now();
  if (!until.isAfter(at)) return HelpDeadlineIssue.past;
  if (until.isAfter(at.add(lifetime))) return HelpDeadlineIssue.beyondLifetime;
  return null;
}

/// A localized explanation of [issue] for the deadline field.
String helpDeadlineError(
  AppLocalizations l,
  HelpDeadlineIssue issue, {
  required int lifetimeDays,
}) => switch (issue) {
  HelpDeadlineIssue.past => l.helpDeadlinePast,
  HelpDeadlineIssue.beyondLifetime => l.helpDeadlineTooLate(lifetimeDays),
};

/// Whether [userId] may apply to [listing]; [mine] is their participation.
///
/// The author never responds to their own request, and one account keeps at
/// most one active application. A busy request has an executor, but an
/// application may be sent only while the request is active.
bool helpCanRespond(
  ListingOutput listing,
  String? userId,
  Iterable<InteractionOutput> mine,
) {
  if (userId == null || !isHelpRequest(listing)) return false;
  if (listing.status != ListingStatus.active) return false;
  if (listing.authorId == userId) return false;
  return !mine.any(
    (item) =>
        item.status == InteractionStatus.pending ||
        item.status == InteractionStatus.accepted,
  );
}

/// Whether the application of [item] waits in the reserve while another
/// respondent is already the executor.
bool helpIsReserve(ListingOutput listing, InteractionOutput item) =>
    isHelpRequest(listing) &&
    listing.status == ListingStatus.busy &&
    item.status == InteractionStatus.pending;

/// Whether [item] is the selected executor of the request.
bool helpIsExecutor(InteractionOutput item) =>
    item.status == InteractionStatus.accepted && item.executor;

/// A message for a failed help request action (Problem Details).
String helpFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.helpDeadlineInvalid),
      ) =>
        l.helpDeadlineInvalid,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.listingConflict),
      ) =>
        l.helpConflict,
      ProblemFailure(status: 403) => l.helpForbidden,
      ProblemFailure(status: 404) => l.listingUnavailable,
      _ => apiFailureMessage(l, error),
    };
