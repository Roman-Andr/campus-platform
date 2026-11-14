import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_ru.dart';
import 'package:campus/src/features/listings/application/lesson_config.dart';
import 'package:campus/src/features/listings/domain/skills.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'lesson_fixtures.dart';

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  ListingOutput listing({
    String kind = 'skill',
    String? direction = 'teach',
    String author = 'author',
  }) => ListingOutput.fromJson(
    listingJson(kind: kind, direction: direction, author: author),
  );

  InteractionOutput interaction({
    String status = 'pending',
    List<Map<String, Object?>> options = const [],
    String participant = 'participant',
  }) => InteractionOutput.fromJson(
    lessonInteractionJson(
      status: status,
      participant: participant,
      options: options,
    ),
  );

  LessonOptionOutput option({
    String id = 'option-1',
    String proposedBy = 'participant',
    String status = 'proposed',
  }) => LessonOptionOutput.fromJson(
    lessonOptionJson(id: id, proposedBy: proposedBy, status: status),
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

  group('skill listing', () {
    test('is recognized by its kind and direction', () {
      final skill = listing();
      expect(isSkillListing(skill), isTrue);
      expect(skillDirectionOf(skill), SkillDirection.teach);
      expect(skillDirectionLabel(en, SkillDirection.teach), 'I can teach');
      expect(skillDirectionLabel(ru, SkillDirection.learn), 'Хочу научиться');
      expect(isSkillListing(ListingOutput.fromJson(listingJson())), isFalse);
      expect(skillDirectionOf(ListingOutput.fromJson(listingJson())), isNull);
    });
  });

  group('lesson options', () {
    test(
      'the author answers the participant and the participant a counter',
      () {
        final skill = listing();
        final participantOption = option();
        final authorOption = option(proposedBy: 'author');
        final pending = interaction(options: [participantOption.toJson()]);

        expect(
          lessonOptionCanBeAccepted(
            pending,
            skill,
            participantOption,
            'author',
          ),
          isTrue,
        );
        expect(
          lessonOptionCanBeAccepted(
            pending,
            skill,
            participantOption,
            'participant',
          ),
          isFalse,
        );
        expect(
          lessonOptionCanBeAccepted(
            pending,
            skill,
            participantOption,
            'stranger',
          ),
          isFalse,
        );
        expect(
          lessonOptionCanBeAccepted(
            pending,
            skill,
            authorOption,
            'participant',
          ),
          isTrue,
        );
        expect(
          lessonOptionCanBeAccepted(pending, skill, authorOption, 'author'),
          isFalse,
        );
        expect(
          lessonOptionCanBeAccepted(
            interaction(
              status: 'accepted',
              options: [participantOption.toJson()],
            ),
            skill,
            participantOption,
            'author',
          ),
          isFalse,
        );
        expect(
          lessonOptionCanBeAccepted(
            pending,
            skill,
            option(status: 'declined'),
            'author',
          ),
          isFalse,
        );
        expect(
          lessonOptionCanBeAccepted(pending, skill, participantOption, null),
          isFalse,
        );
        expect(lessonHasAnswer(pending, skill, 'author'), isTrue);
        expect(lessonHasAnswer(pending, skill, 'participant'), isFalse);
      },
    );

    test('labels every status in RU and EN', () {
      expect(
        lessonOptionStatusLabel(en, LessonOptionStatus.proposed),
        'Awaiting response',
      );
      expect(
        lessonOptionStatusLabel(ru, LessonOptionStatus.proposed),
        'Ждёт ответа',
      );
      expect(
        lessonOptionStatusLabel(en, LessonOptionStatus.selected),
        'Selected',
      );
      expect(
        lessonOptionStatusLabel(ru, LessonOptionStatus.declined),
        'Отклонён',
      );
    });

    test('only the author counters, only while pending', () {
      final skill = listing();
      final pending = interaction(options: [option().toJson()]);
      expect(lessonCanCounter(pending, skill, 'author'), isTrue);
      expect(lessonCanCounter(pending, skill, 'participant'), isFalse);
      expect(
        lessonCanCounter(interaction(status: 'accepted'), skill, 'author'),
        isFalse,
      );
      expect(
        lessonCanCounter(
          pending,
          ListingOutput.fromJson(listingJson()),
          'author',
        ),
        isFalse,
      );
    });

    test('a lesson is repeated by both sides after it is scheduled', () {
      final skill = listing();
      final accepted = interaction(status: 'accepted');
      final completed = interaction(status: 'completed');
      expect(lessonCanRepeat(accepted, skill, 'author'), isTrue);
      expect(lessonCanRepeat(accepted, skill, 'participant'), isTrue);
      expect(lessonCanRepeat(completed, skill, 'participant'), isTrue);
      expect(lessonCanRepeat(interaction(), skill, 'author'), isFalse);
      expect(
        lessonCanRepeat(
          accepted,
          ListingOutput.fromJson(listingJson()),
          'author',
        ),
        isFalse,
      );
      expect(lessonCanRepeat(accepted, skill, 'stranger'), isFalse);
    });

    test('an active lesson hides the proposal button', () {
      expect(
        lessonHasActiveLesson([interaction(status: 'completed')]),
        isFalse,
      );
      expect(lessonHasActiveLesson([interaction()]), isTrue);
      expect(lessonHasActiveLesson([interaction(status: 'accepted')]), isTrue);
    });
  });

  group('lesson form validation', () {
    final config = LessonConfig.fromEnvironment();

    test('configuration keeps the specification bounds', () {
      expect(config.minOptions, 2);
      expect(config.maxOptions, 3);
    });

    test('one option is too few and four are too many', () {
      expect(
        lessonCountError(
          en,
          1,
          minOptions: config.minOptions,
          maxOptions: config.maxOptions,
        ),
        'Add at least 2 time options.',
      );
      expect(
        lessonCountError(
          ru,
          4,
          minOptions: config.minOptions,
          maxOptions: config.maxOptions,
        ),
        'Можно добавить не больше 3 вариантов времени.',
      );
      for (final count in [2, 3]) {
        expect(
          lessonCountError(
            en,
            count,
            minOptions: config.minOptions,
            maxOptions: config.maxOptions,
          ),
          isNull,
        );
      }
    });

    test('a slot needs a future time and a place unless online', () {
      final now = DateTime.utc(2026, 11, 14, 12);
      final future = now.add(const Duration(days: 1));
      expect(
        LessonSlotDraft(time: now).error(en, now: now),
        "The time can't be in the past.",
      );
      expect(
        LessonSlotDraft(time: future).error(en, now: now),
        'Enter a meeting place.',
      );
      expect(
        LessonSlotDraft(time: future, location: 'Library').error(en, now: now),
        isNull,
      );
      expect(
        LessonSlotDraft(time: future, online: true).error(en, now: now),
        isNull,
      );
      expect(
        LessonSlotDraft(
          time: future,
          online: true,
          location: 'ignored',
        ).toInput().location,
        isNull,
      );
      expect(
        LessonSlotDraft(
          time: future,
          location: '  Library  ',
        ).toInput().location,
        'Library',
      );
    });
  });

  group('Problem Details', () {
    test('every lesson problem has its own localized message', () {
      expect(
        lessonFailureMessage(en, problem(422, 'lesson_options_invalid')),
        'A lesson needs 2 to 3 time options in the future.',
      );
      expect(
        lessonFailureMessage(ru, problem(422, 'meeting_time_invalid')),
        'Выберите время в будущем.',
      );
      expect(
        lessonFailureMessage(en, problem(422, 'meeting_place_invalid')),
        'Check the meeting place.',
      );
      expect(
        lessonFailureMessage(en, problem(409, 'listing_conflict')),
        'The lesson has already been answered. Refresh the listing.',
      );
      expect(
        lessonFailureMessage(ru, problem(403, 'listing_forbidden')),
        'Отвечать на занятие могут только автор и участник.',
      );
      expect(
        lessonFailureMessage(en, problem(404, 'not_found')),
        'The listing is unavailable. It may have been removed or access has changed.',
      );
      expect(
        lessonFailureMessage(en, problem(500, 'internal_error')),
        'Something went wrong on the server. Please try again later.',
      );
    });
  });
}
