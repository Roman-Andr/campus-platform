import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_ru.dart';
import 'package:campus/src/features/listings/application/meeting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

Map<String, Object?> meetingJson({
  String? scheduledAt,
  String? location,
  String? scheduledBy,
  String? proposedAt,
  String? proposedLocation,
  String? proposedBy,
  bool online = false,
  int version = 1,
}) => {
  'id': 'meeting-1',
  'version': version,
  'status': proposedAt == null ? 'scheduled' : 'proposed',
  'scheduled_at': scheduledAt,
  'location': location,
  'online': online,
  'scheduled_by_id': scheduledBy,
  'proposed_at': proposedAt,
  'proposed_location': proposedLocation,
  'proposed_by_id': proposedBy,
};

Map<String, Object?> interactionJson({
  String status = 'accepted',
  Map<String, Object?>? meeting,
  String participant = 'other',
}) => {
  'id': 'request-1',
  'listing_id': 'listing-1',
  'participant_id': participant,
  'participant_name': 'Boris',
  'stage': null,
  'response_due_at': null,
  'status': status,
  'meeting': meeting,
};

InteractionOutput interaction({Map<String, Object?>? meeting}) =>
    InteractionOutput.fromJson(interactionJson(meeting: meeting));

ProblemFailure problem(int status, String code) => ProblemFailure(
  Problem.fromJson({
    'type': 'urn:problem:campus:$code',
    'title': 'Title',
    'status': status,
    'code': code,
    'request_id': 'req-1',
  }),
);

