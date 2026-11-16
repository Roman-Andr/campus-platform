import 'package:campus/src/core/design_system/foundations/tokens.dart';
import 'package:material_ui/material_ui.dart';

String fixture(BuildContext context, String en, String ru) =>
    Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

class StoryPage extends StatelessWidget {
  const StoryPage({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    padding: CampusSpace.page,
    children: [
      for (final child in children)
        Padding(
          padding: const EdgeInsets.only(bottom: CampusSpace.md),
          child: child,
        ),
    ],
  );
}
