// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attendance_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(attendanceConfig)
final attendanceConfigProvider = AttendanceConfigProvider._();

final class AttendanceConfigProvider
    extends
        $FunctionalProvider<
          AttendanceConfig,
          AttendanceConfig,
          AttendanceConfig
        >
    with $Provider<AttendanceConfig> {
  AttendanceConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'attendanceConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$attendanceConfigHash();

  @$internal
  @override
  $ProviderElement<AttendanceConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AttendanceConfig create(Ref ref) {
    return attendanceConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AttendanceConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AttendanceConfig>(value),
    );
  }
}

String _$attendanceConfigHash() => r'7276c4690a86e34c356baaaa62e09b9a23cbce93';
