import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/features/listings/application/exchange.dart';
import 'package:campus/src/features/listings/domain/reservation.dart';
import 'package:campus/src/features/listings/presentation/status_labels.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';

Map<String, Object?> meetingJson({
  String? scheduledAt,
  String? proposedAt,
  int version = 1,
}) => {
  'id': 'meeting-1',
  'version': version,
  'status': proposedAt == null ? 'scheduled' : 'proposed',
  'scheduled_at': scheduledAt,
  'location': 'Library',
  'online': false,
  'scheduled_by_id': 'author',
  'proposed_at': proposedAt,
  'proposed_location': proposedAt == null ? null : 'Cafe',
  'proposed_by_id': proposedAt == null ? null : 'other',
};

Map<String, Object?> interactionJson({
  String status = 'accepted',
  String? reservationDueAt,
  String? offerDescription,
  Map<String, Object?>? meeting,
}) => {
  'id': 'interaction-1',
  'listing_id': 'listing-1',
  'participant_id': userJson['id'],
  'participant_name': 'Ivan Ivanov',
  'status': status,
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'reservation_due_at': ?reservationDueAt,
  'offer_description': ?offerDescription,
  'meeting': meeting,
};

InteractionOutput interaction({
  String status = 'accepted',
  String? reservationDueAt,
  String? offerDescription,
  Map<String, Object?>? meeting,
}) => InteractionOutput.fromJson(
  interactionJson(
    status: status,
    reservationDueAt: reservationDueAt,
    offerDescription: offerDescription,
    meeting: meeting,
  ),
);

ProblemFailure problem(int status, String code) => ProblemFailure(
  Problem.fromJson({
    'type': 'urn:problem:campus:$code',
    'title': 'Title',
    'status': status,
    'code': code,
    'request_id': 'req-1',
  }),
);

