import 'dart:async';

import 'package:centrifuge/centrifuge.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/client_info.dart';
import '../auth/auth_session.dart';
import 'realtime_channel.dart';
import 'realtime_config.dart';
import 'realtime_failure.dart';
import 'realtime_models.dart';
import 'realtime_tokens.dart';

part 'realtime_service.g.dart';

/// The Centrifugo client of this app installation.
///
/// The SDK owns reconnects with exponential backoff and refreshes both the
/// connection and the subscription tokens through the API. Tests replace
/// this provider with a fake `Client`.
@Riverpod(keepAlive: true)
Client realtimeClient(Ref ref) {
  final config = ref.watch(realtimeConfigProvider);
  final tokens = ref.watch(realtimeTokensProvider);
  final clientInfo = ref.watch(clientInfoProvider);
  final client = createClient(
    config.url.toString(),
    ClientConfig(
      getToken: (_) => tokens.connectionToken(),
      minReconnectDelay: config.minReconnectDelay,
      maxReconnectDelay: config.maxReconnectDelay,
      name: 'campus-${clientInfo.platform.value}',
      version: clientInfo.version,
    ),
  );
  ref.onDispose(() {
    unawaited(client.close());
  });
  return client;
}

/// Lifecycle of realtime subscriptions of the signed-in session.
///
/// The client connects lazily with the first subscription and keeps one
/// Centrifugo subscription per channel no matter how many listeners use it.
/// Sign-out or a revoked session disconnects, drops every subscription and
/// forgets the tokens. The app disconnects in the background and reloads the
/// state through the API when it returns, so old data is not shown as
/// current.
@Riverpod(keepAlive: true)
class RealtimeService extends _$RealtimeService {
  final _channels = <String, _Channel>{};
  final _clientListeners = <StreamSubscription<Object?>>[];
  late final Client _client;
  late final RealtimeTokens _tokens;
  late final RealtimeConfig _config;
  late final AppLifecycleListener _lifecycle;
  bool _signedIn = false;
  bool _backgrounded = false;
  bool _endingSession = false;
  bool _hadConnection = false;
  bool _refreshing = false;
  bool _disposed = false;
  DateTime? _lastEventAt;
  RealtimeFailure? _connectionFailure;

  @override
  RealtimeStatus build() {
    _client = ref.watch(realtimeClientProvider);
    _tokens = ref.watch(realtimeTokensProvider);
    _config = ref.watch(realtimeConfigProvider);
    _signedIn =
        ref.read(authStatusProvider).value ==
        AuthenticationStatus.authenticated;

    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => unawaited(handleLifecycleState(state)),
    );
    ref.onDispose(_lifecycle.dispose);

    ref.listen(authStatusProvider, (_, next) {
      final signedIn = next.value == AuthenticationStatus.authenticated;
      if (signedIn == _signedIn) return;
      _signedIn = signedIn;
      if (!signedIn) unawaited(_endSession());
    });

    _clientListeners.addAll([
      _client.connected.listen(_onConnected),
      _client.connecting.listen(_onConnecting),
      _client.disconnected.listen(_onDisconnected),
      _client.error.listen(_onClientError),
    ]);

    ref.onDispose(() {
      _disposed = true;
      for (final listener in _clientListeners) {
        unawaited(listener.cancel());
      }
      for (final entry in _channels.values) {
        unawaited(entry.dispose());
      }
      _channels.clear();
    });

