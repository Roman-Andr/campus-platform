import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/core/router/notification_route.dart';
import 'package:campus/src/features/listings/application/listings.dart';
import 'package:campus/src/features/listings/application/waitlist.dart';
import 'package:campus/src/features/listings/presentation/waitlist_widgets.dart';
import 'package:clock/clock.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
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

List<LocalizationsDelegate<Object>> delegates() => const [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Map<String, Object?> interactionJson() => {
  'id': 'interaction-1',
  'listing_id': 'listing-1',
  'participant_id': userJson['id'],
  'participant_name': 'Ivan Ivanov',
  'status': 'pending',
  'stage': null,
  'response_due_at': null,
  'executor': false,
  'meeting': null,
};

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

/// A listing card server with a mutable own entry and listing status.
FakeHttpAdapter listingServer({
  required Map<String, Object?>? Function() own,
  required String Function() status,
  void Function(String method)? onQueueChange,
}) {
  Map<String, Object?>? entry;
  return FakeHttpAdapter(feed: pageJson([]))..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path.endsWith('/waitlist/me')) {
      entry = own();
      return entry == null
          ? problemBody(404, 'not_found')
          : jsonBody(200, entry!);
    }
    if (options.path.endsWith('/waitlist') && options.method == 'POST') {
      onQueueChange?.call(options.method);
      entry = own();
      return jsonBody(201, entry!);
    }
    if (options.path.endsWith('/waitlist') && options.method == 'DELETE') {
      onQueueChange?.call(options.method);
      entry = own();
      return jsonBody(204);
    }
    if (options.path.endsWith('/reservations/mine')) {
      return jsonBody(200, pageJson([]));
    }
    if (options.path == '/api/v1/listings/listing-1') {
      return jsonBody(200, listingJson(author: 'other', status: status()));
    }
    return jsonBody(200, pageJson([]));
  });
}

