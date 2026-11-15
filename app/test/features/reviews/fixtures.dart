import 'package:campus/src/core/api/api_client.dart';

/// The author of the listing and the other participant of the interaction.
const reviewAuthorId = '01890a5d-ac96-774b-bcce-b302099a8058';
const reviewParticipantId = '01890a5d-ac96-774b-bcce-b302099a8060';

/// The tag catalogue of a giveaway, as the server sends it.
const reviewTagsJson = <String>[
  'punctual',
  'item_as_described',
  'friendly',
  'clear_communication',
];

Map<String, Object?> reviewReplyJson({
  String id = 'reply-1',
  String reviewId = 'review-theirs',
  String? author,
  String authorName = 'Petr Petrov',
  String text = 'Thanks, it was a pleasure.',
  String createdAt = '2026-11-21T12:00:00Z',
}) => {
  'id': id,
  'review_id': reviewId,
  'author_id': author ?? reviewParticipantId,
  'author_name': authorName,
  'text': text,
  'created_at': createdAt,
  'updated_at': createdAt,
};

Map<String, Object?> reviewJson({
  String id = 'review-mine',
  String? author,
  String authorName = 'Ivan Ivanov',
  String? subject,
  String kind = 'giveaway',
  int rating = 5,
  List<String> tags = const ['punctual', 'friendly'],
  String? text = 'Everything went well',
  String createdAt = '2026-11-20T12:00:00Z',
  String? publishedAt,
  bool hidden = false,
  Map<String, Object?>? reply,
}) => {
  'id': id,
  'interaction_id': 'request-1',
  'listing_id': 'listing-1',
  'kind': kind,
  'author_id': author ?? reviewAuthorId,
  'author_name': authorName,
  'subject_id': subject ?? reviewParticipantId,
  'rating': rating,
  'tags': tags,
  'text': text,
  'created_at': createdAt,
  'updated_at': createdAt,
  'reveal_at': '2026-12-04T12:00:00Z',
  'published_at': publishedAt,
  'hidden': hidden,
  'reply': reply,
};

Map<String, Object?> reviewStateJson({
  String kind = 'giveaway',
  String status = 'completed',
  bool oneWay = false,
  String? completedAt = '2026-11-20T12:00:00Z',
  String? windowClosesAt = '2026-12-04T12:00:00Z',
  bool revealed = false,
  bool eligible = true,
  bool canReview = true,
  bool canEdit = false,
  bool canReply = false,
  List<String> tags = reviewTagsJson,
  Map<String, Object?>? mine,
  Map<String, Object?>? theirs,
}) => {
  'listing_id': 'listing-1',
  'interaction_id': 'request-1',
  'kind': kind,
  'status': status,
  'one_way': oneWay,
  'completed_at': completedAt,
  'window_closes_at': windowClosesAt,
  'revealed': revealed,
  'eligible': eligible,
  'can_review': canReview,
  'can_edit': canEdit,
  'can_reply': canReply,
  'tags': tags,
  'mine': mine,
  'theirs': theirs,
  'server_time': '2026-11-21T12:00:00Z',
};

ReviewStateOutput reviewState({
  String kind = 'giveaway',
  String status = 'completed',
  bool oneWay = false,
  String? completedAt = '2026-11-20T12:00:00Z',
  String? windowClosesAt = '2026-12-04T12:00:00Z',
  bool revealed = false,
  bool eligible = true,
  bool canReview = true,
  bool canEdit = false,
  bool canReply = false,
  List<String> tags = reviewTagsJson,
  Map<String, Object?>? mine,
  Map<String, Object?>? theirs,
}) => ReviewStateOutput.fromJson(
  reviewStateJson(
    kind: kind,
    status: status,
    oneWay: oneWay,
    completedAt: completedAt,
    windowClosesAt: windowClosesAt,
    revealed: revealed,
    eligible: eligible,
    canReview: canReview,
    canEdit: canEdit,
    canReply: canReply,
    tags: tags,
    mine: mine,
    theirs: theirs,
  ),
);

Map<String, Object?> interactionJson({
  String id = 'request-1',
  String status = 'completed',
  String? completedAt = '2026-11-20T12:00:00Z',
  String participantId = reviewParticipantId,
  String participantName = 'Petr Petrov',
}) => {
  'id': id,
  'listing_id': 'listing-1',
  'participant_name': participantName,
  'participant_id': participantId,
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'status': status,
  'completed_at': completedAt,
  'meeting': null,
};

ProblemFailure reviewProblem(String code, {int status = 409}) => ProblemFailure(
  Problem(
    type: 'urn:problem:campus:$code',
    title: 'Server title',
    status: status,
    code: ProblemCodeKnown(
      ProblemCodeValue.values.firstWhere((value) => value.value == code),
    ),
  ),
);
