import 'app_router.dart';

/// The screen a notification opens, or null when the client has none for it.
///
/// The server puts the object into `params` of the notification payload; the
/// client only maps the known types, so a new type never opens a wrong screen.
String? notificationRoute(String type, Map<String, Object?> data) {
  final listingId = data['listing_id'];
  if (listingId is! String || listingId.isEmpty) return null;
  return switch (type) {
    'listing.offer' => AppRoutes.placeOfferOf(listingId),
    'listing.offer_expired' ||
    'listing.waitlist_joined' ||
    'listing.waitlist_open' ||
    'listing.waitlist_cleared' => '/listings/${Uri.encodeComponent(listingId)}',
    _ => null,
  };
}
