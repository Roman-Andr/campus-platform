import 'dart:ui' show Locale;

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations.dart';
import 'package:campus/src/features/reviews/domain/review.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fixtures.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });
  final l = lookupAppLocalizations(const Locale('en'));
  final ru = lookupAppLocalizations(const Locale('ru'));
  String cityTime(DateTime instant) =>
      reviewTimeLabel(l, instant, timezone: 'Europe/Moscow');

  group('the entry card of a review', () {
    test('is offered only after the interaction is completed', () {
      expect(
        reviewAvailable(
          'giveaway',
          InteractionOutput.fromJson(interactionJson()),
        ),
        isTrue,
      );
      expect(
        reviewAvailable(
          'giveaway',
          InteractionOutput.fromJson(
            interactionJson(status: 'accepted', completedAt: null),
          ),
        ),
        isFalse,
      );
    });

    test('is offered for every scenario that has reviews', () {
      final item = InteractionOutput.fromJson(interactionJson());
      for (final kind in [
        'giveaway',
        'exchange',
        'loan',
        'skill',
        'help',
        'event',
        'purchase',
      ]) {
        expect(reviewAvailable(kind, item), isTrue, reason: kind);
      }
      expect(reviewAvailable('publication', item), isFalse);
      expect(reviewAvailable('unknown', item), isFalse);
    });
  });

  group('the phase of a review', () {
    test('follows the flags of the server', () {
      expect(reviewPhaseOf(reviewState()), ReviewPhase.form);
      expect(
        reviewPhaseOf(
          reviewState(canReview: false, canEdit: true, mine: reviewJson()),
        ),
        ReviewPhase.editable,
      );
      expect(
        reviewPhaseOf(
          reviewState(
            canReview: false,
            mine: reviewJson(publishedAt: '2026-12-04T12:00:00Z'),
            revealed: true,
          ),
        ),
        ReviewPhase.revealed,
      );
      expect(
        reviewPhaseOf(reviewState(canReview: false, mine: reviewJson())),
        ReviewPhase.waiting,
      );
      expect(
        reviewPhaseOf(reviewState(canReview: false, eligible: false)),
        ReviewPhase.unavailable,
      );
      // A review hidden by a moderator is neither waiting nor editable.
      expect(
        reviewPhaseOf(
          reviewState(canReview: false, mine: reviewJson(hidden: true)),
        ),
        ReviewPhase.unavailable,
      );
    });

    test('reads the own and the revealed review apart', () {
      final state = reviewState(
        canReview: false,
        revealed: true,
        mine: reviewJson(),
        theirs: reviewJson(
          id: 'review-theirs',
          author: reviewParticipantId,
          authorName: 'Petr Petrov',
          reply: reviewReplyJson(),
        ),
      );
      expect(reviewMine(state)?.id, 'review-mine');
      final theirs = reviewTheirs(state);
      expect(theirs?.id, 'review-theirs');
      expect(reviewReplyOf(theirs!)?.text, 'Thanks, it was a pleasure.');
      expect(reviewMine(reviewState(theirs: reviewJson())), isNull);
      expect(reviewTheirs(reviewState()), isNull);
    });
  });

  group('the ready-made tags', () {
    test('are localized in both languages', () {
      expect(reviewTagName(l, 'punctual'), 'Punctual');
      expect(reviewTagName(l, 'item_as_described'), 'Item as described');
      expect(reviewTagName(ru, 'returned_on_time'), 'Вернули вовремя');
      expect(reviewTagName(ru, 'well_organized'), 'Хорошо организовано');
      expect(reviewTagNames(l, ['punctual', 'friendly']), [
        'Punctual',
        'Friendly',
      ]);
    });

    test('hide a code this build does not know behind a generic label', () {
      expect(reviewTagName(l, 'brand_new_code'), l.reviewTagOther);
      expect(reviewTagName(ru, 'brand_new_code'), ru.reviewTagOther);
    });
  });

  group('the waiting notice', () {
    test('names the end of the window in the city of the listing', () {
      final state = reviewState(
        canReview: false,
        mine: reviewJson(),
        windowClosesAt: '2026-11-21T09:00:00Z',
      );
      // 09:00 UTC is 12:00 in Moscow.
      expect(cityTime(state.windowClosesAt!), contains('12:00'));
    });
  });

  group('the reason of an unavailable review', () {
    test('is the missing completion first', () {
      expect(
        reviewUnavailableText(
          l,
          reviewState(
            canReview: false,
            eligible: false,
            completedAt: null,
            windowClosesAt: null,
          ),
          cityTime: cityTime,
        ),
        l.reviewUnavailableNotCompleted,
      );
    });

    test('is the closed window with its time in the city', () {
      final text = reviewUnavailableText(
        l,
        reviewState(
          canReview: false,
          eligible: false,
          windowClosesAt: '2026-11-01T12:00:00Z',
        ),
        cityTime: cityTime,
        now: DateTime.utc(2026, 11, 21, 12),
      );
      expect(text, contains('The review window closed at'));
      expect(text, contains('15:00'));
    });

    test('is the one-way rule of an event for its organiser', () {
      expect(
        reviewUnavailableText(
          l,
          reviewState(oneWay: true, canReview: false, eligible: false),
          cityTime: cityTime,
        ),
        l.reviewUnavailableOrganizer,
      );
    });

    test('is the moderator decision for a hidden own review', () {
      expect(
        reviewUnavailableText(
          l,
          reviewState(canReview: false, mine: reviewJson(hidden: true)),
          cityTime: cityTime,
        ),
        l.reviewHiddenByModerator,
      );
    });
  });

  group('the refusal of a review request', () {
    test('is localized for every review problem code', () {
      const codes = [
        'review_forbidden',
        'review_one_way',
        'review_unavailable',
        'review_window_closed',
        'review_exists',
        'review_published',
        'review_hidden',
        'review_rating_invalid',
        'review_tags_invalid',
        'review_text_invalid',
        'review_reply_exists',
        'review_reply_invalid',
      ];
      for (final code in codes) {
        final message = reviewFailureMessage(
          l,
          reviewProblem(code, status: 422),
        );
        expect(message, isNot(l.errorRequest), reason: code);
        expect(message, isNotEmpty, reason: code);
        // Both languages are complete: the Russian text is different.
        final russian = reviewFailureMessage(
          ru,
          reviewProblem(code, status: 422),
        );
        expect(russian, isNot(message), reason: code);
      }
    });

    test('hides a not revealed or hidden review behind a plain 404', () {
      expect(
        reviewFailureMessage(l, reviewProblem('not_found', status: 404)),
        l.reviewErrorNotFound,
      );
    });

    test('falls back to the shared message for a dropped connection', () {
      final failure = reviewFailureMessage(l, const NetworkFailure());
      expect(failure, l.errorNetwork);
    });
  });
}
