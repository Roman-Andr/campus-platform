import 'dart:async';
import 'dart:convert';

import 'package:centrifuge/centrifuge.dart' as cf;
import 'package:fixnum/fixnum.dart';

/// An in-memory `Client` of the Centrifuge SDK.
///
/// The real SDK owns the WebSocket, exponential backoff and token refresh;
/// tests drive those transitions explicitly and check what the app layer
/// does around them.
class FakeCentrifugeClient implements cf.Client {
  FakeCentrifugeClient();

  cf.ClientConfig? config;

  /// How the client gets its connection token; by default a fixed token
  /// without an API request. Tests wire this to the real token store.
  Future<String> Function()? connectionToken;

  @override
  cf.State state = cf.State.disconnected;
  String token = '';
  bool refreshRequired = false;
  int connectCalls = 0;
  int newSubscriptionCalls = 0;

  final _subscriptions = <String, FakeSubscription>{};
  final _connecting = StreamController<cf.ConnectingEvent>.broadcast();
  final _connected = StreamController<cf.ConnectedEvent>.broadcast();
  final _disconnected = StreamController<cf.DisconnectedEvent>.broadcast();
  final _error = StreamController<cf.ErrorEvent>.broadcast();
  final _message = StreamController<cf.MessageEvent>.broadcast();
  final _subscribed = StreamController<cf.ServerSubscribedEvent>.broadcast();
  final _subscribing = StreamController<cf.ServerSubscribingEvent>.broadcast();
  final _unsubscribed =
      StreamController<cf.ServerUnsubscribedEvent>.broadcast();
  final _publication = StreamController<cf.ServerPublicationEvent>.broadcast();
  final _join = StreamController<cf.ServerJoinEvent>.broadcast();
  final _leave = StreamController<cf.ServerLeaveEvent>.broadcast();

