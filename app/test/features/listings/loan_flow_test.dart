import 'dart:convert';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/features/listings/application/loan.dart';
import 'package:campus/src/features/qr/domain/base64url.dart';
import 'package:campus/src/features/qr/domain/qr_document.dart';
import 'package:campus/src/features/qr/domain/qr_signing.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'fixtures.dart';

const _owner = '01890a5d-ac96-774b-bcce-b302099a80a0';
const _borrower = '01890a5d-ac96-774b-bcce-b302099a80a1';
const _listing = '01890a5d-ac96-774b-bcce-b302099a80a2';
const _interaction = '01890a5d-ac96-774b-bcce-b302099a80a3';
const _ownerKey = '01890a5d-ac96-774b-bcce-b302099a80a4';
const _borrowerKey = '01890a5d-ac96-774b-bcce-b302099a80a5';

const _loanDays = 5;
const _onlineTtl = 30;
final _now = DateTime.utc(2027, 1, 15, 12);

/// A signing key of one participant, as their device holds it.
class _Keys {
  _Keys(this.owner, this.borrower);

  final QrSigningKey owner;
  final QrSigningKey borrower;
}

Future<QrSigningKey> _key(List<int> seed, String keyId) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  return QrSigningKey(
    keyPair: keyPair,
    keyId: keyId,
    publicKey: base64UrlNoPadding((await keyPair.extractPublicKey()).bytes),
  );
}

/// The state of one loan interaction as both participants change it.
///
/// It plays the server of #214 for the client flow: the endpoints, the
/// signature and nonce checks of the two loan actions and the state of the
/// interaction. The client code under test is the real one: the generated
/// client, the signing of the showing side and the model parsing.
class _Scenario {
  String status = 'pending';
  String? stage;
  DateTime? returnDueAt;
  DateTime? completedAt;
  final usedNonces = <String>{};
  final requests = <SentRequest>[];
  final scanned = <(String presenter, QrScanDocument document)>[];

  _Scenario({required this.keys});

  final _Keys keys;

  FakeHttpAdapter adapter(String userId) {
    final adapter = FakeHttpAdapter();
    adapter.me = {...userJson, 'id': userId, ...filledProfileJson};
    adapter.route((options) {
      requests.add(SentRequest(options));
      return _handle(userId, options);
    });
    return adapter;
  }

  ResponseBody _handle(String userId, RequestOptions options) {
    final path = options.path;
    if (path.endsWith('/token/refresh')) {
      return jsonBody(200, tokensJson(1));
    }
    if (path == '/api/v1/listings/loans' && options.method == 'POST') {
      return jsonBody(201, _listingJson());
    }
    if (path == '/api/v1/listings/$_listing') {
      return jsonBody(200, _listingJson());
    }
    if (path == '/api/v1/listings/$_listing/reservations' &&
        options.method == 'POST') {
      return jsonBody(201, _interactionJson());
    }
    if (path.endsWith('/transition') && options.method == 'POST') {
      final body = _body(options);
      if (body['status'] == 'accepted') status = 'accepted';
      return jsonBody(200, _interactionJson());
    }
    if (path.endsWith('/qr/handover') && options.method == 'POST') {
      return _handover(userId, options);
    }
    if (path.endsWith('/qr/return') && options.method == 'POST') {
      return _return(userId, options);
    }
    if (path.endsWith('/qr') && options.method == 'POST') {
      return problemBody(409, 'qr_loan_action_required');
    }
    return problemBody(404, 'not_found');
  }

  ResponseBody _handover(String userId, RequestOptions options) {
    if (status != 'accepted' || stage != null) {
      return problemBody(409, 'qr_loan_already_issued');
    }
    final error = _checkCode(userId, options, presenter: _owner);
    if (error != null) return error;
    stage = 'issued';
    returnDueAt = _now.add(const Duration(days: _loanDays));
    return jsonBody(
      200,
      _scanJson(handover: true, presenterId: _owner, scannerId: _borrower),
    );
  }

  ResponseBody _return(String userId, RequestOptions options) {
    if (status != 'accepted' || stage != 'issued') {
      return problemBody(409, 'qr_loan_not_handed_over');
    }
    final error = _checkCode(userId, options, presenter: _borrower);
    if (error != null) return error;
    status = 'completed';
    completedAt = _now;
    stage = null;
    return jsonBody(
      200,
      _scanJson(handover: false, presenterId: _borrower, scannerId: _owner),
    );
  }

