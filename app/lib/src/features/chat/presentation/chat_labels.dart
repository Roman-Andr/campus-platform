import '../../../core/api/api_failure.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/api/generated/campus_api.dart';
import '../../../core/l10n/l10n.dart';
import '../domain/chat.dart';

/// A message for a failed chat request, with texts from the localization.
///
/// Chat-specific Problem Details explain the rules of the module (a dialog
/// that is not available, an alumni creating a new one, a conflicting client
/// UUID); everything else falls back to the shared API messages.
String chatFailureMessage(
  AppLocalizations l10n,
  Object error, {
  bool alumni = false,
}) {
  final failure = ApiFailure.from(error);
  if (failure is ProblemFailure) {
    return switch (failure.code) {
      ProblemCodeKnown(value: ProblemCodeValue.chatNotFound) =>
        l10n.chatNotFound,
      ProblemCodeKnown(value: ProblemCodeValue.chatForbidden) =>
        alumni ? l10n.chatForbiddenAlumni : l10n.chatUnavailable,
      ProblemCodeKnown(value: ProblemCodeValue.chatMessageConflict) =>
        l10n.chatFailureConflict,
      ProblemCodeKnown(value: ProblemCodeValue.chatMessageInvalid) =>
        l10n.chatFailureInvalid,
      ProblemCodeKnown(value: ProblemCodeValue.chatRateLimited) =>
        l10n.chatFailureRateLimited,
      ProblemCodeKnown(value: ProblemCodeValue.chatLinkInvalid) =>
        l10n.chatFailureInvalid,
      ProblemCodeKnown(value: ProblemCodeValue.chatSelf) =>
        l10n.chatFailureInvalid,
      _ => apiFailureMessage(l10n, error),
    };
  }
  return apiFailureMessage(l10n, error);
}

/// A message for a failed chat search.
String chatSearchFailureMessage(AppLocalizations l10n, Object error) {
  final failure = ApiFailure.from(error);
  if (failure is NetworkFailure) return l10n.chatSearchNetwork;
  if (failure is ProblemFailure &&
      failure.code == ProblemCode.chatSearchInvalid) {
    return l10n.chatSearchTooLong;
  }
  return l10n.chatSearchFailed;
}

/// A message for an outbox row that has not been delivered.
String outgoingFailureMessage(
  AppLocalizations l10n,
  OutgoingChatFailure? failure,
) => switch (failure) {
  null => l10n.chatMessageWaiting,
  OutgoingChatFailure.network => l10n.chatFailureNetwork,
  OutgoingChatFailure.rateLimited => l10n.chatFailureRateLimited,
  OutgoingChatFailure.forbidden => l10n.chatFailureForbidden,
  OutgoingChatFailure.notFound => l10n.chatNotFound,
  OutgoingChatFailure.conflict => l10n.chatFailureConflict,
  OutgoingChatFailure.invalid => l10n.chatFailureInvalid,
  OutgoingChatFailure.unauthorized => l10n.chatFailureUnauthorized,
  OutgoingChatFailure.server => l10n.chatFailureServer,
  OutgoingChatFailure.unexpected => l10n.chatFailureUnexpected,
};
