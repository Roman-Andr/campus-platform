import '../../../core/api/api_failure.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/api/generated/campus_api.dart';
import '../../../core/l10n/l10n.dart';

/// A message for the user about a failed sign-in request.
///
/// Sign-in problems get their own texts; the rest fall back to
/// [apiFailureMessage].
String authFailureMessage(AppLocalizations l10n, Object error) {
  final failure = ApiFailure.from(error);
  if (failure is! ProblemFailure) return apiFailureMessage(l10n, error);
  return switch (failure.code) {
    ProblemCodeKnown(value: ProblemCodeValue.emailDomainNotAllowed) =>
      l10n.authErrorDomain,
    ProblemCodeKnown(value: ProblemCodeValue.signInCodeInvalid) =>
      l10n.authErrorCodeInvalid,
    ProblemCodeKnown(value: ProblemCodeValue.signInCodeExpired) =>
      l10n.authErrorCodeExpired,
    ProblemCodeKnown(value: ProblemCodeValue.signInCodeAttemptsExceeded) =>
      l10n.authErrorAttemptsExceeded,
    ProblemCodeKnown(value: ProblemCodeValue.rateLimited)
        when failure.retryAfter != null =>
      l10n.authErrorRateLimitedFor(formatWait(l10n, failure.retryAfter!)),
    _ => apiFailureMessage(l10n, error),
  };
}

/// A wait as the user reads it: seconds under a minute, else whole
/// minutes rounded up.
String formatWait(AppLocalizations l10n, Duration wait) {
  final seconds = wait.inSeconds;
  if (seconds < 60) return l10n.waitSeconds(seconds < 1 ? 1 : seconds);
  return l10n.waitMinutes((seconds + 59) ~/ 60);
}

/// Whether [error] means the address has no account and the names are
/// needed to create one.
bool isRegistrationRequired(Object error) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.registrationRequired),
  ) =>
    true,
  _ => false,
};