  /// The checks the server of #214 applies to a scanned online code.
  ResponseBody? _checkCode(
    String userId,
    RequestOptions options, {
    required String presenter,
  }) {
    final body = _body(options);
    final document = QrScanDocument(
      payload: body['payload']! as String,
      signature: body['signature']! as String,
    );
    final payload = document.decodedPayload!;
    if (userId != (presenter == _owner ? _borrower : _owner)) {
      return problemBody(403, 'qr_not_participant');
    }
    if (payload.presenterId != presenter) {
      return problemBody(403, 'qr_not_participant');
    }
    if (payload.listingId != _listing ||
        payload.interactionId != _interaction) {
      return problemBody(409, 'qr_not_participant');
    }
    scanned.add((payload.presenterId, document));
    if (payload.issuedAt.isBefore(
          _now.subtract(const Duration(seconds: _onlineTtl)),
        ) ||
        payload.issuedAt.isAfter(
          _now.add(const Duration(seconds: _onlineTtl)),
        )) {
      return problemBody(409, 'qr_expired');
    }
    if (!usedNonces.add(payload.nonce)) {
      return problemBody(409, 'qr_nonce_reused');
    }
    return null;
  }

  Map<String, Object?> _body(RequestOptions options) =>
      jsonDecode(options.data! as String) as Map<String, Object?>;

  Map<String, Object?> _listingJson() => {
    ...listingJson(id: _listing, author: _owner, kind: 'loan'),
    'loan_days': _loanDays,
  };

  Map<String, Object?> _interactionJson() => {
    'id': _interaction,
    'listing_id': _listing,
    'participant_name': 'Boris',
    'participant_id': _borrower,
    'status': status,
    'stage': stage,
    'response_due_at': null,
    'executor': false,
    'meeting': null,
    'return_due_at': returnDueAt?.toIso8601String(),
    'overdue': false,
    'completed_at': completedAt?.toIso8601String(),
    'completion_method': completedAt == null ? null : 'qr',
  };

  Map<String, Object?> _scanJson({
    required bool handover,
    required String presenterId,
    required String scannerId,
  }) => {
    'listing_id': _listing,
    'interaction_id': _interaction,
    'presenter_id': presenterId,
    'scanner_id': scannerId,
    'status': handover ? 'accepted' : 'completed',
    'completed': !handover,
    'completed_at': handover ? null : completedAt?.toIso8601String(),
    'completion_method': handover ? null : 'qr',
    'rating_weight': handover ? null : 1,
    'stage': handover ? 'issued' : null,
    'return_due_at': handover ? returnDueAt?.toIso8601String() : null,
    'nonce': const Uuid().v4(),
    'issued_at': _now.subtract(const Duration(seconds: 1)).toIso8601String(),
    'received_at': _now.toIso8601String(),
    'server_time': _now.toIso8601String(),
  };
}

Future<QrScanDocument> _signed({
  required QrSigningKey key,
  required String presenter,
  required String nonce,
}) => signOnlineQr(
  key: key,
  listingId: _listing,
  interactionId: _interaction,
  presenterId: presenter,
  issuedAt: _now,
  nonce: nonce,
);

/// The failure a refused request throws, as the UI classifies it.
Future<Object> _failureOf(Future<Object?> future) async {
  try {
    await future;
  } on Object catch (error) {
    return ApiFailure.from(error);
  }
  fail('the request was expected to fail');
}

