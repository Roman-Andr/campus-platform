import '../../../core/api/api_client.dart';

/// Kinds of interactions that are completed by meeting the other participant.
///
/// It mirrors the server rule: events, group purchases and publications use
/// other workflows, and a loan needs a separate return stage (ТЗ п. 5.1.1,
/// модуль 5, пункт 1).
const qrCompletionKinds = {'giveaway', 'exchange', 'skill', 'help'};

/// How an accepted interaction looks to the QR confirmation, or why it is not
/// available.
enum QrInteractionState {
  /// The interaction may be completed by showing and scanning a code.
  available,

  /// The interaction is completed and the completion was a QR code.
  completedWithQr,

  /// The interaction is completed in another way; nothing to confirm.
  completedOtherwise,

  /// The interaction is not accepted (pending, cancelled or marked no-show).
  notAccepted,

  /// The kind or stage of the interaction has no final meeting step.
  unavailable,
}

/// The state of [item] of a [kind] listing for the QR confirmation.
QrInteractionState qrInteractionState(String kind, InteractionOutput item) {
  if (item.status == InteractionStatus.completed) {
    return completedWithQr(item)
        ? QrInteractionState.completedWithQr
        : QrInteractionState.completedOtherwise;
  }
  if (item.status != InteractionStatus.accepted) {
    return QrInteractionState.notAccepted;
  }
  if (item.stage != null || !qrCompletionKinds.contains(kind)) {
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
