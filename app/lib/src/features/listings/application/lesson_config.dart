import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'lesson_config.g.dart';

/// Client-side limits of a skill lesson (ТЗ, Приложение 4).
///
/// Values come from `--dart-define` at build time; they must match the
/// server's `CAMPUS_LESSON_OPTIONS_MIN` and `CAMPUS_LESSON_OPTIONS_MAX`.
class LessonConfig {
  const LessonConfig({required this.minOptions, required this.maxOptions})
    : assert(minOptions > 0, 'a lesson needs at least one time option'),
      assert(minOptions <= maxOptions, 'the minimum cannot exceed the maximum');

  factory LessonConfig.fromEnvironment() => const LessonConfig(
    minOptions: int.fromEnvironment(
      'CAMPUS_LESSON_OPTIONS_MIN',
      defaultValue: 2,
    ),
    maxOptions: int.fromEnvironment(
      'CAMPUS_LESSON_OPTIONS_MAX',
      defaultValue: 3,
    ),
  );

  /// Fewest time options a lesson request may offer.
  final int minOptions;

  /// Most time options a lesson request may offer.
  final int maxOptions;
}

@Riverpod(keepAlive: true)
LessonConfig lessonConfig(Ref ref) => LessonConfig.fromEnvironment();
