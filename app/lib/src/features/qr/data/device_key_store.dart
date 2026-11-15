import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/base64url.dart';

/// The locally kept half of the device signing key.
class StoredDeviceKey {
  const StoredDeviceKey({required this.seed, this.keyId, this.registrationKey});

  /// The 32-byte Ed25519 seed the key pair is derived from.
  final List<int> seed;

  /// Server ID of the registered public key; null until the first successful
  /// registration.
  final String? keyId;

  /// `Idempotency-Key` of the registration request, kept so a retry after a
  /// lost response repeats the same operation.
  final String? registrationKey;

  StoredDeviceKey copyWith({
    List<int>? seed,
    String? keyId,
    String? registrationKey,
  }) => StoredDeviceKey(
    seed: seed ?? this.seed,
    keyId: keyId ?? this.keyId,
    registrationKey: registrationKey ?? this.registrationKey,
  );
}

/// Storage of the device signing key.
abstract interface class DeviceKeyStore {
  Future<StoredDeviceKey?> read();
  Future<void> write(StoredDeviceKey key);
}

/// Keeps the Ed25519 seed in the platform secure storage.
///
/// On Android (`flutter_secure_storage`) the value is encrypted with AES-GCM
/// under a key that is itself wrapped by an RSA key held by Android Keystore,
/// so the private half never leaves hardware protection in clear (ТЗ
/// п. 5.5.4). [scope] namespaces the key by the local session: signing out
/// drops the namespace, so the next sign-in starts a new namespace and
/// generates a new key instead of reusing the previous account's key.
class SecureDeviceKeyStore implements DeviceKeyStore {
  SecureDeviceKeyStore(this._storage, this._scope);

  static const _prefix = 'qr.device_key';

  final FlutterSecureStorage _storage;
  final Future<String> Function() _scope;

  Future<String> _name(String part) async => '$_prefix.${await _scope()}.$part';

  @override
  Future<StoredDeviceKey?> read() async {
    final encodedSeed = await _storage.read(key: await _name('seed'));
    if (encodedSeed == null) return null;
    final seed = tryBase64UrlDecode(encodedSeed);
    if (seed == null || seed.length != 32) return null;
    return StoredDeviceKey(
      seed: seed,
      keyId: await _storage.read(key: await _name('key_id')),
      registrationKey: await _storage.read(key: await _name('registration')),
    );
  }

  @override
  Future<void> write(StoredDeviceKey key) async {
    await _storage.write(
      key: await _name('seed'),
      value: base64UrlNoPadding(key.seed),
    );
    final keyId = key.keyId;
    if (keyId == null) {
      await _storage.delete(key: await _name('key_id'));
    } else {
      await _storage.write(key: await _name('key_id'), value: keyId);
    }
    final registrationKey = key.registrationKey;
    if (registrationKey == null) {
      await _storage.delete(key: await _name('registration'));
    } else {
      await _storage.write(
        key: await _name('registration'),
        value: registrationKey,
      );
    }
  }
}