  @override
  Stream<cf.ConnectingEvent> get connecting => _connecting.stream;
  @override
  Stream<cf.ConnectedEvent> get connected => _connected.stream;
  @override
  Stream<cf.DisconnectedEvent> get disconnected => _disconnected.stream;
  @override
  Stream<cf.ErrorEvent> get error => _error.stream;
  @override
  Stream<cf.MessageEvent> get message => _message.stream;
  @override
  Stream<cf.ServerSubscribedEvent> get subscribed => _subscribed.stream;
  @override
  Stream<cf.ServerSubscribingEvent> get subscribing => _subscribing.stream;
  @override
  Stream<cf.ServerUnsubscribedEvent> get unsubscribed => _unsubscribed.stream;
  @override
  Stream<cf.ServerPublicationEvent> get publication => _publication.stream;
  @override
  Stream<cf.ServerJoinEvent> get join => _join.stream;
  @override
  Stream<cf.ServerLeaveEvent> get leave => _leave.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    state = cf.State.connecting;
    _connecting.add(cf.ConnectingEvent(0, 'connect called'));
    await _connectInner();
  }

  Future<void> _connectInner() async {
    if (refreshRequired || token.isEmpty) {
      try {
        token =
            await (connectionToken?.call() ??
                Future.value('fake-connection-token'));
        refreshRequired = false;
      } catch (error) {
        _error.add(cf.ErrorEvent(cf.RefreshError(error)));
        // The real client stays connecting and schedules a retry.
        return;
      }
    }
    state = cf.State.connected;
    _connected.add(cf.ConnectedEvent('fake', '6.0', const []));
    for (final subscription in _subscriptions.values.toList()) {
      await subscription.resubscribeOnConnect();
    }
  }

  /// Retries a failed connection attempt, like the SDK backoff timer.
  Future<void> retryConnect() => _connectInner();

  /// Drops the transport; the SDK would reconnect after a backoff delay.
  void dropConnection() {
    if (state != cf.State.connected) return;
    state = cf.State.connecting;
    _connecting.add(cf.ConnectingEvent(1, 'transport closed'));
    for (final subscription in _subscriptions.values) {
      subscription.markSubscribing();
    }
  }

  /// Completes a reconnect after [dropConnection], e.g. after a new token.
  Future<void> reconnect() => _connectInner();

  /// Simulates a token expiry: the next connect refreshes the connection
  /// token through the API.
  void expireToken() => refreshRequired = true;

  @override
  Future<void> disconnect() async {
    if (state == cf.State.disconnected) return;
    state = cf.State.disconnected;
    _disconnected.add(cf.DisconnectedEvent(0, 'disconnect called'));
    for (final subscription in _subscriptions.values) {
      subscription.markSubscribing();
    }
  }

  /// Reports an unauthorized disconnect, like the SDK does for a rejected
  /// connection token.
  void failUnauthorized() {
    state = cf.State.disconnected;
    _disconnected.add(cf.DisconnectedEvent(1, 'unauthorized'));
  }

  /// Reports a temporary transport failure.
  void failWithError(Object error) {
    _error.add(cf.ErrorEvent(cf.TransportError(error)));
  }

  @override
  Future<void> close() async {
    state = cf.State.disconnected;
    for (final subscription in _subscriptions.values) {
      subscription.dispose();
    }
    _subscriptions.clear();
    await Future.wait([
      _connecting.close(),
      _connected.close(),
      _disconnected.close(),
      _error.close(),
      _message.close(),
      _subscribed.close(),
      _subscribing.close(),
      _unsubscribed.close(),
      _publication.close(),
      _join.close(),
      _leave.close(),
    ]);
  }

  @override
  void setToken(String value) => token = value;

  @override
  void setHeaders(Map<String, String> headers) {}

  @override
  Future<void> ready() async {}

  @override
  Future<void> send(List<int> data) async {}

  @override
  Future<cf.PublishResult> publish(String channel, List<int> data) async =>
      cf.PublishResult();

  @override
  Future<cf.RPCResult> rpc(String method, List<int> data) async =>
      cf.RPCResult(const []);

  @override
  Future<cf.HistoryResult> history(
    String channel, {
    int limit = 0,
    cf.StreamPosition? since,
    bool reverse = false,
  }) async => cf.HistoryResult(const [], Int64(), '');

  @override
  Future<cf.PresenceResult> presence(String channel) async =>
      cf.PresenceResult(const {});

  @override
  Future<cf.PresenceStatsResult> presenceStats(String channel) async =>
      cf.PresenceStatsResult(0, 0);

  @override
  cf.Subscription? getSubscription(String channel) => _subscriptions[channel];

  @override
  cf.Subscription newSubscription(
    String channel, [
    cf.SubscriptionConfig? config,
  ]) {
    newSubscriptionCalls++;
    final subscription = FakeSubscription(channel, this, config!);
    _subscriptions[channel] = subscription;
    return subscription;
  }

  @override
  Future<void> removeSubscription(cf.Subscription subscription) async {
    if (!identical(_subscriptions[subscription.channel], subscription)) return;
    _subscriptions.remove(subscription.channel);
    await (subscription as FakeSubscription).remove();
  }

  @override
  Map<String, cf.Subscription> subscriptions() =>
      Map.unmodifiable(_subscriptions);
}

class FakeSubscription implements cf.Subscription {
  FakeSubscription(this.channel, this.client, this.config)
    : _token = config.token;

  final FakeCentrifugeClient client;
  final cf.SubscriptionConfig config;

  String _token;
  cf.StreamPosition? _position;
  bool getStateCalled = false;

  @override
  final String channel;

  @override
  cf.SubscriptionState state = cf.SubscriptionState.unsubscribed;

  final _subscribing = StreamController<cf.SubscribingEvent>.broadcast();
  final _subscribed = StreamController<cf.SubscribedEvent>.broadcast();
  final _unsubscribed = StreamController<cf.UnsubscribedEvent>.broadcast();
  final _error = StreamController<cf.SubscriptionErrorEvent>.broadcast();
  final _publication = StreamController<cf.PublicationEvent>.broadcast();
  final _join = StreamController<cf.JoinEvent>.broadcast();
  final _leave = StreamController<cf.LeaveEvent>.broadcast();

  @override
  Stream<cf.SubscribingEvent> get subscribing => _subscribing.stream;
  @override
  Stream<cf.SubscribedEvent> get subscribed => _subscribed.stream;
  @override
  Stream<cf.UnsubscribedEvent> get unsubscribed => _unsubscribed.stream;
  @override
  Stream<cf.SubscriptionErrorEvent> get error => _error.stream;
  @override
  Stream<cf.PublicationEvent> get publication => _publication.stream;
  @override
  Stream<cf.JoinEvent> get join => _join.stream;
  @override
  Stream<cf.LeaveEvent> get leave => _leave.stream;

  @override
  Future<void> subscribe() async {
    if (state == cf.SubscriptionState.subscribed) return;
    state = cf.SubscriptionState.subscribing;
    _subscribing.add(cf.SubscribingEvent(0, 'subscribe called'));
    if (client.state != cf.State.connected) return;
    await _subscribeInner();
  }

