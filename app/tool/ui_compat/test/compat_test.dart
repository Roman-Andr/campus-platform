import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:animations/animations.dart';

void main() {
  testWidgets('Widgetbook renders Material UI and animations', (tester) async {
    await tester.pumpWidget(
      Widgetbook.material(
        initialRoute: '/?path=spike/button',
        appBuilder: (context, child) => MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff675080),
            ),
          ),
          home: child,
        ),
        directories: [
          WidgetbookComponent(
            name: 'Spike',
            useCases: [
              WidgetbookUseCase(
                name: 'button',
                builder: (_) => const Center(
                  child: FadeScaleTransition(
                    animation: AlwaysStoppedAnimation(1),
                    child: FilledButton(
                      onPressed: null,
                      child: Text('Offline fixture'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline fixture'), findsOneWidget);
    final context = tester.element(find.byType(FilledButton));
    expect(
      Theme.of(context).colorScheme.primary,
      ColorScheme.fromSeed(seedColor: const Color(0xff675080)).primary,
    );
    expect(tester.takeException(), isNull);
  });
}
