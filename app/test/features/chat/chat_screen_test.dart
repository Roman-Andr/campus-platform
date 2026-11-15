import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/chat/application/chat_config.dart';
import 'package:campus/src/features/chat/application/chat_history.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:campus/src/features/chat/data/chat_store.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import '../listings/fixtures.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const otherId = '01890a5d-ac96-774b-bcce-b302099a8059';

  Future<({FakeChatApi api, FakeChatRealtime realtime})> pumpChats(
    WidgetTester tester, {
    FakeChatApi? api,
    FakeChatRealtime? realtime,
    FakeHttpAdapter? server,
    Stream<bool>? network,
  }) async {
    final chatApi = api ?? FakeChatApi();
    final chatRealtime = realtime ?? FakeChatRealtime();
    await tester.pumpCampusApp(
      InMemorySettingsRepository(
        const AppSettings(language: AppLanguage.english),
      ),
      adapter: server,
      network: network,
      overrides: [
        appDatabaseProvider.overrideWithValue(createTestDatabase()),
        chatApiProvider.overrideWithValue(chatApi),
        chatRealtimeProvider.overrideWithValue(chatRealtime),
        chatConfigProvider.overrideWithValue(
          const ChatConfig(maxMessageLength: 4000, retryDelays: []),
        ),
      ],
    );
    return (api: chatApi, realtime: chatRealtime);
  }

  Future<void> openChats(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('home-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-chats')));
    await tester.pumpAndSettle();
  }

  Future<void> openChat(WidgetTester tester) async {
    await openChats(tester);
    await tester.tap(find.byKey(const ValueKey('chat-tile-$testChatId')));
    await tester.pumpAndSettle();
  }

  testWidgets('lists dialogs and shows history in server order', (
    tester,
  ) async {
    final server = FakeHttpAdapter();
    final api = FakeChatApi(
      chats: [
        chatJson(
          id: testChatId,
          lastMessage: messageJson(
            chatId: testChatId,
            sequence: 3,
            text: 'Latest',
          ),
        ),
      ],
      messages: {
        testChatId: [
          messageJson(chatId: testChatId, sequence: 3, text: 'Third'),
          messageJson(chatId: testChatId, sequence: 1, text: 'First'),
          messageJson(chatId: testChatId, sequence: 2, text: 'Second'),
        ],
      },
    );
    await pumpChats(tester, api: api, server: server);
    await openChats(tester);

    expect(find.byKey(const ValueKey('chat-tile-$testChatId')), findsOneWidget);
    expect(find.text('Мария Петрова'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-tile-$testChatId')));
    await tester.pumpAndSettle();
    final texts = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((text) => text.data)
        .toList();
    expect(texts, ['First', 'Second', 'Third']);
  });

  testWidgets('a long city time wraps inside the message bubble', (
    tester,
  ) async {
    final server = FakeHttpAdapter(
      me: {
        ...userJson,
        ...filledProfileJson,
        'city_timezone': 'Pacific/Kiritimati',
      },
    );
    final api = FakeChatApi(
      chats: [chatJson(id: testChatId)],
      messages: {
        testChatId: [
          messageJson(chatId: testChatId, sequence: 1, text: 'Long time'),
        ],
      },
    );
    await pumpChats(tester, api: api, server: server);
    await openChat(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Kiritimati'), findsOneWidget);
  });

  testWidgets('opens a dialog from a listing author', (tester) async {
    final server =
        FakeHttpAdapter(
          feed: pageJson([
            listingJson(author: otherId, authorName: 'Maria Petrova'),
          ]),
        )..route(
          (options) => options.path == '/api/v1/auth/token/refresh'
              ? jsonBody(200, tokensJson(1))
              : jsonBody(
                  200,
                  listingJson(author: otherId, authorName: 'Maria Petrova'),
                ),
        );
    final api = FakeChatApi(
      chats: [chatJson(id: testChatId)],
      messages: {testChatId: []},
    );
    await pumpChats(tester, api: api, server: server);

    await tester.tap(find.text('A desk'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('listing-chat')), findsOneWidget);
    await tester.tap(find.byKey(const Key('listing-chat')));
    await tester.pumpAndSettle();

    expect(api.createCalls, hasLength(1));
    expect(api.createCalls.single.recipientId, otherId);
    expect(api.createCalls.single.listingId, 'listing-1');
    expect(find.byKey(const Key('chat-input')), findsOneWidget);
  });

  testWidgets('a refused new dialog is explained and stays on the listing', (
    tester,
  ) async {
    final server =
        FakeHttpAdapter(
          feed: pageJson([
            listingJson(author: otherId, authorName: 'Maria Petrova'),
          ]),
        )..route(
          (options) => options.path == '/api/v1/auth/token/refresh'
              ? jsonBody(200, tokensJson(1))
              : jsonBody(
                  200,
                  listingJson(author: otherId, authorName: 'Maria Petrova'),
                ),
        );
    final api = FakeChatApi()
      ..createError = const ProblemFailure(
        Problem(
          type: 'urn:problem:campus:chat_forbidden',
          title: 'Forbidden',
          status: 403,
          code: ProblemCode.chatForbidden,
        ),
      );
    await pumpChats(tester, api: api, server: server);

    await tester.tap(find.text('A desk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('listing-chat')));
    await tester.pumpAndSettle();

    expect(
      find.text('Alumni can write only in existing chats.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('listing-chat-error')), findsOneWidget);
    expect(find.byKey(const Key('chat-input')), findsNothing);
  });

  testWidgets('a graduate writes in an existing dialog', (tester) async {
    final server = FakeHttpAdapter(
      me: {
        ...userJson,
        ...filledProfileJson,
        'account_type': 'former_employee',
      },
    );
    final api = FakeChatApi(
      chats: [chatJson(id: testChatId)],
      messages: {testChatId: []},
    );
    await pumpChats(tester, api: api, server: server);
    await openChat(tester);

    await tester.enterText(find.byKey(const Key('chat-input')), 'Hello there');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(api.createCalls, isEmpty);
    expect(api.sendCalls, hasLength(1));
    expect(find.text('Hello there'), findsOneWidget);
    expect(find.byKey(const Key('chat-messages')), findsOneWidget);
  });

  testWidgets('a queued message has its own status and never looks delivered', (
    tester,
  ) async {
    final api =
        FakeChatApi(
            chats: [chatJson(id: testChatId)],
            messages: {testChatId: []},
          )
          ..sendError = const ProblemFailure(
            Problem(
              type: 'urn:problem:campus:chat_message_conflict',
              title: 'Conflict',
              status: 409,
              code: ProblemCode.chatMessageConflict,
            ),
          );
    await pumpChats(tester, api: api);
    await openChat(tester);

    await tester.enterText(find.byKey(const Key('chat-input')), 'Failed text');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(find.text('Failed text'), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byKey(const Key('chat-messages')), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Failed text'), findsNothing);
    expect(find.text('Not sent'), findsNothing);
  });

  testWidgets('a pending message says so while the request is in flight', (
    tester,
  ) async {
    final api = FakeChatApi(
      chats: [chatJson(id: testChatId)],
      messages: {testChatId: []},
    );
    final gate = Completer<void>();
    api.sendGate = gate;
    await pumpChats(tester, api: api);
    await openChat(tester);

    await tester.enterText(find.byKey(const Key('chat-input')), 'Waiting');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();

    expect(find.text('Sending…'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Sending…'), findsNothing);
  });

  testWidgets('an unavailable dialog shows a localized error and retries', (
    tester,
  ) async {
    final api =
        FakeChatApi(
            chats: [chatJson(id: testChatId)],
            messages: {testChatId: []},
          )
          ..listError = const ProblemFailure(
            Problem(
              type: 'urn:problem:campus:chat_not_found',
              title: 'Chat not found',
              status: 404,
              code: ProblemCode.chatNotFound,
            ),
          );
    await pumpChats(tester, api: api);
    await openChat(tester);

    expect(find.text('Chat unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The history is loaded again after the retry.
    api.messages[testChatId]!.add(
      messageJson(chatId: testChatId, sequence: 1, text: 'Recovered'),
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets('an offline restart shows the saved queue without history', (
    tester,
  ) async {
    final database = createTestDatabase();
    final store = ChatStore(database);
    const owner = 'test-session-cache';
    await store.enqueue(
      owner: owner,
      chatId: testChatId,
      clientId: '01890a5d-ac96-774b-bcce-b302099a8061',
      idempotencyKey: '01890a5d-ac96-774b-bcce-b302099a8062',
      text: 'Saved offline',
      createdAt: DateTime.utc(2026, 11, 14, 12),
    );
    await store.upsertDialogs(owner, [chatJson(id: testChatId)]);
    final api = FakeChatApi(
      chats: [chatJson(id: testChatId)],
      messages: {testChatId: []},
    )..sendError = const NetworkFailure();
    await tester.pumpCampusApp(
      InMemorySettingsRepository(
        const AppSettings(language: AppLanguage.english),
      ),
      network: Stream.value(false),
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        chatApiProvider.overrideWithValue(api),
        chatRealtimeProvider.overrideWithValue(FakeChatRealtime()),
        chatConfigProvider.overrideWithValue(
          const ChatConfig(maxMessageLength: 4000, retryDelays: []),
        ),
      ],
    );

    await openChat(tester);

    expect(find.text('Saved offline'), findsOneWidget);
    expect(
      find.text(
        'No network. The message will be sent when the connection returns.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an older-page error stays at the top and can be retried', (
    tester,
  ) async {
    final api = FakeChatApi(
      chats: [chatJson(id: testChatId)],
      messages: {
        testChatId: [
          messageJson(chatId: testChatId, sequence: 1, text: 'Oldest'),
          messageJson(chatId: testChatId, sequence: 2, text: 'Newest'),
        ],
      },
    )..pageLimit = 1;
    await pumpChats(tester, api: api);
    await openChat(tester);
    expect(find.byKey(const Key('chat-load-older')), findsOneWidget);

    api.listError = const NetworkFailure();
    await tester.tap(find.byKey(const Key('chat-load-older')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-older-error')), findsOneWidget);
    expect(find.byKey(const Key('chat-form-error')), findsNothing);

    await tester.tap(find.byKey(const Key('chat-load-older')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-older-error')), findsNothing);
    expect(find.text('Oldest'), findsOneWidget);
  });

  testWidgets('loading an older page keeps the reader near the top', (
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
              text: 'Message $sequence',
            ),
        ],
      },
    )..pageLimit = 20;
    await pumpChats(tester, api: api);
    await openChat(tester);

    final list = find.byKey(const Key('chat-messages'));
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('chat-load-older')));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable.first).position;
    expect(position.pixels, lessThan(position.maxScrollExtent));

    await tester.tap(find.byKey(const Key('chat-load-older')));
    await tester.pumpAndSettle();

    final after = tester.state<ScrollableState>(scrollable.first).position;
    expect(after.pixels, greaterThan(0));
    expect(after.pixels, lessThan(after.maxScrollExtent));
    expect(find.text('Message 10'), findsOneWidget);
  });

  testWidgets('a failed realtime refresh offers a stale-state retry', (
    tester,
  ) async {
    final realtime = FakeChatRealtime();
    final api = FakeChatApi(
      chats: [chatJson(id: testChatId)],
      messages: {
        testChatId: [
          messageJson(chatId: testChatId, sequence: 1, text: 'First'),
        ],
      },
    );
    await pumpChats(tester, api: api, realtime: realtime);
    await openChat(tester);

    api.listError = const NetworkFailure();
    api.messages[testChatId]!.add(
      messageJson(chatId: testChatId, sequence: 2, text: 'From another device'),
    );
    realtime.emit();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-sync-error')), findsOneWidget);
    expect(find.text('From another device'), findsNothing);

    await tester.tap(find.byKey(const Key('chat-sync-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-sync-error')), findsNothing);
    expect(find.text('From another device'), findsOneWidget);
  });

  testWidgets('a failed next dialogs page can be retried', (tester) async {
    final ids = [
      for (var index = 0; index < 12; index++)
        '01890a5d-ac96-774b-bcce-b302099a${(0x8060 + index).toRadixString(16).padLeft(4, '0')}',
    ];
    final api = FakeChatApi(chats: [for (final id in ids) chatJson(id: id)])
      ..listChatsPageLimit = 10;
    await pumpChats(tester, api: api);
    await openChats(tester);

    api.listChatsError = const NetworkFailure();
    await tester.drag(
      find.byKey(const Key('chats-list')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    // The footer is lazily built; scroll it into the viewport.
    await tester.drag(
      find.byKey(const Key('chats-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chats-more-error')), findsOneWidget);
    expect(find.byKey(const Key('chats-more-loading')), findsNothing);

    await tester.tap(find.byKey(const Key('chats-more-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chats-more-error')), findsNothing);
    await tester.drag(
      find.byKey(const Key('chats-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('chat-tile-${ids.last}')), findsOneWidget);
  });

  testWidgets('the profile leads to the chats list', (tester) async {
    await pumpChats(tester);
    await tester.tap(find.byKey(const Key('home-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-chats')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-chats')));
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
  });
}
