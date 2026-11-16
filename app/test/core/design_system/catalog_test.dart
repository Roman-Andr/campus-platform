import 'package:campus/src/core/design_system/components/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../catalog/main.dart';

void main() {
  testWidgets('catalog renders offline and changes locale/scale/motion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const CampusCatalog());
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BusyAction), findsNWidgets(4));
    expect(find.text('Сохранить'), findsWidgets);
    await tester.tap(find.text('Locale: ru'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Locale: en').last);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Save'), findsWidgets);
    await tester.tap(find.text('Reduced motion'));
    await tester.pump(const Duration(seconds: 1));
    final context = tester.element(find.byType(BusyAction).first);
    expect(MediaQuery.disableAnimationsOf(context), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