void main() {
  final en = AppLocalizationsEn();
  final due = DateTime.utc(2027, 1, 15, 15);

  group('reservation hold', () {
    test('is open only for an accepted hold without a meeting', () {
      final open = interaction(reservationDueAt: due.toIso8601String());
      expect(reservationIsOpen(open), isTrue);
      expect(reservationEndsAtMeeting(open), isFalse);
      expect(
        reservationIsOpen(
          interaction(
            reservationDueAt: due.toIso8601String(),
            status: 'pending',
          ),
        ),
        isFalse,
      );
      expect(reservationIsOpen(interaction()), isFalse);
    });

    test('a scheduled meeting extends the hold to its time', () {
      final meeting = meetingJson(
        scheduledAt: due.add(const Duration(days: 2)).toIso8601String(),
      );
      final item = interaction(
        reservationDueAt: due.toIso8601String(),
        meeting: meeting,
      );
      expect(reservationIsOpen(item), isFalse);
      expect(reservationEndsAtMeeting(item), isTrue);
    });

    test('a pending meeting proposal does not stop the hold', () {
      final meeting = meetingJson(
        proposedAt: due.add(const Duration(days: 1)).toIso8601String(),
      );
      final item = interaction(
        reservationDueAt: due.toIso8601String(),
        meeting: meeting,
      );
      expect(reservationIsOpen(item), isTrue);
    });

    test('the time left never goes below zero', () {
      final item = interaction(reservationDueAt: due.toIso8601String());
      expect(
        reservationLeft(item, now: DateTime.utc(2027, 1, 15, 13)),
        const Duration(hours: 2),
      );
      expect(
        reservationLeft(item, now: DateTime.utc(2027, 1, 16)),
        Duration.zero,
      );
      expect(
        reservationLeft(interaction(), now: DateTime.utc(2027, 1, 15)),
        Duration.zero,
      );
    });
  });

  group('hold time wording', () {
    test('shows hours and minutes, then minutes only', () {
      expect(
        reservationTimeLeft(en, const Duration(hours: 46, minutes: 12)),
        'Hold ends in 46 h 12 min',
      );
      expect(
        reservationTimeLeft(en, const Duration(hours: 1)),
        'Hold ends in 1 h 0 min',
      );
      expect(
        reservationTimeLeft(en, const Duration(minutes: 30)),
        'Hold ends in 30 min',
      );
    });

    test('has its own wording for the first and the last minute', () {
      expect(
        reservationTimeLeft(en, const Duration(seconds: 20)),
        'The hold ends in less than a minute.',
      );
      expect(reservationTimeLeft(en, Duration.zero), 'The hold has ended.');
      expect(
        reservationTimeLeft(en, const Duration(seconds: -5)),
        'The hold has ended.',
      );
    });
  });

  group('exchange offers', () {
    test('only a pending or accepted offer is the active one', () {
      final pending = interaction(
        status: 'pending',
        offerDescription: 'A chair',
      );
      final accepted = interaction(offerDescription: 'A lamp');
      final rejected = interaction(
        status: 'rejected',
        offerDescription: 'A mug',
      );
      expect(activeExchangeOffer([rejected])?.offerDescription, isNull);
      expect(
        activeExchangeOffer([rejected, pending])?.offerDescription,
        'A chair',
      );
      expect(
        activeExchangeOffer([accepted, pending])?.offerDescription,
        'A lamp',
      );
    });

    test('the latest offer is shown even when it lost', () {
      final cancelled = interaction(
        status: 'cancelled',
        offerDescription: 'A chair',
      );
      final rejected = interaction(
        status: 'rejected',
        offerDescription: 'A lamp',
      );
      expect(latestExchangeOffer(const []), isNull);
      expect(
        latestExchangeOffer([cancelled, rejected])?.offerDescription,
        'A lamp',
      );
    });

    test('describes the item or asks for a description', () {
      expect(exchangeOfferError(en, null), 'Describe what you offer.');
      expect(exchangeOfferError(en, '   '), 'Describe what you offer.');
      expect(exchangeOfferError(en, ' A chair '), isNull);
    });

    test('explains the conflicts of the server', () {
      expect(
        exchangeFailureMessage(en, problem(409, 'exchange_offer_duplicate')),
        en.exchangeOfferDuplicate,
      );
      expect(
        exchangeFailureMessage(en, problem(422, 'exchange_offer_invalid')),
        en.exchangeOfferInvalid,
      );
      expect(
        exchangeFailureMessage(en, problem(409, 'listing_conflict')),
        en.listingTransitionConflict,
      );
      expect(
        exchangeFailureMessage(en, problem(404, 'not_found')),
        en.listingUnavailable,
      );
      expect(
        exchangeFailureMessage(en, problem(403, 'forbidden')),
        en.errorForbidden,
      );
    });
  });

  test('reasons of expired and lost offers are labelled', () {
    expect(
      interactionReasonLabel(en, 'reservation_expired'),
      en.reservationExpiredByDeadline,
    );
    expect(
      interactionReasonLabel(en, 'another_offer_accepted'),
      en.exchangeOfferRejectedAnother,
    );
    expect(
      interactionReasonLabel(en, 'author_timeout'),
      en.reservationRejectedTimeout,
    );
    expect(interactionReasonLabel(en, 'Я передумал'), 'Я передумал');
    expect(interactionReasonLabel(en, null), isNull);
    expect(interactionReasonLabel(en, ''), isNull);
    expect(
      interactionRejectionLabel(en, 'future_reason'),
      en.reservationRejectedOther,
    );
    expect(
      interactionRejectionLabel(en, 'another_offer_accepted'),
      en.exchangeOfferRejectedAnother,
    );
    expect(interactionRejectionLabel(en, null), isNull);
  });

  test('the clock decides the hold time by default', () {
    final now = DateTime.utc(2027, 1, 15, 12);
    final item = interaction(
      reservationDueAt: now.add(const Duration(hours: 6)).toIso8601String(),
    );
    withClock(
      Clock.fixed(now),
      () => expect(reservationLeft(item), const Duration(hours: 6)),
    );
  });
}
