import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/design_system/foundations/palette.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';

part 'settings_controller.g.dart';

/// Current [AppSettings]; changes are applied immediately and persisted.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> setLanguage(AppLanguage language) =>
      _update((settings) => settings.copyWith(language: language));

  Future<void> setPalette(PaletteId paletteId) =>
      _update((settings) => settings.copyWith(paletteId: paletteId));

  Future<void> setThemeMode(ThemeMode themeMode) =>
      _update((settings) => settings.copyWith(themeMode: themeMode));

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    final updated = change(state.value ?? await future);
    state = AsyncData(updated);
    await ref.read(settingsRepositoryProvider).save(updated);
  }
}
