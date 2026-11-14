import '../../helpers/fake_api.dart';
import 'fixtures.dart';

Map<String, Object?> skillListingJson({
  String id = 'listing-1',
  String? author,
  String? authorName,
  String status = 'active',
  String? direction = 'teach',
}) => listingJson(
  id: id,
  author: author,
  authorName: authorName,
  status: status,
  kind: 'skill',
  direction: direction,
);

Map<String, Object?> lessonOptionJson({
  String id = 'option-1',
  int position = 0,
  String? time,
  String? location = 'Library',
  bool online = false,
  String? proposedBy,
  String status = 'proposed',
}) => {
  'id': id,
  'position': position,
  'time':
      time ??
      DateTime.now()
          .toUtc()
          .add(Duration(days: 2, hours: position))
          .toIso8601String(),
  'location': online ? null : location,
  'online': online,
  'proposed_by_id': proposedBy ?? userJson['id'],
  'status': status,
};

Map<String, Object?> lessonInteractionJson({
  String id = 'request-1',
  String listingId = 'listing-1',
  String? participant,
  String participantName = 'Boris',
  String status = 'pending',
  String? responseDueAt,
  List<Map<String, Object?>> options = const [],
  Map<String, Object?>? meeting,
}) => {
  'id': id,
  'listing_id': listingId,
  'participant_id': participant ?? 'other',
  'participant_name': participantName,
  'stage': null,
  'response_due_at': responseDueAt,
  'executor': false,
  'status': status,
  'meeting': meeting,
  'options': options,
};

Map<String, Object?> lessonParticipationJson({
  String id = 'request-1',
  String listingId = 'listing-1',
  String status = 'pending',
  List<Map<String, Object?>> options = const [],
  Map<String, Object?>? meeting,
}) => {
  ...lessonInteractionJson(
    id: id,
    listingId: listingId,
    participant: userJson['id']! as String,
    participantName: 'Ivan Ivanov',
    status: status,
    options: options,
    meeting: meeting,
  ),
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': listingId,
    'kind': 'skill',
    'title': 'Guitar lessons',
    'status': 'active',
    'city_timezone': 'Europe/Moscow',
  },
};

const citiesJson = {
  'items': [
    {
      'id': 'city-moscow',
      'code': 'moscow',
      'name': 'Moscow',
      'timezone': 'Europe/Moscow',
    },
  ],
};

const skillCategoriesJson = {
  'items': [
    {'id': 'category-items', 'code': 'items', 'name': 'Items'},
  ],
};
