import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_token.dart';
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
    await container
        .read(authSessionProvider)
        .setToken(
          AuthToken(
            accessToken: 'access-0',
            refreshToken: 'refresh-0',
            expiresAt: DateTime.now().add(const Duration(minutes: 10)),
          ),
        );
    return container;
  }

  const chat = <String, Object?>{
    'id': '019a0000-0000-7000-8000-000000000001',
    'kind': 'personal',
    'listing_id': null,
    'interaction_id': null,
    'created_at': '2026-11-15T10:00:00Z',
    'updated_at': '2026-11-15T10:00:00Z',
    'participants': <Object?>[
      {
        'id': '01890a5d-ac96-774b-bcce-b302099a8058',
        'first_name': 'Иван',
        'last_name': 'Иванов',
        'account_type': 'student',
      },
    ],
    'last_message': null,
  };

  const message = <String, Object?>{
    'id': '019a0000-0000-7000-8000-000000000002',
    'chat_id': '019a0000-0000-7000-8000-000000000001',
    'sender_id': '01890a5d-ac96-774b-bcce-b302099a8058',
    'client_id': '01890a5d-ac96-774b-bcce-b302099a8057',
    'sequence': 1,
    'text': 'hello',
    'created_at': '2026-11-15T10:01:00Z',
  };

  List<SentRequest> sentTo(String path) => [
    for (final request in server.sent)
      if (request.path == path) request,
  ];

  test('createChat returns the same chat after 201 and 200', () async {
    server
      ..reply(201, chat)
      ..reply(200, chat);
    final chats = (await start()).read(campusApiProvider).chats;

    final created = await chats.createChat(
      body: const ChatInput(
        recipientId: '01890a5d-ac96-774b-bcce-b302099a8059',
      ),
    );
    final repeated = await chats.createChat(
      body: const ChatInput(
        recipientId: '01890a5d-ac96-774b-bcce-b302099a8059',
      ),
    );

    expect(created.id, chat['id']);
    expect(repeated.id, chat['id']);
    final requests = sentTo('/api/v1/chats');
    expect(requests, hasLength(2));
    expect(requests.map((request) => request.method), everyElement('POST'));
    expect(
      requests.map((request) => request.headers['Idempotency-Key']).toSet(),
      hasLength(2),
    );
  });

  test('sendMessage returns the same message after 201 and 200', () async {
    server
      ..reply(201, message)
      ..reply(200, message);
    final chats = (await start()).read(campusApiProvider).chats;
    const body = MessageInput(
      clientId: '01890a5d-ac96-774b-bcce-b302099a8057',
      text: 'hello',
    );

    final sent = await chats.sendMessage(
      chatId: chat['id']! as String,
      body: body,
    );
    final repeated = await chats.sendMessage(
      chatId: chat['id']! as String,
      body: body,
    );

    expect(sent.id, message['id']);
    expect(repeated.id, message['id']);
    final requests = sentTo('/api/v1/chats/${chat['id']}/messages');
    expect(requests, hasLength(2));
    expect(requests.map((request) => request.method), everyElement('POST'));
    expect(
      requests.map((request) => request.headers['Idempotency-Key']).toSet(),
      hasLength(2),
    );
    expect(requests.map((request) => request.json['client_id']).toSet(), {
      body.clientId,
    });
  });
}
