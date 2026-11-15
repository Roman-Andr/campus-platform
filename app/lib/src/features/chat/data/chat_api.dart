import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';

part 'chat_api.g.dart';

/// The chat operations used by the application layer.
///
/// The generated client is the transport; this interface keeps the queue
/// testable without a network and isolates the two `200` replays of the
/// server (an existing dialog or an already stored message).
abstract interface class ChatApi {
  Future<PageChatOutput> listChats({String? cursor});

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
  Future<ChatOutput> createChat({
    required String recipientId,
    String? listingId,
  }) async {
    try {
      return await _chats.createChat(
        body: ChatInput(recipientId: recipientId, listingId: listingId),
      );
    } on DioException catch (error) {
      // The server answers 200 with the stored dialog when the pair and
      // link already exist; the generated contract describes only 201.
      return _replayed(error, ChatOutput.fromJson);
    }
  }

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
  }) async {
    try {
      return await _chats.sendMessage(
        chatId: chatId,
        body: MessageInput(clientId: clientId, text: text),
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
    } on DioException catch (error) {
      // A repeat of the client UUID answers 200 with the stored message
      // after a response was lost; a different text is 409.
      return _replayed(error, MessageOutput.fromJson);
    }
  }

  T _replayed<T>(DioException error, T Function(Map<String, Object?>) parse) {
    final response = error.response;
    if (response?.statusCode != 200) throw error;
    final data = response!.data;
    if (data is Map) return parse(Map<String, Object?>.from(data));
    if (data is String) {
      return parse(jsonDecode(data) as Map<String, Object?>);
    }
    throw error;
  }
}

@Riverpod(keepAlive: true)
ChatApi chatApi(Ref ref) => GeneratedChatApi(ref.watch(campusApiProvider));
