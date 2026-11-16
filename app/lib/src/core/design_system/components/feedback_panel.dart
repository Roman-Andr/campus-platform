import 'package:material_ui/material_ui.dart';

import '../foundations/tokens.dart';
import '../theme/campus_colors.dart';

enum NoticeTone { information, success, warning, error }

/// Retains surrounding content during offline/refresh/conflict feedback.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    required this.message,
    this.tone = NoticeTone.information,
    this.action,
    super.key,
  });
  final String message;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = CampusColors.of(context);
    final (background, foreground, icon) = switch (tone) {
      NoticeTone.information => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        Icons.info_outline,
      ),
      NoticeTone.success => (
        status.success,
        status.onSuccess,
        Icons.check_circle_outline,
      ),
      NoticeTone.warning => (
        status.warning,
        status.onWarning,
        Icons.warning_amber,
      ),
      NoticeTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        Icons.error_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(CampusGeometry.controlRadius),
        child: Padding(
          padding: CampusSpace.page,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, color: foreground)),
              const SizedBox(width: CampusSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message, style: TextStyle(color: foreground)),
                    ?action,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Initial empty/failure/loading presentation. Labels are localized by caller.
class StatePanel extends StatelessWidget {
  const StatePanel({
    required this.title,
    required this.description,
    required this.icon,
    this.action,
    super.key,
  });
  final String title;
  final String description;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: CampusSpace.section,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, size: CampusGeometry.target)),
        const SizedBox(height: CampusSpace.md),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: CampusSpace.sm),
        Text(description, textAlign: TextAlign.center),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: CampusSpace.md),
            child: action!,
          ),
      ],
    ),
  );
}
