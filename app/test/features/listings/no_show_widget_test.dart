@Timeout(Duration(seconds: 120))
library;

import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/realtime/realtime_service.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/realtime/fake_centrifuge.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

const authorId = '01890a5d-ac96-774b-bcce-b302099a8058';
const participantId = '01890a5d-ac96-774b-bcce-b302099a8060';

Map<String, Object?> account(String id) => {
  ...userJson,
  ...filledProfileJson,
  'id': id,
  'first_name': 'Ivan',
  'last_name': 'Ivanov',
};

Map<String, Object?> meetingJson({required DateTime scheduledAt}) => {
  'id': 'meeting-1',
  'version': 1,
  'status': 'scheduled',
  'scheduled_at': scheduledAt.toIso8601String(),
  'location': 'Library',
  'online': false,
  'scheduled_by_id': authorId,
  'proposed_at': null,
  'proposed_location': null,
  'proposed_by_id': null,
};

Map<String, Object?> interactionJson({
  required DateTime scheduledAt,
  String status = 'accepted',
}) => {
  'id': 'request-1',
  'listing_id': 'listing-1',
  'participant_name': 'Petr Petrov',
  'participant_id': participantId,
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'status': status,
  'meeting': meetingJson(scheduledAt: scheduledAt),
};

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

/// Answers of the realtime endpoints; `null` for a path of another module.
ResponseBody? realtimeReply(
  RequestOptions options, {
  bool historyLost = false,
}) {
  if (options.path == '/api/v1/auth/token/refresh') {
    return jsonBody(200, tokensJson(1));
  }
  if (options.path == '/api/v1/realtime/subscription-token') {
    final body = jsonDecode(options.data! as String) as Map<String, Object?>;
    return jsonBody(200, {
      'token': 'subscription-token',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'channel': body['channel'],
    });
  }
  if (options.path == '/api/v1/realtime/recover') {
    final body = jsonDecode(options.data! as String) as Map<String, Object?>;
    if (body['since'] != null && historyLost) {
      return problemBody(409, 'realtime_history_lost');
    }
    return jsonBody(200, {
      'channel': body['channel'],
      'epoch': 'epoch-1',
      'offset': 0,
      'publications': <Object?>[],
    });
  }
  return null;
}

/// The personal no-show state and the refusals of a fake server.
class FakeNoShowBackend {
  FakeNoShowBackend({
    this.cityTimezone = 'Europe/Moscow',
    DateTime? markFrom,
    DateTime? autoAfter,
    DateTime? meetingAt,
  }) : markFrom =
           markFrom ??
           DateTime.now().toUtc().subtract(const Duration(hours: 1)),
       autoAfter =
           autoAfter ?? DateTime.now().toUtc().add(const Duration(days: 5)),
       meetingAt =
           meetingAt ??
           DateTime.now().toUtc().subtract(const Duration(days: 2));

  final String listingId = 'listing-1';
  final String interactionId = 'request-1';
  String cityTimezone;
  DateTime markFrom;
  DateTime autoAfter;
  DateTime meetingAt;

  String status = 'accepted';
  String basis = 'unmarked';
  String? noShowAt;
  bool canMark = true;
  List<Map<String, Object?>> marks = [];
  Map<String, Object?>? dispute;

  /// The own row of the participant in the incoming list of the author.
  bool incoming = false;

  /// Whether the current user is the author of the listing.
  String viewer = authorId;

  int stateRequests = 0;
  int markRequests = 0;

  /// How many attempts of a mark fail like a dropped connection.
  int networkFailures = 0;

  /// A problem the next mark answers instead of marking.
  String? markProblem;
  int markProblemStatus = 409;
  DateTime? markProblemAvailableAt;

  String get statePath =>
      '/api/v1/listings/$listingId/interactions/$interactionId/no-show';

  Map<String, Object?> listing() => {
    ...listingJson(id: listingId, author: authorId),
    'city_timezone': cityTimezone,
  };

  Map<String, Object?> state() => {
    'listing_id': listingId,
    'interaction_id': interactionId,
    'status': status,
    'basis': basis,
    'marks': marks,
    'dispute': dispute,
    'no_show_at': noShowAt,
    'mark_from': markFrom.toIso8601String(),
    'auto_after': autoAfter.toIso8601String(),
    'can_mark': canMark,
    'server_time': DateTime.now().toUtc().toIso8601String(),
  };

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

