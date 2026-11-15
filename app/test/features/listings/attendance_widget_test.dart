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

const organizerId = '01890a5d-ac96-774b-bcce-b302099a8058';
const participantId = '01890a5d-ac96-774b-bcce-b302099a8060';
const attendancePath = '/api/v1/listings/event-1/event/attendance';
const personalChannel = 'user#$organizerId';

Map<String, Object?> account(String id) => {
  ...userJson,
  ...filledProfileJson,
  'id': id,
  'first_name': 'Ivan',
  'last_name': 'Ivanov',
};

Map<String, Object?> markJson({
  required String id,
  required String participant,
  required String name,
  String status = 'marked',
  String method = 'self',
  bool registered = true,
}) => {
  'id': id,
  'listing_id': 'event-1',
  'participant_id': participant,
  'participant_name': name,
  'interaction_id': 'interaction-$id',
  'status': status,
  'method': method,
  'marked_at': '2026-12-01T18:00:00Z',
  'marked_by_id': participant,
  'removed_at': status == 'removed' ? '2026-12-01T18:05:00Z' : null,
  'removed_by_id': status == 'removed' ? organizerId : null,
  'registered': registered,
};

/// Attendance state and responses of the fake server.
class FakeAttendanceBackend {
  FakeAttendanceBackend({this.mode = 'self', this.open = true, DateTime? start})
    : startsAt =
          start ??
          (open
              ? DateTime.now().toUtc().subtract(const Duration(hours: 1))
              : DateTime.now().toUtc().add(const Duration(hours: 2))),
      endsAt =
          (start ??
                  (open
                      ? DateTime.now().toUtc().subtract(
                          const Duration(hours: 1),
                        )
                      : DateTime.now().toUtc().add(const Duration(hours: 2))))
              .add(const Duration(hours: 2));

  final String listingId = 'event-1';
  final DateTime startsAt;
  final DateTime endsAt;
  String mode;
  bool open;
  String viewer = organizerId;
  bool registered = true;
  bool historyLost = false;

  /// A problem code the next self mark answers instead of marking.
  String? selfProblem;

  /// How many attempts of a self mark fail like a dropped connection.
  int selfNetworkFailures = 0;
  int qrRequests = 0;
  int codeRequests = 0;
  int listRequests = 0;
  int version = 1;
  final items = <Map<String, Object?>>[];

  Map<String, Object?> listing() => eventListingJson(
    id: listingId,
    author: organizerId,
    startsAt: startsAt.toIso8601String(),
    endsAt: endsAt.toIso8601String(),
    attendanceMode: mode,
  );

  Map<String, Object?> get _list => {
    'listing_id': listingId,
    'mode': mode,
    'version': version,
    'items': items,
    'marked_count': items.where((item) => item['status'] == 'marked').length,
    'server_time': _now,
  };

  String get _now => DateTime.now().toUtc().toIso8601String();

  Map<String, Object?> _code(String code) {
    final now = DateTime.now().toUtc();
    return {
      'listing_id': listingId,
      'mode': mode,
      'code': code,
      'issued_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(seconds: 30)).toIso8601String(),
      'server_time': now.toIso8601String(),
    };
  }

  Map<String, Object?> _attendance(Map<String, Object?> item, String result) =>
      {...item, 'result': result, 'version': version, 'server_time': _now};

  Map<String, Object?> _mark(String participant, String name) {
    final existing = items.where(
      (item) => item['participant_id'] == participant,
    );
    if (existing.isNotEmpty && existing.first['status'] == 'marked') {
      return _attendance(existing.first, 'already_marked');
    }
    final id = 'attendance-${items.length + 1}';
    final item = markJson(
      id: id,
      participant: participant,
      name: name,
      method: mode,
    );
    version += 1;
    if (existing.isEmpty) {
      items.add(item);
    } else {
      existing.first
        ..['status'] = 'marked'
        ..['removed_at'] = null
        ..['removed_by_id'] = null;
    }
    return _attendance(item, 'marked');
  }

