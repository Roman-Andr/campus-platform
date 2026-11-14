import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/api/interceptors.dart';
import 'package:campus/src/core/realtime/realtime_channel.dart';
import 'package:campus/src/core/realtime/realtime_failure.dart';
import 'package:campus/src/core/realtime/realtime_models.dart';
import 'package:campus/src/core/realtime/realtime_tokens.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'realtime_test_server.dart';

void main() {
  const userId = '01890a5d-ac96-774b-bcce-b302099a8058';
  final channel = RealtimeChannel.personal(userId);

  late RealtimeTestServer server;
  late Dio dio;
  late DateTime now;
  late RealtimeTokens tokens;

  setUp(() {
    server = RealtimeTestServer();
    dio = Dio(BaseOptions(baseUrl: testApiConfig.baseUrl.toString()));
    dio.httpClientAdapter = server.adapter;
    dio.interceptors.addAll([
      IdempotencyKeyInterceptor(generate: () => 'idempotency-key'),
      retryInterceptor(dio, const [Duration.zero, Duration.zero]),
    ]);
    now = DateTime.utc(2026, 11, 14, 12);
    server.tokenExpiry = now.add(const Duration(minutes: 5));
    tokens = RealtimeTokens(
      CampusApi(dio).realtime,
      refreshMargin: const Duration(seconds: 30),
      now: () => now,
    );
  });

  group('connection token', () {
    test('is reused until it is about to expire', () async {
      expect(await tokens.connectionToken(), 'connection-1');
      expect(await tokens.connectionToken(), 'connection-1');
      expect(server.connectionTokenRequests, 1);

      now = server.tokenExpiry.subtract(const Duration(seconds: 10));
      expect(await tokens.connectionToken(), 'connection-2');
      expect(server.connectionTokenRequests, 2);
    });

    test('concurrent callbacks share one request', () async {
      final issued = await Future.wait([
        tokens.connectionToken(),
        tokens.connectionToken(),
        tokens.connectionToken(),
      ]);

      expect(issued, everyElement('connection-1'));
      expect(server.connectionTokenRequests, 1);
    });

    test('is forgotten on sign-out', () async {
      await tokens.connectionToken();
      tokens.clear();

      expect(await tokens.connectionToken(), 'connection-2');
      expect(server.connectionTokenRequests, 2);
    });

    test('a retry after a dropped connection keeps Idempotency-Key', () async {
      server.connectionTokenNetworkFailures = 1;

      expect(await tokens.connectionToken(), 'connection-2');

      final requests = server.adapter.sent
          .where(
            (request) => request.path == '/api/v1/realtime/connection-token',
          )
          .toList();
      expect(requests, hasLength(2));
      final key = requests.first.headers['Idempotency-Key'];
      expect(key, isNotEmpty);
      expect(requests.last.headers['Idempotency-Key'], key);
    });
  });

  group('subscription token', () {
    test('is bound to its channel', () async {
      expect(await tokens.subscriptionToken(channel.name), 'subscription-1');
      expect(server.subscriptionChannels, [channel.name]);
      expect(tokens.takeSubscriptionFailure(channel.name), isNull);
    });

    test('forbidden channel stops without a retry', () async {
      server.forbiddenChannels.add(channel.name);

      await expectLater(
        tokens.subscriptionToken(channel.name),
        throwsA(
          isA<RealtimeUnauthorizedException>().having(
            (error) => error.failure.kind,
            'kind',
            RealtimeFailureKind.forbidden,
          ),
        ),
      );
      expect(server.subscriptionTokenRequests, 1);
      expect(
        tokens.takeSubscriptionFailure(channel.name),
        const RealtimeFailure(RealtimeFailureKind.forbidden, code: 'forbidden'),
      );
    });

    test('unavailable server is reported as retryable', () async {
      server.subscriptionTokenStatus = 503;

      await expectLater(
        tokens.subscriptionToken(channel.name),
        throwsA(
          isA<RealtimeApiException>().having(
            (error) => error.failure.kind,
            'kind',
            RealtimeFailureKind.unavailable,
          ),
        ),
      );
    });
  });

  group('recovery', () {
    test('returns the position and publications after it', () async {
      server.positions[channel.name] = 42;
      server.recoveredPublications[channel.name] = [
        {
          'offset': 41,
          'data': {'created_at': '2026-11-14T11:59:00Z', 'text': 'missed'},
        },
      ];

      final recovery = await tokens.recoverPosition(
        channel,
        since: const RealtimePosition(epoch: 'epoch-1', offset: 40),
      );

      expect(recovery.position.epoch, 'epoch-1');
      expect(recovery.position.offset, 42);
      expect(recovery.publications, hasLength(1));
      expect(recovery.publications.single.offset, 41);
      expect(recovery.publications.single.data, containsPair('text', 'missed'));
      expect(
        recovery.publications.single.occurredAt,
        DateTime.utc(2026, 11, 14, 11, 59),
      );
    });

    test('an exhausted history is reported as history lost', () async {
      server.historyLostChannels.add(channel.name);

      await expectLater(
        tokens.recoverPosition(
          channel,
          since: const RealtimePosition(epoch: 'epoch-1', offset: 40),
        ),
        throwsA(
          isA<RealtimeApiException>().having(
            (error) => error.failure.kind,
            'kind',
            RealtimeFailureKind.historyLost,
          ),
        ),
      );
      expect(server.recoverRequests, 1);
    });
  });
}
