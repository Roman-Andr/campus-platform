import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../application/listings.dart';
import '../application/my_listings.dart';
import '../application/waitlist.dart';
import 'cancellation.dart';

/// Explains the queue and offer conflicts of the server (Problem Details).
String waitlistFailureMessage(
  AppLocalizations l,
  Object error,
) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingWaitlistFree),
  ) =>
    l.waitlistFree,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingWaitlistDuplicate),
  ) =>
    l.waitlistDuplicate,
  ProblemFailure(
    code: ProblemCodeKnown(
      value: ProblemCodeValue.listingWaitlistParticipating,
    ),
  ) =>
    l.waitlistParticipating,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingWaitlistUnavailable),
  ) =>
    l.waitlistUnavailable,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingOfferPending),
  ) =>
    l.waitlistOfferPending,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingOfferMissing),
  ) =>
    l.waitlistOfferMissing,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingOfferExpired),
  ) =>
    l.waitlistOfferExpired,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingConflict),
  ) =>
    l.listingTransitionConflict,
  _ => apiFailureMessage(l, error),
};

/// A queue action that keeps the card visible and explains a failure locally.
class WaitlistAction extends ConsumerStatefulWidget {
  const WaitlistAction({
    required this.label,
    required this.run,
    this.buttonKey,
    this.filled = true,
    this.after,
    this.failureMessage,
    super.key,
  });

  final String label;
  final Future<void> Function() run;
  final Key? buttonKey;
  final bool filled;
  final VoidCallback? after;
  final String Function(AppLocalizations, Object)? failureMessage;

  @override
  ConsumerState<WaitlistAction> createState() => _WaitlistActionState();
}

class _WaitlistActionState extends ConsumerState<WaitlistAction> {
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
    } on CancellationDismissed {
      // The user kept the interaction.
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => error = (widget.failureMessage ?? waitlistFailureMessage)(
            context.l10n,
            e,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = busy ? null : _run;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null) Text(error!, key: const Key('waitlist-error')),
        if (widget.filled)
          FilledButton(
            key: widget.buttonKey,
            onPressed: onPressed,
            child: Text(widget.label),
          )
        else
          TextButton(
            key: widget.buttonKey,
            onPressed: onPressed,
            child: Text(widget.label),
          ),
      ],
    );
  }
}

/// The actions under a busy listing: join its queue, or leave it and show the
/// own place. The offer replaces them for the participant who has one.
class ListingWaitlistSection extends ConsumerWidget {
  const ListingWaitlistSection({required this.listing, super.key});

  final ListingOutput listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final entries = ref.watch(myWaitlistEntryProvider(listing.id));
    return entries.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(waitlistFailureMessage(l, e)),
          TextButton(
            onPressed: () =>
                ref.invalidate(myWaitlistEntryProvider(listing.id)),
            child: Text(l.errorRetry),
          ),
        ],
      ),
      data: (entry) {
        if (entry != null) {
          return switch (entry.status) {
            WaitlistStatusKnown(value: WaitlistStatusValue.offered) =>
              PlaceOfferCard(entry: entry, title: listing.title),
            WaitlistStatusKnown(value: WaitlistStatusValue.waiting) =>
              WaitlistQueueControls(entry: entry),
            _ => const SizedBox.shrink(),
          };
        }
        // A queue exists only while the listing is occupied: a free place is
        // reserved directly, never queued for.
        return switch (listing.status) {
          ListingStatus.active => WaitlistAction(
            label: l.listingReserve,
            failureMessage: apiFailureMessage,
            run: () async {
              await ref
                  .read(campusApiProvider)
                  .listings
                  .reserveGiveaway(listingId: listing.id);
            },
            after: () => context.push('/my-listings'),
          ),
          ListingStatus.busy => WaitlistAction(
            label: l.waitlistJoin,
            buttonKey: Key('waitlist-join-${listing.id}'),
            run: () async {
              await ref
                  .read(campusApiProvider)
                  .listings
                  .joinListingWaitlist(listingId: listing.id);
            },
          ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}

/// The own place in the queue, its leave action and an explicit refresh.
///
/// The listing card and "Мои" both show it; the position changes when somebody
/// ahead leaves, and the server sends no event for that.
class WaitlistQueueControls extends ConsumerWidget {
  const WaitlistQueueControls({
    required this.entry,
    this.showPosition = true,
    super.key,
  });

  final WaitlistEntryOutput entry;
  final bool showPosition;

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(myWaitlistEntryProvider(entry.listingId))
      ..invalidate(myWaitlistProvider)
      ..invalidate(listingProvider(entry.listingId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final position = entry.position;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPosition && position != null)
          Text(
            l.waitlistPosition(position),
            key: Key('waitlist-position-${entry.listingId}'),
          ),
        Wrap(
          spacing: 8,
          children: [
            WaitlistAction(
              label: l.waitlistLeave,
              buttonKey: Key('waitlist-leave-${entry.listingId}'),
              filled: false,
              run: () async {
                await ref
                    .read(campusApiProvider)
                    .listings
                    .leaveListingWaitlist(listingId: entry.listingId);
              },
            ),
            TextButton(
              key: Key('waitlist-refresh-${entry.listingId}'),
              onPressed: () => _refresh(ref),
              child: Text(l.waitlistRefresh),
            ),
          ],
        ),
      ],
    );
  }
}

