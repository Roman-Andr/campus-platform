// Real API acceptance. Run via backend/tests/test_help_client.py, which
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
  testWidgets('three users apply, select, refuse and select again', (
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

    Future<void> openRequest() async {
      await until(find.text('Integration help'));
      await tester.tap(find.text('Integration help'));
      await tester.pumpAndSettle();
    }

    Future<void> respond() async {
      await until(find.byKey(const Key('help-respond')));
      await tester.tap(find.byKey(const Key('help-respond')));
      await tester.pumpAndSettle();
      await until(find.text('Your response is waiting for the author.'));
    }

    Future<void> select(String name) async {
      await until(find.text(name));
      final column = find
          .ancestor(of: find.text(name), matching: find.byType(Column))
          .first;
      final button = find.descendant(
        of: column,
        matching: find.text('Choose executor'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await until(find.text('Executor'));
    }

    try {
      var ownerRefresh = await start(ownerRefresh0);
      await tester.tap(find.byKey(const Key('feed-create-help')));
      await tester.pumpAndSettle();
      await until(find.byKey(const Key('help-category')));
      await tester.tap(find.byKey(const Key('help-category')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownMenuItem<String>).hitTestable().first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('help-title')),
        'Integration help',
      );
      await tester.enterText(
        find.byKey(const Key('help-description')),
        'Two floors, no elevator.',
      );
      await tester.ensureVisible(find.byKey(const Key('help-publish')));
      await tester.tap(find.byKey(const Key('help-publish')));
      await until(find.text('Integration help'));
      ownerRefresh = await savedToken();

      var firstRefresh = await start(firstRefresh0);
      await openRequest();
      await respond();
      firstRefresh = await savedToken();

      var secondRefresh = await start(secondRefresh0);
      await openRequest();
      await respond();
      secondRefresh = await savedToken();

      ownerRefresh = await start(ownerRefresh);
      await openRequest();
      await select('Dana Doe');
      ownerRefresh = await savedToken();

      firstRefresh = await start(firstRefresh);
      await openRequest();
      await until(find.text('Cancel request or reservation'));
      await tester.tap(find.text('Cancel request or reservation'));
      await tester.pumpAndSettle();
      await until(find.text('Cancelled'));
      firstRefresh = await savedToken();

      ownerRefresh = await start(ownerRefresh);
      await openRequest();
      await select('Egor Petrov');
      ownerRefresh = await savedToken();

      secondRefresh = await start(secondRefresh);
      await openRequest();
      await until(find.text('You are the executor.'));
      expect(find.text('You are the executor.'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container?.dispose();
      await storage.deleteAll();
    }
  });
}
