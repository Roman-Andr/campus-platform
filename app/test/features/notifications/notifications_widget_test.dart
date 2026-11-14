import 'package:campus/src/core/realtime/realtime_service.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/realtime/fake_centrifuge.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import '../listings/fixtures.dart';
import 'fixtures.dart';

void main() {
  late FakeHttpAdapter server;
  late FakeCentrifugeClient client;
  late int readSequence;
  late ResponseBody Function() listingResponse;
  ResponseBody Function()? notificationsFailure;

  setUp(() {
    readSequence = 2;
    notificationsFailure = null;
    listingResponse = () => jsonBody(200, listingJson(kind: 'publication'));
    client = FakeCentrifugeClient();
    server = FakeHttpAdapter(
      notifications: notificationPage([
        notificationJson(id: 'n2', sequence: 2),
        notificationJson(
          id: 'n1',
          sequence: 1,
          read: true,
          en: 'Someone joined the queue of your listing.',
          ru: 'В вашу очередь встали.',
        ),
      ]),
    );
    server.route((options) {
      switch (options.path) {
        case '/api/v1/auth/token/refresh':
          return jsonBody(200, tokensJson(1));
        case '/api/v1/notifications/read':
          return jsonBody(200, {'sequence': readSequence});
        case '/api/v1/realtime/subscription-token':
          return jsonBody(200, {
            'token': 'subscription-token',
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .toIso8601String(),
            'channel':
                (options.data! as Map<String, Object?>)['channel'] as String,
          });
        case '/api/v1/realtime/recover':
          return jsonBody(200, {
            'channel':
                (options.data! as Map<String, Object?>)['channel'] as String,
            'epoch': 'epoch-1',
            'offset': 0,
            'publications': <Object?>[],
          });
        case '/api/v1/listings/listing-1':
          return listingResponse();
        case '/api/v1/notifications':
          final failure = notificationsFailure;
          if (failure != null) return failure();
          throw StateError('The inbox has its own answer');
        default:
          throw StateError('Unexpected ${options.method} ${options.path}');
      }
    });
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    bool russian = false,
    String route = AppRoutes.home,
  }) async {
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(
        AppSettings(
          language: russian ? AppLanguage.russian : AppLanguage.english,
        ),
      ),
      adapter: server,
      overrides: [realtimeClientProvider.overrideWithValue(client)],
    );
    if (route != AppRoutes.home) {
      container.read(appRouterProvider).go(route);
      await tester.pumpAndSettle();
    }
    return container;
  }

  Future<void> openInbox(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('home-notifications')));
    await tester.pumpAndSettle();
  }

  Finder tile(String id) => find.byKey(ValueKey('notification-$id'));

  int readRequests() => server.sent
      .where((request) => request.path == '/api/v1/notifications/read')
      .length;

  testWidgets(
    'the home badge counts unread notifications and opens the inbox',
    (tester) async {
      await open(tester);

      expect(find.byKey(const Key('home-notifications')), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);

      await openInbox(tester);

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('A place is free — book it now.'), findsOneWidget);
      expect(tile('n1'), findsOneWidget);
      // The unread one is emphasised, the read one is not.
      expect(
        tester
            .widget<Text>(find.text('A place is free — book it now.'))
            .style
            ?.fontWeight,
        FontWeight.w600,
      );
      // 09:00 UTC in the Moscow zone of the profile.
      expect(
        find.descendant(of: tile('n2'), matching: find.textContaining('12:00')),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping a notification marks it read and opens the listing', (
    tester,
  ) async {
    await open(tester);
    await openInbox(tester);

    await tester.tap(tile('n2'));
    await tester.pumpAndSettle();

    expect(
      server.sent
          .singleWhere(
            (request) => request.path == '/api/v1/notifications/read',
          )
          .json,
      {'through_id': 'n2'},
    );
    expect(find.text('Listing'), findsOneWidget);
  });

  testWidgets('a removed listing shows a clear screen without server details', (
    tester,
  ) async {
    listingResponse = () => problemBody(404, 'not_found');
    await open(tester);
    await openInbox(tester);

    await tester.tap(tile('n2'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The listing is unavailable. It may have been removed or access has '
        'changed.',
      ),
      findsOneWidget,
    );
    expect(find.text('Server detail'), findsNothing);
  });

  testWidgets('marking all read clears the badge', (tester) async {
    await open(tester);
    await openInbox(tester);

    await tester.tap(find.byKey(const Key('notifications-mark-all-read')));
    await tester.pumpAndSettle();

    expect(
      server.sent
          .singleWhere(
            (request) => request.path == '/api/v1/notifications/read',
          )
          .json,
      {'through_id': 'n2'},
    );
    expect(find.byIcon(Icons.circle), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });

  testWidgets('an empty inbox explains itself', (tester) async {
    server.notifications = notificationPage([]);
    await open(tester, route: AppRoutes.notifications);

    expect(find.byKey(const Key('notifications-empty')), findsOneWidget);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('notifications-mark-all-read')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a rejected inbox shows the localized problem and a retry', (
    tester,
  ) async {
    server.notifications = null;
    notificationsFailure = () => problemBody(403, 'forbidden');
    await open(tester, route: AppRoutes.notifications);

    expect(find.text("You don't have access to this action."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a notification without a destination opens no screen', (
    tester,
  ) async {
    server.notifications = notificationPage([
      notificationJson(id: 'n9', sequence: 9, type: 'unknown.type'),
    ]);
    await open(tester);
    await openInbox(tester);

    await tester.tap(tile('n9'));
    await tester.pumpAndSettle();

    expect(
      find.text('There is no screen for this notification in the app yet.'),
      findsOneWidget,
    );
    expect(find.text('Notifications'), findsOneWidget);
    expect(tile('n9'), findsOneWidget);
    expect(readRequests(), 0);
  });

  testWidgets('a realtime wakeup adds a notification to the open inbox', (
    tester,
  ) async {
    await open(tester);
    await openInbox(tester);

    server.notifications = notificationPage([
      notificationJson(
        id: 'n3',
        sequence: 3,
        en: 'A meeting was proposed.',
        ru: 'Вам предложили встречу.',
      ),
      notificationJson(id: 'n2', sequence: 2),
      notificationJson(id: 'n1', sequence: 1, read: true),
    ]);
    (client.getSubscription('user#${userJson['id']}')! as FakeSubscription)
        .addPublication(
          offset: 1,
          data: {'notification_id': 'n3', 'sequence': 3},
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(tile('n3'), findsOneWidget);
    expect(find.text('A meeting was proposed.'), findsOneWidget);
  });

  testWidgets('Russian notification texts', (tester) async {
    server.notifications = notificationPage([
      notificationJson(id: 'n2', sequence: 2),
    ]);
    await open(tester, russian: true);
    await openInbox(tester);

    expect(find.text('Уведомления'), findsOneWidget);
    expect(find.text('Место освободилось — бронируйте.'), findsOneWidget);
    expect(find.text('A place is free — book it now.'), findsNothing);
  });
}
