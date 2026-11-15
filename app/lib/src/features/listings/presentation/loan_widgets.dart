import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/realtime/realtime_channel.dart';
import '../../../core/realtime/realtime_models.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../profile/application/my_profile.dart';
import '../../qr/domain/qr_availability.dart';
import '../../qr/presentation/qr_presenter_screen.dart';
import '../../qr/presentation/qr_scanner_screen.dart';
import '../application/listings.dart';
import '../application/loan.dart';
import '../application/loan_config.dart';
import '../application/meeting.dart';
import '../application/my_listings.dart';
import '../application/no_show.dart';
import '../domain/loan.dart';
import 'status_labels.dart';

/// The loan card of an accepted or finished interaction: the three steps
/// "accepted → issued → returned", the return deadline in the city zone, the
/// "overdue" flag, the two QR actions and the owner's "not returned" mark
/// (ТЗ п. 5.1.1, модуль 4, п. 9).
///
/// The owner shows the handover code and scans the return one; the borrower
/// does the opposite. The server refuses a participant of the other side and
/// any code of another interaction, so the card only guides the flow.
class LoanSummary extends ConsumerStatefulWidget {
  const LoanSummary({
    required this.item,
    required this.kind,
    required this.timezone,
    this.city,
    super.key,
  });

  final InteractionOutput item;

  /// Kind of the listing the interaction belongs to.
  final String kind;

  /// Time zone of the city of the listing.
  final String timezone;

  /// City name for the time zone note; the zone itself is a fallback.
  final String? city;

  @override
  ConsumerState<LoanSummary> createState() => _LoanSummaryState();
}

