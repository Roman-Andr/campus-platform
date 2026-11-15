import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:campus/src/core/api/generated/campus_api.dart';
import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:campus/src/core/realtime/realtime_channel.dart';
import 'package:campus/src/core/realtime/realtime_models.dart';
import 'package:campus/src/features/chat/application/chat_history.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';
import 'package:campus/src/features/chat/data/chat_photo_uploader.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

/// A canonical UUID the realtime channel accepts for a test dialog.
const testChatId = '01890a5d-ac96-774b-bcce-b302099a8060';

MessageOutput messageJson({
  required String chatId,
  required int sequence,
  String? clientId,
  String? id,
  String senderId = '01890a5d-ac96-774b-bcce-b302099a8058',
  String text = 'Hello',
  DateTime? createdAt,
  int version = 1,
  String? replyToId,
  MessageOutputReplyTo? replyTo,
  List<String>? photoIds,
}) => MessageOutput(
  id: id ?? 'server-$sequence',
  chatId: chatId,
  senderId: senderId,
  clientId: clientId ?? '01890a5d-ac96-774b-bcce-b302099a80$sequence',
  sequence: sequence,
  text: text,
  version: version,
  replyToId: replyToId,
  replyTo: replyTo,
  photoIds: photoIds,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 14, 12, sequence),
);

/// The quote payload the history API returns for a replied message.
QuoteOutput quoteJson(MessageOutput message) => QuoteOutput(
  id: message.id,
  senderId: message.senderId,
  text: message.text,
  createdAt: message.createdAt,
);

ParticipantOutput participantJson({
  required String id,
  String firstName = 'Иван',
  String lastName = 'Иванов',
  String accountType = 'student',
}) => ParticipantOutput(
  id: id,
  firstName: firstName,
  lastName: lastName,
  accountType: accountType,
);

ChatOutput chatJson({
  String id = 'chat-1',
  String kind = 'personal',
  List<ParticipantOutput>? participants,
  MessageOutput? lastMessage,
  String? listingId = 'listing-1',
  DateTime? updatedAt,
}) => ChatOutput(
  id: id,
  kind: kind,
  listingId: listingId,
  interactionId: null,
  createdAt: DateTime.utc(2026, 11, 14, 10),
  updatedAt: updatedAt ?? DateTime.utc(2026, 11, 14, 12),
  participants:
      participants ??
      [
        participantJson(id: '01890a5d-ac96-774b-bcce-b302099a8058'),
        participantJson(
          id: '01890a5d-ac96-774b-bcce-b302099a8059',
          firstName: 'Мария',
          lastName: 'Петрова',
        ),
      ],
  lastMessage: lastMessage,
);

/// An in-memory server of chat operations with controllable failures.
class FakeChatApi implements ChatApi {
  FakeChatApi({
    List<ChatOutput>? chats,
    Map<String, List<MessageOutput>>? messages,
    List<ChatSearchResult>? searchResults,
  }) : chats = chats ?? [chatJson()],
       messages = messages ?? {},
       searchResults = searchResults ?? [];

  final List<ChatOutput> chats;
  final Map<String, List<MessageOutput>> messages;
  final List<ChatSearchResult> searchResults;

  final searchCalls = <({String query, String? cursor})>[];

  /// While set, a search request snapshots the results, then waits for it.
  Completer<void>? searchGate;

  /// Throws this instead of answering the next search request.
  Object? searchError;

  /// Maximum search results per page; the next cursor is the last message id.
  int? searchPageLimit;

  final createCalls = <ChatInput>[];
  final sendCalls =
      <
        ({
          String chatId,
          String clientId,
          String key,
          String text,
          String? replyToId,
          List<String> photoIds,
        })
      >[];
  final editCalls =
      <({String chatId, String messageId, String key, String text})>[];
  final deleteCalls = <({String chatId, String messageId, String key})>[];
  final listMessageCalls = <({String chatId, int? after, bool? ascending})>[];
  final photoRequests = <String>[];
  final photoRequestKeys = <String>[];
  final photoRequestCancels = <CancelToken?>[];
  final completePhotoCalls = <({String chatId, String fileId, String key})>[];
  final photoStatusCalls = <String>[];
  final messagePhotoCalls = <({String chatId, String messageId})>[];

