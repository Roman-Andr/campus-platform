import 'dart:async';

import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/qr/application/qr_providers.dart';
import 'package:campus/src/features/qr/domain/qr_availability.dart';
import 'package:campus/src/features/qr/presentation/meeting_qr_code.dart';
import 'package:campus/src/features/qr/presentation/qr_camera.dart';
import 'package:campus/src/features/qr/presentation/qr_presenter_screen.dart';
import 'package:campus/src/features/qr/presentation/qr_scanner_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import '../listings/fixtures.dart';
import 'fixtures.dart';

void english(WidgetTester tester) {
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// A camera that reports [code] when its button is pressed.
QrCameraBuilder fakeCamera(String Function() code) =>
    (context, onDetect) => Center(
      child: TextButton(
        key: const Key('fake-scan'),
        onPressed: () => onDetect(code()),
        child: const Text('scan'),
      ),
    );

Map<String, Object?> loanListingJson({String? author}) => {
  ...listingJson(id: qrListingId, author: author, kind: 'loan'),
  'loan_days': 5,
};

Map<String, Object?> loanScanJson({
  required bool handover,
  DateTime? returnDueAt,
  DateTime? completedAt,
  String presenterId = qrOtherId,
}) {
  final at = completedAt ?? DateTime.utc(2027, 1, 15, 12, 0, 30);
  return {
    'listing_id': qrListingId,
    'interaction_id': qrInteractionId,
    'presenter_id': presenterId,
    'scanner_id': userJson['id'],
    'status': handover ? 'accepted' : 'completed',
    'completed': !handover,
    'completed_at': handover ? null : at.toIso8601String(),
    'completion_method': handover ? null : 'qr',
    'rating_weight': handover ? null : 1,
    'stage': handover ? 'issued' : null,
    'return_due_at': returnDueAt?.toIso8601String(),
    'nonce': qrNonce,
    'issued_at': at.subtract(const Duration(seconds: 1)).toIso8601String(),
    'received_at': at.toIso8601String(),
    'server_time': at.toIso8601String(),
  };
}

/// A server of a loan interaction with the two QR actions of the steps.
FakeHttpAdapter loanQrServer({
  required DateTime Function() serverNow,
  required Map<String, Object?> Function() participation,
  Map<String, Object?> Function()? listing,
  ResponseBody Function(RequestOptions options)? onScan,
}) {
  final adapter = FakeHttpAdapter(feed: pageJson([]));
  adapter.route((options) {
    final path = options.path;
    if (path.endsWith('/token/refresh')) return jsonBody(200, tokensJson(1));
    if (path.endsWith('/reservations/mine')) {
      return jsonBody(200, pageJson([participation()]));
    }
    if (path.endsWith('/university/cities')) return jsonBody(200, qrCitiesJson);
    if (path == '/api/v1/listings/$qrListingId') {
      return jsonBody(200, (listing ?? loanListingJson)());
    }
    if (path == '/api/v1/time') {
      return jsonBody(200, qrServerTimeJson(now: serverNow()));
    }
    if (path == '/api/v1/me/device-key' && options.method == 'PUT') {
      return jsonBody(200, qrDeviceKeyJson(publicKey: 'registered-key'));
    }
    if (options.method == 'POST' &&
        (path.endsWith('/qr/handover') || path.endsWith('/qr/return'))) {
      return (onScan ??
          (_) => jsonBody(
            200,
            loanScanJson(handover: path.endsWith('/qr/handover')),
          ))(options);
    }
    if (options.method == 'POST' && path.endsWith('/qr')) {
      return problemBody(409, 'qr_loan_action_required');
    }
    return jsonBody(200, pageJson([]));
  });
  return adapter;
}

Future<ProviderContainer> openLoanQr(
  WidgetTester tester,
  FakeHttpAdapter adapter,
  String path, {
  String Function()? cameraCode,
}) async {
  final container = await tester.pumpCampusApp(
    InMemorySettingsRepository(),
    adapter: adapter,
    overrides: [
      deviceKeyStoreProvider.overrideWithValue(InMemoryDeviceKeyStore()),
      if (cameraCode != null)
        qrCameraBuilderProvider.overrideWithValue(fakeCamera(cameraCode)),
    ],
  );
  unawaited(container.read(appRouterProvider).push(path));
  await tester.pumpAndSettle();
  return container;
}

MeetingQrCode shownCode(WidgetTester tester) =>
    tester.widget<MeetingQrCode>(find.byKey(const Key('qr-presenter-code')));

void main() {
  group('presenter', () {
    testWidgets('the owner shows the handover code', (tester) async {
      english(tester);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(kind: 'loan'),
        listing: () => loanListingJson(author: userJson['id']! as String),
      );
      await openLoanQr(
        tester,
        server,
        qrShowPath(qrListingId, qrInteractionId, action: QrAction.loanHandover),
      );

      expect(find.text('Handover QR code'), findsOneWidget);
      expect(
        find.text(
          'Show this code to the borrower: they confirm receiving the item.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qr-presenter-code')), findsOneWidget);
      expect(
        shownCode(tester).document.decodedPayload!.presenterId,
        userJson['id'],
      );
    });

    testWidgets('the borrower shows the return code after the handover', (
      tester,
    ) async {
      english(tester);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          kind: 'loan',
          stage: 'issued',
          participantId: userJson['id']! as String,
        ),
        listing: () => loanListingJson(author: qrOtherId),
      );
      await openLoanQr(
        tester,
        server,
        qrShowPath(qrListingId, qrInteractionId, action: QrAction.loanReturn),
      );

      expect(find.text('Return QR code'), findsOneWidget);
      expect(
        find.text('Show this code to the owner: they confirm the return.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qr-presenter-code')), findsOneWidget);
    });

    testWidgets('the return code is not offered before the handover', (
      tester,
    ) async {
      english(tester);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          kind: 'loan',
          participantId: userJson['id']! as String,
        ),
        listing: () => loanListingJson(author: qrOtherId),
      );
      await openLoanQr(
        tester,
        server,
        qrShowPath(qrListingId, qrInteractionId, action: QrAction.loanReturn),
      );

      expect(
        find.text('The return is possible only after the handover.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qr-presenter-code')), findsNothing);
    });

    testWidgets('the plain completion is not offered for a loan', (
      tester,
    ) async {
      english(tester);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(kind: 'loan'),
        listing: () => loanListingJson(author: userJson['id']! as String),
      );
      await openLoanQr(
        tester,
        server,
        qrShowPath(qrListingId, qrInteractionId),
      );

      expect(find.byKey(const Key('qr-presenter-code')), findsNothing);
      expect(
        find.text('This interaction cannot be completed with a QR code.'),
        findsOneWidget,
      );
    });
  });

  group('scanner', () {
    testWidgets('the borrower confirms the handover with the owner code', (
      tester,
    ) async {
      english(tester);
      final document = await qrSignedDocument();
      final due = DateTime.utc(2027, 1, 20, 12);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          kind: 'loan',
          participantId: userJson['id']! as String,
        ),
        listing: () => loanListingJson(author: qrOtherId),
        onScan: (options) =>
            jsonBody(200, loanScanJson(handover: true, returnDueAt: due)),
      );
      await openLoanQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId, action: QrAction.loanHandover),
        cameraCode: document.encode,
      );

      expect(find.text('Scan the handover'), findsOneWidget);
      expect(
        find.text('Point the camera at the code the owner shows.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('fake-scan')));
      await tester.pumpAndSettle();

      expect(find.text('The handover is confirmed.'), findsOneWidget);
      expect(find.textContaining('Return by'), findsOneWidget);
      expect(find.textContaining('15:00'), findsWidgets);
      final scan = server.sent.singleWhere(
        (request) => request.path.endsWith('/qr/handover'),
      );
      expect(scan.headers['Idempotency-Key'], isNotEmpty);
    });

    testWidgets('a return before the handover is never scanned', (
      tester,
    ) async {
      english(tester);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          kind: 'loan',
          participantId: userJson['id']! as String,
        ),
        listing: () => loanListingJson(author: qrOtherId),
      );
      await openLoanQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId, action: QrAction.loanReturn),
      );

      expect(
        find.text('The return is possible only after the handover.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qr-scanner-camera')), findsNothing);
      expect(
        server.sent.where((request) => request.path.contains('/qr')),
        isEmpty,
      );
    });

    testWidgets('the owner confirms the return with the borrower code', (
      tester,
    ) async {
      english(tester);
      final document = await qrSignedDocument();
      final completedAt = DateTime.utc(2027, 1, 25, 12);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 25, 12),
        participation: () => qrParticipationJson(kind: 'loan', stage: 'issued'),
        listing: () => loanListingJson(author: userJson['id']! as String),
        onScan: (options) => jsonBody(
          200,
          loanScanJson(handover: false, completedAt: completedAt),
        ),
      );
      await openLoanQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId, action: QrAction.loanReturn),
        cameraCode: document.encode,
      );

      expect(find.text('Scan the return'), findsOneWidget);
      await tester.tap(find.byKey(const Key('fake-scan')));
      await tester.pumpAndSettle();

      expect(
        find.text('The return is confirmed; the loan is complete.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qr-scanner-success')), findsOneWidget);
      expect(
        server.sent.where((request) => request.path.endsWith('/qr')),
        isEmpty,
      );
    });

    testWidgets('a scanned loan that is already returned says so', (
      tester,
    ) async {
      english(tester);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 25, 12),
        participation: () => qrParticipationJson(
          kind: 'loan',
          stage: 'issued',
          status: 'completed',
          completionMethod: 'qr',
          completedAt: DateTime.utc(2027, 1, 25, 12),
        ),
        listing: () => loanListingJson(author: userJson['id']! as String),
      );
      await openLoanQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId, action: QrAction.loanReturn),
      );

      expect(find.byKey(const Key('qr-scanner-completed')), findsOneWidget);
      expect(find.text('The item was already returned.'), findsOneWidget);
    });

    for (final (code, message) in [
      ('qr_loan_not_handed_over', 'Confirm the handover of the item first.'),
      (
        'qr_loan_already_issued',
        'The handover is already confirmed. Use the return code instead.',
      ),
      (
        'qr_loan_return_marked',
        'The owner marked the item as not returned; the dispute decides the '
            'outcome.',
      ),
      (
        'qr_loan_action_required',
        'A loan is confirmed by its handover and return actions.',
      ),
      (
        'qr_not_participant',
        'You are not a participant of this interaction and cannot confirm it.',
      ),
      ('qr_expired', 'The code has expired. Ask for a new one.'),
    ]) {
      testWidgets('the server refusal $code is explained', (tester) async {
        english(tester);
        final document = await qrSignedDocument();
        final server = loanQrServer(
          serverNow: () => DateTime.utc(2027, 1, 15, 12),
          participation: () => qrParticipationJson(
            kind: 'loan',
            participantId: userJson['id']! as String,
          ),
          listing: () => loanListingJson(author: qrOtherId),
          onScan: (_) => problemBody(409, code),
        );
        await openLoanQr(
          tester,
          server,
          qrScanPath(
            qrListingId,
            qrInteractionId,
            action: QrAction.loanHandover,
          ),
          cameraCode: document.encode,
        );
        await tester.tap(find.byKey(const Key('fake-scan')));
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.byKey(const Key('qr-scanner-success')), findsNothing);
        expect(find.byKey(const Key('qr-scanner-retry')), findsNothing);
      });
    }

    testWidgets('the own handover code is refused before it is sent', (
      tester,
    ) async {
      english(tester);
      final document = await qrSignedDocument(
        presenterId: userJson['id']! as String,
      );
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          kind: 'loan',
          participantId: userJson['id']! as String,
        ),
        listing: () => loanListingJson(author: qrOtherId),
      );
      await openLoanQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId, action: QrAction.loanHandover),
        cameraCode: document.encode,
      );
      await tester.tap(find.byKey(const Key('fake-scan')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This is your code: show it to the other participant and let them '
          'scan it.',
        ),
        findsOneWidget,
      );
      expect(
        server.sent.where((request) => request.path.contains('/qr')),
        isEmpty,
      );
    });

    testWidgets('a retry after network loss keeps the handover key', (
      tester,
    ) async {
      english(tester);
      final document = await qrSignedDocument();
      var attempts = 0;
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          kind: 'loan',
          participantId: userJson['id']! as String,
        ),
        listing: () => loanListingJson(author: qrOtherId),
        onScan: (options) {
          attempts++;
          if (attempts <= 4) {
            throw DioException.connectionError(
              requestOptions: options,
              reason: 'Connection reset by peer',
            );
          }
          return jsonBody(200, loanScanJson(handover: true));
        },
      );
      await openLoanQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId, action: QrAction.loanHandover),
        cameraCode: document.encode,
      );
      await tester.tap(find.byKey(const Key('fake-scan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qr-scanner-success')), findsNothing);
      expect(find.byKey(const Key('qr-scanner-retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('qr-scanner-retry')));
      await tester.pumpAndSettle();

      expect(find.text('The handover is confirmed.'), findsOneWidget);
      final keys = server.sent
          .where((request) => request.path.endsWith('/qr/handover'))
          .map((request) => request.headers['Idempotency-Key'])
          .toSet();
      expect(keys, hasLength(1));
      expect(keys.single, isNotEmpty);
    });

    testWidgets('a device without a camera explains why scanning is not '
        'available', (tester) async {
      english(tester);
      final server = loanQrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          kind: 'loan',
          participantId: userJson['id']! as String,
        ),
        listing: () => loanListingJson(author: qrOtherId),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await openLoanQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId, action: QrAction.loanHandover),
      );

      expect(
        find.text('Camera scanning is not available on this device.'),
        findsOneWidget,
      );
    });
  });
}
