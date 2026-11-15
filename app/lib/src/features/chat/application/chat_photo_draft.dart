import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/photos/photo_upload.dart';
import '../data/chat_photo_uploader.dart';
import 'chat_config.dart';

part 'chat_photo_draft.g.dart';

/// The stage of one photo chosen for a chat message.
enum ChatPhotoPhase { uploading, processing, ready, rejected, failed }

/// One photo attached to the composer of a chat.
///
/// Only a [ChatPhotoPhase.ready] slot has a server file id and may be sent;
/// the bytes stay in memory for the thumbnail and for a retry.
class ChatPhotoSlot {
  const ChatPhotoSlot({
    required this.key,
    required this.phase,
    required this.uploadKey,
    required this.completeKey,
    this.name = '',
    this.bytes,
    this.progress = 0,
    this.form,
    this.fileId,
    this.rejectionReason,
    this.error,
  });

  /// Stable identity in the composer; survives a retry.
  final int key;
  final ChatPhotoPhase phase;
  final String name;

  /// Local content for the thumbnail and for a retry.
  final Uint8List? bytes;
  final double progress;

  /// Key of the upload-form request, kept for a retry after a lost response.
  final String uploadKey;

  /// Key of the completion mutation; a poll never reuses it.
  final String completeKey;

  /// Signed form and file id received for this slot.
  final ChatPhotoForm? form;

  final String? fileId;

  /// Server reason of a rejected image, e.g. `invalid_size`.
  final String? rejectionReason;
  final Object? error;

  bool get busy =>
      phase == ChatPhotoPhase.uploading || phase == ChatPhotoPhase.processing;

  bool get formExpired {
    final current = form;
    return current != null && !clock.now().isBefore(current.expiresAt);
  }

  ChatPhotoSlot copyWith({
    ChatPhotoPhase? phase,
    double? progress,
    ChatPhotoForm? form,
    String? fileId,
    String? rejectionReason,
    Object? error,
  }) => ChatPhotoSlot(
    key: key,
    phase: phase ?? this.phase,
    uploadKey: uploadKey,
    completeKey: completeKey,
    name: name,
    bytes: bytes,
    progress: progress ?? this.progress,
    form: form ?? this.form,
    fileId: fileId ?? this.fileId,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    error: error ?? this.error,
  );
}

/// Files the composer refused before uploading.
class ChatPhotoAddResult {
  const ChatPhotoAddResult({this.overLimit = 0, this.tooLarge = const []});
  final int overLimit;
  final List<String> tooLarge;
  bool get ok => overLimit == 0 && tooLarge.isEmpty;
}

/// Photos of one chat composer.
///
/// Uploading starts as soon as files are chosen and the composer may send
/// the message only when every chosen photo is ready: the server rejects an
/// unprocessed id, and a rejected or failed photo never hides that fact.
@riverpod
class ChatPhotoDraft extends _$ChatPhotoDraft {
  var _next = 0;
  final _cancels = <int, CancelToken>{};
  final _owners = <int, String>{};

  @override
  List<ChatPhotoSlot> build(String chatId) {
    ref.listen(authStatusProvider, (previous, next) {
      final was = previous?.value;
      final now = next.value;
      if (was != null && now != null && was != now) _dropAccountChange();
    });
    ref.onDispose(() {
      for (final cancel in _cancels.values) {
        cancel.cancel();
      }
      _cancels.clear();
    });
    return const [];
  }

  int get limit => ref.read(chatConfigProvider).maxPhotos;

  int get room => limit - state.length;

  /// Ids of processed photos in the chosen order.
  List<String> get readyIds => [
    for (final slot in state)
      if (slot.phase == ChatPhotoPhase.ready) slot.fileId!,
  ];

  bool get busy => state.any((slot) => slot.busy);

  bool get failed => state.any(
    (slot) =>
        slot.phase == ChatPhotoPhase.rejected ||
        slot.phase == ChatPhotoPhase.failed,
  );

  Future<ChatPhotoAddResult> add(List<XFile> files) async {
    final owner = await ref.read(authStorageProvider).cacheNamespace();
    if (!ref.mounted) return const ChatPhotoAddResult();
    final config = ref.read(photoConfigProvider);
    final tooLarge = <String>[];
    final accepted = <ChatPhotoSlot>[];
    var overLimit = 0;
    for (final file in files) {
      if (accepted.length >= room) {
        overLimit++;
        continue;
      }
      final size = await file.length();
      if (!ref.mounted) return const ChatPhotoAddResult();
      if (size == 0 || size > config.maxBytes) {
        tooLarge.add(file.name);
        continue;
      }
      final bytes = await file.readAsBytes();
      if (!ref.mounted) return const ChatPhotoAddResult();
      accepted.add(
        ChatPhotoSlot(
          key: _next++,
          phase: ChatPhotoPhase.uploading,
          uploadKey: const Uuid().v7(),
          completeKey: const Uuid().v7(),
          name: file.name,
          bytes: bytes,
        ),
      );
    }
    state = [...state, ...accepted];
    for (final slot in accepted) {
      _owners[slot.key] = owner;
      unawaited(_upload(slot, owner));
    }
    return ChatPhotoAddResult(overLimit: overLimit, tooLarge: tooLarge);
  }