  /// Created forms by upload key; a retry with the same key returns this.
  final photoForms = <String, ChatUploadOutput>{};

  /// Current state of every uploaded file, by id.
  final photoFiles = <String, ChatFileOutput>{};

  /// Failures after the server committed the form/completion, to model a
  /// lost response.
  Object? photoRequestError;
  Object? completePhotoError;

  /// While set, a form request waits for it, so a test can cancel the
  /// CancelToken before the server answers.
  Completer<void>? photoRequestGate;

  /// Statuses returned by `completeChatPhoto`, consumed in order; a ready
  /// result is synthesized when the queue is empty.
  final photoStatuses = <String>[];

  /// Signed photos returned for a message id.
  final messagePhotos = <String, List<ChatPhotoOutput>>{};
  Object? messagePhotosError;

  /// Failures of the next edit or delete request.
  Object? editError;
  Object? deleteError;

  int _photoSequence = 0;

  /// While set, every send waits for this future before replying.
  Completer<void>? sendGate;

  /// While set, messages requests snapshot the data, then wait for it.
  Completer<void>? listGate;

  /// Per-`after_sequence` gates, so a targeted event refresh can run while
  /// a stale page request is still in flight.
  final listGates = <int?, Completer<void>>{};

  /// Replaces the response of a specific request after its snapshot and
  /// gate, for simulating a stale read that must not erase newer data.
  List<MessageOutput>? Function(String chatId, int? afterSequence)?
  listOverride;

  /// While set, dialogs requests snapshot the data, then wait for it.
  Completer<void>? listChatsGate;

  /// Maximum dialogs per page; the next cursor is the last dialog id.
  int? listChatsPageLimit;

  /// Throws this instead of answering the next dialogs request.
  Object? listChatsError;

  final listChatsCalls = <String?>[];

  /// Maximum rows per messages page; the next cursor is the last sequence.
  int? pageLimit;

  /// Throws this instead of returning from the next list request.
  Object? listError;

  /// Throws this instead of answering a send, but stores the message first:
  /// this is a response lost after the server committed.
  bool loseNextResponse = false;

  /// The next send fails before reaching the server.
  Object? sendError;

  /// The next dialog creation fails with this error.
  Object? createError;

  final _storedByKey = <String, MessageOutput>{};
  int _serverSequence = 100;

  @override
  Future<PageChatOutput> listChats({String? cursor}) async {
    listChatsCalls.add(cursor);
    final snapshot = List<ChatOutput>.of(chats);
    final gate = listChatsGate;
    if (gate != null) await gate.future;
    final error = listChatsError;
    if (error != null) {
      listChatsError = null;
      throw error;
    }
    var start = 0;
    if (cursor != null) {
      final index = snapshot.indexWhere((chat) => chat.id == cursor);
      start = index < 0 ? 0 : index + 1;
    }
    final limit = listChatsPageLimit ?? snapshot.length;
    final end = start + limit > snapshot.length
        ? snapshot.length
        : start + limit;
    final items = snapshot.sublist(start, end);
    return PageChatOutput(
      items: items,
      nextPage: end < snapshot.length && items.isNotEmpty
          ? items.last.id
          : null,
    );
  }

  @override
  Future<PageChatSearchResult> searchChats({
    required String query,
    String? cursor,
    int? size,
  }) async {
    searchCalls.add((query: query, cursor: cursor));
    final normalized = query.trim().toLowerCase();
    final snapshot = searchResults
        .where(
          (result) =>
              normalized.isEmpty ||
              result.message.text.toLowerCase().contains(normalized) ||
              result.snippet.toLowerCase().contains(normalized),
        )
        .toList();
    final gate = searchGate;
    if (gate != null) await gate.future;
    final error = searchError;
    if (error != null) {
      searchError = null;
      throw error;
    }
    var start = 0;
    if (cursor != null) {
      final index = snapshot.indexWhere(
        (result) => result.message.id == cursor,
      );
      start = index < 0 ? 0 : index + 1;
    }
    final limit = searchPageLimit ?? size ?? 20;
    final end = start + limit > snapshot.length
        ? snapshot.length
        : start + limit;
    final items = snapshot.sublist(start, end);
    return PageChatSearchResult(
      items: items,
      nextPage: end < snapshot.length && items.isNotEmpty
          ? items.last.message.id
          : null,
    );
  }

