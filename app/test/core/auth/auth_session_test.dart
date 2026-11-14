import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_service.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_storage.dart';
import 'package:campus/src/core/auth/auth_token.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

const _refresh = '/api/v1/auth/token/refresh';
const _protected = '/api/v1/things';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter server;

  Future<ProviderContainer> start({
    Map<String, String> secure = signedInStorage,
  }) async {
    final container = ProviderContainer(
      overrides: apiOverrides(adapter: server, secure: secure),
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    return container;
  }

  /// A request to an operation that requires authentication.
  Future<Response<Object?>> protectedRequest(ProviderContainer container) =>
      container
          .read(apiDioProvider)
          .get<Object?>(
            _protected,
            options: Options(extra: {securityExtra: <Object?>[]}),
          );

  List<SentRequest> sentTo(String path) =>
      server.sent.where((request) => request.path == path).toList();

  Future<Map<String, String>> secureContents() =>
      const FlutterSecureStorage().readAll();

  AuthenticationStatus? status(ProviderContainer container) =>
      container.read(authStatusProvider).value;

  setUp(() => server = FakeHttpAdapter());

  group('restoring the session', () {
    test('a saved refresh token means signed in', () async {
      final container = await start();

      expect(status(container), AuthenticationStatus.authenticated);
    });

    test('without a saved refresh token the user is signed out', () async {
      final container = await start(secure: const {});

      expect(status(container), AuthenticationStatus.unauthenticated);
    });
  });

  group('refresh', () {
    test('concurrent requests with an expired token refresh it once', () async {
      // After a restart only the refresh token is known: every request
      // needs a fresh access token.
      final container = await start();
      var issued = 0;
      server.route(
        (options) => options.path == _refresh
            ? jsonBody(200, tokensJson(++issued))
            : jsonBody(200),
      );

      await Future.wait([
        for (var i = 0; i < 5; i++) protectedRequest(container),
      ]);

      final refreshes = sentTo(_refresh);
      expect(refreshes, hasLength(1));
      expect(refreshes.single.json, {
        'refresh_token': testRefreshToken,
        'device_id': signedInStorage[AuthStorage.deviceIdKey],
      });
      expect(refreshes.single.headers['Authorization'], isNull);
      expect(refreshes.single.headers['Idempotency-Key'], isNotNull);
      final requests = sentTo(_protected);
      expect(requests, hasLength(5));
      for (final request in requests) {
        expect(request.headers['Authorization'], 'Bearer access-1');
      }
      expect(
        (await secureContents())[AuthStorage.refreshTokenKey],
        'refresh-1',
      );
    });

    test('concurrent requests rejected as unauthorized refresh once and '
        'are repeated with the new token', () async {
      final container = await start();
      await container
          .read(authSessionProvider)
          .setToken(
            AuthToken(
              accessToken: 'access-0',
              refreshToken: 'refresh-0',
              expiresAt: DateTime.now().add(const Duration(minutes: 10)),
            ),
          );
      var issued = 0;
      server.route((options) {
        if (options.path == _refresh) {
          return jsonBody(200, tokensJson(++issued));
        }
        return options.headers['Authorization'] == 'Bearer access-1'
            ? jsonBody(200)
            : problemBody(401, 'unauthorized');
      });

      final responses = await Future.wait([
        for (var i = 0; i < 5; i++) protectedRequest(container),
      ]);

      expect(
        responses.map((response) => response.statusCode),
        everyElement(200),
      );
      expect(sentTo(_refresh), hasLength(1));
      expect(sentTo(_refresh).single.json['refresh_token'], 'refresh-0');
      expect(status(container), AuthenticationStatus.authenticated);
    });

    test('a valid access token is used without a refresh', () async {
      final container = await start();
      await container
          .read(authSessionProvider)
          .setToken(
            AuthToken(
              accessToken: 'access-0',
              refreshToken: 'refresh-0',
              expiresAt: DateTime.now().add(const Duration(minutes: 10)),
            ),
          );
      server.reply(200);

      await protectedRequest(container);

      expect(sentTo(_refresh), isEmpty);
      expect(
        sentTo(_protected).single.headers['Authorization'],
        'Bearer access-0',
      );
    });

    test('a rejected refresh token signs out', () async {
      final container = await start();
      server.route(
        (options) => options.path == _refresh
            ? problemBody(401, 'refresh_token_invalid')
            : problemBody(401, 'unauthorized'),
      );

      final failure = await protectedRequest(container)
          .then<Object?>((_) => null, onError: ApiFailure.from);

      expect(failure, isA<ProblemFailure>());
      expect(sentTo(_refresh), hasLength(1));
      expect(status(container), AuthenticationStatus.unauthenticated);
      final saved = await secureContents();
      expect(saved.containsKey(AuthStorage.refreshTokenKey), isFalse);
      // The device stays the same for the next sign-in.
      expect(
        saved[AuthStorage.deviceIdKey],
        signedInStorage[AuthStorage.deviceIdKey],
      );
    });

    test('a network failure keeps the session for a later try', () async {
      final container = await start();
      server.failConnection();

      final failure = await protectedRequest(container)
          .then<Object?>((_) => null, onError: ApiFailure.from);

      expect(failure, isA<NetworkFailure>());
      expect(sentTo(_protected), isEmpty);
      expect(status(container), AuthenticationStatus.authenticated);
      expect(
        (await secureContents())[AuthStorage.refreshTokenKey],
        testRefreshToken,
      );
    });

    test('public requests carry no token and cause no refresh', () async {
      final container = await start();
      server.reply(200, {'items': <Object?>[]});

      await container.read(campusApiProvider).university.listCities();

      expect(server.sent.single.headers['Authorization'], isNull);
      expect(sentTo(_refresh), isEmpty);
    });
  });

  group('sign-in', () {
    test('keeps only the refresh token, in the secure storage', () async {
      final container = await start(secure: const {});
      server.reply(200, tokensJson(1));

      final user = await container
          .read(authServiceProvider)
          .signIn(email: 'ivanov@edu.hse.ru', code: '123456');

      expect(user.firstName, 'Иван');
      expect(status(container), AuthenticationStatus.authenticated);
      final saved = await secureContents();
      expect(saved[AuthStorage.refreshTokenKey], 'refresh-1');
      expect(saved.values, isNot(contains('access-1')));
      final deviceId = saved[AuthStorage.deviceIdKey]!;
      expect(Uuid.isValidUUID(fromString: deviceId), isTrue);
      expect(server.sent.single.json, {
        'email': 'ivanov@edu.hse.ru',
        'code': '123456',
        'device_id': deviceId,
      });
    });

    test('sends the names of a new user', () async {
      final container = await start(secure: const {});
      server.reply(200, tokensJson(1));

      await container
          .read(authServiceProvider)
          .signIn(
            email: 'ivanov@edu.hse.ru',
            code: '123456',
            firstName: 'Иван',
            lastName: 'Иванов',
          );

      expect(server.sent.single.json['first_name'], 'Иван');
      expect(server.sent.single.json['last_name'], 'Иванов');
    });

    test('the device ID is created once and reused', () async {
      final container = await start(secure: const {});
      server.reply(200, tokensJson(1));
      final service = container.read(authServiceProvider);

      await service.signIn(email: 'ivanov@edu.hse.ru', code: '123456');
      await service.signOut();
      await service.signIn(email: 'ivanov@edu.hse.ru', code: '654321');

      final signIns = sentTo('/api/v1/auth/sign-in');
      expect(signIns[0].json['device_id'], signIns[1].json['device_id']);
    });
  });

  group('sign-out', () {
    test('ends the session on the server and forgets the tokens', () async {
      final container = await start();
      var issued = 0;
      server.route(
        (options) => options.path == _refresh
            ? jsonBody(200, tokensJson(++issued))
            : jsonBody(204, null),
      );

      await container.read(authServiceProvider).signOut();

      final signOut = sentTo('/api/v1/auth/sign-out').single;
      expect(signOut.headers['Authorization'], 'Bearer access-1');
      expect(status(container), AuthenticationStatus.unauthenticated);
      expect(
        (await secureContents()).containsKey(AuthStorage.refreshTokenKey),
        isFalse,
      );
    });

    test('signs out on the device without a network', () async {
      final container = await start();
      server.failConnection();

      await container.read(authServiceProvider).signOut();

      expect(status(container), AuthenticationStatus.unauthenticated);
      expect(
        (await secureContents()).containsKey(AuthStorage.refreshTokenKey),
        isFalse,
      );
    });
  });

  test('tokens never reach the logs', () async {
    final logged = StringBuffer();
    final debugPrintBefore = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.writeln(message);
    addTearDown(() => debugPrint = debugPrintBefore);

    await runZoned(
      () async {
        final container = await start();
        var issued = 0;
        server.route((options) {
          if (options.path == _refresh) {
            return issued < 1
                ? jsonBody(200, tokensJson(++issued))
                : problemBody(401, 'refresh_token_invalid');
          }
          return options.headers['Authorization'] == 'Bearer access-1'
              ? jsonBody(200)
              : problemBody(401, 'unauthorized');
        });
        final session = container.read(authSessionProvider);
        await protectedRequest(container);
        // ignore: avoid_print
        print(await session.token);
        await session.setToken(
          const AuthToken(accessToken: 'access-2', refreshToken: 'refresh-2'),
        );
        try {
          await protectedRequest(container);
        } on DioException catch (error) {
          // ignore: avoid_print
          print(error);
          // ignore: avoid_print
          print(ApiFailure.from(error));
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => logged.writeln(line),
      ),
    );

    expect(logged.toString(), isNotEmpty);
    expect(logged.toString(), isNot(contains('access-')));
    expect(logged.toString(), isNot(contains('refresh-')));
    expect(logged.toString(), isNot(contains(testRefreshToken)));
  });
}
