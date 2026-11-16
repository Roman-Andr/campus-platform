import 'package:material_ui/material_ui.dart';

import '../components/components.dart';
import '../foundations/tokens.dart';
import '../theme/campus_colors.dart';

/// A redacted identity is represented by an absent name/image, not fake data.
@immutable
class AuthorViewData {
  const AuthorViewData({
    required this.redactedLabel,
    this.name,
    this.detail,
    this.image,
  });
  final String? name;
  final String? detail;
  final ImageProvider? image;
  final String redactedLabel;
}

class AuthorRow extends StatelessWidget {
  const AuthorRow({required this.data, this.trailing, super.key});
  final AuthorViewData data;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      CampusAvatar(
        label: data.name ?? data.redactedLabel,
        image: data.name == null ? null : data.image,
      ),
      const SizedBox(width: CampusSpace.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.name ?? data.redactedLabel),
            if (data.name != null && data.detail != null)
              Text(data.detail!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

@immutable
class StatusViewData {
  const StatusViewData({
    required this.label,
    this.tone = NoticeTone.information,
  });

  /// Display label supplied by the feature mapper, including unknown fallback.
  final String label;
  final NoticeTone tone;
}

class StatusLabel extends StatelessWidget {
  const StatusLabel({required this.data, super.key});
  final StatusViewData data;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme, s = CampusColors.of(context);
    final (bg, fg) = switch (data.tone) {
      NoticeTone.information => (c.secondaryContainer, c.onSecondaryContainer),
      NoticeTone.success => (s.success, s.onSuccess),
      NoticeTone.warning => (s.warning, s.onWarning),
      NoticeTone.error => (c.errorContainer, c.onErrorContainer),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CampusGeometry.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CampusSpace.sm,
          vertical: CampusSpace.xs,
        ),
        child: Text(
          data.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
        ),
      ),
    );
  }
}

class ScopeBadge extends StatelessWidget {
  const ScopeBadge({
    required this.label,
    this.icon = Icons.visibility_outlined,
    super.key,
  });
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(child: Icon(icon, size: CampusSpace.md)),
      const SizedBox(width: CampusSpace.xs),
      Flexible(child: Text(label)),
    ],
  );
}

/// Deadline/offer text is formatted by application view mapping, never a timer.
class DeadlineBanner extends StatelessWidget {
  const DeadlineBanner({required this.message, this.action, super.key});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) =>
      InlineNotice(message: message, tone: NoticeTone.warning, action: action);
}
