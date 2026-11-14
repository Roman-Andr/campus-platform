import '../../../core/api/api_failure.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/api/generated/campus_api.dart';
import '../../../core/l10n/l10n.dart';
import '../../auth/presentation/auth_failure_message.dart';

/// A message under the field that started changing an address.
///
/// The requested [kind] picks the text for a rejected domain: a corporate
/// address must be in a university domain, a backup one must not.
String accountEmailFailureMessage(
  AppLocalizations l10n,
  Object error, {
  AddressInputKind? kind,
}) {
  final failure = ApiFailure.from(error);
  if (failure is! ProblemFailure) return apiFailureMessage(l10n, error);
  return switch (failure.code) {
    ProblemCodeKnown(value: ProblemCodeValue.emailConflict) =>
      l10n.emailsErrorTaken,
    ProblemCodeKnown(value: ProblemCodeValue.emailKindInvalid) =>
      kind == AddressInputKind.backup
          ? l10n.emailsErrorBackupDomain
          : l10n.emailsErrorCorporateDomain,
    ProblemCodeKnown(value: ProblemCodeValue.lastCorporateEmail) =>
      l10n.emailsLastCorporateNote,
    ProblemCodeKnown(value: ProblemCodeValue.emailNotFound) =>
      l10n.errorNotFound,
    ProblemCodeKnown(value: ProblemCodeValue.signInCodeInvalid) =>
      l10n.authErrorCodeInvalid,
    ProblemCodeKnown(value: ProblemCodeValue.signInCodeExpired) =>
      l10n.authErrorCodeExpired,
    ProblemCodeKnown(value: ProblemCodeValue.signInCodeAttemptsExceeded) =>
      l10n.authErrorAttemptsExceeded,
    ProblemCodeKnown(value: ProblemCodeValue.rateLimited)
        when failure.retryAfter != null =>
      l10n.emailsErrorRateLimitedFor(formatWait(l10n, failure.retryAfter!)),
    _ => apiFailureMessage(l10n, error),
  };
}

/// Whether [error] is about the address itself and the e-mail field must
/// get the message instead of the code field.
bool isAddressRejected(Object error) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(
      value: ProblemCodeValue.emailConflict ||
          ProblemCodeValue.emailKindInvalid,
    ),
  ) =>
    true,
  _ => false,
};
