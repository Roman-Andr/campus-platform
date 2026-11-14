import 'package:clock/clock.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_client.dart';
import '../auth/auth_session.dart';
import 'realtime_channel.dart';
import 'realtime_config.dart';
import 'realtime_failure.dart';
import 'realtime_models.dart';

part 'realtime_tokens.g.dart';

/// Connection and subscription tokens of the current device session.
///
/// Centrifugo asks for a new token when the old one expires or the server
/// invalidates the connection. Both calls go through the shared API client,
/// so the access token, `Idempotency-Key` and retry of a dropped request are
/// the same as for every other request: a retry reuses its key, and the
/// server returns the stored token instead of issuing a second one.
@Riverpod(keepAlive: true)
RealtimeTokens realtimeTokens(Ref ref) {
  final tokens = RealtimeTokens(
    ref.watch(campusApiProvider).realtime,
    refreshMargin: ref.watch(realtimeConfigProvider).tokenRefreshMargin,
  );
  // Tokens are bound to the session and its grants: a new user must not
  // reuse them, and a signed-out client must not hold them in memory.
  ref.listen(authStatusProvider, (_, next) {
    if (next.value != AuthenticationStatus.authenticated) tokens.clear();
  });
  return tokens;
}

class RealtimeTokens {
  RealtimeTokens(
    this._api, {
    required this.refreshMargin,
    DateTime Function()? now,
  }) : _now = now ?? clock.now;

  final RealtimeClient _api;
  final Duration refreshMargin;
  final DateTime Function() _now;

  final _connection = _CachedToken();
  final _subscriptions = <String, _CachedToken>{};
  final _subscriptionFailures = <String, RealtimeFailure>{};

  /// A connection token, reused until it is about to expire.
  Future<String> connectionToken() =>
      _connection.get(_fetchConnectionToken, _now, refreshMargin);

  /// A token for [channel], reused until it is about to expire.
  Future<String> subscriptionToken(String channel) {
    final cache = _subscriptions.putIfAbsent(channel, _CachedToken.new);
    return cache.get(
      () => _fetchSubscriptionToken(channel),
      _now,
      refreshMargin,
      onError: (failure) => _subscriptionFailures[channel] = failure,
    );
  }

  /// The failure that stopped the last token request of [channel], if any.
  ///
  /// The SDK reports a rejected token as a plain unauthorized unsubscribe,
  /// so the reason is kept here for the interface.
  RealtimeFailure? takeSubscriptionFailure(String channel) =>
      _subscriptionFailures.remove(channel);

  /// The current position of [channel] and, when [since] is given, the
  /// publications after it.
  ///
  /// Used when Centrifugo cannot recover a subscription: the state is
  /// reloaded through the API and the subscription continues from this
  /// position.
  Future<RealtimeRecovery> recoverPosition(
    RealtimeChannel channel, {
    RealtimePosition? since,
  }) async {
    try {
      final result = await _api.recover(
        body: RecoverInput(
          channel: channel.name,
          since: since == null
              ? null
              : Position(epoch: since.epoch, offset: since.offset),
        ),
      );
      return RealtimeRecovery(
        position: RealtimePosition(epoch: result.epoch, offset: result.offset),
        publications: [
          for (final publication
              in result.publications ?? <PublicationOutput>[])
            RealtimeEvent(
              channel: channel.name,
              offset: publication.offset,
              data: publication.data,
            ),
        ],
      );
    } catch (error) {
      throw RealtimeApiException(RealtimeFailure.from(error));
    }
  }

  /// Forgets all tokens and failures; called on sign-out.
  void clear() {
    _connection.clear();
    _subscriptions.clear();
    _subscriptionFailures.clear();
  }

  Future<_IssuedToken> _fetchConnectionToken() async {
    final token = await _guard((api) => api.issueConnectionToken());
    return _IssuedToken(token.token, token.expiresAt);
  }

  Future<_IssuedToken> _fetchSubscriptionToken(String channel) async {
    final token = await _guard(
      (api) => api.issueSubscriptionToken(
        body: SubscriptionTokenInput(channel: channel),
      ),
      channel: channel,
    );
    return _IssuedToken(token.token, token.expiresAt);
  }

  Future<T> _guard<T>(
    Future<T> Function(RealtimeClient api) call, {
    String? channel,
  }) async {
    try {
      return await call(_api);
    } catch (error) {
      final failure = RealtimeFailure.from(error);
      if (channel != null) _subscriptionFailures[channel] = failure;
      if (failure.isTerminal) {
        throw RealtimeUnauthorizedException(failure);
      }
      throw RealtimeApiException(failure);
    }
  }
}

/// A token and its server-reported expiry.
class _IssuedToken {
  const _IssuedToken(this.token, this.expiresAt);

  final String token;
  final DateTime expiresAt;
}

/// One token with its expiry and the request in flight, so concurrent
/// callbacks of the SDK share one API request.
class _CachedToken {
  String? _token;
  DateTime? _expiresAt;
  Future<String>? _loading;

  Future<String> get(
    Future<_IssuedToken> Function() fetch,
    DateTime Function() now,
    Duration margin, {
    void Function(RealtimeFailure failure)? onError,
  }) {
    final token = _token;
    final expiresAt = _expiresAt;
    if (token != null &&
        expiresAt != null &&
        now().add(margin).isBefore(expiresAt)) {
      return Future.value(token);
    }
    final loading = _loading;
    if (loading != null) return loading;
    final future = _load(fetch, onError);
    _loading = future;
    return future;
  }

  Future<String> _load(
    Future<_IssuedToken> Function() fetch,
    void Function(RealtimeFailure failure)? onError,
  ) async {
    try {
      final issued = await fetch();
      _token = issued.token;
      _expiresAt = issued.expiresAt;
      return issued.token;
    } catch (error) {
      onError?.call(RealtimeFailure.from(error));
      rethrow;
    } finally {
      _loading = null;
    }
  }

  void clear() {
    _token = null;
    _expiresAt = null;
    _loading = null;
  }
}
