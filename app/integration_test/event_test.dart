// Real API acceptance. Run via backend/tests/test_event_client.py, which
// provisions three independent accounts and a disposable PostgreSQL/Redis
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
  testWidgets('one seat fills up and the next user queues', (tester) async {
    const ownerRefresh = String.fromEnvironment('CAMPUS_TEST_OWNER_REFRESH');
    const participantRefresh = String.fromEnvironment(
      'CAMPUS_TEST_PARTICIPANT_REFRESH',
    );
    const queuedRefresh = String.fromEnvironment('CAMPUS_TEST_QUEUED_REFRESH');
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
      await tester.tap(find.byKey(const Key('feed-create-event')));
      await tester.pumpAndSettle();
      await until(find.byKey(const Key('event-category')));
      await tester.tap(find.byKey(const Key('event-category')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownMenuItem<String>).hitTestable().first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('event-title')),
        'Integration concert',
      );
      await tester.enterText(
        find.byKey(const Key('event-description')),
        'Meet in the hall',
      );
      await tester.ensureVisible(find.byKey(const Key('event-location')));
      await tester.enterText(find.byKey(const Key('event-location')), 'Hall A');
      await tester.enterText(find.byKey(const Key('event-capacity')), '1');
      await tester.ensureVisible(find.byKey(const Key('event-submit')));
      await tester.tap(find.byKey(const Key('event-submit')));
      await until(find.text('Integration concert'));

      await start(participantRefresh);
      await until(find.text('Integration concert'));
      await tester.tap(find.text('Integration concert'));
      await tester.pumpAndSettle();
      await until(find.text('Sign up'));
      await tester.tap(find.text('Sign up'));
      await until(find.text('You are registered'));

      await start(queuedRefresh);
      await until(find.text('Integration concert'));
      await tester.tap(find.text('Integration concert'));
      await tester.pumpAndSettle();
      await until(find.text('No seats left'));
      await tester.tap(find.text('Join the queue'));
      await until(find.text('You are in the queue'));
    } finally {
      container?.dispose();
    }
  });
}
