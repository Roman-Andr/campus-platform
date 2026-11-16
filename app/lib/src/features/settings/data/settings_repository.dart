import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/design_system/foundations/palette.dart';
import '../domain/app_settings.dart';

part 'settings_repository.g.dart';

/// Storage of [AppSettings] on this device.
abstract interface class SettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

/// Persists [AppSettings] in the local database.
class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  static const _languageKey = 'settings.language';
  static const _paletteKey = 'settings.palette_id';
  static const _themeModeKey = 'settings.theme_mode';

  @override
  Future<AppSettings> load() async {
    final rows = await _db.select(_db.preferences).get();
    final values = {for (final row in rows) row.key: row.value};
    return AppSettings(
      paletteId: PaletteId.parse(values[_paletteKey]),
      language:
          _byName(AppLanguage.values, values[_languageKey]) ??
          AppLanguage.system,
      themeMode:
          _byName(ThemeMode.values, values[_themeModeKey]) ?? ThemeMode.system,
    );
  }

  @override
  Future<void> save(AppSettings settings) => _db.batch((batch) {
    batch.insertAllOnConflictUpdate(_db.preferences, [
      PreferencesCompanion.insert(
        key: _paletteKey,
        value: settings.paletteId.name,
      ),
      PreferencesCompanion.insert(
        key: _languageKey,
        value: settings.language.name,
      ),
      PreferencesCompanion.insert(
        key: _themeModeKey,
        value: settings.themeMode.name,
      ),
    ]);
  });

  /// Unknown values (e.g. written by a newer app version) fall back to the
  /// default instead of failing the app start.
  static T? _byName<T extends Enum>(List<T> values, String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    DriftSettingsRepository(ref.watch(appDatabaseProvider));
