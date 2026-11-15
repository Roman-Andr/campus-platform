import 'dart:ui' show Locale;

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/api/mutation_keys.dart';
import 'package:campus/src/core/l10n/generated/app_localizations.dart';
import 'package:campus/src/features/listings/application/no_show.dart';
import 'package:campus/src/features/listings/domain/no_show.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fixtures.dart';

const authorId = '01890a5d-ac96-774b-bcce-b302099a8058';
const participantId = '01890a5d-ac96-774b-bcce-b302099a8060';

Map<String, Object?> meetingJson({String? scheduledAt}) => {
  'id': 'meeting-1',
  'version': 1,
  'status': 'scheduled',
  'scheduled_at': scheduledAt,
  'location': 'Library',
  'online': false,
  'scheduled_by_id': authorId,
  'proposed_at': null,
  'proposed_location': null,
  'proposed_by_id': null,
};

Map<String, Object?> interactionJson({
  String status = 'accepted',
  Map<String, Object?>? meeting,
}) => {
  'id': 'request-1',
  'listing_id': 'listing-1',
  'participant_name': 'Petr Petrov',
  'participant_id': participantId,
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'status': status,
  'meeting': meeting,
};

InteractionOutput interaction({
  String status = 'accepted',
  Map<String, Object?>? meeting,
}) => InteractionOutput.fromJson(
  interactionJson(status: status, meeting: meeting),
);

Map<String, Object?> markJson({
  String id = 'mark-1',
  String kind = 'personal',
  String status = 'counted',
  String? reporter = authorId,
  String subject = participantId,
  String? reason = 'Nobody came',
  String? createdAt,
  String? disputedAt,
  String? removedAt,
}) => {
  'id': id,
  'kind': kind,
  'status': status,
  'reporter_id': reporter,
  'subject_id': subject,
  'reason': reason,
  'created_at': createdAt ?? '2026-11-20T12:00:00Z',
  'disputed_at': disputedAt,
  'removed_at': removedAt,
};

Map<String, Object?> noShowJson({
  String status = 'accepted',
  String basis = 'unmarked',
  List<Map<String, Object?>>? marks,
  Map<String, Object?>? dispute,
  String? noShowAt,
  String? markFrom = '2026-11-21T12:00:00Z',
  String? autoAfter = '2026-11-27T12:00:00Z',
  bool canMark = true,
}) => {
  'listing_id': 'listing-1',
  'interaction_id': 'request-1',
  'status': status,
  'basis': basis,
  'marks': marks ?? const <Object?>[],
  'dispute': dispute,
  'no_show_at': noShowAt,
  'mark_from': markFrom,
  'auto_after': autoAfter,
  'can_mark': canMark,
  'server_time': '2026-11-21T12:00:00Z',
};

NoShowOutput noShow({
  String status = 'accepted',
  String basis = 'unmarked',
  List<Map<String, Object?>>? marks,
  Map<String, Object?>? dispute,
  String? noShowAt,
  String? markFrom = '2026-11-21T12:00:00Z',
  String? autoAfter = '2026-11-27T12:00:00Z',
  bool canMark = true,
}) => NoShowOutput.fromJson(
  noShowJson(
    status: status,
    basis: basis,
    marks: marks,
    dispute: dispute,
    noShowAt: noShowAt,
    markFrom: markFrom,
    autoAfter: autoAfter,
    canMark: canMark,
  ),
);

Map<String, Object?> disputeJson({
  String status = 'open',
  String? resolution,
}) => {
  'id': 'dispute-1',
  'status': status,
  'opened_at': '2026-11-20T13:00:00Z',
  'resolved_at': status == 'resolved' ? '2026-11-20T14:00:00Z' : null,
  'resolution': resolution,
};

Map<String, Object?> eventNoShowJson({
  int registered = 4,
  int votes = 0,
  int threshold = 2,
  bool notHeld = false,
  Map<String, Object?>? organizerMark,
  Map<String, Object?>? dispute,
  String? disputeDeadline,
  List<Map<String, Object?>>? participantMarks,
  String? voteOpensAt = '2026-11-20T20:00:00Z',
  String? voteClosesAt = '2026-11-27T20:00:00Z',
  bool canVote = true,
  bool canDispute = false,
  bool voted = false,
}) => {
  'listing_id': 'event-1',
  'organizer_id': authorId,
  'registered': registered,
  'votes': votes,
  'threshold': threshold,
  'not_held': notHeld,
  'organizer_mark': organizerMark,
  'dispute': dispute,
  'dispute_deadline': disputeDeadline,
  'participant_marks': participantMarks ?? const <Object?>[],
  'vote_opens_at': voteOpensAt,
  'vote_closes_at': voteClosesAt,
  'can_vote': canVote,
  'can_dispute': canDispute,
  'voted': voted,
  'server_time': '2026-11-21T12:00:00Z',
};

