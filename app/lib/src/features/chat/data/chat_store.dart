import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/database/app_database.dart';
import '../domain/chat.dart';

/// Local state of personal chats: cached dialogs, server messages and the
/// durable outgoing queue.
///
/// Every row belongs to an owner — the local identity of the signed-in
/// account. Queries never cross that boundary, and signing out clears the
/// tables, so data of a previous account is not shown to the next one.
class ChatStore {
  ChatStore(this.db);

  final AppDatabase db;

  /// Cached dialogs, the most recently active first.
  Future<List<ChatOutput>> loadDialogs(String owner) async {
    final rows =
        await (db.select(db.chatDialogs)
              ..where((row) => row.owner.equals(owner))
              ..orderBy([
                (row) => OrderingTerm.desc(row.updatedAt),
                (row) => OrderingTerm.asc(row.chatId),
              ]))
            .get();
    return [
      for (final row in rows)
        ChatOutput.fromJson(jsonDecode(row.payload) as Map<String, Object?>),
    ];
  }

  /// Replaces the first page of the dialog cache of [owner].
  Future<void> replaceDialogs(String owner, List<ChatOutput> chats) async {
    await db.transaction(() async {
      await (db.delete(
        db.chatDialogs,
      )..where((row) => row.owner.equals(owner))).go();
      for (final chat in chats) {
        await _upsertDialog(owner, chat);
      }
    });
  }

  /// Adds or updates dialogs, keeping the cached ones not in [chats].
  Future<void> upsertDialogs(String owner, Iterable<ChatOutput> chats) async {
    await db.transaction(() async {
      for (final chat in chats) {
        await _upsertDialog(owner, chat);
      }
    });
  }

  Future<void> _upsertDialog(String owner, ChatOutput chat) => db
      .into(db.chatDialogs)
      .insertOnConflictUpdate(
        ChatDialogsCompanion.insert(
          owner: owner,
          chatId: chat.id,
          updatedAt: chat.updatedAt,
          payload: jsonEncode(chat.toJson()),
        ),
      );

