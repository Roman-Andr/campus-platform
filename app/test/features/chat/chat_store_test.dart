import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/chat/data/chat_store.dart';
import 'package:campus/src/features/chat/domain/chat.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';
import 'chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chatId = testChatId;
  const owner = 'account-a';

  late ChatStore store;
  late AppDatabase database;

  setUp(() {
    database = createTestDatabase();
    store = ChatStore(database);
  });

  tearDown(() => database.close());

  test('an older version never replaces a newer stored version', () async {
    await store.saveMessages(owner, chatId, [
      messageJson(chatId: chatId, sequence: 1, text: 'newer', version: 2),
    ]);
    await store.saveMessages(owner, chatId, [
      messageJson(chatId: chatId, sequence: 1, text: 'older'),
    ]);

    final stored = await store.loadMessages(owner, chatId);
    expect(stored.single.text, 'newer');
    expect(stored.single.version, 2);
  });

  test(
    'a tombstone blocks a delayed page from resurrecting a message',
    () async {
      final message = messageJson(chatId: chatId, sequence: 1, text: 'hidden');
      await store.saveMessages(owner, chatId, [message]);
      await store.markDeleted(
        owner,
        chatId,
        messageId: message.id,
        sequence: message.sequence,
        version: 2,
      );

      await store.saveMessages(owner, chatId, [message]);

      expect(await store.loadMessages(owner, chatId), isEmpty);
    },
  );

  test('removeMessages tombstones every row it drops', () async {
    final message = messageJson(chatId: chatId, sequence: 7, text: 'gone');
    await store.saveMessages(owner, chatId, [message]);

    await store.removeMessages(owner, chatId, serverIds: [message.id]);
    await store.saveMessages(owner, chatId, [message]);

    expect(await store.loadMessages(owner, chatId), isEmpty);
  });

  test('clearing the outbox quote keeps the immutable wire id', () async {
    final quote = ChatQuote(
      messageId: 'server-1',
      senderId: '01890a5d-ac96-774b-bcce-b302099a8059',
      text: 'quoted',
      createdAt: DateTime.utc(2026, 11, 14, 12),
    );
    await store.enqueue(
      owner: owner,
      chatId: chatId,
      clientId: '01890a5d-ac96-774b-bcce-b302099a8080',
      idempotencyKey: '01890a5d-ac96-774b-bcce-b302099a8081',
      text: 'hello',
      createdAt: DateTime.utc(2026, 11, 14, 12),
      replyTo: quote,
    );
    await store.updateOutgoingQuote(owner, quote.messageId);

    final stored = (await store.loadOutbox(owner)).single;
    expect(stored.replyToId, 'server-1');
    expect(stored.replyTo, isNull);
  });

  test(
    'a delayed reply does not restore an edited quote of a cached target',
    () async {
      final target = messageJson(chatId: chatId, sequence: 1, text: 'original');
      final reply = messageJson(
        chatId: chatId,
        sequence: 2,
        text: 'reply',
        replyToId: target.id,
        replyTo: quoteJson(target),
      );
      await store.saveMessages(owner, chatId, [target, reply]);
      final delayedRevision = store.beginQuoteRequest();

      final editedTarget = messageJson(
        chatId: chatId,
        sequence: 1,
        text: 'edited',
        version: 2,
      );
      await store.saveMessages(owner, chatId, [editedTarget]);
      await store.updateQuote(
        owner,
        chatId,
        target.id,
        quote: ChatQuote(
          messageId: target.id,
          senderId: target.senderId,
          text: 'edited',
          createdAt: target.createdAt,
        ),
      );
      // The page started before the edit and still carries the old snapshot.
      await store.saveMessages(owner, chatId, [
        reply,
      ], quoteRevision: delayedRevision);

      final stored = (await store.loadMessages(
        owner,
        chatId,
      )).where((message) => message.id == reply.id).single;
      expect(quoteOf(stored)?.text, 'edited');
    },
  );

  test(
    'a delayed reply does not restore a quote of a deleted target',
    () async {
      final target = messageJson(
        chatId: chatId,
        sequence: 1,
        text: 'will be deleted',
      );
      final reply = messageJson(
        chatId: chatId,
        sequence: 2,
        text: 'reply',
        replyToId: target.id,
        replyTo: quoteJson(target),
      );
      await store.saveMessages(owner, chatId, [target, reply]);
      final delayedRevision = store.beginQuoteRequest();

      await store.markDeleted(
        owner,
        chatId,
        messageId: target.id,
        sequence: target.sequence,
        version: 2,
      );
      await store.saveMessages(owner, chatId, [
        reply,
      ], quoteRevision: delayedRevision);

      final stored = (await store.loadMessages(
        owner,
        chatId,
      )).where((message) => message.id == reply.id).single;
      expect(stored.replyTo, isNull);
    },
  );

  test(
    'a delayed reply keeps a newer quote when the target is not cached',
    () async {
      final target = messageJson(chatId: chatId, sequence: 1, text: 'original');
      final reply = messageJson(
        chatId: chatId,
        sequence: 2,
        text: 'reply',
        replyToId: target.id,
        replyTo: quoteJson(target),
      );
      await store.saveMessages(owner, chatId, [reply]);
      final delayedRevision = store.beginQuoteRequest();
      await store.updateQuote(
        owner,
        chatId,
        target.id,
        quote: ChatQuote(
          messageId: target.id,
          senderId: target.senderId,
          text: 'edited elsewhere',
          createdAt: target.createdAt,
        ),
      );

      await store.saveMessages(owner, chatId, [
        reply,
      ], quoteRevision: delayedRevision);

      final stored = (await store.loadMessages(owner, chatId)).single;
      expect(quoteOf(stored)?.text, 'edited elsewhere');
    },
  );

  test('a delivery does not restore a stale quote after an edit', () async {
    final target = messageJson(chatId: chatId, sequence: 1, text: 'original');
    final oldQuote = ChatQuote(
      messageId: target.id,
      senderId: target.senderId,
      text: 'original',
      createdAt: target.createdAt,
    );
    await store.saveMessages(owner, chatId, [target]);
    final queued = await store.enqueue(
      owner: owner,
      chatId: chatId,
      clientId: '01890a5d-ac96-774b-bcce-b302099a8092',
      idempotencyKey: '01890a5d-ac96-774b-bcce-b302099a8093',
      text: 'reply',
      createdAt: DateTime.utc(2026, 11, 14, 13),
      replyTo: oldQuote,
    );
    await store.saveMessages(owner, chatId, [
      messageJson(chatId: chatId, sequence: 1, text: 'edited', version: 2),
    ]);
    await store.updateQuote(
      owner,
      chatId,
      target.id,
      quote: ChatQuote(
        messageId: target.id,
        senderId: target.senderId,
        text: 'edited',
        createdAt: target.createdAt,
      ),
    );

    await store.complete(
      owner: owner,
      message: queued,
      delivered: messageJson(
        chatId: chatId,
        sequence: 2,
        text: 'reply',
        replyToId: target.id,
        replyTo: quoteJson(target),
      ),
    );

    final stored = (await store.loadMessages(
      owner,
      chatId,
    )).where((message) => message.sequence == 2).single;
    expect(quoteOf(stored)?.text, 'edited');
  });

  test(
    'a delayed delivery keeps a quote updated after the request started',
    () async {
      final target = messageJson(chatId: chatId, sequence: 1, text: 'original');
      final oldQuote = ChatQuote(
        messageId: target.id,
        senderId: target.senderId,
        text: 'original',
        createdAt: target.createdAt,
      );
      final newQuote = ChatQuote(
        messageId: target.id,
        senderId: target.senderId,
        text: 'edited while sending',
        createdAt: target.createdAt,
      );
      final queued = await store.enqueue(
        owner: owner,
        chatId: chatId,
        clientId: '01890a5d-ac96-774b-bcce-b302099a8094',
        idempotencyKey: '01890a5d-ac96-774b-bcce-b302099a8095',
        text: 'reply',
        createdAt: DateTime.utc(2026, 11, 14, 13),
        replyTo: oldQuote,
      );
      // The edit event updates the pending quote after send has started; the
      // target itself is outside the loaded window.
      await store.updateOutgoingQuote(owner, target.id, quote: newQuote);

      await store.complete(
        owner: owner,
        message: queued,
        delivered: messageJson(
          chatId: chatId,
          sequence: 2,
          text: 'reply',
          replyToId: target.id,
          replyTo: quoteJson(target),
        ),
      );

      final stored = (await store.loadMessages(owner, chatId)).single;
      expect(quoteOf(stored)?.text, 'edited while sending');
    },
  );
}