/// The place offered to the user: the server timer, confirm and decline.
///
/// The countdown is measured from the expiry instant the server set, so it
/// continues correctly whenever the card is rebuilt, and the confirm button is
/// removed as soon as that instant passes.
class PlaceOfferCard extends ConsumerStatefulWidget {
  const PlaceOfferCard({
    required this.entry,
    this.title,
    this.now,
    this.onAccepted,
    this.onDeclined,
    super.key,
  });

  final WaitlistEntryOutput entry;

  /// Listing title when the caller already has it.
  final String? title;

  /// Current instant; tests pass a controllable clock.
  final DateTime Function()? now;

  final VoidCallback? onAccepted;
  final VoidCallback? onDeclined;

  @override
  ConsumerState<PlaceOfferCard> createState() => _PlaceOfferCardState();
}

class _PlaceOfferCardState extends ConsumerState<PlaceOfferCard> {
  Timer? ticker;
  bool busy = false;
  String? error;

  DateTime get _now => (widget.now ?? clock.now)();

  Duration get _remaining => offerRemaining(widget.entry, _now);

  bool get _expired => _remaining == Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(PlaceOfferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.status != widget.entry.status ||
        oldWidget.entry.offerExpiresAt != widget.entry.offerExpiresAt) {
      _startTicker();
    }
  }

  void _startTicker() {
    ticker?.cancel();
    if (_expired) return;
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_expired) ticker?.cancel();
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref
      ..invalidate(myWaitlistEntryProvider(widget.entry.listingId))
      ..invalidate(myWaitlistProvider)
      ..invalidate(listingProvider(widget.entry.listingId));
  }

  Future<void> _run(
    Future<void> Function() action,
    String doneMessage,
    VoidCallback? done,
  ) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (!mounted) return;
      refreshListings(ref);
      if (done != null) {
        done();
      } else {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(doneMessage)));
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => error = waitlistFailureMessage(context.l10n, e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final position = widget.entry.position;
    return Card(
      key: Key('place-offer-${widget.entry.listingId}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.offerOffered,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (widget.title case final title?) Text(title),
            if (position != null) Text(l.waitlistPosition(position)),
            if (_expired)
              Text(
                l.offerExpired,
                key: Key('offer-expired-${widget.entry.listingId}'),
              )
            else
              Text(
                l.offerCountdown(formatOfferCountdown(_remaining)),
                key: Key('offer-countdown-${widget.entry.listingId}'),
              ),
            if (error != null)
              Text(
                error!,
                key: Key('offer-error-${widget.entry.listingId}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            if (_expired)
              TextButton(
                key: Key('offer-refresh-${widget.entry.listingId}'),
                onPressed: _refresh,
                child: Text(l.waitlistRefresh),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: Key('offer-accept-${widget.entry.listingId}'),
                    onPressed: busy
                        ? null
                        : () => _run(
                            () async {
                              await ref
                                  .read(campusApiProvider)
                                  .listings
                                  .acceptPlaceOffer(
                                    listingId: widget.entry.listingId,
                                  );
                            },
                            l.offerConfirmed,
                            widget.onAccepted,
                          ),
                    child: Text(l.offerAccept),
                  ),
                  TextButton(
                    key: Key('offer-decline-${widget.entry.listingId}'),
                    onPressed: busy
                        ? null
                        : () => _run(
                            () async {
                              await ref
                                  .read(campusApiProvider)
                                  .listings
                                  .declinePlaceOffer(
                                    listingId: widget.entry.listingId,
                                  );
                            },
                            l.offerDeclined,
                            widget.onDeclined,
                          ),
                    child: Text(l.offerDecline),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// One active queue row of "Мои": its listing, place and actions; an offer
/// keeps the countdown card instead.
class WaitlistEntryTile extends ConsumerWidget {
  const WaitlistEntryTile({required this.entry, super.key});

  final WaitlistEntryOutput entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final listing = ref.watch(listingProvider(entry.listingId));
    final title = listing.value?.title ?? l.listingDetails;
    if (entry.status == WaitlistStatus.offered) {
      return PlaceOfferCard(entry: entry, title: title);
    }
    final position = entry.position;
    return Column(
      children: [
        ListTile(
          key: Key('waitlist-row-${entry.id}'),
          title: Text(title),
          subtitle: Text(
            position == null ? l.waitlistWaiting : l.waitlistPosition(position),
          ),
          onTap: () => context.push('/listings/${entry.listingId}'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: WaitlistQueueControls(entry: entry, showPosition: false),
        ),
      ],
    );
  }
}
