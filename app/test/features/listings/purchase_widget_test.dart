import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/router/app_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

const organizerId = '01890a5d-ac96-774b-bcce-b302099a8058';
const participantId = '01890a5d-ac96-774b-bcce-b302099a8060';

Map<String, Object?> account(String id, String name) => {
  ...userJson,
  ...filledProfileJson,
  'id': id,
  'first_name': name.split(' ').first,
  'last_name': name.split(' ').last,
};

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// Makes the whole card visible without scrolling inside a small surface.
void wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

String amountOf(String unitPrice, int units) {
  final cents = (double.parse(unitPrice) * 100).round() * units;
  return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

class _Share {
  _Share(this.id, this.units);

  final String id;
  int units;
  bool requested = false;
}

/// The purchase state that the UI mutates through real requests.
class FakePurchaseBackend {
  FakePurchaseBackend({
    this.unitPrice = '12.50',
    this.minUnits = 2,
    this.maxUnits = 10,
    this.stage = 'collecting',
    this.taken = 0,
    this.fixedUnits,
  });

  final String id = 'purchase-1';
  final String author = organizerId;
  String viewer = organizerId;
  String title = 'A bag of rice';
  String unitPrice;
  int minUnits;
  int maxUnits;
  String stage;
  int taken;
  int? fixedUnits;
  final shares = <String, _Share>{};
  late final DateTime deadline = DateTime.now().toUtc().add(
    const Duration(days: 3),
  );

  int get available => maxUnits - taken;

  Map<String, Object?> listing() => purchaseListingJson(
    id: id,
    author: author,
    title: title,
    stage: stage,
    unitPrice: unitPrice,
    minUnits: minUnits,
    maxUnits: maxUnits,
    takenUnits: taken,
    fixedUnits: fixedUnits,
    deadline: deadline.toIso8601String(),
  );

  Map<String, Object?> share(String participant) {
    final share = shares[participant]!;
    return purchaseShareJson(
      id: share.id,
      listingId: id,
      participantId: participant,
      participantName: participant == organizerId
          ? 'Ivan Ivanov'
          : 'Petr Petrov',
      units: share.units,
      unitPrice: unitPrice,
      stage: stage,
      leaveRequestedAt: share.requested ? '2026-11-15T12:00:00Z' : null,
    );
  }

  Map<String, Object?> composition() {
    final units = shares.values.fold(0, (sum, share) => sum + share.units);
    return {
      'listing_id': id,
      'stage': stage,
      'unit_price': unitPrice,
      'min_units': minUnits,
      'max_units': maxUnits,
      'taken_units': taken,
      'fixed_units': fixedUnits,
      'collection_deadline': deadline.toIso8601String(),
      'total_units': units,
      'total_amount': amountOf(unitPrice, units),
      'items': [for (final entry in shares.keys) share(entry)],
    };
  }

  ResponseBody reply(RequestOptions options) {
    final path = options.path;
    final method = options.method;
    final me = shares[viewer];
    if (path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (method == 'GET' && path == '/api/v1/listings/$id') {
      return jsonBody(200, listing());
    }
    if (method == 'GET' && path == '/api/v1/listings/$id/shares/me') {
      return me == null
          ? problemBody(404, 'not_found')
          : jsonBody(200, share(viewer));
    }
    if (method == 'GET' && path == '/api/v1/listings/$id/shares') {
      if (viewer != author) return problemBody(403, 'forbidden');
      return jsonBody(200, composition());
    }
    if (method == 'POST' && path == '/api/v1/listings/$id/shares') {
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      final units = body['units']! as int;
      if (units < 1 || units > available) {
        return problemBody(
          409,
          'listing_purchase_units_unavailable',
          extra: {'available': available},
        );
      }
      shares[viewer] = _Share('share-$viewer', units);
      taken += units;
      return jsonBody(201, share(viewer));
    }
    if (method == 'PATCH' && path == '/api/v1/listings/$id/shares/me') {
      final current = shares[viewer]!;
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      final units = body['units']! as int;
      final free = maxUnits - taken + current.units;
      if (units < 1 || units > free) {
        return problemBody(
          409,
          'listing_purchase_units_unavailable',
          extra: {'available': free},
        );
      }
      taken += units - current.units;
      current.units = units;
      return jsonBody(200, share(viewer));
    }
    if (method == 'DELETE' && path == '/api/v1/listings/$id/shares/me') {
      final share = shares.remove(viewer)!;
      taken -= share.units;
      return jsonBody(204);
    }
    if (method == 'POST' &&
        path == '/api/v1/listings/$id/shares/me/withdrawal') {
      shares[viewer]!.requested = true;
      return jsonBody(201, share(viewer));
    }
    if (method == 'DELETE' &&
        path == '/api/v1/listings/$id/shares/me/withdrawal') {
      shares[viewer]!.requested = false;
      return jsonBody(204);
    }
    if (method == 'POST' &&
        path.startsWith('/api/v1/listings/$id/shares/') &&
        path.endsWith('/withdrawal/decision')) {
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      final shareId = path.split('/')[6];
      final entry = shares.entries.firstWhere(
        (item) => item.value.id == shareId,
      );
      entry.value.requested = false;
      final response = share(entry.key);
      if (body['approve'] == true) {
        taken -= entry.value.units;
        shares.remove(entry.key);
      }
      return jsonBody(200, response);
    }
    if (method == 'POST' && path == '/api/v1/listings/purchases') {
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      title = body['title']! as String;
      unitPrice = body['price_per_unit']! as String;
      minUnits = body['min_units']! as int;
      maxUnits = body['max_units']! as int;
      return jsonBody(201, listing());
    }
    return jsonBody(200, pageJson([]));
  }
}

FakeHttpAdapter serverFor(FakePurchaseBackend backend, String viewer) {
  backend.viewer = viewer;
  return FakeHttpAdapter(
    me: account(viewer, viewer == organizerId ? 'Ivan Ivanov' : 'Petr Petrov'),
    feed: pageJson([backend.listing()]),
  )..route(backend.reply);
}

Future<ProviderContainer> open(
  WidgetTester tester,
  FakeHttpAdapter server,
  String path,
) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
  );
  unawaited(container.read(appRouterProvider).push(path));
  await tester.pumpAndSettle();
  return container;
}