  /// Turns the state into a late-QR lift: the interaction is completed and
  /// every mark is removed.
  void liftByLateQr() {
    status = 'completed';
    basis = 'completed';
    canMark = false;
    final now = DateTime.now().toUtc().toIso8601String();
    marks = [
      for (final mark in marks)
        {...mark, 'status': 'removed', 'removed_at': now},
    ];
    dispute = disputeJson(status: 'resolved', resolution: 'late_qr');
  }

  void mark({required String reason, required String reporter}) {
    final subject = reporter == authorId ? participantId : authorId;
    final now = DateTime.now().toUtc();
    if (status == 'accepted') {
      marks = [
        markJson(
          reporter: reporter,
          subject: subject,
          reason: reason,
          createdAt: now.toIso8601String(),
        ),
      ];
      status = 'no_show';
      basis = 'marked';
      noShowAt = now.toIso8601String();
      canMark = false;
      return;
    }
    // An answer to the other allegation opens the single dispute.
    marks = [
      ...marks.map((mark) => {...mark, 'status': 'disputed'}),
      markJson(
        id: 'mark-2',
        status: 'disputed',
        disputedAt: now.toIso8601String(),
        reporter: reporter,
        subject: subject,
        reason: reason,
        createdAt: now.toIso8601String(),
      ),
    ];
    basis = 'mutual_dispute';
    dispute = disputeJson();
    canMark = false;
  }

  ResponseBody reply(RequestOptions options) {
    final base = realtimeReply(options);
    if (base != null) return base;
    final path = options.path;
    final method = options.method;
    if (method == 'GET' && path == '/api/v1/listings/$listingId') {
      return jsonBody(200, listing());
    }
    if (method == 'GET' && path == '/api/v1/listings/reservations/mine') {
      return jsonBody(200, pageJson([]));
    }
    if (method == 'GET' && path == '/api/v1/listings/$listingId/waitlist/me') {
      return problemBody(404, 'not_found');
    }
    if (method == 'GET' && path == '/api/v1/listings/$listingId/interactions') {
      return jsonBody(
        200,
        pageJson(incoming ? [interactionJson(scheduledAt: meetingAt)] : []),
      );
    }
    if (method == 'GET' && path == statePath) {
      stateRequests++;
      return jsonBody(200, state());
    }
    if (method == 'POST' && path == statePath) {
      markRequests++;
      if (networkFailures > 0) {
        networkFailures--;
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection reset by peer',
        );
      }
      final problem = markProblem;
      if (problem != null) {
        return problemBody(
          markProblemStatus,
          problem,
          extra: {
            if (markProblemAvailableAt case final availableAt?)
              'available_at': availableAt.toIso8601String(),
          },
        );
      }
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      mark(reason: body['reason']! as String, reporter: viewer);
      return jsonBody(200, state());
    }
    throw StateError('No reply for $method $path');
  }
}

/// The event result and the refusals of a fake server.
class FakeEventNoShowBackend {
  FakeEventNoShowBackend({
    DateTime? endsAt,
    this.cityTimezone = 'Europe/Moscow',
  }) : endsAt =
           endsAt ?? DateTime.now().toUtc().subtract(const Duration(hours: 2));

  final String listingId = 'event-1';
  final DateTime endsAt;
  String cityTimezone;
  String viewer = participantId;
  int registered = 4;
  int threshold = 2;
  int votes = 0;
  bool notHeld = false;
  bool voted = false;
  bool canVote = true;
  bool canDispute = false;
  Map<String, Object?>? organizerMark;
  Map<String, Object?>? dispute;
  List<Map<String, Object?>> participantMarks = [];
  DateTime? disputeDeadline;
  int stateRequests = 0;
  int voteRequests = 0;
  int disputeRequests = 0;

  /// A problem the next vote answers instead of voting.
  String? voteProblem;

  String get statePath => '/api/v1/listings/$listingId/event/no-show';

  Map<String, Object?> listing() => {
    ...eventListingJson(
      id: listingId,
      author: authorId,
      startsAt: endsAt.subtract(const Duration(hours: 2)).toIso8601String(),
      endsAt: endsAt.toIso8601String(),
    ),
    'city_timezone': cityTimezone,
  };

