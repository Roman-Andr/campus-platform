import 'package:material_ui/material_ui.dart';

import '../foundations/tokens.dart';

class SectionHeading extends StatelessWidget {
  const SectionHeading({required this.title, this.action, super.key});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: CampusSpace.sm),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: CampusSpace.md,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

/// Wraps rather than clipping actions at large text scales and with keyboards.
class BottomActions extends StatelessWidget {
  const BottomActions({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
    elevation: CampusGeometry.raised,
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: CampusSpace.page,
        child: Wrap(
          spacing: CampusSpace.sm,
          runSpacing: CampusSpace.sm,
          alignment: WrapAlignment.end,
          children: children,
        ),
      ),
    ),
  );
}

class CampusAvatar extends StatelessWidget {
  const CampusAvatar({required this.label, this.image, super.key});
  final String label;
  final ImageProvider? image;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    image: true,
    child: ExcludeSemantics(
      child: CircleAvatar(
        backgroundImage: image,
        child: image == null ? const Icon(Icons.person_outline) : null,
      ),
    ),
  );
}

/// One modal convention, retaining native dismissal, Back and focus behavior.
Future<T?> showCampusSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(child: builder(context)),
  ),
);

/// Native dialog with the same accessibility policy as other modal feedback.
Future<T?> showCampusDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  animationStyle: CampusMotion.modalStyle(context),
  builder: builder,
);