    return const RealtimeStatus();
  }

  /// A listener of [channel]; [reload] loads the current state of the
  /// channel through the API.
  ///
  /// [reload] is called before the first subscription and whenever the
  /// missed publications can no longer be recovered from Centrifugo, so the
  /// screen never starts from a partial history. It is also called when the
  /// app returns from the background.
  RealtimeSubscription subscribe(
    RealtimeChannel channel, {
    required Future<void> Function() reload,
  }) {
    if (!_signedIn) {
      throw const RealtimeApiException(
        RealtimeFailure(RealtimeFailureKind.unauthorized),
      );
    }
    final existing = _channels[channel.name];
    if (existing != null) {
      // The same channel already has a subscription: a second listener must
      // not create a second Centrifugo subscription or re-request events.
      existing.handles++;
      return _Handle(this, existing, reload).._register();
    }
    final entry = _Channel(this, channel);
    entry.sdk = _client.newSubscription(
      channel.name,
      SubscriptionConfig(
        recoverable: true,
        positioned: true,
        minResubscribeDelay: _config.minResubscribeDelay,
        maxResubscribeDelay: _config.maxResubscribeDelay,
        getToken: (event) => _tokens.subscriptionToken(event.channel),
        getState: () => _loadState(entry),
      ),
    );
    entry.attach();
    _channels[channel.name] = entry;
    entry.handles++;
    final handle = _Handle(this, entry, reload).._register();
    entry.setStatus(
      phase: RealtimeSubscriptionPhase.subscribing,
      clearFailure: true,
    );
    _publish();
    unawaited(_start(entry));
    return handle;
  }

  /// Handles a change of the app lifecycle; public for tests.
  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        if (_backgrounded) return;
        _backgrounded = true;
        if (!_signedIn) return;
        _markAllStale();
        // The OS may silently close a socket in the background, so the
        // client does not rely on it: it disconnects and reconnects with a
        // fresh token and a state reload on return.
        try {
          await _client.disconnect();
        } on Object {
          // Already disconnected or closed; nothing to stop.
        }
        _publish(phase: RealtimeConnectionPhase.disconnected);
      case AppLifecycleState.resumed:
        if (!_backgrounded) return;
        _backgrounded = false;
        if (!_signedIn || _channels.isEmpty) return;
        _markAllStale();
        _refreshing = true;
        _publish();
        await _refreshAll();
        _refreshing = false;
        _publish();
        await _connect();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        // A short inactive state (a system dialog) keeps the connection.
        break;
    }
  }

  Future<void> _start(_Channel entry) async {
    entry.setStatus(phase: RealtimeSubscriptionPhase.subscribing);
    _publish(
      phase: _hadConnection
          ? RealtimeConnectionPhase.reconnecting
          : RealtimeConnectionPhase.connecting,
    );
    await _connect();
    if (!_channels.containsKey(entry.channel.name)) return;
    await entry.sdk.subscribe();
  }

  Future<void> _connect() async {
    if (!_signedIn || _backgrounded || _disposed) return;
    if (_client.state != State.disconnected) return;
    try {
      await _client.connect();
    } catch (error) {
      _publish(failure: RealtimeFailure.from(error));
    }
  }

  /// Loads the current position and state, then lets the SDK subscribe with
  /// recovery from it.
  ///
  /// The SDK calls this before the first subscribe and when Centrifugo
  /// answers that the saved position is no longer recoverable (error 112).
  /// The recovery API is asked first: when it still has the missed
  /// publications they are delivered and the subscription continues from
  /// the current position. When the history is exhausted (`409
  /// realtime_history_lost`), the state is reloaded through the API instead
  /// of pretending the history is complete.
  Future<StreamPosition> _loadState(_Channel entry) async {
    final recovering = entry.epoch != null;
    try {
      if (recovering) {
        try {
          // The position is read before the state: everything the API
          // returns after this point is included in the delivery.
          final recovery = await _tokens.recoverPosition(
            entry.channel,
            since: RealtimePosition(
              epoch: entry.epoch!,
              offset: entry.lastOffset ?? 0,
            ),
          );
          for (final event in recovery.publications) {
            _deliver(entry, event);
          }
          entry.lastOffset = recovery.position.offset;
          entry.epoch = recovery.position.epoch;
          entry.setStatus(
            phase: RealtimeSubscriptionPhase.subscribing,
            stale: false,
            clearFailure: true,
          );
          _publish();
          return StreamPosition(
            Int64(recovery.position.offset),
            recovery.position.epoch,
          );
        } on RealtimeApiException catch (error) {
          if (error.failure.kind != RealtimeFailureKind.historyLost) rethrow;
          // The position is gone from the Centrifugo history: reload the
          // whole channel state through the API, then subscribe from the
          // current position. The caller is told why the data was reloaded.
          final recovery = await _tokens.recoverPosition(entry.channel);
          await _reload(entry);
          entry.lastOffset = recovery.position.offset;
          entry.epoch = recovery.position.epoch;
          entry.setStatus(
            phase: RealtimeSubscriptionPhase.subscribing,
            stale: false,
            failure: const RealtimeFailure(RealtimeFailureKind.historyLost),
          );
          _publish();
          return StreamPosition(
            Int64(recovery.position.offset),
            recovery.position.epoch,
          );
        }
      }
      final recovery = await _tokens.recoverPosition(entry.channel);
      await _reload(entry);
      entry.lastOffset = recovery.position.offset;
      entry.epoch = recovery.position.epoch;
      entry.setStatus(
        phase: RealtimeSubscriptionPhase.subscribing,
        stale: false,
        clearFailure: true,
      );
      _publish();
      return StreamPosition(
        Int64(recovery.position.offset),
        recovery.position.epoch,
      );
    } catch (error) {
      final failure = RealtimeFailure.from(error);
      entry.setStatus(failure: failure, stale: true);
      _publish();
      if (failure.isTerminal) {
        await entry.sdk.unsubscribe();
      }
      rethrow;
    }
  }

  Future<void> _reload(_Channel entry) async {
    for (final reload in entry.reloaders.values.toList()) {
      await reload();
    }
  }

  Future<void> _refreshAll() async {
    for (final entry in _channels.values.toList()) {
      try {
        await _reload(entry);
        entry.setStatus(stale: false, clearFailure: true);
      } catch (error) {
        final failure = RealtimeFailure.from(error);
        entry.setStatus(failure: failure, stale: true);
        if (failure.isTerminal) unawaited(entry.sdk.unsubscribe());
      }
      _publish();
    }
  }

  Future<void> _closeHandle(_Handle handle) async {
    final entry = handle._entry;
    entry.reloaders.remove(handle._id);
    entry.handles--;
    if (entry.handles > 0) {
      _publish();
      return;
    }
    if (!identical(_channels[entry.channel.name], entry)) return;
    _channels.remove(entry.channel.name);
    await _client.removeSubscription(entry.sdk);
    await entry.dispose();
    _publish();
  }

  Future<void> _endSession() async {
    if (_endingSession) return;
    _endingSession = true;
    final entries = _channels.values.toList();
    _channels.clear();
    try {
      await _client.disconnect();
    } on Object {
      // Already disconnected or closed.
    }
    for (final entry in entries) {
      entry.setStatus(phase: RealtimeSubscriptionPhase.unsubscribed);
      await _client.removeSubscription(entry.sdk);
      await entry.dispose();
    }
    _tokens.clear();
    _lastEventAt = null;
    _connectionFailure = null;
    _hadConnection = false;
    _backgrounded = false;
    _refreshing = false;
    if (!_disposed) state = const RealtimeStatus();
    _endingSession = false;
  }

  void _onConnected(ConnectedEvent _) {
    _hadConnection = true;
    _publish(phase: RealtimeConnectionPhase.connected, clearFailure: true);
  }

  void _onConnecting(ConnectingEvent _) {
    _publish(
      phase: _hadConnection
          ? RealtimeConnectionPhase.reconnecting
          : RealtimeConnectionPhase.connecting,
    );
  }

  void _onDisconnected(DisconnectedEvent event) {
    if (_endingSession) return;
    final failure = switch (event.code) {
      1 => const RealtimeFailure(RealtimeFailureKind.unauthorized),
      0 => null,
      _ => const RealtimeFailure(RealtimeFailureKind.unexpected),
    };
    if (event.code != 0) _markAllStale();
    _publish(
      phase: RealtimeConnectionPhase.disconnected,
      failure: failure,
      clearFailure: event.code == 0,
    );
  }

  void _onClientError(ErrorEvent event) {
    final failure = RealtimeFailure.from(_unwrap(event.error as Object));
    _publish(failure: failure);
  }

  void _onSubscribing(_Channel entry, SubscribingEvent _) {
    // After a reconnect the data may be behind until the subscription is
    // restored, so it is marked stale instead of being shown as current.
    entry.setStatus(
      phase: RealtimeSubscriptionPhase.subscribing,
      stale: entry.epoch != null,
    );
    _publish();
  }

  void _onSubscribed(_Channel entry, SubscribedEvent event) {
    final position = event.streamPosition;
    if (position != null) {
      if (entry.epoch != null && entry.epoch != position.epoch) {
        // A new stream epoch: offsets of the previous one cannot be
        // compared with the new ones.
        entry.lastOffset = null;
      }
      entry.epoch = position.epoch;
    }
    // Recovered publications are delivered after this event; their offsets
    // continue after the position getState returned, so lastOffset stays as
    // set there. A transient token or network failure is over now; the
    // history-loss note stays until the next live publication.
    final failure = entry.status.failure;
    entry.setStatus(
      phase: RealtimeSubscriptionPhase.subscribed,
      stale: false,
      clearFailure: failure?.kind != RealtimeFailureKind.historyLost,
    );
    _publish();
  }

  void _onPublication(_Channel entry, PublicationEvent event) {
    _deliver(
      entry,
      RealtimeEvent.fromBytes(
        channel: entry.channel.name,
        offset: event.offset.toInt(),
        bytes: event.data,
      ),
    );
  }

  void _deliver(_Channel entry, RealtimeEvent event) {
    final lastOffset = entry.lastOffset;
    if (lastOffset != null && event.offset <= lastOffset) return;
    entry.lastOffset = event.offset;
    entry.emit(event);
    _lastEventAt = event.receivedAt;
    entry.setStatus(
      lastEventAt: event.receivedAt,
      // A fresh publication after a history-loss reload means the channel
      // is live again; the informational banner is no longer needed.
      clearFailure: true,
    );
    _publish();
  }

  void _onUnsubscribed(_Channel entry, UnsubscribedEvent event) {
    final stored = _tokens.takeSubscriptionFailure(entry.channel.name);
    final failure =
        stored ??
        entry.status.failure ??
        (event.code == 1
            ? const RealtimeFailure(RealtimeFailureKind.unauthorized)
            : null);
    entry.setStatus(
      phase: RealtimeSubscriptionPhase.unsubscribed,
      failure: failure,
    );
    _publish();
  }

  void _onSubscriptionError(_Channel entry, SubscriptionErrorEvent event) {
    final failure = RealtimeFailure.from(_unwrap(event.error as Object));
    entry.setStatus(failure: failure);
    _publish();
    if (failure.isTerminal) unawaited(entry.sdk.unsubscribe());
  }

  void _markAllStale() {
    for (final entry in _channels.values) {
      entry.setStatus(stale: true);
    }
    _publish();
  }

  void _publish({
    RealtimeConnectionPhase? phase,
    RealtimeFailure? failure,
    bool clearFailure = false,
  }) {
    if (clearFailure) {
      _connectionFailure = null;
    } else if (failure != null) {
      _connectionFailure = failure;
    }
    if (_disposed) return;
    final active = _channels.values
        .where((entry) => entry.handles > 0)
        .toList();
    RealtimeFailure? channelFailure;
    var channelStale = false;
    for (final entry in active) {
      channelFailure ??= entry.status.failure;
      channelStale = channelStale || entry.status.stale;
    }
    state = RealtimeStatus(
      phase: phase ?? state.phase,
      stale: channelStale || _refreshing,
      failure: _connectionFailure ?? channelFailure,
      activeSubscriptions: active.length,
      lastEventAt: _lastEventAt,
    );
  }

  Object _unwrap(Object error) {
    if (error is RefreshError) return (error.error ?? error) as Object;
    if (error is ConnectError) return (error.error ?? error) as Object;
    if (error is TransportError) return (error.error ?? error) as Object;
    if (error is SubscriptionSubscribeError) {
      return (error.error ?? error) as Object;
    }
    if (error is SubscriptionGetStateError) {
      return (error.error ?? error) as Object;
    }
    if (error is SubscriptionRefreshError) {
      return (error.error ?? error) as Object;
    }
    return error;
  }
}

