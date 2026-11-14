import 'dart:async';

import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/listings/domain/feed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

/// Pins a notice in the feed fixtures.
Map<String, Object?> pinnedNotice({
  String id = 'pinned',
  String title = 'Pinned notice',
}) => {
  ...listingJson(
    id: id,
    kind: 'publication',
    pinnedUntil: '2099-01-01T00:00:00Z',
  ),
  'title': title,
};

const headmanRoles = [
  {'role': 'headman', 'dormitory_id': 'dorm-dubki', 'faculty_id': null},
];

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

void main() {
  testWidgets('pinned notices stay above the feed offline', (tester) async {
    english(tester);
    final cache = InMemoryListingsCache();
    final server = FakeHttpAdapter(
      feed: pageJson([
        pinnedNotice(),
        {...listingJson(id: 'ordinary'), 'title': 'Ordinary desk'},
      ]),
    );

    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      cache: cache,
    );

    expect(find.byKey(const Key('feed-pinned-header')), findsOneWidget);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Pinned notice')).dy,
      lessThan(tester.getTopLeft(find.text('Ordinary desk')).dy),
    );

    // Restart without a network: the snapshot, pins included, is restored.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    server
      ..feed = null
      ..failConnection();
    final offlineSecure = {
      ...signedInStorage,
      'auth.refresh_token': 'refresh-1',
    };
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      cache: cache,
      secure: offlineSecure,
    );

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.byKey(const Key('feed-pinned-header')), findsOneWidget);
    expect(find.text('Pinned notice'), findsOneWidget);
  });

  testWidgets('feed filters reload the feed and survive a restart', (
    tester,
  ) async {
    english(tester);
    final filters = InMemoryFeedFiltersRepository();
    final server =
        FakeHttpAdapter(
          categories: const {
            'items': [
              {'id': 'category-items', 'code': 'items', 'name': 'Items'},
              {'id': 'category-study', 'code': 'study', 'name': 'Stationery'},
            ],
          },
          feed: pageJson([listingJson()]),
        )..route((options) {
          if (options.path.endsWith('/token/refresh')) {
            return jsonBody(200, tokensJson(1));
          }
          if (options.path == '/api/v1/university/dormitories') {
            return jsonBody(200, {
              'items': [
                {
                  'id': 'dorm-dubki',
                  'city_id': 'city-moscow',
                  'city_timezone': 'Europe/Moscow',
                  'code': 'dubki',
                  'name': 'Dubki',
                },
              ],
            });
          }
          return jsonBody(200, pageJson([listingJson()]));
        });

    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      filters: filters,
    );

    await tester.tap(find.byKey(const Key('feed-filter-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stationery').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feed-filter-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notice').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feed-filter-dormitory')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dubki').last);
    await tester.pumpAndSettle();

    expect(filters.saved.categoryId, 'category-study');
    expect(filters.saved.kind, FeedKind.publication);
    expect(filters.saved.dormitoryId, 'dorm-dubki');
    expect(find.byKey(const Key('feed-filters-reset')), findsOneWidget);
    final filtered = server.sent.lastWhere(
      (request) => request.path == '/api/v1/listings',
    );
    expect(filtered.query['category_id'], 'category-study');
    expect(filtered.query['kind'], 'publication');
    expect(filtered.query['dormitory_id'], 'dorm-dubki');

    // The next app start restores the same selection and requests it at once.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    server.sent.clear();
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      filters: filters,
    );
    final restored = server.sent.lastWhere(
      (request) => request.path == '/api/v1/listings',
    );
    expect(restored.query['category_id'], 'category-study');
    expect(restored.query['kind'], 'publication');
    expect(restored.query['dormitory_id'], 'dorm-dubki');
    expect(filters.saved.kind, FeedKind.publication);
  });

  testWidgets('the create-notice action belongs to headmen only', (
    tester,
  ) async {
    english(tester);
    final student = FakeHttpAdapter(me: {...userJson, ...filledProfileJson});
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: student);
    expect(find.byKey(const Key('feed-create-publication')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final headman = FakeHttpAdapter(
      me: {...userJson, ...filledProfileJson, 'roles': headmanRoles},
    );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: headman);
    expect(find.byKey(const Key('feed-create-publication')), findsOneWidget);
  });

  testWidgets('a headman pins a notice for their dormitory', (tester) async {
    english(tester);
    final server =
        FakeHttpAdapter(
          me: {...userJson, ...filledProfileJson, 'roles': headmanRoles},
        )..route((options) {
          if (options.path.endsWith('/publications')) {
            return jsonBody(
              201,
              listingJson(
                kind: 'publication',
                pinnedUntil: '2099-01-01T00:00:00Z',
              ),
            );
          }
          if (options.path.endsWith('/token/refresh')) {
            return jsonBody(200, tokensJson(1));
          }
          return jsonBody(200, pageJson([]));
        });
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);

    await tester.tap(find.byKey(const Key('feed-create-publication')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('publication-title')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('publication-title')),
      'Water outage',
    );
    await tester.enterText(
      find.byKey(const Key('publication-description')),
      'No water tomorrow',
    );
    await tester.ensureVisible(find.text('Publish'));
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    final post = server.sent.singleWhere(
      (request) =>
          request.method == 'POST' &&
          request.path == '/api/v1/listings/publications',
    );
    expect(post.json['title'], 'Water outage');
    expect(post.json['visibility'], 'dormitory');
    expect(post.json['dormitory_id'], 'dorm-dubki');
    expect(post.json.containsKey('faculty_id'), isFalse);
    expect(
      DateTime.parse(post.json['pinned_until']! as String)
          .isAfter(DateTime.now()),
      isTrue,
    );
  });

  testWidgets('a notice shows its pin and can be unpinned', (tester) async {
    english(tester);
    final publication = {
      ...pinnedNotice(id: 'pub-1', title: 'Water outage'),
      'description': 'No water tomorrow',
    };
    final server =
        FakeHttpAdapter(
          me: {...userJson, ...filledProfileJson, 'roles': headmanRoles},
        )..route((options) {
          if (options.path.endsWith('/unpin')) {
            return jsonBody(200, {...publication, 'pinned_until': null});
          }
          if (options.path.endsWith('/token/refresh')) {
            return jsonBody(200, tokensJson(1));
          }
          if (options.path == '/api/v1/listings/pub-1') {
            return jsonBody(200, publication);
          }
          return jsonBody(200, pageJson([]));
        });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    unawaited(container.read(appRouterProvider).push('/listings/pub-1'));
    await tester.pumpAndSettle();

    expect(find.text('Water outage'), findsOneWidget);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Reserve'), findsNothing);
    expect(find.byKey(const Key('publication-edit')), findsOneWidget);

    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();
    expect(
      server.sent.where(
        (request) =>
            request.method == 'POST' && request.path.endsWith('/unpin'),
      ),
      hasLength(1),
    );
  });

  testWidgets('a headman edits a notice and its pin deadline', (tester) async {
    english(tester);
    final publication = {
      ...pinnedNotice(id: 'pub-1', title: 'Water outage'),
      'description': 'No water tomorrow',
    };
    final server =
        FakeHttpAdapter(
          me: {...userJson, ...filledProfileJson, 'roles': headmanRoles},
        )..route((options) {
          if (options.method == 'PATCH' &&
              options.path == '/api/v1/listings/pub-1') {
            return jsonBody(200, {...publication, 'title': 'Water restored'});
          }
          if (options.path.endsWith('/token/refresh')) {
            return jsonBody(200, tokensJson(1));
          }
          if (options.path == '/api/v1/listings/pub-1') {
            return jsonBody(200, publication);
          }
          return jsonBody(200, pageJson([]));
        });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    unawaited(container.read(appRouterProvider).push('/listings/pub-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('publication-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('publication-title')),
      'Water restored',
    );
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final patch = server.sent.singleWhere(
      (request) => request.method == 'PATCH',
    );
    expect(patch.json['title'], 'Water restored');
    expect(patch.json['version'], 1);
    expect(patch.json['pinned_until'], '2099-01-01T00:00:00.000Z');
  });
}
