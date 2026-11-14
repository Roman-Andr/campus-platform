// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'realtime_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Centrifugo client of this app installation.
///
/// The SDK owns reconnects with exponential backoff and refreshes both the
/// connection and the subscription tokens through the API. Tests replace
/// this provider with a fake `Client`.

@ProviderFor(realtimeClient)
final realtimeClientProvider = RealtimeClientProvider._();

/// The Centrifugo client of this app installation.
///
/// The SDK owns reconnects with exponential backoff and refreshes both the
/// connection and the subscription tokens through the API. Tests replace
/// this provider with a fake `Client`.

final class RealtimeClientProvider
    extends $FunctionalProvider<Client, Client, Client>
    with $Provider<Client> {
  /// The Centrifugo client of this app installation.
  ///
  /// The SDK owns reconnects with exponential backoff and refreshes both the
  /// connection and the subscription tokens through the API. Tests replace
  /// this provider with a fake `Client`.
  RealtimeClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'realtimeClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$realtimeClientHash();

  @$internal
  @override
  $ProviderElement<Client> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Client create(Ref ref) {
    return realtimeClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Client value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Client>(value),
    );
  }
}

String _$realtimeClientHash() => r'625eed9ef8461460b308f07debd5b65229de1fde';

/// Lifecycle of realtime subscriptions of the signed-in session.
///
/// The client connects lazily with the first subscription and keeps one
/// Centrifugo subscription per channel no matter how many listeners use it.
/// Sign-out or a revoked session disconnects, drops every subscription and
/// forgets the tokens. The app disconnects in the background and reloads the
/// state through the API when it returns, so old data is not shown as
/// current.

@ProviderFor(RealtimeService)
final realtimeServiceProvider = RealtimeServiceProvider._();

/// Lifecycle of realtime subscriptions of the signed-in session.
///
/// The client connects lazily with the first subscription and keeps one
/// Centrifugo subscription per channel no matter how many listeners use it.
/// Sign-out or a revoked session disconnects, drops every subscription and
/// forgets the tokens. The app disconnects in the background and reloads the
/// state through the API when it returns, so old data is not shown as
/// current.
final class RealtimeServiceProvider
    extends $NotifierProvider<RealtimeService, RealtimeStatus> {
  /// Lifecycle of realtime subscriptions of the signed-in session.
  ///
  /// The client connects lazily with the first subscription and keeps one
  /// Centrifugo subscription per channel no matter how many listeners use it.
  /// Sign-out or a revoked session disconnects, drops every subscription and
  /// forgets the tokens. The app disconnects in the background and reloads the
  /// state through the API when it returns, so old data is not shown as
  /// current.
  RealtimeServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'realtimeServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$realtimeServiceHash();

  @$internal
  @override
  RealtimeService create() => RealtimeService();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RealtimeStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RealtimeStatus>(value),
    );
  }
}

String _$realtimeServiceHash() => r'78a0470b15c2d3cf2de8c4f70a5b19ee4aa153f1';

/// Lifecycle of realtime subscriptions of the signed-in session.
///
/// The client connects lazily with the first subscription and keeps one
/// Centrifugo subscription per channel no matter how many listeners use it.
/// Sign-out or a revoked session disconnects, drops every subscription and
/// forgets the tokens. The app disconnects in the background and reloads the
/// state through the API when it returns, so old data is not shown as
/// current.

abstract class _$RealtimeService extends $Notifier<RealtimeStatus> {
  RealtimeStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RealtimeStatus, RealtimeStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RealtimeStatus, RealtimeStatus>,
              RealtimeStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
