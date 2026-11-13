import 'package:material_ui/material_ui.dart';

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
  });

  final AppLanguage language;
  final ThemeMode themeMode;

  AppSettings copyWith({AppLanguage? language, ThemeMode? themeMode}) =>
      AppSettings(
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(language, themeMode);
}
