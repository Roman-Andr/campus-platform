import 'dart:async';

import 'package:dio/dio.dart' show Options;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/interceptors.dart' show idempotencyKeyHeader;
import '../../../core/realtime/personal_wakeups.dart';
import '../../../core/realtime/realtime_models.dart';
import '../../listings/application/listings.dart' show listingRetry;
import '../../profile/application/my_profile.dart';

part 'review.g.dart';

/// Client-side parameters of the review rules (ТЗ, Приложение 4).
///
/// Values come from `--dart-define` at build time and must match the
/// server's `CAMPUS_REVIEW_TEXT_MAX_LENGTH`. The form only limits the input
/// to that length; the server stays the authority and reports its own
/// refusal, so a drifting build parameter never accepts what the server
/// rejects.
class ReviewConfig {
  ReviewConfig({required this.textMaxLength})
    : assert(textMaxLength > 0, 'a text cannot be limited to nothing');

  factory ReviewConfig.fromEnvironment() => ReviewConfig(
    textMaxLength: const int.fromEnvironment(
      'CAMPUS_REVIEW_TEXT_MAX_LENGTH',
      defaultValue: 2000,
    ),
  );

  /// Longest review text or answer the server accepts, in characters.
  final int textMaxLength;
}

@Riverpod(keepAlive: true)
ReviewConfig reviewConfig(Ref ref) => ReviewConfig.fromEnvironment();

/// The review state of one interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a review written on another device,
/// a reveal that already happened and a closed window are never hidden behind
/// a stale response. A realtime publication only wakes [sync] up, which loads
/// the whole state again; the payload never carries a rating or a text.
@Riverpod(retry: listingRetry)
class InteractionReview extends _$InteractionReview {
  bool _syncing = false;
  bool _syncAgain = false;

  @override
  Future<ReviewStateOutput> build((String, String) ids) async {
    final current = await _load();
    final wakeups = PersonalWakeups(ref);
    ref.onDispose(() => unawaited(wakeups.stop()));
    unawaited(
      wakeups.start(
        reload: sync,
        onEvent: (event) {
          if (!matchesInteractionWakeup(
            event,
            listingId: ids.$1,
            interactionId: ids.$2,
          )) {
            return;
          }
          unawaited(sync());
        },
      ),
    );
    return current;
  }

  /// Reloads the state from the server; a failure keeps the shown state.
  Future<void> sync() async {
    if (!ref.mounted) return;
    // A wakeup that arrives while the state is loading must not be dropped:
    // the request in flight may have been sent before the change was made.
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        try {
          final next = await _load();
          if (!ref.mounted) return;
          state = AsyncData(next);
        } on Object {
          // The screen reports the failure of its own request; the next
          // wakeup, the refresh action or the reopening retries.
          break;
        }
      } while (_syncAgain && ref.mounted);
    } finally {
      _syncing = false;
    }
  }

  /// Writes the own review of the completed interaction.
  ///
  /// The caller keeps [idempotencyKey] while repeating the same intent, so a
  /// repeat after a dropped connection is applied once by the server. The
  /// state is read back after both a success and a refusal: the server may
  /// have revealed the reviews or closed the window meanwhile, and the screen
  /// must show that instead of the state it had.
  Future<ReviewStateOutput> create({
    required int rating,
    required List<String> tags,
    required String? text,
    required String idempotencyKey,
  }) => _attempt(
    () => ref
        .read(campusApiProvider)
        .reviews
        .createInteractionReview(
          listingId: ids.$1,
          interactionId: ids.$2,
          body: ReviewInputBody(rating: rating, tags: tags, text: text),
          options: _options(idempotencyKey),
        ),
  );

  /// Replaces the own review before the reveal.
  Future<ReviewStateOutput> edit({
    required int rating,
    required List<String> tags,
    required String? text,
    required String idempotencyKey,
  }) => _attempt(
    () => ref
        .read(campusApiProvider)
        .reviews
        .editInteractionReview(
          listingId: ids.$1,
          interactionId: ids.$2,
          body: ReviewInputBody(rating: rating, tags: tags, text: text),
          options: _options(idempotencyKey),
        ),
  );

  /// Answers the revealed review of the other side exactly once.
  Future<ReviewStateOutput> reply({
    required String text,
    required String idempotencyKey,
  }) => _attempt(
    () => ref
        .read(campusApiProvider)
        .reviews
        .replyToInteractionReview(
          listingId: ids.$1,
          interactionId: ids.$2,
          body: ReplyInputBody(text: text),
          options: _options(idempotencyKey),
        ),
  );

  /// Runs a mutation and rereads the authoritative state after it either way.
  Future<ReviewStateOutput> _attempt(
    Future<ReviewStateOutput> Function() request,
  ) async {
    final ReviewStateOutput output;
    try {
      output = await request();
    } on Object {
      // A review that lost the race with the reveal or a closed window must
      // leave the current state on the screen, not the old one.
      await sync();
      rethrow;
    }
    if (ref.mounted) state = AsyncData(output);
    await sync();
    return output;
  }

  Options _options(String idempotencyKey) =>
      Options(headers: {idempotencyKeyHeader: idempotencyKey});

  Future<ReviewStateOutput> _load() => ref
      .read(campusApiProvider)
      .reviews
      .interactionReview(listingId: ids.$1, interactionId: ids.$2);
}

