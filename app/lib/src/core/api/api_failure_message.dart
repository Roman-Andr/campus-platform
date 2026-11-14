import '../l10n/l10n.dart';
import 'api_failure.dart';
import 'generated/campus_api.dart';

/// A message for the user about a failed request.
///
/// Texts come from the localization files: the title and detail of the
/// server, request IDs and causes are technical and never shown. Codes
/// without their own message fall back to one by HTTP status.
String apiFailureMessage(AppLocalizations l10n, Object error) =>
    switch (ApiFailure.from(error)) {
      NetworkFailure() => l10n.errorNetwork,
      CancelledFailure() || UnexpectedFailure() => l10n.errorUnexpected,
      UpdateRequiredFailure() => l10n.errorUpdateRequired,
      ProblemFailure(:final status, :final retryAfter?) when status == 429 =>
        l10n.listingRateLimitedFor(retryAfter.inSeconds),
      ProblemFailure(:final code, :final status) => switch (code) {
        ProblemCodeKnown(
          value: ProblemCodeValue.consentRequired ||
              ProblemCodeValue.consentInvalid,
        ) =>
          l10n.consentUpdateIntro,
        ProblemCodeKnown(value: ProblemCodeValue.notFound) =>
          l10n.errorNotFound,
        ProblemCodeKnown(value: ProblemCodeValue.validationFailed) =>
          l10n.errorValidation,
        ProblemCodeKnown(value: ProblemCodeValue.invalidCursor) =>
          l10n.errorListChanged,
        ProblemCodeKnown(
          value: ProblemCodeValue.rateLimited ||
              ProblemCodeValue.listingRateLimited,
        ) =>
          l10n.errorRateLimited,
        ProblemCodeKnown(value: ProblemCodeValue.listingVersionConflict) =>
          l10n.listingVersionConflict,
        ProblemCodeKnown(
          value: ProblemCodeValue.listingCategoryInvalid ||
              ProblemCodeValue.listingContentInvalid,
        ) =>
          l10n.errorValidation,
        ProblemCodeKnown(value: ProblemCodeValue.listingConflict) =>
          l10n.listingConflict,
        ProblemCodeKnown(value: ProblemCodeValue.listingForbidden) =>
          l10n.listingForbidden,
        _ when status >= 500 => l10n.errorServer,
        _ => l10n.errorRequest,
      },
    };
