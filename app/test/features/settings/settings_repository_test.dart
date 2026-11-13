import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/settings/data/settings_repository.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase database;
  late DriftSettingsRepository repository;

  setUp(() {
    database = createTestDatabase();
    repository = DriftSettingsRepository(database);
  });

  test('empty database yields system defaults', () async {
    expect(await repository.load(), const AppSettings());
  });

  test('saved settings are loaded back', () async {
    const settings = AppSettings(
      language: AppLanguage.english,
      themeMode: ThemeMode.dark,
    );

    await repository.save(settings);
    await repository.save(settings.copyWith(themeMode: ThemeMode.light));

    expect(
      await repository.load(),
      const AppSettings(
        language: AppLanguage.english,
        themeMode: ThemeMode.light,
      ),
    );
    expect(await database.select(database.preferences).get(), hasLength(2));
  });

  test('unknown stored values fall back to defaults', () async {
    await database
        .into(database.preferences)
        .insert(
          PreferencesCompanion.insert(
            key: 'settings.language',
            value: 'klingon',
          ),
        );

    expect((await repository.load()).language, AppLanguage.system);
  });
}
