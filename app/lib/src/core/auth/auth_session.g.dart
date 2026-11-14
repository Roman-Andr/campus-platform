// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_session.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(secureStorage)
final secureStorageProvider = SecureStorageProvider._();

final class SecureStorageProvider
    extends
        $FunctionalProvider<
          FlutterSecureStorage,
          FlutterSecureStorage,
          FlutterSecureStorage
        >
    with $Provider<FlutterSecureStorage> {
  SecureStorageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'secureStorageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$secureStorageHash();

  @$internal
  @override
  $ProviderElement<FlutterSecureStorage> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FlutterSecureStorage create(Ref ref) {
    return secureStorage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FlutterSecureStorage value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FlutterSecureStorage>(value),
    );
  }
}

String _$secureStorageHash() => r'0cd1b80f91784467390034386f925a0be155bfbd';

@ProviderFor(authStorage)
final authStorageProvider = AuthStorageProvider._();

final class AuthStorageProvider
    extends $FunctionalProvider<AuthStorage, AuthStorage, AuthStorage>
    with $Provider<AuthStorage> {
  AuthStorageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authStorageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authStorageHash();

  @$internal
  @override
  $ProviderElement<AuthStorage> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthStorage create(Ref ref) {
    return authStorage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthStorage value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthStorage>(value),
    );
  }
}

String _$authStorageHash() => r'dbad61a03439e1e946df4c3f6c7b3fcc9b6afe0e';

/// The session of the signed-in user: adds the access token to requests
/// that need it and refreshes it.
///
/// [Fresh] queues requests while a refresh is in flight, so any number of
/// concurrent requests with an expired token cause one refresh. A rejected
/// refresh token (the session was revoked or its chain was reused) signs
/// the user out: [authStatusProvider] becomes unauthenticated and the app
/// returns to the sign-in screen.

@ProviderFor(authSession)
final authSessionProvider = AuthSessionProvider._();

/// The session of the signed-in user: adds the access token to requests
/// that need it and refreshes it.
///
/// [Fresh] queues requests while a refresh is in flight, so any number of
/// concurrent requests with an expired token cause one refresh. A rejected
/// refresh token (the session was revoked or its chain was reused) signs
/// the user out: [authStatusProvider] becomes unauthenticated and the app
/// returns to the sign-in screen.

final class AuthSessionProvider
    extends
        $FunctionalProvider<
          Fresh<AuthToken>,
          Fresh<AuthToken>,
          Fresh<AuthToken>
        >
    with $Provider<Fresh<AuthToken>> {
  /// The session of the signed-in user: adds the access token to requests
  /// that need it and refreshes it.
  ///
  /// [Fresh] queues requests while a refresh is in flight, so any number of
  /// concurrent requests with an expired token cause one refresh. A rejected
  /// refresh token (the session was revoked or its chain was reused) signs
  /// the user out: [authStatusProvider] becomes unauthenticated and the app
  /// returns to the sign-in screen.
  AuthSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authSessionHash();

  @$internal
  @override
  $ProviderElement<Fresh<AuthToken>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Fresh<AuthToken> create(Ref ref) {
    return authSession(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Fresh<AuthToken> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Fresh<AuthToken>>(value),
    );
  }
}

String _$authSessionHash() => r'37553f881e324869c057dc9269f6652408f850d3';

/// Whether a user is signed in on this device.
///
/// The saved session is read here and handed to [Fresh] explicitly: its own
/// initial read reports the status through a stream that can drop it, and
/// requests would then wait for a token forever.

@ProviderFor(AuthStatus)
final authStatusProvider = AuthStatusProvider._();

/// Whether a user is signed in on this device.
///
/// The saved session is read here and handed to [Fresh] explicitly: its own
/// initial read reports the status through a stream that can drop it, and
/// requests would then wait for a token forever.
final class AuthStatusProvider
    extends $AsyncNotifierProvider<AuthStatus, AuthenticationStatus> {
  /// Whether a user is signed in on this device.
  ///
  /// The saved session is read here and handed to [Fresh] explicitly: its own
  /// initial read reports the status through a stream that can drop it, and
  /// requests would then wait for a token forever.
  AuthStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authStatusHash();

  @$internal
  @override
  AuthStatus create() => AuthStatus();
}

String _$authStatusHash() => r'6586f84e00d2226cfcd00521a7f4c2d7f58765b3';

/// Whether a user is signed in on this device.
///
/// The saved session is read here and handed to [Fresh] explicitly: its own
/// initial read reports the status through a stream that can drop it, and
/// requests would then wait for a token forever.

abstract class _$AuthStatus extends $AsyncNotifier<AuthenticationStatus> {
  FutureOr<AuthenticationStatus> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<AuthenticationStatus>, AuthenticationStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AuthenticationStatus>,
                AuthenticationStatus
              >,
              AsyncValue<AuthenticationStatus>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
