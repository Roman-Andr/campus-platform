import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/router/app_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

const organizerId = '01890a5d-ac96-774b-bcce-b302099a8058';
const participantId = '01890a5d-ac96-774b-bcce-b302099a8060';
const queuedId = '01890a5d-ac96-774b-bcce-b302099a8061';

const names = {
  organizerId: 'Ivan Ivanov',
  participantId: 'Petr Petrov',
  queuedId: 'Anna Smirnova',
};

Map<String, Object?> account(String id) => {
  ...userJson,
  ...filledProfileJson,
  'id': id,
  'first_name': names[id]!.split(' ').first,
  'last_name': names[id]!.split(' ').last,
};

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// Makes the whole form visible without scrolling inside a small surface.
void wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The event state that the UI mutates through real requests.
class FakeEventBackend {
  FakeEventBackend({this.capacity = 1, this.title = 'Campus concert'});

  final String id = 'event-1';
  final String author = organizerId;
  String viewer = organizerId;
  String title;
  String location = 'Hall A';
  int capacity;
  int registered = 0;
  bool capacityConflict = false;
  final participants = <String>{};
  final queue = <String>[];
  late final DateTime startsAt = DateTime.now().toUtc().add(
    const Duration(days: 3),
  );
  late final DateTime endsAt = startsAt.add(const Duration(hours: 2));

  int get remaining => capacity - registered;

  Map<String, Object?> listing() => eventListingJson(
    id: id,
    author: author,
    title: title,
    capacity: capacity,
    remaining: remaining,
    startsAt: startsAt.toIso8601String(),
    endsAt: endsAt.toIso8601String(),
    location: location,
  );

  Map<String, Object?> interaction(String participant, {String? status}) => {
    'id': 'interaction-$participant',
    'listing_id': id,
    'participant_name': names[participant] ?? 'Guest',
    'participant_id': participant,
    'status':
        status ??
        (participants.contains(participant) ? 'accepted' : 'cancelled'),
    'stage': null,
    'response_due_at': null,
    'executor': false,
    'meeting': null,
  };

  Map<String, Object?> participation(String participant) => {
    ...interaction(participant),
    'created_at': '2026-11-14T00:00:00Z',
    'listing': {
      'id': id,
      'kind': 'event',
      'title': title,
      'status': 'active',
      'city_timezone': 'Europe/Moscow',
    },
  };

  Map<String, Object?> entry(String participant) => {
    ...waitlistJson(listingId: id, position: queue.indexOf(participant) + 1),
    'participant_id': participant,
  };

  ResponseBody signup() {
    if (participants.contains(viewer)) return registeredReply();
    if (remaining > 0) {
      participants.add(viewer);
      registered += 1;
      return registeredReply();
    }
    return jsonBody(200, {
      'result': 'full',
      'interaction': null,
      'remaining_places': remaining,
    });
  }

  ResponseBody registeredReply() => jsonBody(200, {
    'result': 'registered',
    'interaction': interaction(viewer),
    'remaining_places': remaining,
  });

  ResponseBody reply(RequestOptions options) {
    final path = options.path;
    final method = options.method;
    if (path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (method == 'GET' && path == '/api/v1/listings/$id') {
      return jsonBody(200, listing());
    }
    if (method == 'GET' && path == '/api/v1/listings/reservations/mine') {
      return jsonBody(
        200,
        pageJson([if (participants.contains(viewer)) participation(viewer)]),
      );
    }
    if (method == 'GET' && path.endsWith('/cancellation')) {
      return jsonBody(200, interactionCancellationJson());
    }
    if (method == 'GET' && path == '/api/v1/listings/$id/waitlist/me') {
      return queue.contains(viewer)
          ? jsonBody(200, entry(viewer))
          : problemBody(404, 'not_found');
    }
    if (method == 'POST' && path == '/api/v1/listings/$id/signup') {
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      if (remaining <= 0 && body['join_queue'] == true) {
        if (!queue.contains(viewer)) queue.add(viewer);
        return jsonBody(200, {
          'result': 'queued',
          'interaction': null,
          'remaining_places': remaining,
        });
      }
      return signup();
    }
    if (method == 'DELETE' && path == '/api/v1/listings/$id/waitlist') {
      queue.remove(viewer);
      return jsonBody(204);
    }
    if (method == 'POST' &&
        path.startsWith('/api/v1/listings/$id/interactions/')) {
      if (participants.remove(viewer)) registered -= 1;
      return jsonBody(200, interaction(viewer, status: 'cancelled'));
    }
    if (method == 'GET' && path == '/api/v1/listings/$id/interactions') {
      return jsonBody(
        200,
        pageJson([
          for (final participant in participants) interaction(participant),
        ]),
      );
    }
    if (method == 'POST' && path == '/api/v1/listings/events') {
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      title = body['title']! as String;
      location = body['location']! as String;
      capacity = body['capacity']! as int;
      return jsonBody(201, listing());
    }
    if (method == 'PATCH' && path == '/api/v1/listings/$id/event') {
      if (capacityConflict) {
        return problemBody(409, 'event_capacity_conflict');
      }
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      capacity = body['capacity']! as int;
      return jsonBody(200, listing());
    }
    return jsonBody(200, pageJson([]));
  }
}

FakeHttpAdapter serverFor(FakeEventBackend backend, String viewer) {
  backend.viewer = viewer;
  return FakeHttpAdapter(
    me: account(viewer),
    feed: pageJson([backend.listing()]),
  )..route(backend.reply);
}

Future<ProviderContainer> open(
  WidgetTester tester,
  FakeHttpAdapter server,
  String path,
) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
  );
  unawaited(container.read(appRouterProvider).push(path));
  await tester.pumpAndSettle();
  return container;
}

