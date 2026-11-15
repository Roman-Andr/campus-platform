import 'dart:async';

import 'package:campus/src/core/api/api_failure.dart';
import 'package:campus/src/core/api/generated/campus_api.dart';
import 'package:campus/src/features/chat/application/chat_search.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_fixtures.dart';

void main() {
  ChatSearchResult hit({
    required int sequence,
    required String text,
    String chatId = 'chat-1',
  }) => ChatSearchResult(
    chat: chatJson(id: chatId),
    message: messageJson(chatId: chatId, sequence: sequence, text: text),
    snippet: '...$text...',
  );

  late FakeChatApi api;
  late ProviderContainer container;

  void create() {
    api = FakeChatApi();
    container = ProviderContainer(
      overrides: [chatApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
  }

  test('normalizes a query and publishes the first page', () async {
    create();
    api.searchResults.addAll([
      hit(sequence: 3, text: 'bike three'),
      hit(sequence: 1, text: 'bike one'),
    ]);

    await container.read(chatSearchProvider.notifier).search('  bike  ');

    final state = container.read(chatSearchProvider);
    expect(api.searchCalls.single.query, 'bike');
    expect(state.query, 'bike');
    expect(state.phase, ChatSearchPhase.ready);
    expect(state.results.map((result) => result.message.sequence), [3, 1]);
  });

  test('an empty query resets without a request', () async {
    create();
    await container.read(chatSearchProvider.notifier).search('bike');
    api.searchCalls.clear();

    await container.read(chatSearchProvider.notifier).search('   ');

    expect(api.searchCalls, isEmpty);
    expect(container.read(chatSearchProvider).phase, ChatSearchPhase.idle);
    expect(container.read(chatSearchProvider).results, isEmpty);
  });

  test('a failed page keeps the query and retry succeeds', () async {
    create();
    api.searchResults.add(hit(sequence: 2, text: 'bike'));
    api.searchError = const NetworkFailure();

    await container.read(chatSearchProvider.notifier).search('bike');
    expect(container.read(chatSearchProvider).phase, ChatSearchPhase.error);
    expect(container.read(chatSearchProvider).query, 'bike');

    await container.read(chatSearchProvider.notifier).retry();

    final state = container.read(chatSearchProvider);
    expect(state.phase, ChatSearchPhase.ready);
    expect(state.results.single.message.text, 'bike');
  });

  test('loads the next page and keeps earlier results', () async {
    create();
    api
      ..searchPageLimit = 2
      ..searchResults.addAll([
        hit(sequence: 5, text: 'bike five'),
        hit(sequence: 4, text: 'bike four'),
        hit(sequence: 2, text: 'bike two'),
      ]);

    await container.read(chatSearchProvider.notifier).search('bike');
    expect(container.read(chatSearchProvider).hasMore, isTrue);

    await container.read(chatSearchProvider.notifier).more();

    final state = container.read(chatSearchProvider);
    expect(state.results.map((result) => result.message.sequence), [5, 4, 2]);
    expect(api.searchCalls.map((call) => call.cursor), [null, 'server-4']);
    expect(state.hasMore, isFalse);
  });

  test('a more-page failure keeps the loaded hits and can retry', () async {
    create();
    api
      ..searchPageLimit = 1
      ..searchResults.addAll([
        hit(sequence: 5, text: 'bike five'),
        hit(sequence: 4, text: 'bike four'),
      ]);
    await container.read(chatSearchProvider.notifier).search('bike');
    api.searchError = const NetworkFailure();

    await container.read(chatSearchProvider.notifier).more();
    expect(container.read(chatSearchProvider).results, hasLength(1));
    expect(container.read(chatSearchProvider).moreError, isA<NetworkFailure>());

    await container.read(chatSearchProvider.notifier).more();
    final state = container.read(chatSearchProvider);
    expect(state.moreError, isNull);
    expect(state.results, hasLength(2));
  });

  test('an older response cannot replace a newer query', () async {
    create();
    api.searchResults.add(hit(sequence: 1, text: 'bike'));
    final gate = Completer<void>();
    api.searchGate = gate;

    final older = container.read(chatSearchProvider.notifier).search('bike');
    await pumpEventQueue();
    api.searchGate = null;
    api.searchResults
      ..clear()
      ..add(hit(sequence: 2, text: 'desk'));
    final newer = container.read(chatSearchProvider.notifier).search('desk');
    // The newer request reaches the fake while the older one waits.
    gate.complete();
    await Future.wait([older, newer]);

    final state = container.read(chatSearchProvider);
    expect(state.query, 'desk');
    expect(state.results.single.message.text, 'desk');
  });
}
