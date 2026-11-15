import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/features/listings/application/loan_config.dart';
import 'package:campus/src/features/listings/domain/loan.dart';
import 'package:campus/src/features/listings/presentation/loan_widgets.dart';
import 'package:campus/src/features/profile/application/my_profile.dart';
import 'package:clock/clock.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:dio/dio.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

const _owner = '01890a5d-ac96-774b-bcce-b302099a8090';
const _borrower = '01890a5d-ac96-774b-bcce-b302099a8091';
const _listing = '01890a5d-ac96-774b-bcce-b302099a8092';
const _interaction = '01890a5d-ac96-774b-bcce-b302099a8093';

final _me = UserOutput.fromJson({...userJson, ...filledProfileJson});

final _config = LoanConfig(
  maxPeriodDays: 90,
  notReturnedAfter: const Duration(days: 3),
);

/// The signed-in user without a session or the network.
class _FakeProfile extends MyProfile {
  @override
  Future<UserOutput?> build() async => _me;
}

InteractionOutput interactionJson({
  InteractionStatus status = InteractionStatus.accepted,
  String? stage,
  DateTime? returnDueAt,
  bool overdue = false,
  bool owner = false,
  DateTime? completedAt,
}) => InteractionOutput.fromJson({
  'id': _interaction,
  'listing_id': _listing,
  'participant_name': 'Boris',
  'participant_id': owner ? _borrower : _me.id,
  'status': status.toJson(),
  'stage': stage,
  'response_due_at': null,
  'executor': false,
  'meeting': null,
  'return_due_at': ?returnDueAt?.toUtc().toIso8601String(),
  'overdue': overdue,
  'completed_at': ?completedAt?.toUtc().toIso8601String(),
});

/// A loan the author of the listing lent; the current user is the owner.
InteractionOutput ownerInteraction({
  InteractionStatus status = InteractionStatus.accepted,
  String? stage,
  DateTime? returnDueAt,
  bool overdue = false,
  DateTime? completedAt,
}) => interactionJson(
  status: status,
  stage: stage,
  returnDueAt: returnDueAt,
  overdue: overdue,
  owner: true,
  completedAt: completedAt,
);

Map<String, Object?> markJson({String reason = 'loan_not_returned'}) => {
  'id': '01890a5d-ac96-774b-bcce-b302099a8094',
  'kind': 'personal',
  'status': 'counted',
  'reporter_id': _owner,
  'subject_id': _borrower,
  'reason': reason,
  'created_at': '2027-01-20T12:00:00Z',
  'disputed_at': null,
  'removed_at': null,
};

Map<String, Object?> noShowJson({
  List<Map<String, Object?>> marks = const [],
  Map<String, Object?>? dispute,
  bool canMark = false,
}) => {
  'listing_id': _listing,
  'interaction_id': _interaction,
  'status': 'no_show',
  'basis': dispute != null
      ? 'mutual_dispute'
      : marks.isEmpty
      ? 'unmarked'
      : 'marked',
  'marks': marks,
  'dispute': dispute,
  'no_show_at': marks.isEmpty ? null : '2027-01-20T12:00:00Z',
  'mark_from': null,
  'auto_after': null,
  'can_mark': canMark,
  'server_time': '2027-01-21T12:00:00Z',
};

Map<String, Object?> disputeJson() => {
  'id': '01890a5d-ac96-774b-bcce-b302099a8095',
  'status': 'open',
  'opened_at': '2027-01-21T12:00:00Z',
  'resolved_at': null,
  'resolution': null,
};

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

