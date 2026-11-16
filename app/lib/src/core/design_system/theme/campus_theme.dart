import 'package:material_ui/material_ui.dart';

import '../foundations/palette.dart';
import '../foundations/tokens.dart';
import 'campus_colors.dart';

/// Full semantic schemes, with deliberate Soft Grid surface/brand roles.
abstract final class CampusTheme {
  static ThemeData build(PaletteId palette, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tones = switch (palette) {
      PaletteId.lavender => (
        0xff675080,
        0xffd8b9f2,
        0xfffdf8ff,
        0xff17131d,
        0xfff0e8f6,
        0xff29232f,
      ),
      PaletteId.sage => (
        0xff38634b,
        0xffa2d3b1,
        0xfff6fcf6,
        0xff101912,
        0xffe5f0e6,
        0xff202c23,
      ),
      PaletteId.sky => (
        0xff285e85,
        0xffa1ccf0,
        0xfff7faff,
        0xff111820,
        0xffe5edf7,
        0xff232c37,
      ),
      PaletteId.peach => (
        0xff8c4c32,
        0xffffb595,
        0xfffff8f5,
        0xff201410,
        0xfff8e8e0,
        0xff352620,
      ),
    };
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Color(tones.$1),
          brightness: brightness,
        ).copyWith(
          primary: Color(dark ? tones.$2 : tones.$1),
          onPrimary: dark ? const Color(0xff21172b) : Colors.white,
          surface: Color(dark ? tones.$4 : tones.$3),
          surfaceContainer: Color(dark ? tones.$6 : tones.$5),
          surfaceContainerLow: Color(dark ? tones.$6 : tones.$5),
          outline: dark ? const Color(0xffa99fae) : const Color(0xff766b7b),
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CampusGeometry.controlRadius),
    );
    final base = ThemeData(colorScheme: scheme, fontFamily: 'Manrope');
    return base.copyWith(
      extensions: [CampusColors.forBrightness(brightness)],
      scaffoldBackgroundColor: scheme.surface,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(CampusGeometry.target, CampusGeometry.target),
          ),
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(
                    color: scheme.onSurface,
                    width: CampusGeometry.focusWidth,
                  )
                : BorderSide.none,
          ),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size.square(CampusGeometry.target),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CampusGeometry.controlRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CampusGeometry.controlRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CampusGeometry.controlRadius),
          borderSide: BorderSide(
            color: scheme.primary,
            width: CampusGeometry.focusWidth,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CampusGeometry.cardRadius),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CampusGeometry.sheetRadius),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }
}
