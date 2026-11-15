import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../domain/base64url.dart';
import '../domain/qr_signing.dart';
import 'device_key_store.dart';

/// Registers the public half of a device key and returns its server ID.
abstract interface class DeviceKeyRegistrar {
  Future<String> register({
    required String publicKey,
    required String idempotencyKey,
  });
}

/// Owns the Ed25519 key of this installation.
///
/// The private half is generated once on the device, kept in the secure
/// storage ([DeviceKeyStore]) and never sent to the server. Only the public
/// key is registered. The server revokes the previous key of a device when a
/// different one is registered, so replacing the key after a reinstall or a
/// sign-in keeps old installations from showing accepted codes (ТЗ п. 5.1.1,
/// модуль 5, пункт 1).
class DeviceKeyManager {
  DeviceKeyManager(
    this._store,
    this._registrar, {
    Ed25519? algorithm,
    String Function()? newRegistrationKey,
  }) : _algorithm = algorithm ?? Ed25519(),
       _newRegistrationKey = newRegistrationKey ?? const Uuid().v7;

  final DeviceKeyStore _store;
  final DeviceKeyRegistrar _registrar;
  final Ed25519 _algorithm;
  final String Function() _newRegistrationKey;

  /// Returns the stored key registered with the current server session.
  ///
  /// A key that was formed for another session of this installation cannot be
  /// registered again (the server reports a conflict), so a fresh key pair is
  /// generated and registered instead; its registration revokes the previous
  /// one. A failed request keeps the stored material and its
  /// `Idempotency-Key`, so repeating [ensure] repeats the same request.
  Future<QrSigningKey> ensure() async {
    final saved = await _store.read();
    var stored = saved ?? await _generate();
    if (stored.registrationKey == null) {
      stored = stored.copyWith(registrationKey: _newRegistrationKey());
      await _store.write(stored);
    }
    for (var attempt = 0; ; attempt++) {
      final keyPair = await _algorithm.newKeyPairFromSeed(stored.seed);
      final publicKey = base64UrlNoPadding(
        (await keyPair.extractPublicKey()).bytes,
      );
      try {
        final keyId = await _registrar.register(
          publicKey: publicKey,
          idempotencyKey: stored.registrationKey!,
        );
        if (stored.keyId != keyId) {
          stored = stored.copyWith(keyId: keyId);
          await _store.write(stored);
        }
        return QrSigningKey(
          keyPair: keyPair,
          keyId: keyId,
          publicKey: publicKey,
        );
      } on Object catch (error) {
        if (attempt > 0 || !isDeviceKeyConflict(error)) rethrow;
        stored = await _generate();
      }
    }
  }

  Future<StoredDeviceKey> _generate() async {
    final keyPair = await _algorithm.newKeyPair();
    final stored = StoredDeviceKey(
      seed: await keyPair.extractPrivateKeyBytes(),
      registrationKey: _newRegistrationKey(),
    );
    await _store.write(stored);
    return stored;
  }
}

/// Whether the server refused the key because it belongs to another session.
bool isDeviceKeyConflict(Object error) => switch (ApiFailure.from(error)) {
  ProblemFailure(
    code: ProblemCodeKnown(value: ProblemCodeValue.deviceKeyConflict),
  ) =>
    true,
  _ => false,
};
