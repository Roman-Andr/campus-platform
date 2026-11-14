import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/features/listings/application/listings.dart';
import 'package:campus/src/features/listings/domain/feed.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'search keeps query on pagination and isolates cached results',
    () async {
      final cache = InMemoryListingsCache();
      final server = FakeHttpAdapter(
        feed: pageJson([listingJson()], next: 'next'),
      );
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
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      container.read(feedSearchProvider.notifier).search('  bikes  ');
      await container.read(provider.future);
      server.feed = null;
      server.route(
        (options) => jsonBody(
          200,
          pageJson([
            {...listingJson(id: 'second'), 'title': 'Second bike'},
          ]),
        ),
      );
      await container.read(provider.notifier).more();
      final sent = server.sent.lastWhere((r) => r.path == '/api/v1/listings');
      expect(sent.query['q'], 'bikes');
      expect(sent.query['cursor'], 'next');
      expect(container.read(provider).value!.items.length, 2);
      expect(cache.pages.keys, contains('test-session-cache/city|q=bikes'));
      expect(cache.pages.keys, contains('test-session-cache/city'));
      expect(
        searchCacheKey(Visibility.city, FeedFilters.none, 'a&b'),
        isNot(searchCacheKey(Visibility.city, FeedFilters.none, 'a')),
      );
    },
  );

  testWidgets('typing searches, loads more, shows empty and clears to feed', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final server = FakeHttpAdapter(feed: pageJson([listingJson()]));
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    server.feed = null;
    server.route((options) {
      if (options.queryParameters['q'] == 'nothing') {
        return jsonBody(200, pageJson([]));
      }
      if (options.queryParameters['q'] == 'bikes') {
        final more = options.queryParameters['cursor'] != null;
        return jsonBody(
          200,
          pageJson([
            {
              ...listingJson(id: more ? 'second' : 'bike'),
              'title': more ? 'Second bike' : 'Bike result',
            },
          ], next: more ? null : 'next'),
        );
      }
      return jsonBody(200, pageJson([listingJson()]));
    });
    await tester.enterText(find.byKey(const Key('feed-search')), 'bikes');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Bike result'), findsOneWidget);
    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Bike result'), findsOneWidget);
    expect(find.text('Second bike'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('feed-search')), 'nothing');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('No matching listings'), findsOneWidget);
    await tester.tap(find.byKey(const Key('feed-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('A desk'), findsOneWidget);
    expect(
      server.sent.lastWhere((r) => r.path == '/api/v1/listings').query['q'],
      isNull,
    );
  });
}
