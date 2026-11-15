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
import '../../profile/application/my_profile.dart';
import '../application/events.dart' show eventSeatProvider;
import '../application/listings.dart';
import '../application/no_show.dart';
import '../domain/event.dart' show EventSeatStatus;
import '../domain/no_show.dart';
import 'event_screen.dart' show EventSummary;
import 'listings_screens.dart' show listingFailureMessage;

/// Route of the no-show result of the event [listingId].
String eventNoShowPath(String listingId) => '/event/$listingId/no-show';

/// Entry point to the vote of an ended event.
///
/// The server judges an event 24 hours after its end and accepts votes during
/// the following 7 days; both windows start at the end, so the action appears
/// with the end time and only for the organiser and registered participants.
class EventNoShowAction extends ConsumerWidget {
  const EventNoShowAction({required this.item, super.key});

  final ListingOutput item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final endsAt = item.eventEndsAt;
    final user = ref.watch(myProfileProvider).value;
    if (endsAt == null || user == null || !clock.now().isAfter(endsAt)) {
      return const SizedBox.shrink();
    }
    final organizer = item.authorId == user.id;
    final seat = ref.watch(eventSeatProvider(item.id)).value;
    final registered = seat?.status == EventSeatStatus.registered;
    if (!organizer && !registered) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('event-no-show-open'),
        onPressed: () => context.push(eventNoShowPath(item.id)),
        icon: const Icon(Icons.event_busy_outlined),
        label: Text(
          organizer ? l.eventNoShowResultAction : l.eventNoShowAction,
        ),
      ),
    );
  }
}

/// The "did not take place" result of one event.
///
/// A registered participant votes during the 7 days after the event; at a
/// third of the registrations, rounded up, the organiser is charged instead
/// of the participants. The organiser sees the charge and can dispute it
/// within 7 days. The decision itself belongs to moderation (#94) and is not
/// taken by the client. Every attempt is followed by a reload, so a vote of
/// another participant or a changed window never leaves a stale screen.
class EventNoShowScreen extends ConsumerStatefulWidget {
  const EventNoShowScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<EventNoShowScreen> createState() => _EventNoShowScreenState();
}

