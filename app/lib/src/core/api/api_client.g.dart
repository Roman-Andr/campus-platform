// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_client.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Transport of requests; tests override it to answer without a server.

@ProviderFor(apiHttpAdapter)
final apiHttpAdapterProvider = ApiHttpAdapterProvider._();

/// Transport of requests; tests override it to answer without a server.

final class ApiHttpAdapterProvider
    extends
        $FunctionalProvider<
          HttpClientAdapter?,
          HttpClientAdapter?,
          HttpClientAdapter?
        >
    with $Provider<HttpClientAdapter?> {
  /// Transport of requests; tests override it to answer without a server.
  ApiHttpAdapterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'apiHttpAdapterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$apiHttpAdapterHash();

  @$internal
  @override
  $ProviderElement<HttpClientAdapter?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  HttpClientAdapter? create(Ref ref) {
    return apiHttpAdapter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HttpClientAdapter? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HttpClientAdapter?>(value),
    );
  }
}

String _$apiHttpAdapterHash() => r'4bf044e67fd70d38d11495d5f3c71c550891e85a';

@ProviderFor(apiDio)
final apiDioProvider = ApiDioProvider._();

final class ApiDioProvider extends $FunctionalProvider<Dio, Dio, Dio>
    with $Provider<Dio> {
  ApiDioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'apiDioProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$apiDioHash();

  @$internal
  @override
  $ProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Dio create(Ref ref) {
    return apiDio(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Dio value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Dio>(value),
    );
  }
}

String _$apiDioHash() => r'7bbaf000fdb8b35dab26ab183393a266ae105351';

/// Generated client of the Campus API.

@ProviderFor(campusApi)
final campusApiProvider = CampusApiProvider._();

/// Generated client of the Campus API.

final class CampusApiProvider
    extends $FunctionalProvider<CampusApi, CampusApi, CampusApi>
    with $Provider<CampusApi> {
  /// Generated client of the Campus API.
  CampusApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'campusApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$campusApiHash();

  @$internal
  @override
  $ProviderElement<CampusApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CampusApi create(Ref ref) {
    return campusApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CampusApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CampusApi>(value),
    );
  }
}

String _$campusApiHash() => r'c0f9e039dad24b8e956713965d1b0bfae4270425';
