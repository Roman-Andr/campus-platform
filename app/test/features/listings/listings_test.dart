import 'dart:convert';
import 'dart:io';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/listings/application/listings.dart';
import 'package:campus/src/features/listings/data/listings_repository.dart';
import 'package:campus/src/features/listings/domain/feed.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Drift restores legacy snapshots and every new listing status',
    () async {
      final db = createTestDatabase();
      final cache = DriftListingsCache(db);
      final legacy = listingJson()
        ..remove('category_id')
        ..remove('hidden_reason')
        ..remove('pinned_until')
        ..remove('archived_at')
        ..remove('purged_at');
      await db
          .into(db.listingFeeds)
          .insert(
            ListingFeedsCompanion.insert(
              owner: 'legacy',
              area: 'city',
              payload: jsonEncode(pageJson([legacy])),
            ),
          );
      final restored = (await cache.load(
        'legacy',
        feedCacheKey(Visibility.city, FeedFilters.none),
      ))!.items.single;
      expect(restored.categoryId, isNull);
      expect(restored.hiddenReason, isNull);
      expect(restored.pinnedUntil, isNull);
      expect(restored.archivedAt, isNull);
      expect(restored.purgedAt, isNull);
      expect(restored.title, 'A desk');
      for (final status in ['draft', 'completed', 'hidden']) {
        await cache.save(
          'session',
          feedCacheKey(Visibility.city, FeedFilters.none),
          PageListingOutput.fromJson(pageJson([listingJson(status: status)])),
        );
        final item = (await cache.load(
          'session',
          feedCacheKey(Visibility.city, FeedFilters.none),
        ))!.items.single;
        expect(item.status.toJson(), status);
        if (status == 'draft') expect(item.expiresAt, isNull);
      }
    },
  );
  test(
    'Drift persists pages, replaces snapshots and isolates session and area',
    () async {
      final db = createTestDatabase();
      final cache = DriftListingsCache(db);
      final page = PageListingOutput.fromJson(
        pageJson([listingJson()], next: 'cursor'),
      );
      await cache.save(
        'alice',
        feedCacheKey(Visibility.city, FeedFilters.none),
        page,
      );
      expect(
        (await DriftListingsCache(db).load(
          'alice',
          feedCacheKey(Visibility.city, FeedFilters.none),
        ))!.items.single.title,
        'A desk',
      );
      expect(
        await cache.load(
          'bob',
          feedCacheKey(Visibility.city, FeedFilters.none),
        ),
        isNull,
      );
      expect(
        await cache.load(
          'alice',
          feedCacheKey(Visibility.faculty, FeedFilters.none),
        ),
        isNull,
      );
      await cache.save(
        'alice',
        feedCacheKey(Visibility.city, FeedFilters.none),
        const PageListingOutput(items: [], nextPage: null),
      );
      expect(
        (await cache.load(
          'alice',
          feedCacheKey(Visibility.city, FeedFilters.none),
        ))!.items,
        isEmpty,
      );
      await cache.clear();
      expect(
        await cache.load(
          'alice',
          feedCacheKey(Visibility.city, FeedFilters.none),
        ),
        isNull,
      );
    },
  );

  test('a feed survives closing and reopening the SQLite database', () async {
    final directory = await Directory.systemTemp.createTemp('campus-feed-');
    final file = File('${directory.path}/cache.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    try {
      await DriftListingsCache(db).save(
        'session',
        feedCacheKey(Visibility.city, FeedFilters.none),
        PageListingOutput.fromJson(pageJson([listingJson()])),
      );
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      expect(
        (await DriftListingsCache(db).load(
          'session',
          feedCacheKey(Visibility.city, FeedFilters.none),
        ))!.items.single.title,
        'A desk',
      );
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'pagination sends the cursor, deduplicates items and caches the result',
    () async {
      final server = FakeHttpAdapter(feed: null)
        ..route(
          (options) => options.path.endsWith('/token/refresh')
              ? jsonBody(200, tokensJson(1))
              : jsonBody(
                  200,
                  options.queryParameters['cursor'] == null
                      ? pageJson([listingJson()], next: 'next')
                      : pageJson([listingJson(), listingJson(id: 'listing-2')]),
                ),
        );
      final cache = InMemoryListingsCache();
      final container = ProviderContainer(
        overrides: [
          ...apiOverrides(
            adapter: server,
            cache: cache,
            secure: signedInStorage,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authStatusProvider.future);
      final provider = listingFeedProvider(Visibility.city);
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      expect((await container.read(provider.future)).items, hasLength(1));
      await container.read(provider.notifier).more();
      expect(container.read(provider).value!.items, hasLength(2));
      expect(cache.pages.values.single.items, hasLength(2));
      expect(container.read(provider).value!.nextPage, isNull);
    },
  );

  test('a fresh container offline restores a saved feed', () async {
    final cache = InMemoryListingsCache();
    final server = FakeHttpAdapter(feed: pageJson([listingJson()]));
    ProviderContainer start() => ProviderContainer(
      overrides: [
        ...apiOverrides(adapter: server, cache: cache, secure: signedInStorage),
      ],
    );
    var container = start();
    await container.read(authStatusProvider.future);
    var sub = container.listen(listingFeedProvider(Visibility.city), (_, _) {});
    await container.read(listingFeedProvider(Visibility.city).future);
    sub.close();
    container.dispose();
    server.feed = null;
    server.failConnection();
    container = start();
    await container.read(authStatusProvider.future);
    sub = container.listen(listingFeedProvider(Visibility.city), (_, _) {});
    expect(
      (await container.read(listingFeedProvider(Visibility.city).future))
          .items
          .single
          .title,
      'A desk',
    );
    sub.close();
    container.dispose();
  });

  test('server rejection is shown even when a cached feed exists', () async {
    final cache = InMemoryListingsCache();
    await cache.save(
      'test-session-cache',
      feedCacheKey(Visibility.city, FeedFilters.none),
      PageListingOutput.fromJson(pageJson([listingJson()])),
    );
    final server = FakeHttpAdapter(feed: null)
      ..route(
        (options) => options.path.endsWith('/token/refresh')
            ? jsonBody(200, tokensJson(2))
            : problemBody(403, 'listing_forbidden'),
      );
    final container = ProviderContainer(
      overrides: apiOverrides(
        adapter: server,
        cache: cache,
        secure: signedInStorage,
      ),
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    final sub = container.listen(
      listingFeedProvider(Visibility.city),
      (_, _) {},
    );
    addTearDown(sub.close);
    await expectLater(
      container.read(listingFeedProvider(Visibility.city).future),
      throwsA(isA<DioException>()),
    );
  });
}