class _EventNoShowScreenState extends ConsumerState<EventNoShowScreen>
    with WidgetsBindingObserver {
  final _keys = MutationKeys();
  Timer? _ticker;
  bool _busy = false;
  String? _error;
  String? _message;

  EventNoShowProvider get _provider => eventNoShowProvider(widget.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Votes of other participants and the automatic judgment are not always
    // published: coming back to the app rereads the result.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  String Function(DateTime instant) _cityTime(AppLocalizations l) {
    final listing = ref.read(listingProvider(widget.id)).value;
    if (listing == null) return (instant) => instant.toIso8601String();
    return noShowCityTime(listing, l);
  }

  Future<void> _refresh() async {
    await ref.read(_provider.notifier).sync();
  }

  Future<void> _vote() async {
    final l = context.l10n;
    if (_busy) return;
    const intent = 'event-no-show-vote';
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref.read(_provider.notifier).vote(idempotencyKey: _keys.of(intent));
      _keys.done(intent);
      if (!mounted) return;
      setState(() => _message = l.eventNoShowVotedDone);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = eventNoShowFailureMessage(l, error, cityTime: _cityTime(l));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dispute() async {
    final l = context.l10n;
    if (_busy) return;
    const intent = 'event-no-show-dispute';
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(_provider.notifier)
          .dispute(idempotencyKey: _keys.of(intent));
      _keys.done(intent);
      if (!mounted) return;
      setState(() => _message = l.eventNoShowDisputeDone);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = eventNoShowFailureMessage(l, error, cityTime: _cityTime(l));
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
    final listing = ref.watch(listingProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: Text(l.eventNoShowTitle)),
      body: switch ((state, listing)) {
        (AsyncData(value: final result), AsyncData(value: final event)) =>
          RealtimeStatusBanner(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _content(result, event),
            ),
          ),
        (AsyncError(:final error), _) => _failure(
          eventNoShowFailureMessage(l, error, cityTime: _cityTime(l)),
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
              key: const Key('event-no-show-load-error'),
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

  Widget _content(EventNoShowOutput state, ListingOutput listing) {
    final l = context.l10n;
    final me = ref.watch(myProfileProvider).value?.id;
    final cityTime = noShowCityTime(listing, l);
    final phase = eventNoShowPhase(state);
    final organizer = me == state.organizerId;
    final dispute = switch (state.dispute) {
      final NoShowDisputeOutput value => value,
      _ => null,
    };
    final openDispute = eventNoShowDisputeOpen(state);
    final organizerMark = switch (state.organizerMark) {
      final NoShowMarkOutput mark => mark,
      _ => null,
    };
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        EventSummary(listing: listing),
        const SizedBox(height: 12),
        Text(l.eventNoShowIntro),
        const SizedBox(height: 8),
        Text(
          l.eventNoShowVotes(state.votes, state.threshold, state.registered),
          key: const Key('event-no-show-votes'),
        ),
        switch (phase) {
          EventNoShowPhase.before => Text(
            l.eventNoShowVoteOpensAt(cityTime(state.voteOpensAt!)),
            key: const Key('event-no-show-window-before'),
          ),
          EventNoShowPhase.open => Text(
            l.eventNoShowVoteClosesAt(cityTime(state.voteClosesAt!)),
            key: const Key('event-no-show-window-open'),
          ),
          EventNoShowPhase.closed => Text(
            l.eventNoShowVoteWindowClosed,
            key: const Key('event-no-show-window-closed'),
          ),
          EventNoShowPhase.unavailable => Text(
            l.eventNoShowUnavailable,
            key: const Key('event-no-show-window-unavailable'),
          ),
        },
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const Key('event-no-show-result')),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const Key('event-no-show-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        if (organizer)
          _organizer(state, cityTime, organizerMark, dispute, openDispute)
        else
          _participant(state, phase),
        const Divider(height: 32),
        Text(
          l.eventNoShowParticipantMarksTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (state.participantMarks.isEmpty)
          Text(l.eventNoShowParticipantMarksEmpty)
        else
          for (final mark in state.participantMarks)
            ListTile(
              key: Key('event-no-show-mark-${mark.id}'),
              leading: Icon(
                mark.removedAt == null ? Icons.person_off_outlined : Icons.undo,
              ),
              title: Text(
                mark.subjectId == me
                    ? l.noShowChargedYou
                    : l.eventNoShowParticipant,
              ),
              subtitle: Text(
                [
                  noShowMarkStatusName(l, mark),
                  if (mark.removedAt != null)
                    l.noShowRemovedAt(cityTime(mark.removedAt!)),
                  cityTime(mark.createdAt),
                ].join(' · '),
              ),
            ),
        const SizedBox(height: 8),
        Text(l.eventNoShowModerationNote),
        const SizedBox(height: 16),
        TextButton.icon(
          key: const Key('event-no-show-refresh'),
          onPressed: _busy ? null : () => unawaited(_refresh()),
          icon: const Icon(Icons.refresh),
          label: Text(l.noShowRefresh),
        ),
      ],
    );
  }

  /// The organiser: the charged no-show, its deadline and the dispute.
  Widget _organizer(
    EventNoShowOutput state,
    String Function(DateTime instant) cityTime,
    NoShowMarkOutput? organizerMark,
    NoShowDisputeOutput? dispute,
    bool openDispute,
  ) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (organizerMark != null) ...[
          Text(
            l.eventNoShowOrganizerCharged(cityTime(organizerMark.createdAt)),
            key: const Key('event-no-show-organizer-charged'),
          ),
          Text(
            noShowMarkStatusName(l, organizerMark),
            key: const Key('event-no-show-organizer-status'),
          ),
        ] else
          Text(
            l.eventNoShowOrganizerClear,
            key: const Key('event-no-show-organizer-clear'),
          ),
        if (state.canDispute) ...[
          if (state.disputeDeadline case final deadline?)
            Text(l.eventNoShowDisputeUntil(cityTime(deadline))),
          FilledButton.icon(
            key: const Key('event-no-show-dispute'),
            onPressed: _busy ? null : () => unawaited(_dispute()),
            icon: const Icon(Icons.gavel_outlined),
            label: Text(l.eventNoShowDisputeAction),
          ),
        ],
        if (openDispute)
          Text(
            l.eventNoShowDisputeOpen,
            key: const Key('event-no-show-dispute-open'),
          )
        else if (dispute != null)
          Text(
            l.eventNoShowDisputeResolved,
            key: const Key('event-no-show-dispute-closed'),
          ),
      ],
    );
  }

  /// A registered participant: the own vote and the lifted marks.
  Widget _participant(EventNoShowOutput state, EventNoShowPhase phase) {
    final l = context.l10n;
    if (state.voted) {
      return Text(l.eventNoShowVoted, key: const Key('event-no-show-voted'));
    }
    if (!state.canVote || phase != EventNoShowPhase.open) {
      return Text(l.eventNoShowNoVote, key: const Key('event-no-show-no-vote'));
    }
    return FilledButton.icon(
      key: const Key('event-no-show-vote'),
      onPressed: _busy ? null : () => unawaited(_vote()),
      icon: const Icon(Icons.event_busy_outlined),
      label: Text(l.eventNoShowVoteAction),
    );
  }
}
