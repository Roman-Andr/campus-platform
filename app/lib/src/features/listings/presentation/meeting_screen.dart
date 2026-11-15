import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../../core/widgets/city_date_time_picker.dart';
import '../../profile/application/my_profile.dart';
import '../../qr/presentation/qr_summary.dart';
import '../application/listings.dart';
import '../application/meeting.dart';
import '../domain/reservation.dart';
import 'cancellation.dart';
import 'no_meeting_screen.dart';

/// Route of the meeting of interaction [interactionId] of listing [listingId].
String meetingPath(String listingId, String interactionId) =>
    '/listings/$listingId/interactions/$interactionId/meeting';

String _meetingTime(
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

/// The effective meeting and the pending proposal of an accepted
/// interaction, with a way to open its screen.
class MeetingSummary extends ConsumerWidget {
  const MeetingSummary({
    required this.item,
    required this.timezone,
    this.city,
    this.showOpen = true,
    super.key,
  });

  final InteractionOutput item;
  final String timezone;

  /// City name for the time zone note; the zone itself is a fallback.
  final String? city;
  final bool showOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (item.status != InteractionStatus.accepted) {
      return const SizedBox.shrink();
    }
    final meeting = meetingOf(item);
    final me = ref.watch(myProfileProvider).value?.id;
    final mine = meeting != null && meetingProposalIsMine(meeting, me);
    final proposal = meeting != null && meetingHasProposal(meeting);
    final scheduledAt = meeting?.scheduledAt;
    final proposedAt = meeting?.proposedAt;
    final location = meeting?.location;
    final online = meeting?.online ?? false;
    final proposedLocation = meeting?.proposedLocation;
    final cityLabel = city ?? timezone;
    return Card(
      key: Key('meeting-${item.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l.meetingTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            if (scheduledAt != null) ...[
              Text(l.meetingCurrent),
              Text(_meetingTime(l, scheduledAt, timezone, cityLabel)),
              if (location != null)
                Text(l.meetingPlace(location))
              else if (online)
                Text(l.meetingOnline),
            ] else if (!proposal)
              Text(l.meetingNotScheduled),
            if (proposal) ...[
              Text(
                mine ? l.meetingYourProposal : l.meetingNewProposal,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(_meetingTime(l, proposedAt!, timezone, cityLabel)),
              if (proposedLocation != null)
                Text(l.meetingPlace(proposedLocation))
              else if (online)
                Text(l.meetingOnline),
              Text(
                mine ? l.meetingAwaitingAnswer : l.meetingAwaitingYourAnswer,
                key: Key('meeting-awaiting-${item.id}'),
              ),
            ],
            // An accepted item reservation runs on its own deadline until a
            // meeting is scheduled; the meeting then extends it.
            if (item.reservationDueAt != null) ...[
              const Divider(),
              if (scheduledAt != null)
                Text(
                  l.reservationUntilMeeting(
                    _meetingTime(l, scheduledAt, timezone, cityLabel),
                  ),
                  key: Key('reservation-until-${item.id}'),
                )
              else ...[
                _ReservationCountdown(
                  item: item,
                  key: Key('reservation-left-${item.id}'),
                ),
                Text(
                  l.reservationMeetingHint,
                  key: Key('reservation-hint-${item.id}'),
                ),
              ],
            ],
            if (showOpen)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('meeting-open-${item.id}'),
                  onPressed: () =>
                      context.push(meetingPath(item.listingId, item.id)),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l.meetingOpen),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The remaining hold time, updated once a minute. When the deadline passes,
/// the authoritative interaction is fetched again, so a server-side release
/// replaces the ended hold with its final status and reason.
class _ReservationCountdown extends ConsumerStatefulWidget {
  const _ReservationCountdown({required this.item, super.key});

  final InteractionOutput item;

  @override
  ConsumerState<_ReservationCountdown> createState() =>
      _ReservationCountdownState();
}

class _ReservationCountdownState extends ConsumerState<_ReservationCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didUpdateWidget(_ReservationCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.reservationDueAt != widget.item.reservationDueAt) {
      _expired = false;
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A background app may miss or delay timers; on return the remaining time
    // is measured again and an expired hold triggers the refresh.
    if (state == AppLifecycleState.resumed) {
      _tick();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    final now = clock.now();
    final left = reservationLeft(widget.item, now: now);
    if (left <= Duration.zero) {
      _expire();
      return;
    }
    final nextMinute = Duration(
      seconds: 60 - now.second,
      milliseconds: -now.millisecond,
      microseconds: -now.microsecond,
    );
    _timer = Timer(nextMinute < left ? nextMinute : left, _tick);
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    _schedule();
  }

  void _expire() {
    _timer?.cancel();
    if (_expired) return;
    _expired = true;
    // The providers cannot be changed while the tree is building; the frame
    // that shows the ended hold also starts the authoritative refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshListings(ref);
      ref.invalidate(
        meetingInteractionProvider((widget.item.listingId, widget.item.id)),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      Text(reservationTimeLeft(context.l10n, reservationLeft(widget.item)));
}

/// The meeting of one interaction: confirms a proposal, reschedules it and
/// lets the participant withdraw the interaction.
class MeetingScreen extends ConsumerStatefulWidget {
  const MeetingScreen({
    required this.listingId,
    required this.interactionId,
    super.key,
  });

  final String listingId;
  final String interactionId;

  @override
  ConsumerState<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends ConsumerState<MeetingScreen> {
  bool _busy = false;
  bool _editing = false;
  String? _error;

  (String, String) get _ids => (widget.listingId, widget.interactionId);

  Future<void> _reload() async {
    final provider = meetingInteractionProvider(_ids);
    ref.invalidate(provider);
    refreshListings(ref);
    try {
      await ref.read(provider.future);
    } on Object {
      // The provider state carries the failure; the screen shows it.
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _accept(MeetingOutput meeting) async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(campusApiProvider)
          .listings
          .acceptMeeting(
            listingId: widget.listingId,
            interactionId: widget.interactionId,
            body: MeetingAcceptInput(version: meeting.version),
          );
      await _reload();
      _showMessage(l.meetingConfirmed);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = meetingFailureMessage(l, error));
        if (meetingIsStale(error)) await _reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(DateTime time, String location) async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(campusApiProvider)
          .listings
          .proposeMeeting(
            listingId: widget.listingId,
            interactionId: widget.interactionId,
            body: MeetingProposalInput(time: time, location: location),
          );
      if (!mounted) return;
      setState(() => _editing = false);
      await _reload();
      _showMessage(l.meetingProposalSent);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = meetingFailureMessage(l, error));
        if (meetingIsStale(error)) await _reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelInteraction() async {
    final l = context.l10n;
    InteractionCancellationPreview preview;
    try {
      preview = await loadInteractionCancellationPreview(
        ref,
        listingId: widget.listingId,
        interactionId: widget.interactionId,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = meetingFailureMessage(l, error));
      }
      return;
    }
    if (!mounted) return;
    if (!preview.allowed) {
      setState(() => _error = l.listingTransitionConflict);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.meetingCancelTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.meetingCancelBody),
            interactionCancellationWarning(context, l, preview),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.meetingCancelKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.meetingCancelConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(campusApiProvider)
          .listings
          .transitionInteraction(
            listingId: widget.listingId,
            interactionId: widget.interactionId,
            body: const TransitionInput(status: InteractionStatus.cancelled),
          );
      refreshListings(ref);
      if (mounted) context.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = meetingFailureMessage(l, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final interaction = ref.watch(meetingInteractionProvider(_ids));
    final listing = ref.watch(listingProvider(widget.listingId));
    final cities = ref.watch(citiesProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.meetingTitle)),
      body: switch ((interaction, listing)) {
        (AsyncData(value: final item), AsyncData(value: final listing)) =>
          _content(item, listing, cities),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => _failure(error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _failure(Object error) {
    final l = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error is MeetingUnavailable
                  ? l.meetingUnavailable
                  : meetingFailureMessage(l, error),
              key: const Key('meeting-load-error'),
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(meetingInteractionProvider(_ids)),
            child: Text(l.errorRetry),
          ),
        ],
      ),
    );
  }

  Widget _content(
    InteractionOutput item,
    ListingOutput listing,
    List<CityOut>? cities,
  ) {
    final l = context.l10n;
    final meeting = meetingOf(item);
    final me = ref.watch(myProfileProvider).value?.id;
    final city =
        cities?.where((city) => city.id == listing.cityId).firstOrNull?.name ??
        listing.cityTimezone;
    if (item.status != InteractionStatus.accepted) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l.meetingStateConflict,
            key: const Key('meeting-state'),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    final proposal = meeting != null && meetingHasProposal(meeting);
    final mine = meeting != null && meetingProposalIsMine(meeting, me);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              key: const Key('meeting-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        MeetingSummary(
          item: item,
          timezone: listing.cityTimezone,
          city: city,
          showOpen: false,
        ),
        NoMeetingSummary(item: item, kind: listing.kind),
        QrConfirmationSummary(item: item, kind: listing.kind),
        if (_editing)
          MeetingProposalForm(
            initialTime: meetingInitialTime(meeting),
            timezone: listing.cityTimezone,
            city: city,
            busy: _busy,
            onSubmit: _propose,
            onCancel: () => setState(() => _editing = false),
          )
        else ...[
          if (meeting != null && proposal && !mine)
            FilledButton.icon(
              key: const Key('meeting-accept'),
              onPressed: _busy ? null : () => _accept(meeting),
              icon: const Icon(Icons.check),
              label: Text(l.meetingAccept),
            ),
          if (meeting != null && proposal)
            TextButton(
              key: const Key('meeting-change'),
              onPressed: _busy ? null : () => setState(() => _editing = true),
              child: Text(l.meetingChangeProposal),
            )
          else
            FilledButton.icon(
              key: const Key('meeting-propose'),
              onPressed: _busy ? null : () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(
                meeting?.scheduledAt == null
                    ? l.meetingSuggest
                    : l.meetingReschedule,
              ),
            ),
          if (item.participantId == me)
            TextButton(
              key: const Key('meeting-cancel'),
              onPressed: _busy ? null : _cancelInteraction,
              child: Text(l.meetingCancelInteraction),
            ),
        ],
      ],
    );
  }
}

/// The proposal form: a time in the city zone, a place, and validation
/// against a time in the past.
class MeetingProposalForm extends StatefulWidget {
  const MeetingProposalForm({
    required this.initialTime,
    required this.timezone,
    required this.city,
    required this.onSubmit,
    required this.onCancel,
    this.busy = false,
    super.key,
  });

  final DateTime initialTime;
  final String timezone;
  final String city;
  final void Function(DateTime time, String location) onSubmit;
  final VoidCallback onCancel;
  final bool busy;

  @override
  State<MeetingProposalForm> createState() => _MeetingProposalFormState();
}

class _MeetingProposalFormState extends State<MeetingProposalForm> {
  late DateTime _time = widget.initialTime;
  final _place = TextEditingController();
  String? _timeError;
  String? _placeError;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  void _submit() {
    final l = context.l10n;
    final timeError = meetingTimeError(l, _time);
    final placeError = meetingPlaceError(l, _place.text);
    setState(() {
      _timeError = timeError;
      _placeError = placeError;
    });
    if (timeError != null || placeError != null) return;
    widget.onSubmit(_time, _place.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final now = tz.TZDateTime.from(clock.now(), cityLocation(widget.timezone));
    final firstDate = DateTime(now.year, now.month, now.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.meetingFormTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        CityDateTimePicker(
          value: _time,
          timezone: widget.timezone,
          city: widget.city,
          firstDate: firstDate,
          lastDate: firstDate.add(const Duration(days: 365)),
          onChanged: (value) => setState(() {
            _time = value;
            _timeError = null;
          }),
        ),
        if (_timeError != null)
          Text(
            _timeError!,
            key: const Key('meeting-time-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextField(
          key: const Key('meeting-place'),
          controller: _place,
          decoration: InputDecoration(labelText: l.meetingPlaceLabel),
          onChanged: (_) {
            if (_placeError != null) setState(() => _placeError = null);
          },
        ),
        if (_placeError != null)
          Text(
            _placeError!,
            key: const Key('meeting-place-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const Key('meeting-send'),
              onPressed: widget.busy ? null : _submit,
              child: Text(l.meetingSaveProposal),
            ),
            TextButton(
              key: const Key('meeting-form-cancel'),
              onPressed: widget.busy ? null : widget.onCancel,
              child: Text(l.meetingDismiss),
            ),
          ],
        ),
      ],
    );
  }
}