class _Channel {
  _Channel(this._service, this.channel) {
    _status = RealtimeChannelStatus(
      channel: channel,
      phase: RealtimeSubscriptionPhase.unsubscribed,
    );
  }

  final RealtimeService _service;
  final RealtimeChannel channel;
  late final Subscription sdk;
  final _listeners = <StreamSubscription<Object?>>[];
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _statuses = StreamController<RealtimeChannelStatus>.broadcast();
  final reloaders = <int, Future<void> Function()>{};
  late RealtimeChannelStatus _status;
  int handles = 0;
  int? lastOffset;
  String? epoch;

  RealtimeChannelStatus get status => _status;

  Stream<RealtimeEvent> get events => _events.stream;

  Stream<RealtimeChannelStatus> get statuses => _statuses.stream;

  void attach() {
    _listeners.addAll([
      sdk.subscribing.listen((event) => _service._onSubscribing(this, event)),
      sdk.subscribed.listen((event) => _service._onSubscribed(this, event)),
      sdk.unsubscribed.listen((event) => _service._onUnsubscribed(this, event)),
      sdk.publication.listen((event) => _service._onPublication(this, event)),
      sdk.error.listen((event) => _service._onSubscriptionError(this, event)),
    ]);
  }

  void setStatus({
    RealtimeSubscriptionPhase? phase,
    bool? stale,
    RealtimeFailure? failure,
    bool clearFailure = false,
    DateTime? lastEventAt,
  }) {
    final next = RealtimeChannelStatus(
      channel: channel,
      phase: phase ?? _status.phase,
      stale: stale ?? _status.stale,
      failure: clearFailure ? null : (failure ?? _status.failure),
      lastEventAt: lastEventAt ?? _status.lastEventAt,
    );
    if (next.phase == _status.phase &&
        next.stale == _status.stale &&
        next.failure == _status.failure &&
        next.lastEventAt == _status.lastEventAt) {
      return;
    }
    _status = next;
    if (!_statuses.isClosed) _statuses.add(next);
  }

  void emit(RealtimeEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> dispose() async {
    for (final listener in _listeners) {
      await listener.cancel();
    }
    await _events.close();
    await _statuses.close();
  }
}

class _Handle implements RealtimeSubscription {
  _Handle(this._service, this._entry, this._reload);

  static int _nextId = 0;

  final RealtimeService _service;
  final _Channel _entry;
  final Future<void> Function() _reload;
  final int _id = _nextId++;
  var _closed = false;

  void _register() => _entry.reloaders[_id] = _reload;

  @override
  RealtimeChannel get channel => _entry.channel;

  @override
  Stream<RealtimeEvent> get events => _entry.events;

  @override
  Stream<RealtimeChannelStatus> get status => _entry.statuses;

  @override
  RealtimeChannelStatus get currentStatus => _entry.status;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _service._closeHandle(this);
  }
}
