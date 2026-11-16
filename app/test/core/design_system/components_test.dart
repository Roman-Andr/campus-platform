import 'package:campus/src/core/design_system/components/components.dart';
import 'package:campus/src/core/design_system/foundations/palette.dart';
import 'package:campus/src/core/design_system/theme/campus_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget host(Widget child, {bool reduced = true}) => MaterialApp(
  theme: CampusTheme.build(PaletteId.lavender, Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('busy action blocks repeat activation and keeps a label', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(BusyAction(label: 'Save', busy: true, onPressed: () => calls++)),
    );
    await tester.tap(find.byType(FilledButton));
    expect(calls, 0);
    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(
      host(BusyAction(label: 'Save', onPressed: () => calls++)),
    );
    await tester.tap(find.byType(FilledButton));
    expect(calls, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final semantics = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
  testWidgets(
    'long notices and action bars wrap at narrow width and large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ListView(
              children: [
                InlineNotice(
                  message: 'A long retained-content error with an explicit retry action',
                  tone: NoticeTone.error,
                  action: TextButton(
                    onPressed: () {},
                    child: const Text('Retry'),
                  ),
                ),
                BottomActions(
                  children: [
                    BusyAction(label: 'Save all changes', onPressed: () {}),
                    TextButton(onPressed: () {}, child: const Text('Cancel')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('sheet closes with Back', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCampusSheet<void>(
              context: context,
              builder: (_) => const Text('Sheet content'),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet content'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sheet content'), findsNothing);
  });
}
