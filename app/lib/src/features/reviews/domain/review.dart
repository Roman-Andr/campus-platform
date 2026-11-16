import 'package:clock/clock.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../listings/domain/feed.dart' show FeedKind;

/// Kinds whose completed interactions are reviewed (ТЗ п. 5.1.1, модуль 5).
///
/// A publication has no counterpart to review; every other scenario has its
/// own ready-made tags. The server uses the same set, so the client only
/// keeps an entry point away from a kind the server would refuse.
const reviewableKinds = {
  FeedKind.giveaway,
  FeedKind.exchange,
  FeedKind.loan,
  FeedKind.skill,
  FeedKind.help,
  FeedKind.event,
  FeedKind.purchase,
};

/// Whether reviews exist for interactions of [kind].
bool reviewKindSupported(String kind) =>
    reviewableKinds.contains(FeedKind.fromApi(kind));

/// The own review of the state, or null when there is none yet.
ReviewOutput? reviewMine(ReviewStateOutput state) => switch (state.mine) {
  final ReviewOutput review => review,
  _ => null,
};

/// The revealed review about the requester, or null while it is hidden.
ReviewOutput? reviewTheirs(ReviewStateOutput state) => switch (state.theirs) {
  final ReviewOutput review => review,
  _ => null,
};

/// The single answer of the addressee, or null while there is none.
ReviewReplyOutput? reviewReplyOf(ReviewOutput review) => switch (review.reply) {
  final ReviewReplyOutput reply => reply,
  _ => null,
};

/// Where the viewer is in the review cycle of one interaction.
enum ReviewPhase {
  /// No own review yet and the server accepts one.
  form,

  /// An own review exists, is not revealed yet and may be changed.
  editable,

  /// An own review exists and is hidden until the reveal.
  waiting,

  /// The reviews are revealed; the own one can no longer be changed.
  revealed,

  /// Nothing to write and nothing to read yet: the interaction is not
  /// completed, the window has closed or the viewer does not review it.
  unavailable,
}

/// The phase of the review from the flags of the server.
///
/// Every flag is authoritative: the server already accounts for the window,
/// the event one-way rule and the participant check, so the client only picks
/// the screen for them instead of repeating those rules.
ReviewPhase reviewPhaseOf(ReviewStateOutput state) {
  if (state.canReview) return ReviewPhase.form;
  if (state.canEdit) return ReviewPhase.editable;
  final mine = reviewMine(state);
  // A review hidden by a moderator is neither waiting for a reveal nor
  // editable: it stays where it is, and the screen says why.
  if (mine != null && mine.hidden) return ReviewPhase.unavailable;
  if (state.revealed) return ReviewPhase.revealed;
  if (mine != null) return ReviewPhase.waiting;
  return ReviewPhase.unavailable;
}

/// Whether the entry card of the review belongs on the interaction row.
///
/// The card is cheap: it uses the interaction itself and does not ask the
/// server, so an interaction row never waits for another request. The exact
/// window, the one-way rule and the answer availability come from the state
/// of the screen.
///
/// An event interaction keeps `completed_at` empty even after the event:
/// the server counts its end as the completion, so [eventEndsAt] of the
/// listing decides when the card appears. Without a known end the card stays
/// away: an event that has not finished cannot be reviewed, and a row
/// without the listing cannot tell.
bool reviewAvailable(
  String kind,
  InteractionOutput item, {
  DateTime? eventEndsAt,
  DateTime? now,
}) {
  if (!reviewKindSupported(kind)) return false;
  if (kind == 'event') {
    final endsAt = eventEndsAt;
    if (endsAt == null) return false;
    if (item.status != InteractionStatus.accepted &&
        item.status != InteractionStatus.completed) {
      return false;
    }
    // The server judges the event once it has ended; a card before that
    // would open a screen the server refuses.
    return !(now ?? clock.now()).isBefore(endsAt);
  }
  return item.completedAt != null;
}

