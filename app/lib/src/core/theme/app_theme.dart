import 'package:material_ui/material_ui.dart';

/// Material 3 light and dark themes generated from the brand seed color.
abstract final class AppTheme {
  static const _seedColor = Color(0xFF1E5AA8);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    ),
  );
}
