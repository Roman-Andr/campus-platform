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

  Future<void> create({int count = 60}) async {
    api = FakeChatApi(
      messages: {
        chatId: [
          for (var sequence = 1; sequence <= count; sequence++)
            messageJson(
              chatId: chatId,
              sequence: sequence,
              text: 'message $sequence',
            ),
        ],
      },
    )..pageLimit = 20;
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

  test('opens a hit with surrounding context and can load earlier', () async {
    await create();
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    final history = container.read(provider.notifier);
    await container.read(provider.future);

    await history.openAt(25);

    var state = container.read(provider).value!;
    expect(state.messages.map((message) => message.sequence), [
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      41,
      42,
      43,
      44,
      45,
      46,
      47,
      48,
      49,
      50,
      51,
      52,
      53,
      54,
      55,
      56,
      57,
      58,
      59,
      60,
    ]);
    expect(state.olderBefore, 6);
    expect(state.nextPage, isNull);
    final jumpCall = api.listMessageCalls.last;
    expect(jumpCall.after, 5);
    expect(jumpCall.ascending, isTrue);

    await history.loadOlder();

    state = container.read(provider).value!;
    expect(state.messages.first.sequence, 1);
    expect(
      state.messages.map((message) => message.sequence),
      containsAll([1, 5, 25]),
    );
    expect(state.olderBefore, isNull);
    expect(state.nextPage, isNull);
  });

  test('rejects a hit that is no longer in the visible history', () async {
    await create(count: 3);
    final provider = chatHistoryProvider(chatId);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    final history = container.read(provider.notifier);
    await container.read(provider.future);

    await expectLater(
      history.openAt(500),
      throwsA(isA<ChatMessageContextUnavailable>()),
    );
  });
}
