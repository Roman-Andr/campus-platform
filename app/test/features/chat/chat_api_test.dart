import 'package:campus/src/core/api/generated/campus_api.dart';
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

  test('passes the query, cursor and size to chat search', () async {
    final result = ChatSearchResult(
      chat: chatJson(id: testChatId),
      message: messageJson(
        chatId: testChatId,
        sequence: 7,
        text: 'bicycle route',
      ),
      snippet: '…bicycle route…',
    );
    final page = PageChatSearchResult(items: [result], nextPage: 'cursor-2');
    server.route(
      (options) => options.path == '/api/v1/chats/search'
          ? jsonBody(200, page.toJson())
          : jsonBody(200, tokensJson(1)),
    );

    final found = await api.searchChats(
      query: 'bicycle',
      cursor: 'cursor-1',
      size: 10,
    );

    expect(found.items.single.snippet, '…bicycle route…');
    final request = server.sent.last;
    expect(request.method, 'GET');
    expect(request.path, '/api/v1/chats/search');
    expect(request.query, {'q': 'bicycle', 'cursor': 'cursor-1', 'size': 10});
  });

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

  test('edits a message with the caller Idempotency-Key', () async {
    final edited = messageJson(
      chatId: testChatId,
      sequence: 1,
      text: 'edited',
      version: 2,
    );
    server.route(
      (options) => options.path == '/api/v1/auth/token/refresh'
          ? jsonBody(200, tokensJson(1))
          : jsonBody(200, edited.toJson()),
    );
    const key = '01890a5d-ac96-774b-bcce-b302099a8071';

    final result = await api.editMessage(
      testChatId,
      edited.id,
      text: 'edited',
      idempotencyKey: key,
    );

    expect(result.text, 'edited');
    expect(result.version, 2);
    final request = server.sent.last;
    expect(request.method, 'PATCH');
    expect(request.path, '/api/v1/chats/$testChatId/messages/${edited.id}');
    expect(request.headers['Idempotency-Key'], key);
    expect(request.json['text'], 'edited');
  });

  test('deletes a message with the caller Idempotency-Key', () async {
    server
      ..reply(200, tokensJson(1))
      ..reply(204);
    const key = '01890a5d-ac96-774b-bcce-b302099a8072';

    await api.deleteMessage(testChatId, 'server-1', idempotencyKey: key);

    final request = server.sent.last;
    expect(request.method, 'DELETE');
    expect(request.path, '/api/v1/chats/$testChatId/messages/server-1');
    expect(request.headers['Idempotency-Key'], key);
  });

  test('sends the quote and the ready photo ids', () async {
    final message = messageJson(
      chatId: testChatId,
      sequence: 4,
      replyToId: 'server-1',
      photoIds: const ['photo-1', 'photo-2'],
    );
    server.route(
      (options) => options.path == '/api/v1/auth/token/refresh'
          ? jsonBody(200, tokensJson(1))
          : jsonBody(201, message.toJson()),
    );

    await api.sendMessage(
      testChatId,
      clientId: message.clientId,
      text: 'hello',
      idempotencyKey: '01890a5d-ac96-774b-bcce-b302099a8073',
      replyToId: 'server-1',
      photoIds: const ['photo-1', 'photo-2'],
    );

    final request = server.sent.last;
    expect(request.json['reply_to_id'], 'server-1');
    expect(request.json['photo_ids'], ['photo-1', 'photo-2']);
  });

  test('requests, completes and lists chat photos', () async {
    final file = ChatFileOutput(
      id: 'file-1',
      purpose: 'chat_photo',
      status: 'pending',
      size: 100,
      rejectionReason: null,
      expiresAt: DateTime.utc(2026, 11, 15, 13),
    );
    server
      ..reply(200, tokensJson(1))
      ..reply(201, {
        'file': file.toJson(),
        'url': 'https://storage.test/upload',
        'fields': {'key': 'value'},
        'expires_at': '2026-11-15T13:00:00Z',
      })
      ..reply(202, {...file.toJson(), 'status': 'processing'})
      ..reply(200, {
        'items': [
          {
            'id': 'photo-1',
            'url': 'https://storage.test/one',
            'preview_url': 'https://storage.test/one-preview',
            'expires_at': '2026-11-15T13:05:00Z',
          },
        ],
      });

    const uploadKey = '01890a5d-ac96-774b-bcce-b302099a8074';
    const completeKey = '01890a5d-ac96-774b-bcce-b302099a8075';
    final upload = await api.requestChatPhoto(
      testChatId,
      idempotencyKey: uploadKey,
    );
    final completed = await api.completeChatPhoto(
      testChatId,
      upload.file.id,
      idempotencyKey: completeKey,
    );
    final photos = await api.listMessagePhotos(testChatId, 'server-1');

    expect(upload.url, 'https://storage.test/upload');
    expect(upload.fields['key'], 'value');
    expect(completed.status, 'processing');
    expect(photos.items.single.url, 'https://storage.test/one');
    final requests = server.sent
        .where((request) => request.path.contains('/chats/'))
        .toList();
    expect(requests[0].path, '/api/v1/chats/$testChatId/photo-uploads');
    expect(
      requests[1].path,
      '/api/v1/chats/$testChatId/photo-uploads/file-1/complete',
    );
    expect(
      requests[2].path,
      '/api/v1/chats/$testChatId/messages/server-1/photos',
    );
    expect(requests[0].headers['Idempotency-Key'], uploadKey);
    expect(requests[1].headers['Idempotency-Key'], completeKey);
  });
}
