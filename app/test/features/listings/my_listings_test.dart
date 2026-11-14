import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_ru.dart';
import 'package:campus/src/features/listings/application/my_listings.dart';
import 'package:campus/src/features/listings/data/listings_repository.dart';
import 'package:campus/src/features/listings/data/my_cache.dart';
import 'package:campus/src/features/listings/domain/feed.dart';
import 'package:campus/src/features/listings/presentation/my_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

Map<String, Object?> participationJson({
  String status = 'pending',
  String? stage,
}) => {
  'id': 'interaction-1',
  'listing_id': 'listing-1',
  'participant_id': userJson['id'],
  'participant_name': 'Ivan Ivanov',
  'status': status,
  'stage': stage,
  'response_due_at': null,
  'executor': false,
  'meeting': null,
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': 'listing-1',
    'kind': 'giveaway',
    'title': 'A lamp',
    'status': 'busy',
    'city_timezone': 'Europe/Moscow',
  },
};

Map<String, Object?> favoritesJson() => pageJson([
  {
    'listing_id': 'listing-1',
    'created_at': '2026-11-14T00:00:00Z',
    'available': true,
    'listing': {...listingJson(author: 'other'), 'favorite': true},
  },
  {
    'listing_id': 'gone',
    'created_at': '2026-11-13T00:00:00Z',
    'available': false,
  },
]);

/// Routes everything but token refreshes to [reply].
FakeHttpAdapter serverWith(Object? Function(Uri uri, String method) reply) =>
    FakeHttpAdapter()..route((options) {
      if (options.path.endsWith('/token/refresh')) {
        return jsonBody(200, tokensJson(1));
      }
      final body = reply(options.uri, options.method);
      return body is int ? jsonBody(body, null) : jsonBody(200, body);
    });

