import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../domain/event.dart';
import 'listings.dart';
import 'waitlist.dart';

part 'events.g.dart';

// Expected API errors must reach the card at once: a retried signup would
// hide the fact that the seats were taken while the form was open.
Duration? eventRetry(int retryCount, Object error) => null;

/// The own seat of an event plus the row that carries it.
@immutable
class EventSeat {
  const EventSeat({
    required this.status,
    required this.listing,
    this.interaction,
    this.entry,
  });

  final EventSeatStatus status;
  final ListingOutput listing;

  /// The accepted interaction of the current user, when registered.
  final InteractionOutput? interaction;

  /// The own queue entry, when waiting or offered a place.
  final WaitlistEntryOutput? entry;
}

/// Resolves the own seat from the listing, own interactions and the queue.
///
/// Registration is an accepted interaction; the server creates it at signup,
/// so there is no pending stage to wait for.
@Riverpod(retry: eventRetry)
Future<EventSeat> eventSeat(Ref ref, String listingId) async {
  final listing = await ref.watch(listingProvider(listingId).future);
  final participation = await ref.watch(
    listingParticipationProvider(listingId).future,
  );
  final entry = await ref.watch(myWaitlistEntryProvider(listingId).future);
  InteractionOutput? accepted;
  for (final item in participation) {
    if (item.status == InteractionStatus.accepted) {
      accepted = item;
      break;
    }
  }
  final queued = entry != null && waitlistIsActive(entry.status);
  return EventSeat(
    status: eventSeatStatus(
      registered: accepted != null,
      queued: queued,
      remainingPlaces: listing.remainingPlaces,
    ),
    listing: listing,
    interaction: accepted,
    entry: queued ? entry : null,
  );
}
