// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'my_profile.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The signed-in user's account and profile, as the server keeps it;
/// `null` when nobody is signed in.
///
/// Loaded from the server after every sign-in and app start, so a profile
/// filled in on another device is the same here.

@ProviderFor(MyProfile)
final myProfileProvider = MyProfileProvider._();

/// The signed-in user's account and profile, as the server keeps it;
/// `null` when nobody is signed in.
///
/// Loaded from the server after every sign-in and app start, so a profile
/// filled in on another device is the same here.
final class MyProfileProvider
    extends $AsyncNotifierProvider<MyProfile, UserOutput?> {
  /// The signed-in user's account and profile, as the server keeps it;
  /// `null` when nobody is signed in.
  ///
  /// Loaded from the server after every sign-in and app start, so a profile
  /// filled in on another device is the same here.
  MyProfileProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myProfileProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myProfileHash();

  @$internal
  @override
  MyProfile create() => MyProfile();
}

String _$myProfileHash() => r'99fccae11dfa86aa1603cff168d9adcddedd6f76';

/// The signed-in user's account and profile, as the server keeps it;
/// `null` when nobody is signed in.
///
/// Loaded from the server after every sign-in and app start, so a profile
/// filled in on another device is the same here.

abstract class _$MyProfile extends $AsyncNotifier<UserOutput?> {
  FutureOr<UserOutput?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<UserOutput?>, UserOutput?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<UserOutput?>, UserOutput?>,
              AsyncValue<UserOutput?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Campus cities, by name in the interface language.

@ProviderFor(cities)
final citiesProvider = CitiesProvider._();

/// Campus cities, by name in the interface language.

final class CitiesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CityOut>>,
          List<CityOut>,
          FutureOr<List<CityOut>>
        >
    with $FutureModifier<List<CityOut>>, $FutureProvider<List<CityOut>> {
  /// Campus cities, by name in the interface language.
  CitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'citiesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$citiesHash();

  @$internal
  @override
  $FutureProviderElement<List<CityOut>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CityOut>> create(Ref ref) {
    return cities(ref);
  }
}

String _$citiesHash() => r'dbfac84a037f16b42b52fa2defabd6855de74de4';

/// Dormitories of the city [cityId], by name.

@ProviderFor(dormitories)
final dormitoriesProvider = DormitoriesFamily._();

/// Dormitories of the city [cityId], by name.

final class DormitoriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CityPlaceOut>>,
          List<CityPlaceOut>,
          FutureOr<List<CityPlaceOut>>
        >
    with
        $FutureModifier<List<CityPlaceOut>>,
        $FutureProvider<List<CityPlaceOut>> {
  /// Dormitories of the city [cityId], by name.
  DormitoriesProvider._({
    required DormitoriesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'dormitoriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dormitoriesHash();

  @override
  String toString() {
    return r'dormitoriesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<CityPlaceOut>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CityPlaceOut>> create(Ref ref) {
    final argument = this.argument as String;
    return dormitories(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DormitoriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dormitoriesHash() => r'dc1b509b371fa3ca5c96e233c8d5e7d6d557f8c9';

/// Dormitories of the city [cityId], by name.

final class DormitoriesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<CityPlaceOut>>, String> {
  DormitoriesFamily._()
    : super(
        retry: null,
        name: r'dormitoriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Dormitories of the city [cityId], by name.

  DormitoriesProvider call(String cityId) =>
      DormitoriesProvider._(argument: cityId, from: this);

  @override
  String toString() => r'dormitoriesProvider';
}

/// Faculties of the city [cityId], by name.

@ProviderFor(faculties)
final facultiesProvider = FacultiesFamily._();

/// Faculties of the city [cityId], by name.

final class FacultiesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CityPlaceOut>>,
          List<CityPlaceOut>,
          FutureOr<List<CityPlaceOut>>
        >
    with
        $FutureModifier<List<CityPlaceOut>>,
        $FutureProvider<List<CityPlaceOut>> {
  /// Faculties of the city [cityId], by name.
  FacultiesProvider._({
    required FacultiesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'facultiesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$facultiesHash();

  @override
  String toString() {
    return r'facultiesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<CityPlaceOut>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CityPlaceOut>> create(Ref ref) {
    final argument = this.argument as String;
    return faculties(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FacultiesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$facultiesHash() => r'f65e475283b7a30f93cc6df71c3e93608bb89565';

/// Faculties of the city [cityId], by name.

final class FacultiesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<CityPlaceOut>>, String> {
  FacultiesFamily._()
    : super(
        retry: null,
        name: r'facultiesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Faculties of the city [cityId], by name.

  FacultiesProvider call(String cityId) =>
      FacultiesProvider._(argument: cityId, from: this);

  @override
  String toString() => r'facultiesProvider';
}
