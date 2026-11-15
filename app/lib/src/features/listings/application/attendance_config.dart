import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'attendance_config.g.dart';

/// Client-side parameters of event attendance (ТЗ, Приложение 4).
///
/// Values come from `--dart-define` at build time; they must match the
/// server's `CAMPUS_EVENT_ATTENDANCE_OPENS_BEFORE`.
class AttendanceConfig {
  AttendanceConfig({required this.opensBefore})
    : assert(
        opensBefore >= Duration.zero,
        'attendance cannot open before the event was created',
      );

  factory AttendanceConfig.fromEnvironment() => AttendanceConfig(
    opensBefore: const Duration(
      minutes: int.fromEnvironment(
        'CAMPUS_EVENT_ATTENDANCE_OPENS_BEFORE_MINUTES',
        defaultValue: 30,
      ),
    ),
  );

  /// How long before the event start the server accepts marks.
  final Duration opensBefore;
}

@Riverpod(keepAlive: true)
AttendanceConfig attendanceConfig(Ref ref) =>
    AttendanceConfig.fromEnvironment();