/// A localized name of a ready-made tag code of the scenario.
///
/// The codes are stable server vocabulary; a code this build does not know
/// is replaced with a generic label instead of a technical value.
String reviewTagName(AppLocalizations l, String code) => switch (code) {
  'punctual' => l.reviewTagPunctual,
  'item_as_described' => l.reviewTagItemAsDescribed,
  'friendly' => l.reviewTagFriendly,
  'clear_communication' => l.reviewTagClearCommunication,
  'fair_offer' => l.reviewTagFairOffer,
  'item_in_order' => l.reviewTagItemInOrder,
  'returned_on_time' => l.reviewTagReturnedOnTime,
  'clear_explanation' => l.reviewTagClearExplanation,
  'patient' => l.reviewTagPatient,
  'useful' => l.reviewTagUseful,
  'helped_as_promised' => l.reviewTagHelpedAsPromised,
  'responsive' => l.reviewTagResponsive,
  'interesting' => l.reviewTagInteresting,
  'well_organized' => l.reviewTagWellOrganized,
  'organizer_punctual' => l.reviewTagOrganizerPunctual,
  'as_described' => l.reviewTagAsDescribed,
  'transparent_terms' => l.reviewTagTransparentTerms,
  _ => l.reviewTagOther,
};

/// The localized names of the tags of a review, in the order of the server.
List<String> reviewTagNames(AppLocalizations l, List<String> codes) => [
  for (final code in codes) reviewTagName(l, code),
];

/// An instant in the city of a listing, or a device-local date and time when
/// the city zone is not known yet.
String reviewTimeLabel(
  AppLocalizations l,
  DateTime instant, {
  String? timezone,
  String? city,
}) {
  if (timezone == null) {
    final local = instant.toLocal();
    return '${DateFormat.yMd(l.localeName).format(local)}, '
        '${DateFormat.Hm(l.localeName).format(local)}';
  }
  return formatCityTime(
    instant,
    timezone: timezone,
    city: city ?? timezone,
    l10n: l,
    includeDate: true,
  );
}

/// The city clock of a listing, as [reviewTimeLabel] expects it.
String Function(DateTime instant) reviewCityTime(
  ListingOutput? listing,
  AppLocalizations l,
) =>
    (instant) => reviewTimeLabel(
      l,
      instant,
      timezone: listing?.cityTimezone,
      city: listing?.cityTimezone,
    );

/// Why nothing can be written or read, in the words of the viewer.
///
/// The server does not say which rule applied, so the reason is derived from
/// the flags it does send: a review hidden by a moderator, an interaction
/// that was never completed, a closed window and the one-way rule of an
/// event cover every case the screen can reach.
String reviewUnavailableText(
  AppLocalizations l,
  ReviewStateOutput state, {
  required String Function(DateTime instant) cityTime,
  DateTime? now,
}) {
  final mine = reviewMine(state);
  if (mine != null && mine.hidden) return l.reviewHiddenByModerator;
  if (state.completedAt == null) return l.reviewUnavailableNotCompleted;
  final closesAt = state.windowClosesAt;
  final at = now ?? clock.now();
  if (closesAt != null && !at.isBefore(closesAt)) {
    return l.reviewWindowMissed(cityTime(closesAt));
  }
  if (state.oneWay && !state.canReview) return l.reviewUnavailableOrganizer;
  return l.reviewUnavailable;
}

/// A message for a failed review request.
///
/// The server decides who may write, change or answer a review; its problem
/// codes are turned into localized texts here, and a request that failed
/// because the state changed is followed by a reload of that state.
String reviewFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewForbidden),
      ) =>
        l.reviewErrorForbidden,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewOneWay),
      ) =>
        l.reviewErrorOneWay,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewUnavailable),
      ) =>
        l.reviewErrorUnavailable,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewWindowClosed),
      ) =>
        l.reviewErrorWindowClosed,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewExists),
      ) =>
        l.reviewErrorExists,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewPublished),
      ) =>
        l.reviewErrorPublished,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewHidden),
      ) =>
        l.reviewErrorHidden,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewRatingInvalid),
      ) =>
        l.reviewErrorRating,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewTagsInvalid),
      ) =>
        l.reviewErrorTags,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewTextInvalid),
      ) =>
        l.reviewErrorText,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewReplyExists),
      ) =>
        l.reviewErrorReplyExists,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.reviewReplyInvalid),
      ) =>
        l.reviewErrorReplyInvalid,
      // A hidden or not yet revealed review is a plain 404: its existence
      // must not leak, and the form for it is not shown anyway.
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.notFound),
      ) =>
        l.reviewErrorNotFound,
      _ => apiFailureMessage(l, error),
    };
