import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:uuid/uuid.dart';

import 'auth_token.dart';

/// Keeps the refresh token and the device ID in the secure storage of the
/// platform (ТЗ п. 5.5.4): on Android they are encrypted with a key held by
/// Android Keystore, on desktop — in the system secret store.
///
/// The access token lives only in memory: it expires in minutes and is
/// refreshed after a restart.
class AuthStorage implements TokenStorage<AuthToken> {
  AuthStorage(this._storage, {String Function()? newDeviceId})
    : _newDeviceId = newDeviceId ?? const Uuid().v7;

  static const refreshTokenKey = 'auth.refresh_token';
  static const deviceIdKey = 'auth.device_id';

  final FlutterSecureStorage _storage;
  final String Function() _newDeviceId;
  Future<String>? _deviceId;

  @override
  Future<AuthToken?> read() async {
    final refresh = await _storage.read(key: refreshTokenKey);
    return refresh == null ? null : AuthToken.restored(refresh);
  }

  @override
  Future<void> write(AuthToken token) =>
      _storage.write(key: refreshTokenKey, value: token.refresh);

  @override
  Future<void> delete() => _storage.delete(key: refreshTokenKey);

  /// Identifier of this installation that the server binds sessions to.
  ///
  /// Created once and kept after sign-out, so signing in again on the same
  /// device replaces the previous session instead of adding one.
  Future<String> deviceId() =>
      _deviceId ??= _loadDeviceId().catchError((Object error) {
        _deviceId = null; // Read again next time.
        throw error;
      });

  Future<String> _loadDeviceId() async {
    final saved = await _storage.read(key: deviceIdKey);
    if (saved != null) return saved;
    final created = _newDeviceId();
    await _storage.write(key: deviceIdKey, value: created);
    return created;
  }
}
