import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/interceptors.dart';
import 'device_key_manager.dart';

/// Registers public keys of this device through the generated client.
class CampusDeviceKeyRegistrar implements DeviceKeyRegistrar {
  CampusDeviceKeyRegistrar(this._client);

  final DeviceKeysClient _client;

  @override
  Future<String> register({
    required String publicKey,
    required String idempotencyKey,
  }) async {
    final output = await _client.registerKey(
      body: DeviceKeyInput(publicKey: publicKey),
      options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
    );
    return output.id;
  }
}
