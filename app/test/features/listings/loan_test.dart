import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/features/listings/application/loan.dart';
import 'package:campus/src/features/listings/application/loan_config.dart';
import 'package:campus/src/features/listings/domain/feed.dart';
import 'package:campus/src/features/listings/domain/loan.dart';
import 'package:campus/src/features/listings/presentation/my_screens.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _l = AppLocalizationsEn();

const _owner = '01890a5d-ac96-774b-bcce-b302099a8070';
const _borrower = '01890a5d-ac96-774b-bcce-b302099a8071';
const _listing = '01890a5d-ac96-774b-bcce-b302099a8072';
const _interaction = '01890a5d-ac96-774b-bcce-b302099a8073';

InteractionOutput interaction({
  InteractionStatus status = InteractionStatus.accepted,
  String? stage,
  DateTime? returnDueAt,
  bool overdue = false,
  String participantId = _borrower,
  DateTime? completedAt,
}) => InteractionOutput.fromJson({
  'id': _interaction,
  'listing_id': _listing,
  'participant_name': 'Boris',
  'participant_id': participantId,
  'status': status.toJson(),
  'stage': stage,
  'response_due_at': null,
  'executor': false,
  'meeting': null,
  'return_due_at': ?returnDueAt?.toUtc().toIso8601String(),
  'overdue': overdue,
  'completed_at': ?completedAt?.toUtc().toIso8601String(),
});

Map<String, Object?> markJson({
  String reporter = _owner,
  String? reason = 'loan_not_returned',
  String status = 'counted',
}) => {
  'id': '01890a5d-ac96-774b-bcce-b302099a8074',
  'kind': 'personal',
  'status': status,
  'reporter_id': reporter,
  'subject_id': _borrower,
  'reason': reason,
  'created_at': '2027-01-20T12:00:00Z',
  'disputed_at': null,
  'removed_at': null,
};

Map<String, Object?> disputeJson({String status = 'open'}) => {
  'id': '01890a5d-ac96-774b-bcce-b302099a8075',
  'status': status,
  'opened_at': '2027-01-21T12:00:00Z',
  'resolved_at': null,
  'resolution': null,
};

NoShowOutput noShow({
  List<Map<String, Object?>> marks = const [],
  Map<String, Object?>? dispute,
  bool canMark = false,
}) => NoShowOutput.fromJson({
  'listing_id': _listing,
  'interaction_id': _interaction,
  'status': 'no_show',
  'basis': dispute != null
      ? 'mutual_dispute'
      : marks.isEmpty
      ? 'unmarked'
      : 'marked',
  'marks': marks,
  'dispute': dispute,
  'no_show_at': marks.isEmpty ? null : '2027-01-20T12:00:00Z',
  'mark_from': null,
  'auto_after': null,
  'can_mark': canMark,
  'server_time': '2027-01-21T12:00:00Z',
});

ProblemFailure problem(
  String code, {
  int status = 409,
  Map<String, Object?> extra = const {},
}) => ProblemFailure(
  Problem.fromJson({
    'type': 'urn:problem:campus:$code',
    'title': 'Title',
    'status': status,
    'code': code,
    'request_id': 'req-1',
    ...extra,
  }),
);

