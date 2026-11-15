import 'dart:convert';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/features/qr/data/device_key_manager.dart';
import 'package:campus/src/features/qr/data/device_key_store.dart';
import 'package:campus/src/features/qr/domain/base64url.dart';
import 'package:campus/src/features/qr/domain/qr_document.dart';
import 'package:campus/src/features/qr/domain/qr_signing.dart';
import 'package:cryptography/cryptography.dart';

import '../../helpers/fake_api.dart';

/// Identifiers of a QR fixture; all values are valid UUIDs.
const qrListingId = '01890a5d-ac96-774b-bcce-b302099a8060';
const qrInteractionId = '01890a5d-ac96-774b-bcce-b302099a8061';
const qrKeyId = '01890a5d-ac96-774b-bcce-b302099a8062';
const qrOtherId = '01890a5d-ac96-774b-bcce-b302099a8063';
const qrNonce = '01890a5d-ac96-774b-bcce-b302099a8064';

/// A fixed Ed25519 seed, so a test can verify the signature.
const qrSeed = <int>[
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
  32,
];

/// The device key of the other participant.
Future<QrSigningKey> qrSigningKey({String keyId = qrKeyId}) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(qrSeed);
  return QrSigningKey(
    keyPair: keyPair,
    keyId: keyId,
    publicKey: base64UrlNoPadding((await keyPair.extractPublicKey()).bytes),
  );
}

/// A signed v1 code of [presenterId] for the interaction.
Future<QrScanDocument> qrSignedDocument({
  String listingId = qrListingId,
  String interactionId = qrInteractionId,
  String presenterId = qrOtherId,
  String keyId = qrKeyId,
  String nonce = qrNonce,
  DateTime? issuedAt,
}) async => signOnlineQr(
  key: await qrSigningKey(keyId: keyId),
  listingId: listingId,
  interactionId: interactionId,
  presenterId: presenterId,
  issuedAt: issuedAt ?? DateTime.utc(2027, 1, 15, 12),
  nonce: nonce,
);

Map<String, Object?> qrServerTimeJson({
  required DateTime now,
  int onlineTtl = 30,
  int offlineTtl = 86400,
  int skew = 10,
}) => {
  'now': now.toUtc().toIso8601String(),
  'qr_online_ttl': onlineTtl,
  'qr_offline_ttl': offlineTtl,
  'qr_clock_skew': skew,
};

Map<String, Object?> qrDeviceKeyJson({
  required String publicKey,
  String id = qrKeyId,
  DateTime? registeredAt,
}) => {
  'id': id,
  'algorithm': 'ed25519',
  'public_key': publicKey,
  'registered_at': (registeredAt ?? DateTime.utc(2027, 1, 15, 12))
      .toIso8601String(),
  'revoked_at': null,
};

Map<String, Object?> qrScanOutputJson({
  String presenterId = qrOtherId,
  DateTime? completedAt,
  String nonce = qrNonce,
  String completionMethod = 'qr',
  String status = 'completed',
}) {
  final at = completedAt ?? DateTime.utc(2027, 1, 15, 12, 0, 30);
  return {
    'listing_id': qrListingId,
    'interaction_id': qrInteractionId,
    'presenter_id': presenterId,
    'scanner_id': userJson['id'],
    'status': status,
    'completed': status == 'completed',
    'completed_at': status == 'completed' ? at.toIso8601String() : null,
    'completion_method': status == 'completed' ? completionMethod : null,
    'rating_weight': status == 'completed' ? 1 : null,
    'nonce': nonce,
    'issued_at': at.subtract(const Duration(seconds: 1)).toIso8601String(),
    'received_at': at.toIso8601String(),
    'server_time': at.toIso8601String(),
  };
}

Map<String, Object?> qrParticipationJson({
  String status = 'accepted',
  String kind = 'giveaway',
  String participantId = qrOtherId,
  String? stage,
  String? completionMethod,
  DateTime? completedAt,
}) => {
  'id': qrInteractionId,
  'listing_id': qrListingId,
  'participant_name': 'Boris',
  'participant_id': participantId,
  'status': status,
  'stage': stage,
  'response_due_at': null,
  'executor': false,
  'meeting': null,
  'completion_method': completionMethod,
  'completed_at': completedAt?.toIso8601String(),
  'created_at': '2027-01-14T00:00:00Z',
  'listing': {
    'id': qrListingId,
    'kind': kind,
    'title': 'A desk',
    'status': status == 'completed' ? 'completed' : 'active',
    'city_timezone': 'Europe/Moscow',
  },
};

const qrCitiesJson = {
  'items': [
    {
      'id': 'city-moscow',
      'code': 'moscow',
      'name': 'Moscow',
      'timezone': 'Europe/Moscow',
    },
  ],
};

/// A Problem Details failure with the given code.
ProblemFailure qrProblem(int status, String code) => ProblemFailure(
  Problem.fromJson({
    'type': 'urn:problem:campus:$code',
    'title': 'Title',
    'status': status,
    'code': code,
    'request_id': 'req-1',
  }),
);

/// Device key storage kept in memory; a widget test starts without a key.
class InMemoryDeviceKeyStore implements DeviceKeyStore {
  StoredDeviceKey? saved;

  @override
  Future<StoredDeviceKey?> read() async => saved;

  @override
  Future<void> write(StoredDeviceKey key) async => saved = key;
}

/// Registration answer of the server, recording its requests.
class FakeDeviceKeyRegistrar implements DeviceKeyRegistrar {
  FakeDeviceKeyRegistrar(this._answer);

  final Future<String> Function(String publicKey) _answer;
  final calls = <({String publicKey, String idempotencyKey})>[];

  @override
  Future<String> register({
    required String publicKey,
    required String idempotencyKey,
  }) {
    calls.add((publicKey: publicKey, idempotencyKey: idempotencyKey));
    return _answer(publicKey);
  }
}

/// Decodes the JSON body of a scan request.
Map<String, Object?> qrRequestJson(Object? data) =>
    jsonDecode(data! as String) as Map<String, Object?>;
