import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_client.dart';
import 'auth_session.dart';
import 'auth_storage.dart';
import 'auth_token.dart';

part 'auth_service.g.dart';

/// Signing in with a code from an e-mail and signing out (ТЗ п. 5.1.1,
/// модуль 1).
class AuthService {
  AuthService(this._api, this._session, this._storage);

  final AuthenticationClient _api;
  final Fresh<AuthToken> _session;
  final AuthStorage _storage;

  /// Asks the server to e-mail a sign-in code to [email].
  Future<void> requestCode(String email) =>
      _api.requestSignInCode(body: EmailInput(email: email));

  /// Signs in with [code]; a new user also gives the names.
  ///
  /// Throws a `registration_required` problem when the address has no
  /// account yet and the names are missing.
  Future<UserOutput> signIn({
    required String email,
    required String code,
    String? firstName,
    String? lastName,
  }) async {
    final tokens = await _api.signIn(
      body: SignInInput(
        email: email,
        code: code,
        deviceId: await _storage.deviceId(),
        firstName: firstName,
        lastName: lastName,
      ),
    );
    await _session.setToken(AuthToken.issued(tokens, clock.now()));
    return tokens.user;
  }

  /// Ends the session on the server and forgets the tokens.
  ///
  /// The device signs out even when the server cannot be reached.
  Future<void> signOut() async {
    try {
      await _api.signOut();
    } on DioException {
      // Nothing to do: the tokens are removed below either way.
    } finally {
      await _session.clearToken();
    }
  }
}

@Riverpod(keepAlive: true)
AuthService authService(Ref ref) => AuthService(
  ref.watch(campusApiProvider).authentication,
  ref.watch(authSessionProvider),
  ref.watch(authStorageProvider),
);