  ResponseBody reply(RequestOptions options) {
    final options1 = options;
    final path = options1.path;
    final method = options1.method;
    if (path == '/api/v1/auth/token/refresh') {
      return jsonBody(200, tokensJson(1));
    }
    if (path == '/api/v1/realtime/subscription-token') {
      final body = jsonDecode(options1.data! as String) as Map<String, Object?>;
      return jsonBody(200, {
        'token': 'subscription-token',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'channel': body['channel'],
      });
    }
    if (path == '/api/v1/realtime/recover') {
      final body = jsonDecode(options1.data! as String) as Map<String, Object?>;
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
    if (method == 'GET' && path == attendancePath) {
      listRequests++;
      return jsonBody(200, _list);
    }
    if (method == 'PUT' && path == '$attendancePath/mode') {
      final body = jsonDecode(options1.data! as String) as Map<String, Object?>;
      final changed = body['mode'] != mode;
      mode = body['mode']! as String;
      if (changed) version += 1;
      return jsonBody(200, {
        'listing_id': listingId,
        'mode': mode,
        'version': version,
        'changed': changed,
      });
    }
    if (method == 'POST' && path == '$attendancePath/qr') {
      qrRequests++;
      return jsonBody(200, _code('organizer-code-$qrRequests'));
    }
    if (method == 'POST' && path == '$attendancePath/code') {
      codeRequests++;
      if (!registered) {
        return problemBody(403, 'event_attendance_not_registered');
      }
      if (mode != 'scan') {
        return problemBody(409, 'event_attendance_mode_conflict');
      }
      return jsonBody(200, _code('personal-code-$codeRequests'));
    }
    if (method == 'POST' && path == '$attendancePath/self') {
      if (selfNetworkFailures > 0) {
        selfNetworkFailures--;
        throw DioException.connectionError(
          requestOptions: options1,
          reason: 'Connection reset by peer',
        );
      }
      final problem = selfProblem;
      if (problem != null) {
        return problemBody(
          problem == 'event_attendance_not_registered' ? 403 : 409,
          problem,
        );
      }
      if (!registered) {
        return problemBody(403, 'event_attendance_not_registered');
      }
      return jsonBody(200, _mark(viewer, 'Ivan Ivanov'));
    }
    if (method == 'POST' && path == '$attendancePath/scan') {
      return jsonBody(200, _mark(participantId, 'Petr Petrov'));
    }
    if (method == 'DELETE' && path.startsWith('$attendancePath/')) {
      final participant = path.substring('$attendancePath/'.length);
      final item = items.firstWhere(
        (item) => item['participant_id'] == participant,
      );
      if (item['status'] == 'removed') {
        return jsonBody(200, _attendance(item, 'already_removed'));
      }
      item
        ..['status'] = 'removed'
        ..['removed_at'] = _now
        ..['removed_by_id'] = organizerId;
      version += 1;
      return jsonBody(200, _attendance(item, 'removed'));
    }
    throw StateError('No reply for ${options1.method} ${options1.path}');
  }
}

/// Advances fake time in bounded steps: the screen rebuilds once a second
/// and the HTTP stack needs frames and timers, while an unbounded
/// `pumpAndSettle` cannot settle forever and awaiting a future of the fake
/// SDK blocks until a timer that only a pump advances.
Future<void> settle(WidgetTester tester, {int steps = 15}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the app signed in as [viewer] and pushes [path].
Future<(FakeCentrifugeClient, FakeHttpAdapter)> open(
  WidgetTester tester,
  FakeAttendanceBackend backend,
  String path, {
  String viewer = organizerId,
}) async {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  backend.viewer = viewer;
  final client = FakeCentrifugeClient();
  final server = FakeHttpAdapter(
    me: account(viewer),
    feed: pageJson([backend.listing()]),
  )..route(backend.reply);
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
    overrides: [realtimeClientProvider.overrideWithValue(client)],
  );
  unawaited(container.read(appRouterProvider).push(path));
  await settle(tester);
  return (client, server);
}

FakeSubscription subscription(FakeCentrifugeClient client) =>
    client.getSubscription(personalChannel)! as FakeSubscription;

List<SentRequest> sentTo(FakeHttpAdapter server, String method, String path) =>
    server.sent
        .where((request) => request.method == method && request.path == path)
        .toList();

Future<void> wakeup(
  WidgetTester tester,
  FakeCentrifugeClient client,
  Map<String, Object?> data,
) async {
  subscription(client).addPublication(offset: 1, data: data);
  await settle(tester);
}

String? codeOf(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const Key('attendance-code')))
    .data;