  /// Stored messages of a chat, ordered by the server sequence.
  Future<List<MessageOutput>> loadMessages(String owner, String chatId) async {
    final rows =
        await (db.select(db.chatMessages)
              ..where(
                (row) => row.owner.equals(owner) & row.chatId.equals(chatId),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();
    return [for (final row in rows) _messageOf(row)];
  }

  /// Stores server messages without letting a delayed response roll back
  /// a newer edit or resurrect a deleted message.
  ///
  /// A page requested before an edit can arrive after it with an older
  /// version; a page requested before a deletion can arrive after the
  /// tombstone was written. Both are dropped here, so every caller (history
  /// load, older page, forward sync and full reconciliation) is safe without
  /// its own ordering logic.
  Future<void> saveMessages(
    String owner,
    String chatId,
    Iterable<MessageOutput> messages, {
    int? quoteRevision,
  }) async {
    // A response is a snapshot taken when its request started. The caller
    // passes that revision for pages; `null` means an authoritative write
    // made now (an edit response or a delivery).
    final requestRevision = quoteRevision ?? _nextQuoteRevision();
    await db.transaction(() async {
      for (final message in messages) {
        if (await _isTombstoned(owner, chatId, message)) continue;
        final existing = await _existingMessage(owner, chatId, message);
        if (existing != null && message.version < existing.version) continue;
        await _upsertMessage(
          owner,
          chatId,
          message,
          existing: existing,
          quoteRevision: requestRevision,
          preferCachedTarget: quoteRevision == null,
        );
      }
    });
  }

  /// A monotonic revision for the start of a history request.
  ///
  /// Wall-clock microseconds keep it increasing across restarts, so a stored
  /// quote updated by a later run is never considered older than a new page.
  int beginQuoteRequest() => _nextQuoteRevision();

  int _quoteRevision = 0;

  int _nextQuoteRevision() {
    final now = clock.now().microsecondsSinceEpoch;
    _quoteRevision = now > _quoteRevision ? now : _quoteRevision + 1;
    return _quoteRevision;
  }

  Future<bool> _isTombstoned(
    String owner,
    String chatId,
    MessageOutput message,
  ) async {
    final row =
        await (db.select(db.chatMessageTombstones)..where(
              (row) =>
                  row.owner.equals(owner) &
                  row.chatId.equals(chatId) &
                  (row.messageId.equals(message.id) |
                      row.sequence.equals(message.sequence)),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<ChatMessageRow?> _existingMessage(
    String owner,
    String chatId,
    MessageOutput message,
  ) async {
    final rows =
        await (db.select(db.chatMessages)..where(
              (row) =>
                  row.owner.equals(owner) &
                  row.chatId.equals(chatId) &
                  (row.clientId.equals(message.clientId) |
                      row.serverId.equals(message.id)),
            ))
            .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _upsertMessage(
    String owner,
    String chatId,
    MessageOutput message, {
    ChatMessageRow? existing,
    required int quoteRevision,
    bool preferCachedTarget = false,
    ChatQuote? preferredQuote,
    bool hasPreferred = false,
  }) async {
    final quote = await _quoteForWrite(
      owner,
      chatId,
      message,
      existing: existing,
      requestRevision: quoteRevision,
      preferCachedTarget: preferCachedTarget,
      preferredQuote: preferredQuote,
      hasPreferred: hasPreferred,
    );
    await db
        .into(db.chatMessages)
        .insertOnConflictUpdate(
          ChatMessagesCompanion.insert(
            owner: owner,
            chatId: chatId,
            clientId: message.clientId,
            serverId: message.id,
            sequence: message.sequence,
            senderId: message.senderId,
            body: message.text,
            version: Value(message.version),
            replyToId: Value(message.replyToId),
            replyToPayload: Value(
              quote.quote == null ? null : jsonEncode(quote.quote!.toJson()),
            ),
            quoteRevision: Value(quote.revision),
            photoIds: Value(
              message.photoIds == null ? null : jsonEncode(message.photoIds),
            ),
            createdAt: message.createdAt,
          ),
        );
  }

  /// The visible quote that survives a delayed reply response.
  ///
  /// A target edit or deletion does not bump the reply's own server version,
  /// so a page that started before that change could otherwise put the old
  /// text back. The cached target row (edited) or its tombstone (deleted) is
  /// authoritative; when the target is outside the local cache, the stored
  /// quote revision wins over a response that started earlier. A delivery
  /// may additionally supply the current outbox snapshot.
  Future<({ChatQuote? quote, int revision})> _quoteForWrite(
    String owner,
    String chatId,
    MessageOutput message, {
    ChatMessageRow? existing,
    required int requestRevision,
    ChatQuote? preferredQuote,
    bool hasPreferred = false,
    bool preferCachedTarget = false,
  }) async {
    final targetId = message.replyToId;
    if (targetId == null) return (quote: null, revision: requestRevision);
    if (await _isTombstonedId(owner, chatId, targetId)) {
      return (quote: null, revision: _nextQuoteRevision());
    }
    final target =
        await (db.select(db.chatMessages)..where(
              (row) =>
                  row.owner.equals(owner) &
                  row.chatId.equals(chatId) &
                  row.serverId.equals(targetId),
            ))
            .getSingleOrNull();
    if (existing != null &&
        existing.quoteRevision > requestRevision &&
        (target == null || existing.quoteRevision >= target.quoteRevision)) {
      // A local edit/delete of the target already refreshed this reply after
      // the response was taken, and the cached target is not newer.
      return (
        quote: _quoteOf(existing.replyToPayload),
        revision: existing.quoteRevision,
      );
    }
    if (target != null &&
        (preferCachedTarget || target.quoteRevision >= requestRevision)) {
      return (
        quote: chatQuoteOf(_messageOf(target)),
        revision: _nextQuoteRevision(),
      );
    }
    if (hasPreferred) {
      return (quote: preferredQuote, revision: _nextQuoteRevision());
    }
    return (quote: quoteOf(message), revision: requestRevision);
  }

  Future<bool> _isTombstonedId(
    String owner,
    String chatId,
    String messageId,
  ) async {
    final row =
        await (db.select(db.chatMessageTombstones)..where(
              (row) =>
                  row.owner.equals(owner) &
                  row.chatId.equals(chatId) &
                  row.messageId.equals(messageId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  MessageOutput _messageOf(ChatMessageRow row) => MessageOutput(
    id: row.serverId,
    chatId: row.chatId,
    senderId: row.senderId,
    clientId: row.clientId,
    sequence: row.sequence,
    text: row.body,
    replyToId: row.replyToId,
    replyTo: _replyOf(row.replyToPayload),
    version: row.version,
    photoIds: _photoIdsOf(row.photoIds),
    createdAt: row.createdAt,
  );

  MessageOutputReplyTo? _replyOf(String? payload) {
    if (payload == null) return null;
    try {
      return MessageOutputReplyTo.fromJson(jsonDecode(payload));
    } on Object {
      // A row written by an older build or a damaged cache degrades to a
      // quote placeholder instead of failing the whole history.
      return null;
    }
  }

  List<String>? _photoIdsOf(String? payload) {
    if (payload == null) return null;
    try {
      return [
        for (final id in jsonDecode(payload) as List<Object?>) id as String,
      ];
    } on Object {
      return null;
    }
  }

  /// Removes stored messages and writes a tombstone for each of them.
  ///
  /// A deletion does not arrive with a new sequence, so the last known row
  /// is matched either way; the tombstone keeps an older page response from
  /// writing the hidden text back.
  Future<void> removeMessages(
    String owner,
    String chatId, {
    Iterable<String> serverIds = const [],
    Iterable<int> sequences = const [],
  }) async {
    final ids = serverIds.toSet();
    final numbers = sequences.toSet();
    if (ids.isEmpty && numbers.isEmpty) return;
    final rows =
        await (db.select(db.chatMessages)..where((row) {
              final scoped =
                  row.owner.equals(owner) & row.chatId.equals(chatId);
              final byId = ids.isEmpty
                  ? const Constant(false)
                  : row.serverId.isIn(ids);
              final bySequence = numbers.isEmpty
                  ? const Constant(false)
                  : row.sequence.isIn(numbers);
              return scoped & (byId | bySequence);
            }))
            .get();
    final now = clock.now().toUtc();
    await db.transaction(() async {
      for (final row in rows) {
        await _tombstone(
          owner,
          chatId,
          row.serverId,
          row.sequence,
          row.version,
          now,
        );
      }
      await (db.delete(db.chatMessages)..where((row) {
            final scoped = row.owner.equals(owner) & row.chatId.equals(chatId);
            final byId = ids.isEmpty
                ? const Constant(false)
                : row.serverId.isIn(ids);
            final bySequence = numbers.isEmpty
                ? const Constant(false)
                : row.sequence.isIn(numbers);
            return scoped & (byId | bySequence);
          }))
          .go();
    });
  }

  /// Marks one message deleted even when it is not stored locally.
  ///
  /// A realtime deletion carries only the id and the sequence; the
  /// tombstone must exist before any in-flight page can write the old text.
  Future<void> markDeleted(
    String owner,
    String chatId, {
    required String messageId,
    required int sequence,
    int version = 0,
  }) async {
    await db.transaction(() async {
      await _tombstone(
        owner,
        chatId,
        messageId,
        sequence,
        version,
        clock.now().toUtc(),
      );
      await (db.delete(db.chatMessages)..where(
            (row) =>
                row.owner.equals(owner) &
                row.chatId.equals(chatId) &
                (row.serverId.equals(messageId) |
                    row.sequence.equals(sequence)),
          ))
          .go();
    });
  }

  Future<void> _tombstone(
    String owner,
    String chatId,
    String messageId,
    int sequence,
    int version,
    DateTime deletedAt,
  ) async {
    final existing =
        await (db.select(db.chatMessageTombstones)..where(
              (row) =>
                  row.owner.equals(owner) &
                  row.chatId.equals(chatId) &
                  row.messageId.equals(messageId),
            ))
            .getSingleOrNull();
    await db
        .into(db.chatMessageTombstones)
        .insertOnConflictUpdate(
          ChatMessageTombstonesCompanion.insert(
            owner: owner,
            chatId: chatId,
            messageId: messageId,
            sequence: sequence,
            version: Value(
              existing == null || existing.version < version
                  ? version
                  : existing.version,
            ),
            deletedAt: deletedAt,
          ),
        );
  }

  /// Replaces the displayed quote of pending outbox rows without changing
  /// the immutable `reply_to_id` they send on every retry.
  Future<void> updateOutgoingQuote(
    String owner,
    String quotedId, {
    ChatQuote? quote,
  }) =>
      (db.update(db.chatOutbox)..where(
            (row) => row.owner.equals(owner) & row.replyToId.equals(quotedId),
          ))
          .write(
            ChatOutboxCompanion(
              replyToPayload: Value(
                quote == null ? null : jsonEncode(quote.toJson()),
              ),
              quoteRevision: Value(_nextQuoteRevision()),
            ),
          );

  /// Replaces the stored quote snapshot of every message that quotes
  /// [quotedId]. `null` marks the quoted message as deleted.
  Future<void> updateQuote(
    String owner,
    String chatId,
    String quotedId, {
    ChatQuote? quote,
  }) {
    final revision = _nextQuoteRevision();
    return (db.update(db.chatMessages)..where(
          (row) =>
              row.owner.equals(owner) &
              row.chatId.equals(chatId) &
              row.replyToId.equals(quotedId),
        ))
        .write(
          ChatMessagesCompanion(
            replyToPayload: Value(
              quote == null ? null : jsonEncode(quote.toJson()),
            ),
            quoteRevision: Value(revision),
          ),
        );
  }

  /// Adds a message to the durable outbox.
  ///
  /// The caller generates [clientId] and [idempotencyKey] once; both are
  /// stored with the row and reused by every later attempt. The quote and
  /// the ready photo ids are stored too: a retry after a restart must send
  /// the same content instead of dropping or duplicating an attachment.
  Future<OutgoingChatMessage> enqueue({
    required String owner,
    required String chatId,
    required String clientId,
    required String idempotencyKey,
    required String text,
    required DateTime createdAt,
    ChatQuote? replyTo,
    List<String> photoIds = const [],
  }) async {
    await db
        .into(db.chatOutbox)
        .insert(
          ChatOutboxCompanion.insert(
            owner: owner,
            chatId: chatId,
            clientId: clientId,
            idempotencyKey: idempotencyKey,
            body: text,
            replyToId: Value(replyTo?.messageId),
            replyToPayload: Value(
              replyTo == null ? null : jsonEncode(replyTo.toJson()),
            ),
            photoIds: Value(photoIds.isEmpty ? null : jsonEncode(photoIds)),
            createdAt: createdAt,
          ),
        );
    return OutgoingChatMessage(
      chatId: chatId,
      clientId: clientId,
      idempotencyKey: idempotencyKey,
      text: text,
      replyToId: replyTo?.messageId,
      replyTo: replyTo,
      photoIds: photoIds,
      createdAt: createdAt,
      attempts: 0,
      state: OutgoingChatState.pending,
    );
  }

  /// Outgoing rows of [owner], oldest first; optionally only one chat.
  Future<List<OutgoingChatMessage>> loadOutbox(
    String owner, {
    String? chatId,
  }) async {
    final query = db.select(db.chatOutbox)
      ..where((row) => row.owner.equals(owner));
    if (chatId != null) query.where((row) => row.chatId.equals(chatId));
    final rows =
        await (query..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.clientId),
            ]))
            .get();
    return [for (final row in rows) _outgoingOf(row)];
  }

  OutgoingChatMessage _outgoingOf(ChatOutboxRow row) => OutgoingChatMessage(
    chatId: row.chatId,
    clientId: row.clientId,
    idempotencyKey: row.idempotencyKey,
    text: row.body,
    replyToId: row.replyToId,
    replyTo: _quoteOf(row.replyToPayload),
    photoIds: _photoIdsOf(row.photoIds) ?? const [],
    createdAt: row.createdAt,
    attempts: row.attempts,
    state: row.status == 'failed'
        ? OutgoingChatState.failed
        : OutgoingChatState.pending,
    failure: row.failure == null
        ? null
        : OutgoingChatFailure.values.asNameMap()[row.failure!],
  );

  ChatQuote? _quoteOf(String? payload) {
    if (payload == null) return null;
    try {
      return ChatQuote.fromJson(jsonDecode(payload) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  /// Records an attempt that can be retried later; the row stays pending.
  Future<void> markAttempt({
    required String owner,
    required OutgoingChatMessage message,
    required OutgoingChatFailure failure,
  }) => _updateOutbox(
    owner,
    message,
    status: 'pending',
    failure: failure,
    attempts: message.attempts + 1,
  );

  /// Marks a refusal that a retry with the same content cannot fix.
  Future<void> fail({
    required String owner,
    required OutgoingChatMessage message,
    required OutgoingChatFailure failure,
  }) => _updateOutbox(
    owner,
    message,
    status: 'failed',
    failure: failure,
    attempts: message.attempts + 1,
  );

  /// Removes a permanently refused row after the user discards it.
  Future<void> discard({
    required String owner,
    required OutgoingChatMessage message,
  }) =>
      (db.delete(db.chatOutbox)..where(
            (row) =>
                row.owner.equals(owner) &
                row.chatId.equals(message.chatId) &
                row.clientId.equals(message.clientId),
          ))
          .go();

  /// Puts a failed row back into the queue after the user asks to retry.
  Future<void> retry({
    required String owner,
    required OutgoingChatMessage message,
  }) => _updateOutbox(
    owner,
    message,
    status: 'pending',
    failure: null,
    attempts: 0,
  );

  Future<void> _updateOutbox(
    String owner,
    OutgoingChatMessage message, {
    required String status,
    required OutgoingChatFailure? failure,
    required int attempts,
  }) =>
      (db.update(db.chatOutbox)..where(
            (row) =>
                row.owner.equals(owner) &
                row.chatId.equals(message.chatId) &
                row.clientId.equals(message.clientId),
          ))
          .write(
            ChatOutboxCompanion(
              status: Value(status),
              failure: Value(failure?.name),
              attempts: Value(attempts),
            ),
          );

  /// Removes the delivered row and caches the server message atomically.
  Future<void> complete({
    required String owner,
    required OutgoingChatMessage message,
    required MessageOutput delivered,
    int requestQuoteRevision = 0,
  }) async {
    await db.transaction(() async {
      final outbox =
          await (db.select(db.chatOutbox)..where(
                (row) =>
                    row.owner.equals(owner) &
                    row.chatId.equals(message.chatId) &
                    row.clientId.equals(message.clientId),
              ))
              .getSingleOrNull();
      // The displayed quote of the outbox may have been refreshed after the
      // send request started. A delayed delivery must use that snapshot,
      // not the older one the request carried.
      final hasOutboxQuote =
          outbox != null &&
          outbox.replyToId != null &&
          outbox.replyToId == delivered.replyToId &&
          outbox.quoteRevision > requestQuoteRevision;
      await (db.delete(db.chatOutbox)..where(
            (row) =>
                row.owner.equals(owner) &
                row.chatId.equals(message.chatId) &
                row.clientId.equals(message.clientId),
          ))
          .go();
      if (!await _isTombstoned(owner, message.chatId, delivered)) {
        final existing = await _existingMessage(
          owner,
          message.chatId,
          delivered,
        );
        if (existing == null || delivered.version >= existing.version) {
          await _upsertMessage(
            owner,
            message.chatId,
            delivered,
            existing: existing,
            quoteRevision: requestQuoteRevision,
            preferredQuote: hasOutboxQuote
                ? _quoteOf(outbox.replyToPayload)
                : null,
            hasPreferred: hasOutboxQuote,
          );
        }
      }
      final dialog =
          await (db.select(db.chatDialogs)..where(
                (row) =>
                    row.owner.equals(owner) & row.chatId.equals(message.chatId),
              ))
              .getSingleOrNull();
      if (dialog != null) {
        final cached = ChatOutput.fromJson(
          jsonDecode(dialog.payload) as Map<String, Object?>,
        );
        await _upsertDialog(
          owner,
          ChatOutput(
            id: cached.id,
            kind: cached.kind,
            listingId: cached.listingId,
            interactionId: cached.interactionId,
            createdAt: cached.createdAt,
            updatedAt: delivered.createdAt,
            participants: cached.participants,
            lastMessage: delivered,
            additionalProperties: cached.additionalProperties,
          ),
        );
      }
    });
  }

  Future<void> clearAll() => db.transaction(() async {
    await db.delete(db.chatDialogs).go();
    await db.delete(db.chatMessages).go();
    await db.delete(db.chatMessageTombstones).go();
    await db.delete(db.chatOutbox).go();
  });
}

final chatStoreProvider = Provider<ChatStore>(
  (ref) => ChatStore(ref.watch(appDatabaseProvider)),
);
