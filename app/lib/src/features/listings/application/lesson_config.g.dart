// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lesson_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lessonConfig)
final lessonConfigProvider = LessonConfigProvider._();

final class LessonConfigProvider
    extends $FunctionalProvider<LessonConfig, LessonConfig, LessonConfig>
    with $Provider<LessonConfig> {
  LessonConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lessonConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lessonConfigHash();

  @$internal
  @override
  $ProviderElement<LessonConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LessonConfig create(Ref ref) {
    return lessonConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LessonConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LessonConfig>(value),
    );
  }
}

String _$lessonConfigHash() => r'b014a353949b0b6109be494476afeea3f91ed0d1';
