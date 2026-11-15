// Real API acceptance. Run via backend/tests/test_exchange_client.py, which
// provisions three independent accounts and a disposable PostgreSQL stand.
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
  testWidgets('three users publish, offer and choose an exchange', (
    tester,
  ) async {
    const ownerRefresh0 = String.fromEnvironment('CAMPUS_TEST_OWNER_REFRESH');
    const firstRefresh0 = String.fromEnvironment('CAMPUS_TEST_FIRST_REFRESH');
    const secondRefresh0 = String.fromEnvironment('CAMPUS_TEST_SECOND_REFRESH');
    expect(ownerRefresh0, isNotEmpty);
    expect(firstRefresh0, isNotEmpty);
    expect(secondRefresh0, isNotEmpty);
    ProviderContainer? container;

    Future<void> until(Finder finder) async {
      for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    Future<String> savedToken() async =>
        (await storage.read(key: AuthStorage.refreshTokenKey))!;

    Future<String> start(String refresh) async {
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
      return savedToken();
    }

    Future<void> openListing() async {
      await until(find.text('Integration exchange'));
      await tester.tap(find.text('Integration exchange'));
      await tester.pumpAndSettle();
    }

    /// A phone may not fit the exchange action in the app bar, so the create
    /// form is opened from the overflow menu there.
    Future<void> openExchangeForm() async {
      final direct = find.byKey(const Key('feed-create-exchange'));
      if (direct.evaluate().isNotEmpty) {
        await tester.tap(direct);
      } else {
        await tester.tap(find.byKey(const Key('home-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('home-create-exchange')));
      }
      await tester.pumpAndSettle();
    }

    Future<void> offer(String description) async {
      await until(find.byKey(const Key('exchange-offer-description')));
      await tester.enterText(
        find.byKey(const Key('exchange-offer-description')),
        description,
      );
      await tester.tap(find.byKey(const Key('exchange-offer-send')));
      await tester.pumpAndSettle();
      await until(find.text('Your offer: $description'));
    }

    try {
      var ownerRefresh = await start(ownerRefresh0);
      await openExchangeForm();
      expect(find.text('New exchange listing'), findsOneWidget);
      await until(find.byKey(const Key('listing-category')));
      await tester.tap(find.byKey(const Key('listing-category')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownMenuItem<String>).hitTestable().first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('listing-title')),
        'Integration exchange',
      );
      await tester.enterText(
        find.byKey(const Key('listing-description')),
        'I want to swap it for a chair',
      );
      await tester.ensureVisible(find.text('Publish'));
      await tester.tap(find.text('Publish'));
      await until(find.text('Integration exchange'));
      ownerRefresh = await savedToken();

      var firstRefresh = await start(firstRefresh0);
      await openListing();
      await offer('A wooden chair');
      firstRefresh = await savedToken();

      var secondRefresh = await start(secondRefresh0);
      await openListing();
      await offer('A floor lamp');
      secondRefresh = await savedToken();

      ownerRefresh = await start(ownerRefresh);
      await openListing();
      await until(find.text('Offers: A wooden chair'));
      await until(find.text('Offers: A floor lamp'));
      final card = find
          .ancestor(
            of: find.text('Offers: A wooden chair'),
            matching: find.byType(Card),
          )
          .first;
      final choose = find.descendant(of: card, matching: find.text('Choose'));
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      await until(find.text('Accepted'));
      ownerRefresh = await savedToken();

      firstRefresh = await start(firstRefresh);
      await openListing();
      await until(find.text('Accepted'));
      expect(find.textContaining('Hold ends in'), findsOneWidget);
      expect(find.text('Schedule a meeting to keep the hold.'), findsOneWidget);
      firstRefresh = await savedToken();

      secondRefresh = await start(secondRefresh);
      await openListing();
      await until(find.text('Rejected'));
      expect(find.text('The author chose another offer.'), findsOneWidget);
      secondRefresh = await savedToken();
      expect(secondRefresh, isNotEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container?.dispose();
      await storage.deleteAll();
    }
  });
}
