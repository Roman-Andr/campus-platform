import '../../helpers/fake_api.dart';

Map<String, Object?> listingJson({
  String id = 'listing-1',
  String? author,
  String status = 'active',
  String kind = 'giveaway',
  String? pinnedUntil,
  String? previewUrl,
  String? previewFileId,
  String? previewExpiresAt,
}) => {
  'id': id,
  'author_id': author ?? userJson['id'],
  'author_name': 'Ivan Ivanov',
  'category_id': 'category-items',
  'hidden_reason': null,
  'archived_at': null,
  'purged_at': null,
  'preview_url': previewUrl,
  'preview_file_id': previewFileId,
  'preview_expires_at': previewExpiresAt,
  'kind': kind,
  'title': 'A desk',
  'description': 'Collect on campus',
  'visibility': 'city',
  'audience': 'students',
  'city_id': 'city-moscow',
  'city_timezone': 'Europe/Moscow',
  'dormitory_id': null,
  'faculty_id': null,
  'status': status,
  'version': 1,
  'created_at': '2026-11-14T00:00:00Z',
  'expires_at': status == 'draft' ? null : '2026-12-14T00:00:00Z',
  'pinned_until': ?pinnedUntil,
};
Map<String, Object?> pageJson(List<Object?> items, {String? next}) => {
  'items': items,
  'next_page': next,
};

Map<String, Object?> waitlistJson({
  String id = 'entry-1',
  String listingId = 'listing-1',
  String status = 'waiting',
  int? position,
  DateTime? expires,
}) => {
  'id': id,
  'listing_id': listingId,
  'participant_name': 'Ivan Ivanov',
  'participant_id': userJson['id'],
  'status': status,
  'position': position,
  'offered_at': status == 'offered' && expires != null
      ? expires.subtract(const Duration(hours: 2)).toIso8601String()
      : null,
  'offer_expires_at': expires?.toIso8601String(),
  'interaction_id': null,
  'created_at': '2026-11-14T00:00:00Z',
};

Map<String, Object?> eventListingJson({
  String id = 'event-1',
  String? author,
  String status = 'active',
  String title = 'Campus concert',
  int capacity = 3,
  int remaining = 3,
  String? startsAt,
  String? endsAt,
  String location = 'Hall A',
}) {
  final ends = endsAt ?? '2099-01-01T02:00:00Z';
  return {
    ...listingJson(id: id, author: author, status: status, kind: 'event'),
    'title': title,
    'description': 'Meet in the hall',
    'expires_at': ends,
    'event_starts_at': startsAt ?? '2099-01-01T00:00:00Z',
    'event_ends_at': ends,
    'event_location': location,
    'event_capacity': capacity,
    'remaining_places': remaining,
  };
}
