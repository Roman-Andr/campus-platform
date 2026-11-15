import 'dart:async';
import 'dart:io';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/api/network_status.dart';
import 'package:campus/src/core/auth/auth_service.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_token.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/chat/application/chat_config.dart';
import 'package:campus/src/features/chat/application/chat_queue.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:campus/src/features/chat/data/chat_store.dart';
import 'package:campus/src/features/chat/domain/chat.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FakeChatApi api;
  late FakeHttpAdapter server;
  late ProviderContainer container;

  List<Override> overridesFor(AppDatabase db, FakeChatApi chatApi) => [
    appDatabaseProvider.overrideWithValue(db),
    chatApiProvider.overrideWithValue(chatApi),
    chatConfigProvider.overrideWithValue(
      const ChatConfig(maxMessageLength: 4000, retryDelays: []),
    ),
    ...apiOverrides(adapter: server, secure: signedInStorage),
  ];

  Future<void> create({
    AppDatabase? db,
    FakeChatApi? chatApi,
    bool signedIn = true,
  }) async {
    database = db ?? createTestDatabase();
    api = chatApi ?? FakeChatApi();
    server = FakeHttpAdapter();
    container = ProviderContainer(overrides: overridesFor(database, api));
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    if (!signedIn) await container.read(authServiceProvider).signOut();
  }

  test('outbox survives an offline process restart', () async {
    final directory = await Directory.systemTemp.createTemp('campus-chat-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/chat.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await create(db: db);
    container.read(networkStatusProvider.notifier).unreachable();
    final queue = container.read(chatQueueProvider.notifier);
    final queued = await queue.send('chat-1', 'survives a restart');
    expect(UuidValue.withValidation(queued.clientId).version, 7);
    expect(
      (container.read(chatQueueProvider).value?.messages ?? []).single.text,
      'survives a restart',
    );
    await pumpEventQueue();
    expect(api.sendCalls, isEmpty);
    container.dispose();
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    await create(db: db, chatApi: api);
    addTearDown(db.close);
    container.read(networkStatusProvider.notifier).unreachable();
    final restored = await container.read(chatQueueProvider.future);
    expect(restored.messages, hasLength(1));
    expect(restored.messages.single.clientId, queued.clientId);
    expect(restored.messages.single.idempotencyKey, queued.idempotencyKey);
    expect(restored.messages.single.text, 'survives a restart');

    container.read(networkStatusProvider.notifier).reachable();
    await pumpEventQueue(times: 60);
    expect(api.sendCalls, hasLength(1));
    expect(api.sendCalls.single.key, queued.idempotencyKey);
    expect(api.sendCalls.single.clientId, queued.clientId);
    expect(container.read(chatQueueProvider).value?.messages, isEmpty);
  });

  test(
    'sends a message of 4000 code points with a longer UTF-16 length',
    () async {
      await create();
      final text = '👍' * 3000;
      expect(text.length, 6000);

      final sent = await container
          .read(chatQueueProvider.notifier)
          .send('chat-1', text);
      await pumpEventQueue(times: 80);

      expect(sent.text, text);
      expect(api.sendCalls.single.text, text);
      expect(container.read(chatQueueProvider).value?.messages, isEmpty);
    },
  );

  test(
    'discarding a refused head lets later messages of the chat go',
    () async {
      await create();
      api.sendError = const ProblemFailure(
        Problem(
          type: 'urn:problem:campus:chat_message_invalid',
          title: 'Invalid message',
          status: 422,
          code: ProblemCode.chatMessageInvalid,
        ),
      );
      final queue = container.read(chatQueueProvider.notifier);
      final refused = await queue.send('chat-1', 'bad');
      await pumpEventQueue(times: 60);
      expect(api.sendCalls, hasLength(1));
      expect(
        container.read(chatQueueProvider).value?.messages.single.state,
        OutgoingChatState.failed,
      );

      await queue.send('chat-1', 'good');
      await pumpEventQueue(times: 40);
      // The refused head still blocks the chat.
      expect(api.sendCalls, hasLength(1));

      await queue.discard('chat-1', refused.clientId);
      await pumpEventQueue(times: 80);

      expect(api.sendCalls.map((call) => call.text), ['bad', 'good']);
      expect(container.read(chatQueueProvider).value?.messages, isEmpty);
    },
  );

  test('sends sequentially with a stable UUID and idempotency key', () async {
    await create();
    final gate = Completer<void>();
    api.sendGate = gate;

    final first = await container
        .read(chatQueueProvider.notifier)
        .send('chat-1', 'first');
    await pumpEventQueue();
    expect(api.sendCalls, hasLength(1));
    expect(api.sendCalls.single.clientId, first.clientId);
    expect(UuidValue.withValidation(first.clientId).version, 7);
    expect(UuidValue.withValidation(first.idempotencyKey).version, 7);

    final second = await container
        .read(chatQueueProvider.notifier)
        .send('chat-1', 'second');
    final third = await container
        .read(chatQueueProvider.notifier)
        .send('chat-1', 'third');
    await pumpEventQueue();
    // The first request is still in flight; nothing overtakes it.
    expect(api.sendCalls, hasLength(1));

    api.sendGate = null;
    gate.complete();
    await pumpEventQueue(times: 100);

    expect(api.sendCalls.map((call) => call.text), [
      'first',
      'second',
      'third',
    ]);
    expect(api.sendCalls.map((call) => call.clientId).toSet(), {
      first.clientId,
      second.clientId,
      third.clientId,
    });
    expect(container.read(chatQueueProvider).value?.messages, isEmpty);
  });

  test(
    'a lost response is retried with the same key and stores one message',
    () async {
      await create();
      final queue = container.read(chatQueueProvider.notifier);
      api.loseNextResponse = true;

      final sent = await queue.send('chat-1', 'only once');
      await pumpEventQueue(times: 60);

      expect(api.sendCalls, hasLength(1));
      final pending = container.read(chatQueueProvider).value!.messages.single;
      expect(pending.clientId, sent.clientId);
      expect(pending.state, OutgoingChatState.pending);
      expect(pending.failure, isNotNull);

      await queue.drain();
      await pumpEventQueue(times: 60);

      expect(api.sendCalls, hasLength(2));
      expect(api.sendCalls[1].key, api.sendCalls[0].key);
      expect(api.sendCalls[1].clientId, api.sendCalls[0].clientId);
      expect(api.messages['chat-1'], hasLength(1));
      expect(container.read(chatQueueProvider).value?.messages, isEmpty);
    },
  );

  test(
    'waits for the network and resumes in order after reconnection',
    () async {
      await create();
      container.read(networkStatusProvider.notifier).unreachable();
      final queue = container.read(chatQueueProvider.notifier);
      await queue.send('chat-1', 'offline message');
      await pumpEventQueue();
      expect(api.sendCalls, isEmpty);

      container.read(networkStatusProvider.notifier).reachable();
      await pumpEventQueue(times: 80);

      expect(api.sendCalls, hasLength(1));
      expect(api.sendCalls.single.text, 'offline message');
      expect(container.read(chatQueueProvider).value?.messages, isEmpty);
    },
  );

  test('does not clear the durable outbox while auth is loading', () async {
    final db = createTestDatabase();
    server = FakeHttpAdapter();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chatApiProvider.overrideWithValue(api = FakeChatApi()),
        chatConfigProvider.overrideWithValue(
          const ChatConfig(maxMessageLength: 4000, retryDelays: []),
        ),
        ...apiOverrides(adapter: server, secure: signedInStorage),
      ],
    );
    addTearDown(container.dispose);
    final owner = await container.read(authStorageProvider).cacheNamespace();
    await ChatStore(db).enqueue(
      owner: owner,
      chatId: 'chat-1',
      clientId: const Uuid().v7(),
      idempotencyKey: const Uuid().v7(),
      text: 'kept while auth loads',
      createdAt: DateTime.utc(2026, 11, 14, 12),
    );

    // Do not wait for authStatus: the queue sees AsyncLoading first.
    final loading = await container.read(chatQueueProvider.future);
    expect(loading.messages, isEmpty);
    expect(await db.select(db.chatOutbox).get(), hasLength(1));

    await container.read(authStatusProvider.future);
    final restored = await container.read(chatQueueProvider.future);
    expect(restored.messages.single.text, 'kept while auth loads');
  });

  test('sign-out during a send clears old data and the next account starts '
      'empty; the late response is ignored', () async {
    await create();
    final delivered = <Object>[];
    final subscription = container
        .read(chatQueueProvider.notifier)
        .delivered
        .listen(delivered.add);
    addTearDown(subscription.cancel);

    final gate = Completer<void>();
    api.sendGate = gate;
    final old = await container
        .read(chatQueueProvider.notifier)
        .send('chat-1', 'old account');
    await pumpEventQueue();
    expect(api.sendCalls, hasLength(1));

    server.reply(204);
    await container.read(authServiceProvider).signOut();
    await pumpEventQueue(times: 40);
    expect(
      container.read(authStatusProvider).value,
      AuthenticationStatus.unauthenticated,
    );
    expect(await database.select(database.chatOutbox).get(), isEmpty);

    // A new account signs in on the same installation.
    await container
        .read(authStorageProvider)
        .write(const AuthToken.restored('new-refresh-token'));
    container.invalidate(authStatusProvider);
    await container.read(authStatusProvider.future);
    await pumpEventQueue(times: 40);
    await container.read(chatQueueProvider.future);

    // The old request finishes after the account switch: its response must
    // not be written to the new account or shown as delivered.
    api.sendGate = null;
    gate.complete();
    await pumpEventQueue(times: 80);
    expect(delivered, isEmpty);
    expect(await database.select(database.chatMessages).get(), isEmpty);
    expect(await database.select(database.chatOutbox).get(), isEmpty);

    final current = await container
        .read(chatQueueProvider.notifier)
        .send('chat-1', 'new account');
    await pumpEventQueue(times: 80);
    expect(current.text, 'new account');
    expect(api.sendCalls.last.text, 'new account');
    expect(api.sendCalls.last.clientId, isNot(old.clientId));
    expect(api.sendCalls.last.clientId, current.clientId);
    expect(await database.select(database.chatMessages).get(), hasLength(1));
  });

  test(
    'runtime listener sends saved messages without opening a chat',
    () async {
      await create();
      final owner = await container.read(authStorageProvider).cacheNamespace();
      await ChatStore(database).enqueue(
        owner: owner,
        chatId: testChatId,
        clientId: const Uuid().v7(),
        idempotencyKey: const Uuid().v7(),
        text: 'sent on app start',
        createdAt: DateTime.utc(2026, 11, 14, 12),
      );

      // No screen or service reads the queue: the app runtime owner starts it.
      final runtime = startChatQueueRuntime(container);
      addTearDown(runtime.close);
      await pumpEventQueue(times: 100);

      expect(api.sendCalls, hasLength(1));
      expect(api.sendCalls.single.text, 'sent on app start');
      expect(await database.select(database.chatOutbox).get(), isEmpty);
    },
  );

  test(
    'runtime sign-out clears private chat rows without a chat screen',
    () async {
      await create();
      container.read(networkStatusProvider.notifier).unreachable();
      final owner = await container.read(authStorageProvider).cacheNamespace();
      final store = ChatStore(database);
      await store.enqueue(
        owner: owner,
        chatId: testChatId,
        clientId: const Uuid().v7(),
        idempotencyKey: const Uuid().v7(),
        text: 'private',
        createdAt: DateTime.utc(2026, 11, 14, 12),
      );
      await store.saveMessages(owner, testChatId, [
        messageJson(chatId: testChatId, sequence: 1),
      ]);
      await store.upsertDialogs(owner, [chatJson(id: testChatId)]);
      final runtime = startChatQueueRuntime(container);
      addTearDown(runtime.close);
      await pumpEventQueue();

      server.reply(204);
      await container.read(authServiceProvider).signOut();
      await pumpEventQueue(times: 100);

      expect(await database.select(database.chatOutbox).get(), isEmpty);
      expect(await database.select(database.chatMessages).get(), isEmpty);
      expect(await database.select(database.chatDialogs).get(), isEmpty);
    },
  );

  test('account rows are isolated by the local session owner', () async {
    await create();
    final store = ChatStore(database);
    final owner = await container.read(authStorageProvider).cacheNamespace();
    await store.enqueue(
      owner: owner,
      chatId: 'chat-1',
      clientId: const Uuid().v7(),
      idempotencyKey: const Uuid().v7(),
      text: 'mine',
      createdAt: DateTime.utc(2026, 11, 14, 12),
    );
    expect(await store.loadOutbox(owner, chatId: 'chat-1'), hasLength(1));
    expect(
      await store.loadOutbox('another-session', chatId: 'chat-1'),
      isEmpty,
    );
    expect(await store.loadMessages('another-session', 'chat-1'), isEmpty);
  });
}