  @override
  Future<ChatOutput> createChat({
    required String recipientId,
    String? listingId,
  }) async {
    createCalls.add(ChatInput(recipientId: recipientId, listingId: listingId));
    final error = createError;
    if (error != null) {
      createError = null;
      throw error;
    }
    return chats.first;
  }

  @override
  Future<ChatOutput> readChat(String chatId) async =>
      chats.firstWhere((chat) => chat.id == chatId);

  @override
  Future<PageMessageOutput> listMessages(
    String chatId, {
    int? afterSequence,
    bool? ascending,
    String? cursor,
    int? size,
  }) async {
    listMessageCalls.add((
      chatId: chatId,
      after: afterSequence,
      ascending: ascending,
    ));
    final snapshot = List<MessageOutput>.of(messages[chatId] ?? const [])
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final gate = listGates[afterSequence] ?? listGate;
    if (gate != null) await gate.future;
    final overridden = listOverride?.call(chatId, afterSequence);
    if (overridden != null) {
      return PageMessageOutput(items: overridden, nextPage: null);
    }
    final error = listError;
    if (error != null) {
      listError = null;
      throw error;
    }
    var rows = snapshot
        .where((row) => afterSequence == null || row.sequence > afterSequence)
        .toList();
    if (ascending == true) {
      rows.sort((a, b) => a.sequence.compareTo(b.sequence));
    } else {
      rows.sort((a, b) => b.sequence.compareTo(a.sequence));
    }
    if (cursor != null) {
      final at = int.parse(cursor);
      rows = rows
          .where(
            (row) => ascending == true ? row.sequence > at : row.sequence < at,
          )
          .toList();
    }
    String? nextPage;
    final limit = pageLimit;
    if (limit != null && rows.length > limit) {
      rows = rows.take(limit).toList();
      nextPage = '${rows.last.sequence}';
    }
    return PageMessageOutput(items: rows, nextPage: nextPage);
  }

  @override
  Future<MessageOutput> sendMessage(
    String chatId, {
    required String clientId,
    required String text,
    required String idempotencyKey,
    String? replyToId,
    List<String> photoIds = const [],
  }) async {
    sendCalls.add((
      chatId: chatId,
      clientId: clientId,
      key: idempotencyKey,
      text: text,
      replyToId: replyToId,
      photoIds: photoIds,
    ));
    final gate = sendGate;
    if (gate != null) await gate.future;
    final stored = _storedByKey[idempotencyKey];
    if (stored != null) return stored;
    final error = sendError;
    if (error != null) {
      sendError = null;
      throw error;
    }
    final quoted = replyToId == null
        ? null
        : (messages[chatId] ?? const <MessageOutput>[])
              .where((row) => row.id == replyToId)
              .firstOrNull;
    final message = messageJson(
      chatId: chatId,
      sequence: ++_serverSequence,
      clientId: clientId,
      text: text,
      replyToId: replyToId,
      replyTo: quoted == null ? null : quoteJson(quoted),
      photoIds: photoIds.isEmpty ? null : photoIds,
    );
    _storedByKey[idempotencyKey] = message;
    messages.putIfAbsent(chatId, () => []).add(message);
    if (loseNextResponse) {
      loseNextResponse = false;
      throw StateError('connection lost after commit');
    }
    return message;
  }

