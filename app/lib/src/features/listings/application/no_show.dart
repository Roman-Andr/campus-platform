import 'dart:async';

import 'package:dio/dio.dart' show Options;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/interceptors.dart' show idempotencyKeyHeader;
import '../../../core/auth/auth_session.dart';
import '../../../core/realtime/realtime_channel.dart';
import '../../../core/realtime/realtime_models.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../profile/application/my_profile.dart';
import 'listings.dart';

part 'no_show.g.dart';

/// Client-side parameters of the no-show rules (ТЗ, Приложение 4).
///
/// Values come from `--dart-define` at build time; they must match the
/// server's `CAMPUS_NO_SHOW_MARK_AFTER` and
/// `CAMPUS_NO_SHOW_REASON_MAX_LENGTH`. The screen itself takes the mark
/// window from the server response, so a drifting build parameter never
/// widens the window the server accepts.
class NoShowConfig {
  NoShowConfig({required this.markAfter, required this.reasonMaxLength})
    : assert(!markAfter.isNegative, 'a mark window cannot open earlier'),
      assert(reasonMaxLength > 0, 'a reason cannot be limited to nothing');

  factory NoShowConfig.fromEnvironment() => NoShowConfig(
    markAfter: const Duration(
      hours: int.fromEnvironment(
        'CAMPUS_NO_SHOW_MARK_AFTER_HOURS',
        defaultValue: 24,
      ),
    ),
    reasonMaxLength: const int.fromEnvironment(
      'CAMPUS_NO_SHOW_REASON_MAX_LENGTH',
      defaultValue: 500,
    ),
  );

  /// How long after the agreed meeting the server accepts a mark.
  final Duration markAfter;

  /// Longest reason the server accepts.
  final int reasonMaxLength;
}

@Riverpod(keepAlive: true)
NoShowConfig noShowConfig(Ref ref) => NoShowConfig.fromEnvironment();

/// The current result of a personal interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a mark made on another device, a
/// mutual allegation, a late QR lift and an automatic rule are never hidden
/// behind a stale response. A realtime publication only wakes [sync] up,
/// which loads the whole state again.
@Riverpod(retry: listingRetry)
class InteractionNoShow extends _$InteractionNoShow {
  bool _syncing = false;
  bool _syncAgain = false;

  @override
  Future<NoShowOutput> build((String, String) ids) async {
    final current = await _load();
    final wakeups = _PersonalWakeups(ref);
    ref.onDispose(() => unawaited(wakeups.stop()));
    unawaited(
      wakeups.start(
        reload: sync,
        onEvent: (event) => _onEvent(event, ids.$1, ids.$2),
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
          // wakeup, the refresh button or the reopening retries.
          break;
        }
      } while (_syncAgain && ref.mounted);
    } finally {
      _syncing = false;
    }
  }

  /// Marks that the meeting did not take place, or answers the other mark.
  ///
  /// The caller keeps [idempotencyKey] while repeating the same intent, so a
  /// repeat after a dropped connection is applied once by the server. The
  /// state is read back after both a success and a refusal: the server may
  /// have closed the window or opened a dispute meanwhile, and the screen
  /// must show that instead of the state it had.
  Future<NoShowOutput> mark({
    required String reason,
    required String idempotencyKey,
  }) async {
    final NoShowOutput output;
    try {
      output = await ref
          .read(campusApiProvider)
          .noShows
          .markInteractionNoShow(
            listingId: ids.$1,
            interactionId: ids.$2,
            body: NoShowReasonInput(reason: reason),
            options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
          );
    } on Object {
      await sync();
      rethrow;
    }
    _apply(output);
    await sync();
    return output;
  }

  void _apply(NoShowOutput output) {
    if (ref.mounted) state = AsyncData(output);
  }

  Future<NoShowOutput> _load() => ref
      .read(campusApiProvider)
      .noShows
      .interactionNoShow(listingId: ids.$1, interactionId: ids.$2);

  /// Reloads the state after a publication about this interaction.
  void _onEvent(RealtimeEvent event, String listingId, String interactionId) {
    if (!_wakeupMatches(
      event,
      listingId: listingId,
      interactionId: interactionId,
    )) {
      return;
    }
    unawaited(sync());
  }
}

/// Votes and marks of one event.
///
/// Like the personal state, it is reloaded after every attempt and woken by
/// the publications of the event, so a vote of another participant, the
/// organiser's dispute and the automatic marks appear without a restart.
@Riverpod(retry: listingRetry)
class EventNoShow extends _$EventNoShow {
  bool _syncing = false;
  bool _syncAgain = false;

