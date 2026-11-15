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
import '../../../core/time/city_time.dart';
import '../../profile/application/my_profile.dart';
import '../application/listings.dart';
import '../application/no_show.dart';
import '../domain/no_show.dart';
import 'listings_screens.dart' show listingFailureMessage;

/// Route of the no-show state of [interactionId] of [listingId].
String noShowPath(String listingId, String interactionId) =>
    '/listings/$listingId/interactions/$interactionId/no-show';

/// Entry point to the no-show rules of a personal interaction.
///
/// It is offered after the agreed meeting and only for the kinds the server
/// judges; before the mark window opens it explains when the action becomes
/// available, and it never offers it at all for a completed interaction. The
/// screen itself takes the exact window from the server.
class NoShowSummary extends ConsumerWidget {
  const NoShowSummary({
    required this.item,
    required this.kind,
    required this.timezone,
    required this.city,
    this.otherName,
    super.key,
  });

  final InteractionOutput item;

  /// Kind of the listing the interaction belongs to.
  final String kind;

  /// Time zone of the city of the listing (#44).
  final String timezone;

  /// City shown next to a time from another zone.
  final String city;

  /// The other participant, when the caller knows the name.
  final String? otherName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (!noShowAvailable(kind, item)) return const SizedBox.shrink();
    final config = ref.watch(noShowConfigProvider);
    final meetingAt = noShowMeetingAt(item);
    final marked = item.status == InteractionStatus.noShow;
    final now = clock.now();
    // The card runs ahead of the server only to hide an action that cannot
    // succeed yet; the screen shows the exact window of the response.
    final opensAt = meetingAt?.add(config.markAfter);
    final locked = !marked && opensAt != null && now.isBefore(opensAt);
    return Card(
      key: Key('no-show-${item.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_busy_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l.noShowSummaryTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(locked ? l.noShowSummaryWaiting : l.noShowSummaryHint),
            if (locked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.noShowOpensAt(_time(context.l10n, opensAt)),
                  key: const Key('no-show-locked'),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('no-show-open-${item.id}'),
                onPressed: locked
                    ? null
                    : () => context.push(
                        noShowPath(item.listingId, item.id),
                        extra: otherName,
                      ),
                icon: const Icon(Icons.person_off_outlined, size: 18),
                label: Text(marked ? l.noShowOpenResult : l.noShowAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(AppLocalizations l, DateTime instant) => formatCityTime(
    instant,
    timezone: timezone,
    city: city,
    l10n: l,
    includeDate: true,
  );
}

/// The no-show state of one personal interaction: the window, the marks of
/// both participants, a mutual dispute and the lift by a late QR code.
///
/// The screen marks with a required reason. The reason, the window bounds and
/// every mark come from the server: after a mark, a repeat or a refusal the
/// screen rereads the whole state, so a mark made elsewhere is never hidden.
/// The `Idempotency-Key` of one intent is kept until it succeeds, so a repeat
/// after a lost connection is applied once.
class NoShowScreen extends ConsumerStatefulWidget {
  const NoShowScreen({
    required this.listingId,
    required this.interactionId,
    this.otherName,
    super.key,
  });

  final String listingId;
  final String interactionId;

  /// The other participant, when the caller knows the name.
  final String? otherName;

  @override
  ConsumerState<NoShowScreen> createState() => _NoShowScreenState();
}

class _NoShowScreenState extends ConsumerState<NoShowScreen>
    with WidgetsBindingObserver {
  final _keys = MutationKeys();
  final _reasonController = TextEditingController();
  Timer? _ticker;
  bool _busy = false;
  String? _error;
  String? _message;

  (String, String) get _ids => (widget.listingId, widget.interactionId);

  InteractionNoShowProvider get _provider => interactionNoShowProvider(_ids);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The window and the dispute deadline change with time; the form has to
    // disappear exactly when the server stops accepting marks.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A late QR or a mark made on another device is not always published:
    // coming back to the app rereads the state instead of keeping it stale.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  String Function(DateTime instant) _cityTime(AppLocalizations l) {
    final listing = ref.read(listingProvider(widget.listingId)).value;
    if (listing == null) return (instant) => instant.toIso8601String();
    return noShowCityTime(listing, l);
  }

  Future<void> _refresh() async {
    await ref.read(_provider.notifier).sync();
  }

  Future<void> _submit(NoShowOutput state) async {
    final l = context.l10n;
    final reason = _reasonController.text.trim();
    if (_busy) return;
    if (reason.isEmpty) {
      setState(() => _error = l.noShowReasonRequired);
      return;
    }
    // The same reason keeps the same key while the user repeats the attempt,
    // so a repeat after a dropped connection is applied once by the server.
    final intent = 'no-show:${state.interactionId}:$reason';
    final answer = state.status == InteractionStatus.noShow;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(_provider.notifier)
          .mark(reason: reason, idempotencyKey: _keys.of(intent));
      _keys.done(intent);
      if (!mounted) return;
      _reasonController.clear();
      refreshInteractionLists(ref);
      setState(() {
        _message = answer ? l.noShowAnswerDone : l.noShowMarkedDone;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = noShowFailureMessage(l, error, cityTime: _cityTime(l));
      });
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
    final state = ref.watch(_provider);
    final listing = ref.watch(listingProvider(widget.listingId));
    return Scaffold(
      appBar: AppBar(title: Text(l.noShowScreenTitle)),
      body: switch ((state, listing)) {
        (AsyncData(value: final noShow), AsyncData(value: final listing)) =>
          RealtimeStatusBanner(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _content(noShow, listing),
            ),
          ),
        (AsyncError(:final error), _) => _failure(
          noShowFailureMessage(l, error, cityTime: _cityTime(l)),
        ),
        (_, AsyncError(:final error)) => _failure(
          listingFailureMessage(l, error),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _failure(String message) {
    final l = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              message,
              key: const Key('no-show-load-error'),
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(_provider),
            child: Text(l.errorRetry),
          ),
        ],
      ),
    );
  }

  Widget _content(NoShowOutput state, ListingOutput listing) {
    final l = context.l10n;
    final me = ref.watch(myProfileProvider).value?.id;
    final config = ref.watch(noShowConfigProvider);
    final cityTime = noShowCityTime(listing, l);
    final phase = noShowPhase(state);
    final accepted = state.status == InteractionStatus.accepted;
    final marked = state.status == InteractionStatus.noShow;
    final mine = state.marks.any((mark) => mark.reporterId == me);
    // The answer window of a mark runs from the moment it was made, which can
    // be after `auto_after`; only the first mark depends on the mark window.
    final canSubmit =
        state.canMark && (accepted ? phase == NoShowPhase.open : marked);
    final dispute = switch (state.dispute) {
      final NoShowDisputeOutput value => value,
      _ => null,
    };
    final openDispute = noShowDisputeOpen(state);
    final lifted = noShowLiftedAfterQr(state);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(listing.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l.noShowIntro),
        const SizedBox(height: 12),
        Chip(
          key: const Key('no-show-basis'),
          label: Text(noShowBasisName(l, state)),
        ),
        if (state.noShowAt case final at?)
          Text(l.noShowAt(cityTime(at)), key: const Key('no-show-at')),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const Key('no-show-result')),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const Key('no-show-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        if (lifted)
          _Notice(
            key: const Key('no-show-lifted'),
            icon: Icons.qr_code_2,
            text: l.noShowLiftedAfterQr,
          )
        else if (openDispute)
          _Notice(
            key: const Key('no-show-dispute-open'),
            icon: Icons.gavel_outlined,
            text: l.noShowDisputeOpenNotice,
          )
        else if (dispute != null)
          _Notice(
            key: const Key('no-show-dispute-closed'),
            icon: Icons.gavel_outlined,
            text: l.noShowDisputeClosedNotice,
          ),
        if (accepted) ...[
          switch (phase) {
            NoShowPhase.before => Text(
              l.noShowOpensAt(cityTime(state.markFrom!)),
              key: const Key('no-show-phase-before'),
            ),
            NoShowPhase.open => Text(
              l.noShowWindowOpen(cityTime(state.autoAfter!)),
              key: const Key('no-show-phase-open'),
            ),
            NoShowPhase.closed => Text(
              l.noShowClosedMessage,
              key: const Key('no-show-phase-closed'),
            ),
            NoShowPhase.unavailable => Text(
              l.noShowUnavailable,
              key: const Key('no-show-phase-unavailable'),
            ),
          },
        ] else if (marked && canSubmit)
          Text(l.noShowAnswerHint, key: const Key('no-show-answer-hint')),
        const SizedBox(height: 12),
        if (canSubmit)
          _form(state, config, l, answer: marked)
        else if (mine)
          Text(l.noShowAlreadyMarked, key: const Key('no-show-already-marked'))
        else if (accepted && phase == NoShowPhase.open)
          Text(l.noShowNoAction, key: const Key('no-show-no-action')),
        const Divider(height: 32),
        Text(
          l.noShowMarksTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (state.marks.isEmpty)
          Text(l.noShowMarksEmpty)
        else
          for (final mark in noShowSortedMarks(state))
            _NoShowMarkTile(
              mark: mark,
              viewerId: me,
              otherName: widget.otherName,
              cityTime: cityTime,
            ),
        const SizedBox(height: 16),
        TextButton.icon(
          key: const Key('no-show-refresh'),
          onPressed: _busy ? null : () => unawaited(_refresh()),
          icon: const Icon(Icons.refresh),
          label: Text(l.noShowRefresh),
        ),
      ],
    );
  }

  /// The required reason of a mark or of an answer to one.
  Widget _form(
    NoShowOutput state,
    NoShowConfig config,
    AppLocalizations l, {
    required bool answer,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(answer ? l.noShowAnswerHint : l.noShowReasonHint),
      TextField(
        key: const Key('no-show-reason'),
        controller: _reasonController,
        maxLength: config.reasonMaxLength,
        maxLines: 3,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: answer ? l.noShowAnswerLabel : l.noShowReasonLabel,
        ),
      ),
      FilledButton.icon(
        key: const Key('no-show-submit'),
        onPressed: _busy ? null : () => unawaited(_submit(state)),
        icon: const Icon(Icons.person_off_outlined),
        label: Text(answer ? l.noShowAnswerAction : l.noShowMarkAction),
      ),
    ],
  );
}

