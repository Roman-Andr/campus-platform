import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/photos/photo_upload.dart';

part 'listing_photo_draft.g.dart';

enum PhotoSlotPhase { uploading, processing, ready, rejected, failed }

/// One photo of the listing form: a local file being uploaded or a photo
/// already attached on the server.
class PhotoSlot {
  const PhotoSlot({
    required this.key,
    required this.phase,
    this.name = '',
    this.bytes,
    this.progress = 0,
    this.fileId,
    this.previewUrl,
    this.rejectionReason,
    this.error,
  });

  /// Stable identity in the form; survives retries and reordering.
  final int key;
  final PhotoSlotPhase phase;
  final String name;

  /// Local content for the thumbnail and for a retry.
  final Uint8List? bytes;
  final double progress;
  final String? fileId;

  /// Signed preview of a photo attached before the form opened.
  final String? previewUrl;
  final String? rejectionReason;
  final Object? error;

  bool get busy =>
      phase == PhotoSlotPhase.uploading || phase == PhotoSlotPhase.processing;

  PhotoSlot copyWith({
    PhotoSlotPhase? phase,
    double? progress,
    String? fileId,
    String? rejectionReason,
    Object? error,
  }) => PhotoSlot(
    key: key,
    phase: phase ?? this.phase,
    name: name,
    bytes: bytes,
    progress: progress ?? this.progress,
    fileId: fileId ?? this.fileId,
    previewUrl: previewUrl,
    rejectionReason: rejectionReason,
    error: error,
  );
}

/// Files the form refused before uploading.
class PhotoAddResult {
  const PhotoAddResult({this.overLimit = 0, this.tooLarge = const []});
  final int overLimit;
  final List<String> tooLarge;
  bool get ok => overLimit == 0 && tooLarge.isEmpty;
}

/// Photos of one listing form. Uploads start as soon as files are chosen;
/// a rejected or failed photo never blocks publishing the others.
@riverpod
class ListingPhotoDraft extends _$ListingPhotoDraft {
  var _next = 0;
  final _cancels = <int, CancelToken>{};

  @override
  List<PhotoSlot> build() {
    ref.onDispose(() {
      for (final cancel in _cancels.values) {
        cancel.cancel();
      }
    });
    return const [];
  }

  int get limit => ref.read(photoConfigProvider).listingLimit;

  int get room => limit - state.length;

  /// Ids of processed photos in the chosen order.
  List<String> get readyIds => [
    for (final slot in state)
      if (slot.phase == PhotoSlotPhase.ready) slot.fileId!,
  ];

  bool get busy => state.any((slot) => slot.busy);

  /// Shows photos already attached to the listing being edited.
  void attached(List<PhotoOutput> photos) {
    state = [
      for (final photo in photos.take(limit))
        PhotoSlot(
          key: _next++,
          phase: PhotoSlotPhase.ready,
          fileId: photo.id,
          previewUrl: photo.previewUrl,
        ),
    ];
  }

  Future<PhotoAddResult> add(List<XFile> files) async {
    final config = ref.read(photoConfigProvider);
    final tooLarge = <String>[];
    final accepted = <PhotoSlot>[];
    var overLimit = 0;
    for (final file in files) {
      if (accepted.length >= room) {
        overLimit++;
        continue;
      }
      final size = await file.length();
      if (!ref.mounted) return const PhotoAddResult();
      if (size > config.maxBytes || size == 0) {
        tooLarge.add(file.name);
        continue;
      }
      accepted.add(
        PhotoSlot(
          key: _next++,
          phase: PhotoSlotPhase.uploading,
          name: file.name,
          bytes: await file.readAsBytes(),
        ),
      );
      if (!ref.mounted) return const PhotoAddResult();
    }
    state = [...state, ...accepted];
    for (final slot in accepted) {
      unawaited(_upload(slot));
    }
    return PhotoAddResult(overLimit: overLimit, tooLarge: tooLarge);
  }

  void retry(int key) {
    final slot = _slot(key);
    if (slot == null || slot.bytes == null || slot.busy) return;
    final fresh = PhotoSlot(
      key: slot.key,
      phase: PhotoSlotPhase.uploading,
      name: slot.name,
      bytes: slot.bytes,
    );
    _replace(fresh);
    unawaited(_upload(fresh));
  }

  void remove(int key) {
    _cancels.remove(key)?.cancel();
    state = [
      for (final slot in state)
        if (slot.key != key) slot,
    ];
  }

  /// Moves a photo, with [ReorderableListView] index semantics.
  void move(int from, int to) {
    final slots = [...state];
    final slot = slots.removeAt(from);
    slots.insert(to > from ? to - 1 : to, slot);
    state = slots;
  }

  Future<void> _upload(PhotoSlot slot) async {
    final cancel = CancelToken();
    _cancels[slot.key] = cancel;
    try {
      final file = await ref
          .read(photoUploaderProvider)
          .upload(
            slot.bytes!,
            filename: slot.name.isEmpty ? 'photo.jpg' : slot.name,
            cancel: cancel,
            onProgress: (progress) => _update(
              slot.key,
              (s) => s.copyWith(
                phase: PhotoSlotPhase.uploading,
                progress: progress,
              ),
            ),
            onProcessing: () => _update(
              slot.key,
              (s) => s.copyWith(phase: PhotoSlotPhase.processing, progress: 1),
            ),
          );
      _update(
        slot.key,
        (s) => photoFileStatus(file) == PhotoFileStatus.ready
            ? s.copyWith(phase: PhotoSlotPhase.ready, fileId: file.id)
            : s.copyWith(
                phase: PhotoSlotPhase.rejected,
                fileId: file.id,
                rejectionReason: file.rejectionReason ?? '',
              ),
      );
    } catch (error) {
      if (cancel.isCancelled) return;
      _update(
        slot.key,
        (s) => s.copyWith(phase: PhotoSlotPhase.failed, error: error),
      );
    } finally {
      if (identical(_cancels[slot.key], cancel)) _cancels.remove(slot.key);
    }
  }

  PhotoSlot? _slot(int key) =>
      state.where((slot) => slot.key == key).firstOrNull;

  void _replace(PhotoSlot next) =>
      state = [for (final slot in state) slot.key == next.key ? next : slot];

  void _update(int key, PhotoSlot Function(PhotoSlot) change) {
    if (!ref.mounted) return;
    final slot = _slot(key);
    if (slot != null) _replace(change(slot));
  }
}
