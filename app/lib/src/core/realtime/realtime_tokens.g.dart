// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'realtime_tokens.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Connection and subscription tokens of the current device session.
///
/// Centrifugo asks for a new token when the old one expires or the server
/// invalidates the connection. Both calls go through the shared API client,
/// so the access token, `Idempotency-Key` and retry of a dropped request are
/// the same as for every other request: a retry reuses its key, and the
/// server returns the stored token instead of issuing a second one.

@ProviderFor(realtimeTokens)
final realtimeTokensProvider = RealtimeTokensProvider._();

/// Connection and subscription tokens of the current device session.
///
/// Centrifugo asks for a new token when the old one expires or the server
/// invalidates the connection. Both calls go through the shared API client,
/// so the access token, `Idempotency-Key` and retry of a dropped request are
/// the same as for every other request: a retry reuses its key, and the
/// server returns the stored token instead of issuing a second one.

final class RealtimeTokensProvider
    extends $FunctionalProvider<RealtimeTokens, RealtimeTokens, RealtimeTokens>
    with $Provider<RealtimeTokens> {
  /// Connection and subscription tokens of the current device session.
  ///
  /// Centrifugo asks for a new token when the old one expires or the server
  /// invalidates the connection. Both calls go through the shared API client,
  /// so the access token, `Idempotency-Key` and retry of a dropped request are
  /// the same as for every other request: a retry reuses its key, and the
  /// server returns the stored token instead of issuing a second one.
  RealtimeTokensProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'realtimeTokensProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$realtimeTokensHash();

  @$internal
  @override
  $ProviderElement<RealtimeTokens> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RealtimeTokens create(Ref ref) {
    return realtimeTokens(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RealtimeTokens value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RealtimeTokens>(value),
    );
  }
}

String _$realtimeTokensHash() => r'6d04da5fc51c822ae8cfaa99d45bf6b34c4a0744';