class _LoanSummaryState extends ConsumerState<LoanSummary>
    with WidgetsBindingObserver {
  final _keys = LoanKeys();
  RealtimeSubscription? _subscription;
  StreamSubscription<RealtimeEvent>? _events;
  Timer? _timer;
  NoShowOutput? _noShow;
  DateTime? _availableAt;
  String? _error;
  bool _busy = false;

  (String, String) get _ids => (widget.item.listingId, widget.item.id);

  @override
  void initState() {
    super.initState();
    if (widget.kind != loanKind) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _schedule();
        unawaited(_watchRealtime());
      }
    });
  }

  @override
  void didUpdateWidget(covariant LoanSummary old) {
    super.didUpdateWidget(old);
    final before = old.item;
    final after = widget.item;
    if (before.id != after.id) {
      // The card of another interaction reuses this state: its mark, server
      // instant and error belong to the previous one.
      _noShow = null;
      _availableAt = null;
      _error = null;
      _busy = false;
    }
    if (before.status != after.status ||
        before.stage != after.stage ||
        before.returnDueAt != after.returnDueAt) {
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A missed realtime publication and an elapsed deadline are both
    // recovered from the server when the app returns to the foreground.
    if (state == AppLifecycleState.resumed) {
      _reload();
      _schedule();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_events?.cancel());
    // Closing a channel notifies the realtime service, which must not happen
    // while the tree is being finalized.
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(subscription.close()),
      );
    }
    super.dispose();
  }

  /// The personal channel carries only wakeups; every one is followed by a
  /// reload of the authoritative interaction, so a lost publication never
  /// leaves a stale stage or a missed "not returned" mark.
  Future<void> _watchRealtime() async {
    if (widget.kind != loanKind || _subscription != null) return;
    try {
      final user =
          ref.read(myProfileProvider).value ??
          await ref.read(myProfileProvider.future);
      if (user == null) return;
      final subscription = ref
          .read(realtimeServiceProvider.notifier)
          .subscribe(
            RealtimeChannel.personal(user.id),
            reload: () async => _reload(),
          );
      if (!mounted) {
        await subscription.close();
        return;
      }
      _subscription = subscription;
      _events = subscription.events.listen((_) => _reload());
    } on Object {
      // Realtime is a wakeup only: the card works on refresh without it.
    }
  }

  void _reload() {
    if (!mounted || widget.kind != loanKind) return;
    ref
      ..invalidate(meetingInteractionProvider(_ids))
      ..invalidate(myParticipationProvider)
      ..invalidate(incomingProvider)
      ..invalidate(listingParticipationProvider(widget.item.listingId))
      ..invalidate(listingProvider(widget.item.listingId));
    if (_noShow != null || widget.item.status == InteractionStatus.noShow) {
      ref.invalidate(interactionNoShowProvider(_ids));
    }
  }

  /// Rereads the card when the deadline passes or the mark becomes allowed.
  ///
  /// The app does not poll: one timer per open card fires at the nearest
  /// of the two moments and is replaced after the reload.
  void _schedule() {
    _timer?.cancel();
    if (widget.kind != loanKind) return;
    final config = ref.read(loanConfigProvider);
    final item = widget.item;
    if (!loanIsIssued(item)) return;
    final now = clock.now();
    final due = item.returnDueAt;
    final available =
        _availableAt ??
        loanNotReturnedFrom(item, wait: config.notReturnedAfter);
    final upcoming = [
      if (due != null && due.isAfter(now)) due,
      if (available != null && available.isAfter(now)) available,
    ]..sort();
    if (upcoming.isEmpty) return;
    _timer = Timer(upcoming.first.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _reload();
      // The first moment may have been the deadline itself; the mark can
      // still be ahead of it.
      _schedule();
    });
  }

  String _time(AppLocalizations l, DateTime instant) =>
      loanCityTime(l, instant, timezone: widget.timezone, city: widget.city);

  Future<void> _markNotReturned(LoanConfig config) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.loanNotReturnedConfirmTitle),
        content: Text(l.loanNotReturnedConfirmBody),
        actions: [
          TextButton(
            key: const Key('loan-not-returned-keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.loanNotReturnedKeep),
          ),
          FilledButton(
            key: const Key('loan-not-returned-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.loanNotReturnedConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final intent = 'not-returned:${widget.item.id}';
    final key = _keys.of(intent);
    try {
      final state = await ref
          .read(campusApiProvider)
          .loans
          .markNotReturned(
            listingId: widget.item.listingId,
            interactionId: widget.item.id,
            options: loanMutationOptions(key),
          );
      _keys.done(intent);
      if (!mounted) return;
      setState(() {
        _noShow = state;
        _availableAt = null;
        _error = null;
      });
      _reload();
    } on Object catch (error) {
      if (!mounted) return;
      final availableAt = switch (ApiFailure.from(error)) {
        ProblemFailure(
          code: ProblemCodeKnown(
            value: ProblemCodeValue.loanNotReturnedTooEarly,
          ),
          :final problem,
        ) =>
          problem.availableAt,
        _ => null,
      };
      setState(() {
        _availableAt = availableAt;
        _error = availableAt == null
            ? loanFailureMessage(
                l,
                error,
                config: config,
                cityTime: (instant) => _time(l, instant),
              )
            : null;
      });
      _schedule();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answerNoShow() async {
    final l = context.l10n;
    final noShowConfig = ref.read(noShowConfigProvider);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) =>
          _LoanDisputeDialog(maxLength: noShowConfig.reasonMaxLength),
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final intent = 'dispute:${widget.item.id}';
    final key = _keys.of(intent);
    try {
      final state = await ref
          .read(campusApiProvider)
          .noShows
          .markInteractionNoShow(
            listingId: widget.item.listingId,
            interactionId: widget.item.id,
            body: NoShowReasonInput(reason: reason),
            options: loanMutationOptions(key),
          );
      _keys.done(intent);
      if (!mounted) return;
      setState(() {
        _noShow = state;
        _error = null;
      });
      _reload();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = loanNoShowFailureMessage(
            l,
            error,
            reasonMaxLength: noShowConfig.reasonMaxLength,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final item = widget.item;
    if (widget.kind != loanKind) return const SizedBox.shrink();
    final step = loanStep(item);
    if (step == LoanStep.closed && item.status != InteractionStatus.noShow) {
      // The status row of the interaction already explains this ending.
      return const SizedBox.shrink();
    }
    final config = ref.watch(loanConfigProvider);
    final me = ref.watch(myProfileProvider).value?.id;
    final borrower = loanIsBorrower(item, me);
    final owner = me != null && !borrower;
    final now = clock.now();
    final availableFrom =
        _availableAt ??
        loanNotReturnedFrom(item, wait: config.notReturnedAfter);
    final notReturnedOpen =
        availableFrom != null && !now.isBefore(availableFrom);
    // The no-show state is loaded only for a loan that ended as one: a
    // missed meeting already has its own explanation in the interaction rows.
    final noShow =
        _noShow ??
        (item.status == InteractionStatus.noShow
            ? ref.watch(interactionNoShowProvider(_ids)).value
            : null);
    final returnDue = item.returnDueAt;
    return Card(
      key: Key('loan-${item.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.handshake_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l.loanCardTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (item.overdue) ...[
                  const SizedBox(width: 8),
                  Chip(
                    key: Key('loan-overdue-${item.id}'),
                    label: Text(l.loanOverdueChip),
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            _Steps(item: item, step: step),
            if (returnDue != null) ...[
              const SizedBox(height: 8),
              Text(
                l.loanReturnDue(_time(l, returnDue)),
                key: Key('loan-return-due-${item.id}'),
                style: item.overdue
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: Key('loan-error-${item.id}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (step == LoanStep.accepted && me != null) ...[
              const SizedBox(height: 8),
              Text(l.loanHandoverHint),
              const SizedBox(height: 8),
              if (owner)
                _QrButton(
                  key: const Key('loan-show-handover'),
                  onPressed: () => context.push(
                    qrShowPath(
                      item.listingId,
                      item.id,
                      action: QrAction.loanHandover,
                    ),
                  ),
                  icon: Icons.qr_code_2,
                  label: l.loanShowHandover,
                ),
              if (borrower)
                _QrButton(
                  key: const Key('loan-scan-handover'),
                  onPressed: () => context.push(
                    qrScanPath(
                      item.listingId,
                      item.id,
                      action: QrAction.loanHandover,
                    ),
                  ),
                  icon: Icons.qr_code_scanner,
                  label: l.loanScanHandover,
                ),
            ],
            if (step == LoanStep.issued && me != null) ...[
              const SizedBox(height: 8),
              Text(l.loanReturnHint),
              const SizedBox(height: 8),
              if (borrower)
                _QrButton(
                  key: const Key('loan-show-return'),
                  onPressed: () => context.push(
                    qrShowPath(
                      item.listingId,
                      item.id,
                      action: QrAction.loanReturn,
                    ),
                  ),
                  icon: Icons.qr_code_2,
                  label: l.loanShowReturn,
                ),
              if (owner)
                _QrButton(
                  key: const Key('loan-scan-return'),
                  onPressed: () => context.push(
                    qrScanPath(
                      item.listingId,
                      item.id,
                      action: QrAction.loanReturn,
                    ),
                  ),
                  icon: Icons.qr_code_scanner,
                  label: l.loanScanReturn,
                ),
              if (owner) ...[
                const SizedBox(height: 8),
                FilledButton.tonal(
                  key: const Key('loan-not-returned'),
                  onPressed: notReturnedOpen && !_busy
                      ? () => unawaited(_markNotReturned(config))
                      : null,
                  child: Text(l.loanNotReturned),
                ),
                if (!notReturnedOpen && availableFrom != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l.loanNotReturnedUntil(_time(l, availableFrom)),
                      key: const Key('loan-not-returned-until'),
                    ),
                  ),
              ],
            ],
            if (step == LoanStep.returned && item.completedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                l.loanReturnedAt(_time(l, item.completedAt!)),
                key: Key('loan-returned-${item.id}'),
              ),
            ],
            if (noShow != null) _noShowSection(l, noShow, borrower),
          ],
        ),
      ),
    );
  }

  Widget _noShowSection(AppLocalizations l, NoShowOutput state, bool borrower) {
    if (!loanNoShowIsNotReturned(state)) return const SizedBox.shrink();
    final dispute = state.dispute;
    final disputeOpen =
        dispute is NoShowDisputeOutput &&
        switch (dispute.status) {
          DisputeStatusKnown(value: DisputeStatusValue.open) => true,
          _ => false,
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          borrower ? l.loanNotReturnedMarked : l.loanBorrowerNoShow,
          key: Key('loan-not-returned-mark-${widget.item.id}'),
        ),
        if (disputeOpen) ...[
          const SizedBox(height: 4),
          Text(l.loanDisputeOpen, key: const Key('loan-dispute-open')),
        ],
        if (borrower && state.canMark) ...[
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('loan-dispute'),
            onPressed: _busy ? null : () => unawaited(_answerNoShow()),
            child: Text(l.loanDispute),
          ),
        ],
        if (!borrower && !disputeOpen)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.loanDisputeWaiting),
          ),
      ],
    );
  }
}

