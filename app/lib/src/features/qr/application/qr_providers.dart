import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';
import '../data/device_key_manager.dart';
import '../data/device_key_registrar.dart';
import '../data/device_key_store.dart';

/// Storage of the Ed25519 device key, namespaced by the local session.
final deviceKeyStoreProvider = Provider<DeviceKeyStore>(
  (ref) => SecureDeviceKeyStore(
    ref.watch(secureStorageProvider),
    () => ref.read(authStorageProvider).cacheNamespace(),
  ),
);

/// The device signing key registered with the server.
final deviceKeyManagerProvider = Provider<DeviceKeyManager>(
  (ref) => DeviceKeyManager(
    ref.watch(deviceKeyStoreProvider),
    CampusDeviceKeyRegistrar(ref.watch(campusApiProvider).deviceKeys),
  ),
);
