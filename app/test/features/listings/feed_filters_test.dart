import 'dart:convert';
import 'dart:io';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/database/app_database.dart';
import 'package:campus/src/features/listings/application/feed_filters.dart';
import 'package:campus/src/features/listings/application/listings.dart';
import 'package:campus/src/features/listings/data/feed_filters_repository.dart';
import 'package:campus/src/features/listings/domain/feed.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FeedFilters', () {
    test('round-trip and ignore unknown values', () {
      const filters = FeedFilters(
        kind: FeedKind.publication,
        categoryId: 'category-items',
        dormitoryId: 'dorm-dubki',
      );
      expect(FeedFilters.fromJson(filters.toJson()), filters);
      expect(FeedFilters.fromJson({'kind': 'future'}), FeedFilters.none);
      expect(FeedFilters.fromJson('broken'), FeedFilters.none);
      expect(
        FeedFilters.fromJson({'kind': 1, 'category_id': '', 'dormitory_id': 2}),
        FeedFilters.none,
      );
    });

    test('cache keys separate every filter set', () {
      const filtered = FeedFilters(
        kind: FeedKind.giveaway,
        categoryId: 'category-items',
        dormitoryId: 'dorm-dubki',
      );
      expect(
        feedCacheKey(Visibility.city, FeedFilters.none),
        Visibility.city.toJson(),
      );
      expect(
        feedCacheKey(Visibility.city, filtered),
        'city|kind=giveaway&category=category-items&dormitory=dorm-dubki',
      );
      expect(
        feedCacheKey(Visibility.faculty, filtered),
        isNot(feedCacheKey(Visibility.city, filtered)),
      );
    });

    test('splits active pins from ordinary entries', () {
      final now = DateTime.utc(2026, 11, 14, 12);
      final pinned = ListingOutput.fromJson(
        listingJson(
          id: 'pinned',
          kind: 'publication',
          pinnedUntil: now.add(const Duration(hours: 1)).toIso8601String(),
        ),
      );
      final expired = ListingOutput.fromJson(
        listingJson(
          id: 'expired',
          kind: 'publication',
          pinnedUntil: now.subtract(const Duration(hours: 1)).toIso8601String(),
        ),
      );
      final ordinary = ListingOutput.fromJson(listingJson(id: 'ordinary'));

      final split = splitPinned([pinned, expired, ordinary], now);

      expect(split.pinned.map((item) => item.id), ['pinned']);
      expect(split.ordinary.map((item) => item.id), ['expired', 'ordinary']);
      expect(isPinnedAt(pinned, now), isTrue);
      expect(isPinnedAt(expired, now), isFalse);
      expect(isPinnedAt(ordinary, now), isFalse);
    });
  });

  test(
    'filters survive reopening the database and broken values are ignored',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'campus-filters-',
      );
      final file = File('${directory.path}/filters.sqlite');
      const saved = FeedFilters(
        kind: FeedKind.publication,
        categoryId: 'category-items',
        dormitoryId: 'dorm-dubki',
      );
      try {
        var db = AppDatabase(NativeDatabase(file));
        await DriftFeedFiltersRepository(db).save(saved);
        await db.close();

        db = AppDatabase(NativeDatabase(file));
        expect(await DriftFeedFiltersRepository(db).load(), saved);
        await db
            .into(db.preferences)
            .insertOnConflictUpdate(
              PreferencesCompanion.insert(
                key: 'listings.feed_filters',
                value: jsonEncode(['not', 'a', 'map']),
              ),
            );
        await db.close();

        db = AppDatabase(NativeDatabase(file));
        expect(await DriftFeedFiltersRepository(db).load(), FeedFilters.none);
        await db.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('selection restores stored filters and stores each change', () async {
    final store = InMemoryFeedFiltersRepository(
      const FeedFilters(kind: FeedKind.giveaway),
    );
    final container = ProviderContainer(
      overrides: [feedFiltersRepositoryProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(feedFilterSelectionProvider.future),
      const FeedFilters(kind: FeedKind.giveaway),
    );
    const wanted = FeedFilters(
      kind: FeedKind.publication,
      categoryId: 'category-items',
    );
    await container.read(feedFilterSelectionProvider.notifier).apply(wanted);
    expect(store.saved, wanted);
    expect(container.read(feedFilterSelectionProvider).value, wanted);
  });

  test('feed requests send filters and cache every selection apart', () async {
    final cache = InMemoryListingsCache();
    final server = FakeHttpAdapter(feed: pageJson([listingJson()]));
    final container = ProviderContainer(
      overrides: [
        ...apiOverrides(adapter: server, cache: cache, secure: signedInStorage),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    final provider = listingFeedProvider(Visibility.city);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    const filters = FeedFilters(
      kind: FeedKind.giveaway,
      categoryId: 'category-items',
      dormitoryId: 'dorm-dubki',
    );
    await container.read(feedFilterSelectionProvider.notifier).apply(filters);
    await container.read(provider.future);

    final filtered = server.sent.lastWhere(
      (request) => request.path == '/api/v1/listings',
    );
    expect(filtered.query, {
      'area': 'city',
      'kind': 'giveaway',
      'category_id': 'category-items',
      'dormitory_id': 'dorm-dubki',
    });
    expect(
      cache.pages.keys,
      contains('test-session-cache/${feedCacheKey(Visibility.city, filters)}'),
    );

    await container
        .read(feedFilterSelectionProvider.notifier)
        .apply(FeedFilters.none);
    await container.read(provider.future);

    expect(
      server.sent
          .lastWhere((request) => request.path == '/api/v1/listings')
          .query,
      {'area': 'city'},
    );
    expect(
      cache.pages.keys,
      contains(
        'test-session-cache/${feedCacheKey(Visibility.city, FeedFilters.none)}',
      ),
    );
  });

  test('pagination keeps the selected filters and the cursor', () async {
    final server = FakeHttpAdapter(
      feed: pageJson([listingJson()], next: 'next'),
    );
    final container = ProviderContainer(
      overrides: [...apiOverrides(adapter: server, secure: signedInStorage)],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    const filters = FeedFilters(kind: FeedKind.publication);
    await container.read(feedFilterSelectionProvider.notifier).apply(filters);
    final provider = listingFeedProvider(Visibility.faculty);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);

    await container.read(provider.notifier).more();

    final request = server.sent.lastWhere(
      (request) => request.path == '/api/v1/listings',
    );
    expect(request.query, {
      'area': 'faculty',
      'kind': 'publication',
      'cursor': 'next',
    });
  });
}
