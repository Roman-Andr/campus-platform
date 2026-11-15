import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../domain/qr_document.dart';

/// A message for a QR code of an interaction that the showing device cannot
/// use.
String qrScanProblemMessage(AppLocalizations l, QrScanProblem problem) =>
    switch (problem) {
      QrScanProblem.malformed => l.qrScannerMalformed,
      QrScanProblem.otherInteraction => l.qrScannerWrongInteraction,
      QrScanProblem.ownCode => l.qrScannerOwnCode,
    };

/// A message for a failed preparation of a code on the showing device.
String qrPresenterFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.deviceKeyConflict),
      ) =>
        l.qrKeyConflict,
      _ => apiFailureMessage(l, error),
    };

/// A message for a rejected scan.
///
/// Every refusal of the server has its own explanation: an expired code, a
/// code of a revoked key and a reused code need different actions from the
/// participants. Network failures never look like a confirmation.
String qrScanFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.qrExpired ||
              ProblemCodeValue.qrConfirmationConflict,
        ),
      ) =>
        l.qrScannerExpired,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.qrIssuedInFuture ||
              ProblemCodeValue.qrNotYetValid,
        ),
      ) =>
        l.qrScannerNotYetValid,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.qrBeforeAcceptance),
      ) =>
        l.qrScannerBeforeAcceptance,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.qrKeyInvalid),
      ) =>
        l.qrScannerUnknownKey,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.qrNonceReused ||
              ProblemCodeValue.qrAlreadyConfirmed ||
              ProblemCodeValue.qrAlreadyCompleted,
        ),
      ) =>
        l.qrScannerUsed,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.qrPayloadInvalid ||
              ProblemCodeValue.qrSignatureInvalid,
        ),
      ) =>
        l.qrScannerMalformed,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.qrNotParticipant),
      ) =>
        l.qrScannerNotParticipant,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.qrSameParticipant),
      ) =>
        l.qrScannerSameParticipant,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.qrNotAccepted),
      ) =>
        l.qrScannerNotAccepted,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.qrUnavailable),
      ) =>
        l.qrScannerUnavailable,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.qrStageUnavailable),
      ) =>
        l.qrScannerStageUnavailable,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.qrAfterNoShow),
      ) =>
        l.qrScannerAfterNoShow,
      _ => apiFailureMessage(l, error),
    };
