import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'client_update.g.dart';

/// The server no longer supports this version of the app.
class ClientUpdate {
  const ClientUpdate({this.minVersion});

  /// Oldest supported version, when the server reported it.
  final String? minVersion;
}

/// Set once a request is answered with `client_update_required`; the app
/// then shows only the update screen.
@Riverpod(keepAlive: true)
class ClientUpdateRequired extends _$ClientUpdateRequired {
  @override
  ClientUpdate? build() => null;

  void require(String? minVersion) =>
      state = ClientUpdate(minVersion: minVersion);
}
