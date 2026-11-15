import 'package:campus/src/core/api/api_failure.dart';
import 'package:campus/src/features/qr/data/device_key_manager.dart';
import 'package:campus/src/features/qr/data/device_key_store.dart';
import 'package:campus/src/features/qr/domain/base64url.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

DioException droppedConnection() => DioException.connectionError(
  requestOptions: RequestOptions(path: '/api/v1/me/device-key'),
  reason: 'Connection reset by peer',
);

StoredDeviceKey storedKey({List<int>? seed}) => StoredDeviceKey(
  seed: seed ?? List<int>.generate(32, (index) => index + 1),
  registrationKey: 'registration-1',
);

void main() {
  group('DeviceKeyManager', () {
    test('generates and registers a key on first use', () async {
      final store = InMemoryDeviceKeyStore();
      final registrar = FakeDeviceKeyRegistrar((_) async => qrKeyId);
      final manager = DeviceKeyManager(store, registrar);

      final key = await manager.ensure();

      expect(key.keyId, qrKeyId);
      expect(tryBase64UrlDecode(key.publicKey), hasLength(32));
      expect(store.saved, isNotNull);
      expect(store.saved!.seed, hasLength(32));
      expect(store.saved!.keyId, qrKeyId);
      expect(store.saved!.registrationKey, isNotEmpty);
      expect(registrar.calls.single.publicKey, key.publicKey);
      expect(
        registrar.calls.single.idempotencyKey,
        store.saved!.registrationKey,
      );
      // The private half is never part of the registered request.
      expect(registrar.calls.single.publicKey, isNot(contains('=')));
    });

    test('keeps the stored key and its registration key on a retry', () async {
      final store = InMemoryDeviceKeyStore()..saved = storedKey();
      final registrar = FakeDeviceKeyRegistrar((_) async => qrKeyId);
      final manager = DeviceKeyManager(store, registrar);

      final first = await manager.ensure();
      final second = await manager.ensure();

      expect(second.publicKey, first.publicKey);
      expect(registrar.calls, hasLength(2));
      expect(
        registrar.calls[1].idempotencyKey,
        registrar.calls[0].idempotencyKey,
      );
      expect(store.saved!.seed, storedKey().seed);
    });

    test('repeats a failed registration with the same key', () async {
      final store = InMemoryDeviceKeyStore();
      var attempts = 0;
      final registrar = FakeDeviceKeyRegistrar((_) async {
        if (attempts++ == 0) throw droppedConnection();
        return qrKeyId;
      });
      final manager = DeviceKeyManager(store, registrar);

      await expectLater(manager.ensure(), throwsA(isA<DioException>()));
      expect(
        store.saved!.registrationKey,
        registrar.calls.single.idempotencyKey,
      );

      final key = await manager.ensure();

      expect(key.keyId, qrKeyId);
      expect(registrar.calls, hasLength(2));
      expect(
        registrar.calls[1].idempotencyKey,
        registrar.calls[0].idempotencyKey,
      );
      expect(registrar.calls[1].publicKey, registrar.calls[0].publicKey);
    });

    test('replaces a key that another session already owns', () async {
      final store = InMemoryDeviceKeyStore()..saved = storedKey();
      var attempts = 0;
      final registrar = FakeDeviceKeyRegistrar((_) async {
        if (attempts++ == 0) throw qrProblem(409, 'device_key_conflict');
        return 'key-2';
      });
      final manager = DeviceKeyManager(store, registrar);

      final key = await manager.ensure();

      expect(key.keyId, 'key-2');
      expect(store.saved!.keyId, 'key-2');
      expect(registrar.calls, hasLength(2));
      expect(registrar.calls[1].publicKey, isNot(registrar.calls[0].publicKey));
      expect(
        registrar.calls[1].idempotencyKey,
        isNot(registrar.calls[0].idempotencyKey),
      );
    });

    test('does not retry other server errors', () async {
      final store = InMemoryDeviceKeyStore();
      final registrar = FakeDeviceKeyRegistrar(
        (_) async => throw qrProblem(500, 'internal_error'),
      );
      final manager = DeviceKeyManager(store, registrar);

      await expectLater(
        manager.ensure(),
        throwsA(
          isA<ProblemFailure>().having(
            (error) => error.code.toJson(),
            'code',
            'internal_error',
          ),
        ),
      );
      expect(registrar.calls, hasLength(1));
    });

    test('stores the ID of the registered public key', () async {
      final store = InMemoryDeviceKeyStore()..saved = storedKey();
      final registrar = FakeDeviceKeyRegistrar((_) async => 'key-new');
      final manager = DeviceKeyManager(store, registrar);

      await manager.ensure();

      expect(store.saved!.keyId, 'key-new');
    });
  });
}
