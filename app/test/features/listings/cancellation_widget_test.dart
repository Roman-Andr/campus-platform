import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

Map<String, Object?> listingJsonWithStatus(String status) =>
    listingJson(status: status);

Map<String, Object?> participationRow({
  String status = 'accepted',
  String? cancelledBy,
  String? cancellationReason,
}) => {
  'id': 'interaction-1',
  'listing_id': 'listing-1',
  'participant_id': userJson['id'],
  'participant_name': 'Ivan Ivanov',
  'status': status,
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'cancelled_by': cancelledBy,
  'cancellation_reason': cancellationReason,
  'late_cancelled': false,
  'meeting': null,
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': 'listing-1',
    'kind': 'giveaway',
    'title': 'A desk',
    'status': 'busy',
    'city_timezone': 'Europe/Moscow',
  },
};

FakeHttpAdapter authorServer({
  required Map<String, Object?> Function() preview,
  required List<Map<String, Object?>> cancelled,
}) {
  var status = 'active';
  return FakeHttpAdapter(feed: pageJson([]))..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.method == 'GET' &&
        options.path == '/api/v1/listings/listing-1') {
      return jsonBody(200, listingJsonWithStatus(status));
    }
    if (options.method == 'GET' &&
        options.path == '/api/v1/listings/listing-1/cancellation') {
      return jsonBody(200, preview());
    }
    if (options.method == 'POST' &&
        options.path == '/api/v1/listings/listing-1/cancel') {
      cancelled.add(
        jsonDecode(options.data! as String) as Map<String, Object?>,
      );
      status = 'cancelled';
      return jsonBody(200, listingJsonWithStatus(status));
    }
    return jsonBody(200, pageJson([]));
  });
}

FakeHttpAdapter participantServer({
  required Map<String, Object?> participation,
  required Map<String, Object?> Function() preview,
  required List<Map<String, Object?>> transitions,
}) => FakeHttpAdapter(feed: pageJson([]))
  ..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.method == 'GET' &&
        options.path.endsWith('/reservations/mine')) {
      return jsonBody(200, pageJson([participation]));
    }
    if (options.method == 'GET' && options.path.endsWith('/cancellation')) {
      return jsonBody(200, preview());
    }
    if (options.method == 'POST' && options.path.endsWith('/transition')) {
      transitions.add(
        jsonDecode(options.data! as String) as Map<String, Object?>,
      );
      return jsonBody(200, {
        ...participation,
        'status': 'cancelled',
        'cancelled_by': 'participant',
      });
    }
    return jsonBody(200, pageJson([]));
  });

Future<ProviderContainer> openListing(
  WidgetTester tester,
  FakeHttpAdapter server,
) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
  );
  unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> openMy(
  WidgetTester tester,
  FakeHttpAdapter server,
) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
  );
  unawaited(container.read(appRouterProvider).push('/my-listings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('My participation'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('accepted listing cannot be cancelled without a reason', (
    tester,
  ) async {
    english(tester);
    final cancelled = <Map<String, Object?>>[];
    final server = authorServer(
      preview: () => listingCancellationJson(accepted: 1, required: true),
      cancelled: cancelled,
    );
    await openListing(tester, server);

    await tester.tap(find.byKey(const Key('listing-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('listing-cancellation-dialog')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Accepted interactions: 1. Participants will be notified with the '
        'reason.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('listing-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a cancellation reason.'), findsOneWidget);
    expect(cancelled, isEmpty);

    await tester.enterText(
      find.byKey(const Key('listing-cancel-reason')),
      'The shelf is gone',
    );
    await tester.tap(find.byKey(const Key('listing-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(cancelled.single['reason'], 'The shelf is gone');
    expect(find.text('Listing cancelled.'), findsOneWidget);
  });

  testWidgets('a listing without accepted interactions needs no reason', (
    tester,
  ) async {
    english(tester);
    final cancelled = <Map<String, Object?>>[];
    final server = authorServer(
      preview: listingCancellationJson,
      cancelled: cancelled,
    );
    await openListing(tester, server);

    await tester.tap(find.byKey(const Key('listing-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('listing-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(cancelled.single, isEmpty);
    expect(find.text('Enter a cancellation reason.'), findsNothing);
    expect(find.text('Listing cancelled.'), findsOneWidget);
  });

  testWidgets('a late participant cancellation shows the warning', (
    tester,
  ) async {
    english(tester);
    final transitions = <Map<String, Object?>>[];
    final server = participantServer(
      participation: participationRow(),
      preview: () => interactionCancellationJson(late: true),
      transitions: transitions,
    );
    await openMy(tester, server);

    await tester.tap(find.text('Cancel request or reservation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('late-cancellation-warning')), findsOneWidget);
    expect(
      find.text('This is a late cancellation: it will be counted as late.'),
      findsOneWidget,
    );
    expect(transitions, isEmpty);

    await tester.tap(find.byKey(const Key('interaction-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(transitions.single, {'status': 'cancelled'});
  });

  testWidgets('a safe participant cancellation has no late warning', (
    tester,
  ) async {
    english(tester);
    final transitions = <Map<String, Object?>>[];
    final server = participantServer(
      participation: participationRow(),
      preview: interactionCancellationJson,
      transitions: transitions,
    );
    await openMy(tester, server);

    await tester.tap(find.text('Cancel request or reservation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('late-cancellation-warning')), findsNothing);
    expect(find.byKey(const Key('interaction-cancel-confirm')), findsNothing);
    expect(transitions.single, {'status': 'cancelled'});
  });

  testWidgets('My shows the reason of an author cancellation', (tester) async {
    english(tester);
    final server = participantServer(
      participation: participationRow(
        status: 'cancelled',
        cancelledBy: 'author',
        cancellationReason: 'The shelf is gone',
      ),
      preview: interactionCancellationJson,
      transitions: [],
    );
    await openMy(tester, server);

    expect(find.text('Cancelled'), findsOneWidget);
    expect(
      find.text('The author cancelled: The shelf is gone'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('author-cancellation-interaction-1')),
      findsOneWidget,
    );
  });
}
