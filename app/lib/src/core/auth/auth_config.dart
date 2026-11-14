import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_config.g.dart';

/// Client-side parameters of signing in.
///
/// Values come from `--dart-define` at build time (README, "Вход").
class AuthConfig {
  const AuthConfig({required this.resendDelay, required this.refreshMargin});

  factory AuthConfig.fromEnvironment() => const AuthConfig(
    resendDelay: Duration(
      seconds: int.fromEnvironment(
        'CAMPUS_SIGN_IN_RESEND_DELAY',
        defaultValue: 60,
      ),
    ),
    refreshMargin: Duration(
      seconds: int.fromEnvironment(
        'CAMPUS_TOKEN_REFRESH_MARGIN',
        defaultValue: 30,
      ),
    ),
  );

  /// Wait before another sign-in code can be requested. The server limits
  /// codes per address (ТЗ, Приложение 4) and may ask to wait longer.
  final Duration resendDelay;

  /// The access token is refreshed this long before it expires, so that a
  /// request does not reach the server with an expired one.
  final Duration refreshMargin;
}

@Riverpod(keepAlive: true)
AuthConfig authConfig(Ref ref) => AuthConfig.fromEnvironment();
