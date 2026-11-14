import 'dart:convert';

import 'package:dio/dio.dart';

import '../../helpers/fake_api.dart';

/// Answers the realtime API of the server without a network.
class RealtimeTestServer {
  RealtimeTestServer() {
    adapter.route(_answer);
  }

  final adapter = FakeHttpAdapter();

  int connectionTokenRequests = 0;
  int subscriptionTokenRequests = 0;
  int recoverRequests = 0;
  final subscriptionChannels = <String>[];

  /// Channels the user may not subscribe to (`403 realtime_channel_forbidden`).
  final forbiddenChannels = <String>{};

  /// Channels whose position is no longer in history: a recovery with
  /// `since` answers `409 realtime_history_lost`.
  final historyLostChannels = <String>{};

  /// Publications the recovery API returns for a requested position.
  final recoveredPublications = <String, List<Map<String, Object?>>>{};

  /// Current position returned by the recovery API.
  final positions = <String, int>{};

  /// The next connection token requests fail on the way to the server.
  int connectionTokenNetworkFailures = 0;

  /// The next subscription token requests fail on the way to the server.
  int subscriptionTokenNetworkFailures = 0;

  /// While set, the connection token route answers with this status.
  int? connectionTokenStatus;
  int? subscriptionTokenStatus;

  DateTime tokenExpiry = DateTime.now().toUtc().add(const Duration(minutes: 5));

  ResponseBody _answer(RequestOptions options) {
    switch (options.path) {
      case '/api/v1/auth/token/refresh':
        return jsonBody(200, tokensJson(1));
      case '/api/v1/realtime/connection-token':
        connectionTokenRequests++;
        if (connectionTokenNetworkFailures > 0) {
          connectionTokenNetworkFailures--;
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection reset by peer',
          );
        }
        final status = connectionTokenStatus;
        if (status != null) {
          return problemBody(status, 'realtime_unavailable');
        }
        return jsonBody(200, {
          'token': 'connection-$connectionTokenRequests',
          'expires_at': tokenExpiry.toIso8601String(),
        });
      case '/api/v1/realtime/subscription-token':
        subscriptionTokenRequests++;
        if (subscriptionTokenNetworkFailures > 0) {
          subscriptionTokenNetworkFailures--;
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection reset by peer',
          );
        }
        final status = subscriptionTokenStatus;
        if (status != null) {
          return problemBody(
            status,
            status == 403
                ? 'realtime_channel_forbidden'
                : 'realtime_unavailable',
          );
        }
        final body =
            jsonDecode(options.data! as String) as Map<String, Object?>;
        final channel = body['channel']! as String;
        subscriptionChannels.add(channel);
        if (forbiddenChannels.contains(channel)) {
          return problemBody(403, 'realtime_channel_forbidden');
        }
        return jsonBody(200, {
          'token': 'subscription-${subscriptionChannels.length}',
          'expires_at': tokenExpiry.toIso8601String(),
          'channel': channel,
        });
      case '/api/v1/realtime/recover':
        recoverRequests++;
        final body =
            jsonDecode(options.data! as String) as Map<String, Object?>;
        final channel = body['channel']! as String;
        final since = body['since'];
        if (since != null && historyLostChannels.contains(channel)) {
          return problemBody(409, 'realtime_history_lost');
        }
        final publications = since == null
            ? const <Map<String, Object?>>[]
            : recoveredPublications.remove(channel) ?? const [];
        final offset = positions[channel] ?? 0;
        return jsonBody(200, {
          'channel': channel,
          'epoch': 'epoch-1',
          'offset': offset,
          'publications': publications,
        });
      case '/api/v1/auth/sign-out':
        return jsonBody(204, {});
      default:
        throw StateError('No reply for ${options.path}');
    }
  }
}
