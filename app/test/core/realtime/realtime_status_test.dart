import 'dart:async';

import 'package:campus/src/core/api/network_status.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/core/realtime/realtime_channel.dart';
import 'package:campus/src/core/realtime/realtime_failure.dart';
import 'package:campus/src/core/realtime/realtime_models.dart';
import 'package:campus/src/core/realtime/realtime_service.dart';
import 'package:campus/src/core/realtime/realtime_status_view.dart';
import 'package:campus/src/core/realtime/realtime_tokens.dart';
import 'package:campus/src/core/time/city_time.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import 'fake_centrifuge.dart';
import 'realtime_test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '01890a5d-ac96-774b-bcce-b302099a8058';
  final channel = RealtimeChannel.personal(userId);
  final ru = lookupAppLocalizations(const Locale('ru'));

  setUpAll(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
  });

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

  /// Lets token refresh, API calls and stream events finish.
  Future<void> settle() async {
    await pumpEventQueue(times: 100);
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue(times: 100);
  }

  Widget app(Widget home) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Scaffold(body: home),
    ),
  );

  testWidgets('a healthy connection shows no status bar', (tester) async {
    await tester.runAsync(() async {
      await createService();
      service.subscribe(channel, reload: () async {});
      await settle();
    });
    await tester.pumpWidget(
      app(const RealtimeStatusBanner(child: Text('content'))),
    );
    await tester.pump();

    expect(find.text('content'), findsOneWidget);
    expect(find.text(ru.realtimeReconnecting), findsNothing);
  });

  testWidgets('a forbidden channel shows a localized status bar', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await createService();
      server.forbiddenChannels.add(channel.name);
      service.subscribe(channel, reload: () async {});
      await settle();
    });
    await tester.pumpWidget(
      app(const RealtimeStatusBanner(child: Text('content'))),
    );
    await tester.pump();

    expect(find.text(ru.realtimeChannelForbidden), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('a network error is shown and disappears after a retry', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await createService();
      server.connectionTokenNetworkFailures = 10;
      service.subscribe(channel, reload: () async {});
      await settle();
      // The failed request marked the device offline, so the strip stays
      // hidden and the offline banner speaks for the network.
      expect(service.state.failure?.kind, RealtimeFailureKind.network);
      container.read(networkStatusProvider.notifier).reachable();
    });
    await tester.pumpWidget(
      app(const RealtimeStatusBanner(child: Text('content'))),
    );
    await tester.pump();
    expect(find.text(ru.realtimeNetworkLost), findsOneWidget);

    await tester.runAsync(() async {
      server.connectionTokenNetworkFailures = 0;
      await client.retryConnect();
      await settle();
    });
    await tester.pump();

    expect(find.text(ru.realtimeNetworkLost), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('returning from the background reloads before showing data', (
    tester,
  ) async {
    final gate = Completer<void>();
    await tester.runAsync(() async {
      await createService();
      var reloads = 0;
      service.subscribe(
        channel,
        reload: () async {
          reloads++;
          if (reloads == 2) await gate.future;
        },
      );
      await settle();
    });
    await tester.pumpWidget(
      app(const RealtimeStatusBanner(child: Text('content'))),
    );
    await tester.pump();

    late Future<void> resume;
    await tester.runAsync(() async {
      await service.handleLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue(times: 10);
      resume = service.handleLifecycleState(AppLifecycleState.resumed);
      await settle();
    });
    await tester.pump();
    expect(find.text(ru.realtimeUpdating), findsOneWidget);

    await tester.runAsync(() async {
      gate.complete();
      await resume;
      await settle();
    });
    await tester.pump();

    expect(find.text(ru.realtimeUpdating), findsNothing);
    expect(service.state.stale, isFalse);
  });

  testWidgets('the status view shows the last event in the city zone', (
    tester,
  ) async {
    final status = RealtimeChannelStatus(
      channel: channel,
      phase: RealtimeSubscriptionPhase.subscribed,
      lastEventAt: DateTime.utc(2026, 11, 16, 13),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: RealtimeStatusView(
            status: status,
            timezone: 'Asia/Yekaterinburg',
            city: 'Пермь',
            deviceLocation: cityLocation('Europe/Moscow'),
          ),
        ),
      ),
    );

    expect(find.text(ru.realtimeConnected), findsOneWidget);
    expect(
      find.text(ru.realtimeLastEvent('18:00, Пермь, UTC+5')),
      findsOneWidget,
    );
  });
}
