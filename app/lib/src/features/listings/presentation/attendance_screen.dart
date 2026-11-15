import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart' show Options;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/api/interceptors.dart' show idempotencyKeyHeader;
import '../../../core/api/mutation_keys.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/realtime/realtime_status_view.dart';
import '../../profile/application/my_profile.dart';
import '../application/attendance.dart';
import '../application/attendance_config.dart';
import '../application/listings.dart';
import '../domain/attendance.dart';
import 'event_screen.dart' show EventSummary;
import 'listings_screens.dart' show listingFailureMessage;

/// Attendance of one event.
///
/// The role decides the screen: the author controls the mode, shows a
/// rotating code or scans participants and manages their marks; a
/// participant marks themselves or shows a personal code.
class EventAttendanceScreen extends ConsumerWidget {
  const EventAttendanceScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final listing = ref.watch(listingProvider(id));
    return listing.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l.attendanceTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(l.attendanceTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(listingFailureMessage(l, error)),
              TextButton(
                onPressed: () => ref.invalidate(listingProvider(id)),
                child: Text(l.errorRetry),
              ),
            ],
          ),
        ),
      ),
      data: (item) {
        if (item.kind != 'event') {
          return Scaffold(
            appBar: AppBar(title: Text(l.attendanceTitle)),
            body: Center(child: Text(l.attendanceUnavailable)),
          );
        }
        // The role depends on the profile: showing the participant screen
        // to the author for a moment would offer the wrong actions.
        final profile = user;
        if (profile == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l.attendanceTitle)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (item.authorId == profile.id) {
          return OrganizerAttendanceScreen(item: item);
        }
        return ParticipantAttendanceScreen(item: item);
      },
    );
  }
}

/// The action of an event author: open the attendance controls.
class EventAttendanceOwnerAction extends StatelessWidget {
  const EventAttendanceOwnerAction({required this.item, super.key});

  final ListingOutput item;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('event-attendance-manage'),
        onPressed: () => context.push('/event/${item.id}/attendance'),
        icon: const Icon(Icons.qr_code_2),
        label: Text(l.attendanceManageAction),
      ),
    );
  }
}

/// The action of a participant: mark the attendance of the event.
class EventAttendanceParticipantAction extends StatelessWidget {
  const EventAttendanceParticipantAction({required this.item, super.key});

  final ListingOutput item;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('event-attendance-open'),
        onPressed: () => context.push('/event/${item.id}/attendance'),
        icon: const Icon(Icons.how_to_reg_outlined),
        label: Text(l.attendanceOpenAction),
      ),
    );
  }
}

/// The organiser's controls: the mode, the rotating codes and the mark list.
///
/// The list is reloaded from the server on every realtime wakeup and on the
/// reload of a reconnected channel, so another device and a missed
/// publication never leave it out of date.
class OrganizerAttendanceScreen extends ConsumerStatefulWidget {
  const OrganizerAttendanceScreen({required this.item, super.key});

  final ListingOutput item;

  @override
  ConsumerState<OrganizerAttendanceScreen> createState() =>
      _OrganizerAttendanceScreenState();
}

