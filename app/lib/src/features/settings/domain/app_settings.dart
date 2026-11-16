import 'package:material_ui/material_ui.dart';

import '../../../core/design_system/foundations/palette.dart';

/// Interface language chosen by the user.
enum AppLanguage {
  system(null),
  russian(Locale('ru')),
  english(Locale('en'));

  const AppLanguage(this.locale);

  /// Locale forced on the app, or `null` to follow the device language.
  final Locale? locale;
}

/// User-adjustable appearance settings of this device.
@immutable
class AppSettings {
  const AppSettings({
    this.language = AppLanguage.system,
    this.themeMode = ThemeMode.system,
    this.paletteId = PaletteId.lavender,
  });

  final AppLanguage language;
  final ThemeMode themeMode;
  final PaletteId paletteId;

  AppSettings copyWith({
    AppLanguage? language,
    ThemeMode? themeMode,
    PaletteId? paletteId,
  }) => AppSettings(
    language: language ?? this.language,
    themeMode: themeMode ?? this.themeMode,
    paletteId: paletteId ?? this.paletteId,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.themeMode == themeMode &&
      other.paletteId == paletteId;

  @override
  int get hashCode => Object.hash(language, themeMode, paletteId);
}
