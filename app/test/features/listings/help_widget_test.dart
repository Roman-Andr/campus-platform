import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/core/time/city_time.dart';
import 'package:campus/src/core/widgets/city_date_time_picker.dart';
import 'package:campus/src/features/listings/application/help_config.dart';
import 'package:campus/src/features/listings/application/listings.dart';
import 'package:campus/src/features/listings/presentation/help_screen.dart';
import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';
import 'help_fixtures.dart';

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// A tall screen: the request, its applications and the form all fit.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String transitionedId(RequestOptions options) {
  final parts = options.path.split('/');
  return parts[parts.indexOf('interactions') + 1];
}

String requestStatus(RequestOptions options) =>
    (jsonDecode(options.data! as String) as Map<String, Object?>)['status']!
        as String;

FakeHttpAdapter helpServer({
  Map<String, Object?>? listing,
  List<Map<String, Object?>> incoming = const [],
  List<Map<String, Object?>> participations = const [],
  ResponseBody Function(RequestOptions options)? onPublish,
  ResponseBody Function(RequestOptions options)? onRespond,
}) {
  final item = listing ?? helpListingJson(author: 'other');
  return FakeHttpAdapter(
    feed: pageJson([item]),
    categories: helpCategoriesJson,
    photos: const {'items': []},
  )..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.method == 'GET' &&
        options.path == '/api/v1/listings/reservations/mine') {
      return jsonBody(200, pageJson(participations));
    }
    if (options.method == 'GET' && options.path.endsWith('/interactions')) {
      return jsonBody(200, pageJson(incoming));
    }
    if (options.method == 'POST' && options.path.endsWith('/responses')) {
      return (onRespond ?? (_) => jsonBody(201, helpInteractionJson()))(
        options,
      );
    }
    if (options.method == 'POST' &&
        options.path == '/api/v1/listings/help-requests') {
      return (onPublish ??
          (_) => jsonBody(201, helpListingJson(author: 'author')))(options);
    }
    if (options.method == 'POST' && options.path.endsWith('/transition')) {
      final id = transitionedId(options);
      final status = requestStatus(options);
      final application = incoming.firstWhere(
        (item) => item['id'] == id,
        orElse: () => helpInteractionJson(id: id),
      );
      application['status'] = status;
      application['executor'] = status == 'accepted';
      if (status == 'accepted') {
        item['status'] = 'busy';
      }
      if (status == 'cancelled') {
        item['status'] = 'active';
        application['executor'] = false;
      }
      return jsonBody(200, application);
    }
    return jsonBody(200, item);
  });
}

void main() {
  testWidgets('a help request is published with a default deadline', (
    tester,
  ) async {
    english(tester);
    tallScreen(tester);
    final server = helpServer();
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      overrides: [
        helpConfigProvider.overrideWithValue(
          const HelpConfig(listingLifetimeDays: 10),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('feed-create-help')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateHelpScreen), findsOneWidget);

    final today = tz.TZDateTime.from(
      clock.now(),
      cityLocation('Europe/Moscow'),
    );
    final firstDate = DateTime(today.year, today.month, today.day);
    final picker = tester.widget<CityDateTimePicker>(
      find.byKey(const Key('help-deadline')),
    );
    expect(picker.firstDate, firstDate);
    expect(picker.lastDate, firstDate.add(const Duration(days: 10)));
    expect(picker.value.isAfter(clock.now()), isTrue);

    await tester.tap(find.byKey(const Key('help-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Items').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('help-title')),
      'Help to move a couch',
    );
    await tester.enterText(
      find.byKey(const Key('help-description')),
      'Two floors, no elevator.',
    );
    await tapVisible(tester, find.byKey(const Key('help-publish')));

    final sent = server.sent.singleWhere(
      (request) => request.path == '/api/v1/listings/help-requests',
    );
    expect(sent.json['title'], 'Help to move a couch');
    expect(sent.json['description'], 'Two floors, no elevator.');
    expect(sent.json['category_id'], 'category-items');
    expect(sent.json['visibility'], 'city');
    expect(sent.json['audience'], 'students');
    expect(
      DateTime.parse(sent.json['actual_until']! as String).isAfter(clock.now()),
      isTrue,
    );
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
    expect(find.byType(CreateHelpScreen), findsNothing);
    expect(find.text('The help request has been published.'), findsOneWidget);
  });

  testWidgets('the author selects an executor and keeps the reserve', (
    tester,
  ) async {
    english(tester);
    tallScreen(tester);
    final applications = [
      helpInteractionJson(participant: 'first', participantName: 'Dana'),
      helpInteractionJson(
        id: 'request-2',
        participant: 'second',
        participantName: 'Egor',
      ),
    ];
    final listing = helpListingJson();
    final server = helpServer(listing: listing, incoming: applications);
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    await tester.tap(find.text('Help to move a couch'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-select-request-1')), findsOneWidget);
    expect(find.byKey(const Key('help-select-request-2')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('help-select-request-1')));
    expect(
      server.sent
          .singleWhere(
            (request) => request.path.endsWith('/request-1/transition'),
          )
          .json['status'],
      'accepted',
    );
    expect(find.byKey(const Key('help-executor-request-1')), findsOneWidget);
    expect(find.byKey(const Key('help-reserve-request-2')), findsOneWidget);
    expect(find.text('The executor has been selected.'), findsOneWidget);
    expect(find.byKey(const Key('help-select-request-2')), findsNothing);

    // The executor refuses: the server releases the request to the reserve.
    applications[0]['status'] = 'cancelled';
    applications[0]['executor'] = false;
    listing['status'] = 'active';
    container
      ..invalidate(listingProvider('listing-1'))
      ..invalidate(incomingProvider('listing-1', null));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-select-request-2')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('help-select-request-2')));
    expect(
      server.sent
          .singleWhere(
            (request) => request.path.endsWith('/request-2/transition'),
          )
          .json['status'],
      'accepted',
    );
    expect(find.byKey(const Key('help-executor-request-2')), findsOneWidget);
  });

  testWidgets('a respondent applies and sees the reserve notice', (
    tester,
  ) async {
    english(tester);
    tallScreen(tester);
    final listing = helpListingJson(author: 'other');
    final participations = <Map<String, Object?>>[];
    final server = helpServer(
      listing: listing,
      participations: participations,
      onRespond: (_) {
        final application = helpInteractionJson();
        participations
          ..clear()
          ..add(helpParticipationJson());
        return jsonBody(201, application);
      },
    );
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    await tester.tap(find.text('Help to move a couch'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-respond')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('help-respond')));
    expect(
      server.sent.where((request) => request.path.endsWith('/responses')),
      isNotEmpty,
    );
    expect(find.text('Response sent.'), findsOneWidget);
    expect(
      find.text('Your response is waiting for the author.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('help-respond')), findsNothing);

    // Another respondent becomes the executor; this one stays in reserve.
    listing['status'] = 'busy';
    participations
      ..clear()
      ..add(helpParticipationJson(listingStatus: 'busy'));
    container
      ..invalidate(listingProvider('listing-1'))
      ..invalidate(listingParticipationProvider('listing-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-reserve-request-1')), findsOneWidget);
    expect(
      find.text('An executor is already selected; you remain in the reserve.'),
      findsOneWidget,
    );

    // The same notice is visible in "My participation".
    unawaited(container.read(appRouterProvider).push('/my-listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My participation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-reserve-request-1')), findsOneWidget);
  });
}
