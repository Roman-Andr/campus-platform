import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/l10n/generated/app_localizations.dart';
import 'package:campus/src/core/realtime/realtime_service.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/reviews/presentation/review_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/realtime/fake_centrifuge.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

/// The signed-in user as `GET /api/v1/me` returns it.
Map<String, Object?> account(String id) => {
  ...userJson,
  ...filledProfileJson,
  'id': id,
  'first_name': 'Ivan',
  'last_name': 'Ivanov',
};

/// Answers of the realtime endpoints; `null` for a path of another module.
ResponseBody? realtimeReply(
  RequestOptions options, {
  bool historyLost = false,
}) {
  if (options.path == '/api/v1/auth/token/refresh') {
    return jsonBody(200, tokensJson(1));
  }
  if (options.path == '/api/v1/realtime/subscription-token') {
    final body = jsonDecode(options.data! as String) as Map<String, Object?>;
    return jsonBody(200, {
      'token': 'subscription-token',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'channel': body['channel'],
    });
  }
  if (options.path == '/api/v1/realtime/recover') {
    final body = jsonDecode(options.data! as String) as Map<String, Object?>;
    if (body['since'] != null && historyLost) {
      return problemBody(409, 'realtime_history_lost');
    }
    return jsonBody(200, {
      'channel': body['channel'],
      'epoch': 'epoch-1',
      'offset': 0,
      'publications': <Object?>[],
    });
  }
  return null;
}

/// The cities of the university; the review screens show times in their zone.
const citiesJson = {
  'items': [
    {
      'id': 'city-moscow',
      'code': 'moscow',
      'name': 'Moscow',
      'timezone': 'Europe/Moscow',
    },
  ],
};

/// Advances fake time in bounded steps; an unbounded `pumpAndSettle` cannot
/// settle a screen that rebuilds on a timer.
Future<void> settle(WidgetTester tester, {int steps = 15}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the app signed in as [viewer] and pushes [path].
Future<(FakeCentrifugeClient, FakeHttpAdapter)> open(
  WidgetTester tester,
  ResponseBody Function(RequestOptions options) reply,
  String path, {
  required String viewer,
}) async {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final client = FakeCentrifugeClient();
  final server = FakeHttpAdapter(me: account(viewer))..route(reply);
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
    overrides: [realtimeClientProvider.overrideWithValue(client)],
  );
  unawaited(container.read(appRouterProvider).push(path));
  await settle(tester);
  return (client, server);
}

FakeSubscription subscription(FakeCentrifugeClient client, String userId) =>
    client.getSubscription('user#$userId')! as FakeSubscription;

List<SentRequest> sentTo(FakeHttpAdapter server, String method, String path) =>
    server.sent
        .where((request) => request.method == method && request.path == path)
        .toList();

Future<void> wakeup(
  WidgetTester tester,
  FakeCentrifugeClient client,
  Map<String, Object?> data, {
  required String userId,
}) async {
  subscription(client, userId).addPublication(offset: 1, data: data);
  await settle(tester);
}

/// Pumps one widget with the providers, the texts and the routes of the app.
///
/// The routes carry the card to the review screen, so a test can tap the
/// entry card and see the screen it opens. [route] answers the requests of a
/// fake server apart from the realtime ones.
Future<void> pumpCard(
  WidgetTester tester,
  Widget child, {
  String viewer = reviewAuthorId,
  ResponseBody Function(RequestOptions options)? route,
}) async {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final client = FakeCentrifugeClient();
  final server = FakeHttpAdapter(me: account(viewer))
    ..route(
      (options) =>
          realtimeReply(options) ??
          route?.call(options) ??
          jsonBody(200, citiesJson),
    );
  final container = ProviderContainer(
    overrides: [
      ...apiOverrides(adapter: server, secure: signedInStorage),
      realtimeClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authStatusProvider.future);
  final router = GoRouter(
    initialLocation: '/card',
    routes: [
      GoRoute(
        path: '/card',
        builder: (context, state) =>
            Scaffold(body: SingleChildScrollView(child: child)),
      ),
      GoRoute(
        path: '/listings/:listingId/interactions/:interactionId/review',
        builder: (context, state) => ReviewScreen(
          listingId: state.pathParameters['listingId']!,
          interactionId: state.pathParameters['interactionId']!,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  // The profile loads through the fake network; the fake clock must tick for
  // the request to finish inside the fake-async zone of a widget test.
  await settle(tester);
  await tester.pumpAndSettle();
}
