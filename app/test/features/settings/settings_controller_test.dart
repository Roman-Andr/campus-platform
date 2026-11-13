import 'package:campus/src/features/settings/application/settings_controller.dart';
import 'package:campus/src/features/settings/data/settings_repository.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

void main() {
  test('changes are applied and persisted', () async {
    final database = createTestDatabase();
    final container = createTestContainer(database);
    final controller = container.read(settingsControllerProvider.notifier);

    expect(
      await container.read(settingsControllerProvider.future),
      const AppSettings(),
    );

    await controller.setLanguage(AppLanguage.russian);
    await controller.setThemeMode(ThemeMode.dark);

    const expected = AppSettings(
      language: AppLanguage.russian,
      themeMode: ThemeMode.dark,
    );
    expect(container.read(settingsControllerProvider).value, expected);
    expect(await DriftSettingsRepository(database).load(), expected);
  });
}
