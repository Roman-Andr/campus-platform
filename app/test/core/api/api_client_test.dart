import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/api/client_update.dart';
import 'package:campus/src/core/api/network_status.dart';
import 'package:campus/src/features/settings/application/settings_controller.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter server;
  late ProviderContainer container;
  late Dio dio;

  setUp(() {
    server = FakeHttpAdapter();
    container = ProviderContainer(
      overrides: apiOverrides(
        adapter: server,
        settings: InMemorySettingsRepository(
          const AppSettings(language: AppLanguage.russian),
        ),
      ),
    );
    addTearDown(container.dispose);
    dio = container.read(apiDioProvider);
  });

  Object? header(SentRequest request, String name) => request.headers[name];

  group('client headers', () {
    test('are sent with every request of the generated client', () async {
      await container.read(settingsControllerProvider.future);
      server.reply(200, {'items': <Object?>[]});

      await container.read(campusApiProvider).university.listCities();

      final request = server.sent.single;
      expect(request.path, '/api/v1/university/cities');
      expect(header(request, 'X-Client-Platform'), 'android');
      expect(header(request, 'X-Client-Version'), '0.1.0');
      expect(header(request, 'Accept-Language'), 'ru');
    });
  });

  group('Idempotency-Key', () {
    test('is not sent with reading requests', () async {
      server.reply(200);

      await dio.get<Object?>('/api/v1/things');

      expect(header(server.sent.single, 'Idempotency-Key'), isNull);
    });

    test('is a new UUIDv7 for every mutating request', () async {
      server.reply(201);

      for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
        await dio.request<Object?>(
          '/api/v1/things',
          options: Options(method: method),
        );
      }

      final keys = [
        for (final request in server.sent)
          header(request, 'Idempotency-Key')! as String,
      ];
      expect(keys.toSet(), hasLength(4));
      for (final key in keys) {
        expect(UuidValue.withValidation(key).version, 7);
      }
    });

    test('is the same when a request is repeated after a dropped '
        'connection', () async {
      server
        ..failConnection()
        ..failTimeout()
        ..reply(201, {'id': 1});

      final response = await dio.post<Object?>('/api/v1/things');

      expect(response.statusCode, 201);
      expect(server.sent, hasLength(3));
      final keys = server.sent.map((r) => header(r, 'Idempotency-Key'));
      expect(keys.toSet(), hasLength(1));
      expect(keys.first, isNotNull);
    });

    test('given by the caller is kept', () async {
      server.reply(201);
      const key = '01890a5d-ac96-774b-bcce-b302099a8057';

      await dio.post<Object?>(
        '/api/v1/things',
        options: Options(headers: {'Idempotency-Key': key}),
      );

      expect(header(server.sent.single, 'Idempotency-Key'), key);
    });
  });

  group('repeats', () {
    test('stop after the configured number and report the network', () async {
      server.failConnection();

      final error = await dio
          .post<Object?>('/api/v1/things')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(server.sent, hasLength(1 + testApiConfig.retryDelays.length));
      expect(ApiFailure.from(error!), isA<NetworkFailure>());
      expect(container.read(networkStatusProvider), isFalse);
    });

    test('happen for an unavailable server', () async {
      server
        ..replyProblem(503, 'http_error')
        ..reply(200);

      await dio.get<Object?>('/api/v1/things');

      expect(server.sent, hasLength(2));
    });

    test('happen for a rate limit with a short wait', () async {
      server
        ..replyProblem(429, 'rate_limited', retryAfter: 0)
        ..reply(200);

      await dio.post<Object?>('/api/v1/things');

      expect(server.sent, hasLength(2));
    });

    test('do not happen for a rate limit with a longer wait', () async {
      server.replyProblem(429, 'rate_limited', retryAfter: 840);

      final error = await dio
          .post<Object?>('/api/v1/things')
          .then<Object?>((_) => null, onError: ApiFailure.from);

      expect(server.sent, hasLength(1));
      expect(
        error,
        isA<ProblemFailure>().having(
          (failure) => failure.retryAfter,
          'retryAfter',
          const Duration(seconds: 840),
        ),
      );
    });

    test('do not happen for errors of the request or server', () async {
      for (final status in [400, 404, 422, 426, 500]) {
        server
          ..sent.clear()
          ..replyProblem(status, 'bad_request');

        await expectLater(
          dio.post<Object?>('/api/v1/things'),
          throwsA(isA<DioException>()),
        );
        expect(server.sent, hasLength(1), reason: '$status');
      }
    });
  });

  group('status reporting', () {
    test('a response brings the app back online', () async {
      container.read(networkStatusProvider.notifier).unreachable();
      server.replyProblem(404, 'not_found');

      await expectLater(
        dio.get<Object?>('/api/v1/things'),
        throwsA(isA<DioException>()),
      );

      expect(container.read(networkStatusProvider), isTrue);
    });

    test('client_update_required requires an update', () async {
      server.replyProblem(426, 'client_update_required', minVersion: '1.2.0');

      final error = await container
          .read(campusApiProvider)
          .university
          .listCities()
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(
        ApiFailure.from(error!),
        isA<UpdateRequiredFailure>().having(
          (f) => f.minVersion,
          'minVersion',
          '1.2.0',
        ),
      );
      expect(container.read(clientUpdateRequiredProvider)?.minVersion, '1.2.0');
    });
  });
}
