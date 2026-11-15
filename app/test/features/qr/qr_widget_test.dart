import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/qr/application/qr_providers.dart';
import 'package:campus/src/features/qr/domain/base64url.dart';
import 'package:campus/src/features/qr/presentation/meeting_qr_code.dart';
import 'package:campus/src/features/qr/presentation/qr_camera.dart';
import 'package:campus/src/features/qr/presentation/qr_presenter_screen.dart';
import 'package:campus/src/features/qr/presentation/qr_scanner_screen.dart';
import 'package:clock/clock.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import '../listings/fixtures.dart';
import 'fixtures.dart';

final _l = AppLocalizationsEn();

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

/// The adapter of a running app with the QR endpoints of the server.
FakeHttpAdapter qrServer({
  required DateTime Function() serverNow,
  required Map<String, Object?> Function() participation,
  Map<String, Object?> Function()? listing,
  ResponseBody Function(RequestOptions options)? onTime,
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
      return jsonBody(
        200,
        (listing ??
            () => listingJson(
              id: qrListingId,
              author: userJson['id']! as String,
            ))(),
      );
    }
    if (path == '/api/v1/time') {
      return (onTime ??
          (_) => jsonBody(200, qrServerTimeJson(now: serverNow())))(options);
    }
    if (path == '/api/v1/me/device-key' && options.method == 'PUT') {
      final body = jsonDecode(options.data! as String) as Map<String, Object?>;
      return jsonBody(
        200,
        qrDeviceKeyJson(publicKey: body['public_key']! as String),
      );
    }
    if (path ==
            '/api/v1/listings/$qrListingId/interactions/$qrInteractionId/qr' &&
        options.method == 'POST') {
      return (onScan ?? (_) => jsonBody(200, qrScanOutputJson()))(options);
    }
    return jsonBody(200, pageJson([]));
  });
  return adapter;
}

