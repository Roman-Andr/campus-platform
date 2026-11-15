import '../../../core/api/api_client.dart';
import '../../listings/domain/loan.dart' as loan;

/// Kinds of interactions that are completed by meeting the other participant.
///
/// It mirrors the server rule: events, group purchases and publications use
/// other workflows, and a loan has its own handover and return actions
/// (ТЗ п. 5.1.1, модуль 5, пункт 1).
const qrCompletionKinds = {'giveaway', 'exchange', 'skill', 'help'};

/// The action a QR code confirms.
enum QrAction {
  /// The final confirmation of a meeting for a kind without stages.
  completion,

  /// The handover of a lent item: the owner shows, the borrower scans.
  loanHandover,

  /// The return of a lent item: the borrower shows, the owner scans.
  loanReturn,
}

/// Whether [action] is one of the loan stages.
bool qrActionIsLoan(QrAction action) =>
    action == QrAction.loanHandover || action == QrAction.loanReturn;

/// How an accepted interaction looks to the QR confirmation of [action], or
/// why it is not available.
enum QrInteractionState {
  /// The interaction may be completed by showing and scanning a code.
  available,

  /// The interaction is completed and the completion was a QR code.
  completedWithQr,

  /// The interaction is completed in another way; nothing to confirm.
  completedOtherwise,

  /// The interaction is not accepted (pending, cancelled or marked no-show).
  notAccepted,

  /// The kind or stage of the interaction has no such step.
  unavailable,
}

/// The state of [item] of a [kind] listing for the QR confirmation of
/// [action].
///
/// A loan is confirmed twice: the handover inside "accepted" and then the
/// return, which completes the interaction. The plain completion of a loan is
/// refused by the server, so the client never offers it.
QrInteractionState qrInteractionState(
  String kind,
  InteractionOutput item, {
  QrAction action = QrAction.completion,
}) {
  if (item.status == InteractionStatus.completed) {
    return completedWithQr(item)
        ? QrInteractionState.completedWithQr
        : QrInteractionState.completedOtherwise;
  }
  if (item.status != InteractionStatus.accepted) {
    return QrInteractionState.notAccepted;
  }
  if (kind == loan.loanKind) {
    return switch (action) {
      QrAction.loanHandover =>
        item.stage == null
            ? QrInteractionState.available
            : QrInteractionState.unavailable,
      QrAction.loanReturn =>
        item.stage == loan.loanIssuedStage
            ? QrInteractionState.available
            : QrInteractionState.unavailable,
      QrAction.completion => QrInteractionState.unavailable,
    };
  }
  if (action != QrAction.completion ||
      item.stage != null ||
      !qrCompletionKinds.contains(kind)) {
    return QrInteractionState.unavailable;
  }
  return QrInteractionState.available;
}

/// Whether the interaction was completed with a QR code.
bool completedWithQr(InteractionOutput item) => switch (item.completionMethod) {
  InteractionOutputCompletionMethodCompletionMethod(
    value: CompletionMethodKnown(value: CompletionMethodValue.qr),
  ) =>
    true,
  _ => false,
};
