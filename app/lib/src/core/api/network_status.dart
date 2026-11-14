import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_status.g.dart';

/// Changes of the device network: `true` when some network is available.
@Riverpod(keepAlive: true)
Stream<bool> networkAvailability(Ref ref) async* {
  final connectivity = Connectivity();
  // Some platforms only emit changes, not the state at startup.
  yield hasNetwork(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(hasNetwork);
}

/// Whether [results] of connectivity_plus include some network.
bool hasNetwork(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none);

/// Whether the app is online (ТЗ п. 5.1.5: the offline state is shown).
///
/// Offline when the device has no network or the server could not be
/// reached; online again when the network comes back or a request gets
/// any response.
@Riverpod(keepAlive: true)
class NetworkStatus extends _$NetworkStatus {
  @override
  bool build() {
    ref.listen(networkAvailabilityProvider, (_, next) {
      if (next case AsyncData(:final value)) state = value;
    });
    return true;
  }

  /// A request got a response.
  void reachable() => state = true;

  /// A request could not connect to the server.
  void unreachable() => state = false;
}
