import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../application/exchange.dart';
import '../application/listings.dart';
import 'interaction_widgets.dart';
import 'meeting_screen.dart';

/// A mutation of an exchange offer that keeps the card visible and explains
/// a failure locally.
class ExchangeAction extends ConsumerStatefulWidget {
  const ExchangeAction({
    required this.label,
    required this.run,
    this.buttonKey,
    this.filled = true,
    this.after,
    super.key,
  });

  final String label;
  final Future<void> Function() run;
  final Key? buttonKey;
  final bool filled;
  final VoidCallback? after;

  @override
  ConsumerState<ExchangeAction> createState() => _ExchangeActionState();
}

class _ExchangeActionState extends ConsumerState<ExchangeAction> {
  bool busy = false;
  String? error;

  Future<void> _run() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.run();
      if (!mounted) return;
      refreshListings(ref);
      widget.after?.call();
    } on Object catch (e) {
      if (mounted) {
        setState(() => error = exchangeFailureMessage(context.l10n, e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = busy ? null : _run;
    final label = Text(widget.label);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null) Text(error!, key: const Key('exchange-error')),
        if (widget.filled)
          FilledButton(
            key: widget.buttonKey,
            onPressed: onPressed,
            child: label,
          )
        else
          TextButton(key: widget.buttonKey, onPressed: onPressed, child: label),
      ],
    );
  }
}

/// The participant side of an exchange listing: the item they already bring
/// with its status, or the form that offers one.
class ExchangeParticipation extends ConsumerWidget {
  const ExchangeParticipation({required this.listing, super.key});

  final ListingOutput listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final own = ref.watch(exchangeOffersProvider(listing.id));
    return own.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Column(
        children: [
          Text(exchangeFailureMessage(l, e)),
          TextButton(
            onPressed: () => ref.invalidate(exchangeOffersProvider(listing.id)),
            child: Text(l.errorRetry),
          ),
        ],
      ),
      data: (items) {
        final offer = latestExchangeOffer(items);
        final canOffer = listing.status == ListingStatus.active;
        if (offer == null) {
          return canOffer
              ? ExchangeOfferForm(listing: listing)
              : Text(l.listingBusy);
        }
        final active =
            offer.status == InteractionStatus.pending ||
            offer.status == InteractionStatus.accepted;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ExchangeOfferCard(
              offer: offer,
              timezone: listing.cityTimezone,
              city: listing.cityTimezone,
              mine: true,
              action: active
                  ? ExchangeAction(
                      label: l.reservationCancel,
                      filled: false,
                      buttonKey: Key('exchange-offer-cancel-${offer.id}'),
                      run: () => ref
                          .read(campusApiProvider)
                          .listings
                          .transitionInteraction(
                            listingId: offer.listingId,
                            interactionId: offer.id,
                            body: const TransitionInput(
                              status: InteractionStatus.cancelled,
                            ),
                          ),
                    )
                  : null,
            ),
            // A rejected or withdrawn offer stays visible; while the listing
            // is still active the participant may offer another item.
            if (!active && canOffer) ExchangeOfferForm(listing: listing),
          ],
        );
      },
    );
  }
}

/// One offer with its status, the reservation countdown and a timeline link.
class _ExchangeOfferCard extends StatelessWidget {
  const _ExchangeOfferCard({
    required this.offer,
    required this.timezone,
    required this.city,
    this.mine = false,
    this.action,
  });

  final InteractionOutput offer;
  final String timezone;
  final String city;
  final bool mine;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final description = offer.offerDescription;
    final text = mine
        ? (description == null
              ? l.exchangeOfferTitle
              : l.exchangeOfferMine(description))
        : (description == null
              ? l.exchangeOfferTitle
              : l.exchangeOfferItem(description));
    return Card(
      key: Key('exchange-offer-${offer.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                offer.participantName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            Text(
              text,
              key: mine ? Key('exchange-offer-mine-${offer.id}') : null,
            ),
            InteractionStatusText(item: offer),
            MeetingSummary(item: offer, timezone: timezone, city: city),
            TimelineButton(item: offer),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// The form a participant fills to offer their own item; the author later
/// chooses one offer.
class ExchangeOfferForm extends ConsumerStatefulWidget {
  const ExchangeOfferForm({required this.listing, super.key});

  final ListingOutput listing;

  @override
  ConsumerState<ExchangeOfferForm> createState() => _ExchangeOfferFormState();
}

class _ExchangeOfferFormState extends ConsumerState<ExchangeOfferForm> {
  final description = TextEditingController();
  bool busy = false;
  String? fieldError;
  String? error;

  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = context.l10n;
    final fieldError = exchangeOfferError(l, description.text);
    setState(() {
      this.fieldError = fieldError;
      error = null;
    });
    if (fieldError != null) return;
    setState(() => busy = true);
    try {
      await ref
          .read(campusApiProvider)
          .listings
          .offerExchange(
            listingId: widget.listing.id,
            body: ExchangeOfferInput(description: description.text.trim()),
          );
      if (!mounted) return;
      description.clear();
      refreshListings(ref);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.exchangeOfferSent)));
    } on Object catch (e) {
      if (mounted) setState(() => error = exchangeFailureMessage(l, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.exchangeOfferFormTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextField(
          key: const Key('exchange-offer-description'),
          controller: description,
          minLines: 2,
          maxLines: null,
          decoration: InputDecoration(
            labelText: l.exchangeOfferDescriptionLabel,
          ),
          onChanged: (_) {
            if (fieldError != null) setState(() => fieldError = null);
          },
        ),
        if (fieldError != null)
          Text(
            fieldError!,
            key: const Key('exchange-offer-field-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (error != null) Text(error!, key: const Key('exchange-offer-error')),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('exchange-offer-send'),
          onPressed: busy ? null : _send,
          child: Text(l.exchangeOfferSend),
        ),
      ],
    );
  }
}

/// The author's view of every offer: the chosen one is accepted, the others
/// are rejected by the server.
class ExchangeOffersList extends ConsumerWidget {
  const ExchangeOffersList({required this.listing, super.key});

  final ListingOutput listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final offers = ref.watch(exchangeOffersProvider(listing.id));
    return offers.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Column(
        children: [
          Text(exchangeFailureMessage(l, e)),
          TextButton(
            onPressed: () => ref.invalidate(exchangeOffersProvider(listing.id)),
            child: Text(l.errorRetry),
          ),
        ],
      ),
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.exchangeOfferTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (items.isEmpty) Text(l.exchangeOfferListEmpty),
          for (final offer in items)
            _ExchangeOfferCard(
              offer: offer,
              timezone: listing.cityTimezone,
              city: listing.cityTimezone,
              action: offer.status == InteractionStatus.pending
                  ? ExchangeAction(
                      label: l.exchangeOfferAccept,
                      buttonKey: Key('exchange-accept-${offer.id}'),
                      after: () => ScaffoldMessenger.maybeOf(context)
                          ?.showSnackBar(
                            SnackBar(content: Text(l.exchangeOfferAccepted)),
                          ),
                      run: () => ref
                          .read(campusApiProvider)
                          .listings
                          .transitionInteraction(
                            listingId: listing.id,
                            interactionId: offer.id,
                            body: const TransitionInput(
                              status: InteractionStatus.accepted,
                            ),
                          ),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