Future<ProviderContainer> openQr(
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
    testWidgets('signs a code with the server clock and refreshes it', (
      tester,
    ) async {
      english(tester);
      var deviceNow = DateTime.utc(2027, 1, 15, 12);
      var serverNow = deviceNow.add(const Duration(minutes: 3));
      final server = qrServer(
        serverNow: () => serverNow,
        participation: qrParticipationJson,
      );

      await withClock(Clock(() => deviceNow), () async {
        await openQr(tester, server, qrShowPath(qrListingId, qrInteractionId));

        expect(find.byKey(const Key('qr-presenter-code')), findsOneWidget);
        final first = shownCode(tester).document;
        final payload = first.decodedPayload!;
        expect(payload.listingId, qrListingId);
        expect(payload.interactionId, qrInteractionId);
        expect(payload.presenterId, userJson['id']);
        expect(payload.keyId, qrKeyId);
        // The device clock is three minutes slow; the code carries the
        // server time instead.
        expect(payload.issuedAt, serverNow);
        expect(
          payload.issuedAt.difference(deviceNow),
          const Duration(minutes: 3),
        );
        expect(
          find.byKey(const Key('qr-presenter-valid-until')),
          findsOneWidget,
        );

        final register = server.sent.singleWhere(
          (request) => request.path == '/api/v1/me/device-key',
        );
        final publicKey = tryBase64UrlDecode(
          register.json['public_key']! as String,
        )!;
        final verified = await Ed25519().verify(
          tryBase64UrlDecode(first.payload)!,
          signature: Signature(
            tryBase64UrlDecode(first.signature)!,
            publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
          ),
        );
        expect(verified, isTrue);

        deviceNow = deviceNow.add(const Duration(seconds: 25));
        serverNow = serverNow.add(const Duration(seconds: 25));
        await tester.pump(const Duration(seconds: 25));
        await tester.pumpAndSettle();

        final second = shownCode(tester).document;
        expect(second.payload, isNot(first.payload));
        expect(second.decodedPayload!.issuedAt, serverNow);
        expect(
          second.decodedPayload!.nonce,
          isNot(first.decodedPayload!.nonce),
        );
        expect(
          server.sent.where((request) => request.path == '/api/v1/time'),
          hasLength(2),
        );
        // The key is registered once per screen.
        expect(
          server.sent.where(
            (request) => request.path == '/api/v1/me/device-key',
          ),
          hasLength(1),
        );
      });
    });

    testWidgets('a failed refresh keeps the valid code and recovers', (
      tester,
    ) async {
      english(tester);
      var deviceNow = DateTime.utc(2027, 1, 15, 12);
      var serverNow = DateTime.utc(2027, 1, 15, 12, 0, 5);
      var online = true;
      final server = qrServer(
        serverNow: () => serverNow,
        participation: qrParticipationJson,
        onTime: (options) {
          if (!online) {
            throw DioException.connectionError(
              requestOptions: options,
              reason: 'Connection reset by peer',
            );
          }
          return jsonBody(200, qrServerTimeJson(now: serverNow));
        },
      );

      await withClock(Clock(() => deviceNow), () async {
        await openQr(tester, server, qrShowPath(qrListingId, qrInteractionId));
        final first = shownCode(tester).document;

        online = false;
        deviceNow = deviceNow.add(const Duration(seconds: 25));
        serverNow = serverNow.add(const Duration(seconds: 25));
        await tester.pump(const Duration(seconds: 25));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('qr-presenter-warning')), findsOneWidget);
        expect(find.byKey(const Key('qr-presenter-error')), findsNothing);
        expect(shownCode(tester).document.payload, first.payload);

        online = true;
        deviceNow = deviceNow.add(const Duration(seconds: 1));
        serverNow = serverNow.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('qr-presenter-warning')), findsNothing);
        expect(shownCode(tester).document.payload, isNot(first.payload));
      });
    });

    testWidgets('an expired code is never shown as valid', (tester) async {
      english(tester);
      var deviceNow = DateTime.utc(2027, 1, 15, 12);
      var serverNow = deviceNow;
      var online = true;
      final server = qrServer(
        serverNow: () => serverNow,
        participation: qrParticipationJson,
        onTime: (options) {
          if (!online) {
            throw DioException.connectionError(
              requestOptions: options,
              reason: 'Connection reset by peer',
            );
          }
          return jsonBody(200, qrServerTimeJson(now: serverNow));
        },
      );

      await withClock(Clock(() => deviceNow), () async {
        await openQr(tester, server, qrShowPath(qrListingId, qrInteractionId));
        expect(find.byKey(const Key('qr-presenter-code')), findsOneWidget);

        online = false;
        deviceNow = deviceNow.add(const Duration(seconds: 40));
        serverNow = serverNow.add(const Duration(seconds: 40));
        await tester.pump(const Duration(seconds: 40));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('qr-presenter-code')), findsNothing);
        expect(find.byKey(const Key('qr-presenter-error')), findsOneWidget);
      });
    });

    testWidgets('a completed interaction shows the server result', (
      tester,
    ) async {
      english(tester);
      var participation = qrParticipationJson();
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => participation,
      );

      await openQr(tester, server, qrShowPath(qrListingId, qrInteractionId));
      expect(find.byKey(const Key('qr-presenter-code')), findsOneWidget);

      participation = qrParticipationJson(
        status: 'completed',
        completionMethod: 'qr',
        completedAt: DateTime.utc(2027, 1, 15, 12, 1),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qr-presenter-code')), findsNothing);
      expect(find.text(_l.qrPresenterCompleted), findsOneWidget);
      expect(find.textContaining('15:01'), findsOneWidget);
    });

    testWidgets('a pending interaction cannot be confirmed', (tester) async {
      english(tester);
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(status: 'pending'),
      );

      await openQr(tester, server, qrShowPath(qrListingId, qrInteractionId));

      expect(find.text(_l.qrPresenterNotAccepted), findsOneWidget);
      expect(
        server.sent.where((request) => request.path == '/api/v1/time'),
        isEmpty,
      );
    });
  });

  group('scanner', () {
    testWidgets('a scanned code confirms the meeting once', (tester) async {
      english(tester);
      final document = await qrSignedDocument();
      var participation = qrParticipationJson(
        participantId: userJson['id']! as String,
      );
      Map<String, Object?>? sentBody;
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => participation,
        listing: () => listingJson(id: qrListingId, author: qrOtherId),
        onScan: (options) {
          sentBody = qrRequestJson(options.data);
          participation = qrParticipationJson(
            status: 'completed',
            participantId: userJson['id']! as String,
            completionMethod: 'qr',
            completedAt: DateTime.utc(2027, 1, 15, 12, 0, 30),
          );
          return jsonBody(
            200,
            qrScanOutputJson(completedAt: DateTime.utc(2027, 1, 15, 12, 0, 30)),
          );
        },
      );

      await openQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId),
        cameraCode: document.encode,
      );
      expect(find.byKey(const Key('qr-scanner-camera')), findsOneWidget);

      await tester.tap(find.byKey(const Key('fake-scan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qr-scanner-success')), findsOneWidget);
      expect(find.textContaining('15:00'), findsOneWidget);
      expect(sentBody, isNotNull);
      expect(sentBody!['payload'], document.payload);
      expect(sentBody!['signature'], document.signature);
      final scan = server.sent.singleWhere(
        (request) => request.method == 'POST' && request.path.endsWith('/qr'),
      );
      expect(scan.headers['Idempotency-Key'], isNotEmpty);
    });

    testWidgets('a lost response is retried with the same Idempotency-Key', (
      tester,
    ) async {
      english(tester);
      final document = await qrSignedDocument();
      var attempts = 0;
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () =>
            qrParticipationJson(participantId: userJson['id']! as String),
        listing: () => listingJson(id: qrListingId, author: qrOtherId),
        onScan: (options) {
          attempts++;
          if (attempts <= 4) {
            throw DioException.connectionError(
              requestOptions: options,
              reason: 'Connection reset by peer',
            );
          }
          return jsonBody(200, qrScanOutputJson());
        },
      );

      await openQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId),
        cameraCode: document.encode,
      );
      await tester.tap(find.byKey(const Key('fake-scan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qr-scanner-success')), findsNothing);
      expect(find.text(_l.errorNetwork), findsOneWidget);
      expect(find.byKey(const Key('qr-scanner-retry')), findsOneWidget);
      expect(attempts, 4);

      await tester.tap(find.byKey(const Key('qr-scanner-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qr-scanner-success')), findsOneWidget);
      final keys = server.sent
          .where((request) => request.path.endsWith('/qr'))
          .map((request) => request.headers['Idempotency-Key'])
          .toSet();
      expect(keys, hasLength(1));
      expect(keys.single, isNotEmpty);
      expect(attempts, 5);
    });

    testWidgets('the own code of the showing participant is refused', (
      tester,
    ) async {
      english(tester);
      final document = await qrSignedDocument(
        presenterId: userJson['id']! as String,
      );
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () =>
            qrParticipationJson(participantId: userJson['id']! as String),
        listing: () => listingJson(id: qrListingId, author: qrOtherId),
      );

      await openQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId),
        cameraCode: document.encode,
      );
      await tester.tap(find.byKey(const Key('fake-scan')));
      await tester.pumpAndSettle();

      expect(find.text(_l.qrScannerOwnCode), findsOneWidget);
      expect(
        server.sent.where((request) => request.path.endsWith('/qr')),
        isEmpty,
      );
    });

    testWidgets('a code of another interaction is refused', (tester) async {
      english(tester);
      final document = await qrSignedDocument(
        interactionId: '01890a5d-ac96-774b-bcce-b302099a8099',
      );
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () =>
            qrParticipationJson(participantId: userJson['id']! as String),
        listing: () => listingJson(id: qrListingId, author: qrOtherId),
      );

      await openQr(
        tester,
        server,
        qrScanPath(qrListingId, qrInteractionId),
        cameraCode: document.encode,
      );
      await tester.tap(find.byKey(const Key('fake-scan')));
      await tester.pumpAndSettle();

      expect(find.text(_l.qrScannerWrongInteraction), findsOneWidget);
      expect(
        server.sent.where((request) => request.path.endsWith('/qr')),
        isEmpty,
      );
    });

    for (final (code, status, message) in [
      ('qr_expired', 409, _l.qrScannerExpired),
      ('qr_key_invalid', 403, _l.qrScannerUnknownKey),
      ('qr_nonce_reused', 409, _l.qrScannerUsed),
      ('qr_not_participant', 403, _l.qrScannerNotParticipant),
    ]) {
      testWidgets('the server rejection $code is explained', (tester) async {
        english(tester);
        final document = await qrSignedDocument();
        final server = qrServer(
          serverNow: () => DateTime.utc(2027, 1, 15, 12),
          participation: () =>
              qrParticipationJson(participantId: userJson['id']! as String),
          listing: () => listingJson(id: qrListingId, author: qrOtherId),
          onScan: (options) => problemBody(status, code),
        );

        await openQr(
          tester,
          server,
          qrScanPath(qrListingId, qrInteractionId),
          cameraCode: document.encode,
        );
        await tester.tap(find.byKey(const Key('fake-scan')));
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.byKey(const Key('qr-scanner-success')), findsNothing);
        expect(find.byKey(const Key('qr-scanner-retry')), findsNothing);
      });
    }

    testWidgets('a completed interaction shows the result without scanning', (
      tester,
    ) async {
      english(tester);
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          status: 'completed',
          participantId: userJson['id']! as String,
          completionMethod: 'qr',
          completedAt: DateTime.utc(2027, 1, 15, 12, 0, 30),
        ),
        listing: () => listingJson(id: qrListingId, author: qrOtherId),
      );

      await openQr(tester, server, qrScanPath(qrListingId, qrInteractionId));

      expect(find.byKey(const Key('qr-scanner-completed')), findsOneWidget);
      expect(find.byKey(const Key('qr-scanner-camera')), findsNothing);
      expect(
        server.sent.where((request) => request.path.endsWith('/qr')),
        isEmpty,
      );
      expect(find.textContaining('15:00'), findsOneWidget);
    });

    testWidgets('an interaction completed otherwise is explained', (
      tester,
    ) async {
      english(tester);
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          status: 'completed',
          participantId: userJson['id']! as String,
          completionMethod: 'no_meeting',
          completedAt: DateTime.utc(2027, 1, 15, 12),
        ),
        listing: () => listingJson(id: qrListingId, author: qrOtherId),
      );

      await openQr(tester, server, qrScanPath(qrListingId, qrInteractionId));

      expect(find.text(_l.qrScannerAlreadyCompleted), findsOneWidget);
      expect(find.byKey(const Key('qr-scanner-camera')), findsNothing);
    });
  });

  group('summary', () {
    testWidgets('an accepted interaction opens both sides of the code', (
      tester,
    ) async {
      english(tester);
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () =>
            qrParticipationJson(participantId: userJson['id']! as String),
        listing: () => listingJson(id: qrListingId, author: qrOtherId),
      );
      await tester.pumpCampusApp(
        InMemorySettingsRepository(),
        adapter: server,
        overrides: [
          deviceKeyStoreProvider.overrideWithValue(InMemoryDeviceKeyStore()),
          qrCameraBuilderProvider.overrideWithValue(
            fakeCamera(() => 'anything'),
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('home-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-my-listings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My participation'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('qr-confirmation-$qrInteractionId')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qr-show-$qrInteractionId')), findsOneWidget);

      await tester.tap(find.byKey(const Key('qr-scan-$qrInteractionId')));
      await tester.pumpAndSettle();
      expect(find.text(_l.qrScannerTitle), findsOneWidget);
      expect(find.byKey(const Key('qr-scanner-camera')), findsOneWidget);
    });

    testWidgets('a completed interaction has no card', (tester) async {
      english(tester);
      final server = qrServer(
        serverNow: () => DateTime.utc(2027, 1, 15, 12),
        participation: () => qrParticipationJson(
          status: 'completed',
          participantId: userJson['id']! as String,
          completionMethod: 'qr',
          completedAt: DateTime.utc(2027, 1, 15, 12),
        ),
        listing: () => listingJson(id: qrListingId, author: qrOtherId),
      );
      await tester.pumpCampusApp(InMemorySettingsRepository(), adapter: server);
      await tester.tap(find.byKey(const Key('home-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-my-listings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My participation'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('qr-confirmation-$qrInteractionId')),
        findsNothing,
      );
    });
  });
}
