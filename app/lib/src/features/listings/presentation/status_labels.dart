import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';

String interactionStatusLabel(AppLocalizations l, InteractionStatus status) =>
    switch (status) {
      InteractionStatusKnown(value: InteractionStatusValue.pending) =>
        l.reservationPending,
      InteractionStatusKnown(value: InteractionStatusValue.accepted) =>
        l.reservationAccepted,
      InteractionStatusKnown(value: InteractionStatusValue.rejected) =>
        l.reservationRejected,
      InteractionStatusKnown(value: InteractionStatusValue.cancelled) =>
        l.reservationCancelled,
      InteractionStatusKnown(value: InteractionStatusValue.completed) =>
        l.listingCompleted,
      InteractionStatusKnown(value: InteractionStatusValue.noShow) =>
        l.reservationNoShow,
      _ => l.listingStatusUnknown,
    };

String listingStatusLabel(AppLocalizations l, ListingStatus status) =>
    switch (status) {
      ListingStatusKnown(value: ListingStatusValue.active) => l.listingActive,
      ListingStatusKnown(value: ListingStatusValue.busy) => l.listingBusy,
      ListingStatusKnown(value: ListingStatusValue.expired) => l.listingExpired,
      ListingStatusKnown(value: ListingStatusValue.cancelled) =>
        l.reservationCancelled,
      ListingStatusKnown(value: ListingStatusValue.draft) => l.listingDraft,
      ListingStatusKnown(value: ListingStatusValue.completed) =>
        l.listingCompleted,
      ListingStatusKnown(value: ListingStatusValue.hidden) => l.listingHidden,
      _ => l.listingStatusUnknown,
    };

/// The reason an interaction was rejected, cancelled or closed. Free text of
/// a person is shown as written; an empty or absent reason has no label.
String? interactionReasonLabel(AppLocalizations l, String? reason) =>
    switch (reason) {
      null || '' => null,
      'listing_expired' => l.reservationRejectedExpired,
      'listing_cancelled' => l.reservationRejectedClosed,
      'author_timeout' => l.reservationRejectedTimeout,
      'another_offer_accepted' => l.exchangeOfferRejectedAnother,
      'reservation_expired' => l.reservationExpiredByDeadline,
      'listing_hidden' => l.timelineReasonHidden,
      _ => reason,
    };
