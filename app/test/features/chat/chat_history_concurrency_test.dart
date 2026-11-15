import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/chat/application/chat_config.dart';
import 'package:campus/src/features/chat/application/chat_history.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:campus/src/features/chat/data/chat_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'chat_fixtures.dart';

/// A store whose save can be paused for one message text.
///
/// The pause happens before SQLite is touched, so the test can land another
/// history update exactly in the window between a caller's snapshot and its
/// post-await state publication.
class _GatedChatStore extends ChatStore {
  _GatedChatStore(super.db);

  String? _text;
  Completer<void>? _gate;
  Completer<void>? entered;

  void gateSave(String text) {
    _text = text;
    _gate = Completer<void>();
    entered = Completer<void>();
  }

  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> saveMessages(
    String owner,
    String chatId,
    Iterable<MessageOutput> messages,
  ) async {
    final text = _text;
    final gate = _gate;
    if (text != null &&
        gate != null &&
        messages.any((message) => message.text == text)) {
      final entered = this.entered;
      if (entered != null && !entered.isCompleted) entered.complete();
      await gate.future;
    }
    await super.saveMessages(owner, chatId, messages);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chatId = testChatId;

  late FakeChatApi api;
  late _GatedChatStore store;
  late ProviderContainer container;

  Future<void> create({
    required List<MessageOutput> messages,
    int? pageLimit,
  }) async {
    api = FakeChatApi(
      messages: {
        chatId: [...messages],
      },
    )..pageLimit = pageLimit;
    store = _GatedChatStore(createTestDatabase());
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(store.db),
        chatStoreProvider.overrideWithValue(store),
        chatApiProvider.overrideWithValue(api),
        chatConfigProvider.overrideWithValue(
          const ChatConfig(maxMessageLength: 4000, retryDelays: []),
        ),
        ...apiOverrides(adapter: FakeHttpAdapter(), secure: signedInStorage),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
  }

  Future<ChatHistory> open() async {
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    final history = container.read(provider.notifier);
    await container.read(provider.future);
    return history;
  }

  ChatHistoryState stateOf() =>
      container.read(chatHistoryProvider(chatId)).value!;

  test(
    'sync keeps an older page and a delivered message from its save window',
    () async {
      await create(
        messages: [
          messageJson(chatId: chatId, sequence: 1, text: 'older'),
          messageJson(chatId: chatId, sequence: 2, text: 'second'),
          messageJson(chatId: chatId, sequence: 3, text: 'third'),
        ],
        pageLimit: 2,
      );
      final history = await open();
      expect(stateOf().messages.map((message) => message.sequence), [2, 3]);
      expect(stateOf().nextPage, '2');

      store.gateSave('gap');
      api.messages[chatId]!.add(
        messageJson(chatId: chatId, sequence: 4, text: 'gap'),
      );
      final sync = history.sync();
      await store.entered!.future;

      await history.loadOlder();
      expect(stateOf().nextPage, isNull);
      await history.mergeDelivered(
        messageJson(chatId: chatId, sequence: 5, text: 'delivered'),
      );

      store.release();
      await sync;

      expect(stateOf().messages.map((message) => message.sequence), [
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(stateOf().nextPage, isNull);
      expect(stateOf().syncError, isNull);
    },
  );

  test('mergeDelivered keeps an older page loaded during its save', () async {
    await create(
      messages: [
        messageJson(chatId: chatId, sequence: 1, text: 'older'),
        messageJson(chatId: chatId, sequence: 2, text: 'second'),
        messageJson(chatId: chatId, sequence: 3, text: 'third'),
      ],
      pageLimit: 2,
    );
    final history = await open();
    expect(stateOf().nextPage, '2');

    store.gateSave('delivered');
    final merge = history.mergeDelivered(
      messageJson(chatId: chatId, sequence: 4, text: 'delivered'),
    );
    await store.entered!.future;

    await history.loadOlder();
    expect(stateOf().nextPage, isNull);

    store.release();
    await merge;

    expect(stateOf().messages.map((message) => message.sequence), [1, 2, 3, 4]);
    expect(stateOf().nextPage, isNull);
  });

  test(
    'mergeDelivered does not restore a stale sync error after a retry',
    () async {
      await create(
        messages: [messageJson(chatId: chatId, sequence: 1, text: 'first')],
      );
      final history = await open();
      final realtime = FakeChatRealtime();
      addTearDown(history.unwatchRealtime);
      await history.watchRealtime(realtime);

      api.listError = const NetworkFailure();
      realtime.emit();
      await pumpEventQueue(times: 40);
      expect(stateOf().syncError, isA<NetworkFailure>());

      api.messages[chatId]!.add(
        messageJson(chatId: chatId, sequence: 2, text: 'gap'),
      );
      store.gateSave('delivered');
      final merge = history.mergeDelivered(
        messageJson(chatId: chatId, sequence: 3, text: 'delivered'),
      );
      await store.entered!.future;

      // The successful retry clears the banner while mergeDelivered is still
      // saving its row. The late merge must not bring the old error back.
      await history.sync();
      expect(stateOf().syncError, isNull);

      store.release();
      await merge;

      expect(stateOf().messages.map((message) => message.sequence), [1, 2, 3]);
      expect(stateOf().syncError, isNull);
    },
  );
}
