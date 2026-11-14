import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:campus/src/core/api/api_config.dart';
import 'package:campus/src/core/api/client_info.dart';
import 'package:campus/src/core/api/generated/campus_api.dart';
import 'package:dio/dio.dart';

/// Configuration for tests: no delays between repeated attempts.
final testApiConfig = ApiConfig(
  baseUrl: Uri.parse('https://campus.test'),
  downloadUrl: Uri.parse('https://campus.test/download'),
  connectTimeout: const Duration(seconds: 1),
  receiveTimeout: const Duration(seconds: 1),
  retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
);

const testClientInfo = ClientInfo(
  platform: ClientPlatformValue.android,
  version: '0.1.0',
);

/// A request as it reached the network.
class SentRequest {
  SentRequest(RequestOptions options)
    : method = options.method,
      path = options.path,
      headers = Map.of(options.headers),
      data = options.data;

  final String method;
  final String path;
  final Map<String, Object?> headers;
  final Object? data;

  /// The JSON body as sent by the generated client.
  Map<String, Object?> get json =>
      jsonDecode(data! as String) as Map<String, Object?>;
}

typedef Reply = ResponseBody Function(RequestOptions options);

/// Answers requests with queued replies instead of a server; once the
/// queue is empty, every request gets the last reply.
class FakeHttpAdapter implements HttpClientAdapter {
  final sent = <SentRequest>[];
  final _replies = <Reply>[];
  Reply? _last;

  void reply(int status, [Object? body = const <String, Object?>{}]) =>
      _add((_) => jsonBody(status, body));

  /// Answers every request with [reply], e.g. depending on its path.
  void route(Reply reply) => _add(reply);

  /// Answers with Problem Details.
  void replyProblem(
    int status,
    String code, {
    String? minVersion,
    List<Map<String, Object?>>? errors,
    int? retryAfter,
  }) => _add(
    (_) => problemBody(
      status,
      code,
      minVersion: minVersion,
      errors: errors,
      retryAfter: retryAfter,
    ),
  );

  /// Fails like a dropped connection.
  void failConnection() => _add(
    (options) => throw DioException.connectionError(
      requestOptions: options,
      reason: 'Connection reset by peer',
    ),
  );

  void failTimeout() => _add(
    (options) => throw DioException.receiveTimeout(
      timeout: const Duration(seconds: 1),
      requestOptions: options,
    ),
  );

  void _add(Reply reply) {
    _replies.add(reply);
    _last = reply;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(SentRequest(options));
    final reply = _replies.isEmpty ? _last : _replies.removeAt(0);
    if (reply == null) throw StateError('No reply for ${options.path}');
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

/// A JSON response with [status].
ResponseBody jsonBody(
  int status, [
  Object? body = const <String, Object?>{},
  Map<String, List<String>> headers = const {},
]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [
      status >= 400 ? 'application/problem+json' : 'application/json',
    ],
    ...headers,
  },
);

/// A Problem Details response.
ResponseBody problemBody(
  int status,
  String code, {
  String? minVersion,
  List<Map<String, Object?>>? errors,
  int? retryAfter,
}) => jsonBody(
  status,
  {
    'type': 'urn:problem:campus:$code',
    'title': 'Server title',
    'status': status,
    'detail': 'Server detail',
    'code': code,
    'request_id': 'req-123',
    'min_version': ?minVersion,
    'errors': ?errors,
  },
  {
    if (retryAfter != null) 'retry-after': ['$retryAfter'],
  },
);

/// Tokens as the server issues them; [n] tells issues apart.
Map<String, Object?> tokensJson(int n, {int expiresIn = 900}) => {
  'access_token': 'access-$n',
  'refresh_token': 'refresh-$n',
  'token_type': 'bearer',
  'expires_in': expiresIn,
  'user': {
    'id': '01890a5d-ac96-774b-bcce-b302099a8058',
    'email': 'ivanov@edu.hse.ru',
    'first_name': 'Иван',
    'last_name': 'Иванов',
    'account_type': 'student',
  },
};
