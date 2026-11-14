import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';

part 'device_sessions.g.dart';

@riverpod
Future<List<SessionOutput>> deviceSessions(Ref ref) async {
  final status = ref.watch(authStatusProvider).value;
  if (status != AuthenticationStatus.authenticated) return const [];
  return ref.watch(campusApiProvider).sessions.listSessions();
}

/// Clear local credentials only after the server confirms revocation.
/// A network failure must leave the user able to retry the operation.
@Riverpod(keepAlive: true)
Future<void> Function(SessionOutput?) endDeviceSessions(Ref ref) =>
    (device) async {
      final api = ref.read(campusApiProvider).sessions;
      if (device == null) {
        await api.revokeAllSessions();
      } else {
        await api.revokeSession(sessionId: device.id);
      }
      if (device == null || device.current) {
        await ref.read(authSessionProvider).clearToken();
      }
      ref.invalidate(deviceSessionsProvider);
    };
