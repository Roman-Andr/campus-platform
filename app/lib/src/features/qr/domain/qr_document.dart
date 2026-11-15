import 'dart:convert';

import 'base64url.dart';

/// The version of the online payload signed by the showing device.
const onlineQrVersion = 1;

/// The number of bytes of an Ed25519 signature.
const ed25519SignatureLength = 64;

/// Why a scanned QR code cannot be used by this device.
enum QrScanProblem {
  /// Not a meeting confirmation code, or a corrupted one.
  malformed,

  /// A code of another interaction or listing.
  otherInteraction,

  /// A code formed by this device: the showing participant cannot scan it.
  ownCode,
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

final _instantPattern = RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$');

/// The JSON document signed once by the showing device for an online code.
///
/// The signature covers the exact UTF-8 bytes of [toJson] in the inserted
/// order, which the server preserves while decoding. The document names the
/// interaction, the showing participant, the device key, the issue time and a
/// one-time nonce (ТЗ п. 5.1.1, модуль 5, пункт 1).
class QrPayload {
  const QrPayload({
    required this.listingId,
    required this.interactionId,
    required this.presenterId,
    required this.keyId,
    required this.issuedAt,
    required this.nonce,
  });

  /// Reads a payload of a scanned code; `null` for any invalid document.
  static QrPayload? fromJson(Map<String, Object?> json) {
    if (json.length != _keys.length || !json.keys.every(_keys.contains)) {
      return null;
    }
    if (json['v'] != onlineQrVersion) return null;
    final listingId = json['listing_id'];
    final interactionId = json['interaction_id'];
    final presenterId = json['presenter_id'];
    final keyId = json['key_id'];
    final issuedAt = json['issued_at'];
    final nonce = json['nonce'];
    if (listingId is! String ||
        interactionId is! String ||
        presenterId is! String ||
        keyId is! String ||
        nonce is! String ||
        issuedAt is! String) {
      return null;
    }
    if (!_isUuid(listingId) ||
        !_isUuid(interactionId) ||
        !_isUuid(presenterId) ||
        !_isUuid(keyId) ||
        !_isUuid(nonce)) {
      return null;
    }
    if (!_instantPattern.hasMatch(issuedAt)) return null;
    final at = DateTime.tryParse(issuedAt);
    if (at == null) return null;
    return QrPayload(
      listingId: listingId,
      interactionId: interactionId,
      presenterId: presenterId,
      keyId: keyId,
      issuedAt: at.toUtc(),
      nonce: nonce,
    );
  }

  static const _keys = <String>{
    'v',
    'listing_id',
    'interaction_id',
    'presenter_id',
    'key_id',
    'issued_at',
    'nonce',
  };

  final String listingId;
  final String interactionId;
  final String presenterId;
  final String keyId;
  final DateTime issuedAt;
  final String nonce;

  /// The document as it is signed, with a fixed field order.
  Map<String, Object?> toJson() => {
    'v': onlineQrVersion,
    'listing_id': listingId,
    'interaction_id': interactionId,
    'presenter_id': presenterId,
    'key_id': keyId,
    'issued_at': issuedAt.toUtc().toIso8601String(),
    'nonce': nonce,
  };

  /// The exact bytes covered by the signature.
  List<int> get bytes => utf8.encode(jsonEncode(toJson()));
}

/// A signed online code as it travels inside a QR code and in the scan
/// request: the encoded payload and the detached signature.
class QrScanDocument {
  const QrScanDocument({required this.payload, required this.signature});

  /// Reads a scanned QR code; `null` when it is not a well-formed document.
  static QrScanDocument? fromEncoded(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?> ||
        decoded.length != _keys.length ||
        !decoded.keys.every(_keys.contains)) {
      return null;
    }
    final payload = decoded['payload'];
    final signature = decoded['signature'];
    if (payload is! String || signature is! String) return null;
    if (tryBase64UrlDecode(payload) == null) return null;
    final signatureBytes = tryBase64UrlDecode(signature);
    if (signatureBytes == null ||
        signatureBytes.length != ed25519SignatureLength) {
      return null;
    }
    return QrScanDocument(payload: payload, signature: signature);
  }

  static const _keys = <String>{'payload', 'signature'};

  final String payload;
  final String signature;

  /// The content of the displayed QR code.
  String encode() => jsonEncode({'payload': payload, 'signature': signature});

  /// The payload of the code, or `null` when its bytes are not a v1 document.
  QrPayload? get decodedPayload {
    final bytes = tryBase64UrlDecode(payload);
    if (bytes == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    return QrPayload.fromJson(decoded);
  }
}

/// The result of reading a scanned QR code for one interaction.
sealed class ScannedQr {
  const ScannedQr();
}

/// A code that belongs to this interaction and may be sent to the server.
final class UsableQr extends ScannedQr {
  const UsableQr({required this.document, required this.payload});

  final QrScanDocument document;
  final QrPayload payload;
}

/// A code that this interaction cannot use, with a reason for the interface.
final class RejectedQr extends ScannedQr {
  const RejectedQr(this.problem);

  final QrScanProblem problem;
}

/// Reads [raw] as a code of the interaction [listingId]/[interactionId].
///
/// The signature is verified by the server, which holds the registered public
/// key; here only the shape, the addressed interaction and the participant
/// are checked, so obvious mistakes show a clear message without a request.
ScannedQr readScannedQr(
  String raw, {
  required String listingId,
  required String interactionId,
  required String? viewerId,
}) {
  final document = QrScanDocument.fromEncoded(raw);
  if (document == null) return const RejectedQr(QrScanProblem.malformed);
  final payload = document.decodedPayload;
  if (payload == null) return const RejectedQr(QrScanProblem.malformed);
  if (payload.listingId != listingId ||
      payload.interactionId != interactionId) {
    return const RejectedQr(QrScanProblem.otherInteraction);
  }
  if (viewerId != null && payload.presenterId == viewerId) {
    return const RejectedQr(QrScanProblem.ownCode);
  }
  return UsableQr(document: document, payload: payload);
}

bool _isUuid(String value) => _uuidPattern.hasMatch(value);
