import 'dart:math' as math;

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/realtime/realtime_service.dart';
import 'package:campus/src/features/notifications/application/notifications.dart';
import 'package:campus/src/features/notifications/domain/notification_feed.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../core/realtime/fake_centrifuge.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

/// Serves an inbox whose read state is a server-side cursor.
///
/// The page grows with [rows]; `read` of every notification is recomputed
/// from [readThrough], so a second client sees the state of the first one.
class _Inbox {
  _Inbox({this.pageSize = 100});

  final int pageSize;
  final rows = <Map<String, Object?>>[];
  int readThrough = 0;

  /// The whole-inbox count the server reports, not just the returned page.
  int get unreadCount =>
      rows.where((row) => (row['sequence']! as int) > readThrough).length;
  int readCalls = 0;
  int? readFailureStatus;
  bool failFirstReadWithNetwork = false;

  ResponseBody answer(RequestOptions options) {
    switch (options.path) {
      case '/api/v1/auth/token/refresh':
        return jsonBody(200, tokensJson(1));
      case '/api/v1/notifications':
        return _feed(options);
      case '/api/v1/notifications/read':
        return _read(options);
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
      default:
        throw StateError('Unexpected ${options.method} ${options.path}');
    }
  }

  ResponseBody _feed(RequestOptions options) {
    final ascending = options.queryParameters['ascending'] == true;
    final after = options.queryParameters['after_sequence'] as int? ?? 0;
    final cursor = options.queryParameters['cursor'] as String?;
    final start = cursor == null ? 0 : int.parse(cursor.split('-').last);
    final matching =
        rows
            .where((row) => (row['sequence']! as int) > after)
            .map(
              (row) => {
                ...row,
                'read': (row['sequence']! as int) <= readThrough,
              },
            )
            .toList()
          ..sort(
            (a, b) => ascending
                ? (a['sequence']! as int).compareTo(b['sequence']! as int)
                : (b['sequence']! as int).compareTo(a['sequence']! as int),
          );
    final page = matching.skip(start).take(pageSize).toList();
    final next = start + pageSize < matching.length
        ? 'offset-${start + pageSize}'
        : null;
    return jsonBody(
      200,
      notificationPage(page, next: next, unread: unreadCount),
    );
  }