  void retry(int key) {
    final slot = _slot(key);
    final owner = _owners[key];
    if (slot == null || slot.bytes == null || slot.busy || owner == null) {
      return;
    }
    final fresh = ChatPhotoSlot(
      key: slot.key,
      phase: ChatPhotoPhase.uploading,
      uploadKey: slot.uploadKey,
      completeKey: slot.completeKey,
      name: slot.name,
      bytes: slot.bytes,
      form: slot.form,
    );
    _replace(fresh);
    unawaited(_upload(fresh, owner));
  }

  void remove(int key) {
    _cancels.remove(key)?.cancel();
    _owners.remove(key);
    state = [
      for (final slot in state)
        if (slot.key != key) slot,
    ];
  }

  /// Drops every attachment after the message was accepted by the queue.
  void clear() {
    for (final cancel in _cancels.values) {
      cancel.cancel();
    }
    _cancels.clear();
    _owners.clear();
    state = const [];
  }

  Future<void> _upload(ChatPhotoSlot slot, String owner) async {
    var current = _slot(slot.key) ?? slot;
    if (current.formExpired) {
      // The signed form (and its file id) expired before the message was
      // queued. That is the only case where a new logical upload starts;
      // the old keys cannot return a usable form any more.
      current = _freshForm(current);
      _replace(current);
    }
    final cancel = CancelToken();
    _cancels[slot.key] = cancel;
    try {
      final result = await ref
          .read(chatPhotoUploaderProvider)
          .upload(
            chatId,
            current.bytes!,
            filename: current.name.isEmpty ? 'photo.jpg' : current.name,
            uploadKey: current.uploadKey,
            completeKey: current.completeKey,
            form: current.form,
            onForm: (form) {
              if (!ref.mounted) return;
              _update(current.key, (s) => s.copyWith(form: form));
            },
            cancel: cancel,
            onProgress: (progress) => _update(
              current.key,
              (s) => s.copyWith(
                phase: ChatPhotoPhase.uploading,
                progress: progress,
              ),
            ),
            onProcessing: () => _update(
              current.key,
              (s) => s.copyWith(phase: ChatPhotoPhase.processing, progress: 1),
            ),
          );
      if (cancel.isCancelled) return;
      if (!await _stillOwner(owner)) {
        _dropAccountChange();
        return;
      }
      final file = result.file;
      _update(
        current.key,
        (s) => file.status == 'ready'
            ? s.copyWith(
                phase: ChatPhotoPhase.ready,
                progress: 1,
                fileId: file.id,
              )
            : s.copyWith(
                phase: ChatPhotoPhase.rejected,
                fileId: file.id,
                rejectionReason: file.rejectionReason ?? '',
              ),
      );
    } on Object catch (error) {
      if (cancel.isCancelled) return;
      if (!await _stillOwner(owner)) {
        _dropAccountChange();
        return;
      }
      final failure = ApiFailure.from(error);
      final expired =
          error is ChatPhotoFormExpired ||
          (failure is ProblemFailure &&
              failure.code == ProblemCode.chatPhotoExpired);
      _update(
        current.key,
        (s) => (expired ? _freshForm(s) : s).copyWith(
          phase: ChatPhotoPhase.failed,
          error: error,
        ),
      );
    } finally {
      if (identical(_cancels[slot.key], cancel)) _cancels.remove(slot.key);
    }
  }

  ChatPhotoSlot _freshForm(ChatPhotoSlot slot) => ChatPhotoSlot(
    key: slot.key,
    phase: ChatPhotoPhase.uploading,
    uploadKey: const Uuid().v7(),
    completeKey: const Uuid().v7(),
    name: slot.name,
    bytes: slot.bytes,
  );

  /// The account changed while the bytes were in flight: nothing of the old
  /// session may stay attached to the composer of the next one.
  void _dropAccountChange() {
    if (!ref.mounted) return;
    for (final cancel in _cancels.values) {
      cancel.cancel();
    }
    _cancels.clear();
    _owners.clear();
    state = const [];
  }

  /// A sign-out or account switch while the bytes were in flight must not
  /// publish the old account's upload into the next session.
  Future<bool> _stillOwner(String owner) async {
    if (!ref.mounted) return false;
    final current = await ref.read(authStorageProvider).cacheNamespace();
    return ref.mounted && current == owner;
  }

  ChatPhotoSlot? _slot(int key) =>
      state.where((slot) => slot.key == key).firstOrNull;

  void _replace(ChatPhotoSlot next) =>
      state = [for (final slot in state) slot.key == next.key ? next : slot];

  void _update(int key, ChatPhotoSlot Function(ChatPhotoSlot) change) {
    if (!ref.mounted) return;
    final slot = _slot(key);
    if (slot != null) _replace(change(slot));
  }
}
