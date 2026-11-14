/// One notification as `GET /api/v1/notifications` returns it.
Map<String, Object?> notificationJson({
  required String id,
  required int sequence,
  String type = 'listing.waitlist_open',
  String? listingId = 'listing-1',
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
  'params': {'listing_id': ?listingId},
  'read': read,
};

Map<String, Object?> notificationPage(
  List<Map<String, Object?>> items, {
  String? next,
}) => {'items': items, 'next_page': next};
