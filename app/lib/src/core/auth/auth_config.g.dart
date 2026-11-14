// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(authConfig)
final authConfigProvider = AuthConfigProvider._();

final class AuthConfigProvider
    extends $FunctionalProvider<AuthConfig, AuthConfig, AuthConfig>
    with $Provider<AuthConfig> {
  AuthConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authConfigHash();

  @$internal
  @override
  $ProviderElement<AuthConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthConfig create(Ref ref) {
    return authConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthConfig>(value),
    );
  }
}

String _$authConfigHash() => r'cb2ef2bc1d1b270d2701f83db660010bef9c3faa';
