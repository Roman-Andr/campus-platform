// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'realtime_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(realtimeConfig)
final realtimeConfigProvider = RealtimeConfigProvider._();

final class RealtimeConfigProvider
    extends $FunctionalProvider<RealtimeConfig, RealtimeConfig, RealtimeConfig>
    with $Provider<RealtimeConfig> {
  RealtimeConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'realtimeConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$realtimeConfigHash();

  @$internal
  @override
  $ProviderElement<RealtimeConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RealtimeConfig create(Ref ref) {
    return realtimeConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RealtimeConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RealtimeConfig>(value),
    );
  }
}

String _$realtimeConfigHash() => r'5d6c5dec60c6f515681fd0ef6cc7bbc8ce35f7fd';
