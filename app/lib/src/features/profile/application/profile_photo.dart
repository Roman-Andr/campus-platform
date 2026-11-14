import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/photos/photo_upload.dart';

part 'profile_photo.g.dart';

/// The chosen file is larger than [PhotoConfig.maxBytes].
class ProfilePhotoTooLarge implements Exception {
  const ProfilePhotoTooLarge();
}

/// The server refused the photo; [reason] is its code, e.g.
/// `invalid_image`.
class ProfilePhotoRejected implements Exception {
  const ProfilePhotoRejected(this.reason);

  final String? reason;
}

/// The signed-in user's profile photo with fresh signed links; `null`
/// without a photo or a signed-in user (ТЗ п. 5.1.1, модуль 2, п. 1).
@Riverpod(keepAlive: true)
class MyPhoto extends _$MyPhoto {
  @override
  Future<ProfilePhoto?> build() async {
    final status = ref.watch(authStatusProvider.select((value) => value.value));
    if (status != AuthenticationStatus.authenticated) return null;
    try {
      return await ref.read(campusApiProvider).profile.getMyPhoto();
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Uploads [file] through the server's checks and makes it the profile
  /// photo; the previous photo is deleted by the server.
  ///
  /// Throws [ProfilePhotoTooLarge] and [ProfilePhotoRejected] for files the
  /// server would not take, API failures otherwise.
  Future<void> upload(
    XFile file, {
    void Function(double progress)? onProgress,
    void Function()? onProcessing,
  }) async {
    final config = ref.read(photoConfigProvider);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > config.maxBytes) {
      throw const ProfilePhotoTooLarge();
    }
    final uploaded = await ref
        .read(photoUploaderProvider)
        .upload(
          bytes,
          filename: file.name,
          onProgress: onProgress,
          onProcessing: onProcessing,
        );
    if (photoFileStatus(uploaded) != PhotoFileStatus.ready) {
      throw ProfilePhotoRejected(uploaded.rejectionReason);
    }
    final photo = await ref
        .read(campusApiProvider)
        .profile
        .setMyPhoto(body: ProfilePhotoInput(fileId: uploaded.id));
    state = AsyncData(photo);
  }

  /// Removes the photo; its links stop working.
  Future<void> remove() async {
    await ref.read(campusApiProvider).profile.deleteMyPhoto();
    state = const AsyncData(null);
  }
}
