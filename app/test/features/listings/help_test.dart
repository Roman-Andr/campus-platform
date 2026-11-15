import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_ru.dart';
import 'package:campus/src/features/listings/application/help_config.dart';
import 'package:campus/src/features/listings/domain/feed.dart';
import 'package:campus/src/features/listings/domain/help.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'help_fixtures.dart';

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  ListingOutput listing({
    String kind = 'help',
    String status = 'active',
    String author = 'author',
  }) => ListingOutput.fromJson(
    listingJson(kind: kind, status: status, author: author),
  );

  InteractionOutput application({
    String status = 'pending',
    bool executor = false,
    String participant = 'participant',
  }) => InteractionOutput.fromJson(
    helpInteractionJson(
      status: status,
      executor: executor,
      participant: participant,
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

  group('help request', () {
    test('is recognized by its kind', () {
      expect(isHelpRequest(listing()), isTrue);
      expect(isHelpRequest(listing(kind: 'giveaway')), isFalse);
      expect(helpKind, 'help');
      expect(FeedKind.fromApi('help'), FeedKind.help);
    });

    test('a relevance deadline stays inside the listing lifetime', () {
      final now = DateTime.utc(2026, 11, 15, 12);
      const lifetime = Duration(days: 30);
      expect(
        helpDeadlineIssue(
          now.subtract(const Duration(seconds: 1)),
          lifetime: lifetime,
          now: now,
        ),
        HelpDeadlineIssue.past,
      );
      expect(
        helpDeadlineIssue(now, lifetime: lifetime, now: now),
        HelpDeadlineIssue.past,
      );
      expect(
        helpDeadlineIssue(
          now.add(const Duration(days: 7)),
          lifetime: lifetime,
          now: now,
        ),
        isNull,
      );
      expect(
        helpDeadlineIssue(
          now.add(const Duration(days: 30)),
          lifetime: lifetime,
          now: now,
        ),
        isNull,
      );
      expect(
        helpDeadlineIssue(
          now.add(const Duration(days: 30, seconds: 1)),
          lifetime: lifetime,
          now: now,
        ),
        HelpDeadlineIssue.beyondLifetime,
      );
    });

    test('the deadline problem is localized', () {
      expect(
        helpDeadlineError(en, HelpDeadlineIssue.past, lifetimeDays: 30),
        'Choose a future deadline.',
      );
      expect(
        helpDeadlineError(
          ru,
          HelpDeadlineIssue.beyondLifetime,
          lifetimeDays: 30,
        ),
        'Срок не может быть больше срока жизни объявления (30 дн.).',
      );
    });

    test('the author and an active applicant cannot respond again', () {
      final request = listing();
      expect(helpCanRespond(request, 'author', const []), isFalse);
      expect(helpCanRespond(request, 'participant', const []), isTrue);
      expect(helpCanRespond(request, null, const []), isFalse);
      expect(helpCanRespond(request, 'participant', [application()]), isFalse);
      expect(
        helpCanRespond(request, 'participant', [
          application(status: 'accepted', executor: true),
        ]),
        isFalse,
      );
      expect(
        helpCanRespond(request, 'participant', [
          application(status: 'rejected'),
        ]),
        isTrue,
      );
      expect(
        helpCanRespond(listing(status: 'busy'), 'participant', const []),
        isFalse,
      );
      expect(
        helpCanRespond(listing(kind: 'giveaway'), 'participant', const []),
        isFalse,
      );
    });

    test('the reserve and the executor are recognized', () {
      final busy = listing(status: 'busy');
      final pending = application();
      final accepted = application(status: 'accepted', executor: true);
      expect(helpIsReserve(busy, pending), isTrue);
      expect(helpIsReserve(listing(), pending), isFalse);
      expect(helpIsReserve(busy, accepted), isFalse);
      expect(helpIsExecutor(accepted), isTrue);
      expect(helpIsExecutor(pending), isFalse);
    });

    test('configuration rejects a zero lifetime', () {
      expect(
        () => HelpConfig(listingLifetimeDays: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        const HelpConfig(listingLifetimeDays: 30).listingLifetime,
        const Duration(days: 30),
      );
    });
  });

  group('Problem Details', () {
    test('help failures have localized messages', () {
      expect(
        helpFailureMessage(en, problem(422, 'help_deadline_invalid')),
        'The deadline must be in the future and no later than the listing lifetime.',
      );
      expect(
        helpFailureMessage(ru, problem(409, 'listing_conflict')),
        'Запрос уже изменился. Обновите объявление.',
      );
      expect(
        helpFailureMessage(en, problem(403, 'listing_forbidden')),
        'You cannot act on this help request.',
      );
      expect(
        helpFailureMessage(en, problem(404, 'not_found')),
        'The listing is unavailable. It may have been removed or access has changed.',
      );
    });
  });
}