/// Opens the purchase card and waits for the own share to load.
Future<ProviderContainer> openPurchase(
  WidgetTester tester,
  FakeHttpAdapter server,
) => open(tester, server, '/listings/purchase-1');

Future<void> fillCategory(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('purchase-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Items').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the form publishes price, volume bounds and deadline', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakePurchaseBackend();
    final server = serverFor(backend, organizerId);
    await open(tester, server, '/purchase/new');

    await fillCategory(tester);
    await tester.enterText(
      find.byKey(const Key('purchase-title')),
      'A bag of rice',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-description')),
      'Bulk order from the market',
    );
    await tester.enterText(find.byKey(const Key('purchase-price')), '12,50');
    await tester.enterText(find.byKey(const Key('purchase-min-units')), '2');
    await tester.enterText(find.byKey(const Key('purchase-max-units')), '10');
    await tester.ensureVisible(find.byKey(const Key('purchase-submit')));
    await tester.tap(find.byKey(const Key('purchase-submit')));
    await tester.pumpAndSettle();

    final post = server.sent.singleWhere(
      (request) =>
          request.method == 'POST' &&
          request.path == '/api/v1/listings/purchases',
    );
    expect(post.json['price_per_unit'], '12.50');
    expect(post.json['min_units'], 2);
    expect(post.json['max_units'], 10);
    expect(post.json['title'], 'A bag of rice');
    expect(post.json['description'], 'Bulk order from the market');
    final deadline = DateTime.parse(
      post.json['collection_deadline']! as String,
    );
    expect(deadline.isAfter(DateTime.now().toUtc()), isTrue);
  });

  testWidgets('a share cannot exceed the free volume', (tester) async {
    english(tester);
    wide(tester);
    final backend = FakePurchaseBackend(taken: 3);
    final server = serverFor(backend, participantId);
    await openPurchase(tester, server);

    expect(find.text('Collecting shares'), findsOneWidget);
    expect(find.text('Collected 3 of 10 units'), findsOneWidget);
    expect(find.text('Available: 7 units'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('purchase-share-units')), '8');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('purchase-share-join')));
    await tester.tap(find.byKey(const Key('purchase-share-join')));
    await tester.pumpAndSettle();

    expect(find.text('Only 7 units are available.'), findsOneWidget);
    expect(
      server.sent.where(
        (request) =>
            request.method == 'POST' && request.path.endsWith('/shares'),
      ),
      isEmpty,
    );
    expect(backend.shares, isEmpty);

    await tester.enterText(find.byKey(const Key('purchase-share-units')), '2');
    await tester.tap(find.byKey(const Key('purchase-share-join')));
    await tester.pumpAndSettle();

    expect(backend.shares[participantId]!.units, 2);
    expect(find.text('Share: 2 units'), findsOneWidget);
    expect(find.text('Amount: ₽25.00'), findsOneWidget);
    final post = server.sent.singleWhere(
      (request) => request.method == 'POST' && request.path.endsWith('/shares'),
    );
    expect(post.json['units'], 2);
  });

  testWidgets('a stale card explains the volume the server still has', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakePurchaseBackend(taken: 3);
    final server = serverFor(backend, participantId);
    await openPurchase(tester, server);

    expect(find.text('Available: 7 units'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('purchase-share-units')), '7');
    // The organiser lowered the maximum after the card was loaded.
    backend.maxUnits = 5;
    await tester.ensureVisible(find.byKey(const Key('purchase-share-join')));
    await tester.tap(find.byKey(const Key('purchase-share-join')));
    await tester.pumpAndSettle();

    expect(find.text('Only 2 units are available.'), findsOneWidget);
    expect(find.byKey(const Key('purchase-join')), findsOneWidget);
    expect(backend.shares, isEmpty);
  });

  testWidgets('changing and leaving a share updates the amount', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakePurchaseBackend(taken: 2)
      ..shares[participantId] = _Share('share-participant', 2);
    final server = serverFor(backend, participantId);
    await openPurchase(tester, server);

    expect(find.text('Collected 2 of 10 units'), findsOneWidget);
    expect(find.text('Amount: ₽25.00'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('purchase-share-units')), '4');
    await tester.pumpAndSettle();
    expect(find.text('New amount: ₽50.00'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('purchase-share-change')));
    await tester.tap(find.byKey(const Key('purchase-share-change')));
    await tester.pumpAndSettle();

    final patch = server.sent.singleWhere(
      (request) => request.method == 'PATCH',
    );
    expect(patch.json['units'], 4);
    expect(backend.shares[participantId]!.units, 4);
    expect(find.text('Share: 4 units'), findsOneWidget);
    expect(find.text('Amount: ₽50.00'), findsOneWidget);
    expect(find.text('New amount: ₽50.00'), findsOneWidget);
    expect(find.text('Collected 4 of 10 units'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('purchase-share-leave')));
    await tester.tap(find.byKey(const Key('purchase-share-leave')));
    await tester.pumpAndSettle();
    expect(backend.shares, isEmpty);
    expect(
      server.sent.where((request) => request.method == 'DELETE'),
      isNotEmpty,
    );
    expect(find.text('Amount: ₽25.00'), findsNothing);
  });

  testWidgets('a fixed purchase asks the organiser instead of leaving', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakePurchaseBackend(stage: 'fixed', taken: 3, fixedUnits: 3)
      ..shares[participantId] = _Share('share-participant', 3);
    final server = serverFor(backend, participantId);
    await openPurchase(tester, server);

    expect(find.text('Composition fixed'), findsOneWidget);
    expect(find.text('Fixed: 3 units'), findsOneWidget);
    expect(find.text('Amount: ₽37.50'), findsOneWidget);
    expect(find.byKey(const Key('purchase-share-leave')), findsNothing);
    expect(find.byKey(const Key('purchase-request-leave')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('purchase-request-leave')));
    await tester.tap(find.byKey(const Key('purchase-request-leave')));
    await tester.pumpAndSettle();

    expect(
      server.sent.singleWhere(
        (request) =>
            request.method == 'POST' &&
            request.path.endsWith('/shares/me/withdrawal'),
      ),
      isNotNull,
    );
    expect(
      find.byKey(const Key('purchase-leave-request-pending')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('purchase-request-leave')), findsNothing);

    await tester.tap(find.byKey(const Key('purchase-cancel-leave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-request-leave')), findsOneWidget);
  });

  testWidgets('the organiser sees amounts and decides a leave request', (
    tester,
  ) async {
    english(tester);
    wide(tester);
    final backend = FakePurchaseBackend(stage: 'fixed', taken: 3, fixedUnits: 3)
      ..shares[participantId] = _Share('share-participant', 3);
    backend.shares[participantId]!.requested = true;
    final server = serverFor(backend, organizerId);
    await openPurchase(tester, server);

    expect(find.byKey(const Key('purchase-composition')), findsOneWidget);
    expect(find.text('Petr Petrov'), findsOneWidget);
    expect(find.text('Asked to leave'), findsOneWidget);
    expect(find.text('Total: 3 units, ₽37.50'), findsOneWidget);
    expect(
      find.byKey(const Key('purchase-leave-approve-share-participant')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('purchase-leave-approve-share-participant')),
    );
    await tester.tap(
      find.byKey(const Key('purchase-leave-approve-share-participant')),
    );
    await tester.pumpAndSettle();

    final decision = server.sent.singleWhere(
      (request) => request.path.endsWith('/withdrawal/decision'),
    );
    expect(decision.json['approve'], isTrue);
    expect(backend.shares, isEmpty);
    expect(find.text('Nobody has taken a share yet.'), findsOneWidget);
    expect(find.text('Total: 0 units, ₽0.00'), findsOneWidget);
  });
}
