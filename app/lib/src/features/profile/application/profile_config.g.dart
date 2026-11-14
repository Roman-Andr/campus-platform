// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(profileConfig)
final profileConfigProvider = ProfileConfigProvider._();

final class ProfileConfigProvider
    extends $FunctionalProvider<ProfileConfig, ProfileConfig, ProfileConfig>
    with $Provider<ProfileConfig> {
  ProfileConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileConfigHash();

  @$internal
  @override
  $ProviderElement<ProfileConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProfileConfig create(Ref ref) {
    return profileConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProfileConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProfileConfig>(value),
    );
  }
}

String _$profileConfigHash() => r'b3bf43124a9be734837b0703314e454013ef6025';
