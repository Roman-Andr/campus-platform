import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/features/privacy/data/privacy_api.dart';
import 'package:campus/src/features/privacy/domain/privacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter server;

  setUp(() => server = FakeHttpAdapter());

  Future<ProviderContainer> start() async {
    final container = ProviderContainer(
      overrides: apiOverrides(adapter: server, secure: signedInStorage),
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    return container;
  }

  test('the generated client sends the privacy bodies and keys', () async {
    const blocked = {
      'id': '01890a5d-ac96-774b-bcce-b302099a8059',
      'first_name': 'Мария',
      'last_name': 'Петрова',
      'account_type': 'student',
      'blocked_at': '2026-11-15T09:00:00Z',
    };
    server.route(
      (options) => switch ((options.method, options.path)) {
        ('POST', '/api/v1/auth/token/refresh') => jsonBody(200, tokensJson(1)),
        ('GET', '/api/v1/me/message-policy') => jsonBody(200, {
          'policy': 'all',
        }),
        ('PUT', '/api/v1/me/message-policy') => jsonBody(200, {
          'policy': 'related',
        }),
        ('POST', '/api/v1/me/blocks') => jsonBody(201, blocked),
        ('DELETE', '/api/v1/me/blocks/01890a5d-ac96-774b-bcce-b302099a8059') =>
          jsonBody(204, null),
        ('GET', '/api/v1/me/blocks') => jsonBody(200, {
          'items': <Object?>[],
          'next_page': null,
        }),
        _ => throw StateError('Unexpected ${options.method} ${options.path}'),
      },
    );
    final api = (await start()).read(privacyApiProvider);

    expect(await api.getMessagePolicy(), MessagePolicy.all);
    expect(
      await api.updateMessagePolicy(
        MessagePolicy.related,
        idempotencyKey: 'policy-key',
      ),
      MessagePolicy.related,
    );
    await api.blockUser(
      '01890a5d-ac96-774b-bcce-b302099a8059',
      idempotencyKey: 'block-key',
    );
    await api.unblockUser(
      '01890a5d-ac96-774b-bcce-b302099a8059',
      idempotencyKey: 'unblock-key',
    );
    expect((await api.listBlocks()).items, isEmpty);

    final requests = server.sent
        .where(
          (request) =>
              request.path.startsWith('/api/v1/me/message-policy') ||
              request.path.startsWith('/api/v1/me/blocks'),
        )
        .toList();
    expect(requests, hasLength(5));
    expect(requests[0].method, 'GET');
    expect(requests[1].method, 'PUT');
    expect(requests[1].json, {'policy': 'related'});
    expect(requests[1].headers['Idempotency-Key'], 'policy-key');
    expect(requests[2].method, 'POST');
    expect(requests[2].json, {
      'user_id': '01890a5d-ac96-774b-bcce-b302099a8059',
    });
    expect(requests[2].headers['Idempotency-Key'], 'block-key');
    expect(requests[3].method, 'DELETE');
    expect(requests[3].headers['Idempotency-Key'], 'unblock-key');
    expect(requests[4].method, 'GET');
    expect(requests[4].query['size'], 100);
  });

  test('a repeated block keeps the caller key', () async {
    const body = {
      'id': '01890a5d-ac96-774b-bcce-b302099a8059',
      'first_name': 'Мария',
      'last_name': 'Петрова',
      'account_type': 'student',
      'blocked_at': '2026-11-15T09:00:00Z',
    };
    server.route(
      (options) => switch ((options.method, options.path)) {
        ('POST', '/api/v1/auth/token/refresh') => jsonBody(200, tokensJson(1)),
        ('POST', '/api/v1/me/blocks') => jsonBody(201, body),
        _ => throw StateError('Unexpected ${options.method} ${options.path}'),
      },
    );
    final api = (await start()).read(privacyApiProvider);

    await api.blockUser(
      '01890a5d-ac96-774b-bcce-b302099a8059',
      idempotencyKey: 'same-key',
    );
    await api.blockUser(
      '01890a5d-ac96-774b-bcce-b302099a8059',
      idempotencyKey: 'same-key',
    );

    final requests = server.sent
        .where((request) => request.path == '/api/v1/me/blocks')
        .toList();
    expect(requests, hasLength(2));
    expect(
      requests.map((request) => request.headers['Idempotency-Key']).toSet(),
      {'same-key'},
    );
  });
}
