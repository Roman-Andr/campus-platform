import 'package:campus/src/core/auth/auth_service.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/realtime/realtime_channel.dart';
import 'package:campus/src/core/realtime/realtime_failure.dart';
import 'package:campus/src/core/realtime/realtime_models.dart';
import 'package:campus/src/core/realtime/realtime_service.dart';
import 'package:campus/src/core/realtime/realtime_tokens.dart';
import 'package:centrifuge/centrifuge.dart' as cf;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';
import 'fake_centrifuge.dart';
import 'realtime_test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '01890a5d-ac96-774b-bcce-b302099a8058';
  final channel = RealtimeChannel.personal(userId);

  late RealtimeTestServer server;
  late FakeCentrifugeClient client;
  late ProviderContainer container;
  late RealtimeService service;

  Future<void> createService() async {
    server = RealtimeTestServer();
    client = FakeCentrifugeClient();
    container = ProviderContainer(
      overrides: [
        ...apiOverrides(adapter: server.adapter, secure: signedInStorage),
        realtimeClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    client.connectionToken = () =>
        container.read(realtimeTokensProvider).connectionToken();
    service = container.read(realtimeServiceProvider.notifier);
  }

  /// Lets token refresh, API calls and stream events finish: the first
  /// connect refreshes the access token, which takes a few event-loop turns.
  Future<void> settle() async {
    await pumpEventQueue(times: 100);
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue(times: 100);
  }

  FakeSubscription fake() =>
      client.getSubscription(channel.name)! as FakeSubscription;

  test('subscribes once and drops repeated publications', () async {
    await createService();
    var reloads = 0;
    final subscription = service.subscribe(
      channel,
      reload: () async => reloads++,
    );
    await settle();

    expect(client.state, cf.State.connected);
    expect(client.newSubscriptionCalls, 1);
    expect(reloads, 1);
    expect(server.recoverRequests, 1);
    expect(
      subscription.currentStatus.phase,
      RealtimeSubscriptionPhase.subscribed,
    );

    final events = <RealtimeEvent>[];
    subscription.events.listen(events.add);

    fake().addPublication(
      offset: 5,
      data: {'text': 'hello', 'created_at': '2026-11-14T12:00:00Z'},
    );
    await settle();
    expect(events, hasLength(1));
    expect(events.single.data, containsPair('text', 'hello'));
    expect(events.single.occurredAt, DateTime.utc(2026, 11, 14, 12));

    fake().addPublication(offset: 5, data: {'text': 'duplicate'});
    await settle();
    expect(events, hasLength(1));

    fake().addPublication(offset: 6, data: {'text': 'next'});
    await settle();
    expect(events, hasLength(2));

    // A second listener shares the one Centrifugo subscription.
    final second = service.subscribe(channel, reload: () async => reloads++);
    expect(client.newSubscriptionCalls, 1);
    await second.close();
    final sdk = fake();
    expect(sdk.state, cf.SubscriptionState.subscribed);
    await subscription.close();
    expect(sdk.state, cf.SubscriptionState.unsubscribed);
    expect(client.subscriptions(), isEmpty);
  });

  test(
    'reconnects after a network loss without a second subscription',
    () async {
      await createService();
      server.tokenExpiry = DateTime.now().toUtc().add(
        const Duration(seconds: 10),
      );
      final subscription = service.subscribe(channel, reload: () async {});
      await settle();
      expect(
        subscription.currentStatus.phase,
        RealtimeSubscriptionPhase.subscribed,
      );

      client.dropConnection();
      await settle();
      expect(service.state.phase, RealtimeConnectionPhase.reconnecting);
      expect(subscription.currentStatus.stale, isTrue);
      expect(client.newSubscriptionCalls, 1);

      client.expireToken();
      await client.reconnect();
      await settle();

      expect(service.state.phase, RealtimeConnectionPhase.connected);
      expect(
        subscription.currentStatus.phase,
        RealtimeSubscriptionPhase.subscribed,
      );
      expect(subscription.currentStatus.stale, isFalse);
      // The expired connection token was requested again.
      expect(server.connectionTokenRequests, 2);
      expect(client.newSubscriptionCalls, 1);
    },
  );

  test('a dropped connection is retried after a token network error', () async {
    await createService();
    server.connectionTokenNetworkFailures = 10;
    final subscription = service.subscribe(channel, reload: () async {});
    await settle();

    expect(service.state.phase, RealtimeConnectionPhase.connecting);
    expect(service.state.failure?.kind, RealtimeFailureKind.network);
    expect(client.state, cf.State.connecting);

    server.connectionTokenNetworkFailures = 0;
    await client.retryConnect();
    await settle();

    expect(service.state.phase, RealtimeConnectionPhase.connected);
    expect(service.state.failure, isNull);
    expect(
      subscription.currentStatus.phase,
      RealtimeSubscriptionPhase.subscribed,
    );
  });

  test('a forbidden channel stops with a localized failure', () async {
    await createService();
    server.forbiddenChannels.add(channel.name);
    final subscription = service.subscribe(channel, reload: () async {});
    await settle();

    expect(
      subscription.currentStatus.phase,
      RealtimeSubscriptionPhase.unsubscribed,
    );
    expect(
      subscription.currentStatus.failure?.kind,
      RealtimeFailureKind.forbidden,
    );
    expect(service.state.failure?.kind, RealtimeFailureKind.forbidden);
    expect(server.subscriptionTokenRequests, 1);
    expect(client.newSubscriptionCalls, 1);
  });

  test('a temporary subscription failure is retried', () async {
    await createService();
    server.subscriptionTokenStatus = 503;
    final subscription = service.subscribe(channel, reload: () async {});
    await settle();

    expect(
      subscription.currentStatus.phase,
      RealtimeSubscriptionPhase.subscribing,
    );
    expect(
      subscription.currentStatus.failure?.kind,
      RealtimeFailureKind.unavailable,
    );

    server.subscriptionTokenStatus = null;
    await fake().retry();
    await settle();

    expect(
      subscription.currentStatus.phase,
      RealtimeSubscriptionPhase.subscribed,
    );
    expect(subscription.currentStatus.failure, isNull);
  });

  test('an exhausted history reloads the state through the API', () async {
    await createService();
    var reloads = 0;
    final subscription = service.subscribe(
      channel,
      reload: () async => reloads++,
    );
    await settle();
    expect(reloads, 1);

    server.historyLostChannels.add(channel.name);
    await fake().recoverLost();
    await settle();

    expect(reloads, 2);
    // Initial position, the failed position request and the fresh one.
    expect(server.recoverRequests, 3);
    expect(
      subscription.currentStatus.phase,
      RealtimeSubscriptionPhase.subscribed,
    );
    expect(
      subscription.currentStatus.failure?.kind,
      RealtimeFailureKind.historyLost,
    );

    fake().addPublication(offset: 20, data: {'text': 'live again'});
    await settle();
    expect(subscription.currentStatus.failure, isNull);
  });

  test('recovery publications are delivered without a full reload', () async {
    await createService();
    var reloads = 0;
    final subscription = service.subscribe(
      channel,
      reload: () async => reloads++,
    );
    await settle();

    final events = <RealtimeEvent>[];
    subscription.events.listen(events.add);
    server.recoveredPublications[channel.name] = [
      {
        'offset': 3,
        'data': {'text': 'missed'},
      },
    ];
    server.positions[channel.name] = 3;

    await fake().recoverLost();
    await settle();

    expect(reloads, 1);
    expect(events.map((event) => event.offset), [3]);

    // The same publication from the live stream is a repeat.
    fake().addPublication(offset: 3, data: {'text': 'missed again'});
    await settle();
    expect(events, hasLength(1));
  });

  test('a rejected connection token ends realtime without retrying', () async {
    await createService();
    client.failUnauthorized();
    await settle();

    expect(service.state.phase, RealtimeConnectionPhase.disconnected);
    expect(service.state.failure?.kind, RealtimeFailureKind.unauthorized);
  });

  test('signing out clears subscriptions and forgets tokens', () async {
    await createService();
    final subscription = service.subscribe(channel, reload: () async {});
    await settle();
    expect(client.subscriptions(), isNotEmpty);

    await container.read(authServiceProvider).signOut();
    await settle();

    expect(client.state, cf.State.disconnected);
    expect(client.subscriptions(), isEmpty);
    expect(service.state.activeSubscriptions, 0);
    expect(
      subscription.currentStatus.phase,
      RealtimeSubscriptionPhase.unsubscribed,
    );
    // A new session starts with no cached tokens.
    expect(container.read(realtimeServiceProvider).activeSubscriptions, 0);
  });

  test(
    'going to the background and back reloads before showing data',
    () async {
      await createService();
      var reloads = 0;
      final subscription = service.subscribe(
        channel,
        reload: () async => reloads++,
      );
      await settle();
      expect(reloads, 1);

      await service.handleLifecycleState(AppLifecycleState.paused);
      await settle();
      expect(client.state, cf.State.disconnected);
      expect(subscription.currentStatus.stale, isTrue);

      await service.handleLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(reloads, 2);
      expect(client.state, cf.State.connected);
      expect(subscription.currentStatus.stale, isFalse);
      expect(
        subscription.currentStatus.phase,
        RealtimeSubscriptionPhase.subscribed,
      );
    },
  );
}
