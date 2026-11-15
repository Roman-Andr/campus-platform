import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/interceptors.dart';

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
    String? replyToId,
    List<String> photoIds = const [],
  });

  /// Edits the author's own message; the previous text stays hidden.
  ///
  /// The caller keeps [idempotencyKey] for every repeat of the same edit,
  /// so a lost response cannot apply it twice.
  Future<MessageOutput> editMessage(
    String chatId,
    String messageId, {
    required String text,
    required String idempotencyKey,
  });

  /// Deletes the author's own message; repeating the request is a no-op.
  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required String idempotencyKey,
  });

  /// A protected upload form for one chat photo.
  ///
  /// The caller keeps [idempotencyKey] for every retry of the same logical
  /// form request, so a lost response returns the same file and form instead
  /// of creating another upload.
  Future<ChatUploadOutput> requestChatPhoto(
    String chatId, {
    required String idempotencyKey,
    CancelToken? cancel,
  });

  /// Starts processing an uploaded chat photo and returns its current state.
  ///
  /// The key belongs to the first completion of this file. Status checks use
  /// [getPhotoUpload] instead: a repeated POST returns the cached response,
  /// not the current processing state.
  Future<ChatFileOutput> completeChatPhoto(
    String chatId,
    String fileId, {
    required String idempotencyKey,
    CancelToken? cancel,
  });

  /// Current server state of an owned uploaded photo, for polling.
  Future<ChatFileOutput> getPhotoUpload(String fileId, {CancelToken? cancel});

  /// Short-lived signed links of the ready photos of a visible message.
  Future<ChatPhotosOutput> listMessagePhotos(
    String chatId,
    String messageId, {
    CancelToken? cancel,
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
    String? replyToId,
    List<String> photoIds = const [],
  }) => _chats.sendMessage(
    chatId: chatId,
    body: MessageInput(
      clientId: clientId,
      text: text,
      replyToId: replyToId,
      photoIds: photoIds.isEmpty ? null : photoIds,
    ),
    options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
  );

  @override
  Future<MessageOutput> editMessage(
    String chatId,
    String messageId, {
    required String text,
    required String idempotencyKey,
  }) => _chats.editMessageView(
    chatId: chatId,
    messageId: messageId,
    body: MessageEditInput(text: text),
    options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
  );

  @override
  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required String idempotencyKey,
  }) => _chats.deleteMessageView(
    chatId: chatId,
    messageId: messageId,
    options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
  );

  @override
  Future<ChatUploadOutput> requestChatPhoto(
    String chatId, {
    required String idempotencyKey,
    CancelToken? cancel,
  }) => _chats.requestChatPhoto(
    chatId: chatId,
    options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
    cancelToken: cancel,
  );

  @override
  Future<ChatFileOutput> completeChatPhoto(
    String chatId,
    String fileId, {
    required String idempotencyKey,
    CancelToken? cancel,
  }) => _chats.completeChatPhoto(
    chatId: chatId,
    fileId: fileId,
    options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
    cancelToken: cancel,
  );

  @override
  Future<ChatFileOutput> getPhotoUpload(
    String fileId, {
    CancelToken? cancel,
  }) async {
    final file = await _api.photos.getPhotoUpload(
      fileId: fileId,
      cancelToken: cancel,
    );
    return ChatFileOutput(
      id: file.id,
      purpose: file.purpose,
      status: file.status,
      size: file.size,
      rejectionReason: file.rejectionReason,
      expiresAt: file.expiresAt,
      additionalProperties: file.additionalProperties,
    );
  }

  @override
  Future<ChatPhotosOutput> listMessagePhotos(
    String chatId,
    String messageId, {
    CancelToken? cancel,
  }) => _chats.listMessagePhotos(
    chatId: chatId,
    messageId: messageId,
    cancelToken: cancel,
  );
}

@Riverpod(keepAlive: true)
ChatApi chatApi(Ref ref) => GeneratedChatApi(ref.watch(campusApiProvider));
