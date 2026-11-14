import 'dart:async';
import 'dart:typed_data';

import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_ru.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/listings/presentation/interaction_timeline_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

const _citiesJson = {
  'items': [
    {
      'id': 'city-moscow',
      'code': 'moscow',
      'name': 'Moscow',
      'timezone': 'Europe/Moscow',
    },
  ],
  'next_page': null,
};

Map<String, Object?> eventJson(
  String id, {
  String? actor,
  String action = 'transition',
  String? previous = 'pending',
  String status = 'accepted',
  String createdAt = '2026-11-14T09:00:00Z',
  String? reason,
  bool viaAssistant = false,
  bool offlineQr = false,
}) => {
  'id': id,
  'interaction_id': 'request-1',
  'actor_id': actor,
  'action': action,
  'previous_status': previous,
  'status': status,
  'version': 1,
  'created_at': createdAt,
  'reason': reason,
  'stage': null,
  'via_assistant': viaAssistant,
  'offline_qr': offlineQr,
};

Map<String, Object?> interactionJson({
  String participant = 'other',
  String status = 'pending',
}) => {
  'id': 'request-1',
  'listing_id': 'listing-1',
  'participant_id': participant,
  'participant_name': 'Boris',
  'stage': null,
  'response_due_at': null,
  'status': status,
};

const _timelinePath = '/listings/listing-1/interactions/request-1';

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// Routes common reads; [events] answers the history requests.
FakeHttpAdapter server(
  ResponseBody Function(RequestOptions r) events, {
  Map<String, Object?>? listing,
  ResponseBody? Function(RequestOptions r)? other,
}) => FakeHttpAdapter()
  ..route((r) {
    if (r.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (r.path.endsWith('/cities')) return jsonBody(200, _citiesJson);
    if (r.path.endsWith('/events')) return events(r);
    final reply = other?.call(r);
    if (reply != null) return reply;
    return jsonBody(200, listing ?? listingJson(author: 'other'));
  });

Future<FakeHttpAdapter> openTimeline(
  WidgetTester tester,
  FakeHttpAdapter adapter,
) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: adapter,
  );
  unawaited(container.read(appRouterProvider).push(_timelinePath));
  await tester.pumpAndSettle();
  return adapter;
}

