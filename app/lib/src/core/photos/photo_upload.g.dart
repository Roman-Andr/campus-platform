// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_upload.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(photoConfig)
final photoConfigProvider = PhotoConfigProvider._();

final class PhotoConfigProvider
    extends $FunctionalProvider<PhotoConfig, PhotoConfig, PhotoConfig>
    with $Provider<PhotoConfig> {
  PhotoConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoConfigHash();

  @$internal
  @override
  $ProviderElement<PhotoConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoConfig create(Ref ref) {
    return photoConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoConfig>(value),
    );
  }
}

String _$photoConfigHash() => r'2781ec11eeadf4bb00c9857c1a65da7c675969a4';

@ProviderFor(photoPicker)
final photoPickerProvider = PhotoPickerProvider._();

final class PhotoPickerProvider
    extends $FunctionalProvider<PhotoPicker, PhotoPicker, PhotoPicker>
    with $Provider<PhotoPicker> {
  PhotoPickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoPickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoPickerHash();

  @$internal
  @override
  $ProviderElement<PhotoPicker> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoPicker create(Ref ref) {
    return photoPicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoPicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoPicker>(value),
    );
  }
}

String _$photoPickerHash() => r'b71d30bec047cf99e031ecba15124a094c433ac0';

/// Client for the signed storage form: no API base URL and no credentials,
/// the form fields carry the authorization.

@ProviderFor(storageDio)
final storageDioProvider = StorageDioProvider._();

/// Client for the signed storage form: no API base URL and no credentials,
/// the form fields carry the authorization.

final class StorageDioProvider extends $FunctionalProvider<Dio, Dio, Dio>
    with $Provider<Dio> {
  /// Client for the signed storage form: no API base URL and no credentials,
  /// the form fields carry the authorization.
  StorageDioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storageDioProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageDioHash();

  @$internal
  @override
  $ProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Dio create(Ref ref) {
    return storageDio(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Dio value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Dio>(value),
    );
  }
}

String _$storageDioHash() => r'adcacb17badfc4432cfb9e09e5176d290ae393af';

@ProviderFor(photoUploader)
final photoUploaderProvider = PhotoUploaderProvider._();

final class PhotoUploaderProvider
    extends $FunctionalProvider<PhotoUploader, PhotoUploader, PhotoUploader>
    with $Provider<PhotoUploader> {
  PhotoUploaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoUploaderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoUploaderHash();

  @$internal
  @override
  $ProviderElement<PhotoUploader> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoUploader create(Ref ref) {
    return photoUploader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoUploader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoUploader>(value),
    );
  }
}

String _$photoUploaderHash() => r'2bcb14de0922aaf7a2f22a968ad9372fbbb8faed';
