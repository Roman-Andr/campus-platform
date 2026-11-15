import 'dart:convert';

import 'package:campus/src/features/qr/domain/base64url.dart';
import 'package:campus/src/features/qr/domain/qr_document.dart';
import 'package:campus/src/features/qr/domain/qr_signing.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'fixtures.dart';

QrPayload payloadWith({
  String listingId = qrListingId,
  String interactionId = qrInteractionId,
  String presenterId = qrOtherId,
  String keyId = qrKeyId,
  DateTime? issuedAt,
  String nonce = qrNonce,
}) => QrPayload(
  listingId: listingId,
  interactionId: interactionId,
  presenterId: presenterId,
  keyId: keyId,
  issuedAt: issuedAt ?? DateTime.utc(2027, 1, 15, 12),
  nonce: nonce,
);

Map<String, Object?> payloadJson({Object? version = 1}) => {
  'v': version,
  'listing_id': qrListingId,
  'interaction_id': qrInteractionId,
  'presenter_id': qrOtherId,
  'key_id': qrKeyId,
  'issued_at': '2027-01-15T12:00:00Z',
  'nonce': qrNonce,
};

String contentOf(Map<String, Object?> payload, {String? signature}) =>
    jsonEncode({
      'payload': base64UrlNoPadding(utf8.encode(jsonEncode(payload))),
      'signature': signature ?? base64UrlNoPadding(List.filled(64, 7)),
    });