final config = LoanConfig(
  maxPeriodDays: 90,
  notReturnedAfter: const Duration(days: 3),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  group('steps', () {
    test('an accepted loan is at the handover step', () {
      final item = interaction();
      expect(loanStep(item), LoanStep.accepted);
      expect(loanIsIssued(item), isFalse);
    });

    test('a confirmed handover is at the issued step', () {
      final item = interaction(
        stage: loanIssuedStage,
        returnDueAt: DateTime.utc(2027, 1, 20, 12),
      );
      expect(loanStep(item), LoanStep.issued);
      expect(loanIsIssued(item), isTrue);
    });

    test('a completed loan is at the returned step', () {
      final item = interaction(
        status: InteractionStatus.completed,
        stage: loanIssuedStage,
        completedAt: DateTime.utc(2027, 1, 20, 12),
      );
      expect(loanStep(item), LoanStep.returned);
    });

    test('every other ending closes the loan', () {
      for (final status in [
        InteractionStatus.pending,
        InteractionStatus.rejected,
        InteractionStatus.cancelled,
        InteractionStatus.noShow,
      ]) {
        expect(loanStep(interaction(status: status)), LoanStep.closed);
      }
    });

    test('the participant is the borrower, everybody else the owner', () {
      final item = interaction();
      expect(loanIsBorrower(item, _borrower), isTrue);
      expect(loanIsBorrower(item, _owner), isFalse);
      expect(loanIsBorrower(item, null), isFalse);
    });
  });

  group('not returned', () {
    final due = DateTime.utc(2027, 1, 20, 12);
    final issued = interaction(stage: loanIssuedStage, returnDueAt: due);

    test('the mark opens the configured wait after the deadline', () {
      expect(
        loanNotReturnedFrom(issued, wait: config.notReturnedAfter),
        due.add(const Duration(days: 3)),
      );
      expect(
        loanNotReturnedFrom(interaction(), wait: config.notReturnedAfter),
        isNull,
      );
      expect(
        loanNotReturnedFrom(
          interaction(stage: loanIssuedStage),
          wait: config.notReturnedAfter,
        ),
        isNull,
      );
    });

    test('the mark is closed before the first allowed moment', () {
      withClock(Clock(() => due.add(const Duration(days: 2))), () {
        expect(
          loanNotReturnedOpen(issued, wait: config.notReturnedAfter),
          isFalse,
        );
      });
      withClock(Clock(() => due.add(const Duration(days: 3))), () {
        expect(
          loanNotReturnedOpen(issued, wait: config.notReturnedAfter),
          isTrue,
        );
      });
      withClock(Clock(() => due.add(const Duration(days: 5))), () {
        expect(
          loanNotReturnedOpen(issued, wait: config.notReturnedAfter),
          isTrue,
        );
      });
    });

    test('the threshold follows the configuration', () {
      withClock(Clock(() => due.add(const Duration(days: 1))), () {
        expect(
          loanNotReturnedOpen(issued, wait: const Duration(days: 1)),
          isTrue,
        );
        expect(
          loanNotReturnedOpen(issued, wait: const Duration(days: 7)),
          isFalse,
        );
      });
    });

    test('only the loan reason is the not-returned mark', () {
      expect(loanNoShowIsNotReturned(noShow()), isFalse);
      expect(
        loanNoShowIsNotReturned(
          noShow(marks: [markJson(reason: 'meeting_missed')]),
        ),
        isFalse,
      );
      expect(
        loanNoShowIsNotReturned(
          noShow(
            marks: [
              markJson(),
              markJson(reason: 'meeting_missed'),
            ],
          ),
        ),
        isTrue,
      );
    });
  });

  group('keys', () {
    test('a repeated intent keeps its key and a new one gets another', () {
      var next = 0;
      final keys = LoanKeys(generate: () => 'key-${++next}');
      final first = keys.of('not-returned');
      expect(keys.of('not-returned'), first);
      expect(keys.of('return'), isNot(first));
      expect(keys.of('not-returned'), isNot(first));
      expect(next, 3);
    });

    test('a successful intent forgets its key', () {
      var next = 0;
      final keys = LoanKeys(generate: () => 'key-${++next}');
      final first = keys.of('not-returned');
      keys.done('not-returned');
      expect(keys.of('not-returned'), isNot(first));
      expect(next, 2);
    });

    test('a completion of another intent keeps the current key', () {
      var next = 0;
      final keys = LoanKeys(generate: () => 'key-${++next}');
      final first = keys.of('not-returned');
      keys.done('dispute');
      expect(keys.of('not-returned'), first);
    });

    test('the mutation options carry the key', () {
      final options = loanMutationOptions('key-1');
      expect(options.headers, {'Idempotency-Key': 'key-1'});
    });
  });

  group('failure messages', () {
    test('an invalid period names the configured maximum', () {
      expect(
        loanFailureMessage(
          _l,
          problem('listing_loan_period_invalid', status: 422),
          config: config,
        ),
        _l.loanPeriodInvalid(90),
      );
    });

    test('a too early mark shows the moment the server named', () {
      expect(
        loanFailureMessage(
          _l,
          problem(
            'loan_not_returned_too_early',
            extra: {'available_at': '2027-01-23T12:00:00Z'},
          ),
          config: config,
          cityTime: (instant) => 'CITY ${instant.toIso8601String()}',
        ),
        _l.loanNotReturnedTooEarly('CITY 2027-01-23T12:00:00.000Z'),
      );
      expect(
        loanFailureMessage(
          _l,
          problem('loan_not_returned_too_early'),
          config: config,
        ),
        _l.loanNotReturnedLater,
      );
    });

    test('owner-only and issued-only refusals are explained', () {
      expect(
        loanFailureMessage(
          _l,
          problem('loan_not_returned_forbidden', status: 403),
          config: config,
        ),
        _l.loanNotReturnedForbidden,
      );
      expect(
        loanFailureMessage(
          _l,
          problem('loan_not_returned_unavailable'),
          config: config,
        ),
        _l.loanNotReturnedUnavailable,
      );
    });

    test('an unknown failure falls back to its general message', () {
      expect(
        loanFailureMessage(_l, const NetworkFailure(), config: config),
        _l.errorNetwork,
      );
    });

    test('a refused dispute is explained', () {
      for (final (code, status, message) in [
        ('no_show_closed', 409, _l.loanDisputeClosed),
        ('no_show_state_conflict', 409, _l.loanDisputeClosed),
        ('no_show_unavailable', 409, _l.loanNoShowUnavailable),
        ('no_show_forbidden', 403, _l.loanDisputeForbidden),
      ]) {
        expect(
          loanNoShowFailureMessage(
            _l,
            problem(code, status: status),
            reasonMaxLength: 500,
          ),
          message,
        );
      }
      expect(
        loanNoShowFailureMessage(
          _l,
          problem('no_show_reason_invalid', status: 422),
          reasonMaxLength: 500,
        ),
        _l.loanDisputeReasonInvalid(500),
      );
    });
  });

  group('dispute reason', () {
    test('an empty reason is refused before it is sent', () {
      expect(
        loanDisputeReasonError(_l, '   ', reasonMaxLength: 500),
        _l.loanDisputeReasonRequired,
      );
    });

    test('a reason longer than the configured limit is refused', () {
      expect(
        loanDisputeReasonError(_l, 'x' * 501, reasonMaxLength: 500),
        _l.loanDisputeReasonInvalid(500),
      );
    });

    test('a usable reason passes', () {
      expect(
        loanDisputeReasonError(_l, 'Returned it late', reasonMaxLength: 500),
        isNull,
      );
    });
  });

  group('config', () {
    test('the defaults of appendix 4 are used', () {
      final config = LoanConfig.fromEnvironment();
      expect(config.maxPeriodDays, 90);
      expect(config.notReturnedAfter, const Duration(days: 3));
    });

    test('a period must last at least a day', () {
      expect(
        () => LoanConfig(maxPeriodDays: 0, notReturnedAfter: Duration.zero),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  test('a loan is a feed kind and has its own name', () {
    expect(FeedKind.fromApi('loan'), FeedKind.loan);
    expect(listingKindName(_l, loanKind), _l.listingKindLoan);
  });

  test('the deadline is shown in the zone of the city', () {
    final text = loanCityTime(
      _l,
      DateTime.utc(2027, 1, 20, 12),
      timezone: 'Europe/Moscow',
      city: 'Moscow',
    );
    expect(text, contains('1/20/2027, 15:00'));
  });
}