Future<ProviderContainer> signedIn(
  FakeHttpAdapter server, {
  MyCache? cache,
  Stream<bool>? network,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...apiOverrides(
        adapter: server,
        myCache: cache,
        network: network,
        secure: signedInStorage,
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authStatusProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Drift keeps private snapshots per account apart from the feed',
    () async {
      final db = createTestDatabase();
      final cache = DriftMyCache(db);
      await cache.save('alice', 'favorites', favoritesJson());
      expect(await cache.load('bob', 'favorites'), isNull);
      expect(await cache.load('alice', 'participation'), isNull);
      final restored = PageFavoriteOutput.fromJson(
        (await cache.load('alice', 'favorites'))!,
      );
      expect(restored.items.first.listing!.title, 'A desk');
      expect(restored.items.last.listing, isNull);
      final feed = DriftListingsCache(db);
      expect(
        await feed.load(
          'alice',
          feedCacheKey(Visibility.city, FeedFilters.none),
        ),
        isNull,
      );
      await feed.clear();
      expect(await cache.load('alice', 'favorites'), isNull);
    },
  );

  test(
    'each section requests its statuses; archive covers closed ones',
    () async {
      final queries = <String, List<String>>{};
      final server = serverWith((uri, _) {
        queries[uri.queryParametersAll['status']!.first] =
            uri.queryParametersAll['status']!;
        return pageJson([listingJson()]);
      });
      final container = await signedIn(server);
      for (final section in MySection.values) {
        final sub = container.listen(myListingsProvider(section), (_, _) {});
        addTearDown(sub.close);
        await container.read(myListingsProvider(section).future);
      }
      expect(queries.values, [
        ['draft'],
        ['active'],
        ['busy'],
        ['expired', 'completed', 'cancelled', 'hidden'],
      ]);
    },
  );

  test('pagination appends pages, deduplicates and caches them', () async {
    final server = serverWith(
      (uri, _) => uri.queryParameters['cursor'] == null
          ? pageJson([participationJson()], next: 'next')
          : pageJson([
              participationJson(),
              {...participationJson(), 'id': 'interaction-2'},
            ]),
    );
    final cache = InMemoryMyCache();
    final container = await signedIn(server, cache: cache);
    final sub = container.listen(myParticipationProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(myParticipationProvider.future);
    await container.read(myParticipationProvider.notifier).more();
    final snapshot = container.read(myParticipationProvider).value!;
    expect(snapshot.page.items, hasLength(2));
    expect(snapshot.page.nextPage, isNull);
    expect(cache.pages.values.single['items'], hasLength(2));
  });

  test(
    'without network the views open from the cache, marked offline',
    () async {
      final cache = InMemoryMyCache();
      final server = serverWith(
        (uri, _) => uri.path.endsWith('/favorites')
            ? favoritesJson()
            : uri.path.endsWith('/reservations/mine')
            ? pageJson([participationJson()])
            : pageJson([listingJson()]),
      );
      var container = await signedIn(server, cache: cache);
      final subs = [
        container.listen(myListingsProvider(MySection.active), (_, _) {}),
        container.listen(myParticipationProvider, (_, _) {}),
        container.listen(favoritesProvider, (_, _) {}),
      ];
      final online = [
        await container.read(myListingsProvider(MySection.active).future),
        await container.read(myParticipationProvider.future),
        await container.read(favoritesProvider.future),
      ];
      expect([for (final s in online) s.offline], [false, false, false]);
      for (final sub in subs) {
        sub.close();
      }
      container.dispose();
      server.failConnection();
      container = await signedIn(server, cache: cache);
      final listings = await container.read(
        myListingsProvider(MySection.active).future,
      );
      expect(listings.offline, isTrue);
      expect(listings.page.items.single.title, 'A desk');
      final participation = await container.read(
        myParticipationProvider.future,
      );
      expect(participation.offline, isTrue);
      expect(participation.page.items.single.listing.title, 'A lamp');
      final favorites = await container.read(favoritesProvider.future);
      expect(favorites.offline, isTrue);
      expect(favorites.page.items.last.available, isFalse);
    },
  );

  test('a rejected bookmark is reverted and reported', () async {
    final server = FakeHttpAdapter()
      ..route(
        (options) => options.path.endsWith('/token/refresh')
            ? jsonBody(200, tokensJson(1))
            : problemBody(404, 'not_found'),
      );
    final container = await signedIn(server);
    final marks = container.read(favoriteMarksProvider.notifier);
    final listing = ListingOutput.fromJson(listingJson(author: 'other'));
    await expectLater(
      marks.set(listing.id, favorite: true),
      throwsA(isA<Object>()),
    );
    expect(marks.of(listing), isFalse);
    expect(server.sent.last.method, 'PUT');
    expect(server.sent.last.headers['Idempotency-Key'], isNotEmpty);
  });

  test('section and kind labels exist in RU and EN', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();
    expect(
      [for (final s in MySection.values) mySectionName(en, s)],
      ['Drafts', 'Active', 'Reserved', 'Archive'],
    );
    expect(
      [for (final s in MySection.values) mySectionName(ru, s)],
      ['Черновики', 'Активные', 'Занятые', 'Архив'],
    );
    expect(listingKindName(ru, 'giveaway'), 'Отдам даром');
    expect(listingKindName(en, 'future'), 'future');
    expect(ru.participationStage('x'), 'Этап: x');
  });

  testWidgets('favorites hide the content of unavailable listings', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final server = serverWith(
      (uri, method) => method == 'DELETE' ? 204 : favoritesJson(),
    );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await tester.tap(find.byKey(const Key('home-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('A desk'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('Listing unavailable'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove from favorites').last);
    await tester.pumpAndSettle();
    final delete = server.sent.lastWhere((r) => r.method == 'DELETE');
    expect(delete.path, '/api/v1/listings/gone/favorite');
  });

  testWidgets('the feed bookmarks a listing with one tap', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final server =
        FakeHttpAdapter(feed: pageJson([listingJson(author: 'other')]))..route(
          (options) => options.path.endsWith('/token/refresh')
              ? jsonBody(200, tokensJson(1))
              : options.method == 'PUT'
              ? jsonBody(204, null)
              : jsonBody(200, pageJson([])),
        );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    expect(find.byIcon(Icons.star_border), findsWidgets);
    await tester.tap(find.byKey(const Key('favorite-listing-1')));
    await tester.pumpAndSettle();
    final put = server.sent.lastWhere((r) => r.method == 'PUT');
    expect(put.path, '/api/v1/listings/listing-1/favorite');
    expect(
      find.descendant(
        of: find.byKey(const Key('favorite-listing-1')),
        matching: find.byIcon(Icons.star),
      ),
      findsOneWidget,
    );
  });

  testWidgets('My shows sections, participation stage and offline note', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final requested = <List<String>>[];
    final server = serverWith((uri, _) {
      if (uri.path.endsWith('/reservations/mine')) {
        return pageJson([
          participationJson(status: 'accepted', stage: 'handover'),
        ]);
      }
      requested.add(uri.queryParametersAll['status'] ?? []);
      return pageJson([listingJson(status: 'expired')]);
    });
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await tester.tap(find.byKey(const Key('home-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-my-listings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-section-archive')));
    await tester.pumpAndSettle();
    expect(requested.last, ['expired', 'completed', 'cancelled', 'hidden']);
    expect(find.textContaining('Срок истёк'), findsOneWidget);
    expect(find.byKey(const Key('my-offline')), findsNothing);
    await tester.tap(find.text('Моё участие'));
    await tester.pumpAndSettle();
    expect(find.text('A lamp'), findsOneWidget);
    expect(find.text('Отдам даром · Этап: handover'), findsOneWidget);
    expect(find.text('Принята'), findsOneWidget);
    expect(find.text('Отменить заявку или бронь'), findsOneWidget);
  });

  testWidgets('offline My lists show the saved-data note', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final cache = InMemoryMyCache()
      ..pages['test-session-cache/favorites'] = favoritesJson();
    final server = FakeHttpAdapter()..failConnection();
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      myCache: cache,
    );
    await tester.tap(find.byKey(const Key('home-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('Offline: showing saved data'), findsOneWidget);
    expect(find.text('Listing unavailable'), findsOneWidget);
  });
}