/// Three steps of a loan with the current one highlighted.
class _Steps extends StatelessWidget {
  const _Steps({required this.item, required this.step});

  final InteractionOutput item;
  final LoanStep step;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final steps = [
      (LoanStep.accepted, l.loanStepAccepted),
      (LoanStep.issued, l.loanStepIssued),
      (LoanStep.returned, l.loanStepReturned),
    ];
    final current = switch (step) {
      LoanStep.accepted => 0,
      LoanStep.issued => 1,
      LoanStep.returned => 2,
      LoanStep.closed => -1,
    };
    if (current < 0) {
      return Text(interactionStatusLabel(l, item.status));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (index, (value, label)) in steps.indexed) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                index < current
                    ? Icons.check_circle
                    : index == current
                    ? Icons.radio_button_checked
                    : Icons.circle_outlined,
                size: 16,
                color: index <= current ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                key: Key('loan-step-${value.name}'),
                style: index == current
                    ? TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      )
                    : index < current
                    ? null
                    : TextStyle(color: scheme.outline),
              ),
            ],
          ),
          if (index != steps.length - 1)
            Icon(Icons.arrow_forward, size: 14, color: scheme.outline),
        ],
      ],
    );
  }
}

class _QrButton extends StatelessWidget {
  const _QrButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    super.key,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

/// Collects the required reason of the borrower's answer to a no-show.
class _LoanDisputeDialog extends StatefulWidget {
  const _LoanDisputeDialog({required this.maxLength});

  final int maxLength;

  @override
  State<_LoanDisputeDialog> createState() => _LoanDisputeDialogState();
}

class _LoanDisputeDialogState extends State<_LoanDisputeDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _send() {
    final l = context.l10n;
    final error = loanDisputeReasonError(
      l,
      _reason.text,
      reasonMaxLength: widget.maxLength,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.loanDisputeTitle),
      content: TextField(
        key: const Key('loan-dispute-reason'),
        controller: _reason,
        minLines: 2,
        maxLines: 4,
        maxLength: widget.maxLength,
        decoration: InputDecoration(
          labelText: l.loanDisputeReason,
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      actions: [
        TextButton(
          key: const Key('loan-dispute-keep'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.loanDisputeKeep),
        ),
        FilledButton(
          key: const Key('loan-dispute-send'),
          onPressed: _send,
          child: Text(l.loanDisputeSend),
        ),
      ],
    );
  }
}
