import 'dart:async';

import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/listings/application/listings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

void main() {
  testWidgets('feed opens a card and explains an already reserved item', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final server =
        FakeHttpAdapter(feed: pageJson([listingJson(author: 'other')]))..route(
          (options) => options.path.endsWith('/token/refresh')
              ? jsonBody(200, tokensJson(1))
              : options.method == 'POST'
              ? problemBody(409, 'listing_conflict')
              : jsonBody(200, listingJson(author: 'other')),
        );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await tester.tap(find.text('A desk'));
    await tester.pumpAndSettle();
    expect(find.text('Author: Ivan Ivanov'), findsOneWidget);
    await tester.tap(find.text('Reserve'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This item is already reserved or no longer available. Refresh the listing.',
      ),
      findsOneWidget,
    );
    final request = server.sent.last;
    expect(request.headers['Idempotency-Key'], isNotEmpty);
  });

  testWidgets('creation validates fields and publishes selected values', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final server = FakeHttpAdapter()
      ..route(
        (options) => options.path.endsWith('/token/refresh')
            ? jsonBody(200, tokensJson(1))
            : jsonBody(201, listingJson()),
      );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(find.text('Fill in this field.'), findsNWidgets(2));
    expect(server.sent.where((r) => r.path.endsWith('/giveaways')), isEmpty);
    await tester.enterText(find.byKey(const Key('listing-title')), 'A desk');
    await tester.enterText(
      find.byKey(const Key('listing-description')),
      'Collect on campus',
    );
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    final sent = server.sent.singleWhere((r) => r.path.endsWith('/giveaways'));
    expect(sent.json, {
      'title': 'A desk',
      'description': 'Collect on campus',
      'visibility': 'city',
      'audience': 'students',
    });
  });

  testWidgets('own card accepts and rejects pending incoming requests', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    var status = 'pending';
    Map<String, Object?> interaction() => {
      'id': 'request-1',
      'listing_id': 'listing-1',
      'participant_id': 'other',
      'participant_name': 'Boris',
      'status': status,
    };
    final server = FakeHttpAdapter()
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/transition')) {
          status = status == 'pending' ? 'accepted' : status;
          return jsonBody(200, interaction());
        }
        if (options.path.endsWith('/interactions')) {
          return jsonBody(200, pageJson([interaction()]));
        }
        return jsonBody(200, listingJson(status: 'busy'));
      });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
    await tester.pumpAndSettle();
    expect(find.text('Boris'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsOneWidget);
    expect(server.sent.lastWhere((r) => r.method == 'POST').json, {
      'status': 'accepted',
    });
    status = 'pending';
    container.invalidate(incomingProvider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(server.sent.lastWhere((r) => r.method == 'POST').json, {
      'status': 'rejected',
    });
  });

  testWidgets('offline start renders cached feed and offline banner', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final cache = InMemoryListingsCache();
    final server = FakeHttpAdapter(feed: pageJson([listingJson()]));
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      cache: cache,
    );
    expect(find.text('A desk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    server.feed = null;
    server.failConnection();
    final offlineSecure = {
      ...signedInStorage,
      'auth.refresh_token': 'refresh-1',
    };
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      secure: offlineSecure,
      cache: cache,
    );
    expect(find.text('A desk'), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
  });

  testWidgets('scope switching and loading more update the feed', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final scopes = <Object?>[];
    final server = FakeHttpAdapter(feed: null)
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        final area = options.queryParameters['area'];
        scopes.add(area);
        final more = options.queryParameters['cursor'] != null;
        return jsonBody(
          200,
          pageJson([
            {
              ...listingJson(id: more ? 'second' : 'first'),
              'title': more
                  ? 'Second desk'
                  : area == 'faculty'
                  ? 'Faculty desk'
                  : 'City desk',
            },
          ], next: more ? null : 'next'),
        );
      });
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    expect(find.text('City desk'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Second desk'), findsOneWidget);
    await tester.tap(find.text('City'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Faculty').last);
    await tester.pumpAndSettle();
    expect(find.text('Faculty desk'), findsOneWidget);
    expect(find.text('City desk'), findsNothing);
    expect(scopes, contains('faculty'));
  });

  testWidgets('My shows own listings and reservation statuses', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final server = FakeHttpAdapter()
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/reservations/mine')) {
          return jsonBody(
            200,
            pageJson([
              {
                'id': 'request',
                'listing_id': 'listing-1',
                'participant_id': userJson['id'],
                'participant_name': 'Ivan',
                'status': 'accepted',
              },
            ]),
          );
        }
        if (options.path.endsWith('/mine')) {
          return jsonBody(200, pageJson([listingJson()]));
        }
        return jsonBody(200, listingJson());
      });
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    expect(find.text('A desk'), findsOneWidget);
    await tester.tap(find.text('My reservations'));
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('A desk'), findsOneWidget);
  });
}
