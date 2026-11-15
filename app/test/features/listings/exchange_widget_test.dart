import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

Map<String, Object?> offerJson({
  String id = 'offer-1',
  String participantId = 'participant-1',
  String participantName = 'Boris Petrov',
  String status = 'pending',
  String description = 'A wooden chair',
  String? reservationDueAt,
  Map<String, Object?>? meeting,
}) => {
  'id': id,
  'listing_id': 'listing-1',
  'participant_id': participantId,
  'participant_name': participantName,
  'status': status,
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'reservation_due_at': ?reservationDueAt,
  'offer_description': description,
  'meeting': meeting,
};

Map<String, Object?> rejectedEventJson() => {
  'id': 'event-1',
  'interaction_id': 'offer-2',
  'waitlist_entry_id': null,
  'actor_id': 'author',
  'action': 'auto_rejected',
  'previous_status': 'pending',
  'status': 'rejected',
  'version': 2,
  'created_at': '2026-11-15T00:00:00Z',
  'reason': 'another_offer_accepted',
  'stage': null,
  'details': null,
  'via_assistant': false,
  'offline_qr': false,
};

Map<String, Object?> exchangeListingJson({
  String author = 'author',
  String status = 'active',
}) => {
  ...listingJson(
    kind: 'exchange',
    author: author,
    status: status,
    authorName: 'Anna Author',
  ),
  'title': 'A desk lamp',
};

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

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

void main() {
  testWidgets('the home button publishes an exchange listing', (tester) async {
    english(tester);
    final server = FakeHttpAdapter(feed: pageJson([]))
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/exchanges')) {
          return jsonBody(201, exchangeListingJson());
        }
        return jsonBody(200, pageJson([]));
      });
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);

    await tester.tap(find.byKey(const Key('feed-create-exchange')));
    await tester.pumpAndSettle();
    expect(find.text('New exchange listing'), findsOneWidget);
    await tester.tap(find.byKey(const Key('listing-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Items').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('listing-title')),
      'A desk lamp',
    );
    await tester.enterText(
      find.byKey(const Key('listing-description')),
      'I want to swap it for a chair',
    );
    await tester.ensureVisible(find.text('Publish'));
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    final published = server.sent.singleWhere(
      (request) => request.path.endsWith('/exchanges'),
    );
    expect(published.method, 'POST');
    expect(published.json['title'], 'A desk lamp');
    expect(published.json['description'], 'I want to swap it for a chair');
  });

  testWidgets('a compact phone opens the exchange form from the menu', (
    tester,
  ) async {
    english(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = FakeHttpAdapter(feed: pageJson([]))
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        return jsonBody(200, pageJson([]));
      });
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);

    expect(find.byKey(const Key('feed-create-exchange')), findsNothing);
    await tester.tap(find.byKey(const Key('home-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-create-exchange')));
    await tester.pumpAndSettle();
    expect(find.text('New exchange listing'), findsOneWidget);
  });

  testWidgets('a participant offers an item and sees it pending', (
    tester,
  ) async {
    english(tester);
    var offers = <Map<String, Object?>>[];
    final server = FakeHttpAdapter(feed: pageJson([]))
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/exchange-offers') &&
            options.method == 'GET') {
          return jsonBody(200, {'items': offers});
        }
        if (options.path.endsWith('/exchange-offers') &&
            options.method == 'POST') {
          final body =
              jsonDecode(options.data! as String) as Map<String, Object?>;
          final created = offerJson(
            description: body['description']! as String,
            participantId: userJson['id']! as String,
            participantName: 'Ivan Ivanov',
          );
          offers = [created];
          return jsonBody(201, created);
        }
        if (options.path == '/api/v1/listings/listing-1') {
          return jsonBody(200, exchangeListingJson());
        }
        return jsonBody(200, pageJson([]));
      });
    await openListing(tester, server);

    expect(find.byKey(const Key('exchange-offer-description')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('exchange-offer-description')),
      'A wooden chair',
    );
    await tester.tap(find.byKey(const Key('exchange-offer-send')));
    await tester.pumpAndSettle();

    final sent = server.sent.singleWhere(
      (request) =>
          request.method == 'POST' && request.path.endsWith('/exchange-offers'),
    );
    expect(sent.json['description'], 'A wooden chair');
    expect(find.text('Your offer: A wooden chair'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.byKey(const Key('exchange-offer-description')), findsNothing);
  });

  testWidgets('the author sees every offer and chooses one', (tester) async {
    english(tester);
    final due = DateTime.now().toUtc().add(
      const Duration(hours: 46, minutes: 30),
    );
    var offers = [
      offerJson(),
      offerJson(
        id: 'offer-2',
        participantId: 'participant-2',
        participantName: 'Dana Doe',
        description: 'A floor lamp',
      ),
    ];
    final server = FakeHttpAdapter(feed: pageJson([]))
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/exchange-offers')) {
          return jsonBody(200, {'items': offers});
        }
        if (options.path.endsWith('/transition')) {
          final chosen = options.path.contains('offer-1');
          offers = [
            offerJson(
              status: chosen ? 'accepted' : 'rejected',
              reservationDueAt: chosen ? due.toIso8601String() : null,
            ),
            offerJson(
              id: 'offer-2',
              participantId: 'participant-2',
              participantName: 'Dana Doe',
              description: 'A floor lamp',
              status: chosen ? 'rejected' : 'accepted',
              reservationDueAt: chosen ? null : due.toIso8601String(),
            ),
          ];
          return jsonBody(
            200,
            offers.firstWhere(
              (item) => item['id'] == (chosen ? 'offer-1' : 'offer-2'),
            ),
          );
        }
        if (options.path == '/api/v1/listings/listing-1') {
          return jsonBody(
            200,
            exchangeListingJson(author: userJson['id']! as String),
          );
        }
        if (options.path.endsWith('/events')) {
          return jsonBody(200, pageJson([rejectedEventJson()]));
        }
        return jsonBody(200, pageJson([]));
      });
    await openListing(tester, server);

    expect(find.text('Offers: A wooden chair'), findsOneWidget);
    expect(find.text('Offers: A floor lamp'), findsOneWidget);
    final card = find
        .ancestor(
          of: find.text('Offers: A wooden chair'),
          matching: find.byType(Card),
        )
        .first;
    final choose = find.descendant(of: card, matching: find.text('Choose'));
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();

    final transition = server.sent.singleWhere(
      (request) => request.path.endsWith('/transition'),
    );
    expect(transition.json['status'], 'accepted');
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('The author chose another offer.'), findsOneWidget);
    expect(find.textContaining('Hold ends in 46 h'), findsOneWidget);
    expect(find.text('Schedule a meeting to keep the hold.'), findsOneWidget);
  });

  testWidgets('a participant whose offer lost sees the reason', (tester) async {
    english(tester);
    final server = FakeHttpAdapter(feed: pageJson([]))
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/exchange-offers')) {
          return jsonBody(200, {
            'items': [
              offerJson(
                participantId: userJson['id']! as String,
                participantName: 'Ivan Ivanov',
                status: 'rejected',
              ),
            ],
          });
        }
        if (options.path.endsWith('/events')) {
          return jsonBody(200, pageJson([rejectedEventJson()]));
        }
        if (options.path == '/api/v1/listings/listing-1') {
          return jsonBody(200, exchangeListingJson(status: 'busy'));
        }
        return jsonBody(200, pageJson([]));
      });
    await openListing(tester, server);

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('The author chose another offer.'), findsOneWidget);
    expect(find.text('Your offer: A wooden chair'), findsOneWidget);
    expect(find.byKey(const Key('exchange-offer-description')), findsNothing);
  });
}
