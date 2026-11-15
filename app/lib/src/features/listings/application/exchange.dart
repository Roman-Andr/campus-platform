import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';

/// The offer the participant still waits on: a pending or accepted one.
InteractionOutput? activeExchangeOffer(Iterable<InteractionOutput> offers) {
  for (final offer in offers) {
    if (offer.status == InteractionStatus.pending ||
        offer.status == InteractionStatus.accepted) {
      return offer;
    }
  }
  return null;
}

/// The last offer of an exchange listing as the server ordered them by
/// creation time. A participant sees their own offers, the author all of
/// them, so the last row is the latest answer to show.
InteractionOutput? latestExchangeOffer(Iterable<InteractionOutput> offers) {
  InteractionOutput? latest;
  for (final offer in offers) {
    latest = offer;
  }
  return latest;
}

/// Rejects a missing offer description; the server checks its length.
String? exchangeOfferError(AppLocalizations l, String? description) =>
    description == null || description.trim().isEmpty
    ? l.exchangeOfferRequired
    : null;

/// Explains the exchange conflicts of the server (Problem Details).
String exchangeFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.exchangeOfferDuplicate),
      ) =>
        l.exchangeOfferDuplicate,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.exchangeOfferInvalid),
      ) =>
        l.exchangeOfferInvalid,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.listingConflict),
      ) =>
        l.listingTransitionConflict,
      ProblemFailure(status: 404) => l.listingUnavailable,
      _ => apiFailureMessage(l, error),
    };
