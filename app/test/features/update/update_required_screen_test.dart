import 'package:campus/src/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

class _FakeLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final opened = <String>[];
  bool succeed = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return succeed;
  }
}

void main() {
  late FakeHttpAdapter server;
  late _FakeLauncher launcher;

  setUp(() {
    server = FakeHttpAdapter();
    launcher = _FakeLauncher();
    final original = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = original);
  });

  /// Starts the app in [locale] and makes a request the server rejects
  /// as coming from an outdated client.
  Future<void> rejectOutdatedClient(
    WidgetTester tester, {
    String locale = 'en',
    String? minVersion,
  }) async {
    tester.platformDispatcher.localesTestValue = [Locale(locale)];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    server.replyProblem(426, 'client_update_required', minVersion: minVersion);

    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
    );
    await tester.runAsync(
      () => container
          .read(campusApiProvider)
          .university
          .listCities()
          .then<void>((_) {}, onError: (Object _) {}),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an update-required answer opens the update screen', (
    tester,
  ) async {
    await rejectOutdatedClient(tester, minVersion: '1.2.0');

    expect(find.text('Update required'), findsOneWidget);
    expect(find.textContaining('version 1.2.0 or newer'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('is shown in Russian without the minimum version', (
    tester,
  ) async {
    await rejectOutdatedClient(tester, locale: 'ru');

    expect(find.text('Требуется обновление'), findsOneWidget);
    expect(
      find.text(
        'Эта версия приложения больше не поддерживается. Чтобы продолжить, '
        'установите новую версию.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cannot be left', (tester) async {
    await rejectOutdatedClient(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('opens the download page', (tester) async {
    await rejectOutdatedClient(tester);

    await tester.tap(find.text('Download update'));
    await tester.pumpAndSettle();

    expect(launcher.opened, [testApiConfig.downloadUrl.toString()]);
  });

  testWidgets('tells when the download page cannot be opened', (tester) async {
    launcher.succeed = false;
    await rejectOutdatedClient(tester);

    await tester.tap(find.text('Download update'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't open the download page."), findsOneWidget);
  });
}
