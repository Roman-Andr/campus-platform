import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the image of a signed link. Signed links change on every read,
/// so the disk cache is keyed by the stable [cacheKey] (file id and size).
typedef PhotoImageFactory = ImageProvider Function(
  String url, {
  required String cacheKey,
});

/// Cached network images; tests override it with in-memory images.
final photoImageProvider = Provider<PhotoImageFactory>(
  (ref) =>
      (url, {required cacheKey}) =>
          CachedNetworkImageProvider(url, cacheKey: cacheKey),
);

/// A private photo by its signed link, with a neutral placeholder while it
/// loads and when it can't be shown.
class CampusPhoto extends ConsumerWidget {
  const CampusPhoto({
    required this.url,
    required this.cacheKey,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    super.key,
  });

  final String url;
  final String cacheKey;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Image(
    image: ref.watch(photoImageProvider)(url, cacheKey: cacheKey),
    fit: fit,
    semanticLabel: semanticLabel,
    frameBuilder: (context, child, frame, sync) =>
        frame == null && !sync ? const PhotoPlaceholder() : child,
    errorBuilder: (context, _, _) =>
        const PhotoPlaceholder(icon: Icons.broken_image_outlined),
  );
}

class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({this.icon = Icons.image_outlined, super.key});
  final IconData icon;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Icon(icon, color: Theme.of(context).colorScheme.outline),
    ),
  );
}
