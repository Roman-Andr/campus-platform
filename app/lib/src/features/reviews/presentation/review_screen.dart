import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/mutation_keys.dart';
import '../../../core/api/network_status.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/realtime/realtime_status_view.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../listings/application/listings.dart'
    show listingProvider, refreshInteractionLists;
import '../../profile/application/my_profile.dart';
import '../application/review.dart';
import '../domain/review.dart';
import 'review_view.dart';

/// Route of the review of [interactionId] of [listingId].
String reviewPath(String listingId, String interactionId) =>
    '/listings/$listingId/interactions/$interactionId/review';

/// Entry point to the review of a completed interaction.
///
/// It is offered for every scenario that has reviews and only after the
/// interaction is completed: the server decides who may write, change and
/// answer a review, so the card itself stays cheap and does not ask for the
/// state of every row. A participant of an event is told that the organiser
/// is reviewed there, not the other way round.
class ReviewSummary extends ConsumerWidget {
  const ReviewSummary({
    required this.item,
    required this.kind,
    required this.authorId,
    super.key,
  });

  final InteractionOutput item;

  /// Kind of the listing the interaction belongs to.
  final String kind;

  /// The author of the listing, the other side of the interaction.
  final String authorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (!reviewAvailable(kind, item)) return const SizedBox.shrink();
    final me = ref.watch(myProfileProvider).value?.id;
    // Only the two participants see the card; the interaction row is shown
    // to them alone, but a stale row of a former participant must not keep
    // an entry the server would refuse.
    final organizer = me != null && me == authorId;
    if (me != null && me != item.participantId && !organizer) {
      return const SizedBox.shrink();
    }
    final oneWay = kind == 'event';
    return Card(
      key: Key('review-summary-${item.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l.reviewSummaryTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              oneWay && organizer
                  ? l.reviewSummaryOrganizerHint
                  : l.reviewSummaryHint,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('review-open-${item.id}'),
                onPressed: () => context.push(
                  reviewPath(item.listingId, item.id),
                  extra: organizer ? item.participantName : null,
                ),
                icon: const Icon(Icons.star_outline, size: 18),
                label: Text(l.reviewSummaryAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The review of one interaction: the own one while it is hidden, the form,
/// the revealed reviews of both sides and the single answer of the addressee.
///
/// Every flag comes from the server: the window, the event one-way rule, the
/// participant check and whether the own review may still be changed. The
/// screen reloads the state after every attempt, including a refused one, and
/// wakes it up on a realtime publication, so a review written on another
/// device or a reveal that has just happened are never hidden. The
/// `Idempotency-Key` of one intent is kept until it succeeds, so a repeat
/// after a lost connection is applied once.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({
    required this.listingId,
    required this.interactionId,
    super.key,
  });

  final String listingId;

  final String interactionId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen>
    with WidgetsBindingObserver {
  final _keys = MutationKeys();
  final _textController = TextEditingController();
  final _replyController = TextEditingController();
  Timer? _revealTimer;
  int _rating = 0;
  final _tags = <String>{};
  bool _busy = false;
  bool _editing = false;
  String? _error;
  String? _message;

  (String, String) get _ids => (widget.listingId, widget.interactionId);

  InteractionReviewProvider get _provider => interactionReviewProvider(_ids);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revealTimer?.cancel();
    _textController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A review written on another device and a reveal that happened while
    // the app was in the background are reread on return.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    await ref.read(_provider.notifier).sync();
  }

  /// Reloads exactly when the review window closes, so the hidden reviews
  /// appear without waiting for the next wakeup.
  void _scheduleReveal(ReviewStateOutput state) {
    _revealTimer?.cancel();
    final closesAt = state.windowClosesAt;
    if (closesAt == null) return;
    final left = closesAt.difference(clock.now());
    if (left <= Duration.zero) return;
    _revealTimer = Timer(left, () {
      if (mounted) unawaited(_refresh());
    });
  }

  void _startEditing(ReviewOutput review) {
    setState(() {
      _editing = true;
      _rating = review.rating;
      _tags
        ..clear()
        ..addAll(review.tags);
      _textController.text = review.text ?? '';
      _error = null;
      _message = null;
    });
  }

  /// The key of one review intent: the same stars, tags and text repeated
  /// after a dropped connection keep it; any change starts a new attempt.
  String _intent(ReviewStateOutput state, {required bool editing}) {
    final tags = _tags.toList()..sort();
    return 'review:${state.interactionId}:${editing ? 'edit' : 'create'}:'
        '$_rating:${tags.join(',')}:${_textController.text.trim()}';
  }

  Future<void> _submit(ReviewStateOutput state) async {
    final l = context.l10n;
    if (_busy) return;
    if (_rating < 1) {
      setState(() => _error = l.reviewRatingRequired);
      return;
    }
    final editing = reviewMine(state) != null;
    final intent = _intent(state, editing: editing);
    final text = _textController.text.trim();
    final tags = _tags.toList();
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final notifier = ref.read(_provider.notifier);
      if (editing) {
        await notifier.edit(
          rating: _rating,
          tags: tags,
          text: text.isEmpty ? null : text,
          idempotencyKey: _keys.of(intent),
        );
      } else {
        await notifier.create(
          rating: _rating,
          tags: tags,
          text: text.isEmpty ? null : text,
          idempotencyKey: _keys.of(intent),
        );
      }
      _keys.done(intent);
      if (!mounted) return;
      refreshInteractionLists(ref);
      refreshUserReviews(ref);
      setState(() {
        _editing = false;
        _message = l.reviewSaved;
        _rating = 0;
        _tags.clear();
        _textController.clear();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _editing = false;
        _error = reviewFailureMessage(l, error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reply(ReviewStateOutput state) async {
    final l = context.l10n;
    final text = _replyController.text.trim();
    if (_busy) return;
    if (text.isEmpty) {
      setState(() => _error = l.reviewReplyRequired);
      return;
    }
    final intent = 'review-reply:${state.interactionId}:$text';
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(_provider.notifier)
          .reply(text: text, idempotencyKey: _keys.of(intent));
      _keys.done(intent);
      if (!mounted) return;
      refreshInteractionLists(ref);
      refreshUserReviews(ref);
      _replyController.clear();
      setState(() => _message = l.reviewReplied);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = reviewFailureMessage(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.listen<bool>(networkStatusProvider, (previous, next) {
      if (previous == false && next) unawaited(_refresh());
    });
    ref.listen(_provider, (previous, next) {
      final value = next.value;
      if (value != null) _scheduleReveal(value);
    });
    final review = ref.watch(_provider);
    final listing = ref.watch(listingProvider(widget.listingId)).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.reviewTitle)),
      body: switch (review) {
        AsyncData(value: final state) => RealtimeStatusBanner(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _content(state, listing, l),
          ),
        ),
        AsyncError(:final error) => ApiErrorView(
          error: error,
          message: reviewFailureMessage,
          onRetry: () => ref.invalidate(_provider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _content(
    ReviewStateOutput state,
    ListingOutput? listing,
    AppLocalizations l,
  ) {
    final config = ref.watch(reviewConfigProvider);
    final cityTime = reviewCityTime(listing, l);
    final phase = reviewPhaseOf(state);
    final mine = reviewMine(state);
    final editing = _editing && phase == ReviewPhase.editable;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          state.oneWay ? l.reviewIntroOneWay : l.reviewIntro,
          key: const Key('review-intro'),
        ),
        const SizedBox(height: 12),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_message!, key: const Key('review-result')),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              key: const Key('review-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (mine != null) ...[
          ReviewView(
            key: const Key('review-mine'),
            title: l.reviewOwnTitle,
            review: mine,
            cityTime: cityTime,
          ),
          const SizedBox(height: 8),
        ],
        switch (phase) {
          ReviewPhase.waiting => _waiting(state, l, cityTime),
          ReviewPhase.form => _form(state, l, config, editing: false),
          ReviewPhase.editable when editing => _form(
            state,
            l,
            config,
            editing: true,
          ),
          ReviewPhase.editable => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _waiting(state, l, cityTime),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('review-edit'),
                onPressed: mine == null ? null : () => _startEditing(mine),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l.reviewEdit),
              ),
            ],
          ),
          ReviewPhase.revealed => _revealed(state, l, cityTime),
          ReviewPhase.unavailable => Text(
            reviewUnavailableText(l, state, cityTime: cityTime),
            key: const Key('review-unavailable'),
          ),
        },
        const SizedBox(height: 16),
        TextButton.icon(
          key: const Key('review-refresh'),
          onPressed: _busy ? null : () => unawaited(_refresh()),
          icon: const Icon(Icons.refresh),
          label: Text(l.reviewRefresh),
        ),
      ],
    );
  }

  /// The waiting notice of an own review that is not revealed yet.
  Widget _waiting(
    ReviewStateOutput state,
    AppLocalizations l,
    String Function(DateTime instant) cityTime,
  ) {
    final closesAt = state.windowClosesAt;
    return _Notice(
      key: const Key('review-waiting'),
      icon: Icons.visibility_off_outlined,
      text: closesAt == null
          ? l.reviewWaiting
          : l.reviewWaitingUntil(cityTime(closesAt)),
    );
  }

  /// The published reviews; the answer of the addressee is written here.
  Widget _revealed(
    ReviewStateOutput state,
    AppLocalizations l,
    String Function(DateTime instant) cityTime,
  ) {
    final theirs = reviewTheirs(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Notice(
          key: const Key('review-revealed'),
          icon: Icons.visibility_outlined,
          text: theirs == null ? l.reviewPublishedOwn : l.reviewRevealed,
        ),
        if (theirs != null) ...[
          const SizedBox(height: 8),
          ReviewView(
            key: const Key('review-theirs'),
            title: l.reviewTheirsTitle,
            review: theirs,
            cityTime: cityTime,
            showOwner: true,
          ),
          const SizedBox(height: 8),
          if (state.canReply) _replyForm(l, state),
        ],
      ],
    );
  }

  Widget _replyForm(AppLocalizations l, ReviewStateOutput state) {
    final config = ref.watch(reviewConfigProvider);
    return Column(
      key: const Key('review-reply-form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.reviewReplyTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextField(
          key: const Key('review-reply-text'),
          controller: _replyController,
          maxLength: config.textMaxLength,
          maxLines: 3,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: l.reviewReplyLabel,
            helperText: l.reviewReplyHint,
          ),
        ),
        FilledButton.icon(
          key: const Key('review-reply-submit'),
          onPressed: _busy ? null : () => unawaited(_reply(state)),
          icon: const Icon(Icons.reply_outlined),
          label: Text(l.reviewReplyAction),
        ),
      ],
    );
  }

  Widget _form(
    ReviewStateOutput state,
    AppLocalizations l,
    ReviewConfig config, {
    required bool editing,
  }) {
    return Column(
      key: const Key('review-form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.reviewRatingLabel),
        Row(
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                key: Key('review-star-$star'),
                tooltip: l.reviewRatingOf(star),
                onPressed: _busy ? null : () => setState(() => _rating = star),
                icon: Icon(
                  star <= _rating ? Icons.star : Icons.star_border,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            const SizedBox(width: 8),
            if (_rating > 0) Text(l.reviewRatingOf(_rating)),
          ],
        ),
        if (state.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l.reviewTagsLabel),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final code in state.tags)
                FilterChip(
                  key: Key('review-tag-$code'),
                  label: Text(reviewTagName(l, code)),
                  selected: _tags.contains(code),
                  onSelected: _busy
                      ? null
                      : (selected) => setState(() {
                          if (selected) {
                            _tags.add(code);
                          } else {
                            _tags.remove(code);
                          }
                        }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('review-text'),
          controller: _textController,
          maxLength: config.textMaxLength,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: l.reviewTextLabel,
            helperText: l.reviewTextHint,
          ),
        ),
        FilledButton.icon(
          key: const Key('review-submit'),
          onPressed: _busy ? null : () => unawaited(_submit(state)),
          icon: const Icon(Icons.send_outlined),
          label: Text(editing ? l.reviewSave : l.reviewSubmit),
        ),
      ],
    );
  }
}

/// A highlighted fact about the state: a hidden review or the reveal.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
