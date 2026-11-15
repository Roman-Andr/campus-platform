// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'privacy_api.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(privacyApi)
final privacyApiProvider = PrivacyApiProvider._();

final class PrivacyApiProvider
    extends $FunctionalProvider<PrivacyApi, PrivacyApi, PrivacyApi>
    with $Provider<PrivacyApi> {
  PrivacyApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'privacyApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$privacyApiHash();

  @$internal
  @override
  $ProviderElement<PrivacyApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PrivacyApi create(Ref ref) {
    return privacyApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PrivacyApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PrivacyApi>(value),
    );
  }
}

String _$privacyApiHash() => r'ca914833ee1bd025c5a02340cf0faac35506d717';
