// Real API acceptance. Run via backend/tests/test_purchase_client.py, which
// provisions two independent accounts and a disposable PostgreSQL/Redis
// stand.
import 'package:campus/src/app.dart';
import 'package:campus/src/core/api/client_info.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_storage.dart';
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
  testWidgets('two users collect and change a purchase share', (tester) async {
    var ownerRefresh = const String.fromEnvironment(
      'CAMPUS_TEST_OWNER_REFRESH',
    );
    const participantRefresh = String.fromEnvironment(
      'CAMPUS_TEST_PARTICIPANT_REFRESH',
    );
    expect(ownerRefresh, isNotEmpty);
    ProviderContainer? container;

    Future<void> until(Finder finder) async {
      for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    Future<void> scrollTo(Finder finder) async {
      await tester.dragUntilVisible(
        finder,
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
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
      var create = find.byKey(const Key('feed-create-purchase'));
      if (create.evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('home-menu')));
        await tester.pumpAndSettle();
        create = find.byKey(const Key('home-create-purchase'));
      }
      await tester.tap(create);
      await tester.pumpAndSettle();
      await until(find.byKey(const Key('purchase-category')));
      await tester.tap(find.byKey(const Key('purchase-category')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownMenuItem<String>).hitTestable().first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('purchase-title')),
        'Integration rice',
      );
      await tester.enterText(
        find.byKey(const Key('purchase-description')),
        'Bulk order from the market',
      );
      await scrollTo(find.byKey(const Key('purchase-price')));
      await tester.enterText(find.byKey(const Key('purchase-price')), '12.50');
      await scrollTo(find.byKey(const Key('purchase-min-units')));
      await tester.enterText(find.byKey(const Key('purchase-min-units')), '2');
      await scrollTo(find.byKey(const Key('purchase-max-units')));
      await tester.enterText(find.byKey(const Key('purchase-max-units')), '10');
      await scrollTo(find.byKey(const Key('purchase-submit')));
      await tester.tap(find.byKey(const Key('purchase-submit')));
      await until(find.text('Integration rice'));
      ownerRefresh = (await storage.read(key: AuthStorage.refreshTokenKey))!;

      await start(participantRefresh);
      await until(find.text('Integration rice'));
      await tester.tap(find.text('Integration rice'));
      await tester.pumpAndSettle();
      await until(find.byKey(const Key('purchase-summary')));
      await scrollTo(find.byKey(const Key('purchase-share-units')));
      await tester.enterText(
        find.byKey(const Key('purchase-share-units')),
        '2',
      );
      await scrollTo(find.byKey(const Key('purchase-share-join')));
      await tester.tap(find.byKey(const Key('purchase-share-join')));
      await tester.pumpAndSettle();
      await scrollTo(find.byKey(const Key('purchase-share-amount')));
      expect(find.text('Share: 2 units'), findsOneWidget);
      expect(find.text('Amount: ₽25.00'), findsOneWidget);

      await scrollTo(find.byKey(const Key('purchase-share-units')));
      await tester.enterText(
        find.byKey(const Key('purchase-share-units')),
        '3',
      );
      await scrollTo(find.byKey(const Key('purchase-share-change')));
      await tester.tap(find.byKey(const Key('purchase-share-change')));
      await until(find.text('Share: 3 units'));
      expect(find.text('Amount: ₽37.50'), findsOneWidget);
      expect(find.text('New amount: ₽37.50'), findsOneWidget);

      await start(ownerRefresh);
      await until(find.text('Integration rice'));
      await tester.tap(find.text('Integration rice'));
      await tester.pumpAndSettle();
      await until(find.byKey(const Key('purchase-summary')));
      await scrollTo(find.byKey(const Key('purchase-composition-total')));
      expect(find.text('Total: 3 units, ₽37.50'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container?.dispose();
      await storage.deleteAll();
    }
  });
}
