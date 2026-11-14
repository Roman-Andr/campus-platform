import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../profile/application/my_profile.dart';
import '../application/interaction_timeline.dart';
import '../application/listings.dart';
import 'status_labels.dart';

/// Route of the history of interaction [interactionId] of listing [listingId].
String interactionTimelinePath(String listingId, String interactionId) =>
    '/listings/$listingId/interactions/$interactionId';

String timelineFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(status: 403) => l.timelineForbidden,
      ProblemFailure(status: 404) => l.listingUnavailable,
      _ => apiFailureMessage(l, error),
    };

String? timelineReason(AppLocalizations l, String? reason) => switch (reason) {
  null || '' => null,
  'listing_expired' => l.reservationRejectedExpired,
  'listing_cancelled' => l.reservationRejectedClosed,
  'author_timeout' => l.reservationRejectedTimeout,
  'listing_hidden' => l.timelineReasonHidden,
  // Free text from a person is shown as written.
  _ => reason,
};

String timelineAction(AppLocalizations l, EventOutput event) =>
    switch (event.action) {
      'requested' => l.timelineRequested,
      'transition' => l.timelineTransition,
      'auto_rejected' => l.timelineAutoRejected,
      'stage_changed' => l.timelineStageChanged,
      _ => l.timelineOther,
    };

String _status(AppLocalizations l, String status) =>
    interactionStatusLabel(l, InteractionStatus.fromJson(status));

/// History of one interaction for its author or participant. The server
/// checks access; a foreign interaction shows the refusal, never events.
class InteractionTimelineScreen extends ConsumerStatefulWidget {
  const InteractionTimelineScreen({
    required this.listingId,
    required this.interactionId,
    this.participantName,
    super.key,
  });

  final String listingId;
  final String interactionId;

  /// Known when opened from a request row; a direct link shows a role.
  final String? participantName;

  @override
  ConsumerState<InteractionTimelineScreen> createState() =>
      _InteractionTimelineScreenState();
}

class _InteractionTimelineScreenState
    extends ConsumerState<InteractionTimelineScreen> {
  bool loadingMore = false;
  String? moreError;

  InteractionTimelineProvider get _provider =>
      interactionTimelineProvider(widget.listingId, widget.interactionId);

  Future<void> _refresh() async {
    setState(() => moreError = null);
    ref
      ..invalidate(_provider)
      ..invalidate(listingProvider(widget.listingId));
    try {
      await ref.read(_provider.future);
    } on Object {
      // The provider state carries the failure; the screen shows it.
    }
  }

  Future<void> _more() async {
    setState(() {
      loadingMore = true;
      moreError = null;
    });
    try {
      await ref.read(_provider.notifier).more();
    } catch (error) {
      if (mounted) {
        setState(() => moreError = timelineFailureMessage(context.l10n, error));
      }
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final timeline = ref.watch(_provider);
    final listing = ref.watch(listingProvider(widget.listingId));
    return Scaffold(
      appBar: AppBar(title: Text(l.timelineTitle)),
      body: switch ((timeline, listing)) {
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  timelineFailureMessage(l, error),
                  key: const Key('timeline-error'),
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton(onPressed: _refresh, child: Text(l.errorRetry)),
            ],
          ),
        ),
        (AsyncData(value: final page), AsyncData(value: final item)) =>
          RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (page.events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.timelineEmpty),
                  ),
                for (final event in page.events)
                  TimelineEventTile(
                    key: ValueKey(event.id),
                    event: event,
                    listing: item,
                    participantName: widget.participantName,
                  ),
                if (moreError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(moreError!),
                  ),
                if (page.nextPage != null)
                  TextButton(
                    onPressed: loadingMore ? null : _more,
                    child: Text(l.listingsMore),
                  ),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class TimelineEventTile extends ConsumerWidget {
  const TimelineEventTile({
    required this.event,
    required this.listing,
    this.participantName,
    super.key,
  });

  final EventOutput event;
  final ListingOutput listing;
  final String? participantName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final me = ref.watch(myProfileProvider).value?.id;
    final city = ref
        .watch(citiesProvider)
        .value
        ?.where((c) => c.id == listing.cityId)
        .firstOrNull
        ?.name;
    final system = event.actorId == null;
    final author = switch (event.actorId) {
      null => l.timelineSystem,
      final id when id == me => l.timelineYou,
      final id when id == listing.authorId => listing.authorName,
      _ => participantName ?? l.timelineParticipant,
    };
    final previous = event.previousStatus;
    final reason = timelineReason(l, event.reason);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        system ? Icons.settings_suggest_outlined : Icons.person_outline,
        color: system ? scheme.outline : scheme.primary,
        semanticLabel: system ? l.timelineSystem : null,
      ),
      title: Text(timelineAction(l, event)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$author · ${formatCityTime(event.createdAt, timezone: listing.cityTimezone, city: city ?? listing.cityTimezone, l10n: l, includeDate: true)}',
          ),
          Text(
            previous == null
                ? _status(l, event.status)
                : l.timelineStatusChange(
                    _status(l, previous),
                    _status(l, event.status),
                  ),
          ),
          if (reason != null) Text(l.timelineReason(reason)),
          if (event.viaAssistant || event.offlineQr)
            Wrap(
              spacing: 8,
              children: [
                if (event.viaAssistant)
                  Chip(
                    key: Key('timeline-assistant-${event.id}'),
                    avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: Text(l.timelineViaAssistant),
                    visualDensity: VisualDensity.compact,
                  ),
                if (event.offlineQr)
                  Chip(
                    key: Key('timeline-qr-${event.id}'),
                    avatar: const Icon(Icons.qr_code_2, size: 16),
                    label: Text(l.timelineOfflineQr),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Opens the history from a request or reservation row.
class TimelineButton extends StatelessWidget {
  const TimelineButton({required this.item, super.key});
  final InteractionOutput item;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: Key('timeline-open-${item.id}'),
    onPressed: () => context.push(
      interactionTimelinePath(item.listingId, item.id),
      extra: item.participantName,
    ),
    icon: const Icon(Icons.history),
    label: Text(context.l10n.timelineOpen),
  );
}
