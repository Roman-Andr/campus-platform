// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_info.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Loaded by `main` before the app starts.

@ProviderFor(clientInfo)
final clientInfoProvider = ClientInfoProvider._();

/// Loaded by `main` before the app starts.

final class ClientInfoProvider
    extends $FunctionalProvider<ClientInfo, ClientInfo, ClientInfo>
    with $Provider<ClientInfo> {
  /// Loaded by `main` before the app starts.
  ClientInfoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clientInfoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clientInfoHash();

  @$internal
  @override
  $ProviderElement<ClientInfo> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ClientInfo create(Ref ref) {
    return clientInfo(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClientInfo value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClientInfo>(value),
    );
  }
}

String _$clientInfoHash() => r'dde156ba2def50b35956739b2a80650e7daa36c3';
