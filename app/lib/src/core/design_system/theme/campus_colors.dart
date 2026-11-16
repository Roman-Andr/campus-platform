import 'package:material_ui/material_ui.dart';

/// Status colors never change meaning when the decorative palette changes.
@immutable
class CampusColors extends ThemeExtension<CampusColors> {
  const CampusColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
  });

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;

  static CampusColors of(BuildContext context) =>
      Theme.of(context).extension<CampusColors>()!;

  static CampusColors forBrightness(Brightness brightness) =>
      brightness == Brightness.light
      ? const CampusColors(
          success: Color(0xffd6f3df),
          onSuccess: Color(0xff153d27),
          warning: Color(0xffffe5b0),
          onWarning: Color(0xff493200),
        )
      : const CampusColors(
          success: Color(0xff254c35),
          onSuccess: Color(0xffc0edcf),
          warning: Color(0xff554014),
          onWarning: Color(0xffffe1a0),
        );

  @override
  CampusColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
  }) => CampusColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
  );

  @override
  CampusColors lerp(covariant CampusColors? other, double t) => other == null
      ? this
      : CampusColors(
          success: Color.lerp(success, other.success, t)!,
          onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          onWarning: Color.lerp(onWarning, other.onWarning, t)!,
        );
}
