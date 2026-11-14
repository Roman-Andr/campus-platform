/// One notification as `GET /api/v1/notifications` returns it.
Map<String, Object?> notificationJson({
  required String id,
  required int sequence,
  String type = 'listing.waitlist_open',
  String? listingId = 'listing-1',
  String? interactionId,
  bool read = false,
  String occurredAt = '2026-11-14T09:00:00Z',
  String ru = 'Место освободилось — бронируйте.',
  String en = 'A place is free — book it now.',
}) => {
  'id': id,
  'sequence': sequence,
  'type': type,
  'object_id': listingId,
  'occurred_at': occurredAt,
  'created_at': occurredAt,
  'text': {'ru': ru, 'en': en},
  'params': {'listing_id': ?listingId, 'interaction_id': ?interactionId},
  'read': read,
};

Map<String, Object?> notificationPage(
  List<Map<String, Object?>> items, {
  String? next,
  int? unread,
}) => {
  'items': items,
  'next_page': next,
  // The server counts the whole inbox; tests default to the page itself.
  'unread_count': unread ?? items.where((row) => row['read'] != true).length,
};
