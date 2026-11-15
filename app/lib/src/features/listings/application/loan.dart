import 'package:dio/dio.dart' show Options;
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/api/interceptors.dart' show idempotencyKeyHeader;
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import 'loan_config.dart';

/// Keys of mutating loan requests that the user may repeat.
///
/// A repeat after a dropped connection must send the key of the same intent
/// (`Idempotency-Key`), so the server applies the handover, the return or the
/// "not returned" mark once. A different intent starts a new key, and a
/// successful operation drops it.
class LoanKeys {
  LoanKeys({String Function()? generate})
    : _generate = generate ?? const Uuid().v7;

  final String Function() _generate;
  String? _intent;
  String? _key;

  /// The key of [intent], created on first use and kept while it repeats.
  String of(String intent) {
    if (_intent != intent || _key == null) {
      _intent = intent;
      _key = _generate();
    }
    return _key!;
  }

  /// Forgets the key of [intent] once it succeeded.
  void done(String intent) {
    if (_intent != intent) return;
    _intent = null;
    _key = null;
  }
}

/// Options of a mutating loan request carrying [key] as `Idempotency-Key`.
Options loanMutationOptions(String key) =>
    Options(headers: {idempotencyKeyHeader: key});

/// Formats [instant] in the zone of a listing's city.
String loanCityTime(
  AppLocalizations l,
  DateTime instant, {
  required String timezone,
  String? city,
}) => formatCityTime(
  instant,
  timezone: timezone,
  city: city ?? timezone,
  l10n: l,
  includeDate: true,
);

/// A message for a failed loan publication or "not returned" mark.
String loanFailureMessage(
  AppLocalizations l,
  Object error, {
  required LoanConfig config,
  String Function(DateTime instant)? cityTime,
}) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.listingLoanPeriodInvalid),
  ) =>
    l.loanPeriodInvalid(config.maxPeriodDays),
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.loanNotReturnedTooEarly),
    :final problem,
  ) =>
    switch (problem.availableAt) {
      final availableAt? when cityTime != null => l.loanNotReturnedTooEarly(
        cityTime(availableAt),
      ),
      _ => l.loanNotReturnedLater,
    },
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.loanNotReturnedForbidden),
  ) =>
    l.loanNotReturnedForbidden,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.loanNotReturnedUnavailable),
  ) =>
    l.loanNotReturnedUnavailable,
  _ => apiFailureMessage(l, error),
};

/// A message for a failed answer to the borrower's no-show.
String loanNoShowFailureMessage(
  AppLocalizations l,
  Object error, {
  required int reasonMaxLength,
}) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowClosed),
  ) =>
    l.loanDisputeClosed,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowStateConflict),
  ) =>
    l.loanDisputeClosed,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowUnavailable),
  ) =>
    l.loanNoShowUnavailable,
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowReasonInvalid),
  ) =>
    l.loanDisputeReasonInvalid(reasonMaxLength),
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.noShowForbidden),
  ) =>
    l.loanDisputeForbidden,
  _ => apiFailureMessage(l, error),
};

/// Checks a dispute reason before it is sent; `null` when it is usable.
String? loanDisputeReasonError(
  AppLocalizations l,
  String reason, {
  required int reasonMaxLength,
}) {
  final trimmed = reason.trim();
  if (trimmed.isEmpty) return l.loanDisputeReasonRequired;
  if (trimmed.length > reasonMaxLength) {
    return l.loanDisputeReasonInvalid(reasonMaxLength);
  }
  return null;
}
