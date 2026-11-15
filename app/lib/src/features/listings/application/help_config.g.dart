// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'help_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(helpConfig)
final helpConfigProvider = HelpConfigProvider._();

final class HelpConfigProvider
    extends $FunctionalProvider<HelpConfig, HelpConfig, HelpConfig>
    with $Provider<HelpConfig> {
  HelpConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'helpConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$helpConfigHash();

  @$internal
  @override
  $ProviderElement<HelpConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HelpConfig create(Ref ref) {
    return helpConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HelpConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HelpConfig>(value),
    );
  }
}

String _$helpConfigHash() => r'f8972ddeb4d90f4316b79a2f515f4fc7cf5cd42e';
