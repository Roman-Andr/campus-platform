import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:uuid/uuid.dart';

import 'api_failure.dart';
import 'client_info.dart';

const platformHeader = 'X-Client-Platform';
const versionHeader = 'X-Client-Version';
const idempotencyKeyHeader = 'Idempotency-Key';

/// Methods that change data and carry an [idempotencyKeyHeader].
const mutatingMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};

/// Adds the client platform, version and interface language to every
/// request (ТЗ п. 4.6).
class ClientHeadersInterceptor extends Interceptor {
  ClientHeadersInterceptor(this._client, this._language);

  final ClientInfo _client;

  /// Language code of the interface, for messages of the server.
  final String Function() _language;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers[platformHeader] = _client.platform.value;
    options.headers[versionHeader] = _client.version;
    options.headers['Accept-Language'] = _language();
    handler.next(options);
  }
}

/// Gives every mutating request an `Idempotency-Key` (UUIDv7).
///
/// The key is stored in the request options, so a repeat of the same
/// request after a network failure (see [retryInterceptor]) sends the same
/// key and the server applies the operation once. A key passed by the
/// caller is kept: an operation repeated by the user, e.g. after the app
/// restarted, reuses the key saved with it.
class IdempotencyKeyInterceptor extends Interceptor {
  IdempotencyKeyInterceptor({String Function()? generate})
    : _generate = generate ?? const Uuid().v7;

  final String Function() _generate;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final hasKey = options.headers.keys.any(
      (name) => name.toLowerCase() == idempotencyKeyHeader.toLowerCase(),
    );
    if (mutatingMethods.contains(options.method.toUpperCase()) && !hasKey) {
      options.headers[idempotencyKeyHeader] = _generate();
    }
    handler.next(options);
  }
}

/// Repeats requests that failed on the way to or from the server.
///
/// Mutating requests are repeated too: their idempotency key makes this
/// safe. Server errors with a response are not repeated, except the
/// statuses of an overloaded or restarting server.
RetryInterceptor retryInterceptor(Dio dio, List<Duration> delays) =>
    RetryInterceptor(
      dio: dio,
      retries: delays.length,
      retryDelays: delays,
      retryEvaluator: (error, attempt) => switch (error.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => true,
        DioExceptionType.badResponse => const {
          408,
          429,
          502,
          503,
          504,
        }.contains(error.response?.statusCode),
        _ => false,
      },
    );

/// Reports the outcome of requests: whether the server is reachable and
/// whether this client version is still supported.
class ApiStatusInterceptor extends Interceptor {
  ApiStatusInterceptor({
    required this.onReachable,
    required this.onUnreachable,
    required this.onUpdateRequired,
  });

  final void Function() onReachable;
  final void Function() onUnreachable;
  final void Function(String? minVersion) onUpdateRequired;

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    onReachable();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null) onReachable();
    switch (ApiFailure.from(err)) {
      case UpdateRequiredFailure(:final minVersion):
        onUpdateRequired(minVersion);
      case NetworkFailure() when _unreachable(err.type):
        onUnreachable();
      default:
    }
    handler.next(err);
  }

  static bool _unreachable(DioExceptionType type) =>
      type == DioExceptionType.connectionError ||
      type == DioExceptionType.connectionTimeout;
}
