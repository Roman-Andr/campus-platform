import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/api/api_failure_message.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_ru.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/listings/presentation/listings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

Map<String, Object?> interactionJson(String status) => {
  'id': 'request-1',
  'listing_id': 'listing-1',
  'participant_id': userJson['id'],
  'participant_name': 'Ivan',
  'stage': null,
  'response_due_at': null,
  'status': status,
  'created_at': '2026-11-14T00:00:00Z',
  'listing': {
    'id': 'listing-1',
    'kind': 'giveaway',
    'title': 'A desk',
    'status': 'busy',
    'city_timezone': 'Europe/Moscow',
  },
};

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

void main() {
  for (final locale in ['en', 'ru']) {
    final l = locale == 'en' ? AppLocalizationsEn() : AppLocalizationsRu();
    for (final status in ListingStatusValue.values) {
      testWidgets('$locale listing ${status.value} renders its label', (
        tester,
      ) async {
        tester.platformDispatcher.localesTestValue = [Locale(locale)];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        final server = FakeHttpAdapter(
          feed: pageJson([listingJson(status: status.value, author: 'other')]),
        );
        await tester.pumpCampusApp(
          InMemorySettingsRepository(),
          adapter: server,
        );
        expect(
          find.textContaining(
            listingStatusLabel(l, ListingStatusKnown(status)),
          ),
          findsOneWidget,
        );
      });
    }
    for (final status in InteractionStatusValue.values) {
      testWidgets('$locale interaction ${status.value} renders its label', (
        tester,
      ) async {
        tester.platformDispatcher.localesTestValue = [Locale(locale)];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        final server = FakeHttpAdapter()
          ..route((r) {
            if (r.path.endsWith('/token/refresh')) {
              return jsonBody(200, tokensJson(1));
            }
            if (r.path.endsWith('/reservations/mine')) {
              return jsonBody(200, pageJson([interactionJson(status.value)]));
            }
            if (r.path.endsWith('/events') || r.path.endsWith('/mine')) {
              return jsonBody(200, pageJson([]));
            }
            return jsonBody(200, listingJson(author: 'other'));
          });
        final container = await tester.pumpCampusApp(
          InMemorySettingsRepository(),
          adapter: server,
        );
        unawaited(container.read(appRouterProvider).push('/my-listings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.listingsReservations));
        await tester.pumpAndSettle();
        expect(
          find.text(interactionStatusLabel(l, InteractionStatusKnown(status))),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('draft can be saved without a category, edited and published', (
    tester,
  ) async {
    english(tester);
    var item = listingJson(status: 'draft')..['category_id'] = null;
    final server = FakeHttpAdapter()
      ..route((r) {
        if (r.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (r.path.endsWith('/giveaways')) {
          expect(r.data, contains('"draft":true'));
          return jsonBody(201, item);
        }
        if (r.path.endsWith('/publish')) {
          item = {
            ...item,
            'status': 'active',
            'version': 3,
            'expires_at': '2026-12-14T00:00:00Z',
          };
          return jsonBody(200, item);
        }
        if (r.method == 'PATCH') {
          item = {
            ...item,
            'title': 'Edited desk',
            'category_id': 'category-items',
            'version': 2,
          };
          return jsonBody(200, item);
        }
        if (r.path.endsWith('/interactions')) {
          return jsonBody(200, pageJson([]));
        }
        if (r.path.endsWith('/mine')) return jsonBody(200, pageJson([item]));
        return jsonBody(200, item);
      });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('listing-title')), 'A desk');
    await tester.enterText(
      find.byKey(const Key('listing-description')),
      'Collect on campus',
    );
    await tester.ensureVisible(find.text('Save draft'));
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(
      server.sent
          .singleWhere((r) => r.path.endsWith('/giveaways'))
          .json['draft'],
      true,
    );
    unawaited(container.read(appRouterProvider).push('/my-listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-section-drafts')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Draft'), findsWidgets);
    await tester.tap(find.text('Edit draft'));
    await tester.pumpAndSettle();
    expect(find.text('A desk'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('listing-title')),
      'Edited desk',
    );
    await tester.tap(find.byKey(const Key('listing-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Items').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final edit = server.sent.singleWhere((r) => r.method == 'PATCH');
    expect(edit.json, {
      'title': 'Edited desk',
      'description': 'Collect on campus',
      'version': 1,
      'category_id': 'category-items',
    });
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Available'), findsOneWidget);
    for (final r in server.sent.where(
      (r) => r.method == 'PATCH' || r.path.endsWith('/publish'),
    )) {
      expect(r.headers['Idempotency-Key'], isNotEmpty);
    }
  });

  testWidgets('employee audience is fixed to community in the sent draft', (
    tester,
  ) async {
    english(tester);
    final server =
        FakeHttpAdapter(
          me: {...userJson, ...filledProfileJson, 'account_type': 'employee'},
        )..route(
          (r) => r.path.endsWith('/token/refresh')
              ? jsonBody(200, tokensJson(1))
              : jsonBody(201, listingJson(status: 'draft')),
        );
    await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButtonFormField<Audience>>(
      find.byType(DropdownButtonFormField<Audience>),
    );
    expect(dropdown.onChanged, isNull);
    expect(dropdown.initialValue, Audience.community);
    await tester.enterText(find.byKey(const Key('listing-title')), 'A desk');
    await tester.enterText(
      find.byKey(const Key('listing-description')),
      'Collect on campus',
    );
    await tester.ensureVisible(find.text('Save draft'));
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(
      server.sent
          .singleWhere((r) => r.path.endsWith('/giveaways'))
          .json['audience'],
      'community',
    );
  });

  testWidgets('archive republishes and active card extends with fresh data', (
    tester,
  ) async {
    english(tester);
    var status = 'expired';
    final server = FakeHttpAdapter()
      ..route((r) {
        if (r.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (r.path.endsWith('/publish')) status = 'active';
        if (r.path.endsWith('/interactions')) {
          return jsonBody(200, pageJson([]));
        }
        if (r.path.endsWith('/mine')) {
          return jsonBody(200, pageJson([listingJson(status: status)]));
        }
        return jsonBody(200, listingJson(status: status));
      });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    unawaited(container.read(appRouterProvider).push('/my-listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-section-archive')));
    await tester.pumpAndSettle();
    // Thumbnails may fetch photos after the list request, so look it up.
    expect(
      server.sent
          .lastWhere((r) => r.path.endsWith('/mine'))
          .uri
          .queryParametersAll['status'],
      ['expired', 'completed', 'cancelled', 'hidden'],
    );
    expect(find.textContaining('Expired'), findsOneWidget);
    await tester.tap(find.text('Publish again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Expired'), findsNothing);
    expect(find.textContaining('Available'), findsOneWidget);
    await tester.tap(find.text('A desk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extend listing'));
    await tester.pumpAndSettle();
    expect(
      server.sent
          .singleWhere((r) => r.path.endsWith('/extend'))
          .headers['Idempotency-Key'],
      isNotEmpty,
    );
    expect(
      server.sent
          .where((r) => r.path.endsWith('/listing-1') && r.method == 'GET')
          .length,
      greaterThan(1),
    );
  });

  for (final status in ['pending', 'accepted']) {
    testWidgets('participant cancels $status from card and sees result', (
      tester,
    ) async {
      english(tester);
      var current = status;
      final server = FakeHttpAdapter()
        ..route((r) {
          if (r.path.endsWith('/token/refresh')) {
            return jsonBody(200, tokensJson(1));
          }
          if (r.path.endsWith('/transition')) {
            current = 'cancelled';
            return jsonBody(200, interactionJson(current));
          }
          if (r.path.endsWith('/reservations/mine')) {
            return jsonBody(200, pageJson([interactionJson(current)]));
          }
          return jsonBody(200, listingJson(author: 'other', status: 'busy'));
        });
      final container = await tester.pumpCampusApp(
        InMemorySettingsRepository(),
        adapter: server,
      );
      unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel request or reservation'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Cancel request or reservation'), findsNothing);
      final request = server.sent.singleWhere(
        (r) => r.path.endsWith('/transition'),
      );
      expect(request.json, {'status': 'cancelled'});
      expect(request.headers['Idempotency-Key'], isNotEmpty);
    });
  }

  testWidgets('429 shows retry duration and keeps expired listing', (
    tester,
  ) async {
    english(tester);
    final server = FakeHttpAdapter()
      ..route((r) {
        if (r.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (r.path.endsWith('/publish')) {
          return problemBody(429, 'listing_rate_limited', retryAfter: 73);
        }
        if (r.path.endsWith('/interactions')) {
          return jsonBody(200, pageJson([]));
        }
        return jsonBody(200, listingJson(status: 'expired'));
      });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish again'));
    await tester.pumpAndSettle();
    expect(
      find.text('Too many requests. Try again in 73 seconds.'),
      findsOneWidget,
    );
    expect(find.text('Expired'), findsOneWidget);
    expect(server.sent.where((r) => r.path.endsWith('/publish')), hasLength(1));
  });

  for (final entry in {
    'listing_expired': 'The listing expired.',
    'listing_cancelled': 'The author closed the listing.',
    'author_timeout': 'The author did not respond in time.',
    'future_reason': 'The request was rejected.',
  }.entries) {
    testWidgets('rejection reason ${entry.key} uses latest paginated event', (
      tester,
    ) async {
      english(tester);
      final cursors = <Object?>[];
      final server = FakeHttpAdapter()
        ..route((r) {
          if (r.path.endsWith('/token/refresh')) {
            return jsonBody(200, tokensJson(1));
          }
          if (r.path.endsWith('/reservations/mine')) {
            return jsonBody(200, pageJson([interactionJson('rejected')]));
          }
          if (r.path.endsWith('/events')) {
            cursors.add(r.queryParameters['cursor']);
            final more = r.queryParameters['cursor'] != null;
            return jsonBody(
              200,
              pageJson([
                {
                  'id': more ? 'event-2' : 'event-1',
                  'interaction_id': 'request-1',
                  'actor_id': null,
                  'action': 'auto_rejected',
                  'previous_status': 'pending',
                  'status': 'rejected',
                  'version': more ? 3 : 2,
                  'created_at': '2026-11-14T00:00:00Z',
                  'reason': more ? entry.key : 'listing_cancelled',
                  'stage': null,
                  'via_assistant': false,
                  'offline_qr': false,
                },
              ], next: more ? null : 'next'),
            );
          }
          return jsonBody(200, listingJson(author: 'other', status: 'expired'));
        });
      final container = await tester.pumpCampusApp(
        InMemorySettingsRepository(),
        adapter: server,
      );
      unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
      await tester.pumpAndSettle();
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(cursors, [null, 'next']);
      expect(find.text('Cancel request or reservation'), findsNothing);
    });
  }

  test('rate limit and stale version messages are localized', () {
    for (final l in [AppLocalizationsEn(), AppLocalizationsRu()]) {
      const problem = Problem(
        type: 'urn:test',
        title: 'Technical title',
        status: 429,
        code: ProblemCode.listingRateLimited,
      );
      expect(
        apiFailureMessage(
          l,
          const ProblemFailure(problem, retryAfter: Duration(seconds: 73)),
        ),
        l.listingRateLimitedFor(73),
      );
      expect(
        apiFailureMessage(l, const ProblemFailure(problem)),
        l.errorRateLimited,
      );
      expect(
        apiFailureMessage(
          l,
          const ProblemFailure(
            Problem(
              type: 'urn:test',
              title: 'Technical',
              status: 409,
              code: ProblemCode.listingVersionConflict,
            ),
          ),
        ),
        l.listingVersionConflict,
      );
      expect(
        listingFailureMessage(
          l,
          const ProblemFailure(
            Problem(
              type: 'urn:test',
              title: 'Technical',
              status: 409,
              code: ProblemCode.listingConflict,
            ),
          ),
        ),
        l.listingTransitionConflict,
      );
      expect(
        listingFailureMessage(
          l,
          const ProblemFailure(
            Problem(
              type: 'urn:test',
              title: 'Technical',
              status: 404,
              code: ProblemCode.notFound,
            ),
          ),
        ),
        l.listingUnavailable,
      );
    }
  });
}
