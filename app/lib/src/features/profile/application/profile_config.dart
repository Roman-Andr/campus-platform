import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_config.g.dart';

/// Client-side parameters of the profile.
///
/// Values come from `--dart-define` at build time (README, "Профиль").
class ProfileConfig {
  const ProfileConfig({required this.maxCourse});

  factory ProfileConfig.fromEnvironment() => const ProfileConfig(
    maxCourse: int.fromEnvironment(
      'CAMPUS_PROFILE_MAX_COURSE',
      defaultValue: 6,
    ),
  );

  /// The highest course offered; the server's `CAMPUS_PROFILE_MAX_COURSE`.
  final int maxCourse;
}

@Riverpod(keepAlive: true)
ProfileConfig profileConfig(Ref ref) => ProfileConfig.fromEnvironment();
