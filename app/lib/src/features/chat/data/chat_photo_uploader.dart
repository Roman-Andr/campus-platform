import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/photos/photo_upload.dart';
import 'chat_api.dart';

part 'chat_photo_uploader.g.dart';

/// A signed storage form and the server file it creates.
///
/// The form is kept with the draft slot before the bytes are sent: a lost
/// upload or completion response retries the same form, file id and keys.
/// A later form is only requested when this one has expired and the message
/// with its photo ids was not queued yet.
class ChatPhotoForm {
  const ChatPhotoForm({
    required this.url,
    required this.fields,
    required this.fileId,
    required this.expiresAt,
  });

  factory ChatPhotoForm.fromUpload(ChatUploadOutput upload) => ChatPhotoForm(
    url: upload.url,
    fields: Map<String, String>.unmodifiable(upload.fields),
    fileId: upload.file.id,
    expiresAt: upload.expiresAt,
  );

  final String url;
  final Map<String, String> fields;
  final String fileId;
  final DateTime expiresAt;
}

/// The signed form cannot be used any more; the caller starts a new logical
/// upload with fresh keys instead of retrying the expired one.
class ChatPhotoFormExpired implements Exception {
  const ChatPhotoFormExpired();
}

/// Uploads one chat photo and waits until the server has processed it.
///
/// [uploadKey] is reused for every request of the same form, [completeKey]
/// for every completion of the same file. Processing is polled with the
/// owned-file GET, never by repeating the completion POST: that POST returns
/// its cached response under the same key, not the current state.
abstract interface class ChatPhotoUploader {
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
  });
}

/// [ChatPhotoUploader] over the signed storage form and the chat API.
class StorageChatPhotoUploader implements ChatPhotoUploader {
  StorageChatPhotoUploader({
    required this.api,
    required this.storage,
    required this.config,
  });

  final ChatApi api;

  /// Signed storage client of the photos: no API base URL and no
  /// credentials, the form fields carry the authorization.
  final Dio storage;

  final PhotoConfig config;

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
    var current = form;
    if (current == null) {
      final requested = await api.requestChatPhoto(
        chatId,
        idempotencyKey: uploadKey,
        cancel: cancel,
      );
      current = ChatPhotoForm.fromUpload(requested);
      onForm(current);
    }
    if (!clock.now().isBefore(current.expiresAt)) {
      // A cached form can outlive its TTL when the first response was lost.
      throw const ChatPhotoFormExpired();
    }
    await storage.post<void>(
      current.url,
      // S3 POST policy: the file field must come after all other fields.
      data: FormData.fromMap({
        ...current.fields,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      cancelToken: cancel,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );
    onProgress?.call(1);
    var file = await api.getPhotoUpload(current.fileId, cancel: cancel);
    if (file.status == 'pending') {
      // Completion is a mutation with its own key. If its response is lost,
      // the next GET says whether the server accepted it.
      file = await api.completeChatPhoto(
        chatId,
        current.fileId,
        idempotencyKey: completeKey,
        cancel: cancel,
      );
      onProcessing?.call();
    } else if (_waiting(file.status)) {
      onProcessing?.call();
    }
    final deadline = clock.now().add(config.processingTimeout);
    while (_waiting(file.status)) {
      if (clock.now().isAfter(deadline)) throw const PhotoProcessingTimeout();
      await Future<void>.delayed(config.pollInterval);
      if (cancel?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: cancel!.cancelError,
        );
      }
      file = await api.getPhotoUpload(current.fileId, cancel: cancel);
    }
    return (form: current, file: file);
  }

  static bool _waiting(String status) =>
      status == 'pending' || status == 'processing';
}

@Riverpod(keepAlive: true)
ChatPhotoUploader chatPhotoUploader(Ref ref) => StorageChatPhotoUploader(
  api: ref.watch(chatApiProvider),
  storage: ref.watch(storageDioProvider),
  config: ref.watch(photoConfigProvider),
);
