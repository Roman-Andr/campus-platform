import 'package:campus/src/core/api/api_failure.dart';
import 'package:campus/src/core/api/generated/campus_api.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/chat/application/chat_config.dart';
import 'package:campus/src/features/chat/application/chat_history.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatSearchResult hit({
    String chatId = testChatId,
    required int sequence,
    required String text,
    String? snippet,
  }) => ChatSearchResult(
    chat: chatJson(id: chatId),
    message: messageJson(chatId: chatId, sequence: sequence, text: text),
    snippet: snippet ?? '…$text…',
  );

  Future<void> pumpChats(
    WidgetTester tester,
    FakeChatApi api, {
    AppLanguage language = AppLanguage.english,
    FakeHttpAdapter? adapter,
  }) async {
    await tester.pumpCampusApp(
      InMemorySettingsRepository(AppSettings(language: language)),
      adapter: adapter,
      overrides: [
        appDatabaseProvider.overrideWithValue(createTestDatabase()),
        chatApiProvider.overrideWithValue(api),
        chatRealtimeProvider.overrideWithValue(FakeChatRealtime()),
        chatConfigProvider.overrideWithValue(
          const ChatConfig(maxMessageLength: 4000, retryDelays: []),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('home-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-chats')));
    await tester.pumpAndSettle();
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('chats-search')));
    await tester.pumpAndSettle();
  }

  Future<void> query(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('chat-search-input')), text);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('searches, shows a snippet and opens the hit with context', (
    tester,
  ) async {
    final api = FakeChatApi(
      chats: [chatJson(id: testChatId)],
      messages: {
        testChatId: [
          for (var sequence = 1; sequence <= 30; sequence++)
            messageJson(
              chatId: testChatId,
              sequence: sequence,
              text: sequence == 15
                  ? 'needle in a haystack'
                  : 'message $sequence',
            ),
        ],
      },
      searchResults: [hit(sequence: 15, text: 'needle in a haystack')],
    );
    await pumpChats(tester, api);
    await openSearch(tester);

    expect(find.byKey(const Key('chat-search-prompt')), findsOneWidget);
    await query(tester, 'needle');

    expect(find.byKey(const Key('chat-search-results')), findsOneWidget);
    expect(find.text('Мария Петрова'), findsOneWidget);
    expect(find.textContaining('needle in a haystack'), findsOneWidget);
    expect(api.searchCalls.single.query, 'needle');

    await tester.tap(
      find.byKey(const ValueKey('chat-search-result-server-15')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-target-15')), findsOneWidget);
    expect(find.text('needle in a haystack'), findsOneWidget);
    final target = tester.getRect(find.byKey(const ValueKey('chat-target-15')));
    final list = tester.getRect(find.byKey(const Key('chat-messages')));
    expect(target.center.dy, inInclusiveRange(list.top, list.bottom));
    final jump = api.listMessageCalls.last;
    expect(jump.after, 0);
    expect(jump.ascending, isTrue);
  });

  testWidgets('loads more search hits on demand', (tester) async {
    final api = FakeChatApi(
      searchResults: [
        hit(sequence: 5, text: 'bike five'),
        hit(sequence: 4, text: 'bike four'),
      ],
    )..searchPageLimit = 1;
    await pumpChats(tester, api);
    await openSearch(tester);
    await query(tester, 'bike');

    expect(
      find.byKey(const ValueKey('chat-search-result-server-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-search-result-server-4')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('chat-search-more')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-search-result-server-4')),
      findsOneWidget,
    );
    expect(api.searchCalls.map((call) => call.cursor), [null, 'server-5']);
  });

  testWidgets('uses Russian interface texts', (tester) async {
    final api = FakeChatApi();
    await pumpChats(tester, api, language: AppLanguage.russian);
    await openSearch(tester);

    expect(find.text('Поиск по диалогам'), findsOneWidget);
    expect(
      find.text(
        'Введите слово или фразу, чтобы найти сообщения в своих диалогах.',
      ),
      findsOneWidget,
    );
    await query(tester, 'ничего');

    expect(find.byKey(const Key('chat-search-empty')), findsOneWidget);
    expect(find.text('По запросу «ничего» ничего не найдено.'), findsOneWidget);
  });

  testWidgets('shows the hit time in the city timezone', (tester) async {
    final api = FakeChatApi(
      searchResults: [hit(sequence: 2, text: 'bike ride')],
    );
    final adapter = FakeHttpAdapter(
      me: {
        ...userJson,
        ...filledProfileJson,
        'city_timezone': 'Pacific/Kiritimati',
      },
    );
    await pumpChats(tester, api, adapter: adapter);
    await openSearch(tester);
    await query(tester, 'bike');

    expect(find.textContaining('Kiritimati'), findsOneWidget);
  });

  testWidgets('an empty result is explicit and a query stays local', (
    tester,
  ) async {
    final api = FakeChatApi();
    await pumpChats(tester, api);
    await openSearch(tester);

    await query(tester, 'absent');

    expect(find.byKey(const Key('chat-search-empty')), findsOneWidget);
    expect(find.text('Nothing found for “absent”.'), findsOneWidget);
    expect(api.searchCalls, hasLength(1));
  });

  testWidgets('a network error offers a retry that repeats the query', (
    tester,
  ) async {
    final api = FakeChatApi()
      ..searchResults.add(hit(sequence: 2, text: 'bike ride'))
      ..searchError = const NetworkFailure();
    await pumpChats(tester, api);
    await openSearch(tester);

    await query(tester, 'bike');

    expect(find.byKey(const Key('chat-search-error')), findsOneWidget);
    expect(
      find.text('No network. Check the connection and search again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('chat-search-result-server-2')),
      findsOneWidget,
    );
    expect(api.searchCalls.map((call) => call.query), ['bike', 'bike']);
  });

  testWidgets('an invalid query is explained', (tester) async {
    final api = FakeChatApi()
      ..searchError = const ProblemFailure(
        Problem(
          type: 'urn:problem:campus:chat_search_invalid',
          title: 'Invalid search',
          status: 400,
          code: ProblemCode.chatSearchInvalid,
        ),
      );
    await pumpChats(tester, api);
    await openSearch(tester);
    await query(tester, 'too long');

    expect(find.byKey(const Key('chat-search-error')), findsOneWidget);
    expect(
      find.text('The search query is too long. Shorten it.'),
      findsOneWidget,
    );
  });

  testWidgets('lost access after a search shows the chat refusal', (
    tester,
  ) async {
    final api =
        FakeChatApi(
            chats: [chatJson(id: testChatId)],
            searchResults: [hit(sequence: 4, text: 'private needle')],
          )
          ..listError = const ProblemFailure(
            Problem(
              type: 'urn:problem:campus:chat_not_found',
              title: 'Not found',
              status: 404,
              code: ProblemCode.chatNotFound,
            ),
          );
    await pumpChats(tester, api);
    await openSearch(tester);
    await query(tester, 'needle');

    await tester.tap(find.byKey(const ValueKey('chat-search-result-server-4')));
    await tester.pumpAndSettle();

    expect(find.text('Chat unavailable'), findsOneWidget);
    expect(find.byKey(const Key('chat-messages')), findsNothing);
  });
}