class _OrganizerAttendanceScreenState
    extends ConsumerState<OrganizerAttendanceScreen> {
  final _keys = MutationKeys();
  final _scanController = TextEditingController();
  Timer? _ticker;
  bool _busy = false;
  String? _error;
  String? _result;

  String get _listingId => widget.item.id;

  @override
  void initState() {
    super.initState();
    // Rebuilds once a second: the window phase changes with time and the
    // countdown of the rotating code shortens.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scanController.dispose();
    super.dispose();
  }

  String _cityTime(DateTime instant) =>
      attendanceCityTime(widget.item, context.l10n)(instant);

  String _failure(Object error) =>
      attendanceFailureMessage(context.l10n, error, cityTime: _cityTime);

  Future<void> _setMode(AttendanceMode mode) async {
    final current = ref.read(organizerAttendanceProvider(_listingId)).value;
    if (_busy || current == null || current.mode == mode) return;
    final intent = 'mode:${mode.toJson()}';
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await ref
          .read(organizerAttendanceProvider(_listingId).notifier)
          .setMode(mode, idempotencyKey: _keys.of(intent));
      _keys.done(intent);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final l = context.l10n;
    final code = _scanController.text.trim();
    if (_busy) return;
    if (code.isEmpty) {
      setState(() => _error = l.attendanceCodeRequired);
      return;
    }
    final intent = 'scan:$code';
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final output = await ref
          .read(organizerAttendanceProvider(_listingId).notifier)
          .scan(code, idempotencyKey: _keys.of(intent));
      _keys.done(intent);
      if (!mounted) return;
      setState(() {
        _scanController.clear();
        _result = output.result == AttendanceOutputResult.alreadyMarked
            ? l.attendanceScanAlreadyMarked(output.participantName)
            : l.attendanceScanMarked(output.participantName);
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AttendanceItemOutput item) async {
    if (_busy) return;
    final intent = 'remove:${item.id}';
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await ref
          .read(organizerAttendanceProvider(_listingId).notifier)
          .remove(item.participantId, idempotencyKey: _keys.of(intent));
      _keys.done(intent);
      if (mounted) {
        setState(() => _result = context.l10n.attendanceRemovedDone);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final config = ref.watch(attendanceConfigProvider);
    final window = attendanceWindow(
      widget.item,
      opensBefore: config.opensBefore,
    );
    final phase = window == null
        ? AttendancePhase.after
        : attendancePhase(window, clock.now());
    return Scaffold(
      appBar: AppBar(title: Text(l.attendanceTitle)),
      body: RealtimeStatusBanner(
        child: ref
            .watch(organizerAttendanceProvider(_listingId))
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _FailureView(
                message: _failure(error),
                onRetry: () =>
                    ref.invalidate(organizerAttendanceProvider(_listingId)),
              ),
              data: (list) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  EventSummary(listing: widget.item),
                  if (window != null)
                    _WindowNotice(
                      phase: phase,
                      window: window,
                      cityTime: _cityTime,
                    ),
                  if (_result != null)
                    Text(_result!, key: const Key('attendance-result')),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const Key('attendance-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  Text(
                    l.attendanceModeTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        key: const Key('attendance-mode-self'),
                        label: Text(l.attendanceModeSelf),
                        selected: attendanceIsSelf(list.mode),
                        onSelected: _busy
                            ? null
                            : (_) => _setMode(AttendanceMode.self),
                      ),
                      ChoiceChip(
                        key: const Key('attendance-mode-scan'),
                        label: Text(l.attendanceModeScan),
                        selected: attendanceIsScan(list.mode),
                        onSelected: _busy
                            ? null
                            : (_) => _setMode(AttendanceMode.scan),
                      ),
                    ],
                  ),
                  Text(
                    attendanceIsScan(list.mode)
                        ? l.attendanceModeScanHint
                        : l.attendanceModeSelfHint,
                    key: const Key('attendance-mode-hint'),
                  ),
                  if (phase == AttendancePhase.open) ...[
                    const SizedBox(height: 8),
                    if (attendanceIsSelf(list.mode))
                      _AttendanceCodeCard(
                        listingId: _listingId,
                        organizer: true,
                        onFailureMessage: _failure,
                      )
                    else if (attendanceIsScan(list.mode))
                      _scanField(l),
                  ],
                  const Divider(height: 32),
                  Text(
                    l.attendanceListTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Row(
                    children: [
                      Text(
                        l.attendanceListCount(list.markedCount),
                        key: const Key('attendance-marked-count'),
                      ),
                      const Spacer(),
                      TextButton(
                        key: const Key('attendance-refresh'),
                        onPressed: () => ref
                            .read(
                              organizerAttendanceProvider(_listingId).notifier,
                            )
                            .sync(),
                        child: Text(l.attendanceRefreshList),
                      ),
                    ],
                  ),
                  if (list.items.isEmpty) Text(l.attendanceListEmpty),
                  for (final item in attendanceSortedItems(list.items))
                    _MarkTile(
                      item: item,
                      cityTime: _cityTime,
                      busy: _busy,
                      onRemove: () => _remove(item),
                    ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _scanField(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l.attendanceScanHint),
      TextField(
        key: const Key('attendance-scan-code'),
        controller: _scanController,
        maxLength: 1024,
        decoration: InputDecoration(
          labelText: l.attendanceParticipantCodeLabel,
        ),
        onSubmitted: (_) => unawaited(_scan()),
      ),
      FilledButton(
        key: const Key('attendance-scan-submit'),
        onPressed: _busy ? null : () => unawaited(_scan()),
        child: Text(l.attendanceSubmitScan),
      ),
    ],
  );
}

/// The participant's part: mark themselves with the organiser's code or show
/// the personal code that the organiser scans.
class ParticipantAttendanceScreen extends ConsumerStatefulWidget {
  const ParticipantAttendanceScreen({required this.item, super.key});

  final ListingOutput item;

  @override
  ConsumerState<ParticipantAttendanceScreen> createState() =>
      _ParticipantAttendanceScreenState();
}

class _ParticipantAttendanceScreenState
    extends ConsumerState<ParticipantAttendanceScreen> {
  final _keys = MutationKeys();
  final _codeController = TextEditingController();
  Timer? _ticker;
  bool _busy = false;
  String? _error;
  String? _result;

  String get _listingId => widget.item.id;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  String _cityTime(DateTime instant) =>
      attendanceCityTime(widget.item, context.l10n)(instant);

  String _failure(Object error) =>
      attendanceFailureMessage(context.l10n, error, cityTime: _cityTime);

  Future<void> _markSelf() async {
    final l = context.l10n;
    final code = _codeController.text.trim();
    if (_busy) return;
    if (code.isEmpty) {
      setState(() => _error = l.attendanceCodeRequired);
      return;
    }
    // The same code keeps the same key while the user repeats the attempt,
    // so a repeat after a dropped connection is applied once by the server.
    final intent = 'self:$code';
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final output = await ref
          .read(campusApiProvider)
          .eventAttendance
          .checkInEvent(
            listingId: _listingId,
            body: AttendanceCodeInput(code: code),
            options: Options(headers: {idempotencyKeyHeader: _keys.of(intent)}),
          );
      _keys.done(intent);
      if (!mounted) return;
      setState(() {
        _codeController.clear();
        _result = output.result == AttendanceOutputResult.alreadyMarked
            ? l.attendanceSelfAlreadyMarked
            : l.attendanceSelfMarked;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final config = ref.watch(attendanceConfigProvider);
    final window = attendanceWindow(
      widget.item,
      opensBefore: config.opensBefore,
    );
    final phase = window == null
        ? AttendancePhase.after
        : attendancePhase(window, clock.now());
    final mode = listingAttendanceMode(widget.item);
    return Scaffold(
      appBar: AppBar(title: Text(l.attendanceTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EventSummary(listing: widget.item),
          if (window != null)
            _WindowNotice(phase: phase, window: window, cityTime: _cityTime),
          if (_result != null)
            Text(_result!, key: const Key('attendance-result')),
          if (_error != null)
            Text(
              _error!,
              key: const Key('attendance-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (phase == AttendancePhase.open) ...[
            if (attendanceIsSelf(mode)) ...[
              Text(l.attendanceSelfHint),
              TextField(
                key: const Key('attendance-self-code'),
                controller: _codeController,
                maxLength: 1024,
                decoration: InputDecoration(
                  labelText: l.attendanceOrganizerCodeLabel,
                ),
                onSubmitted: (_) => unawaited(_markSelf()),
              ),
              FilledButton(
                key: const Key('attendance-self-submit'),
                onPressed: _busy ? null : () => unawaited(_markSelf()),
                child: Text(l.attendanceSubmitSelf),
              ),
            ] else if (attendanceIsScan(mode))
              _AttendanceCodeCard(
                listingId: _listingId,
                organizer: false,
                onFailureMessage: _failure,
              )
            else
              Text(
                l.attendanceModeMissing,
                key: const Key('attendance-mode-missing'),
              ),
          ],
          const SizedBox(height: 16),
          TextButton(
            key: const Key('attendance-reload'),
            onPressed: () => ref.invalidate(listingProvider(_listingId)),
            child: Text(l.attendanceRefreshList),
          ),
        ],
      ),
    );
  }
}

/// The rotating code of the event: shown by the organiser or by a participant.
class _AttendanceCodeCard extends ConsumerWidget {
  const _AttendanceCodeCard({
    required this.listingId,
    required this.organizer,
    this.onFailureMessage,
  });

  final String listingId;
  final bool organizer;

  /// Overrides the message of a failed request; the organiser screen passes
  /// its own formatter, the participant screen its own.
  final String Function(Object error)? onFailureMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final provider = attendanceCodeProvider((listingId, organizer));
    return ref
        .watch(provider)
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
          error: (error, _) => Row(
            children: [
              Flexible(
                child: Text(
                  onFailureMessage?.call(error) ?? apiFailureMessage(l, error),
                  key: const Key('attendance-code-error'),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(provider),
                child: Text(l.errorRetry),
              ),
            ],
          ),
          data: (state) {
            final remaining = state.remainingAt(clock.now());
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  organizer
                      ? l.attendanceCodeTitle
                      : l.attendanceParticipantCodeTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  organizer
                      ? l.attendanceCodeHint
                      : l.attendanceParticipantCodeHint,
                ),
                SelectableText(
                  state.code.code,
                  key: const Key('attendance-code'),
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                Text(
                  l.attendanceCodeExpires(remaining.inSeconds),
                  key: const Key('attendance-code-expires'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      key: const Key('attendance-code-copy'),
                      onPressed: () => _copy(context, state.code.code),
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(l.attendanceCodeCopy),
                    ),
                    TextButton.icon(
                      key: const Key('attendance-code-refresh'),
                      onPressed: () => ref.invalidate(provider),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(l.attendanceCodeRefresh),
                    ),
                  ],
                ),
              ],
            );
          },
        );
  }

  Future<void> _copy(BuildContext context, String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
    } on Object {
      // A platform without a clipboard still shows the selectable code.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(context.l10n.attendanceCodeCopied)));
  }
}

/// The state of the attendance window in the city of the event.
class _WindowNotice extends StatelessWidget {
  const _WindowNotice({
    required this.phase,
    required this.window,
    required this.cityTime,
  });

  final AttendancePhase phase;
  final AttendanceWindow window;
  final String Function(DateTime instant) cityTime;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = switch (phase) {
      AttendancePhase.before => l.attendanceWindowBefore(
        cityTime(window.opensAt),
      ),
      AttendancePhase.open => l.attendanceWindowOpen(cityTime(window.closesAt)),
      AttendancePhase.after => l.attendanceWindowAfter,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, key: Key('attendance-window-${phase.name}')),
    );
  }
}

/// One mark of the organiser's list.
class _MarkTile extends StatelessWidget {
  const _MarkTile({
    required this.item,
    required this.cityTime,
    required this.busy,
    required this.onRemove,
  });

  final AttendanceItemOutput item;
  final String Function(DateTime instant) cityTime;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final removed = item.removedAt != null;
    return ListTile(
      key: Key('attendance-item-${item.id}'),
      title: Text(item.participantName),
      subtitle: Text(
        [
          attendanceMethodName(l, item.method),
          cityTime(item.markedAt),
          if (!item.registered) l.attendanceNoLongerRegistered,
          if (removed) l.attendanceRemoved,
        ].join(' · '),
      ),
      trailing: removed
          ? null
          : IconButton(
              key: Key('attendance-remove-${item.id}'),
              tooltip: l.attendanceRemove,
              onPressed: busy ? null : onRemove,
              icon: const Icon(Icons.person_remove_outlined),
            ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          TextButton(onPressed: onRetry, child: Text(l.errorRetry)),
        ],
      ),
    );
  }
}