/// Verifies the detached signature of a shipped code with [key].
Future<bool> _verify(QrScanDocument document, QrSigningKey key) async {
  final publicKey = SimplePublicKey(
    tryBase64UrlDecode(key.publicKey)!,
    type: KeyPairType.ed25519,
  );
  return Ed25519().verify(
    tryBase64UrlDecode(document.payload)!,
    signature: Signature(
      tryBase64UrlDecode(document.signature)!,
      publicKey: publicKey,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'two participants publish, book, accept, hand over and return a loan',
    () async {
      final keys = _Keys(
        await _key(List<int>.generate(32, (i) => i + 1), _ownerKey),
        await _key(List<int>.generate(32, (i) => i + 41), _borrowerKey),
      );
      final scenario = _Scenario(keys: keys);
      final owner = ProviderContainer(
        overrides: apiOverrides(adapter: scenario.adapter(_owner)),
      );
      addTearDown(owner.dispose);
      final borrower = ProviderContainer(
        overrides: apiOverrides(adapter: scenario.adapter(_borrower)),
      );
      addTearDown(borrower.dispose);
      final ownerApi = owner.read(campusApiProvider);
      final borrowerApi = borrower.read(campusApiProvider);

      // The owner publishes an item for five days.
      final published = await ownerApi.listings.publishLoan(
        body: const LoanInput(
          title: 'A desk lamp',
          description: 'Lend it for the weekend',
          loanDays: _loanDays,
        ),
        options: loanMutationOptions('create-key'),
      );
      expect(published.loanDays, _loanDays);
      expect(published.kind, 'loan');

      // The borrower books it; the owner accepts.
      final booked = await borrowerApi.listings.reserveGiveaway(
        listingId: _listing,
      );
      expect(booked.status, InteractionStatus.pending);

      final accepted = await ownerApi.listings.transitionInteraction(
        listingId: _listing,
        interactionId: _interaction,
        body: const TransitionInput(status: InteractionStatus.accepted),
        options: loanMutationOptions('accept-key'),
      );
      expect(accepted.status, InteractionStatus.accepted);
      expect(accepted.stage, isNull);

      // The owner shows the handover code; the borrower scans it.
      final handoverCode = await _signed(
        key: keys.owner,
        presenter: _owner,
        nonce: const Uuid().v4(),
      );
      final handed = await borrowerApi.qr.handOverLoan(
        listingId: _listing,
        interactionId: _interaction,
        body: QrScanInput(
          payload: handoverCode.payload,
          signature: handoverCode.signature,
        ),
        options: loanMutationOptions('handover-key'),
      );
      expect(handed.stage, 'issued');
      expect(handed.completed, isFalse);
      expect(handed.returnDueAt, _now.add(const Duration(days: _loanDays)));
      expect(scenario.stage, 'issued');

      // The borrower shows the return code; the owner scans it.
      final returnCode = await _signed(
        key: keys.borrower,
        presenter: _borrower,
        nonce: const Uuid().v4(),
      );
      final returned = await ownerApi.qr.returnLoan(
        listingId: _listing,
        interactionId: _interaction,
        body: QrScanInput(
          payload: returnCode.payload,
          signature: returnCode.signature,
        ),
        options: loanMutationOptions('return-key'),
      );
      expect(returned.status, InteractionStatus.completed);
      expect(returned.completed, isTrue);
      expect(scenario.status, 'completed');

      // Both codes were signed by the device of the showing participant.
      expect(scenario.scanned, hasLength(2));
      expect(await _verify(scenario.scanned[0].$2, keys.owner), isTrue);
      expect(await _verify(scenario.scanned[1].$2, keys.borrower), isTrue);

      // Only the two loan actions were used, each with its own key.
      final mutations = scenario.requests
          .where((request) => request.method == 'POST')
          .where((request) => !request.path.endsWith('/token/refresh'))
          .toList();
      expect(mutations.map((request) => request.uri.path), [
        '/api/v1/listings/loans',
        '/api/v1/listings/$_listing/reservations',
        '/api/v1/listings/$_listing/interactions/$_interaction/transition',
        '/api/v1/listings/$_listing/interactions/$_interaction/qr/handover',
        '/api/v1/listings/$_listing/interactions/$_interaction/qr/return',
      ]);
      expect(
        mutations.map((request) => request.headers['Idempotency-Key']),
        everyElement(isNotEmpty),
      );
      expect(
        scenario.requests.where((request) => request.path.endsWith('/qr')),
        isEmpty,
      );
    },
  );

  test(
    'a return before the handover is refused with its loan reason',
    () async {
      final keys = _Keys(
        await _key(List<int>.generate(32, (i) => i + 1), _ownerKey),
        await _key(List<int>.generate(32, (i) => i + 41), _borrowerKey),
      );
      final scenario = _Scenario(keys: keys)..status = 'accepted';
      final owner = ProviderContainer(
        overrides: apiOverrides(adapter: scenario.adapter(_owner)),
      );
      addTearDown(owner.dispose);
      final api = owner.read(campusApiProvider);

      final returnCode = await _signed(
        key: keys.borrower,
        presenter: _borrower,
        nonce: const Uuid().v4(),
      );
      final error = await _failureOf(
        api.qr.returnLoan(
          listingId: _listing,
          interactionId: _interaction,
          body: QrScanInput(
            payload: returnCode.payload,
            signature: returnCode.signature,
          ),
        ),
      );
      expect(
        error,
        isA<ProblemFailure>().having(
          (failure) => failure.code,
          'code',
          ProblemCode.qrLoanNotHandedOver,
        ),
      );
      expect(scenario.status, 'accepted');
      expect(scenario.stage, isNull);
    },
  );

  test('a repeated handover is refused with its loan reason', () async {
    final keys = _Keys(
      await _key(List<int>.generate(32, (i) => i + 1), _ownerKey),
      await _key(List<int>.generate(32, (i) => i + 41), _borrowerKey),
    );
    final scenario = _Scenario(keys: keys)..status = 'accepted';
    final borrower = ProviderContainer(
      overrides: apiOverrides(adapter: scenario.adapter(_borrower)),
    );
    addTearDown(borrower.dispose);
    final api = borrower.read(campusApiProvider);

    final first = await _signed(
      key: keys.owner,
      presenter: _owner,
      nonce: const Uuid().v4(),
    );
    await api.qr.handOverLoan(
      listingId: _listing,
      interactionId: _interaction,
      body: QrScanInput(payload: first.payload, signature: first.signature),
    );
    expect(scenario.stage, 'issued');

    final second = await _signed(
      key: keys.owner,
      presenter: _owner,
      nonce: const Uuid().v4(),
    );
    final error = await _failureOf(
      api.qr.handOverLoan(
        listingId: _listing,
        interactionId: _interaction,
        body: QrScanInput(payload: second.payload, signature: second.signature),
      ),
    );
    expect(
      error,
      isA<ProblemFailure>().having(
        (failure) => failure.code,
        'code',
        ProblemCode.qrLoanAlreadyIssued,
      ),
    );
  });
}
