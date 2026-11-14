import 'dart:convert';

import 'package:clock/clock.dart';

import 'realtime_channel.dart';
import 'realtime_failure.dart';

/// The connection phase of the realtime client.
enum RealtimeConnectionPhase {
  disconnected,
  connecting,
  reconnecting,
  connected,
}

/// The subscription phase of one channel.
enum RealtimeSubscriptionPhase { subscribing, subscribed, unsubscribed }

/// The stream position a subscription recovers from.
class RealtimePosition {
  const RealtimePosition({required this.epoch, required this.offset});

  final String epoch;
  final int offset;
}

/// The position returned by the recovery API and, when a position was
/// requested, the publications after it.
class RealtimeRecovery {
  const RealtimeRecovery({
    required this.position,
    this.publications = const [],
  });

  final RealtimePosition position;
  final List<RealtimeEvent> publications;
}

/// A publication delivered by Centrifugo.
class RealtimeEvent {
  RealtimeEvent({
    required this.channel,
    required this.offset,
    required this.data,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? clock.now(),
       occurredAt = _occurredAt(data);

  /// Decodes a publication payload.
  ///
  /// Real-time publications carry JSON. A payload that is not JSON is kept
  /// as text instead of failing the whole event: a future server may add a
  /// transport this client does not know yet.
  factory RealtimeEvent.fromBytes({
    required String channel,
    required int offset,
    required List<int> bytes,
    DateTime? receivedAt,
  }) {
    final text = utf8.decode(bytes, allowMalformed: true);
    Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      data = text;
    }
    return RealtimeEvent(
      channel: channel,
      offset: offset,
      data: data,
      receivedAt: receivedAt,
    );
  }

  /// The channel that delivered the event.
  final String channel;

  /// The server-assigned stream position; used to drop duplicates.
  final int offset;

  /// The decoded JSON payload.
  final Object? data;

  /// When the client received the event, in UTC.
  final DateTime receivedAt;

  /// The moment the payload describes, when it carries an RFC 3339
  /// `created_at`; otherwise `null`.
  final DateTime? occurredAt;

  static DateTime? _occurredAt(Object? data) {
    if (data is! Map<String, Object?>) return null;
    final raw = data['created_at'];
    if (raw is! String) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  String toString() =>
      'RealtimeEvent($channel, offset: $offset, occurredAt: $occurredAt)';
}

/// The aggregated state of the realtime client.
class RealtimeStatus {
  const RealtimeStatus({
    this.phase = RealtimeConnectionPhase.disconnected,
    this.stale = false,
    this.failure,
    this.activeSubscriptions = 0,
    this.lastEventAt,
  });

  final RealtimeConnectionPhase phase;

  /// Whether subscribed data may be out of date, e.g. right after the app
  /// returned from the background and before the API reload finished.
  final bool stale;

  /// The failure to show, if any.
  final RealtimeFailure? failure;

  /// The number of channels with at least one listener.
  final int activeSubscriptions;

  /// When the last publication arrived, in UTC.
  final DateTime? lastEventAt;

  /// Whether a status bar is needed instead of the normal screen.
  bool get isDegraded =>
      activeSubscriptions > 0 &&
      (phase != RealtimeConnectionPhase.connected || stale || failure != null);
}

/// The state of one channel subscription.
class RealtimeChannelStatus {
  const RealtimeChannelStatus({
    required this.channel,
    required this.phase,
    this.stale = false,
    this.failure,
    this.lastEventAt,
  });

  final RealtimeChannel channel;
  final RealtimeSubscriptionPhase phase;
  final bool stale;
  final RealtimeFailure? failure;
  final DateTime? lastEventAt;
}

/// A listener of one realtime channel.
///
/// Several listeners may share the same channel: the client keeps exactly
/// one Centrifugo subscription per channel and hands out this handle.
abstract interface class RealtimeSubscription {
  /// The channel of this handle.
  RealtimeChannel get channel;

  /// Publications of the channel, in stream order and without repeats.
  Stream<RealtimeEvent> get events;

  /// Subscription state changes, starting with the current state.
  Stream<RealtimeChannelStatus> get status;

  /// The state at this moment; the stream only carries later changes.
  RealtimeChannelStatus get currentStatus;

  /// Removes this listener; the SDK unsubscribes after the last one.
  Future<void> close();
}
