import 'dart:convert';

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

  Future<void> saveMessages(
    String owner,
    String chatId,
    Iterable<MessageOutput> messages,
  ) async {
    await db.transaction(() async {
      for (final message in messages) {
        await _upsertMessage(owner, chatId, message);
      }
    });
  }

  Future<void> _upsertMessage(
    String owner,
    String chatId,
    MessageOutput message,
  ) => db
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
          createdAt: message.createdAt,
        ),
      );

  MessageOutput _messageOf(ChatMessageRow row) => MessageOutput(
    id: row.serverId,
    chatId: row.chatId,
    senderId: row.senderId,
    clientId: row.clientId,
    sequence: row.sequence,
    text: row.body,
    createdAt: row.createdAt,
  );

  /// Adds a message to the durable outbox.
  ///
  /// The caller generates [clientId] and [idempotencyKey] once; both are
  /// stored with the row and reused by every later attempt.
  Future<OutgoingChatMessage> enqueue({
    required String owner,
    required String chatId,
    required String clientId,
    required String idempotencyKey,
    required String text,
    required DateTime createdAt,
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
            createdAt: createdAt,
          ),
        );
    return OutgoingChatMessage(
      chatId: chatId,
      clientId: clientId,
      idempotencyKey: idempotencyKey,
      text: text,
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
    createdAt: row.createdAt,
    attempts: row.attempts,
    state: row.status == 'failed'
        ? OutgoingChatState.failed
        : OutgoingChatState.pending,
    failure: row.failure == null
        ? null
        : OutgoingChatFailure.values.asNameMap()[row.failure!],
  );

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
  }) async {
    await db.transaction(() async {
      await (db.delete(db.chatOutbox)..where(
            (row) =>
                row.owner.equals(owner) &
                row.chatId.equals(message.chatId) &
                row.clientId.equals(message.clientId),
          ))
          .go();
      await _upsertMessage(owner, message.chatId, delivered);
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
    await db.delete(db.chatOutbox).go();
  });
}

final chatStoreProvider = Provider<ChatStore>(
  (ref) => ChatStore(ref.watch(appDatabaseProvider)),
);
