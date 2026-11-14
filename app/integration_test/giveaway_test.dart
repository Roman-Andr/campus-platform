// Real API acceptance. Run via backend/tests/test_giveaway_client.py, which
// provisions two independent accounts and a disposable PostgreSQL/Redis stand.
import 'package:campus/src/app.dart';
import 'package:campus/src/core/api/client_info.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_storage.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/settings/application/settings_controller.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  testWidgets('two users publish, reserve and accept a giveaway', (
    tester,
  ) async {
    var ownerRefresh = const String.fromEnvironment(
      'CAMPUS_TEST_OWNER_REFRESH',
    );
    const borrowerRefresh = String.fromEnvironment(
      'CAMPUS_TEST_BORROWER_REFRESH',
    );
    expect(ownerRefresh, isNotEmpty);
    ProviderContainer? container;

    Future<void> until(Finder finder) async {
      for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    Future<void> start(String refresh) async {
      await tester.pumpWidget(const SizedBox());
      container?.dispose();
      await storage.deleteAll();
      await storage.write(
        key: AuthStorage.deviceIdKey,
        value: const String.fromEnvironment('CAMPUS_TEST_DEVICE'),
      );
      await storage.write(key: AuthStorage.refreshTokenKey, value: refresh);
      final package = await PackageInfo.fromPlatform();
      final next = ProviderContainer(
        overrides: [
          clientInfoProvider.overrideWithValue(ClientInfo.current(package)),
        ],
      );
      container = next;
      await next.read(settingsControllerProvider.future);
      await next
          .read(settingsControllerProvider.notifier)
          .setLanguage(AppLanguage.english);
      await next.read(authStatusProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: next, child: const CampusApp()),
      );
      await until(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
    }

    try {
      await start(ownerRefresh);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('listing-title')),
        'Integration desk',
      );
      await tester.enterText(
        find.byKey(const Key('listing-description')),
        'Collect on campus',
      );
      await tester.tap(find.text('Publish'));
      await until(find.text('Integration desk'));
      ownerRefresh = (await storage.read(key: AuthStorage.refreshTokenKey))!;

      await start(borrowerRefresh);
      await until(find.text('Integration desk'));
      await tester.tap(find.text('Integration desk'));
      await tester.pumpAndSettle();
      await until(find.text('Reserve'));
      await tester.tap(find.text('Reserve'));
      await until(find.text('My listings and reservations'));
      await tester.tap(find.text('My reservations'));
      await tester.pumpAndSettle();
      await until(find.text('Pending'));
      final borrowerRotated = (await storage.read(
        key: AuthStorage.refreshTokenKey,
      ))!;

      await start(ownerRefresh);
      await until(find.text('Integration desk'));
      await tester.tap(find.text('Integration desk'));
      await tester.pumpAndSettle();
      await until(find.text('Accept'));
      await tester.tap(find.text('Accept'));
      await until(find.text('Accepted'));

      await start(borrowerRotated);
      container!.read(appRouterProvider).go('/my-listings');
      await tester.pumpAndSettle();
      await tester.tap(find.text('My reservations'));
      await tester.pumpAndSettle();
      await until(find.text('Accepted'));
      expect(find.text('Integration desk'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container?.dispose();
      await storage.deleteAll();
    }
  });
}
