import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/photos/photo_image.dart';
import '../../../core/photos/photo_upload.dart';
import '../application/profile_photo.dart';

/// The profile photo as a round preview, or an icon without one.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({required this.photo, this.radius = 40, super.key});

  final ProfilePhoto? photo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return CircleAvatar(
      radius: radius,
      child: photo == null
          ? Icon(Icons.person_outline, size: radius)
          : ClipOval(
              child: SizedBox.square(
                dimension: radius * 2,
                child: CampusPhoto(
                  key: const Key('profile-photo-image'),
                  url: photo.previewUrl,
                  // Signed links change on every read; the file does not.
                  cacheKey: '${photo.id}-preview',
                  semanticLabel: context.l10n.profilePhoto,
                ),
              ),
            ),
    );
  }
}

/// The profile photo with ways to choose, replace or remove it.
class ProfilePhotoEditor extends ConsumerStatefulWidget {
  const ProfilePhotoEditor({super.key});

  @override
  ConsumerState<ProfilePhotoEditor> createState() => _ProfilePhotoEditorState();
}

enum _Stage { idle, uploading, processing, removing }

class _ProfilePhotoEditorState extends ConsumerState<ProfilePhotoEditor> {
  var _stage = _Stage.idle;
  double? _progress;
  String? _error;

  bool get _busy => _stage != _Stage.idle;

  Future<void> _pick(Future<XFile?> Function(PhotoPicker picker) pick) async {
    final file = await pick(ref.read(photoPickerProvider));
    if (file == null || !mounted) return;
    setState(() {
      _stage = _Stage.uploading;
      _progress = null;
      _error = null;
    });
    try {
      await ref
          .read(myPhotoProvider.notifier)
          .upload(
            file,
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress);
            },
            onProcessing: () {
              if (mounted) setState(() => _stage = _Stage.processing);
            },
          );
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _stage = _Stage.idle);
    }
  }

  Future<void> _remove() async {
    setState(() {
      _stage = _Stage.removing;
      _error = null;
    });
    try {
      await ref.read(myPhotoProvider.notifier).remove();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _stage = _Stage.idle);
    }
  }

  String _message(Object error) {
    final l10n = context.l10n;
    return switch (error) {
      ProfilePhotoTooLarge() => l10n.profilePhotoTooLarge(
        ref.read(photoConfigProvider).maxBytes ~/ (1024 * 1024),
      ),
      ProfilePhotoRejected() => l10n.profilePhotoRejected,
      PhotoProcessingTimeout() => l10n.profilePhotoTimeout,
      _ => apiFailureMessage(l10n, error),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final photo = ref.watch(myPhotoProvider);
    final picker = ref.watch(photoPickerProvider);
    final current = photo.value;
    final error = _error;
    return Column(
      children: [
        ProfileAvatar(photo: current, radius: 56),
        const SizedBox(height: 12),
        if (_stage == _Stage.uploading || _stage == _Stage.processing) ...[
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              key: const Key('profile-photo-progress'),
              value: _stage == _Stage.uploading ? _progress : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _stage == _Stage.uploading
                ? l10n.profilePhotoUploading
                : l10n.profilePhotoProcessing,
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              error,
              key: const Key('profile-photo-error'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('profile-photo-gallery'),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                current == null
                    ? l10n.profilePhotoChoose
                    : l10n.profilePhotoReplace,
              ),
              onPressed: _busy || photo.isLoading
                  ? null
                  : () => unawaited(
                      _pick(
                        (picker) => picker
                            .gallery(limit: 1)
                            .then((files) => files.firstOrNull),
                      ),
                    ),
            ),
            if (picker.hasCamera)
              OutlinedButton.icon(
                key: const Key('profile-photo-camera'),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.profilePhotoCamera),
                onPressed: _busy || photo.isLoading
                    ? null
                    : () => unawaited(_pick((picker) => picker.camera())),
              ),
            if (current != null)
              TextButton.icon(
                key: const Key('profile-photo-remove'),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.profilePhotoRemove),
                onPressed: _busy ? null : () => unawaited(_remove()),
              ),
          ],
        ),
      ],
    );
  }
}
