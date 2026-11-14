import 'dart:async';

import 'package:campus/src/core/api/network_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  late StreamController<bool> network;
  late ProviderContainer container;

  setUp(() {
    network = StreamController<bool>.broadcast();
    addTearDown(network.close);
    container = ProviderContainer(
      overrides: apiOverrides(network: network.stream),
    );
    addTearDown(container.dispose);
  });

  bool online() => container.read(networkStatusProvider);

  test('is online until something says otherwise', () {
    expect(online(), isTrue);
  });

  test('follows the device network', () async {
    container.listen(networkStatusProvider, (_, _) {});

    network.add(false);
    await pumpEventQueue();
    expect(online(), isFalse);

    network.add(true);
    await pumpEventQueue();
    expect(online(), isTrue);
  });

  test('follows the reachability of the server', () {
    final status = container.read(networkStatusProvider.notifier);

    status.unreachable();
    expect(online(), isFalse);

    status.reachable();
    expect(online(), isTrue);
  });

  test('any connection but none counts as a network', () {
    expect(hasNetwork([ConnectivityResult.none]), isFalse);
    expect(hasNetwork([]), isFalse);
    expect(hasNetwork([ConnectivityResult.wifi]), isTrue);
    expect(
      hasNetwork([ConnectivityResult.vpn, ConnectivityResult.mobile]),
      isTrue,
    );
  });
}
