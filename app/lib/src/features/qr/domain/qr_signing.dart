import 'package:cryptography/cryptography.dart';

import 'base64url.dart';
import 'qr_document.dart';

/// The device key pair used to sign online codes and the ID of its registered
/// public half.
class QrSigningKey {
  const QrSigningKey({
    required this.keyPair,
    required this.keyId,
    required this.publicKey,
  });

  final SimpleKeyPair keyPair;

  /// Server ID of the registered public key, sent inside signed payloads.
  final String keyId;

  /// Unpadded base64url of the 32 public key bytes.
  final String publicKey;
}

/// Signs an online payload with the device key.
///
/// The signature is made over the exact bytes of the JSON document, which
/// travel base64url-encoded inside the QR code; the server verifies them with
/// the registered public key (ТЗ п. 5.1.1, модуль 5, пункт 1).
Future<QrScanDocument> signOnlineQr({
  required QrSigningKey key,
  required String listingId,
  required String interactionId,
  required String presenterId,
  required DateTime issuedAt,
  required String nonce,
  Ed25519? algorithm,
}) async {
  final payload = QrPayload(
    listingId: listingId,
    interactionId: interactionId,
    presenterId: presenterId,
    keyId: key.keyId,
    issuedAt: issuedAt.toUtc(),
    nonce: nonce,
  );
  final bytes = payload.bytes;
  final signature = await (algorithm ?? Ed25519()).sign(
    bytes,
    keyPair: key.keyPair,
  );
  return QrScanDocument(
    payload: base64UrlNoPadding(bytes),
    signature: base64UrlNoPadding(signature.bytes),
  );
}