EventNoShowOutput eventNoShow({
  int registered = 4,
  int votes = 0,
  int threshold = 2,
  bool notHeld = false,
  Map<String, Object?>? organizerMark,
  Map<String, Object?>? dispute,
  String? disputeDeadline,
  List<Map<String, Object?>>? participantMarks,
  String? voteOpensAt = '2026-11-20T20:00:00Z',
  String? voteClosesAt = '2026-11-27T20:00:00Z',
  bool canVote = true,
  bool canDispute = false,
  bool voted = false,
}) => EventNoShowOutput.fromJson(
  eventNoShowJson(
    registered: registered,
    votes: votes,
    threshold: threshold,
    notHeld: notHeld,
    organizerMark: organizerMark,
    dispute: dispute,
    disputeDeadline: disputeDeadline,
    participantMarks: participantMarks,
    voteOpensAt: voteOpensAt,
    voteClosesAt: voteClosesAt,
    canVote: canVote,
    canDispute: canDispute,
    voted: voted,
  ),
);

ProblemFailure problemFailure(
  String codeValue, {
  int status = 409,
  DateTime? availableAt,
}) => ProblemFailure(
  Problem(
    type: 'urn:problem:campus:$codeValue',
    title: 'Server title',
    status: status,
    code: ProblemCodeKnown(
      ProblemCodeValue.values.firstWhere((value) => value.value == codeValue),
    ),
    availableAt: availableAt,
  ),
);