/// A server that knows the no-show state of the loan and the mark request.
FakeHttpAdapter loanServer({
  Map<String, Object?> Function()? noShow,
  ResponseBody Function(RequestOptions options)? onNotReturned,
  ResponseBody Function(RequestOptions options)? onDispute,
}) => FakeHttpAdapter()
  ..route((options) {
    if (options.path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (options.path.endsWith('/not-returned')) {
      return (onNotReturned ?? (_) => jsonBody(200, noShow?.call()))(options);
    }
    if (options.path.endsWith('/no-show')) {
      if (options.method == 'POST') {
        return (onDispute ?? (_) => jsonBody(200, noShow?.call()))(options);
      }
      return jsonBody(200, noShow?.call() ?? noShowJson());
    }
    return jsonBody(200, <String, Object?>{});
  });

Future<ProviderContainer> pumpCard(
  WidgetTester tester,
  FakeHttpAdapter server,
  InteractionOutput item, {
  LoanConfig? config,
  String kind = 'loan',
}) async {
  final container = ProviderContainer(
    overrides: [
      ...apiOverrides(adapter: server),
      myProfileProvider.overrideWith(_FakeProfile.new),
      loanConfigProvider.overrideWithValue(config ?? _config),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: delegates(),
        home: Scaffold(
          body: LoanSummary(
            item: item,
            kind: kind,
            timezone: 'Europe/Moscow',
            city: 'Moscow',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('an accepted loan shows the owner how to hand it over', (
    tester,
  ) async {
    english(tester);
    await pumpCard(tester, loanServer(), ownerInteraction());

    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Handed over'), findsOneWidget);
    expect(find.text('Returned'), findsOneWidget);
    expect(find.byKey(const Key('loan-show-handover')), findsOneWidget);
    expect(find.byKey(const Key('loan-scan-handover')), findsNothing);
    expect(find.byKey(const Key('loan-show-return')), findsNothing);
    expect(find.byKey(const Key('loan-scan-return')), findsNothing);
    expect(find.byKey(const Key('loan-not-returned')), findsNothing);
  });

  testWidgets('the borrower scans the handover the owner shows', (
    tester,
  ) async {
    english(tester);
    await pumpCard(tester, loanServer(), interactionJson());

    expect(find.byKey(const Key('loan-scan-handover')), findsOneWidget);
    expect(find.byKey(const Key('loan-show-handover')), findsNothing);
    expect(find.byKey(const Key('loan-not-returned')), findsNothing);
  });

  testWidgets('a non-loan interaction has no loan card', (tester) async {
    english(tester);
    await pumpCard(tester, loanServer(), interactionJson(), kind: 'giveaway');

    expect(find.byKey(const Key('loan-$_interaction')), findsNothing);
  });

  testWidgets('an issued loan shows the deadline in the city zone', (
    tester,
  ) async {
    english(tester);
    final item = ownerInteraction(
      stage: loanIssuedStage,
      returnDueAt: DateTime.utc(2027, 1, 20, 12),
    );
    await pumpCard(tester, loanServer(), item);

    expect(
      find.byKey(const Key('loan-return-due-$_interaction')),
      findsOneWidget,
    );
    expect(find.textContaining('Return by'), findsOneWidget);
    expect(find.textContaining('Return by 1/20/2027, 15:00'), findsOneWidget);
    expect(find.byKey(const Key('loan-scan-return')), findsOneWidget);
    expect(find.byKey(const Key('loan-show-return')), findsNothing);
  });

  testWidgets('the borrower shows the return code the owner scans', (
    tester,
  ) async {
    english(tester);
    final item = interactionJson(
      stage: loanIssuedStage,
      returnDueAt: DateTime.utc(2027, 1, 20, 12),
    );
    await pumpCard(tester, loanServer(), item);

    expect(find.byKey(const Key('loan-show-return')), findsOneWidget);
    expect(find.byKey(const Key('loan-scan-return')), findsNothing);
    expect(find.byKey(const Key('loan-not-returned')), findsNothing);
  });

  testWidgets('the overdue flag is visible next to the deadline', (
    tester,
  ) async {
    english(tester);
    final item = ownerInteraction(
      stage: loanIssuedStage,
      returnDueAt: DateTime.utc(2027, 1, 20, 12),
      overdue: true,
    );
    await pumpCard(tester, loanServer(), item);

    expect(find.byKey(const Key('loan-overdue-$_interaction')), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('the not-returned button waits for the configured delay', (
    tester,
  ) async {
    english(tester);
    final due = DateTime.utc(2027, 1, 20, 12);
    final now = due.add(const Duration(days: 1));
    final item = ownerInteraction(stage: loanIssuedStage, returnDueAt: due);
    await withClock(Clock(() => now), () async {
      await pumpCard(tester, loanServer(), item);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('loan-not-returned')),
      );
      expect(button.onPressed, isNull);
      expect(find.byKey(const Key('loan-not-returned-until')), findsOneWidget);
      expect(find.textContaining('Available from'), findsOneWidget);
      expect(find.textContaining('1/23/2027'), findsOneWidget);
    });
  });

  testWidgets('the card enables the mark when the wait ends', (tester) async {
    english(tester);
    final due = DateTime.utc(2027, 1, 20, 12);
    var now = due;
    final item = ownerInteraction(stage: loanIssuedStage, returnDueAt: due);
    await withClock(Clock(() => now), () async {
      await pumpCard(tester, loanServer(), item);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('loan-not-returned')))
            .onPressed,
        isNull,
      );

      now = due.add(const Duration(days: 3));
      await tester.pump(const Duration(days: 3));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('loan-not-returned')))
            .onPressed,
        isNotNull,
      );
    });
  });

  testWidgets('the owner marks the item once the delay has passed', (
    tester,
  ) async {
    english(tester);
    final due = DateTime.utc(2027, 1, 20, 12);
    final now = due.add(const Duration(days: 3, hours: 1));
    final item = ownerInteraction(stage: loanIssuedStage, returnDueAt: due);
    final server = loanServer(noShow: () => noShowJson(marks: [markJson()]));
    await withClock(Clock(() => now), () async {
      await pumpCard(tester, server, item);

      await tester.tap(find.byKey(const Key('loan-not-returned')));
      await tester.pumpAndSettle();
      expect(find.text('Mark the item as not returned?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('loan-not-returned-confirm')));
      await tester.pumpAndSettle();

      final mark = server.sent.singleWhere(
        (request) => request.path.endsWith('/not-returned'),
      );
      expect(mark.method, 'POST');
      expect(mark.headers['Idempotency-Key'], isNotEmpty);
      expect(
        find.byKey(const Key('loan-not-returned-mark-$_interaction')),
        findsOneWidget,
      );
      expect(
        find.text(
          'The borrower did not return the item in time: a no-show was '
          'recorded.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The borrower may dispute the no-show within the dispute window.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('a lost mark response is retried under the same key', (
    tester,
  ) async {
    english(tester);
    final due = DateTime.utc(2027, 1, 20, 12);
    final now = due.add(const Duration(days: 3, hours: 1));
    final item = ownerInteraction(stage: loanIssuedStage, returnDueAt: due);
    var attempts = 0;
    final server = loanServer(
      noShow: () => noShowJson(marks: [markJson()]),
      onNotReturned: (options) {
        attempts++;
        if (attempts <= 4) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection reset by peer',
          );
        }
        return jsonBody(200, noShowJson(marks: [markJson()]));
      },
    );
    await withClock(Clock(() => now), () async {
      await pumpCard(tester, server, item);

      await tester.tap(find.byKey(const Key('loan-not-returned')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('loan-not-returned-confirm')));
      await tester.pumpAndSettle();
      expect(attempts, 4);
      expect(find.byKey(const Key('loan-error-$_interaction')), findsOneWidget);

      await tester.tap(find.byKey(const Key('loan-not-returned')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('loan-not-returned-confirm')));
      await tester.pumpAndSettle();

      expect(attempts, 5);
      expect(
        find.byKey(const Key('loan-not-returned-mark-$_interaction')),
        findsOneWidget,
      );
      final keys = server.sent
          .where((request) => request.path.endsWith('/not-returned'))
          .map((request) => request.headers['Idempotency-Key'])
          .toSet();
      expect(keys, hasLength(1));
      expect(keys.single, isNotEmpty);
    });
  });

  testWidgets('a refusal before the threshold keeps the server moment', (
    tester,
  ) async {
    english(tester);
    final due = DateTime.utc(2027, 1, 20, 12);
    final now = due.add(const Duration(days: 3, hours: 1));
    final item = ownerInteraction(stage: loanIssuedStage, returnDueAt: due);
    final server = loanServer(
      onNotReturned: (_) => problemBody(
        409,
        'loan_not_returned_too_early',
        extra: {'available_at': '2027-01-24T12:00:00Z'},
      ),
    );
    await withClock(Clock(() => now), () async {
      await pumpCard(tester, server, item);

      await tester.tap(find.byKey(const Key('loan-not-returned')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('loan-not-returned-confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Available from'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('loan-not-returned')),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('1/24/2027'), findsWidgets);
    });
  });

  testWidgets('a returned loan shows the return time and no actions', (
    tester,
  ) async {
    english(tester);
    final at = DateTime.utc(2027, 1, 25, 9);
    final item = interactionJson(
      status: InteractionStatus.completed,
      stage: loanIssuedStage,
      returnDueAt: DateTime.utc(2027, 1, 20, 12),
      completedAt: at,
    );
    await pumpCard(tester, loanServer(), item);

    expect(
      find.byKey(const Key('loan-returned-$_interaction')),
      findsOneWidget,
    );
    expect(find.textContaining('Returned'), findsWidgets);
    expect(find.textContaining('12:00'), findsOneWidget);
    expect(find.byKey(const Key('loan-not-returned')), findsNothing);
    expect(find.byKey(const Key('loan-show-return')), findsNothing);
    expect(find.byKey(const Key('loan-scan-return')), findsNothing);
  });

  testWidgets('the borrower sees the mark and the open dispute', (
    tester,
  ) async {
    english(tester);
    final item = interactionJson(
      status: InteractionStatus.noShow,
      stage: loanIssuedStage,
    );
    final server = loanServer(
      noShow: () => noShowJson(marks: [markJson()], dispute: disputeJson()),
    );
    await pumpCard(tester, server, item);

    expect(
      find.text('The owner marked the item as not returned.'),
      findsOneWidget,
    );
    expect(
      find.text('The no-show is disputed; a moderator will decide.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('loan-dispute')), findsNothing);
    expect(find.byKey(const Key('loan-not-returned')), findsNothing);
  });

  testWidgets('the borrower answers the mark when the server allows it', (
    tester,
  ) async {
    english(tester);
    final item = interactionJson(
      status: InteractionStatus.noShow,
      stage: loanIssuedStage,
    );
    var disputeOpen = false;
    final server = loanServer(
      noShow: () => noShowJson(
        marks: [markJson()],
        dispute: disputeOpen ? disputeJson() : null,
        canMark: !disputeOpen,
      ),
      onDispute: (_) {
        disputeOpen = true;
        return jsonBody(
          200,
          noShowJson(marks: [markJson()], dispute: disputeJson()),
        );
      },
    );
    await pumpCard(tester, server, item);

    expect(find.byKey(const Key('loan-dispute')), findsOneWidget);
    await tester.tap(find.byKey(const Key('loan-dispute')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('loan-dispute-send')));
    await tester.pumpAndSettle();
    expect(find.text('Describe the reason'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('loan-dispute-reason')),
      'Returned it late',
    );
    await tester.tap(find.byKey(const Key('loan-dispute-send')));
    await tester.pumpAndSettle();

    final answer = server.sent.singleWhere(
      (request) =>
          request.path.endsWith('/no-show') && request.method == 'POST',
    );
    expect(answer.json['reason'], 'Returned it late');
    expect(answer.headers['Idempotency-Key'], isNotEmpty);
    expect(
      find.text('The no-show is disputed; a moderator will decide.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('loan-dispute')), findsNothing);
  });

  testWidgets('returning to the app rereads the mark and the dispute', (
    tester,
  ) async {
    english(tester);
    final item = interactionJson(
      status: InteractionStatus.noShow,
      stage: loanIssuedStage,
    );
    var state = noShowJson(marks: [markJson()]);
    final server = loanServer(noShow: () => state);
    await pumpCard(tester, server, item);

    expect(
      find.text('The owner marked the item as not returned.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('loan-dispute-open')), findsNothing);

    // The borrower disputes on another device while this card is open.
    state = noShowJson(marks: [markJson()], dispute: disputeJson());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-dispute-open')), findsOneWidget);
    expect(
      find.text('The no-show is disputed; a moderator will decide.'),
      findsOneWidget,
    );
  });

  testWidgets('an unknown no-show is not treated as the loan mark', (
    tester,
  ) async {
    english(tester);
    final item = interactionJson(
      status: InteractionStatus.noShow,
      stage: loanIssuedStage,
    );
    final server = loanServer(
      noShow: () => noShowJson(marks: [markJson(reason: 'meeting_missed')]),
    );
    await pumpCard(tester, server, item);

    expect(
      find.byKey(const Key('loan-not-returned-mark-$_interaction')),
      findsNothing,
    );
  });
}
