import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';

part 'photo_upload.g.dart';

/// Client-side photo parameters (ТЗ, Приложение 4).
///
/// Values come from `--dart-define` at build time (README, "Фото"); the
/// limits must match the server's `CAMPUS_PHOTO_*` settings.
class PhotoConfig {
  const PhotoConfig({
    required this.maxBytes,
    required this.listingLimit,
    required this.pollInterval,
    required this.processingTimeout,
  });

  factory PhotoConfig.fromEnvironment() => const PhotoConfig(
    maxBytes: int.fromEnvironment(
      'CAMPUS_PHOTO_MAX_BYTES',
      defaultValue: 10 * 1024 * 1024,
    ),
    listingLimit: int.fromEnvironment(
      'CAMPUS_PHOTO_LISTING_LIMIT',
      defaultValue: 10,
    ),
    pollInterval: Duration(
      milliseconds: int.fromEnvironment(
        'CAMPUS_PHOTO_POLL_INTERVAL_MS',
        defaultValue: 1000,
      ),
    ),
    processingTimeout: Duration(
      seconds: int.fromEnvironment(
        'CAMPUS_PHOTO_PROCESSING_TIMEOUT',
        defaultValue: 120,
      ),
    ),
  );

  /// Largest accepted source file; the server's `CAMPUS_PHOTO_MAX_BYTES`.
  final int maxBytes;

  /// Photos per listing; the server's `CAMPUS_PHOTO_LISTING_LIMIT`.
  final int listingLimit;

  /// Delay between status checks while the server processes a photo.
  final Duration pollInterval;

  /// How long to wait for processing before offering a retry.
  final Duration processingTimeout;
}

@Riverpod(keepAlive: true)
PhotoConfig photoConfig(Ref ref) => PhotoConfig.fromEnvironment();

/// Chooses photos with the platform UI: camera and gallery on mobile, a file
/// dialog on the web and desktop.
abstract interface class PhotoPicker {
  bool get hasCamera;
  Future<List<XFile>> gallery({required int limit});
  Future<XFile?> camera();
}

class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  bool get hasCamera => _picker.supportsImageSource(ImageSource.camera);

  @override
  Future<List<XFile>> gallery({required int limit}) => limit == 1
      ? _picker.pickImage(source: ImageSource.gallery).then((f) => [?f])
      : _picker.pickMultiImage(limit: limit, requestFullMetadata: false);

  @override
  Future<XFile?> camera() =>
      _picker.pickImage(source: ImageSource.camera, requestFullMetadata: false);
}

@Riverpod(keepAlive: true)
PhotoPicker photoPicker(Ref ref) => ImagePickerPhotoPicker();

/// Client for the signed storage form: no API base URL and no credentials,
/// the form fields carry the authorization.
@Riverpod(keepAlive: true)
Dio storageDio(Ref ref) {
  final config = ref.watch(apiConfigProvider);
  final dio = Dio(
    BaseOptions(
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
    ),
  );
  final adapter = ref.watch(apiHttpAdapterProvider);
  if (adapter != null) dio.httpClientAdapter = adapter;
  ref.onDispose(dio.close);
  return dio;
}

/// Server-side outcome of an uploaded photo.
enum PhotoFileStatus { pending, processing, ready, rejected, unknown }

PhotoFileStatus photoFileStatus(FileOutput file) => switch (file.status) {
  'pending' => PhotoFileStatus.pending,
  'processing' => PhotoFileStatus.processing,
  'ready' => PhotoFileStatus.ready,
  'rejected' => PhotoFileStatus.rejected,
  _ => PhotoFileStatus.unknown,
};

bool _waiting(PhotoFileStatus status) =>
    status == PhotoFileStatus.pending || status == PhotoFileStatus.processing;

/// Processing did not finish in [PhotoConfig.processingTimeout].
class PhotoProcessingTimeout implements Exception {
  const PhotoProcessingTimeout();
}

/// Uploads one photo: requests a signed form, posts the file with progress,
/// asks the server to process it and waits for the verdict.
///
/// Returns the final file — `ready` or `rejected` with its reason. Network
/// and server failures are thrown; a retry starts a new upload, and the
/// server removes abandoned ones by itself.
class PhotoUploader {
  PhotoUploader({
    required this.api,
    required this.storage,
    required this.config,
  });

  final CampusApi api;
  final Dio storage;
  final PhotoConfig config;

  Future<FileOutput> upload(
    Uint8List bytes, {
    required String filename,
    void Function(double progress)? onProgress,
    void Function()? onProcessing,
    CancelToken? cancel,
  }) async {
    final form = await api.photos.requestPhotoUpload(cancelToken: cancel);
    await storage.post<void>(
      form.url,
      // S3 POST policy: the file field must come after all other fields.
      data: FormData.fromMap({
        ...form.fields,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      cancelToken: cancel,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );
    onProgress?.call(1);
    var file = await api.photos.completePhotoUpload(
      fileId: form.file.id,
      cancelToken: cancel,
    );
    onProcessing?.call();
    final deadline = clock.now().add(config.processingTimeout);
    while (_waiting(photoFileStatus(file))) {
      if (clock.now().isAfter(deadline)) throw const PhotoProcessingTimeout();
      await Future<void>.delayed(config.pollInterval);
      if (cancel?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: cancel!.cancelError,
        );
      }
      file = await api.photos.getPhotoUpload(
        fileId: file.id,
        cancelToken: cancel,
      );
    }
    return file;
  }
}

@riverpod
PhotoUploader photoUploader(Ref ref) => PhotoUploader(
  api: ref.watch(campusApiProvider),
  storage: ref.watch(storageDioProvider),
  config: ref.watch(photoConfigProvider),
);
