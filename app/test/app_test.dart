import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/test_app.dart';

void main() {
  late InMemorySettingsRepository repository;

  setUp(() => repository = InMemorySettingsRepository());

  testWidgets('follows the device language by default', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru', 'RU')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpCampusApp(repository);

    expect(find.text('Кампус'), findsOneWidget);
    expect(find.text('Пока ничего нет'), findsOneWidget);
  });

  testWidgets('falls back to English for an unsupported device language', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpCampusApp(repository);

    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('follows the device theme by default', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpCampusApp(repository);

    expect(_brightness(tester), Brightness.dark);
  });

  testWidgets('switches language and theme from settings', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpCampusApp(repository);
    expect(_brightness(tester), Brightness.light);

    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Язык'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(AppLanguage.english)));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(ThemeMode.dark)));
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.dark);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(_brightness(tester), Brightness.dark);

    expect(
      repository.saved,
      const AppSettings(
        language: AppLanguage.english,
        themeMode: ThemeMode.dark,
      ),
    );
  });

  testWidgets('restores saved settings on start', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    repository.saved = const AppSettings(
      language: AppLanguage.english,
      themeMode: ThemeMode.dark,
    );

    await tester.pumpCampusApp(repository);

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(_brightness(tester), Brightness.dark);
  });
}

/// Brightness of the theme applied to the visible screen.
Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).last)).brightness;