  /// The SDK repeats a subscription after reconnecting.
  Future<void> resubscribeOnConnect() async {
    if (state == cf.SubscriptionState.unsubscribed) return;
    state = cf.SubscriptionState.subscribing;
    _subscribing.add(cf.SubscribingEvent(1, 'transport closed'));
    await _subscribeInner();
  }

  /// Marks the subscription as waiting while the connection is down.
  void markSubscribing() {
    if (state == cf.SubscriptionState.unsubscribed) return;
    state = cf.SubscriptionState.subscribing;
    _subscribing.add(cf.SubscribingEvent(1, 'transport closed'));
  }

  Future<void> _subscribeInner() async {
    if (config.getState != null && _position == null) {
      getStateCalled = true;
      try {
        _position = await config.getState!();
      } catch (error) {
        _error.add(
          cf.SubscriptionErrorEvent(cf.SubscriptionGetStateError(error)),
        );
        return;
      }
    }
    if (_token.isEmpty) {
      try {
        _token = await config.getToken!(cf.SubscriptionTokenEvent(channel));
      } on cf.UnauthorizedException catch (error) {
        state = cf.SubscriptionState.unsubscribed;
        _unsubscribed.add(cf.UnsubscribedEvent(1, error.message));
        return;
      } catch (error) {
        _error.add(
          cf.SubscriptionErrorEvent(cf.SubscriptionSubscribeError(error)),
        );
        return;
      }
    }
    state = cf.SubscriptionState.subscribed;
    _subscribed.add(
      cf.SubscribedEvent(
        false,
        false,
        const [],
        _position ?? cf.StreamPosition(Int64(), 'epoch-1'),
        true,
        true,
      ),
    );
  }

  /// Simulates the server answering that the saved position is no longer
  /// recoverable (error 112), so the SDK calls `getState` again.
  Future<void> recoverLost() async {
    state = cf.SubscriptionState.subscribing;
    _subscribing.add(cf.SubscribingEvent(1, 'unrecoverable position'));
    _position = null;
    await _subscribeInner();
  }

  /// Retries after a failed getState or subscribe.
  Future<void> retry() async {
    state = cf.SubscriptionState.subscribing;
    _subscribing.add(cf.SubscribingEvent(1, 'retry'));
    await _subscribeInner();
  }

  /// Delivers a publication while subscribed.
  void addPublication({required int offset, required Object? data}) {
    _publication.add(
      cf.PublicationEvent(
        utf8.encode(jsonEncode(data)),
        Int64(offset),
        null,
        const {},
      ),
    );
  }

  /// Expires the subscription token so the next refresh asks the API.
  void expireToken() => _token = '';

  /// Refreshes the subscription token, like the SDK timer before expiry.
  Future<void> refreshToken() async {
    if (config.getToken == null) return;
    try {
      _token = await config.getToken!(cf.SubscriptionTokenEvent(channel));
    } catch (error) {
      _error.add(cf.SubscriptionErrorEvent(cf.SubscriptionRefreshError(error)));
    }
  }

  @override
  Future<void> unsubscribe() async {
    if (state == cf.SubscriptionState.unsubscribed) return;
    state = cf.SubscriptionState.unsubscribed;
    _unsubscribed.add(cf.UnsubscribedEvent(0, 'unsubscribe called'));
  }

  Future<void> remove() async {
    await unsubscribe();
    dispose();
  }

  void dispose() {
    unawaited(_subscribing.close());
    unawaited(_subscribed.close());
    unawaited(_unsubscribed.close());
    unawaited(_error.close());
    unawaited(_publication.close());
    unawaited(_join.close());
    unawaited(_leave.close());
  }

  @override
  void setTagsFilter(cf.FilterNode? tagsFilter) {}

  @override
  Future<cf.PublishResult> publish(List<int> data) async => cf.PublishResult();

  @override
  Future<cf.PresenceResult> presence() async => cf.PresenceResult(const {});

  @override
  Future<cf.PresenceStatsResult> presenceStats() async =>
      cf.PresenceStatsResult(0, 0);

  @override
  Future<cf.HistoryResult> history({
    int limit = 0,
    cf.StreamPosition? since,
    bool reverse = false,
  }) async => cf.HistoryResult(const [], Int64(), '');

  @override
  Future<void> ready() async {}
}
