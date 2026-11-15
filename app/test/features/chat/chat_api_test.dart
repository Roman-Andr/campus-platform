import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter server;
  late ProviderContainer container;
  late ChatApi api;

  setUp(() async {
    server = FakeHttpAdapter();
    container = ProviderContainer(
      overrides: apiOverrides(adapter: server, secure: signedInStorage),
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    api = container.read(chatApiProvider);
  });

  test(
    'sends the persisted Idempotency-Key and accepts a 200 success',
    () async {
      final message = messageJson(
        chatId: testChatId,
        sequence: 1,
        text: 'hello',
      );
      server.route(
        (options) => options.path == '/api/v1/auth/token/refresh'
            ? jsonBody(200, tokensJson(1))
            : jsonBody(200, message.toJson()),
      );
      const key = '01890a5d-ac96-774b-bcce-b302099a8061';

      final stored = await api.sendMessage(
        testChatId,
        clientId: message.clientId,
        text: 'hello',
        idempotencyKey: key,
      );

      expect(stored.id, message.id);
      final request = server.sent.last;
      expect(request.path, '/api/v1/chats/$testChatId/messages');
      expect(request.headers['Idempotency-Key'], key);
      expect(request.json['client_id'], message.clientId);
      expect(request.json['text'], 'hello');
    },
  );

  test('accepts a 200 stored dialog from the generated client', () async {
    final chat = chatJson(id: testChatId);
    server.route(
      (options) => options.path == '/api/v1/auth/token/refresh'
          ? jsonBody(200, tokensJson(1))
          : jsonBody(200, chat.toJson()),
    );

    final stored = await api.createChat(
      recipientId: '01890a5d-ac96-774b-bcce-b302099a8059',
      listingId: 'listing-1',
    );

    expect(stored.id, testChatId);
    final request = server.sent.last;
    expect(request.path, '/api/v1/chats');
    expect(
      request.json['recipient_id'],
      '01890a5d-ac96-774b-bcce-b302099a8059',
    );
    expect(request.json['listing_id'], 'listing-1');
  });
}
