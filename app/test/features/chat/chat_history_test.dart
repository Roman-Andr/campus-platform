import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/chat/application/chat_config.dart';
import 'package:campus/src/features/chat/application/chat_history.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chatId = testChatId;

  late FakeChatApi api;
  late ProviderContainer container;

  Future<void> create({List<MessageOutput> messages = const []}) async {
    api = FakeChatApi(
      messages: {
        chatId: [...messages],
      },
    );
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(createTestDatabase()),
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

  test('orders a descending page by the server sequence', () async {
    await create(
      messages: [
        messageJson(chatId: chatId, sequence: 5, text: 'fifth'),
        messageJson(chatId: chatId, sequence: 2, text: 'second'),
      ],
    );
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);

    final state = await container.read(provider.future);

    expect(state.messages.map((message) => message.sequence), [2, 5]);
    expect(state.messages.map((message) => message.text), ['second', 'fifth']);
  });

  test('coalesces a wakeup received during an in-flight sync', () async {
    await create(
      messages: [messageJson(chatId: chatId, sequence: 1, text: 'first')],
    );
    final history = container.read(chatHistoryProvider(chatId).notifier);
    final listener = container.listen(chatHistoryProvider(chatId), (_, _) {});
    addTearDown(listener.close);
    await container.read(chatHistoryProvider(chatId).future);

    final gate = Completer<void>();
    api.listGate = gate;
    final firstSync = history.sync();
    await pumpEventQueue();
    expect(api.listMessageCalls, hasLength(2));

    // The second wakeup happens while the first response is still on the
    // wire; the response may predate this message.
    api.messages[chatId]!.add(
      messageJson(chatId: chatId, sequence: 3, text: 'arrived during sync'),
    );
    final secondSync = history.sync();
    gate.complete();
    await Future.wait([firstSync, secondSync]);
    await pumpEventQueue();

    final state = container.read(chatHistoryProvider(chatId)).value!;
    expect(state.messages.map((message) => message.sequence), [1, 3]);
    // The coalesced pass made another request after the first response.
    expect(api.listMessageCalls.length, greaterThanOrEqualTo(3));
  });

  test(
    'multi-page forward recovery does not publish an older cursor',
    () async {
      await create(messages: [messageJson(chatId: chatId, sequence: 1)]);
      final provider = chatHistoryProvider(chatId);
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      final history = container.read(provider.notifier);
      final initial = await container.read(provider.future);
      expect(initial.nextPage, isNull);

      api.pageLimit = 1;
      api.messages[chatId]!.addAll([
        messageJson(chatId: chatId, sequence: 2),
        messageJson(chatId: chatId, sequence: 3),
        messageJson(chatId: chatId, sequence: 4),
      ]);
      await history.sync();

      final recovered = container.read(provider).value!;
      expect(recovered.messages.map((message) => message.sequence), [
        1,
        2,
        3,
        4,
      ]);
      // The cursor of the forward pages points at sequence 2 while the next
      // request still filters after sequence 1; it must not become the older
      // history cursor used by loadOlder.
      expect(recovered.nextPage, isNull);
      final calls = api.listMessageCalls.skip(1).toList();
      expect(calls.length, greaterThanOrEqualTo(3));
      expect(calls.first.after, 1);
      expect(calls.first.ascending, isTrue);

      final callsBefore = api.listMessageCalls.length;
      await history.loadOlder();
      expect(api.listMessageCalls.length, callsBefore);
    },
  );

  test('forward sync keeps an older cursor that was already loaded', () async {
    await create(
      messages: [
        messageJson(chatId: chatId, sequence: 1),
        messageJson(chatId: chatId, sequence: 2),
        messageJson(chatId: chatId, sequence: 3),
      ],
    );
    api.pageLimit = 2;
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    final history = container.read(provider.notifier);
    final initial = await container.read(provider.future);
    expect(initial.messages.map((message) => message.sequence), [2, 3]);
    expect(initial.nextPage, '2');

    api.messages[chatId]!.add(messageJson(chatId: chatId, sequence: 4));
    await history.sync();

    final synced = container.read(provider).value!;
    expect(synced.messages.map((message) => message.sequence), [2, 3, 4]);
    expect(synced.nextPage, '2');

    await history.loadOlder();
    final all = container.read(provider).value!;
    expect(all.messages.map((message) => message.sequence), [1, 2, 3, 4]);
    expect(all.nextPage, isNull);
  });

  test('the initial page still supplies the older-history cursor', () async {
    await create(
      messages: [
        messageJson(chatId: chatId, sequence: 1),
        messageJson(chatId: chatId, sequence: 2),
        messageJson(chatId: chatId, sequence: 3),
      ],
    );
    api.pageLimit = 2;
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    final history = container.read(provider.notifier);

    final initial = await container.read(provider.future);
    expect(initial.messages.map((message) => message.sequence), [2, 3]);
    expect(initial.nextPage, '2');

    await history.loadOlder();
    final all = container.read(provider).value!;
    expect(all.messages.map((message) => message.sequence), [1, 2, 3]);
    expect(all.nextPage, isNull);
  });

  test('a realtime event reloads the gap through the API', () async {
    await create(messages: [messageJson(chatId: chatId, sequence: 1)]);
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final realtime = FakeChatRealtime();
    final history = container.read(provider.notifier);

    await history.watchRealtime(realtime);
    expect(realtime.subscribeCalls, 1);
    api.messages[chatId]!.add(
      messageJson(chatId: chatId, sequence: 4, text: 'from another device'),
    );
    realtime.emit();
    await pumpEventQueue(times: 60);

    final state = container.read(provider).value!;
    expect(state.messages.map((message) => message.sequence), [1, 4]);
    expect(state.messages.last.text, 'from another device');
    await history.unwatchRealtime();
    expect(realtime.subscription?.closed, isTrue);
  });

  test('a failed realtime sync stays visible and can be retried', () async {
    await create(messages: [messageJson(chatId: chatId, sequence: 1)]);
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final realtime = FakeChatRealtime();
    final history = container.read(provider.notifier);
    await history.watchRealtime(realtime);

    api.listError = const NetworkFailure();
    api.messages[chatId]!.add(
      messageJson(chatId: chatId, sequence: 2, text: 'missed while failing'),
    );
    realtime.emit();
    await pumpEventQueue(times: 40);

    final stale = container.read(provider).value!;
    expect(stale.syncError, isA<NetworkFailure>());
    expect(stale.messages.map((message) => message.sequence), [1]);

    await history.retrySync();
    await pumpEventQueue(times: 40);

    final fresh = container.read(provider).value!;
    expect(fresh.syncError, isNull);
    expect(fresh.messages.map((message) => message.sequence), [1, 2]);
    await history.unwatchRealtime();
  });

  test('an exhausted realtime history reloads the missed messages', () async {
    await create(messages: [messageJson(chatId: chatId, sequence: 1)]);
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final realtime = FakeChatRealtime();
    final history = container.read(provider.notifier);
    await history.watchRealtime(realtime);

    api.messages[chatId]!.addAll([
      messageJson(chatId: chatId, sequence: 2, text: 'missed two'),
      messageJson(chatId: chatId, sequence: 3, text: 'missed three'),
    ]);
    await realtime.reload!();
    await pumpEventQueue(times: 60);

    expect(
      container
          .read(provider)
          .value!
          .messages
          .map((message) => message.sequence),
      [1, 2, 3],
    );
    await history.unwatchRealtime();
  });

  test(
    'a forbidden dialog surfaces a chat problem and keeps no data',
    () async {
      await create();
      api.listError = const ProblemFailure(
        Problem(
          type: 'urn:problem:campus:chat_not_found',
          title: 'Chat not found',
          status: 404,
          code: ProblemCode.chatNotFound,
        ),
      );
      final provider = chatHistoryProvider(chatId);
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);

      await expectLater(
        container.read(provider.future),
        throwsA(isA<ProblemFailure>()),
      );
    },
  );
}