void main() {
  group('QrPayload', () {
    test('has the v1 alias a fixed field order and an UTC instant', () {
      final payload = payloadWith(
        issuedAt: DateTime.utc(2027, 1, 15, 12, 0, 0, 123),
      );

      expect(payload.toJson().keys, [
        'v',
        'listing_id',
        'interaction_id',
        'presenter_id',
        'key_id',
        'issued_at',
        'nonce',
      ]);
      expect(payload.toJson()['v'], 1);
      expect(payload.toJson()['issued_at'], '2027-01-15T12:00:00.123Z');
      expect(
        utf8.decode(payload.bytes),
        '{"v":1,"listing_id":"$qrListingId",'
        '"interaction_id":"$qrInteractionId","presenter_id":"$qrOtherId",'
        '"key_id":"$qrKeyId","issued_at":"2027-01-15T12:00:00.123Z",'
        '"nonce":"$qrNonce"}',
      );
    });

    test('reads back every field of a valid document', () {
      final payload = QrPayload.fromJson(payloadJson())!;

      expect(payload.listingId, qrListingId);
      expect(payload.interactionId, qrInteractionId);
      expect(payload.presenterId, qrOtherId);
      expect(payload.keyId, qrKeyId);
      expect(payload.issuedAt, DateTime.utc(2027, 1, 15, 12));
      expect(payload.nonce, qrNonce);
    });

    test('rejects a document with a wrong version or an unknown field', () {
      expect(QrPayload.fromJson(payloadJson(version: 2)), isNull);
      expect(QrPayload.fromJson({...payloadJson(), 'extra': 'value'}), isNull);
      final missing = Map<String, Object?>.of(payloadJson())..remove('nonce');
      expect(QrPayload.fromJson(missing), isNull);
    });

    test('rejects malformed identifiers and a time without an offset', () {
      expect(
        QrPayload.fromJson({...payloadJson(), 'listing_id': 'not-a-uuid'}),
        isNull,
      );
      expect(
        QrPayload.fromJson({
          ...payloadJson(),
          'issued_at': '2027-01-15T12:00:00',
        }),
        isNull,
      );
      expect(
        QrPayload.fromJson({...payloadJson(), 'issued_at': 'yesterday'}),
        isNull,
      );
    });
  });

  group('QrScanDocument', () {
    test('round-trips the content of a QR code', () {
      final document = QrScanDocument(
        payload: base64UrlNoPadding(payloadWith().bytes),
        signature: base64UrlNoPadding(List.filled(64, 1)),
      );

      final parsed = QrScanDocument.fromEncoded(document.encode())!;
      expect(parsed.payload, document.payload);
      expect(parsed.signature, document.signature);
      expect(parsed.decodedPayload?.nonce, qrNonce);
    });

    test('rejects content that is not a scan document', () {
      final valid = contentOf(payloadJson());
      expect(QrScanDocument.fromEncoded('https://example.com'), isNull);
      expect(QrScanDocument.fromEncoded('{"payload":"x"}'), isNull);
      expect(
        QrScanDocument.fromEncoded(
          jsonEncode({'payload': 'x', 'signature': 'y', 'extra': 1}),
        ),
        isNull,
      );
      expect(
        QrScanDocument.fromEncoded(valid.replaceFirst('"payload"', '"p"')),
        isNull,
      );
    });

    test('rejects a signature of the wrong size', () {
      expect(
        QrScanDocument.fromEncoded(
          contentOf(payloadJson(), signature: base64UrlNoPadding([1, 2, 3])),
        ),
        isNull,
      );
    });

    test('rejects a payload that is not a v1 document', () {
      expect(
        QrScanDocument.fromEncoded(contentOf({...payloadJson(), 'v': 2}))
            ?.decodedPayload,
        isNull,
      );
    });
  });

  group('signOnlineQr', () {
    test('signs the exact payload bytes with the device key', () async {
      final key = await qrSigningKey();
      final issuedAt = DateTime.utc(2027, 1, 15, 12, 0, 0, 500);
      final document = await signOnlineQr(
        key: key,
        listingId: qrListingId,
        interactionId: qrInteractionId,
        presenterId: qrOtherId,
        issuedAt: issuedAt,
        nonce: qrNonce,
      );

      final bytes = tryBase64UrlDecode(document.payload)!;
      final signature = Signature(
        tryBase64UrlDecode(document.signature)!,
        publicKey: await key.keyPair.extractPublicKey(),
      );
      expect(await Ed25519().verify(bytes, signature: signature), isTrue);
      expect(
        QrPayload.fromJson(
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
        )?.issuedAt,
        issuedAt,
      );

      // The signature covers the encoded bytes, so a changed byte fails.
      final tampered = [...bytes]..[0] ^= 1;
      expect(await Ed25519().verify(tampered, signature: signature), isFalse);
    });
  });

  group('readScannedQr', () {
    test('accepts a code of the interaction', () async {
      final document = await qrSignedDocument();
      final scanned = readScannedQr(
        document.encode(),
        listingId: qrListingId,
        interactionId: qrInteractionId,
        viewerId: userJson['id']! as String,
      );

      expect(scanned, isA<UsableQr>());
      expect((scanned as UsableQr).payload.presenterId, qrOtherId);
    });

    test('rejects the own code of the showing participant', () async {
      final document = await qrSignedDocument();
      final scanned = readScannedQr(
        document.encode(),
        listingId: qrListingId,
        interactionId: qrInteractionId,
        viewerId: qrOtherId,
      );

      expect(scanned, isA<RejectedQr>());
      expect((scanned as RejectedQr).problem, QrScanProblem.ownCode);
    });

    test('rejects a code of another interaction', () async {
      final document = await qrSignedDocument(
        interactionId: '01890a5d-ac96-774b-bcce-b302099a8099',
      );
      final scanned = readScannedQr(
        document.encode(),
        listingId: qrListingId,
        interactionId: qrInteractionId,
        viewerId: userJson['id']! as String,
      );

      expect((scanned as RejectedQr).problem, QrScanProblem.otherInteraction);
    });

    test('rejects a code that is not a signed document', () {
      final scanned = readScannedQr(
        'just some text',
        listingId: qrListingId,
        interactionId: qrInteractionId,
        viewerId: null,
      );

      expect((scanned as RejectedQr).problem, QrScanProblem.malformed);
    });
  });
}
