import 'package:centrifuge/centrifuge.dart' show UnauthorizedException;

import '../api/api_failure.dart';
import '../api/generated/campus_api.dart';
import '../l10n/generated/app_localizations.dart';

/// Why a realtime operation failed, in terms the interface can act on.
enum RealtimeFailureKind {
  /// The session is over; no token will be issued until the user signs in.
  unauthorized,

  /// The user is not a member of the channel any more.
  forbidden,

  /// The channel name is not a Campus realtime channel.
  invalidChannel,

  /// The realtime server or its recovery API is temporarily unavailable.
  unavailable,

  /// Centrifugo no longer keeps the stream position; the state was reloaded
  /// through the API.
  historyLost,

  /// The device or the server could not be reached.
  network,

  /// Anything else: a bug, an unreadable reply.
  unexpected,
}

/// A classified realtime failure.
class RealtimeFailure {
  const RealtimeFailure(this.kind, {this.code});

  /// Classifies an error thrown by the realtime API or the client SDK.
  factory RealtimeFailure.from(Object error) {
    if (error is RealtimeApiException) return error.failure;
    if (error is RealtimeUnauthorizedException) return error.failure;
    if (error is UnauthorizedException) {
      return const RealtimeFailure(RealtimeFailureKind.unauthorized);
    }
    final failure = ApiFailure.from(error);
    return switch (failure) {
      NetworkFailure() ||
      CancelledFailure() => const RealtimeFailure(RealtimeFailureKind.network),
      ProblemFailure(:final code, :final status) => _fromProblem(code, status),
      _ => const RealtimeFailure(RealtimeFailureKind.unexpected),
    };
  }

  static RealtimeFailure _fromProblem(ProblemCode code, int status) =>
      switch (code) {
        ProblemCodeKnown(value: ProblemCodeValue.realtimeChannelForbidden) =>
          const RealtimeFailure(
            RealtimeFailureKind.forbidden,
            code: 'forbidden',
          ),
        ProblemCodeKnown(value: ProblemCodeValue.realtimeChannelInvalid) =>
          const RealtimeFailure(
            RealtimeFailureKind.invalidChannel,
            code: 'invalid_channel',
          ),
        ProblemCodeKnown(value: ProblemCodeValue.realtimeUnavailable) =>
          const RealtimeFailure(
            RealtimeFailureKind.unavailable,
            code: 'unavailable',
          ),
        ProblemCodeKnown(value: ProblemCodeValue.realtimeHistoryLost) =>
          const RealtimeFailure(
            RealtimeFailureKind.historyLost,
            code: 'history_lost',
          ),
        _ when status == 401 => const RealtimeFailure(
          RealtimeFailureKind.unauthorized,
        ),
        _ when status == 403 => const RealtimeFailure(
          RealtimeFailureKind.forbidden,
        ),
        _ when status == 409 => const RealtimeFailure(
          RealtimeFailureKind.historyLost,
        ),
        _ when status >= 500 => const RealtimeFailure(
          RealtimeFailureKind.unavailable,
        ),
        _ => const RealtimeFailure(RealtimeFailureKind.unexpected),
      };

  final RealtimeFailureKind kind;

  /// Machine-readable reason, when the server reported one; for logs only.
  final String? code;

  /// Whether retrying without a new sign-in cannot help.
  bool get isTerminal =>
      kind == RealtimeFailureKind.unauthorized ||
      kind == RealtimeFailureKind.forbidden ||
      kind == RealtimeFailureKind.invalidChannel;

  @override
  bool operator ==(Object other) =>
      other is RealtimeFailure && other.kind == kind && other.code == code;

  @override
  int get hashCode => Object.hash(kind, code);

  @override
  String toString() => 'RealtimeFailure(${kind.name}, code: $code)';
}

/// A failure of a realtime API call, kept typed through the client SDK.
class RealtimeApiException implements Exception {
  const RealtimeApiException(this.failure);

  final RealtimeFailure failure;

  @override
  String toString() => 'RealtimeApiException(${failure.kind.name})';
}

/// A rejected connection or subscription token.
///
/// The SDK stops and disconnects for [UnauthorizedException] instead of
/// retrying: no later attempt with the same session will be allowed.
class RealtimeUnauthorizedException extends UnauthorizedException {
  RealtimeUnauthorizedException(this.failure) : super(failure.kind.name);

  final RealtimeFailure failure;
}

/// A message for the user about a realtime failure; texts come from ARB.
String realtimeFailureMessage(AppLocalizations l10n, RealtimeFailure failure) =>
    switch (failure.kind) {
      RealtimeFailureKind.unauthorized => l10n.realtimeSessionEnded,
      RealtimeFailureKind.forbidden => l10n.realtimeChannelForbidden,
      RealtimeFailureKind.invalidChannel => l10n.realtimeChannelInvalid,
      RealtimeFailureKind.unavailable => l10n.realtimeUnavailable,
      RealtimeFailureKind.historyLost => l10n.realtimeHistoryLost,
      RealtimeFailureKind.network => l10n.realtimeNetworkLost,
      RealtimeFailureKind.unexpected => l10n.realtimeError,
    };
