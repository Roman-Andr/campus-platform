import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart' show Options;
import 'package:flutter/foundation.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/interceptors.dart' show idempotencyKeyHeader;
import '../../../core/auth/auth_session.dart';
import '../../../core/realtime/realtime_channel.dart';
import '../../../core/realtime/realtime_models.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../profile/application/my_profile.dart';
import '../domain/attendance.dart';

part 'attendance.g.dart';

// The HTTP transport already retries transient failures; an expected refusal
// must reach the screen at once with an explicit retry action.
Duration? attendanceRetry(int retryCount, Object error) => null;

/// Keys of mutating attendance requests that the user may repeat.
///
/// A repeat after a dropped connection must send the key of the same intent
/// (`Idempotency-Key`), so the server applies the mark once. A different
/// intent (another code, mode or participant) starts a new key, and a
/// successful operation drops it.
class AttendanceKeys {
  AttendanceKeys({String Function()? generate})
    : _generate = generate ?? const Uuid().v7;

  final String Function() _generate;
  String? _intent;
  String? _key;

  /// The key of [intent], created on first use and kept while it repeats.
  String of(String intent) {
    if (_intent != intent || _key == null) {
      _intent = intent;
      _key = _generate();
    }
    return _key!;
  }

  /// Forgets the key of [intent] once it succeeded.
  void done(String intent) {
    if (_intent != intent) return;
    _intent = null;
    _key = null;
  }
}

/// A rotating attendance code and the moment the client received it.
///
/// The server reports both the issue and the expiry instants, so the
/// remaining time is a duration from the receipt: a skewed device clock
/// neither extends nor cuts the code short.
@immutable
class AttendanceCodeState {
  const AttendanceCodeState({required this.code, required this.receivedAt});

  final AttendanceCodeOutput code;

  /// When the response was received, by the device clock.
  final DateTime receivedAt;

  /// How long the code is still valid at [now].
  Duration remainingAt(DateTime now) {
    final left = attendanceCodeLifetime(code) - now.difference(receivedAt);
    return left.isNegative ? Duration.zero : left;
  }
}

/// The current rotating code of the event: the organiser's self-mark code or
/// the personal code of a participant, depending on [request].
///
/// A new code is requested before the current one expires, so the screen
/// never shows a code that the server would reject as expired. The screen
/// watches this provider only inside the attendance window and only in the
/// matching mode; the server refuses a code of the other mode.
@Riverpod(retry: attendanceRetry)
Future<AttendanceCodeState> attendanceCode(
  Ref ref,
  (String, bool) request,
) async {
  final (listingId, organizer) = request;
  final api = ref.read(campusApiProvider).eventAttendance;
  final code = organizer
      ? await api.issueEventAttendanceQr(listingId: listingId)
      : await api.issueEventAttendanceCode(listingId: listingId);
  final refreshAfter = attendanceCodeRefreshAfter(code);
  if (refreshAfter > Duration.zero) {
    final timer = Timer(refreshAfter, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return AttendanceCodeState(code: code, receivedAt: clock.now());
}

/// The organiser's view of the marks: the chosen mode, every mark of the
/// event and the live updates of the list.
///
/// The list endpoint is the authoritative state: a realtime publication and
/// the reload of a reconnected channel only wake [sync] up, which loads the
/// whole list again, so a missed publication never loses or duplicates a
/// mark.
@Riverpod(retry: attendanceRetry)
class OrganizerAttendance extends _$OrganizerAttendance {
  RealtimeSubscription? _subscription;
  final _events = <StreamSubscription<Object?>>[];
  bool _syncing = false;
  bool _syncAgain = false;

  /// Tells a subscription of a closed screen from one of a reopened one.
  int _generation = 0;

  @override
  Future<AttendanceListOutput> build(String listingId) async {
    final list = await _load();
    ref.onDispose(() => unawaited(_stopRealtime()));
    unawaited(_watchRealtime());
    return list;
  }

  /// Reloads the whole list from the server.
  ///
  /// Also the reload callback of the personal channel: it runs before the
  /// first subscription and after a reconnect or a lost history, so the
  /// list shown after a reconnect matches the server.
  Future<void> sync() async {
    if (!ref.mounted) return;
    // A wakeup that arrives while the list is loading must not be dropped:
    // the request in flight may have been sent before the mark was written.
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        try {
          final list = await _load();
          if (!ref.mounted) return;
          state = AsyncData(list);
        } on Object {
          // Kept as is: the realtime banner reports the connection, and the
          // next wakeup, the refresh button or the screen reopening retries.
          break;
        }
      } while (_syncAgain && ref.mounted);
    } finally {
      _syncing = false;
    }
  }

  /// Switches how participants are marked; every taken mark stays.
  Future<AttendanceModeOutput> setMode(
    AttendanceMode mode, {
    required String idempotencyKey,
  }) async {
    final output = await ref
        .read(campusApiProvider)
        .eventAttendance
        .setEventAttendanceMode(
          listingId: listingId,
          body: AttendanceModeInput(mode: mode),
          options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
        );
    final current = state.value;
    if (!ref.mounted || current == null) return output;
    state = AsyncData(
      AttendanceListOutput(
        listingId: current.listingId,
        mode: output.mode,
        version: output.version,
        items: current.items,
        markedCount: current.markedCount,
        serverTime: current.serverTime,
      ),
    );
    return output;
  }

  /// Marks the participant whose personal code the organiser supplied.
  Future<AttendanceOutput> scan(
    String code, {
    required String idempotencyKey,
  }) async {
    final output = await ref
        .read(campusApiProvider)
        .eventAttendance
        .scanEventAttendance(
          listingId: listingId,
          body: AttendanceCodeInput(code: code),
          options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
        );
    await sync();
    return output;
  }

  /// Removes one participant's mark; the row stays as removed.
  Future<AttendanceOutput> remove(
    String participantId, {
    required String idempotencyKey,
  }) async {
    final output = await ref
        .read(campusApiProvider)
        .eventAttendance
        .removeEventAttendance(
          listingId: listingId,
          participantId: participantId,
          options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
        );
    await sync();
    return output;
  }

  Future<AttendanceListOutput> _load() => ref
      .read(campusApiProvider)
      .eventAttendance
      .listEventAttendance(listingId: listingId);

  /// Subscribes to the personal channel, which carries the wakeups of the
  /// organiser's events.
  Future<void> _watchRealtime() async {
    if (ref.read(authStatusProvider).value !=
        AuthenticationStatus.authenticated) {
      return;
    }
    final generation = ++_generation;
    try {
      final user = await ref.read(myProfileProvider.future);
      if (!ref.mounted || generation != _generation || user == null) return;
      final subscription = ref
          .read(realtimeServiceProvider.notifier)
          .subscribe(RealtimeChannel.personal(user.id), reload: sync);
      if (!ref.mounted || generation != _generation) {
        await subscription.close();
        return;
      }
      _events.add(subscription.events.listen(_onEvent));
      _subscription = subscription;
    } on Object {
      // Realtime is a wakeup only: the list works without it and the screen
      // can refresh it explicitly.
    }
  }

  /// Reloads the list after a publication of this event.
  ///
  /// The personal channel also carries the other events of the organiser, so
  /// a publication with another `listing_id` is ignored. A publication whose
  /// payload cannot be read still wakes the list up: a lost wakeup is worse
  /// than one extra request.
  void _onEvent(RealtimeEvent event) {
    final data = event.data;
    if (data is Map<String, Object?>) {
      final id = data['listing_id'];
      if (id is String && id != listingId) return;
    }
    unawaited(sync());
  }

  Future<void> _stopRealtime() async {
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