/// One page of the public reviews about a user.
class ReviewPage {
  const ReviewPage({required this.items, this.nextPage});

  final List<ReviewOutput> items;

  /// Cursor of the next page; null on the last page.
  final String? nextPage;
}

/// The public reviews about a user: revealed and not hidden ones only.
///
/// The list is paginated by the server cursor. A realtime publication about a
/// review or its answer reloads the first page, so a reply written on another
/// device and a reveal that has just happened show up without a restart; the
/// loaded extra pages are dropped, because a new review shifts them.
@Riverpod(retry: listingRetry)
class UserReviews extends _$UserReviews {
  bool _loading = false;
  Object? _generation;

  @override
  Future<ReviewPage> build(String userId) async {
    _generation = null;
    _loading = false;
    final current = await _load(null);
    final wakeups = PersonalWakeups(ref);
    ref.onDispose(() => unawaited(wakeups.stop()));
    unawaited(
      wakeups.start(
        reload: sync,
        onEvent: (event) {
          if (!_reviewWakeup(event)) return;
          unawaited(sync());
        },
      ),
    );
    return current;
  }

  /// Reloads the first page; a failure keeps the shown list.
  Future<void> sync() async {
    if (!ref.mounted) return;
    final generation = Object();
    _generation = generation;
    _loading = false;
    try {
      final next = await _load(null);
      if (!ref.mounted || !identical(_generation, generation)) return;
      state = AsyncData(next);
    } on Object {
      // The screen reports the failure of its own request; the refresh
      // action or the reopening retries.
    }
  }

  /// Appends the next page, skipping reviews already shown.
  Future<void> more() async {
    final previous = state.value;
    if (_loading || previous == null || previous.nextPage == null) return;
    _loading = true;
    final generation = Object();
    _generation = generation;
    try {
      final page = await _load(previous.nextPage);
      if (!ref.mounted || !identical(_generation, generation)) return;
      final seen = {for (final review in previous.items) review.id};
      state = AsyncData(
        ReviewPage(
          items: [
            ...previous.items,
            for (final review in page.items)
              if (seen.add(review.id)) review,
          ],
          nextPage: page.nextPage,
        ),
      );
    } finally {
      _loading = false;
    }
  }

  Future<ReviewPage> _load(String? cursor) async {
    final page = await ref
        .read(campusApiProvider)
        .reviews
        .userReviews(userId: userId, cursor: cursor);
    return ReviewPage(items: page.items, nextPage: page.nextPage);
  }
}

/// Whether a publication of the personal channel is about a review.
///
/// The server queues the review wakeups with a `kind` of `published` or
/// `replied`; the personal channel also carries other changes of the user,
/// which must not reload the public list.
bool _reviewWakeup(RealtimeEvent event) {
  final data = event.data;
  if (data is! Map<String, Object?>) return true;
  final kind = data['kind'];
  if (kind is! String) return true;
  return kind == 'published' || kind == 'replied';
}

/// Refresh every view that shows the signed-in user's public reviews.
void refreshUserReviews(WidgetRef ref) {
  final me = ref.read(myProfileProvider).value;
  if (me != null) ref.invalidate(userReviewsProvider(me.id));
}