/// A highlighted fact about the state: a lifted mark or a dispute.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
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

/// One mark of the interaction: who made it, whom it is charged to, whether
/// it still counts and why.
class _NoShowMarkTile extends StatelessWidget {
  const _NoShowMarkTile({
    required this.mark,
    required this.viewerId,
    required this.otherName,
    required this.cityTime,
  });

  final NoShowMarkOutput mark;
  final String? viewerId;
  final String? otherName;
  final String Function(DateTime instant) cityTime;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final removedAt = mark.removedAt;
    return ListTile(
      key: Key('no-show-mark-${mark.id}'),
      leading: Icon(removedAt == null ? Icons.person_off_outlined : Icons.undo),
      title: Text(
        l.noShowMarkChargedTo(
          noShowSubjectName(l, mark, viewerId: viewerId, otherName: otherName),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.noShowMarkBy(
              noShowReporterName(
                l,
                mark,
                viewerId: viewerId,
                otherName: otherName,
              ),
            ),
          ),
          Text(
            [
              noShowMarkStatusName(l, mark),
              if (removedAt != null) l.noShowRemovedAt(cityTime(removedAt)),
              cityTime(mark.createdAt),
            ].join(' · '),
          ),
          if (mark.reason case final reason?) Text(l.noShowMarkReason(reason)),
        ],
      ),
    );
  }
}
