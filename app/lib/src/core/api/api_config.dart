import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_config.g.dart';

/// Server address and transport parameters of the API client.
///
/// Values come from `--dart-define` at build time (README, "Клиент API"),
/// so a build can target the dev server, the staging stand or production.
class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    required this.downloadUrl,
    required this.connectTimeout,
    required this.receiveTimeout,
    required this.retryDelays,
  });

  /// Reads the build-time configuration.
  factory ApiConfig.fromEnvironment() => ApiConfig(
    baseUrl: Uri.parse(
      const String.fromEnvironment(
        'CAMPUS_API_URL',
        defaultValue: 'http://localhost:8000',
      ),
    ),
    downloadUrl: Uri.parse(
      const String.fromEnvironment(
        'CAMPUS_DOWNLOAD_URL',
        defaultValue:
            'https://github.com/Roman-Andr/campus-platform/releases/latest',
      ),
    ),
    connectTimeout: const Duration(
      seconds: int.fromEnvironment(
        'CAMPUS_API_CONNECT_TIMEOUT',
        defaultValue: 10,
      ),
    ),
    receiveTimeout: const Duration(
      seconds: int.fromEnvironment(
        'CAMPUS_API_RECEIVE_TIMEOUT',
        defaultValue: 30,
      ),
    ),
    retryDelays: [
      for (var attempt = 0; attempt < _retries; attempt++)
        Duration(seconds: 1 << attempt),
    ],
  );

  static const _retries = int.fromEnvironment(
    'CAMPUS_API_RETRIES',
    defaultValue: 3,
  );

  /// Origin of the server; API paths start with `/api/v1`.
  final Uri baseUrl;

  /// Page with the latest release, opened when an update is required.
  final Uri downloadUrl;

  final Duration connectTimeout;
  final Duration receiveTimeout;

  /// Delays before repeated attempts after a network failure; their number
  /// is the number of repeats.
  final List<Duration> retryDelays;
}

@Riverpod(keepAlive: true)
ApiConfig apiConfig(Ref ref) => ApiConfig.fromEnvironment();
