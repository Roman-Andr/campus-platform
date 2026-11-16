import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import 'preview.dart';
import 'stories.dart';

void main() => runApp(const CampusCatalog());

/// Independent fixture entry point; does not bootstrap the application.
class CampusCatalog extends StatelessWidget {
  const CampusCatalog({super.key});
  @override
  Widget build(BuildContext context) => Widgetbook.material(
    initialRoute: '/?path=controls/actions',
    appBuilder: (context, child) => CatalogPreview(child: child),
    directories: catalogStories,
  );
}