  ResponseBody _read(RequestOptions options) {
    readCalls++;
    if (failFirstReadWithNetwork && readCalls == 1) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection reset by peer',
      );
    }
    final status = readFailureStatus;
    if (status != null) return problemBody(status, 'not_found');
    final id = SentRequest(options).json['through_id']! as String;
    final sequence =
        rows.firstWhere((row) => row['id'] == id)['sequence']! as int;
    readThrough = math.max(readThrough, sequence);
    return jsonBody(200, {
      'sequence': readThrough,
      'unread_count': unreadCount,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter server;
  late _Inbox inbox;

  setUp(() {
    inbox = _Inbox();
    server = FakeHttpAdapter()..notifications = null;
    server.route(inbox.answer);
  });

  Future<ProviderContainer> start({List<Override> overrides = const []}) async {
    final container = ProviderContainer(
      overrides: [
        ...apiOverrides(adapter: server, secure: signedInStorage),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    return container;
  }

  /// The classified failure of [future]; the generated client throws
  /// `DioException`, the app classifies it with [ApiFailure.from].
  Future<Object> failureOf(Future<Object?> future) async {
    try {
      await future;
    } on Object catch (error) {
      return ApiFailure.from(error);
    }
    fail('The request did not fail.');
  }

  group('feed', () {
    test('shows the notifications of the server, newest first', () async {
      inbox.rows.addAll([
        notificationJson(id: 'n1', sequence: 1),
        notificationJson(id: 'n2', sequence: 2),
      ]);
      final container = await start();

      final feed = await container.read(notificationsFeedProvider.future);

      expect(feed.items.map((row) => row.id), ['n2', 'n1']);
      expect(feed.nextPage, isNull);
      expect(container.read(unreadNotificationsProvider), 2);
    });

    test('the unread count ignores notifications read before', () async {
      inbox
        ..readThrough = 1
        ..rows.addAll([
          notificationJson(id: 'n1', sequence: 1),
          notificationJson(id: 'n2', sequence: 2),
        ]);
      final container = await start();

      await container.read(notificationsFeedProvider.future);

      expect(container.read(unreadNotificationsProvider), 1);
    });

    test('more() follows the cursor of the next page', () async {
      inbox = _Inbox(pageSize: 2)
        ..rows.addAll([
          notificationJson(id: 'n1', sequence: 1),
          notificationJson(id: 'n2', sequence: 2),
          notificationJson(id: 'n3', sequence: 3),
        ]);
      server.route(inbox.answer);
      final container = await start();
      await container.read(notificationsFeedProvider.future);

      await container.read(notificationsFeedProvider.notifier).more();

      final feed = container.read(notificationsFeedProvider).requireValue;
      expect(feed.items.map((row) => row.id), ['n3', 'n2', 'n1']);
      expect(feed.nextPage, isNull);
      expect(
        server.sent
            .lastWhere((request) => request.path == '/api/v1/notifications')
            .query['cursor'],
        'offset-2',
      );
      expect(container.read(unreadNotificationsProvider), 3);
    });

    test('the unread count covers pages that are not loaded yet', () async {
      inbox = _Inbox(pageSize: 20)
        ..rows.addAll([
          for (var sequence = 1; sequence <= 25; sequence++)
            notificationJson(id: 'n$sequence', sequence: sequence),
        ]);
      server.route(inbox.answer);
      final container = await start();

      final feed = await container.read(notificationsFeedProvider.future);

      // The badge does not page through the inbox: the server reports the
      // exact count over all pages.
      expect(feed.items, hasLength(20));
      expect(feed.unreadCount, 25);
      expect(container.read(unreadNotificationsProvider), 25);
    });

    test('sync() loads notifications missed during a gap', () async {
      inbox.rows.addAll([
        notificationJson(id: 'n1', sequence: 1),
        notificationJson(id: 'n2', sequence: 2),
      ]);
      final container = await start();
      await container.read(notificationsFeedProvider.future);

      inbox.rows.add(notificationJson(id: 'n3', sequence: 3));
      await container.read(notificationsFeedProvider.notifier).sync();

      final feed = container.read(notificationsFeedProvider).requireValue;
      expect(feed.items.map((row) => row.id), ['n3', 'n2', 'n1']);
      final request = server.sent.lastWhere(
        (request) => request.path == '/api/v1/notifications',
      );
      expect(request.query['after_sequence'], 2);
      expect(request.query['ascending'], true);
    });

    test('a rejected feed reports the Problem Details', () async {
      server.route(
        (options) => options.path == '/api/v1/auth/token/refresh'
            ? jsonBody(200, tokensJson(1))
            : problemBody(403, 'forbidden'),
      );
      final container = await start();

      final error = await failureOf(
        container.read(notificationsFeedProvider.future),
      );

      expect(
        error,
        isA<ProblemFailure>()
            .having((failure) => failure.status, 'status', 403)
            .having((failure) => failure.code.toJson(), 'code', 'forbidden'),
      );
    });

    test('nobody signed in has an empty inbox and asks nothing', () async {
      final container = ProviderContainer(
        overrides: apiOverrides(adapter: server),
      );
      addTearDown(container.dispose);
      await container.read(authStatusProvider.future);

      final feed = await container.read(notificationsFeedProvider.future);

      expect(feed.items, isEmpty);
      expect(container.read(unreadNotificationsProvider), 0);
      expect(
        server.sent.where((request) => request.path == '/api/v1/notifications'),
        isEmpty,
      );
    });
  });

  group('read state', () {
    setUp(() {
      inbox.rows.addAll([
        notificationJson(id: 'n1', sequence: 1),
        notificationJson(id: 'n2', sequence: 2),
      ]);
    });

    test('marking read sends the id and the idempotency key', () async {
      final container = await start();
      final feed = await container.read(notificationsFeedProvider.future);

      await container
          .read(notificationsFeedProvider.notifier)
          .markRead(feed.items.first);

      final post = server.sent.singleWhere(
        (request) =>
            request.method == 'POST' &&
            request.path == '/api/v1/notifications/read',
      );
      expect(post.json, {'through_id': 'n2'});
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(container.read(unreadNotificationsProvider), 0);
      expect(
        container
            .read(notificationsFeedProvider)
            .requireValue
            .items
            .every((row) => row.read),
        isTrue,
      );
    });

    test('another device sees the same read state after signing in', () async {
      final first = await start();
      final feed = await first.read(notificationsFeedProvider.future);
      await first
          .read(notificationsFeedProvider.notifier)
          .markRead(feed.items.first);

      final second = await start();
      await second.read(notificationsFeedProvider.future);

      expect(second.read(unreadNotificationsProvider), 0);
      expect(
        second
            .read(notificationsFeedProvider)
            .requireValue
            .items
            .every((row) => row.read),
        isTrue,
      );
    });

    test('refresh() picks up the read cursor of another device', () async {
      final container = await start();
      await container.read(notificationsFeedProvider.future);

      // Another device read both notifications: no new record is created,
      // only the server-side read cursor moves.
      inbox.readThrough = 2;
      await container.read(notificationsFeedProvider.notifier).refresh();

      final feed = container.read(notificationsFeedProvider).requireValue;
      expect(feed.items.every((row) => row.read), isTrue);
      expect(feed.unreadCount, 0);
      expect(container.read(unreadNotificationsProvider), 0);
    });

    test('marking all read uses the newest loaded notification', () async {
      final container = await start();
      await container.read(notificationsFeedProvider.future);

      await container.read(notificationsFeedProvider.notifier).markAllRead();

      final post = server.sent.singleWhere(
        (request) => request.path == '/api/v1/notifications/read',
      );
      expect(post.json, {'through_id': 'n2'});
      expect(container.read(unreadNotificationsProvider), 0);
    });

    test('a read retried after a lost connection keeps the key', () async {
      inbox.failFirstReadWithNetwork = true;
      final container = await start();
      final feed = await container.read(notificationsFeedProvider.future);

      await container
          .read(notificationsFeedProvider.notifier)
          .markRead(feed.items.first);

      final posts = server.sent
          .where((request) => request.path == '/api/v1/notifications/read')
          .toList();
      expect(posts, hasLength(2));
      expect(
        posts.first.headers['Idempotency-Key'],
        posts.last.headers['Idempotency-Key'],
      );
      expect(inbox.readCalls, 2);
      expect(container.read(unreadNotificationsProvider), 0);
    });

    test('a deleted notification reports not found and stays unread', () async {
      inbox.readFailureStatus = 404;
      final container = await start();
      final feed = await container.read(notificationsFeedProvider.future);

      final error = await failureOf(
        container
            .read(notificationsFeedProvider.notifier)
            .markRead(feed.items.first),
      );

      expect(
        ApiFailure.from(error),
        isA<ProblemFailure>().having(
          (failure) => failure.status,
          'status',
          404,
        ),
      );
      expect(container.read(unreadNotificationsProvider), 2);
    });
  });

  test('a realtime wakeup loads the notification from the API', () async {
    inbox.rows.add(notificationJson(id: 'n1', sequence: 1));
    final client = FakeCentrifugeClient();
    final container = await start(
      overrides: [realtimeClientProvider.overrideWithValue(client)],
    );
    final notifier = container.read(notificationsFeedProvider.notifier);
    await container.read(notificationsFeedProvider.future);

    await notifier.watchRealtime();
    await pumpEventQueue(times: 100);

    inbox.rows.add(notificationJson(id: 'n2', sequence: 2));
    (client.getSubscription('user#${userJson['id']}')! as FakeSubscription)
        .addPublication(
          offset: 1,
          data: {'notification_id': 'n2', 'sequence': 2},
        );
    await pumpEventQueue(times: 100);

    final feed = container.read(notificationsFeedProvider).requireValue;
    expect(feed.items.map((row) => row.id), ['n2', 'n1']);
    final request = server.sent.lastWhere(
      (request) => request.path == '/api/v1/notifications',
    );
    expect(request.query['after_sequence'], 1);
    expect(request.query['ascending'], true);

    await notifier.unwatchRealtime();
  });

  group('domain', () {
    test(
      'the text follows the interface language with an English fallback',
      () {
        final row = notificationJson(id: 'n1', sequence: 1);
        final notification = NotificationOutput.fromJson(row);

        expect(
          notificationText(notification, 'ru'),
          'Место освободилось — бронируйте.',
        );
        expect(
          notificationText(notification, 'en'),
          'A place is free — book it now.',
        );
        expect(
          notificationText(notification, 'de'),
          'A place is free — book it now.',
        );
        expect(
          notificationText(
            NotificationOutput.fromJson({
              ...row,
              'text': {'ru': 'Только RU'},
            }),
            'de',
          ),
          'Только RU',
        );
      },
    );

    test('a read cursor marks this notification and earlier ones', () {
      final items = [
        for (final sequence in [3, 2, 1])
          NotificationOutput.fromJson(
            notificationJson(id: 'n$sequence', sequence: sequence),
          ),
      ];

      final read = applyReadCursor(items, 2);

      expect(read.map((row) => row.read), [false, true, true]);
      expect(applyReadCursor(read, 2).map((row) => row.read), [
        false,
        true,
        true,
      ]);
    });

    test('merging keeps a notification read once reported read', () {
      final read = NotificationOutput.fromJson(
        notificationJson(id: 'n1', sequence: 1, read: true),
      );
      final stale = NotificationOutput.fromJson(
        notificationJson(id: 'n1', sequence: 1),
      );

      expect(mergeNotifications([read], [stale]).single.read, isTrue);
      expect(mergeNotifications([stale], [read]).single.read, isTrue);
    });
  });
}
