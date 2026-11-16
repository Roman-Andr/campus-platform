import 'package:material_ui/material_ui.dart';

import '../components/components.dart';
import '../foundations/tokens.dart';

/// Reusable section for description, visibility, audience or feature fields.
class FormSection extends StatelessWidget {
  const FormSection({
    required this.title,
    required this.child,
    this.description,
    super.key,
  });
  final String title;
  final String? description;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: CampusSpace.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(title: title),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(bottom: CampusSpace.sm),
              child: Text(description!),
            ),
          child,
        ],
      ),
    ),
  );
}

/// Keeps editor composition independent of feature validation and submission.
class EditorScaffold extends StatelessWidget {
  const EditorScaffold({
    required this.title,
    required this.sections,
    required this.actions,
    super.key,
  });
  final String title;
  final List<Widget> sections;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: CampusGeometry.readingWidth,
        ),
        child: ListView(
          padding: CampusSpace.page,
          children: [
            for (final section in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: CampusSpace.md),
                child: section,
              ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: BottomActions(children: actions),
  );
}

class TimelineEntry extends StatelessWidget {
  const TimelineEntry({
    required this.title,
    required this.detail,
    required this.icon,
    this.trailing,
    super.key,
  });
  final String title;
  final String detail;
  final IconData icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: CampusSpace.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon)),
        const SizedBox(width: CampusSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(detail),
              ?trailing,
            ],
          ),
        ),
      ],
    ),
  );
}
