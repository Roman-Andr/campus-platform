import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_ru.dart';
import 'package:campus/src/features/listings/application/no_meeting.dart';
import 'package:campus/src/features/listings/domain/help.dart';
import 'package:campus/src/features/listings/domain/skills.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

Map<String, Object?> meetingJson({
  String? scheduledAt,
  String? location,
  bool online = false,
  int version = 1,
}) => {
  'id': 'meeting-1',
  'version': version,
  'status': 'scheduled',
  'scheduled_at': scheduledAt,
  'location': location,
  'online': online,
  'scheduled_by_id': 'author',
  'proposed_at': null,
  'proposed_location': null,
  'proposed_by_id': null,
};

Map<String, Object?> interactionJson({
  String status = 'accepted',
  Map<String, Object?>? meeting,
  String? completionMethod,
  bool withoutMeeting = false,
}) => {
  'id': 'request-1',
  'listing_id': 'listing-1',
  'participant_id': 'participant',
  'participant_name': 'Boris',
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'status': status,
  'meeting': meeting,
  'completion_method': completionMethod,
  'without_meeting': withoutMeeting,
};

InteractionOutput interaction({
  String status = 'accepted',
  Map<String, Object?>? meeting,
  String? completionMethod,
  bool withoutMeeting = false,
}) => InteractionOutput.fromJson(
  interactionJson(
    status: status,
    meeting: meeting,
    completionMethod: completionMethod,
    withoutMeeting: withoutMeeting,
  ),
);

Map<String, Object?> noMeetingJson({
  String status = 'accepted',
  String? agreedAt,
  bool confirmedByMe = false,
  bool confirmedByOther = false,
  List<Map<String, Object?>> confirmations = const [],
  bool completed = false,
  String? completedAt,
  Object? completionMethod,
}) => {
  'listing_id': 'listing-1',
  'interaction_id': 'request-1',
  'status': status,
  'method': 'no_meeting',
  'agreed_at': agreedAt,
  'confirmed_by_me': confirmedByMe,
  'confirmed_by_other': confirmedByOther,
  'confirmations': confirmations,
  'completed': completed,
  'completed_at': completedAt,
  'completion_method': completionMethod,
  'rating_weight': completed ? 0.5 : null,
};

Map<String, Object?> confirmationJson(String id, String at) => {
  'participant_id': id,
  'confirmed_at': at,
};

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
  required Map<String, Object?> Function() state,
  Map<String, Object?> Function()? onConfirm,
}) => FakeHttpAdapter()
  ..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path.endsWith('/no-meeting/confirmations')) {
      return jsonBody(200, (onConfirm ?? state)());
    }
    if (options.path.endsWith('/no-meeting')) return jsonBody(200, state());
    return problemBody(404, 'not_found');
  });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offers no-meeting only for an accepted online lesson or help '
      'without a meeting', () {
    final online = meetingJson(
      scheduledAt: '2026-11-16T15:00:00Z',
      online: true,
    );
    expect(noMeetingAvailable(skillKind, interaction(meeting: online)), isTrue);
    expect(
      noMeetingAvailable(
        skillKind,
        interaction(meeting: meetingJson(online: true)),
      ),
      isFalse,
    );
    expect(
      noMeetingAvailable(skillKind, interaction(meeting: meetingJson())),
      isFalse,
    );
    expect(noMeetingAvailable(skillKind, interaction()), isFalse);
    expect(noMeetingAvailable(helpKind, interaction()), isTrue);
    expect(noMeetingAvailable(helpKind, interaction(meeting: online)), isFalse);
    expect(
      noMeetingAvailable(
        skillKind,
        interaction(status: 'pending', meeting: online),
      ),
      isFalse,
    );
    expect(
      noMeetingAvailable(
        'giveaway',
        interaction(
          status: 'completed',
          completionMethod: 'no_meeting',
          withoutMeeting: true,
        ),
      ),
      isFalse,
    );
    expect(
      noMeetingAvailable(
        'event',
        interaction(
          status: 'completed',
          completionMethod: 'no_meeting',
          withoutMeeting: true,
        ),
      ),
      isFalse,
    );
  });

  test('reads the completion flag from the interaction', () {
    expect(interactionWithoutMeeting(interaction()), isFalse);
    expect(
      interactionWithoutMeeting(
        interaction(status: 'completed', completionMethod: 'qr'),
      ),
      isFalse,
    );
    expect(
      interactionWithoutMeeting(
        interaction(status: 'completed', completionMethod: 'no_meeting'),
      ),
      isTrue,
    );
    expect(
      interactionWithoutMeeting(
        interaction(status: 'completed', withoutMeeting: true),
      ),
      isTrue,
    );
  });

  test('a no-meeting refusal has its own localized message', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();
    final unavailable = problem(409, 'listing_no_meeting_unavailable');
    expect(noMeetingIsUnavailable(unavailable), isTrue);
    expect(noMeetingFailureMessage(en, unavailable), en.noMeetingUnavailable);
    expect(
      noMeetingFailureMessage(ru, unavailable),
      'Это взаимодействие нельзя завершить без встречи.',
    );
    expect(
      noMeetingFailureMessage(en, problem(403, 'forbidden')),
      en.noMeetingForbidden,
    );
    expect(
      noMeetingFailureMessage(en, problem(404, 'not_found')),
      en.listingUnavailable,
    );
  });

  test('loads both consents from the server', () async {
    final adapter = server(
      state: () => noMeetingJson(
        agreedAt: '2026-11-16T15:00:00Z',
        confirmedByMe: true,
        confirmations: [
          confirmationJson(userJson['id']! as String, '2026-11-15T12:00:00Z'),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: apiOverrides(adapter: adapter),
    );
    addTearDown(container.dispose);
    final provider = noMeetingStateProvider(('listing-1', 'request-1'));
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);

    final state = await container.read(provider.future);

    expect(state.confirmedByMe, isTrue);
    expect(state.confirmedByOther, isFalse);
    expect(state.agreedAt, DateTime.utc(2026, 11, 16, 15));
    expect(
      state.confirmations.single.confirmedAt,
      DateTime.utc(2026, 11, 15, 12),
    );
    expect(
      adapter.sent.single.path,
      '/api/v1/listings/listing-1/interactions/request-1/no-meeting',
    );
  });

  test('confirming sends the key and stores the returned state', () async {
    final adapter = server(
      state: noMeetingJson,
      onConfirm: () => noMeetingJson(
        agreedAt: '2026-11-16T15:00:00Z',
        confirmedByMe: true,
        confirmations: [
          confirmationJson(userJson['id']! as String, '2026-11-15T12:00:00Z'),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: apiOverrides(adapter: adapter),
    );
    addTearDown(container.dispose);
    final provider = noMeetingStateProvider(('listing-1', 'request-1'));
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await container.read(provider.future);

    final output = await container
        .read(provider.notifier)
        .confirm(idempotencyKey: '01890a5d-ac96-774b-bcce-b302099a8057');

    expect(output.confirmedByMe, isTrue);
    expect(container.read(provider).value!.confirmedByMe, isTrue);
    final request = adapter.sent.singleWhere(
      (request) => request.path.endsWith('/no-meeting/confirmations'),
    );
    expect(request.method, 'POST');
    expect(
      request.headers['Idempotency-Key'],
      '01890a5d-ac96-774b-bcce-b302099a8057',
    );
    expect(request.data, isNull);
  });
}