  @override
  Future<MessageOutput> editMessage(
    String chatId,
    String messageId, {
    required String text,
    required String idempotencyKey,
  }) async {
    editCalls.add((
      chatId: chatId,
      messageId: messageId,
      key: idempotencyKey,
      text: text,
    ));
    final error = editError;
    if (error != null) {
      editError = null;
      throw error;
    }
    final rows = messages[chatId] ?? const <MessageOutput>[];
    final index = rows.indexWhere((row) => row.id == messageId);
    if (index < 0) throw StateError('message not found');
    final current = rows[index];
    final updated = MessageOutput(
      id: current.id,
      chatId: current.chatId,
      senderId: current.senderId,
      clientId: current.clientId,
      sequence: current.sequence,
      text: text,
      replyToId: current.replyToId,
      replyTo: current.replyTo,
      version: current.version + 1,
      photoIds: current.photoIds,
      createdAt: current.createdAt,
    );
    rows[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required String idempotencyKey,
  }) async {
    deleteCalls.add((
      chatId: chatId,
      messageId: messageId,
      key: idempotencyKey,
    ));
    final error = deleteError;
    if (error != null) {
      deleteError = null;
      throw error;
    }
    messages[chatId]?.removeWhere((row) => row.id == messageId);
  }

  @override
  Future<ChatUploadOutput> requestChatPhoto(
    String chatId, {
    required String idempotencyKey,
    CancelToken? cancel,
  }) async {
    photoRequests.add(chatId);
    photoRequestKeys.add(idempotencyKey);
    photoRequestCancels.add(cancel);
    final gate = photoRequestGate;
    if (gate != null) await gate.future;
    if (cancel?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: cancel!.cancelError,
      );
    }
    final existing = photoForms[idempotencyKey];
    if (existing != null) return existing;
    final file = ChatFileOutput(
      id: 'file-${++_photoSequence}',
      purpose: 'chat_photo',
      status: 'pending',
      size: 1,
      rejectionReason: null,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final form = ChatUploadOutput(
      file: file,
      url: 'https://storage.test/upload',
      fields: const {},
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    photoFiles[file.id] = file;
    photoForms[idempotencyKey] = form;
    final error = photoRequestError;
    if (error != null) {
      photoRequestError = null;
      throw error;
    }
    return form;
  }

  @override
  Future<ChatFileOutput> completeChatPhoto(
    String chatId,
    String fileId, {
    required String idempotencyKey,
    CancelToken? cancel,
  }) async {
    completePhotoCalls.add((
      chatId: chatId,
      fileId: fileId,
      key: idempotencyKey,
    ));
    if (cancel?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: cancel!.cancelError,
      );
    }
    final current = photoFiles[fileId];
    if (current == null) throw StateError('file not found');
    final status = photoStatuses.isEmpty ? 'ready' : photoStatuses.removeAt(0);
    final file = ChatFileOutput(
      id: fileId,
      purpose: 'chat_photo',
      status: current.status == 'pending' ? 'processing' : status,
      size: 1,
      rejectionReason: status == 'rejected' ? 'invalid_image' : null,
      expiresAt: current.expiresAt,
    );
    photoFiles[fileId] = file;
    final error = completePhotoError;
    if (error != null) {
      completePhotoError = null;
      throw error;
    }
    return file;
  }

  @override
  Future<ChatFileOutput> getPhotoUpload(
    String fileId, {
    CancelToken? cancel,
  }) async {
    photoStatusCalls.add(fileId);
    if (cancel?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: cancel!.cancelError,
      );
    }
    final stored = photoFiles[fileId];
    if (stored == null) {
      return ChatFileOutput(
        id: fileId,
        purpose: 'chat_photo',
        status: 'ready',
        size: 1,
        rejectionReason: null,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
    }
    if (stored.status == 'processing') {
      final next = photoStatuses.isEmpty ? 'ready' : photoStatuses.removeAt(0);
      final ready = ChatFileOutput(
        id: stored.id,
        purpose: stored.purpose,
        status: next,
        size: stored.size,
        rejectionReason: next == 'rejected' ? 'invalid_image' : null,
        expiresAt: stored.expiresAt,
      );
      photoFiles[fileId] = ready;
      return ready;
    }
    return stored;
  }