Future<void> restart(
  WidgetTester tester,
  FakeHttpAdapter server,
  String path,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await open(tester, server, path);
}

Future<void> publish(
  WidgetTester tester, {
  required String title,
  required String location,
  required String capacity,
}) async {
  await tester.tap(find.byKey(const Key('event-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Items').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('event-title')), title);
  await tester.enterText(
    find.byKey(const Key('event-description')),
    'Meet in the hall',
  );
  await tester.enterText(find.byKey(const Key('event-location')), location);
  await tester.enterText(find.byKey(const Key('event-capacity')), capacity);
  await tester.tap(find.byKey(const Key('event-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the form publishes the schedule, place and seat limit', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakeEventBackend(capacity: 5);
    final server = serverFor(backend, organizerId);
    await open(tester, server, '/event/new');

    expect(find.byKey(const Key('event-title')), findsOneWidget);
    await publish(
      tester,
      title: 'Campus concert',
      location: 'Hall A',
      capacity: '1',
    );

    final post = server.sent.singleWhere(
      (request) =>
          request.method == 'POST' && request.path == '/api/v1/listings/events',
    );
    expect(post.json['title'], 'Campus concert');
    expect(post.json['description'], 'Meet in the hall');
    expect(post.json['location'], 'Hall A');
    expect(post.json['capacity'], 1);
    expect(post.json['visibility'], 'city');
    expect(post.json['audience'], 'students');
    expect(post.json['draft'], isFalse);
    final startsAt = DateTime.parse(post.json['starts_at']! as String);
    final endsAt = DateTime.parse(post.json['ends_at']! as String);
    expect(startsAt.isAfter(DateTime.now().toUtc()), isTrue);
    expect(endsAt.isAfter(startsAt), isTrue);
    expect(backend.capacity, 1);
  });

  testWidgets('an employee publishes for the whole community', (tester) async {
    english(tester);
    wide(tester);
    const employeeId = '01890a5d-ac96-774b-bcce-b302099a8062';
    final backend = FakeEventBackend(capacity: 5);
    final server = FakeHttpAdapter(
      me: {
        ...userJson,
        ...filledProfileJson,
        'id': employeeId,
        'account_type': 'employee',
      },
      feed: pageJson([backend.listing()]),
    )..route(backend.reply);
    backend.viewer = employeeId;

    await open(tester, server, '/event/new');
    expect(find.text('Community'), findsOneWidget);

    await publish(
      tester,
      title: 'Staff meeting',
      location: 'Hall B',
      capacity: '5',
    );

    final post = server.sent.singleWhere(
      (request) =>
          request.method == 'POST' && request.path == '/api/v1/listings/events',
    );
    expect(post.json['audience'], 'community');
  });

  testWidgets('the edit form refuses a limit below the registered count', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakeEventBackend(capacity: 3)
      ..registered = 3
      ..participants.addAll([
        participantId,
        queuedId,
        '01890a5d-ac96-774b-bcce-b302099a8062',
      ]);
    final server = serverFor(backend, organizerId);
    await open(tester, server, '/event/event-1/edit');

    await tester.enterText(find.byKey(const Key('event-capacity')), '1');
    await tester.tap(find.byKey(const Key('event-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The seat limit cannot be lower than the number of registered '
        'participants: 3.',
      ),
      findsOneWidget,
    );
    expect(
      server.sent.where(
        (request) =>
            request.method == 'PATCH' &&
            request.path == '/api/v1/listings/event-1/event',
      ),
      isEmpty,
    );

    await tester.enterText(find.byKey(const Key('event-capacity')), '3');
    await tester.tap(find.byKey(const Key('event-submit')));
    await tester.pumpAndSettle();
    final patch = server.sent.singleWhere(
      (request) =>
          request.method == 'PATCH' &&
          request.path == '/api/v1/listings/event-1/event',
    );
    expect(patch.json['capacity'], 3);
    expect(patch.json['version'], 1);
    expect(backend.capacity, 3);
  });

  testWidgets('the server conflict explains the seat limit', (tester) async {
    english(tester);
    wide(tester);
    final backend = FakeEventBackend(capacity: 3)
      ..registered = 1
      ..participants.add(participantId)
      ..capacityConflict = true;
    final server = serverFor(backend, organizerId);
    await open(tester, server, '/event/event-1/edit');

    // The limit is not below the registered count, so the client sends it and
    // lets the server decide: somebody could have registered in between.
    await tester.enterText(find.byKey(const Key('event-capacity')), '1');
    await tester.tap(find.byKey(const Key('event-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The seat limit cannot be lower than the number of registered '
        'participants.',
      ),
      findsOneWidget,
    );
    expect(
      server.sent.where(
        (request) =>
            request.method == 'PATCH' &&
            request.path == '/api/v1/listings/event-1/event',
      ),
      isNotEmpty,
    );
    expect(backend.capacity, 3);
  });

  testWidgets('open, registered, full and queued are distinct card states', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakeEventBackend(capacity: 2);
    final server = serverFor(backend, participantId);
    await open(tester, server, '/listings/event-1');

    expect(find.byKey(const Key('event-seat-open')), findsOneWidget);
    expect(find.text('Seats left: 2'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);

    await tester.tap(find.byKey(const Key('event-signup')));
    await tester.pumpAndSettle();
    final signup = server.sent.singleWhere(
      (request) =>
          request.method == 'POST' &&
          request.path == '/api/v1/listings/event-1/signup',
    );
    expect(signup.json['join_queue'], isFalse);
    expect(find.byKey(const Key('event-seat-registered')), findsOneWidget);
    expect(find.text('You are registered'), findsOneWidget);
    expect(find.text('Seats left: 1'), findsOneWidget);
    expect(find.text('Cancel signup'), findsOneWidget);

    await tester.tap(find.byKey(const Key('event-cancel-signup')));
    await tester.pumpAndSettle();
    expect(
      server.sent.where(
        (request) =>
            request.method == 'POST' && request.path.endsWith('/transition'),
      ),
      isNotEmpty,
    );
    expect(find.byKey(const Key('event-seat-open')), findsOneWidget);

    // Somebody else takes the last seats while the card is open.
    backend
      ..registered = 2
      ..participants.addAll([queuedId, '01890a5d-ac96-774b-bcce-b302099a8062']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final queuedServer = serverFor(backend, participantId);
    await open(tester, queuedServer, '/listings/event-1');

    expect(find.byKey(const Key('event-seat-full')), findsOneWidget);
    expect(find.text('No seats left'), findsOneWidget);
    expect(find.text('Join the queue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('event-join-queue')));
    await tester.pumpAndSettle();
    final joinQueue = queuedServer.sent.lastWhere(
      (request) =>
          request.method == 'POST' &&
          request.path == '/api/v1/listings/event-1/signup',
    );
    expect(joinQueue.json['join_queue'], isTrue);
    expect(find.byKey(const Key('event-seat-queued')), findsOneWidget);
    expect(find.text('You are in the queue'), findsOneWidget);
    expect(find.text('Your place in the queue: 1'), findsOneWidget);
    expect(find.text('Leave queue'), findsOneWidget);
  });

  testWidgets('two participants sign up and queue for a one-seat event', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakeEventBackend();
    final container = await open(
      tester,
      serverFor(backend, organizerId),
      '/event/new',
    );
    await publish(
      tester,
      title: 'Integration concert',
      location: 'Hall A',
      capacity: '1',
    );
    unawaited(container.read(appRouterProvider).push('/listings/event-1'));
    await tester.pumpAndSettle();
    expect(find.text('Registered participants'), findsOneWidget);
    expect(find.text('No one has signed up yet'), findsOneWidget);

    await restart(
      tester,
      serverFor(backend, participantId),
      '/listings/event-1',
    );
    expect(find.text('Sign up'), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-signup')));
    await tester.pumpAndSettle();
    expect(find.text('You are registered'), findsOneWidget);

    await restart(tester, serverFor(backend, queuedId), '/listings/event-1');
    expect(find.text('No seats left'), findsOneWidget);
    expect(find.text('Join the queue'), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-join-queue')));
    await tester.pumpAndSettle();
    expect(find.text('You are in the queue'), findsOneWidget);

    await restart(tester, serverFor(backend, organizerId), '/listings/event-1');
    expect(find.text('No seats left'), findsOneWidget);
    expect(find.text('Petr Petrov'), findsOneWidget);
    expect(find.text('Registered'), findsOneWidget);
    expect(find.text('Registered participants'), findsOneWidget);
  });
}
