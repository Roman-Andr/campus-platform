import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/photos/photo_image.dart';
import '../../../core/photos/photo_upload.dart';
import '../application/listing_photo_draft.dart';
import '../application/listings.dart';

const _thumb = 96.0;
const _galleryHeight = 260.0;

String rejectionMessage(AppLocalizations l, String? reason, int maxMegabytes) =>
    switch (reason) {
      'invalid_size' => l.photoRejectedTooLarge(maxMegabytes),
      'unsupported_image' => l.photoRejectedUnsupported,
      'too_many_pixels' => l.photoRejectedTooManyPixels,
      'invalid_image' => l.photoRejectedInvalidImage,
      _ => l.photoRejectedOther,
    };

int megabytes(int bytes) => (bytes / (1024 * 1024)).ceil();

/// Photos of the listing form: choose, watch the upload, reorder, remove.
class ListingPhotosField extends ConsumerStatefulWidget {
  const ListingPhotosField({super.key});
  @override
  ConsumerState<ListingPhotosField> createState() => _ListingPhotosFieldState();
}

class _ListingPhotosFieldState extends ConsumerState<ListingPhotosField> {
  List<String> notices = [];

  Future<void> _add(Future<List<XFile>> Function(int room) pick) async {
    final draft = ref.read(listingPhotoDraftProvider.notifier);
    final l = context.l10n;
    final config = ref.read(photoConfigProvider);
    final files = await pick(draft.room);
    if (files.isEmpty || !mounted) return;
    final result = await draft.add(files);
    if (!mounted) return;
    setState(
      () => notices = [
        if (result.overLimit > 0) l.photoLimit(config.listingLimit),
        for (final name in result.tooLarge)
          l.photoTooLarge(name, megabytes(config.maxBytes)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final slots = ref.watch(listingPhotoDraftProvider);
    final draft = ref.read(listingPhotoDraftProvider.notifier);
    final config = ref.watch(photoConfigProvider);
    final picker = ref.watch(photoPickerProvider);
    final full = slots.length >= config.listingLimit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.photoCount(slots.length, config.listingLimit),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (slots.isNotEmpty)
            SizedBox(
              height: _thumb + 56,
              child: ReorderableListView(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                onReorderItem: draft.move,
                children: [
                  for (final (index, slot) in slots.indexed)
                    ReorderableDelayedDragStartListener(
                      key: ValueKey(slot.key),
                      index: index,
                      child: _SlotTile(
                        slot: slot,
                        index: index,
                        maxMegabytes: megabytes(config.maxBytes),
                      ),
                    ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('photo-gallery'),
                onPressed: full
                    ? null
                    : () => _add((room) => picker.gallery(limit: room)),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l.photoChoose),
              ),
              if (picker.hasCamera)
                OutlinedButton.icon(
                  key: const Key('photo-camera'),
                  onPressed: full
                      ? null
                      : () => _add((_) async => [?await picker.camera()]),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(l.photoTake),
                ),
            ],
          ),
          for (final notice in notices)
            Text(
              notice,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}

class _SlotTile extends ConsumerWidget {
  const _SlotTile({
    required this.slot,
    required this.index,
    required this.maxMegabytes,
  });
  final PhotoSlot slot;
  final int index;
  final int maxMegabytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final draft = ref.read(listingPhotoDraftProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final image = slot.bytes != null
        ? Image.memory(
            slot.bytes!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const PhotoPlaceholder(icon: Icons.broken_image_outlined),
          )
        : slot.previewUrl != null
        ? CampusPhoto(url: slot.previewUrl!, cacheKey: 'preview:${slot.fileId}')
        : const PhotoPlaceholder();
    final status = switch (slot.phase) {
      PhotoSlotPhase.uploading => l.photoUploading(
        (slot.progress * 100).round(),
      ),
      PhotoSlotPhase.processing => l.photoProcessing,
      PhotoSlotPhase.ready => null,
      PhotoSlotPhase.rejected => l.photoRejected(
        rejectionMessage(l, slot.rejectionReason, maxMegabytes),
      ),
      PhotoSlotPhase.failed => apiFailureMessage(l, slot.error ?? ''),
    };
    final problem =
        slot.phase == PhotoSlotPhase.rejected ||
        slot.phase == PhotoSlotPhase.failed;
    return Padding(
      key: Key('photo-slot-$index'),
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: _thumb,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: _thumb,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(opacity: problem ? 0.4 : 1, child: image),
                    if (slot.busy)
                      Center(
                        child: CircularProgressIndicator(
                          value: slot.phase == PhotoSlotPhase.uploading
                              ? slot.progress
                              : null,
                        ),
                      ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton.filledTonal(
                        key: Key('photo-remove-$index'),
                        visualDensity: VisualDensity.compact,
                        tooltip: l.photoRemove,
                        onPressed: () => draft.remove(slot.key),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ),
                    if (index > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: IconButton.filledTonal(
                          key: Key('photo-earlier-$index'),
                          visualDensity: VisualDensity.compact,
                          tooltip: l.photoMoveEarlier,
                          onPressed: () => draft.move(index, index - 1),
                          icon: const Icon(Icons.chevron_left, size: 16),
                        ),
                      ),
                    if (slot.phase == PhotoSlotPhase.failed)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: IconButton.filled(
                          key: Key('photo-retry-$index'),
                          visualDensity: VisualDensity.compact,
                          tooltip: l.errorRetry,
                          onPressed: () => draft.retry(slot.key),
                          icon: const Icon(Icons.refresh, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (status != null)
              Expanded(
                child: Text(
                  status,
                  key: Key('photo-status-$index'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: problem ? scheme.error : null),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Swipeable photos on the listing card; nothing when there are none.
class ListingGallery extends ConsumerStatefulWidget {
  const ListingGallery({required this.id, super.key});
  final String id;
  @override
  ConsumerState<ListingGallery> createState() => _ListingGalleryState();
}

class _ListingGalleryState extends ConsumerState<ListingGallery> {
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final photos = ref.watch(listingPhotosProvider(widget.id));
    return switch (photos) {
      AsyncValue(value: final items?) when items.isNotEmpty => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            SizedBox(
              height: _galleryHeight,
              child: PageView(
                key: const Key('listing-gallery'),
                onPageChanged: (index) => setState(() => page = index),
                children: [
                  for (final (index, photo) in items.indexed)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CampusPhoto(
                        url: photo.url,
                        cacheKey: 'photo:${photo.id}',
                        fit: BoxFit.contain,
                        semanticLabel: l.photoOf(index + 1, items.length),
                      ),
                    ),
                ],
              ),
            ),
            if (items.length > 1)
              Text(
                l.photoOf(page.clamp(0, items.length - 1) + 1, items.length),
              ),
          ],
        ),
      ),
      AsyncValue(isLoading: true, hasValue: false) => const SizedBox(
        height: _galleryHeight,
        child: PhotoPlaceholder(),
      ),
      AsyncError(:final error) => Row(
        children: [
          Expanded(child: Text(apiFailureMessage(l, error))),
          TextButton(
            onPressed: () => ref.invalidate(listingPhotosProvider(widget.id)),
            child: Text(l.errorRetry),
          ),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The first photo's preview carried by a listing row; a plain icon without
/// photos. The link comes with the row, so a feed page needs no photo request.
class ListingThumbnail extends StatelessWidget {
  const ListingThumbnail({required this.listing, super.key});
  final ListingOutput listing;
  @override
  Widget build(BuildContext context) {
    final url = listing.previewUrl;
    return SizedBox.square(
      dimension: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: url == null
            ? const PhotoPlaceholder()
            : CampusPhoto(
                key: Key('listing-thumbnail-${listing.id}'),
                url: url,
                cacheKey: 'preview:${listing.previewFileId ?? listing.id}',
                semanticLabel: context.l10n.photoPreview,
              ),
      ),
    );
  }
}