  Map<String, Object?> state() => {
    'listing_id': listingId,
    'organizer_id': authorId,
    'registered': registered,
    'votes': votes,
    'threshold': threshold,
    'not_held': notHeld,
    'organizer_mark': organizerMark,
    'dispute': dispute,
    'dispute_deadline': disputeDeadline?.toIso8601String(),
    'participant_marks': participantMarks,
    'vote_opens_at': endsAt.toIso8601String(),
    'vote_closes_at': endsAt.add(const Duration(days: 7)).toIso8601String(),
    'can_vote': canVote && viewer != authorId,
    'can_dispute': canDispute && viewer == authorId,
    'voted': voted,
    'server_time': DateTime.now().toUtc().toIso8601String(),
  };

  Map<String, Object?> disputeJson({String status = 'open'}) => {
    'id': 'dispute-1',
    'status': status,
    'opened_at': '2026-11-20T13:00:00Z',
    'resolved_at': status == 'resolved' ? '2026-11-20T14:00:00Z' : null,
    'resolution': null,
  };

  ResponseBody reply(RequestOptions options) {
    final base = realtimeReply(options);
    if (base != null) return base;
    final path = options.path;
    final method = options.method;
    if (method == 'GET' && path == '/api/v1/listings/$listingId') {
      return jsonBody(200, listing());
    }
    if (method == 'GET' && path == '/api/v1/listings/reservations/mine') {
      return jsonBody(200, pageJson([]));
    }
    if (method == 'GET' && path == '/api/v1/listings/$listingId/waitlist/me') {
      return problemBody(404, 'not_found');
    }
    if (method == 'GET' && path == '/api/v1/listings/$listingId/interactions') {
      return jsonBody(200, pageJson([]));
    }
    if (method == 'GET' && path == statePath) {
      stateRequests++;
      return jsonBody(200, state());
    }
    if (method == 'POST' && path == '$statePath/votes') {
      voteRequests++;
      final problem = voteProblem;
      if (problem != null) return problemBody(409, problem);
      if (!voted) {
        voted = true;
        votes += 1;
        if (votes >= threshold && threshold > 0) {
          notHeld = true;
          organizerMark = markJson(
            id: 'organizer-mark',
            kind: 'event_vote',
            reporter: null,
            subject: authorId,
            reason: null,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          );
          disputeDeadline = DateTime.now().toUtc().add(const Duration(days: 7));
          participantMarks = [
            for (final mark in participantMarks)
              {
                ...mark,
                'status': 'removed',
                'removed_at': DateTime.now().toUtc().toIso8601String(),
              },
          ];
        }
      }
      return jsonBody(200, state());
    }
    if (method == 'POST' && path == '$statePath/dispute') {
      disputeRequests++;
      dispute = disputeJson();
      canDispute = false;
      organizerMark = {...?organizerMark, 'status': 'disputed'};
      return jsonBody(200, state());
    }
    throw StateError('No reply for $method $path');
  }
}

/// Advances fake time in bounded steps; an unbounded `pumpAndSettle` cannot
/// settle the screen that rebuilds once a second.
Future<void> settle(WidgetTester tester, {int steps = 15}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the app signed in as [viewer] and pushes [path].
Future<(FakeCentrifugeClient, FakeHttpAdapter)> open(
  WidgetTester tester,
  ResponseBody Function(RequestOptions options) reply,
  String path, {
  required String viewer,
}) async {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final client = FakeCentrifugeClient();
  final server = FakeHttpAdapter(me: account(viewer), feed: pageJson([]))
    ..route(reply);
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
    overrides: [realtimeClientProvider.overrideWithValue(client)],
  );
  unawaited(container.read(appRouterProvider).push(path));
  await settle(tester);
  return (client, server);
}

FakeSubscription subscription(FakeCentrifugeClient client, String userId) =>
    client.getSubscription('user#$userId')! as FakeSubscription;

List<SentRequest> sentTo(FakeHttpAdapter server, String method, String path) =>
    server.sent
        .where((request) => request.method == method && request.path == path)
        .toList();

