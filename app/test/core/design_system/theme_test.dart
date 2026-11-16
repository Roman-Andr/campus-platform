import 'package:campus/src/core/design_system/foundations/palette.dart';
import 'package:campus/src/core/design_system/theme/campus_colors.dart';
import 'package:campus/src/core/design_system/theme/campus_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  for (final palette in PaletteId.values) {
    for (final brightness in Brightness.values) {
      test('$palette $brightness semantic contrast', () {
        final theme = CampusTheme.build(palette, brightness);
        final c = theme.colorScheme;
        final status = theme.extension<CampusColors>()!;
        for (final pair in [
          (c.primary, c.onPrimary),
          (c.primaryContainer, c.onPrimaryContainer),
          (c.secondary, c.onSecondary),
          (c.secondaryContainer, c.onSecondaryContainer),
          (c.tertiary, c.onTertiary),
          (c.tertiaryContainer, c.onTertiaryContainer),
          (c.error, c.onError),
          (c.errorContainer, c.onErrorContainer),
          (c.surface, c.onSurface),
          (c.surfaceContainerLow, c.onSurfaceVariant),
          (status.success, status.onSuccess),
          (status.warning, status.onWarning),
        ]) {
          expect(
            contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: '$pair',
          );
        }
        expect(
          contrast(c.primary, c.surfaceContainerLow),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrast(c.outline, c.surfaceContainerLow),
          greaterThanOrEqualTo(3),
        );
        expect(theme.textTheme.bodyMedium!.fontFamily, 'Manrope');
      });
    }
  }
  test('extension interpolates and preserves endpoints', () {
    final a = CampusColors.forBrightness(Brightness.light);
    final b = CampusColors.forBrightness(Brightness.dark);
    expect(a.lerp(b, 0).success, a.success);
    expect(a.lerp(b, 1).warning, b.warning);
    expect(a.lerp(b, .5).onWarning, Color.lerp(a.onWarning, b.onWarning, .5));
    expect(a.copyWith().success, a.success);
  });
}