/// Holds history requests until [release] completes.
class _HeldEvents extends FakeHttpAdapter {
  final release = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/events')) await release.future;
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  test('timeline texts and reasons are localized in RU and EN', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();
    expect(en.timelineTitle, 'Interaction history');
    expect(ru.timelineTitle, 'История взаимодействия');
    expect(timelineReason(en, 'listing_hidden'), en.timelineReasonHidden);
    expect(timelineReason(ru, 'listing_hidden'), ru.timelineReasonHidden);
    expect(timelineReason(ru, 'author_timeout'), ru.reservationRejectedTimeout);
    expect(timelineReason(en, null), isNull);
    expect(timelineReason(en, ''), isNull);
    expect(timelineReason(en, 'Changed my mind'), 'Changed my mind');
  });

  testWidgets('participant sees ordered events with authors and marks', (
    tester,
  ) async {
    english(tester);
    final cursors = <Object?>[];
    await openTimeline(
      tester,
      server((r) {
        final cursor = r.queryParameters['cursor'];
        cursors.add(cursor);
        return jsonBody(
          200,
          cursor == null
              ? pageJson([
                  eventJson(
                    'e1',
                    actor: userJson['id']! as String,
                    action: 'requested',
                    previous: null,
                    status: 'pending',
                  ),
                  eventJson(
                    'e2',
                    actor: 'other',
                    createdAt: '2026-11-14T10:00:00Z',
                    viaAssistant: true,
                  ),
                ], next: 'next')
              // The page boundary moved: e2 comes again and must not repeat.
              : pageJson([
                  eventJson(
                    'e2',
                    actor: 'other',
                    createdAt: '2026-11-14T10:00:00Z',
                    viaAssistant: true,
                  ),
                  eventJson(
                    'e3',
                    action: 'auto_rejected',
                    previous: 'accepted',
                    status: 'rejected',
                    createdAt: '2026-11-14T11:00:00Z',
                    reason: 'listing_expired',
                    offlineQr: true,
                  ),
                ]),
        );
      }),
    );
    expect(find.text('Interaction history'), findsOneWidget);
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.textContaining('You · '), findsOneWidget);
    expect(find.textContaining('Ivan Ivanov · '), findsOneWidget);
    // 09:00 UTC is 12:00 in Moscow.
    expect(find.textContaining('12:00'), findsOneWidget);
    expect(find.text('Pending → Accepted'), findsOneWidget);
    expect(find.byKey(const Key('timeline-assistant-e2')), findsOneWidget);
    expect(find.byKey(const Key('timeline-assistant-e1')), findsNothing);
    expect(find.byKey(const Key('timeline-qr-e2')), findsNothing);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(cursors, [null, 'next']);
    expect(find.text('Status changed'), findsOneWidget);
    expect(find.text('Request rejected automatically'), findsOneWidget);
    expect(find.textContaining('System · '), findsOneWidget);
    expect(find.byIcon(Icons.settings_suggest_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNWidgets(2));
    expect(find.textContaining('Reason: '), findsOneWidget);
    expect(find.byKey(const Key('timeline-qr-e3')), findsOneWidget);
    expect(find.byKey(const Key('timeline-assistant-e3')), findsNothing);
    expect(find.text('Load more'), findsNothing);
    final order = tester
        .widgetList<TimelineEventTile>(find.byType(TimelineEventTile))
        .map((tile) => tile.event.id);
    expect(order, ['e1', 'e2', 'e3']);
  });

  testWidgets('empty history says so', (tester) async {
    english(tester);
    await openTimeline(tester, server((_) => jsonBody(200, pageJson([]))));
    expect(find.text('No events yet'), findsOneWidget);
  });

  testWidgets('loading shows a progress indicator', (tester) async {
    english(tester);
    final adapter = _HeldEvents()
      ..route((r) {
        if (r.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (r.path.endsWith('/cities')) return jsonBody(200, _citiesJson);
        if (r.path.endsWith('/events')) return jsonBody(200, pageJson([]));
        return jsonBody(200, listingJson(author: 'other'));
      });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: adapter,
    );
    unawaited(container.read(appRouterProvider).push(_timelinePath));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.descendant(
        of: find.byType(InteractionTimelineScreen),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    adapter.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('No events yet'), findsOneWidget);
  });

  testWidgets('a foreign interaction is refused by a direct link', (
    tester,
  ) async {
    english(tester);
    await openTimeline(tester, server((_) => problemBody(403, 'forbidden')));
    expect(
      find.text(
        'Only the listing author and the participant can see this history.',
      ),
      findsOneWidget,
    );
    expect(find.byType(TimelineEventTile), findsNothing);
  });

  testWidgets('failure and lost network recover with retry', (tester) async {
    english(tester);
    var mode = 'server';
    await openTimeline(
      tester,
      server((r) {
        if (mode == 'server') return problemBody(503, 'internal_error');
        if (mode == 'network') {
          throw DioException.connectionError(
            requestOptions: r,
            reason: 'Connection reset by peer',
          );
        }
        return jsonBody(200, pageJson([eventJson('e1', actor: 'other')]));
      }),
    );
    expect(
      find.text('Something went wrong on the server. Please try again later.'),
      findsOneWidget,
    );
    mode = 'network';
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timeline-error')), findsOneWidget);
    expect(find.byType(TimelineEventTile), findsNothing);
    mode = 'ok';
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timeline-error')), findsNothing);
    expect(find.byType(TimelineEventTile), findsOneWidget);
  });

  testWidgets('history opened again after an action shows the new event', (
    tester,
  ) async {
    english(tester);
    var status = 'pending';
    final adapter = server(
      (_) => jsonBody(
        200,
        pageJson([
          eventJson(
            'e1',
            actor: 'other',
            action: 'requested',
            previous: null,
            status: 'pending',
          ),
          if (status == 'accepted')
            eventJson('e2', actor: userJson['id']! as String),
        ]),
      ),
      listing: listingJson(),
      other: (r) {
        if (r.path.endsWith('/transition')) {
          status = 'accepted';
          return jsonBody(200, interactionJson(status: status));
        }
        if (r.path.endsWith('/interactions')) {
          return jsonBody(200, pageJson([interactionJson(status: status)]));
        }
        return null;
      },
    );
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: adapter,
    );
    unawaited(container.read(appRouterProvider).push('/listings/listing-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-open-request-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Boris · '), findsOneWidget);
    expect(find.byType(TimelineEventTile), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-open-request-1')));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineEventTile), findsNWidgets(2));
    expect(find.textContaining('You · '), findsOneWidget);
    expect(find.text('Pending → Accepted'), findsOneWidget);
  });
}