  @override
  Future<EventNoShowOutput> build(String listingId) async {
    final current = await _load();
    final wakeups = _PersonalWakeups(ref);
    ref.onDispose(() => unawaited(wakeups.stop()));
    unawaited(
      wakeups.start(
        reload: sync,
        onEvent: (event) {
          if (_wakeupMatches(event, listingId: listingId)) unawaited(sync());
        },
      ),
    );
    return current;
  }

  /// Reloads votes and marks from the server; a failure keeps the shown state.
  Future<void> sync() async {
    if (!ref.mounted) return;
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
          break;
        }
      } while (_syncAgain && ref.mounted);
    } finally {
      _syncing = false;
    }
  }

  /// Votes that the event did not take place.
  Future<EventNoShowOutput> vote({required String idempotencyKey}) async {
    final output = await _attempt(
      () => ref
          .read(campusApiProvider)
          .eventNoShows
          .voteEvent(
            listingId: listingId,
            options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
          ),
    );
    return output;
  }

  /// Disputes the no-show charged to the organiser by the vote.
  Future<EventNoShowOutput> dispute({required String idempotencyKey}) async {
    final output = await _attempt(
      () => ref
          .read(campusApiProvider)
          .eventNoShows
          .disputeEventNoShowEndpoint(
            listingId: listingId,
            options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
          ),
    );
    return output;
  }

  /// Runs a mutation and rereads the authoritative state after it either way.
  Future<EventNoShowOutput> _attempt(
    Future<EventNoShowOutput> Function() request,
  ) async {
    final EventNoShowOutput output;
    try {
      output = await request();
    } on Object {
      // A vote that lost the race with the automatic rule or a closed window
      // must leave the current result on the screen, not the old one.
      await sync();
      rethrow;
    }
    if (ref.mounted) state = AsyncData(output);
    await sync();
    return output;
  }

  Future<EventNoShowOutput> _load() => ref
      .read(campusApiProvider)
      .eventNoShows
      .eventNoShow(listingId: listingId);
}

/// Whether a publication of the personal channel is about the watched state.
///
/// The personal channel also carries the other listings of the user, so a
/// publication with another `listing_id` (or `interaction_id`, when it has
/// one) is ignored. A publication without a readable payload still wakes the
/// screen up: a lost wakeup is worse than one extra request.
bool _wakeupMatches(
  RealtimeEvent event, {
  required String listingId,
  String? interactionId,
}) {
  final data = event.data;
  if (data is! Map<String, Object?>) return true;
  final otherListing = data['listing_id'];
  if (otherListing is String && otherListing != listingId) return false;
  final otherInteraction = data['interaction_id'];
  if (interactionId != null &&
      otherInteraction is String &&
      otherInteraction != interactionId) {
    return false;
  }
  return true;
}

/// Subscribes to the wakeups of the personal channel and reloads on them.
///
/// The subscription is a hint only: the state works without it and the
/// refresh action reloads it explicitly.
class _PersonalWakeups {
  _PersonalWakeups(this._ref);

  final Ref _ref;
  RealtimeSubscription? _subscription;
  final _events = <StreamSubscription<Object?>>[];
  bool _started = false;

  /// Tells a subscription of a closed provider from one of a reopened one.
  int _generation = 0;

  Future<void> start({
    required Future<void> Function() reload,
    required void Function(RealtimeEvent event) onEvent,
  }) async {
    if (_started) return;
    _started = true;
    if (_ref.read(authStatusProvider).value !=
        AuthenticationStatus.authenticated) {
      return;
    }
    final generation = ++_generation;
    try {
      final user = await _ref.read(myProfileProvider.future);
      if (!_ref.mounted || generation != _generation || user == null) return;
      final subscription = _ref
          .read(realtimeServiceProvider.notifier)
          .subscribe(RealtimeChannel.personal(user.id), reload: reload);
      if (!_ref.mounted || generation != _generation) {
        await subscription.close();
        return;
      }
      _events.add(subscription.events.listen(onEvent));
      _subscription = subscription;
    } on Object {
      // Realtime is a wakeup only: the state works without it and the screen
      // can refresh it explicitly.
    }
  }

  Future<void> stop() async {
    _generation++;
    final events = _events.toList();
    final subscription = _subscription;
    _events.clear();
    _subscription = null;
    for (final listener in events) {
      await listener.cancel();
    }
    await subscription?.close();
  }
}
