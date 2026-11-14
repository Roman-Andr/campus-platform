import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../application/listings.dart';
import '../application/waitlist.dart';
import 'waitlist_widgets.dart';

/// The place offered to the user, opened from the `listing.offer` notification.
///
/// The route carries only the listing: the offer itself is read from the
/// server, so an old notification cannot confirm a place that is already gone.
class PlaceOfferScreen extends ConsumerWidget {
  const PlaceOfferScreen({required this.listingId, super.key});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final entry = ref.watch(myWaitlistEntryProvider(listingId));
    final listing = ref.watch(listingProvider(listingId));
    return Scaffold(
      appBar: AppBar(title: Text(l.offerTitle)),
      body: entry.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(apiFailureMessage(l, e)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(myWaitlistEntryProvider(listingId)),
                child: Text(l.errorRetry),
              ),
            ],
          ),
        ),
        data: (entry) {
          if (entry == null || entry.status != WaitlistStatus.offered) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.offerUnavailable),
                  TextButton(
                    onPressed: () => context.push('/listings/$listingId'),
                    child: Text(l.offerOpenListing),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PlaceOfferCard(
                entry: entry,
                title: listing.value?.title,
                onAccepted: () => context.go('/my-listings'),
                onDeclined: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/listings/$listingId');
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
