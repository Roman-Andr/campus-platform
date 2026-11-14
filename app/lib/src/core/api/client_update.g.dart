// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_update.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Set once a request is answered with `client_update_required`; the app
/// then shows only the update screen.

@ProviderFor(ClientUpdateRequired)
final clientUpdateRequiredProvider = ClientUpdateRequiredProvider._();

/// Set once a request is answered with `client_update_required`; the app
/// then shows only the update screen.
final class ClientUpdateRequiredProvider
    extends $NotifierProvider<ClientUpdateRequired, ClientUpdate?> {
  /// Set once a request is answered with `client_update_required`; the app
  /// then shows only the update screen.
  ClientUpdateRequiredProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clientUpdateRequiredProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clientUpdateRequiredHash();

  @$internal
  @override
  ClientUpdateRequired create() => ClientUpdateRequired();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClientUpdate? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClientUpdate?>(value),
    );
  }
}

String _$clientUpdateRequiredHash() =>
    r'd09418ca62a84e1b17f5ce78bf406988b17f7c72';

/// Set once a request is answered with `client_update_required`; the app
/// then shows only the update screen.

abstract class _$ClientUpdateRequired extends $Notifier<ClientUpdate?> {
  ClientUpdate? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ClientUpdate?, ClientUpdate?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClientUpdate?, ClientUpdate?>,
              ClientUpdate?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
