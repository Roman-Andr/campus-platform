import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';

/// The kind of a listing where the author offers or asks for a skill
/// (ТЗ п. 5.1.1, модуль 4, п. 10).
const skillKind = 'skill';

/// Whether [listing] is a skill listing rather than a giveaway or a notice.
bool isSkillListing(ListingOutput listing) => listing.kind == skillKind;

/// Direction of a skill listing: the author can teach or wants to learn.
SkillDirection? skillDirectionOf(ListingOutput listing) =>
    switch (listing.direction) {
      ListingOutputDirectionSkillDirection(value: final direction) => direction,
      _ => null,
    };

String skillDirectionLabel(AppLocalizations l, SkillDirection direction) =>
    switch (direction) {
      SkillDirectionKnown(value: SkillDirectionValue.teach) =>
        l.skillDirectionTeach,
      SkillDirectionKnown(value: SkillDirectionValue.learn) =>
        l.skillDirectionLearn,
      _ => l.listingKindSkill,
    };

/// Time options of a lesson; empty for other interactions.
List<LessonOptionOutput> lessonOptionsOf(InteractionOutput item) =>
    item.options ?? const [];

String lessonOptionStatusLabel(AppLocalizations l, LessonOptionStatus status) =>
    switch (status) {
      LessonOptionStatusKnown(value: LessonOptionStatusValue.proposed) =>
        l.lessonOptionProposed,
      LessonOptionStatusKnown(value: LessonOptionStatusValue.selected) =>
        l.lessonOptionSelected,
      LessonOptionStatusKnown(value: LessonOptionStatusValue.declined) =>
        l.lessonOptionDeclined,
      _ => l.listingStatusUnknown,
    };

/// Who made [option]: the author of the listing or the participant.
bool lessonOptionProposedByAuthor(
  LessonOptionOutput option,
  ListingOutput listing,
) => option.proposedById == listing.authorId;

/// Whether [userId] may select [option] now.
///
/// The author answers the participant's options, the participant answers the
/// author's counter-option; nobody may answer their own option.
bool lessonOptionCanBeAccepted(
  InteractionOutput item,
  ListingOutput listing,
  LessonOptionOutput option,
  String? userId,
) {
  if (userId == null ||
      item.status != InteractionStatus.pending ||
      option.status != LessonOptionStatus.proposed) {
    return false;
  }
  final expected = switch (option.proposedById) {
    final id when id == listing.authorId => item.participantId,
    final id when id == item.participantId => listing.authorId,
    _ => null,
  };
  return expected != null && expected == userId;
}

/// Whether [userId] may answer any option of the interaction.
bool lessonHasAnswer(
  InteractionOutput item,
  ListingOutput listing,
  String? userId,
) => lessonOptionsOf(item)
    .any((option) => lessonOptionCanBeAccepted(item, listing, option, userId));

/// Whether the author may replace the participant's options with their own
/// counter-option.
bool lessonCanCounter(
  InteractionOutput item,
  ListingOutput listing,
  String? userId,
) =>
    isSkillListing(listing) &&
    userId != null &&
    userId == listing.authorId &&
    item.status == InteractionStatus.pending;

/// A lesson may be repeated once the previous one is scheduled or completed.
bool lessonCanRepeat(
  InteractionOutput item,
  ListingOutput listing,
  String? userId,
) =>
    isSkillListing(listing) &&
    userId != null &&
    (userId == listing.authorId || userId == item.participantId) &&
    (item.status == InteractionStatus.accepted ||
        item.status == InteractionStatus.completed);

/// Whether the participant already has a lesson that is pending or scheduled.
bool lessonHasActiveLesson(Iterable<InteractionOutput> items) => items.any(
  (item) =>
      item.status == InteractionStatus.pending ||
      item.status == InteractionStatus.accepted,
);

/// One time option being edited in the lesson form.
@immutable
class LessonSlotDraft {
  const LessonSlotDraft({
    required this.time,
    this.location = '',
    this.online = false,
  });

  final DateTime time;
  final String location;
  final bool online;

  LessonSlotDraft copyWith({DateTime? time, String? location, bool? online}) =>
      LessonSlotDraft(
        time: time ?? this.time,
        location: location ?? this.location,
        online: online ?? this.online,
      );

  LessonSlotInput toInput() => LessonSlotInput(
    time: time,
    location: online ? null : location.trim(),
    online: online,
  );

  /// Rejects a past time or a missing place of an offline option.
  String? error(AppLocalizations l, {DateTime? now}) {
    if (!time.isAfter(now ?? clock.now())) return l.meetingTimePast;
    if (!online && location.trim().isEmpty) return l.meetingPlaceRequired;
    return null;
  }
}

/// Rejects a number of options outside the configured bounds.
String? lessonCountError(
  AppLocalizations l,
  int count, {
  required int minOptions,
  required int maxOptions,
}) {
  if (count < minOptions) return l.lessonOptionsTooFew(minOptions);
  if (count > maxOptions) return l.lessonOptionsTooMany(maxOptions);
  return null;
}

/// A message for a failed lesson request (Problem Details).
String lessonFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.lessonOptionsInvalid),
      ) =>
        l.lessonOptionsInvalid,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.meetingTimeInvalid),
      ) =>
        l.meetingTimeInvalid,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.meetingPlaceInvalid),
      ) =>
        l.meetingPlaceInvalid,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.listingConflict),
      ) =>
        l.lessonConflict,
      ProblemFailure(status: 403) => l.lessonForbidden,
      ProblemFailure(status: 404) => l.listingUnavailable,
      _ => apiFailureMessage(l, error),
    };

/// The single slot of a counter-proposal.
LessonSlotInput counterSlot(LessonSlotDraft draft) => draft.toInput();

/// A future starting time of the first option of a new lesson.
DateTime lessonInitialTime({DateTime? now}) =>
    (now ?? clock.now()).add(const Duration(days: 1));
