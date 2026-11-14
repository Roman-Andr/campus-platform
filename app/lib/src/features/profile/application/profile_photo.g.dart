// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_photo.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The signed-in user's profile photo with fresh signed links; `null`
/// without a photo or a signed-in user (ТЗ п. 5.1.1, модуль 2, п. 1).

@ProviderFor(MyPhoto)
final myPhotoProvider = MyPhotoProvider._();

/// The signed-in user's profile photo with fresh signed links; `null`
/// without a photo or a signed-in user (ТЗ п. 5.1.1, модуль 2, п. 1).
final class MyPhotoProvider
    extends $AsyncNotifierProvider<MyPhoto, ProfilePhoto?> {
  /// The signed-in user's profile photo with fresh signed links; `null`
  /// without a photo or a signed-in user (ТЗ п. 5.1.1, модуль 2, п. 1).
  MyPhotoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myPhotoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myPhotoHash();

  @$internal
  @override
  MyPhoto create() => MyPhoto();
}

String _$myPhotoHash() => r'd097226d7766d63a75bb02764d28e9aa3e7ad553';

/// The signed-in user's profile photo with fresh signed links; `null`
/// without a photo or a signed-in user (ТЗ п. 5.1.1, модуль 2, п. 1).

abstract class _$MyPhoto extends $AsyncNotifier<ProfilePhoto?> {
  FutureOr<ProfilePhoto?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ProfilePhoto?>, ProfilePhoto?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ProfilePhoto?>, ProfilePhoto?>,
              AsyncValue<ProfilePhoto?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
