import 'package:material_ui/material_ui.dart';

import '../foundations/tokens.dart';

/// Presentation only; the upload pipeline owns transitions and retry policy.
enum PhotoStage { empty, local, uploading, processing, ready, failed }

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    required this.stage,
    required this.label,
    this.preview,
    this.action,
    super.key,
  });
  final PhotoStage stage;

  /// Explicit localized state name, including any retry/removal instruction.
  final String label;
  final Widget? preview;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: CampusGeometry.photoWidth,
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child:
                preview ??
                Icon(switch (stage) {
                  PhotoStage.empty => Icons.add_photo_alternate_outlined,
                  PhotoStage.local => Icons.photo_outlined,
                  PhotoStage.uploading => Icons.cloud_upload_outlined,
                  PhotoStage.processing => Icons.hourglass_top,
                  PhotoStage.ready => Icons.photo,
                  PhotoStage.failed => Icons.broken_image_outlined,
                }, semanticLabel: label),
          ),
          Padding(
            padding: const EdgeInsets.all(CampusSpace.sm),
            child: Text(label),
          ),
          ?action,
        ],
      ),
    ),
  );
}

/// Wraps for large text rather than imposing a fixed-height horizontal strip.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: CampusSpace.sm,
    runSpacing: CampusSpace.sm,
    children: children,
  );
}
