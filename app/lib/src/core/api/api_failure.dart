import 'package:dio/dio.dart';

import 'generated/campus_api.dart';

/// Why an API request failed, in terms the interface can act on.
///
/// Requests made through the shared client throw [DioException]; use
/// [ApiFailure.from] to classify it. Messages for the user come from the
/// localization files (`apiFailureMessage`), never from the server.
sealed class ApiFailure implements Exception {
  const ApiFailure();

  /// Classifies [error] thrown by an API request.
  factory ApiFailure.from(Object error) {
    if (error is ApiFailure) return error;
    if (error is! DioException) return UnexpectedFailure(error);
    if (error.error case final ApiFailure failure) return failure;
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const NetworkFailure(),
      DioExceptionType.cancel => const CancelledFailure(),
      DioExceptionType.badResponse => _fromResponse(error.response),
      DioExceptionType.badCertificate ||
      DioExceptionType.transformTimeout ||
      DioExceptionType.unknown => UnexpectedFailure(error.error ?? error),
    };
  }

  static ApiFailure _fromResponse(Response<Object?>? response) {
    final problem = _problemOf(response?.data);
    final status = response?.statusCode;
    if (problem?.code == ProblemCode.clientUpdateRequired ||
        (problem == null && status == 426)) {
      return UpdateRequiredFailure(minVersion: problem?.minVersion);
    }
    if (problem != null) return ProblemFailure(problem);
    return UnexpectedFailure(status);
  }

  static Problem? _problemOf(Object? data) {
    if (data is! Map<String, Object?>) return null;
    try {
      return Problem.fromJson(data);
    } on Object {
      return null;
    }
  }
}

/// The server could not be reached or did not answer in time.
final class NetworkFailure extends ApiFailure {
  const NetworkFailure();
}

/// The request was cancelled by the app; nothing to show.
final class CancelledFailure extends ApiFailure {
  const CancelledFailure();
}

/// This version of the app is no longer supported (`426`).
final class UpdateRequiredFailure extends ApiFailure {
  const UpdateRequiredFailure({this.minVersion});

  /// Oldest supported version, when the server reported it.
  final String? minVersion;
}

/// The server rejected the request with Problem Details.
final class ProblemFailure extends ApiFailure {
  const ProblemFailure(this.problem);

  final Problem problem;

  int get status => problem.status;

  /// Machine-readable reason; unknown codes of newer servers are kept.
  ProblemCode get code => problem.code;

  /// Invalid parts of the request, for showing next to form fields.
  List<FieldError> get fieldErrors => problem.errors ?? const [];
}

/// Anything else: an unreadable response, a bug in the client.
final class UnexpectedFailure extends ApiFailure {
  const UnexpectedFailure(this.cause);

  /// For logs only; never shown to the user.
  final Object? cause;
}
