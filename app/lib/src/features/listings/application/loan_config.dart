import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Client-side parameters of a loan (ТЗ, Приложение 4).
///
/// Values come from `--dart-define` at build time and must match the server's
/// `CAMPUS_LOAN_PERIOD_MAX_DAYS` and the day count of
/// `CAMPUS_LOAN_NOT_RETURNED_AFTER`.
class LoanConfig {
  LoanConfig({required this.maxPeriodDays, required this.notReturnedAfter})
    : assert(maxPeriodDays > 0, 'a loan period must last at least a day'),
      assert(!notReturnedAfter.isNegative, 'the wait cannot be negative');

  factory LoanConfig.fromEnvironment() => LoanConfig(
    maxPeriodDays: const int.fromEnvironment(
      'CAMPUS_LOAN_PERIOD_MAX_DAYS',
      defaultValue: 90,
    ),
    notReturnedAfter: const Duration(
      days: int.fromEnvironment(
        'CAMPUS_LOAN_NOT_RETURNED_AFTER_DAYS',
        defaultValue: 3,
      ),
    ),
  );

  /// Longest return period an author may set, in days.
  final int maxPeriodDays;

  /// How long after the return deadline the owner may mark "not returned".
  final Duration notReturnedAfter;
}

/// Limits of a loan; tests replace it with their own values.
final loanConfigProvider = Provider<LoanConfig>(
  (ref) => LoanConfig.fromEnvironment(),
);