String Function(DateTime instant) moscowTime(AppLocalizations l) =>
    noShowCityTime(ListingOutput.fromJson(listingJson()), l);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });
  final l = lookupAppLocalizations(const Locale('en'));

  group('the no-show action', () {
    test('is offered for an accepted personal interaction with a meeting', () {
      final item = interaction(
        meeting: meetingJson(scheduledAt: '2026-11-20T12:00:00Z'),
      );
      expect(noShowAvailable('giveaway', item), isTrue);
      expect(noShowAvailable('help', item), isTrue);
      expect(noShowAvailable('skill', item), isTrue);
      expect(noShowAvailable('exchange', item), isTrue);
    });

    test('is not offered for an event, a purchase or a publication', () {
      final item = interaction(
        meeting: meetingJson(scheduledAt: '2026-11-20T12:00:00Z'),
      );
      expect(noShowAvailable('event', item), isFalse);
      expect(noShowAvailable('purchase', item), isFalse);
      expect(noShowAvailable('publication', item), isFalse);
    });

    test('waits for an agreed meeting', () {
      expect(noShowAvailable('giveaway', interaction()), isFalse);
      expect(
        noShowAvailable('giveaway', interaction(meeting: meetingJson())),
        isFalse,
      );
    });

    test('stays for a marked interaction to answer it', () {
      expect(
        noShowAvailable(
          'giveaway',
          interaction(status: 'no_show', meeting: meetingJson()),
        ),
        isTrue,
      );
      expect(
        noShowAvailable(
          'giveaway',
          interaction(status: 'completed', meeting: meetingJson()),
        ),
        isFalse,
      );
      expect(
        noShowAvailable(
          'giveaway',
          interaction(status: 'pending', meeting: meetingJson()),
        ),
        isFalse,
      );
    });
  });

  group('the mark window', () {
    final state = noShow();

    test('opens at mark_from and closes at auto_after', () {
      expect(
        noShowPhase(state, now: DateTime.utc(2026, 11, 21, 11, 59)),
        NoShowPhase.before,
      );
      expect(
        noShowPhase(state, now: DateTime.utc(2026, 11, 21, 12)),
        NoShowPhase.open,
      );
      expect(
        noShowPhase(state, now: DateTime.utc(2026, 11, 27, 11, 59)),
        NoShowPhase.open,
      );
      expect(
        noShowPhase(state, now: DateTime.utc(2026, 11, 27, 12)),
        NoShowPhase.closed,
      );
    });

    test('has no bounds without an agreed meeting', () {
      final unbounded = noShow(markFrom: null, autoAfter: null);
      expect(noShowPhase(unbounded), NoShowPhase.unavailable);
    });
  });

  group('the state of the marks', () {
    test('counted marks come before suspended and removed ones', () {
      final state = noShow(
        status: 'no_show',
        basis: 'mutual_dispute',
        marks: [
          markJson(id: 'removed', status: 'removed', removedAt: '2026-11-21'),
          markJson(id: 'counted'),
          markJson(id: 'disputed', status: 'disputed'),
        ],
        dispute: disputeJson(),
      );
      expect(noShowSortedMarks(state).map((mark) => mark.id), [
        'counted',
        'disputed',
        'removed',
      ]);
    });

    test('a mutual allegation is shown as an open dispute', () {
      final state = noShow(
        status: 'no_show',
        basis: 'mutual_dispute',
        marks: [markJson(status: 'disputed')],
        dispute: disputeJson(),
      );
      expect(noShowDisputeOpen(state), isTrue);
      expect(noShowBasisName(l, state), 'Mutual marks: under dispute');
    });

    test('a decided dispute is closed', () {
      final state = noShow(
        status: 'no_show',
        basis: 'mutual_dispute',
        marks: [markJson(status: 'disputed')],
        dispute: disputeJson(status: 'resolved'),
      );
      expect(noShowDisputeOpen(state), isFalse);
    });

    test('a late QR lift is recognized from the removed marks', () {
      final state = noShow(
        status: 'completed',
        basis: 'completed',
        marks: [markJson(status: 'removed', removedAt: '2026-11-21T13:00:00Z')],
        dispute: disputeJson(status: 'resolved', resolution: 'late_qr'),
      );
      expect(noShowLiftedAfterQr(state), isTrue);
      expect(noShowBasisName(l, state), 'The meeting took place');
    });

    test('a completed interaction without marks is not a lift', () {
      expect(
        noShowLiftedAfterQr(
          noShow(status: 'completed', basis: 'completed', canMark: false),
        ),
        isFalse,
      );
    });

    test('a counted mark is not a lift', () {
      expect(
        noShowLiftedAfterQr(
          noShow(
            status: 'no_show',
            basis: 'marked',
            marks: [markJson()],
            canMark: false,
          ),
        ),
        isFalse,
      );
    });

    test('names and statuses are read from the viewer point of view', () {
      final mine = noShowMarkOutput();
      expect(noShowReporterName(l, mine, viewerId: participantId), 'You');
      expect(
        noShowReporterName(l, mine, viewerId: authorId, otherName: 'Petr'),
        'Petr',
      );
      expect(
        noShowSubjectName(l, mine, viewerId: authorId, otherName: 'Petr'),
        'Petr',
      );
      expect(noShowSubjectName(l, mine, viewerId: participantId), 'you');
      expect(l.noShowMarkChargedTo('Petr'), 'Charged to: Petr');
      expect(
        noShowReporterName(
          l,
          noShowMarkOutput(reporter: null),
          viewerId: participantId,
        ),
        'an automatic rule',
      );
      expect(noShowMarkStatusName(l, mine), 'counts');
      expect(
        noShowMarkStatusName(l, noShowMarkOutput(status: 'disputed')),
        'suspended by a dispute',
      );
      expect(
        noShowMarkStatusName(l, noShowMarkOutput(status: 'removed')),
        'removed',
      );
    });
  });

  group('messages of a failed mark', () {
    test('a too-early refusal names the opening instant in the city', () {
      final message = noShowFailureMessage(
        l,
        problemFailure(
          'no_show_too_early',
          availableAt: DateTime.utc(2026, 11, 21, 9),
        ),
        cityTime: moscowTime(l),
      );
      expect(message, startsWith('A no-show can be marked from '));
      // Europe/Moscow is three hours ahead of UTC in November.
      expect(message, contains('12:00'));
    });

    test('a too-early refusal without an instant stays generic', () {
      expect(
        noShowFailureMessage(l, problemFailure('no_show_too_early')),
        'The meeting time is still recent: a no-show cannot be marked yet.',
      );
    });

    test('a closed window explains itself', () {
      expect(
        noShowFailureMessage(l, problemFailure('no_show_closed')),
        'No-show marking is closed: the interaction has already become '
        '“did not take place”.',
      );
    });

    test('a foreign interaction is refused', () {
      expect(
        noShowFailureMessage(
          l,
          problemFailure('no_show_forbidden', status: 403),
        ),
        'Only the two participants of the interaction can mark a no-show.',
      );
    });

    test('an unsupported interaction and a changed state have messages', () {
      expect(
        noShowFailureMessage(l, problemFailure('no_show_unavailable')),
        'A no-show cannot be marked for this interaction.',
      );
      expect(
        noShowFailureMessage(l, problemFailure('no_show_state_conflict')),
        'The interaction can no longer be marked.',
      );
      expect(
        noShowFailureMessage(l, problemFailure('no_show_reason_invalid')),
        'The reason is empty or too long.',
      );
      expect(
        noShowFailureMessage(l, problemFailure('loan_no_show_unavailable')),
        'A loan cannot be marked as a no-show: the item was handed over. '
        'After the return deadline its owner marks it not returned.',
      );
    });
  });

  group('the event result', () {
    test('the vote window opens with the end and closes a week later', () {
      final state = eventNoShow();
      expect(
        eventNoShowPhase(state, now: DateTime.utc(2026, 11, 20, 19, 59)),
        EventNoShowPhase.before,
      );
      expect(
        eventNoShowPhase(state, now: DateTime.utc(2026, 11, 20, 20)),
        EventNoShowPhase.open,
      );
      expect(
        eventNoShowPhase(state, now: DateTime.utc(2026, 11, 27, 20)),
        EventNoShowPhase.open,
      );
      expect(
        eventNoShowPhase(state, now: DateTime.utc(2026, 11, 27, 20, 1)),
        EventNoShowPhase.closed,
      );
    });

    test('an event without an end has no vote window', () {
      expect(
        eventNoShowPhase(eventNoShow(voteOpensAt: null, voteClosesAt: null)),
        EventNoShowPhase.unavailable,
      );
    });

    test('the dispute of a vote charge is open or closed', () {
      final charged = eventNoShow(
        notHeld: true,
        organizerMark: markJson(
          reporter: null,
          subject: authorId,
          kind: 'event_vote',
          status: 'disputed',
        ),
        dispute: disputeJson(),
      );
      expect(eventNoShowDisputeOpen(charged), isTrue);
      expect(
        eventNoShowDisputeOpen(
          eventNoShow(
            notHeld: true,
            organizerMark: markJson(kind: 'event_vote'),
            dispute: disputeJson(status: 'resolved'),
          ),
        ),
        isFalse,
      );
    });

    test('refusals of the vote and of the dispute have messages', () {
      expect(
        eventNoShowFailureMessage(
          l,
          problemFailure('event_no_show_not_registered', status: 403),
        ),
        'Only a registered participant can vote.',
      );
      expect(
        eventNoShowFailureMessage(
          l,
          problemFailure('event_no_show_vote_closed'),
        ),
        'Voting is closed.',
      );
      expect(
        eventNoShowFailureMessage(
          l,
          problemFailure('event_no_show_dispute_closed'),
        ),
        'The dispute is already closed.',
      );
      expect(
        eventNoShowFailureMessage(
          l,
          problemFailure('event_no_show_dispute_forbidden', status: 403),
        ),
        'Only the organiser can dispute the no-show of their event.',
      );
      expect(
        eventNoShowFailureMessage(
          l,
          problemFailure('event_no_show_dispute_unavailable'),
        ),
        'There is no charged no-show to dispute.',
      );
    });
  });

  group('configuration and keys', () {
    test('the defaults follow Appendix 4 of the specification', () {
      final config = NoShowConfig.fromEnvironment();
      expect(config.markAfter, const Duration(hours: 24));
      expect(config.reasonMaxLength, 500);
    });

    test('a reason limit cannot be empty and a window cannot be negative', () {
      expect(
        () => NoShowConfig(
          markAfter: const Duration(hours: -1),
          reasonMaxLength: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => NoShowConfig(markAfter: Duration.zero, reasonMaxLength: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a repeat of an intent keeps the idempotency key', () {
      var counter = 0;
      final keys = MutationKeys(generate: () => 'key-${++counter}');
      expect(keys.of('no-show:request-1:no one came'), 'key-1');
      expect(keys.of('no-show:request-1:no one came'), 'key-1');
      expect(keys.of('no-show:request-1:another reason'), 'key-2');
      keys.done('no-show:request-1:another reason');
      expect(keys.of('no-show:request-1:another reason'), 'key-3');
    });
  });
}

NoShowMarkOutput noShowMarkOutput({
  String kind = 'personal',
  String status = 'counted',
  String? reporter = participantId,
  String subject = participantId,
}) => NoShowMarkOutput.fromJson(
  markJson(kind: kind, status: status, reporter: reporter, subject: subject),
);
