import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

Map<String, Object?> device(String id, {bool current = false}) => {
  'id': id,
  'device_name': id == 'phone' ? 'My phone' : null,
  'platform': id == 'phone' ? 'android' : 'web',
  'signed_in_at': '2026-11-14T10:00:00Z',
  'last_active_at': '2026-11-14T11:00:00Z',
  'current': current,
};

void main() {
  late FakeHttpAdapter server;
  late List<Map<String, Object?>> sessions;
  late bool failDelete;
  late bool failList;

  setUp(() {
    sessions = [device('phone', current: true), device('browser')];
    failDelete = false;
    failList = false;
    server = FakeHttpAdapter();
    server.route((options) {
      if (options.path == '/api/v1/auth/token/refresh') {
        return jsonBody(200, tokensJson(1));
      }
      if (options.method == 'DELETE') {
        if (failDelete) return problemBody(503, 'internal_error');
        sessions.removeWhere((d) => options.path.endsWith('/${d['id']}'));
        return jsonBody(204, null);
      }
      if (failList) return problemBody(503, 'internal_error');
      return jsonBody(200, sessions);
    });
  });

  Future<void> open(WidgetTester tester, {bool russian = false}) async {
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(
        AppSettings(
          language: russian ? AppLanguage.russian : AppLanguage.english,
        ),
      ),
      adapter: server,
    );
    container.read(appRouterProvider).go(AppRoutes.devices);
    await tester.pumpAndSettle();
  }

  Finder signOut(String id) => find.descendant(
    of: find.byKey(ValueKey(id)),
    matching: find.byType(IconButton),
  );

  testWidgets('settings links to consents and devices', (tester) async {
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(
        const AppSettings(language: AppLanguage.english),
      ),
      adapter: server,
    );
    container.read(appRouterProvider).go(AppRoutes.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('consents')), 200);
    await tester.tap(find.byKey(const Key('consents')));
    await tester.pumpAndSettle();
    expect(find.text('Consents and documents'), findsWidgets);
    container.read(appRouterProvider).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('devices')), 200);
    await tester.tap(find.byKey(const Key('devices')));
    await tester.pumpAndSettle();
    expect(find.text('My phone'), findsOneWidget);
  });

  testWidgets('inventory shows platform, current marker and dates', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('My phone'), findsOneWidget);
    expect(find.text('Unnamed device'), findsOneWidget);
    expect(find.textContaining('This device'), findsOneWidget);
    expect(find.textContaining('Android'), findsOneWidget);
    expect(find.textContaining('Web browser'), findsOneWidget);
    expect(find.textContaining('Signed in:'), findsNWidgets(2));
    expect(find.textContaining('Last active:'), findsNWidgets(2));
  });

  testWidgets('cancel leaves the device signed in, confirm removes it', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(signOut('browser'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of Unnamed device?'), findsOneWidget);
    expect(server.sent.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('browser')), findsOneWidget);
    await tester.tap(signOut('browser'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-revoke')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('browser')), findsNothing);
    expect(find.text('My phone'), findsOneWidget);
    final sent = server.sent.singleWhere((r) => r.method == 'DELETE');
    expect(sent.path, '/api/v1/me/sessions/browser');
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
  });

  for (final all in [true, false]) {
    testWidgets('confirmed ${all ? 'all' : 'current'} sign-out opens sign-in', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(
        all ? find.byKey(const Key('revoke-all')) : signOut('phone'),
      );
      await tester.pumpAndSettle();
      if (all) {
        expect(
          find.text('Sign out of all devices, including this one?'),
          findsOneWidget,
        );
      }
      expect(server.sent.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.tap(find.byKey(const Key('confirm-revoke')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-in-email')), findsOneWidget);
      expect(
        server.sent.singleWhere((r) => r.method == 'DELETE').path,
        all ? '/api/v1/me/sessions' : '/api/v1/me/sessions/phone',
      );
    });
  }

  testWidgets('failed revocation preserves session and allows retry', (
    tester,
  ) async {
    failDelete = true;
    await open(tester);
    await tester.tap(find.byKey(const Key('revoke-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-revoke')));
    await tester.pumpAndSettle();
    expect(find.text('My phone'), findsOneWidget);
    expect(find.byKey(const Key('revoke-all')), findsOneWidget);
    expect(find.byKey(const Key('sign-in-email')), findsNothing);
  });

  testWidgets('Russian device and confirmation texts', (tester) async {
    await open(tester, russian: true);
    expect(find.text('Устройства'), findsOneWidget);
    expect(find.textContaining('Текущее устройство'), findsOneWidget);
    await tester.tap(find.byKey(const Key('revoke-all')));
    await tester.pumpAndSettle();
    expect(
      find.text('Выйти со всех устройств, включая текущее?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(server.sent.where((r) => r.method == 'DELETE'), isEmpty);
  });

  testWidgets('loading error can be retried', (tester) async {
    failList = true;
    await open(tester);
    expect(find.byKey(const Key('revoke-all')), findsNothing);
    failList = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('My phone'), findsOneWidget);
  });
}
