import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'realtime_config.g.dart';

/// Address and backoff parameters of the Centrifugo client.
///
/// The default targets the development stand of `infra/` where Centrifugo
/// publishes its client endpoint directly on `127.0.0.1:8001`. A build for
/// the staging stand or production uses the public Caddy route:
/// `--dart-define=CAMPUS_REALTIME_URL=wss://campus.example/connection/websocket`.
class RealtimeConfig {
  const RealtimeConfig({
    required this.url,
    required this.minReconnectDelay,
    required this.maxReconnectDelay,
    required this.minResubscribeDelay,
    required this.maxResubscribeDelay,
    required this.tokenRefreshMargin,
  }) : assert(minReconnectDelay <= maxReconnectDelay),
       assert(minResubscribeDelay <= maxResubscribeDelay);

  /// Reads build-time configuration; values are documented in the app
  /// README.
  factory RealtimeConfig.fromEnvironment() => RealtimeConfig(
    url: Uri.parse(
      const String.fromEnvironment(
        'CAMPUS_REALTIME_URL',
        defaultValue: 'ws://localhost:8001/connection/websocket',
      ),
    ),
    minReconnectDelay: const Duration(
      milliseconds: int.fromEnvironment(
        'CAMPUS_REALTIME_RECONNECT_MIN_MS',
        defaultValue: 500,
      ),
    ),
    maxReconnectDelay: const Duration(
      milliseconds: int.fromEnvironment(
        'CAMPUS_REALTIME_RECONNECT_MAX_MS',
        defaultValue: 30000,
      ),
    ),
    minResubscribeDelay: const Duration(
      milliseconds: int.fromEnvironment(
        'CAMPUS_REALTIME_RESUBSCRIBE_MIN_MS',
        defaultValue: 500,
      ),
    ),
    maxResubscribeDelay: const Duration(
      milliseconds: int.fromEnvironment(
        'CAMPUS_REALTIME_RESUBSCRIBE_MAX_MS',
        defaultValue: 30000,
      ),
    ),
    tokenRefreshMargin: const Duration(
      seconds: int.fromEnvironment(
        'CAMPUS_REALTIME_TOKEN_MARGIN',
        defaultValue: 30,
      ),
    ),
  );

  /// WebSocket endpoint of Centrifugo (its client transport).
  final Uri url;

  /// The first and the longest pause between connection attempts.
  final Duration minReconnectDelay;
  final Duration maxReconnectDelay;

  /// The same for repeated subscription attempts after an error.
  final Duration minResubscribeDelay;
  final Duration maxResubscribeDelay;

  /// An access or subscription token that expires within this margin is
  /// renewed before it is reused.
  final Duration tokenRefreshMargin;
}

@Riverpod(keepAlive: true)
RealtimeConfig realtimeConfig(Ref ref) => RealtimeConfig.fromEnvironment();
