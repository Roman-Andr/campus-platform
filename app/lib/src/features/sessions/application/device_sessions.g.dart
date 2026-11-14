// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_sessions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deviceSessions)
final deviceSessionsProvider = DeviceSessionsProvider._();

final class DeviceSessionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SessionOutput>>,
          List<SessionOutput>,
          FutureOr<List<SessionOutput>>
        >
    with
        $FutureModifier<List<SessionOutput>>,
        $FutureProvider<List<SessionOutput>> {
  DeviceSessionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceSessionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceSessionsHash();

  @$internal
  @override
  $FutureProviderElement<List<SessionOutput>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SessionOutput>> create(Ref ref) {
    return deviceSessions(ref);
  }
}

String _$deviceSessionsHash() => r'7f1db3315920601dfaeacfed631f55e64e54d778';

/// Clear local credentials only after the server confirms revocation.
/// A network failure must leave the user able to retry the operation.

@ProviderFor(endDeviceSessions)
final endDeviceSessionsProvider = EndDeviceSessionsProvider._();

/// Clear local credentials only after the server confirms revocation.
/// A network failure must leave the user able to retry the operation.

final class EndDeviceSessionsProvider
    extends
        $FunctionalProvider<
          Future<void> Function(SessionOutput?),
          Future<void> Function(SessionOutput?),
          Future<void> Function(SessionOutput?)
        >
    with $Provider<Future<void> Function(SessionOutput?)> {
  /// Clear local credentials only after the server confirms revocation.
  /// A network failure must leave the user able to retry the operation.
  EndDeviceSessionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'endDeviceSessionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$endDeviceSessionsHash();

  @$internal
  @override
  $ProviderElement<Future<void> Function(SessionOutput?)> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<void> Function(SessionOutput?) create(Ref ref) {
    return endDeviceSessions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<void> Function(SessionOutput?) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Future<void> Function(SessionOutput?)>(value),
    );
  }
}

String _$endDeviceSessionsHash() => r'e086f789c30f58a464badd5297ea5920bcbe0a0b';
