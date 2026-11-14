import 'dart:async';

import 'package:campus/src/core/api/network_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

void main() {
  late StreamController<bool> network;

  setUp(() {
    network = StreamController<bool>.broadcast();
    addTearDown(network.close);
  });

  Future<void> setNetwork(
    WidgetTester tester, {
    required bool available,
  }) async {
    network.add(available);
    await tester.pumpAndSettle();
  }

  testWidgets('is shown while the device has no network', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      network: network.stream,
    );
    expect(find.text('Нет подключения к сети'), findsNothing);

    await setNetwork(tester, available: false);
    expect(find.text('Нет подключения к сети'), findsOneWidget);
    // The app stays usable under the strip.
    expect(find.text('Добро пожаловать в Кампус'), findsOneWidget);

    await setNetwork(tester, available: true);
    expect(find.text('Нет подключения к сети'), findsNothing);
  });

  testWidgets('is shown when the server cannot be reached', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final container = await tester.pumpCampusApp(InMemorySettingsRepository());

    container.read(networkStatusProvider.notifier).unreachable();
    await tester.pumpAndSettle();

    expect(find.text("You're offline"), findsOneWidget);
  });
}
