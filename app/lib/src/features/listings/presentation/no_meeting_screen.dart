import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/network_status.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../profile/application/my_profile.dart';
import '../application/listings.dart';
import '../application/meeting.dart';
import '../application/no_meeting.dart';

/// Route of the no-meeting confirmation of [interactionId] of [listingId].
String noMeetingPath(String listingId, String interactionId) =>
    '/listings/$listingId/interactions/$interactionId/no-meeting';

/// Entry point to the mutual confirmation of an interaction that may be
/// completed without a meeting; nothing for other kinds and states.
class NoMeetingSummary extends StatelessWidget {
  const NoMeetingSummary({required this.item, required this.kind, super.key});

  final InteractionOutput item;

  /// Kind of the listing the interaction belongs to.
  final String kind;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (!noMeetingAvailable(kind, item)) return const SizedBox.shrink();
    return Card(
      key: Key('no-meeting-${item.id}'),
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
                  l.noMeetingTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l.noMeetingBothConfirm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('no-meeting-open-${item.id}'),
                onPressed: () =>
                    context.push(noMeetingPath(item.listingId, item.id)),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(l.noMeetingOpen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mutual confirmation of one interaction without a meeting: the current
/// user's consent, the consent of the other participant and the result.
///
/// The state is read from the server on every opening and refresh, so a
/// confirmation made on another device is recovered. The consent keeps its
/// `Idempotency-Key` for the lifetime of the screen, so a repeat after a
/// network failure is applied once.
class NoMeetingScreen extends ConsumerStatefulWidget {
  const NoMeetingScreen({
    required this.listingId,
    required this.interactionId,
    super.key,
  });

  final String listingId;
  final String interactionId;

  @override
  ConsumerState<NoMeetingScreen> createState() => _NoMeetingScreenState();
}

class _NoMeetingScreenState extends ConsumerState<NoMeetingScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;
  String? _idempotencyKey;

  (String, String) get _ids => (widget.listingId, widget.interactionId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  Future<void> _reload() async {
    final provider = noMeetingStateProvider(_ids);
    ref.invalidate(provider);
    try {
      final state = await ref.read(provider.future);
      // Completion made on another device also changes the interaction lists.
      if (!mounted) return;
      if (state.completed) refreshInteractionLists(ref);
    } on Object {
      // The provider state carries the failure; the screen shows it.
    }
  }

  /// Reloads the state and the listing after either of them failed to load.
  Future<void> _retry() async {
    final state = noMeetingStateProvider(_ids);
    final listing = listingProvider(widget.listingId);
    ref
      ..invalidate(state)
      ..invalidate(listing);
    try {
      await Future.wait([ref.read(state.future), ref.read(listing.future)]);
    } on Object {
      // The provider states carry the failure; the screen shows it.
    }
  }

  Future<void> _refresh() async {
    await _reload();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirm() async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    final idempotencyKey = _idempotencyKey ??= const Uuid().v7();
    try {
      final output = await ref
          .read(noMeetingStateProvider(_ids).notifier)
          .confirm(idempotencyKey: idempotencyKey);
      if (!mounted) return;
      ref.invalidate(meetingInteractionProvider(_ids));
      refreshInteractionLists(ref);
      _showMessage(output.completed ? l.noMeetingCompleted : l.noMeetingSent);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = noMeetingFailureMessage(l, error));
        if (noMeetingIsUnavailable(error)) unawaited(_reload());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.listen<bool>(networkStatusProvider, (previous, next) {
      if (previous == false && next) unawaited(_reload());
    });
    final state = ref.watch(noMeetingStateProvider(_ids));
    final listing = ref.watch(listingProvider(widget.listingId));
    return Scaffold(
      appBar: AppBar(title: Text(l.noMeetingTitle)),
      body: switch ((state, listing)) {
        (AsyncData(value: final data), AsyncData(value: final listing)) =>
          RefreshIndicator(onRefresh: _refresh, child: _content(data, listing)),
        (AsyncError(:final error), _) => _failure(
          noMeetingFailureMessage(l, error),
        ),
        (_, AsyncError(:final error)) => _failure(
          noMeetingFailureMessage(l, error),
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
              key: const Key('no-meeting-load-error'),
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(onPressed: _retry, child: Text(l.errorRetry)),
        ],
      ),
    );
  }

  Widget _content(NoMeetingOutput state, ListingOutput listing) {
    final l = context.l10n;
    final me = ref.watch(myProfileProvider).value?.id;
    final cities = ref.watch(citiesProvider).value;
    final city =
        cities?.where((city) => city.id == listing.cityId).firstOrNull?.name ??
        listing.cityTimezone;
    final mine = state.confirmations
        .where((item) => item.participantId == me)
        .firstOrNull;
    final other = state.confirmations
        .where((item) => item.participantId != me)
        .firstOrNull;
    final completed = state.completed;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              key: const Key('no-meeting-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Text(l.noMeetingIntro),
        const SizedBox(height: 16),
        _consent(
          key: const Key('no-meeting-your-consent'),
          label: l.noMeetingYourConsent,
          confirmedAt: mine?.confirmedAt,
          timezone: listing.cityTimezone,
          city: city,
        ),
        const SizedBox(height: 8),
        _consent(
          key: const Key('no-meeting-other-consent'),
          label: l.noMeetingOtherConsent,
          confirmedAt: other?.confirmedAt,
          timezone: listing.cityTimezone,
          city: city,
        ),
        if (state.agreedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            l.noMeetingAgreedAt(
              _time(l, state.agreedAt!, listing.cityTimezone, city),
            ),
            key: const Key('no-meeting-agreed-at'),
          ),
        ],
        if (completed) ...[
          const SizedBox(height: 16),
          Chip(
            key: const Key('no-meeting-completed'),
            avatar: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(l.noMeetingCompletedStatus),
          ),
          if (state.completedAt != null)
            Text(
              l.noMeetingCompletedAt(
                _time(l, state.completedAt!, listing.cityTimezone, city),
              ),
              key: const Key('no-meeting-completed-at'),
            ),
        ] else if (state.confirmedByMe) ...[
          const SizedBox(height: 16),
          Text(l.noMeetingWaiting, key: const Key('no-meeting-waiting')),
          TextButton.icon(
            key: const Key('no-meeting-refresh'),
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(l.noMeetingRefresh),
          ),
        ] else ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('no-meeting-confirm'),
            onPressed: _busy ? null : _confirm,
            icon: const Icon(Icons.check),
            label: Text(l.noMeetingConfirm),
          ),
        ],
      ],
    );
  }

  Widget _consent({
    required Key key,
    required String label,
    required DateTime? confirmedAt,
    required String timezone,
    required String city,
  }) {
    final l = context.l10n;
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          Text(
            confirmedAt == null
                ? l.noMeetingNotConfirmed
                : l.noMeetingConfirmedAt(_time(l, confirmedAt, timezone, city)),
          ),
        ],
      ),
    );
  }

  String _time(
    AppLocalizations l,
    DateTime instant,
    String timezone,
    String city,
  ) => formatCityTime(
    instant,
    timezone: timezone,
    city: city,
    l10n: l,
    includeDate: true,
  );
}