  @override
  Future<ChatPhotosOutput> listMessagePhotos(
    String chatId,
    String messageId, {
    CancelToken? cancel,
  }) async {
    messagePhotoCalls.add((chatId: chatId, messageId: messageId));
    final error = messagePhotosError;
    if (error != null) {
      messagePhotosError = null;
      throw error;
    }
    return ChatPhotosOutput(items: messagePhotos[messageId] ?? const []);
  }
}

/// A realtime service double: the test emits publications and calls reload.
class FakeChatRealtime implements ChatRealtime {
  Future<void> Function()? reload;
  FakeChatSubscription? subscription;
  int subscribeCalls = 0;

  @override
  Future<RealtimeSubscription> subscribe(
    RealtimeChannel channel, {
    required Future<void> Function() reload,
  }) async {
    subscribeCalls++;
    this.reload = reload;
    return subscription = FakeChatSubscription(channel);
  }

  void emit({int offset = 1, Object? data}) {
    subscription?.emit(
      RealtimeEvent(
        channel: subscription!.channel.name,
        offset: offset,
        data: data ?? const {'type': 'chat.message'},
      ),
    );
  }
}

class FakeChatSubscription implements RealtimeSubscription {
  FakeChatSubscription(this.channel);

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _statuses = StreamController<RealtimeChannelStatus>.broadcast();
  bool closed = false;

  @override
  final RealtimeChannel channel;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<RealtimeChannelStatus> get status => _statuses.stream;

  @override
  RealtimeChannelStatus get currentStatus => RealtimeChannelStatus(
    channel: channel,
    phase: RealtimeSubscriptionPhase.subscribed,
  );

  void emit(RealtimeEvent event) => _events.add(event);

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
    await _statuses.close();
  }
}

/// A picker that returns files already in memory.
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker({this.galleryFiles = const [], this.cameraFile});

  final List<XFile> galleryFiles;
  final XFile? cameraFile;

  @override
  bool get hasCamera => cameraFile != null;

  @override
  Future<List<XFile>> gallery({required int limit}) async =>
      galleryFiles.take(limit).toList();

  @override
  Future<XFile?> camera() async => cameraFile;
}

XFile testImage(String name) => XFile.fromData(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
  name: name,
  mimeType: 'image/png',
);

/// A chat photo uploader with controllable processing outcomes.
class FakeChatPhotoUploader implements ChatPhotoUploader {
  final statuses = <String>[];
  final rejectionReasons = <String?>[];
  final calls = <({String chatId, int length})>[];
  final attempts =
      <({String uploadKey, String completeKey, String? formFileId})>[];

  /// While set, the upload waits for it after reporting processing.
  Completer<void>? gate;

  /// Throws this instead of returning a file; the form is still reported.
  Object? error;

  int _sequence = 0;

  @override
  Future<({ChatPhotoForm form, ChatFileOutput file})> upload(
    String chatId,
    Uint8List bytes, {
    required String filename,
    required String uploadKey,
    required String completeKey,
    ChatPhotoForm? form,
    required void Function(ChatPhotoForm form) onForm,
    void Function(double progress)? onProgress,
    void Function()? onProcessing,
    CancelToken? cancel,
  }) async {
    calls.add((chatId: chatId, length: bytes.length));
    attempts.add((
      uploadKey: uploadKey,
      completeKey: completeKey,
      formFileId: form?.fileId,
    ));
    onProgress?.call(0.5);
    final current =
        form ??
        ChatPhotoForm(
          url: 'https://storage.test/upload',
          fields: const {},
          fileId: 'upload-${++_sequence}',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
    if (form == null) onForm(current);
    onProcessing?.call();
    final wait = gate;
    if (wait != null) await wait.future;
    if (cancel?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: cancel!.cancelError,
      );
    }
    final failure = error;
    if (failure != null) {
      error = null;
      throw failure;
    }
    final status = statuses.isEmpty ? 'ready' : statuses.removeAt(0);
    final reason = rejectionReasons.isEmpty
        ? null
        : rejectionReasons.removeAt(0);
    return (
      form: current,
      file: ChatFileOutput(
        id: current.fileId,
        purpose: 'chat_photo',
        status: status,
        size: bytes.length,
        rejectionReason: reason,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}
