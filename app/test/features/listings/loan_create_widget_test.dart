import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/listings/application/loan_config.dart';
import 'package:campus/src/features/listings/domain/loan.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

final _maxThirty = LoanConfig(
  maxPeriodDays: 30,
  notReturnedAfter: const Duration(days: 3),
);

Map<String, Object?> loanListingJson({
  String id = 'listing-1',
  int? days = 5,
  String status = 'active',
  Map<String, Object?>? extra,
}) => {
  ...listingJson(id: id, status: status, kind: loanKind),
  'loan_days': ?days,
  ...?extra,
};

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// A server that publishes loans and appends them to the feed.
FakeHttpAdapter loanFormServer({
  ResponseBody Function(RequestOptions options)? onPublish,
}) {
  final adapter = FakeHttpAdapter(feed: pageJson([]));
  Map<String, Object?>? published;
  adapter.route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path.endsWith('/listings/loans') && options.method == 'POST') {
      if (onPublish != null) return onPublish(options);
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      final listing = loanListingJson(days: body['loan_days']! as int);
      published = listing;
      adapter.feed = pageJson([listing]);
      return jsonBody(201, listing);
    }
    if (options.path == '/api/v1/listings/listing-1') {
      return jsonBody(200, published ?? loanListingJson());
    }
    return jsonBody(200, pageJson([]));
  });
  return adapter;
}

Future<ProviderContainer> openLoanForm(
  WidgetTester tester,
  FakeHttpAdapter server, {
  List<Override> overrides = const [],
}) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: server,
    overrides: overrides,
  );
  unawaited(container.read(appRouterProvider).push('/loan/new'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> fillForm(WidgetTester tester, {String days = '5'}) async {
  await tester.tap(find.byKey(const Key('listing-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Items').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('listing-title')), 'A desk lamp');
  await tester.enterText(
    find.byKey(const Key('listing-description')),
    'Lend it for the weekend',
  );
  await tester.enterText(find.byKey(const Key('loan-days')), days);
}

void main() {
  testWidgets('the home button opens the loan form', (tester) async {
    english(tester);
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: loanFormServer(),
    );

    await tester.tap(find.byKey(const Key('feed-create-loan')));
    await tester.pumpAndSettle();

    expect(find.text('New loan listing'), findsOneWidget);
    expect(find.byKey(const Key('loan-days')), findsOneWidget);
    expect(find.text('From 1 to 90 days'), findsOneWidget);
  });

  testWidgets('the form publishes the loan period and the card shows it', (
    tester,
  ) async {
    english(tester);
    final server = loanFormServer();
    await openLoanForm(tester, server);
    await fillForm(tester);

    await tester.ensureVisible(find.text('Publish'));
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    final published = server.sent.singleWhere(
      (request) => request.path.endsWith('/listings/loans'),
    );
    expect(published.method, 'POST');
    expect(published.json['loan_days'], 5);
    expect(published.json['draft'], isFalse);
    expect(published.headers['Idempotency-Key'], isNotEmpty);

    // The feed card of the published loan shows the period.
    expect(find.textContaining('5 d'), findsOneWidget);

    await tester.tap(find.text('A desk'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loan-period')), findsOneWidget);
    expect(
      find.text('Return period: 5 days after the handover'),
      findsOneWidget,
    );
  });

  testWidgets('a period outside the configured range is refused locally', (
    tester,
  ) async {
    english(tester);
    final server = loanFormServer();
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      overrides: [loanConfigProvider.overrideWithValue(_maxThirty)],
    );

    for (final days in ['0', '31']) {
      unawaited(container.read(appRouterProvider).push('/loan/new'));
      await tester.pumpAndSettle();
      await fillForm(tester, days: days);
      await tester.ensureVisible(find.text('Publish'));
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      expect(
        find.text('The return period must be from 1 to 30 days'),
        findsOneWidget,
      );
      expect(
        server.sent.where(
          (request) => request.path.endsWith('/listings/loans'),
        ),
        isEmpty,
      );
      container.read(appRouterProvider).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a draft carries the period and no publish', (tester) async {
    english(tester);
    final server = loanFormServer();
    await openLoanForm(
      tester,
      server,
      overrides: [loanConfigProvider.overrideWithValue(_maxThirty)],
    );
    await fillForm(tester);

    await tester.dragUntilVisible(
      find.text('Save draft'),
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    final draft = server.sent.singleWhere(
      (request) => request.path.endsWith('/listings/loans'),
    );
    expect(draft.json['draft'], isTrue);
    expect(draft.json['loan_days'], 5);
    expect(draft.headers['Idempotency-Key'], isNotEmpty);
  });

  testWidgets('a lost response is retried under the same idempotency key', (
    tester,
  ) async {
    english(tester);
    var attempts = 0;
    final server = loanFormServer(
      onPublish: (options) {
        attempts++;
        if (attempts <= 4) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection reset by peer',
          );
        }
        final body =
            jsonDecode(options.data! as String) as Map<String, Object?>;
        return jsonBody(201, loanListingJson(days: body['loan_days']! as int));
      },
    );
    await openLoanForm(tester, server);
    await fillForm(tester);

    await tester.ensureVisible(find.text('Publish'));
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listing-error')), findsOneWidget);
    expect(
      find.text(
        "Can't reach the server. Check your internet connection and try again.",
      ),
      findsOneWidget,
    );
    expect(attempts, 4);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(attempts, 5);
    final keys = server.sent
        .where((request) => request.path.endsWith('/listings/loans'))
        .map((request) => request.headers['Idempotency-Key'])
        .toSet();
    expect(keys, hasLength(1));
    expect(keys.single, isNotEmpty);
  });
}
