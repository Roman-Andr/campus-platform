// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_status.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Changes of the device network: `true` when some network is available.

@ProviderFor(networkAvailability)
final networkAvailabilityProvider = NetworkAvailabilityProvider._();

/// Changes of the device network: `true` when some network is available.

final class NetworkAvailabilityProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  /// Changes of the device network: `true` when some network is available.
  NetworkAvailabilityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'networkAvailabilityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$networkAvailabilityHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return networkAvailability(ref);
  }
}

String _$networkAvailabilityHash() =>
    r'5259f0970a574b5bbaf9f23842da7996825229e8';

/// Whether the app is online (ТЗ п. 5.1.5: the offline state is shown).
///
/// Offline when the device has no network or the server could not be
/// reached; online again when the network comes back or a request gets
/// any response.

@ProviderFor(NetworkStatus)
final networkStatusProvider = NetworkStatusProvider._();

/// Whether the app is online (ТЗ п. 5.1.5: the offline state is shown).
///
/// Offline when the device has no network or the server could not be
/// reached; online again when the network comes back or a request gets
/// any response.
final class NetworkStatusProvider
    extends $NotifierProvider<NetworkStatus, bool> {
  /// Whether the app is online (ТЗ п. 5.1.5: the offline state is shown).
  ///
  /// Offline when the device has no network or the server could not be
  /// reached; online again when the network comes back or a request gets
  /// any response.
  NetworkStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'networkStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$networkStatusHash();

  @$internal
  @override
  NetworkStatus create() => NetworkStatus();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$networkStatusHash() => r'fa7005bdb65533f3ac316a1eaa657c8102cdfed2';

/// Whether the app is online (ТЗ п. 5.1.5: the offline state is shown).
///
/// Offline when the device has no network or the server could not be
/// reached; online again when the network comes back or a request gets
/// any response.

abstract class _$NetworkStatus extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
