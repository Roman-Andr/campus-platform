import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';

part 'chat_api.g.dart';

/// The chat operations used by the application layer.
///
/// The generated client is the transport; this interface keeps the queue
/// testable without a network and carries the explicit message idempotency
/// key, which the queue persists with the row.
abstract interface class ChatApi {
  Future<PageChatOutput> listChats({String? cursor});

  Future<PageChatSearchResult> searchChats({
    required String query,
    String? cursor,
    int? size,
  });

  Future<ChatOutput> createChat({
    required String recipientId,
    String? listingId,
  });

  Future<ChatOutput> readChat(String chatId);

  Future<PageMessageOutput> listMessages(
    String chatId, {
    int? afterSequence,
    bool? ascending,
    String? cursor,
    int? size,
  });

  Future<MessageOutput> sendMessage(
    String chatId, {
    required String clientId,
    required String text,
    required String idempotencyKey,
  });
}

/// [ChatApi] over the generated OpenAPI client of the server.
class GeneratedChatApi implements ChatApi {
  GeneratedChatApi(this._api);

  final CampusApi _api;

  ChatsClient get _chats => _api.chats;

  @override
  Future<PageChatOutput> listChats({String? cursor}) =>
      _chats.listChats(orderBy: ListChatsOrderBy.updatedAt, cursor: cursor);

  @override
  Future<PageChatSearchResult> searchChats({
    required String query,
    String? cursor,
    int? size,
  }) => _chats.searchChats(q: query, cursor: cursor, size: size);

  @override
  Future<ChatOutput> createChat({
    required String recipientId,
    String? listingId,
  }) => _chats.createChat(
    body: ChatInput(recipientId: recipientId, listingId: listingId),
  );

  @override
  Future<ChatOutput> readChat(String chatId) => _chats.readChat(chatId: chatId);

  @override
  Future<PageMessageOutput> listMessages(
    String chatId, {
    int? afterSequence,
    bool? ascending,
    String? cursor,
    int? size,
  }) => _chats.listMessages(
    chatId: chatId,
    afterSequence: afterSequence,
    ascending: ascending,
    cursor: cursor,
    size: size,
  );

  @override
  Future<MessageOutput> sendMessage(
    String chatId, {
    required String clientId,
    required String text,
    required String idempotencyKey,
  }) => _chats.sendMessage(
    chatId: chatId,
    body: MessageInput(clientId: clientId, text: text),
    options: Options(headers: {'Idempotency-Key': idempotencyKey}),
  );
}

@Riverpod(keepAlive: true)
ChatApi chatApi(Ref ref) => GeneratedChatApi(ref.watch(campusApiProvider));
