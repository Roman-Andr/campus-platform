import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/core/design_system/foundations/palette.dart';
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
    expect(await database.select(database.preferences).get(), hasLength(3));
  });

  test(
    'legacy palette and unknown palette preserve other preferences',
    () async {
      await repository.save(
        const AppSettings(
          language: AppLanguage.russian,
          themeMode: ThemeMode.dark,
        ),
      );
      await database
          .into(database.preferences)
          .insertOnConflictUpdate(
            PreferencesCompanion.insert(
              key: 'settings.palette_id',
              value: 'future-palette',
            ),
          );
      final restored = await repository.load();
      expect(restored.paletteId, PaletteId.lavender);
      expect(restored.language, AppLanguage.russian);
      expect(restored.themeMode, ThemeMode.dark);
      await database
          .into(database.preferences)
          .insert(
            PreferencesCompanion.insert(
              key: 'unrelated.setting',
              value: 'retained',
            ),
          );
      await repository.save(restored.copyWith(paletteId: PaletteId.peach));
      expect(
        (await DriftSettingsRepository(database).load()).paletteId,
        PaletteId.peach,
      );
      expect(
        (await database.select(database.preferences).get()).any(
          (r) => r.key == 'unrelated.setting' && r.value == 'retained',
        ),
        isTrue,
      );
    },
  );

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
