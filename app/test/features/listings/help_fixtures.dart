import 'fixtures.dart';

Map<String, Object?> helpListingJson({
  String id = 'listing-1',
  String? author,
  String status = 'active',
  DateTime? relevantUntil,
  String title = 'Help to move a couch',
  String description = 'Two floors, no elevator, around 30 minutes.',
}) => {
  ...listingJson(id: id, author: author, status: status, kind: 'help'),
  'title': title,
  'description': description,
  'expires_at':
      (relevantUntil ?? DateTime.now().toUtc().add(const Duration(days: 7)))
          .toIso8601String(),
};

Map<String, Object?> helpInteractionJson({
  String id = 'request-1',
  String listingId = 'listing-1',
  String participant = 'participant',
  String participantName = 'Boris',
  String status = 'pending',
  bool executor = false,
}) => {
  'id': id,
  'listing_id': listingId,
  'participant_id': participant,
  'participant_name': participantName,
  'stage': null,
  'response_due_at': null,
  'executor': executor,
  'status': status,
  'meeting': null,
};

Map<String, Object?> helpParticipationJson({
  String id = 'request-1',
  String listingId = 'listing-1',
  String participant = 'participant',
  String participantName = 'Boris',
  String status = 'pending',
  String listingStatus = 'active',
  bool executor = false,
}) => {
  ...helpInteractionJson(
    id: id,
    listingId: listingId,
    participant: participant,
    participantName: participantName,
    status: status,
    executor: executor,
  ),
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': listingId,
    'kind': 'help',
    'title': 'Help to move a couch',
    'status': listingStatus,
    'city_timezone': 'Europe/Moscow',
  },
};

const helpCategoriesJson = {
  'items': [
    {'id': 'category-items', 'code': 'items', 'name': 'Items'},
  ],
};