void main() {
  testWidgets('a busy card joins and leaves the queue, a free one reserves', (
    tester,
  ) async {
    english(tester);
    Map<String, Object?>? own;
    var status = 'busy';
    final server = listingServer(
      own: () => own,
      status: () => status,
      onQueueChange: (method) {
        own = method == 'POST' ? waitlistJson(position: 1) : null;
      },
    );
    final container = await openListing(tester, server);

    expect(find.text('Join queue'), findsOneWidget);
    expect(find.text('Reserve'), findsNothing);
    await tester.tap(find.text('Join queue'));
    await tester.pumpAndSettle();
    expect(
      server.sent.lastWhere((r) => r.method == 'POST').path,
      endsWith('/waitlist'),
    );
    expect(find.text('Your place in the queue: 1'), findsOneWidget);
    expect(find.text('Leave queue'), findsOneWidget);

    await tester.tap(find.text('Leave queue'));
    await tester.pumpAndSettle();
    expect(
      server.sent.lastWhere((r) => r.method == 'DELETE').path,
      endsWith('/waitlist'),
    );
    expect(find.text('Join queue'), findsOneWidget);

    // Once the place is free again, the card offers to reserve it instead.
    status = 'active';
    container.invalidate(listingProvider('listing-1'));
    await tester.pumpAndSettle();
    expect(find.text('Reserve'), findsOneWidget);
    expect(find.text('Join queue'), findsNothing);
  });

  testWidgets('the own place follows a refresh after somebody ahead leaves', (
    tester,
  ) async {
    english(tester);
    var position = 2;
    Map<String, Object?> own() => waitlistJson(position: position);
    final server = listingServer(own: own, status: () => 'busy');
    await openListing(tester, server);

    expect(find.text('Your place in the queue: 2'), findsOneWidget);
    position = 1;
    await tester.tap(find.byKey(const Key('waitlist-refresh-listing-1')));
    await tester.pumpAndSettle();
    expect(find.text('Your place in the queue: 1'), findsOneWidget);
    expect(find.text('Your place in the queue: 2'), findsNothing);
    expect(
      server.sent.where((r) => r.path.endsWith('/waitlist/me')).length,
      greaterThan(1),
    );
  });

  testWidgets('the own place is polled while the user waits', (tester) async {
    english(tester);
    var position = 2;
    Map<String, Object?> own() => waitlistJson(position: position);
    final server = listingServer(own: own, status: () => 'busy');
    await openListing(tester, server);

    expect(find.text('Your place in the queue: 2'), findsOneWidget);
    position = 1;
    await tester.pump(waitlistPollInterval + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Your place in the queue: 1'), findsOneWidget);
  });

  testWidgets(
    'the offer countdown follows the server expiry and hides confirm',
    (tester) async {
      english(tester);
      var now = DateTime.utc(2026, 11, 14, 12);
      final offer = WaitlistEntryOutput.fromJson(
        waitlistJson(
          status: 'offered',
          position: 1,
          expires: now.add(const Duration(seconds: 2)),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: delegates(),
            home: Scaffold(
              body: PlaceOfferCard(entry: offer, now: () => now),
            ),
          ),
        ),
      );

      expect(find.text('Offer expires in 00:02'), findsOneWidget);
      expect(find.byKey(const Key('offer-accept-listing-1')), findsOneWidget);
      expect(find.byKey(const Key('offer-decline-listing-1')), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Offer expires in 00:01'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('offer-expired-listing-1')), findsOneWidget);
      expect(find.byKey(const Key('offer-accept-listing-1')), findsNothing);
      expect(find.byKey(const Key('offer-decline-listing-1')), findsNothing);
      expect(find.byKey(const Key('offer-refresh-listing-1')), findsOneWidget);
    },
  );

  testWidgets('a place offer notification opens the offer card', (
    tester,
  ) async {
    english(tester);
    final server = FakeHttpAdapter(feed: pageJson([]))
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/waitlist/me')) {
          return jsonBody(
            200,
            waitlistJson(
              status: 'offered',
              position: 1,
              expires: clock.now().add(const Duration(hours: 1)),
            ),
          );
        }
        if (options.path.endsWith('/reservations/mine')) {
          return jsonBody(200, pageJson([]));
        }
        if (options.path == '/api/v1/listings/listing-1') {
          return jsonBody(200, listingJson(author: 'other'));
        }
        return jsonBody(200, pageJson([]));
      });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    unawaited(
      container
          .read(appRouterProvider)
          .push(
            notificationRoute('listing.offer', {'listing_id': 'listing-1'})!,
          ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Place offer'), findsOneWidget);
    expect(find.text('A desk'), findsOneWidget);
    expect(find.byKey(const Key('offer-countdown-listing-1')), findsOneWidget);
    expect(find.byKey(const Key('offer-accept-listing-1')), findsOneWidget);
    expect(find.byKey(const Key('offer-decline-listing-1')), findsOneWidget);
  });

  testWidgets('My shows place offers and queues with the own place', (
    tester,
  ) async {
    english(tester);
    final server = FakeHttpAdapter(feed: pageJson([]))
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/waitlist/mine')) {
          return jsonBody(
            200,
            pageJson([
              waitlistJson(
                id: 'entry-wait',
                listingId: 'listing-2',
                position: 2,
              ),
              waitlistJson(
                id: 'entry-offer',
                status: 'offered',
                position: 1,
                expires: clock.now().add(const Duration(hours: 1)),
              ),
            ]),
          );
        }
        if (options.path.endsWith('/reservations/mine')) {
          return jsonBody(200, pageJson([]));
        }
        if (options.path == '/api/v1/listings/mine') {
          return jsonBody(200, pageJson([]));
        }
        if (options.path == '/api/v1/listings/listing-1') {
          return jsonBody(200, {
            ...listingJson(author: 'other'),
            'title': 'Sofa',
          });
        }
        if (options.path == '/api/v1/listings/listing-2') {
          return jsonBody(200, {
            ...listingJson(author: 'other', status: 'busy'),
            'title': 'Lamp',
          });
        }
        return jsonBody(200, pageJson([]));
      });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    unawaited(container.read(appRouterProvider).push('/my-listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queues and offers'));
    await tester.pumpAndSettle();

    expect(find.text('Place offers'), findsOneWidget);
    expect(find.text('Sofa'), findsOneWidget);
    expect(find.byKey(const Key('offer-countdown-listing-1')), findsOneWidget);
    expect(find.text('Your queues'), findsOneWidget);
    expect(find.text('Lamp'), findsOneWidget);
    expect(find.text('Your place in the queue: 2'), findsOneWidget);
  });

  testWidgets('confirm and decline send the offer actions', (tester) async {
    english(tester);
    var accepted = false;
    var declined = false;
    final server = FakeHttpAdapter()
      ..route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path.endsWith('/offer/accept')) {
          accepted = true;
          return jsonBody(201, interactionJson());
        }
        if (options.path.endsWith('/offer/decline')) {
          declined = true;
          return jsonBody(200, waitlistJson(status: 'declined'));
        }
        return problemBody(404, 'not_found');
      });
    final offer = WaitlistEntryOutput.fromJson(
      waitlistJson(
        status: 'offered',
        position: 1,
        expires: clock.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: apiOverrides(adapter: server, secure: signedInStorage),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: delegates(),
          home: Scaffold(body: PlaceOfferCard(entry: offer)),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('offer-accept-listing-1')));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
    expect(
      find.text('Offer confirmed. The application is waiting for the author.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('offer-decline-listing-1')));
    await tester.pumpAndSettle();
    expect(declined, isTrue);
  });
}