void main() {
  testWidgets('the organizer switches the mode and the rotating code follows', (
    tester,
  ) async {
    final backend = FakeAttendanceBackend();
    final (client, server) = await open(
      tester,
      backend,
      '/event/event-1/attendance',
    );

    expect(find.byKey(const Key('attendance-mode-self')), findsOneWidget);
    expect(find.byKey(const Key('attendance-mode-scan')), findsOneWidget);
    expect(codeOf(tester), 'organizer-code-1');
    expect(backend.qrRequests, 1);
    expect(subscription(client).channel, personalChannel);

    await tester.tap(find.byKey(const Key('attendance-mode-scan')));
    await settle(tester);

    final put = sentTo(server, 'PUT', '$attendancePath/mode').single;
    expect(put.json['mode'], 'scan');
    expect(put.headers['Idempotency-Key'], isA<String>());
    expect(find.byKey(const Key('attendance-code')), findsNothing);
    expect(find.byKey(const Key('attendance-scan-code')), findsOneWidget);

    await tester.tap(find.byKey(const Key('attendance-mode-self')));
    await settle(tester);

    expect(backend.mode, 'self');
    expect(codeOf(tester), 'organizer-code-2');
    expect(backend.qrRequests, 2);
  });

  testWidgets('a realtime wakeup adds a mark without a restart', (
    tester,
  ) async {
    final backend = FakeAttendanceBackend();
    final (client, _) = await open(
      tester,
      backend,
      '/event/event-1/attendance',
    );
    expect(find.text('Nobody has been marked yet.'), findsOneWidget);

    backend.items.add(
      markJson(
        id: 'attendance-1',
        participant: participantId,
        name: 'Petr Petrov',
      ),
    );
    await wakeup(tester, client, {
      'listing_id': 'event-1',
      'status': 'marked',
      'attendance_id': 'attendance-1',
    });

    expect(find.text('Petr Petrov'), findsOneWidget);
    expect(find.text('Marked: 1'), findsOneWidget);

    // A publication of another event of the same organiser does not reload
    // this list.
    final before = backend.listRequests;
    await wakeup(tester, client, {'listing_id': 'event-2'});
    expect(backend.listRequests, before);
  });

  testWidgets('a reconnect with a lost history restores the list from the '
      'server', (tester) async {
    final backend = FakeAttendanceBackend();
    final (client, _) = await open(
      tester,
      backend,
      '/event/event-1/attendance',
    );
    expect(find.text('Nobody has been marked yet.'), findsOneWidget);

    // Another device marked two people while this client was disconnected.
    backend.items.addAll([
      markJson(
        id: 'attendance-1',
        participant: participantId,
        name: 'Petr Petrov',
      ),
      markJson(
        id: 'attendance-2',
        participant: '01890a5d-ac96-774b-bcce-b302099a8061',
        name: 'Anna Smirnova',
      ),
    ]);

    client.dropConnection();
    await settle(tester, steps: 3);
    backend.historyLost = true;
    unawaited(client.reconnect());
    await settle(tester, steps: 5);
    unawaited(subscription(client).recoverLost());
    await settle(tester, steps: 30);

    expect(find.text('Petr Petrov'), findsOneWidget);
    expect(find.text('Anna Smirnova'), findsOneWidget);
    expect(find.text('Marked: 2'), findsOneWidget);
  });

  testWidgets('the organizer removes a mark and the list shows it', (
    tester,
  ) async {
    final backend = FakeAttendanceBackend()
      ..items.addAll([
        markJson(
          id: 'attendance-1',
          participant: participantId,
          name: 'Petr Petrov',
        ),
        markJson(
          id: 'attendance-2',
          participant: '01890a5d-ac96-774b-bcce-b302099a8061',
          name: 'Anna Smirnova',
        ),
      ]);
    final (_, server) = await open(
      tester,
      backend,
      '/event/event-1/attendance',
    );
    expect(find.text('Marked: 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('attendance-remove-attendance-1')));
    await settle(tester);

    final delete = sentTo(
      server,
      'DELETE',
      '$attendancePath/$participantId',
    ).single;
    expect(delete.headers['Idempotency-Key'], isA<String>());
    expect(find.text('The mark was removed.'), findsOneWidget);
    expect(find.text('Marked: 1'), findsOneWidget);
    expect(find.textContaining('mark removed'), findsOneWidget);
    expect(
      find.byKey(const Key('attendance-remove-attendance-1')),
      findsNothing,
    );
  });

  testWidgets('the organizer marks a participant by a personal code', (
    tester,
  ) async {
    final backend = FakeAttendanceBackend(mode: 'scan');
    final (_, server) = await open(
      tester,
      backend,
      '/event/event-1/attendance',
    );

    await tester.enterText(
      find.byKey(const Key('attendance-scan-code')),
      'personal-code',
    );
    await tester.tap(find.byKey(const Key('attendance-scan-submit')));
    await settle(tester);

    final post = sentTo(server, 'POST', '$attendancePath/scan').single;
    expect(post.json['code'], 'personal-code');
    expect(post.headers['Idempotency-Key'], isA<String>());
    expect(find.text('Petr Petrov is marked present.'), findsOneWidget);
    expect(find.text('Petr Petrov'), findsOneWidget);
    expect(find.text('Marked: 1'), findsOneWidget);
  });

  testWidgets('a registered participant marks themselves', (tester) async {
    final backend = FakeAttendanceBackend();
    final (_, server) = await open(
      tester,
      backend,
      '/event/event-1/attendance',
      viewer: participantId,
    );

    expect(find.byKey(const Key('attendance-self-code')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('attendance-self-code')),
      'organizer-code',
    );
    await tester.tap(find.byKey(const Key('attendance-self-submit')));
    await settle(tester);

    final post = sentTo(server, 'POST', '$attendancePath/self').single;
    expect(post.json['code'], 'organizer-code');
    expect(find.text('You are marked at the event.'), findsOneWidget);
  });

  testWidgets('a participant who is not registered is refused', (tester) async {
    final backend = FakeAttendanceBackend()..registered = false;
    await open(
      tester,
      backend,
      '/event/event-1/attendance',
      viewer: participantId,
    );

    await tester.enterText(
      find.byKey(const Key('attendance-self-code')),
      'organizer-code',
    );
    await tester.tap(find.byKey(const Key('attendance-self-submit')));
    await settle(tester);

    expect(
      find.text('Only a registered participant can be marked.'),
      findsOneWidget,
    );
  });

  testWidgets('an expired code is explained', (tester) async {
    final backend = FakeAttendanceBackend()
      ..selfProblem = 'event_attendance_code_expired';
    await open(
      tester,
      backend,
      '/event/event-1/attendance',
      viewer: participantId,
    );

    await tester.enterText(
      find.byKey(const Key('attendance-self-code')),
      'old-code',
    );
    await tester.tap(find.byKey(const Key('attendance-self-submit')));
    await settle(tester);

    expect(
      find.text('The code has expired. Ask for a new one.'),
      findsOneWidget,
    );
  });

  testWidgets('a repeat after a lost connection keeps the Idempotency-Key', (
    tester,
  ) async {
    // The transport already repeats a dropped request; every attempt of the
    // first tap fails, so the user has to retry explicitly.
    final backend = FakeAttendanceBackend()..selfNetworkFailures = 4;
    final (_, server) = await open(
      tester,
      backend,
      '/event/event-1/attendance',
      viewer: participantId,
    );

    await tester.enterText(
      find.byKey(const Key('attendance-self-code')),
      'organizer-code',
    );
    await tester.tap(find.byKey(const Key('attendance-self-submit')));
    await settle(tester);

    expect(find.byKey(const Key('attendance-error')), findsOneWidget);
    final attempts = sentTo(server, 'POST', '$attendancePath/self');
    expect(attempts, hasLength(4));
    expect(
      attempts.map((request) => request.headers['Idempotency-Key']).toSet(),
      hasLength(1),
    );

    await tester.tap(find.byKey(const Key('attendance-self-submit')));
    await settle(tester);

    expect(find.text('You are marked at the event.'), findsOneWidget);
    final all = sentTo(server, 'POST', '$attendancePath/self');
    expect(all, hasLength(5));
    expect(
      all.map((request) => request.headers['Idempotency-Key']).toSet(),
      hasLength(1),
    );
  });

  testWidgets('the personal code refreshes before it expires', (tester) async {
    final backend = FakeAttendanceBackend(mode: 'scan');
    await open(
      tester,
      backend,
      '/event/event-1/attendance',
      viewer: participantId,
    );

    expect(codeOf(tester), 'personal-code-1');
    expect(backend.codeRequests, 1);
    expect(find.textContaining('The code refreshes in'), findsOneWidget);

    await tester.pump(const Duration(seconds: 25));
    await settle(tester);

    expect(backend.codeRequests, 2);
    expect(codeOf(tester), 'personal-code-2');
  });

  testWidgets('before and after the window the screens show the window state', (
    tester,
  ) async {
    final before = FakeAttendanceBackend(open: false);
    await open(
      tester,
      before,
      '/event/event-1/attendance',
      viewer: participantId,
    );
    expect(find.byKey(const Key('attendance-window-before')), findsOneWidget);
    expect(find.byKey(const Key('attendance-self-code')), findsNothing);
    expect(before.codeRequests, 0);

    final after = FakeAttendanceBackend(
      start: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
    );
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await open(
      tester,
      after,
      '/event/event-1/attendance',
      viewer: participantId,
    );
    expect(find.byKey(const Key('attendance-window-after')), findsOneWidget);
    expect(find.byKey(const Key('attendance-self-code')), findsNothing);
  });

  testWidgets('the listing opens the attendance of a participant', (
    tester,
  ) async {
    final backend = FakeAttendanceBackend();
    await open(tester, backend, '/listings/event-1', viewer: participantId);

    expect(find.byKey(const Key('event-attendance-open')), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-attendance-open')));
    await settle(tester);

    expect(find.byKey(const Key('attendance-self-code')), findsOneWidget);
    expect(backend.listRequests, 0);
  });

  testWidgets('the listing opens the attendance controls of the author', (
    tester,
  ) async {
    final backend = FakeAttendanceBackend();
    await open(tester, backend, '/listings/event-1');

    expect(find.byKey(const Key('event-attendance-manage')), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-attendance-manage')));
    await settle(tester);

    expect(find.byKey(const Key('attendance-mode-self')), findsOneWidget);
    expect(backend.listRequests, greaterThanOrEqualTo(1));
  });
}