Future<void> wakeup(
  WidgetTester tester,
  FakeCentrifugeClient client,
  Map<String, Object?> data, {
  required String userId,
}) async {
  subscription(client, userId).addPublication(offset: 1, data: data);
  await settle(tester);
}

Future<void> submitReason(WidgetTester tester, String reason) async {
  await tester.enterText(find.byKey(const Key('no-show-reason')), reason);
  await tester.tap(find.byKey(const Key('no-show-submit')));
  await settle(tester);
}

void main() {
  group('the personal no-show', () {
    testWidgets('marks with a reason and rereads the state', (tester) async {
      final backend = FakeNoShowBackend();
      final (_, server) = await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: authorId,
      );

      expect(find.byKey(const Key('no-show-phase-open')), findsOneWidget);
      await submitReason(tester, 'Nobody came');

      final post = sentTo(server, 'POST', backend.statePath).single;
      expect(post.json['reason'], 'Nobody came');
      expect(post.headers['Idempotency-Key'], isA<String>());
      // The state is read back after the mark, not just taken from the answer.
      expect(backend.stateRequests, greaterThanOrEqualTo(2));
      expect(find.text('Marked by a participant'), findsOneWidget);
      expect(find.text('The no-show was recorded.'), findsOneWidget);
      expect(
        find.textContaining('Charged to: the other participant'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('no-show-submit')), findsNothing);
    });

    testWidgets('is unavailable before the window and opens by city time', (
      tester,
    ) async {
      final backend = FakeNoShowBackend(
        cityTimezone: 'Asia/Tokyo',
        markFrom: DateTime.utc(2026, 11, 21, 9),
      )..viewer = authorId;
      await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: authorId,
      );

      expect(find.byKey(const Key('no-show-phase-before')), findsOneWidget);
      expect(find.byKey(const Key('no-show-submit')), findsNothing);
      // 09:00 UTC is 18:00 in Tokyo, not the device time.
      expect(find.textContaining('18:00'), findsOneWidget);
    });

    testWidgets('is closed after the automatic deadline', (tester) async {
      final backend = FakeNoShowBackend(
        autoAfter: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      )..viewer = authorId;
      await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: authorId,
      );

      expect(find.byKey(const Key('no-show-phase-closed')), findsOneWidget);
      expect(find.byKey(const Key('no-show-submit')), findsNothing);
    });

    testWidgets('a refusal updates the screen from the server', (tester) async {
      final backend = FakeNoShowBackend()
        ..viewer = authorId
        ..markProblem = 'no_show_too_early'
        ..markProblemAvailableAt = DateTime.utc(2026, 11, 21, 9);
      await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: authorId,
      );
      final before = backend.stateRequests;

      await submitReason(tester, 'Nobody came');

      expect(find.byKey(const Key('no-show-error')), findsOneWidget);
      expect(
        find.textContaining('A no-show can be marked from'),
        findsOneWidget,
      );
      expect(find.textContaining('12:00'), findsOneWidget);
      // The refusal is followed by the state of the server, not the old one.
      expect(backend.stateRequests, greaterThan(before));
    });

    testWidgets('a foreign participant is refused with its own message', (
      tester,
    ) async {
      final backend = FakeNoShowBackend()
        ..viewer = authorId
        ..markProblem = 'no_show_forbidden'
        ..markProblemStatus = 403;
      await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: authorId,
      );

      await submitReason(tester, 'Nobody came');

      expect(
        find.text(
          'Only the two participants of the interaction can mark a no-show.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a repeat after a lost connection keeps the idempotency key', (
      tester,
    ) async {
      final backend = FakeNoShowBackend()
        ..viewer = authorId
        ..networkFailures = 4;
      final (_, server) = await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: authorId,
      );

      await submitReason(tester, 'Nobody came');

      expect(find.byKey(const Key('no-show-error')), findsOneWidget);
      final attempts = sentTo(server, 'POST', backend.statePath);
      expect(attempts, hasLength(4));
      expect(
        attempts.map((request) => request.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(backend.marks, isEmpty);

      await tester.tap(find.byKey(const Key('no-show-submit')));
      await settle(tester);

      expect(find.text('The no-show was recorded.'), findsOneWidget);
      final all = sentTo(server, 'POST', backend.statePath);
      expect(all, hasLength(5));
      expect(
        all.map((request) => request.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(backend.marks, hasLength(1));
    });

    testWidgets('an answer stays possible after the mark window closed', (
      tester,
    ) async {
      final backend =
          FakeNoShowBackend(
              autoAfter: DateTime.now().toUtc().subtract(
                const Duration(days: 1),
              ),
            )
            ..viewer = participantId
            ..status = 'no_show'
            ..basis = 'marked'
            ..noShowAt = DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 2))
                .toIso8601String()
            ..marks = [markJson()];
      final (_, server) = await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: participantId,
      );

      // The other participant marked it; the answer window runs from the mark
      // and outlives the mark window itself.
      expect(find.byKey(const Key('no-show-answer-hint')), findsOneWidget);
      expect(find.byKey(const Key('no-show-phase-closed')), findsNothing);
      expect(find.byKey(const Key('no-show-submit')), findsOneWidget);

      await submitReason(tester, 'We met');

      expect(
        sentTo(server, 'POST', backend.statePath).single.json['reason'],
        'We met',
      );
      expect(find.byKey(const Key('no-show-dispute-open')), findsOneWidget);
      expect(find.text('Mutual marks: under dispute'), findsOneWidget);
      expect(find.textContaining('suspended by a dispute'), findsNWidgets(2));
      expect(
        find.text(
          'Your answer was recorded; a moderator will decide the case.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a mutual allegation is shown as an open dispute', (
      tester,
    ) async {
      final backend = FakeNoShowBackend()
        ..viewer = participantId
        ..status = 'no_show'
        ..basis = 'mutual_dispute'
        ..canMark = false
        ..noShowAt = '2026-11-20T12:00:00Z'
        ..marks = [
          markJson(status: 'disputed', disputedAt: '2026-11-20T13:00:00Z'),
          markJson(
            id: 'mark-2',
            status: 'disputed',
            reporter: participantId,
            subject: authorId,
            disputedAt: '2026-11-20T13:00:00Z',
          ),
        ]
        ..dispute = {
          'id': 'dispute-1',
          'status': 'open',
          'opened_at': '2026-11-20T13:00:00Z',
          'resolved_at': null,
          'resolution': null,
        };
      await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: participantId,
      );

      expect(find.byKey(const Key('no-show-dispute-open')), findsOneWidget);
      expect(find.text('Mutual marks: under dispute'), findsOneWidget);
      expect(find.textContaining('suspended by a dispute'), findsNWidgets(2));
      expect(find.byKey(const Key('no-show-submit')), findsNothing);
    });

    testWidgets('a late QR lift is shown without the stale mark', (
      tester,
    ) async {
      final backend = FakeNoShowBackend()
        ..viewer = authorId
        ..status = 'no_show'
        ..basis = 'marked'
        ..canMark = false
        ..noShowAt = DateTime.now().toUtc().toIso8601String()
        ..marks = [markJson()];
      final (client, _) = await open(
        tester,
        backend.reply,
        '/listings/listing-1/interactions/request-1/no-show',
        viewer: authorId,
      );
      expect(find.textContaining('counts'), findsOneWidget);

      backend.liftByLateQr();
      await wakeup(tester, client, {
        'listing_id': 'listing-1',
        'interaction_id': 'request-1',
        'status': 'completed',
      }, userId: authorId);

      expect(find.byKey(const Key('no-show-lifted')), findsOneWidget);
      expect(find.text('The meeting took place'), findsOneWidget);
      expect(find.textContaining('removed '), findsOneWidget);
      expect(find.textContaining('counts'), findsNothing);
      expect(find.byKey(const Key('no-show-submit')), findsNothing);
    });

    testWidgets('the entry card opens the screen', (tester) async {
      final backend =
          FakeNoShowBackend(
              meetingAt: DateTime.now().toUtc().subtract(
                const Duration(days: 2),
              ),
            )
            ..viewer = authorId
            ..incoming = true;
      await open(
        tester,
        backend.reply,
        '/listings/listing-1',
        viewer: authorId,
      );

      expect(find.byKey(const Key('no-show-request-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('no-show-open-request-1')));
      await settle(tester);

      expect(find.byKey(const Key('no-show-phase-open')), findsOneWidget);
      expect(find.byKey(const Key('no-show-reason')), findsOneWidget);
    });
  });

  group('the event result', () {
    testWidgets('a participant votes and the counter follows', (tester) async {
      final backend = FakeEventNoShowBackend();
      final (_, server) = await open(
        tester,
        backend.reply,
        '/event/event-1/no-show',
        viewer: participantId,
      );

      expect(find.text('Votes: 0 of 2 needed · 4 registered'), findsOneWidget);
      await tester.tap(find.byKey(const Key('event-no-show-vote')));
      await settle(tester);

      final post = sentTo(server, 'POST', '${backend.statePath}/votes').single;
      expect(post.headers['Idempotency-Key'], isA<String>());
      expect(find.text('Votes: 1 of 2 needed · 4 registered'), findsOneWidget);
      expect(find.byKey(const Key('event-no-show-voted')), findsOneWidget);
      expect(find.byKey(const Key('event-no-show-vote')), findsNothing);
    });

    testWidgets('reaching the threshold charges the organiser', (tester) async {
      final backend = FakeEventNoShowBackend()
        ..registered = 3
        ..threshold = 1
        ..participantMarks = [
          markJson(kind: 'event_auto', reporter: null, reason: null),
        ];
      await open(
        tester,
        backend.reply,
        '/event/event-1/no-show',
        viewer: participantId,
      );

      await tester.tap(find.byKey(const Key('event-no-show-vote')));
      await settle(tester);

      expect(find.text('Votes: 1 of 1 needed · 3 registered'), findsOneWidget);
      // The automatic no-show of the participant is lifted by the vote.
      expect(find.textContaining('removed '), findsOneWidget);
    });

    testWidgets('the organiser sees the charge and disputes it', (
      tester,
    ) async {
      final backend = FakeEventNoShowBackend()
        ..viewer = authorId
        ..notHeld = true
        ..canDispute = true
        ..disputeDeadline = DateTime.now().toUtc().add(const Duration(days: 6))
        ..organizerMark = markJson(
          id: 'organizer-mark',
          kind: 'event_vote',
          reporter: null,
          subject: authorId,
          reason: null,
        );
      final (_, server) = await open(
        tester,
        backend.reply,
        '/event/event-1/no-show',
        viewer: authorId,
      );

      expect(
        find.byKey(const Key('event-no-show-organizer-charged')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('event-no-show-dispute')));
      await settle(tester);

      final post = sentTo(
        server,
        'POST',
        '${backend.statePath}/dispute',
      ).single;
      expect(post.headers['Idempotency-Key'], isA<String>());
      expect(
        find.byKey(const Key('event-no-show-dispute-open')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('event-no-show-dispute')), findsNothing);
      expect(find.text('The dispute was opened.'), findsOneWidget);
    });

    testWidgets('the vote window is shown in the city of the event', (
      tester,
    ) async {
      // Ended six days before the moment of this test: the week of voting is
      // still open, and the window times are shown in the city, not the
      // device zone.
      final backend = FakeEventNoShowBackend(
        endsAt: DateTime.utc(2026, 11, 10, 12),
        cityTimezone: 'Asia/Tokyo',
      )..viewer = participantId;
      await open(
        tester,
        backend.reply,
        '/event/event-1/no-show',
        viewer: participantId,
      );

      expect(
        find.byKey(const Key('event-no-show-window-open')),
        findsOneWidget,
      );
      // 12:00 UTC is 21:00 in Tokyo; the device zone is not UTC in general,
      // so the value proves the city zone is used.
      final window = tester.widget<Text>(
        find.byKey(const Key('event-no-show-window-open')),
      );
      expect(window.data, contains('21:00'));
    });

    testWidgets('a closed vote updates the screen from the server', (
      tester,
    ) async {
      final backend = FakeEventNoShowBackend()
        ..voteProblem = 'event_no_show_vote_closed';
      await open(
        tester,
        backend.reply,
        '/event/event-1/no-show',
        viewer: participantId,
      );
      final before = backend.stateRequests;

      await tester.tap(find.byKey(const Key('event-no-show-vote')));
      await settle(tester);

      expect(find.text('Voting is closed.'), findsOneWidget);
      expect(backend.stateRequests, greaterThan(before));
    });
  });
}
