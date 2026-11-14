import 'app_router.dart';

/// The screen a notification opens, or null when the client has none for it.
///
/// The server puts the object into `params` of the notification payload; the
/// client only maps the known types, so a new type never opens a wrong screen.
String? notificationRoute(String type, Map<String, Object?> data) {
  final listingId = data['listing_id'];
  if (listingId is! String || listingId.isEmpty) return null;
  final listing = '/listings/${Uri.encodeComponent(listingId)}';
  final interactionId = data['interaction_id'];
  final interaction = interactionId is String && interactionId.isNotEmpty
      ? '$listing/interactions/${Uri.encodeComponent(interactionId)}'
      : null;
  return switch (type) {
    'listing.offer' => AppRoutes.placeOfferOf(listingId),
    'listing.activity' => interaction ?? listing,
    'listing.meeting.proposed' ||
    'listing.meeting.scheduled' ||
    'listing.meeting.rescheduled' ||
    'listing.meeting.reminder' =>
      interaction == null ? listing : '$interaction/meeting',
    'listing.offer_expired' ||
    'listing.waitlist_joined' ||
    'listing.waitlist_open' ||
    'listing.waitlist_cleared' => listing,
    _ => null,
  };
}
