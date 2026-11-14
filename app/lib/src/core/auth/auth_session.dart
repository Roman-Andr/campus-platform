import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_client.dart';
import 'auth_config.dart';
import 'auth_storage.dart';
import 'auth_token.dart';

export 'package:fresh_dio/fresh_dio.dart' show AuthenticationStatus;

part 'auth_session.g.dart';

/// Extra of generated operations that require an access token.
const securityExtra = 'openapi.security';

@Riverpod(keepAlive: true)
FlutterSecureStorage secureStorage(Ref ref) => const FlutterSecureStorage();

@Riverpod(keepAlive: true)
AuthStorage authStorage(Ref ref) =>
    AuthStorage(ref.watch(secureStorageProvider));

/// The session of the signed-in user: adds the access token to requests
/// that need it and refreshes it.
///
/// [Fresh] queues requests while a refresh is in flight, so any number of
/// concurrent requests with an expired token cause one refresh. A rejected
/// refresh token (the session was revoked or its chain was reused) signs
/// the user out: [authStatusProvider] becomes unauthenticated and the app
/// returns to the sign-in screen.
@Riverpod(keepAlive: true)
Fresh<AuthToken> authSession(Ref ref) {
  final storage = ref.watch(authStorageProvider);
  final margin = ref.watch(authConfigProvider).refreshMargin;
  final session = Fresh<AuthToken>(
    tokenStorage: storage,
    httpClient: ref.watch(authRefreshDioProvider),
    tokenHeader: (token) => {'Authorization': 'Bearer ${token.accessToken}'},
    // Generated operations declare their security; public ones such as
    // sign-in must not get a token or trigger a refresh.
    isTokenRequired: (options) => options.extra.containsKey(securityExtra),
    shouldRefreshBeforeRequest: (options, token) =>
        token != null && token.needsRefresh(clock.now(), margin),
    refreshToken: (token, client) => _refresh(token, client, storage),
  );
  ref.onDispose(session.close);
  return session;
}

Future<AuthToken> _refresh(
  AuthToken? token,
  Dio client,
  AuthStorage storage,
) async {
  if (token == null) throw RevokeTokenException();
  try {
    final tokens = await AuthenticationClient(client).refreshTokens(
      body: RefreshInput(
        refreshToken: token.refresh,
        deviceId: await storage.deviceId(),
      ),
    );
    return AuthToken.issued(tokens, clock.now());
  } on DioException catch (error) {
    // The server no longer accepts the refresh token: the session is over.
    // Other failures (no network, server errors) keep it for a later try.
    if (ApiFailure.from(error) case ProblemFailure(status: 401)) {
      throw RevokeTokenException();
    }
    rethrow;
  }
}

/// Whether a user is signed in on this device.
///
/// The saved session is read here and handed to [Fresh] explicitly: its own
/// initial read reports the status through a stream that can drop it, and
/// requests would then wait for a token forever.
@Riverpod(keepAlive: true)
class AuthStatus extends _$AuthStatus {
  @override
  Future<AuthenticationStatus> build() async {
    final session = ref.watch(authSessionProvider);
    final saved = await ref.watch(authStorageProvider).read();
    await session.setToken(saved);
    final changes = session.authenticationStatus.listen((status) {
      if (status != AuthenticationStatus.initial) state = AsyncData(status);
    });
    ref.onDispose(changes.cancel);
    return saved == null
        ? AuthenticationStatus.unauthenticated
        : AuthenticationStatus.authenticated;
  }
}
