import 'package:campus/src/core/design_system/components/components.dart';
import 'package:campus/src/core/design_system/foundations/palette.dart';
import 'package:campus/src/core/design_system/theme/campus_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Manrope');
    for (final weight in [400, 500, 600, 700]) {
      loader.addFont(
        rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final brightness in Brightness.values) {
    testWidgets('common controls ${brightness.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: CampusTheme.build(PaletteId.lavender, brightness),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: RepaintBoundary(
              key: const Key('golden'),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeading(title: 'Кампус · Campus'),
                      BusyAction(label: 'Сохранить · Save', onPressed: () {}),
                      const BusyAction(
                        label: 'Сохранение · Saving',
                        onPressed: null,
                        busy: true,
                      ),
                      const BusyAction(
                        label: 'Недоступно · Unavailable',
                        onPressed: null,
                      ),
                      const SizedBox(height: 16),
                      const TextField(
                        decoration: InputDecoration(
                          labelText: 'Описание · Description',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const TextField(
                        decoration: InputDecoration(
                          labelText: 'Название · Title',
                          errorText: 'Проверьте значение · Check value',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const InlineNotice(
                        message: 'Сохранённые данные доступны офлайн. Cached content is available offline.',
                        tone: NoticeTone.warning,
                      ),
                      const SizedBox(height: 16),
                      const CampusAvatar(label: 'Hidden profile'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/controls_${brightness.name}.png'),
      );
    });
  }
}