FakeHttpAdapter server({
  List<Map<String, Object?>> participations = const [],
  List<Map<String, Object?>> incoming = const [],
}) => FakeHttpAdapter()
  ..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path.endsWith('/reservations/mine')) {
      return jsonBody(200, pageJson(participations));
    }
    if (options.path.endsWith('/interactions')) {
      return jsonBody(200, pageJson(incoming));
    }
    return problemBody(404, 'not_found');
  });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('meetingOf reads the optional meeting of an interaction', () {
    final scheduled = meetingJson(
      scheduledAt: '2027-01-15T15:00:00Z',
      location: 'Library',
      scheduledBy: 'author',
    );
    expect(meetingOf(interaction())?.scheduledAt, isNull);
    expect(meetingOf(interaction(meeting: scheduled))!.location, 'Library');
    expect(meetingOf(interaction(meeting: scheduled))!.version, 1);
  });

  test('the form starts from a future proposal, then the meeting', () {
    final now = DateTime.utc(2026, 11, 14, 12);
    final proposal = meetingJson(
      scheduledAt: '2026-11-15T15:00:00Z',
      location: 'Old place',
      scheduledBy: 'author',
      proposedAt: '2026-11-16T15:00:00Z',
      proposedLocation: 'New place',
      proposedBy: 'other',
      version: 2,
    );
    final meeting = meetingOf(interaction(meeting: proposal));
    expect(
      meetingInitialTime(meeting, now: now),
      DateTime.utc(2026, 11, 16, 15),
    );
    expect(
      meetingInitialTime(
        meetingOf(
          interaction(
            meeting: meetingJson(
              scheduledAt: '2026-11-15T15:00:00Z',
              location: 'Library',
              scheduledBy: 'author',
            ),
          ),
        ),
        now: now,
      ),
      DateTime.utc(2026, 11, 15, 15),
    );
    expect(
      meetingInitialTime(meetingOf(interaction()), now: now),
      DateTime.utc(2026, 11, 15, 12),
    );
    expect(
      meetingInitialTime(meeting, now: DateTime.utc(2026, 11, 17)),
      DateTime.utc(2026, 11, 18),
    );
  });

  test('a proposal time in the past is rejected', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();
    final now = DateTime.utc(2026, 11, 14, 12);
    expect(meetingTimeError(en, null), en.meetingTimeRequired);
    expect(
      meetingTimeError(en, now.subtract(const Duration(minutes: 1)), now: now),
      en.meetingTimePast,
    );
    expect(meetingTimeError(en, now, now: now), en.meetingTimePast);
    expect(
      meetingTimeError(en, now.add(const Duration(minutes: 1)), now: now),
      isNull,
    );
    expect(meetingTimeError(ru, null), 'Выберите время встречи.');
    expect(
      meetingTimeError(ru, now.subtract(const Duration(hours: 1)), now: now),
      'Нельзя выбрать время в прошлом.',
    );
  });

  test('a place is required', () {
    final en = AppLocalizationsEn();
    expect(meetingPlaceError(en, null), en.meetingPlaceRequired);
    expect(meetingPlaceError(en, '  '), en.meetingPlaceRequired);
    expect(meetingPlaceError(en, 'Library'), isNull);
  });

  test('a stale proposal has its own message and is recognized', () {
    final en = AppLocalizationsEn();
    final stale = problem(409, 'meeting_stale');
    expect(meetingIsStale(stale), isTrue);
    expect(meetingFailureMessage(en, stale), en.meetingStale);
    expect(meetingIsStale(problem(409, 'meeting_state_conflict')), isFalse);
    expect(
      meetingFailureMessage(en, problem(422, 'meeting_time_invalid')),
      en.meetingTimeInvalid,
    );
    expect(
      meetingFailureMessage(en, problem(422, 'meeting_place_invalid')),
      en.meetingPlaceInvalid,
    );
    expect(
      meetingFailureMessage(en, problem(409, 'meeting_state_conflict')),
      en.meetingStateConflict,
    );
    expect(
      meetingFailureMessage(en, problem(403, 'forbidden')),
      en.errorRequest,
    );
  });

  test(
    'own participation is found without reading the incoming list',
    () async {
      final adapter = server(
        participations: [
          {
            ...interactionJson(
              participant: userJson['id']! as String,
              meeting: meetingJson(
                proposedAt: '2027-01-16T15:00:00Z',
                proposedLocation: 'Cafe',
                proposedBy: 'other',
              ),
            ),
            'created_at': '2026-11-14T00:00:00Z',
            'listing': {
              'id': 'listing-1',
              'kind': 'giveaway',
              'title': 'A desk',
              'status': 'busy',
              'city_timezone': 'Europe/Moscow',
            },
          },
        ],
      );
      final container = ProviderContainer(
        overrides: apiOverrides(adapter: adapter),
      );
      addTearDown(container.dispose);
      final provider = meetingInteractionProvider(('listing-1', 'request-1'));
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final item = await container.read(provider.future);
      expect(item.id, 'request-1');
      expect(meetingOf(item)!.proposedLocation, 'Cafe');
      expect(
        adapter.sent.where((request) => request.path.endsWith('/interactions')),
        isEmpty,
      );
    },
  );

  test('the author finds the interaction in the incoming list', () async {
    final adapter = server(incoming: [interactionJson(meeting: meetingJson())]);
    final container = ProviderContainer(
      overrides: apiOverrides(adapter: adapter),
    );
    addTearDown(container.dispose);
    final provider = meetingInteractionProvider(('listing-1', 'request-1'));
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final item = await container.read(provider.future);
    expect(item.id, 'request-1');
    expect(
      adapter.sent.where((request) => request.path.endsWith('/interactions')),
      isNotEmpty,
    );
  });

  test('a foreign interaction is unavailable', () async {
    final adapter = server();
    final container = ProviderContainer(
      overrides: apiOverrides(adapter: adapter),
    );
    addTearDown(container.dispose);
    final provider = meetingInteractionProvider(('listing-1', 'request-1'));
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await expectLater(
      container.read(provider.future),
      throwsA(isA<MeetingUnavailable>()),
    );
  });

  test(
    'a forbidden incoming list means the interaction is unavailable',
    () async {
      final adapter = FakeHttpAdapter()
        ..route((options) {
          if (options.path.endsWith('/token/refresh')) {
            return jsonBody(200, tokensJson(1));
          }
          if (options.path.endsWith('/reservations/mine')) {
            return jsonBody(200, pageJson([]));
          }
          return problemBody(403, 'forbidden');
        });
      final container = ProviderContainer(
        overrides: apiOverrides(adapter: adapter),
      );
      addTearDown(container.dispose);
      final provider = meetingInteractionProvider(('listing-1', 'request-1'));
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await expectLater(
        container.read(provider.future),
        throwsA(isA<MeetingUnavailable>()),
      );
    },
  );
}
