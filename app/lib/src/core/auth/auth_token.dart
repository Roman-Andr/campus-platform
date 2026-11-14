import 'package:fresh_dio/fresh_dio.dart';

import '../api/generated/campus_api.dart';

/// Credentials of the signed-in user on this device.
///
/// Only [refreshToken] outlives the app process (see `AuthStorage`); after
/// a restart the access token is empty and is obtained again before the
/// first request that needs it.
class AuthToken extends Token {
  const AuthToken({
    required super.accessToken,
    required String super.refreshToken,
    this.expiresAt,
  });

  /// Credentials issued by sign-in or refresh at [now].
  factory AuthToken.issued(Tokens tokens, DateTime now) => AuthToken(
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    expiresAt: now.add(Duration(seconds: tokens.expiresIn)),
  );

  /// Credentials restored from storage: no access token yet.
  const AuthToken.restored(String refreshToken)
    : this(accessToken: '', refreshToken: refreshToken);

  /// When the access token stops working; `null` when there is none.
  @override
  final DateTime? expiresAt;

  String get refresh => refreshToken!;

  /// Whether the access token is missing or expires within [margin] of
  /// [now], so a request with it would be rejected.
  bool needsRefresh(DateTime now, Duration margin) {
    final expiresAt = this.expiresAt;
    return accessToken.isEmpty ||
        expiresAt == null ||
        !now.add(margin).isBefore(expiresAt);
  }

  /// Never includes the tokens: they must not reach logs.
  @override
  String toString() => 'AuthToken(expiresAt: $expiresAt)';
}
