import 'package:material_ui/material_ui.dart';

import '../design_system/foundations/palette.dart';
import '../design_system/theme/campus_theme.dart';

/// Compatibility entry point for existing screens and tests.
abstract final class AppTheme {
  static ThemeData get light =>
      forPalette(PaletteId.lavender, Brightness.light);
  static ThemeData get dark => forPalette(PaletteId.lavender, Brightness.dark);
  static ThemeData forPalette(PaletteId palette, Brightness brightness) =>
      CampusTheme.build(palette, brightness);
}
