import 'package:clock/clock.dart';

import '../../../core/api/api_client.dart';

/// Kind of a listing whose item is lent for an author-set period
/// (ТЗ п. 5.1.1, модуль 4, п. 9).
const loanKind = 'loan';

/// The only stage inside an accepted loan: the item was handed over.
///
/// The return itself completes the interaction, so it has no stage of its
/// own; the card shows it as a step built from the status.
const loanIssuedStage = 'issued';

/// Why the server recorded the no-show of a loan that was never returned.
const loanNotReturnedReason = 'loan_not_returned';

/// The steps of a loan on the interaction card.
enum LoanStep {
  /// The author accepted the booking; the item is still with the owner.
  accepted,

  /// The handover is confirmed; the item is with the borrower.
  issued,

  /// The return is confirmed; the interaction is completed.
  returned,

  /// The interaction ended in another way (rejected, cancelled, no-show).
  closed,
}

/// The step [item] of a loan is at.
LoanStep loanStep(InteractionOutput item) {
  if (item.status == InteractionStatus.completed) return LoanStep.returned;
  if (item.status != InteractionStatus.accepted) return LoanStep.closed;
  return item.stage == loanIssuedStage ? LoanStep.issued : LoanStep.accepted;
}

/// Whether the item is with the borrower and due back.
bool loanIsIssued(InteractionOutput item) =>
    item.status == InteractionStatus.accepted && item.stage == loanIssuedStage;

/// When the owner may first mark the item "not returned".
///
/// The wait mirrors the server's `CAMPUS_LOAN_NOT_RETURNED_AFTER` (Приложение
/// 4: three days after the return deadline); the server also names the exact
/// moment in the `available_at` extension of an early refusal, so a build with
/// another definition is corrected by the server answer.
DateTime? loanNotReturnedFrom(
  InteractionOutput item, {
  required Duration wait,
}) {
  if (!loanIsIssued(item)) return null;
  final due = item.returnDueAt;
  return due?.add(wait);
}

/// Whether the "not returned" action is open at [now].
bool loanNotReturnedOpen(
  InteractionOutput item, {
  required Duration wait,
  DateTime? now,
}) {
  final from = loanNotReturnedFrom(item, wait: wait);
  if (from == null) return false;
  return !(now ?? clock.now()).isBefore(from);
}

/// Whether the no-show of [item] is the owner's "not returned" mark.
///
/// A loan may also end as "did not take place" after a missed meeting, so the
/// status alone does not identify this mark; its reason does.
bool loanNoShowIsNotReturned(NoShowOutput state) =>
    state.marks.any((mark) => mark.reason == loanNotReturnedReason);

/// Whether [user] is the borrower of [item]; otherwise it is the owner.
bool loanIsBorrower(InteractionOutput item, String? user) =>
    user != null && user == item.participantId;
