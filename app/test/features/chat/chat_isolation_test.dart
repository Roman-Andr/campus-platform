import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_service.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_token.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/chat/application/chat_config.dart';
import 'package:campus/src/features/chat/application/chat_history.dart';
import 'package:campus/src/features/chat/application/chats.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:campus/src/features/chat/data/chat_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chatId = testChatId;
  const otherChatId = '01890a5d-ac96-774b-bcce-b302099a8061';

  late FakeChatApi api;
  late FakeHttpAdapter server;
  late ProviderContainer container;

  Future<void> create({
    List<MessageOutput> messages = const [],
    List<ChatOutput>? chats,
  }) async {
    api = FakeChatApi(
      chats: chats ?? [chatJson()],
      messages: {
        chatId: [...messages],
      },
    );
    server = FakeHttpAdapter();
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(createTestDatabase()),
        chatApiProvider.overrideWithValue(api),
        chatConfigProvider.overrideWithValue(
          const ChatConfig(maxMessageLength: 4000, retryDelays: []),
        ),
        ...apiOverrides(adapter: server, secure: signedInStorage),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
  }

  Future<String> owner() =>
      container.read(authStorageProvider).cacheNamespace();

  Future<void> signInAsB() async {
    server.reply(204);
    await container.read(authServiceProvider).signOut();
    await container
        .read(authStorageProvider)
        .write(const AuthToken.restored('account-b-refresh'));
    container.invalidate(authStatusProvider);
    await container.read(authStatusProvider.future);
  }

  ChatStore store() => ChatStore(container.read(appDatabaseProvider));

  test('an old history build cannot publish into account B', () async {
    await create(
      messages: [messageJson(chatId: chatId, sequence: 1, text: 'account A')],
    );
    final ownerA = await owner();
    final gate = Completer<void>();
    api.listGate = gate;
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);

    final oldBuild = container.read(provider.future);
    await pumpEventQueue();
    expect(api.listMessageCalls, hasLength(1));

    api.listGate = null;
    api.messages[chatId] = [
      messageJson(chatId: chatId, sequence: 1, text: 'account B'),
    ];
    await signInAsB();
    final ownerB = await owner();
    expect(ownerB, isNot(ownerA));
    final current = await container.read(provider.future);
    expect(current.messages.single.text, 'account B');
    expect(
      (await store().loadMessages(ownerB, chatId)).single.text,
      'account B',
    );
    expect(await store().loadMessages(ownerA, chatId), isEmpty);

    gate.complete();
    await oldBuild.then((_) {}, onError: (_) {});
    await pumpEventQueue(times: 40);

    final state = container.read(provider).value!;
    expect(state.messages.single.text, 'account B');
    expect(
      (await store().loadMessages(ownerB, chatId)).single.text,
      'account B',
    );
    expect(await store().loadMessages(ownerA, chatId), isEmpty);
  });

  test('an old history sync cannot publish into account B', () async {
    await create(
      messages: [messageJson(chatId: chatId, sequence: 1, text: 'account A')],
    );
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final history = container.read(provider.notifier);

    final gate = Completer<void>();
    api.listGate = gate;
    final oldSync = history.sync();
    await pumpEventQueue();
    expect(api.listMessageCalls, hasLength(2));

    api.listGate = null;
    api.messages[chatId] = [
      messageJson(chatId: chatId, sequence: 1, text: 'account B'),
    ];
    await signInAsB();
    final ownerB = await owner();
    final current = await container.read(provider.future);
    expect(current.messages.single.text, 'account B');

    gate.complete();
    await oldSync;
    await pumpEventQueue(times: 40);

    final state = container.read(provider).value!;
    expect(state.messages.single.text, 'account B');
    expect(
      (await store().loadMessages(ownerB, chatId)).single.text,
      'account B',
    );
  });

  test('an old history page cannot publish into account B', () async {
    await create(
      messages: [
        messageJson(chatId: chatId, sequence: 1, text: 'A older'),
        messageJson(chatId: chatId, sequence: 2, text: 'A newer'),
        messageJson(chatId: chatId, sequence: 3, text: 'A newest'),
      ],
    );
    api.pageLimit = 2;
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    final initial = await container.read(provider.future);
    expect(initial.messages.map((message) => message.sequence), [2, 3]);
    expect(initial.nextPage, '2');
    final history = container.read(provider.notifier);

    final gate = Completer<void>();
    api.listGate = gate;
    final oldPage = history.loadOlder();
    await pumpEventQueue();

    api.listGate = null;
    api.messages[chatId] = [
      messageJson(chatId: chatId, sequence: 5, text: 'account B'),
    ];
    await signInAsB();
    final ownerB = await owner();
    final current = await container.read(provider.future);
    expect(current.messages.single.text, 'account B');

    gate.complete();
    await oldPage;
    await pumpEventQueue(times: 40);

    final state = container.read(provider).value!;
    expect(state.messages.single.text, 'account B');
    expect(
      (await store().loadMessages(ownerB, chatId)).single.text,
      'account B',
    );
  });

  test('an old dialogs build cannot publish into account B', () async {
    await create(chats: [chatJson(id: chatId)]);
    final ownerA = await owner();
    final gate = Completer<void>();
    api.listChatsGate = gate;
    final provider = chatDialogsProvider;
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);

    final oldBuild = container.read(provider.future);
    await pumpEventQueue();

    api.listChatsGate = null;
    api.chats
      ..clear()
      ..add(chatJson(id: otherChatId));
    await signInAsB();
    final ownerB = await owner();
    expect(ownerB, isNot(ownerA));
    final current = await container.read(provider.future);
    expect(current.items.single.id, otherChatId);
    expect((await store().loadDialogs(ownerB)).single.id, otherChatId);
    expect(await store().loadDialogs(ownerA), isEmpty);

    gate.complete();
    await oldBuild.then((_) {}, onError: (_) {});
    await pumpEventQueue(times: 40);

    final state = container.read(provider).value!;
    expect(state.items.single.id, otherChatId);
    expect((await store().loadDialogs(ownerB)).single.id, otherChatId);
    expect(await store().loadDialogs(ownerA), isEmpty);
  });

  test('an old dialogs refresh cannot publish into account B', () async {
    await create(chats: [chatJson(id: chatId)]);
    final provider = chatDialogsProvider;
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final dialogs = container.read(provider.notifier);

    final gate = Completer<void>();
    api.listChatsGate = gate;
    final oldRefresh = dialogs.refresh();
    await pumpEventQueue();

    api.listChatsGate = null;
    api.chats
      ..clear()
      ..add(chatJson(id: otherChatId));
    await signInAsB();
    final ownerB = await owner();
    final current = await container.read(provider.future);
    expect(current.items.single.id, otherChatId);

    gate.complete();
    await oldRefresh;
    await pumpEventQueue(times: 40);

    final state = container.read(provider).value!;
    expect(state.items.single.id, otherChatId);
    expect((await store().loadDialogs(ownerB)).single.id, otherChatId);
  });

  test('an old full reconcile cannot publish into account B', () async {
    await create(
      messages: [
        messageJson(chatId: chatId, sequence: 1, text: 'A first'),
        messageJson(chatId: chatId, sequence: 2, text: 'A second'),
      ],
    );
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final history = container.read(provider.notifier);

    final gate = Completer<void>();
    api.listGate = gate;
    final oldReconcile = history.retrySync();
    await pumpEventQueue();

    api.listGate = null;
    api.messages[chatId] = [
      messageJson(chatId: chatId, sequence: 1, text: 'account B'),
    ];
    await signInAsB();
    final ownerB = await owner();
    final current = await container.read(provider.future);
    expect(current.messages.single.text, 'account B');

    gate.complete();
    await oldReconcile;
    await pumpEventQueue(times: 40);

    final state = container.read(provider).value!;
    expect(state.messages.single.text, 'account B');
    expect(
      (await store().loadMessages(ownerB, chatId)).single.text,
      'account B',
    );
  });
}
