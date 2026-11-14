// Signing in against a running stand: the API with its worker, and
// Mailpit catching the e-mails (README, "Вход", "Интеграционный тест").
//
//   adb reverse tcp:8000 tcp:8000 && adb reverse tcp:8025 tcp:8025
//   flutter test integration_test -d <device> \
//     --dart-define=CAMPUS_API_URL=http://127.0.0.1:8000 \
//     --dart-define=CAMPUS_TEST_MAILPIT_URL=http://127.0.0.1:8025

import 'package:campus/main.dart' as app;
import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_storage.dart';
import 'package:campus/src/core/auth/auth_token.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

const _mailpitUrl = String.fromEnvironment(
  'CAMPUS_TEST_MAILPIT_URL',
  defaultValue: 'http://127.0.0.1:8025',
);

/// A domain of the stand's seed data.
const _domain = String.fromEnvironment(
  'CAMPUS_TEST_EMAIL_DOMAIN',
  defaultValue: 'edu.hse.ru',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final mailpit = Dio(BaseOptions(baseUrl: _mailpitUrl));
  const storage = FlutterSecureStorage();

  /// The code from the latest e-mail to [email], waiting for the worker to
  /// send it.
  Future<String> codeFrom(String email, {Set<String> seen = const {}}) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      final found = await mailpit.get<Map<String, Object?>>(
        '/api/v1/search',
        queryParameters: {'query': 'to:"$email"'},
      );
      final messages = found.data!['messages']! as List<Object?>;
      for (final message in messages.cast<Map<String, Object?>>()) {
        final id = message['ID']! as String;
        if (seen.contains(id)) continue;
        final full = await mailpit.get<Map<String, Object?>>(
          '/api/v1/message/$id',
        );
        final text = full.data!['Text']! as String;
        return RegExp(r'\b\d{6}\b').firstMatch(text)!.group(0)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('No e-mail to $email');
  }

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  testWidgets('a new user signs up, refreshes the session and signs out', (
    tester,
  ) async {
    await storage.deleteAll();
    final email = 'it-${DateTime.now().millisecondsSinceEpoch}@$_domain';

    await app.main();
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );

    // E-mail step.
    final emailField = find.byKey(const Key('sign-in-email'));
    await pumpUntil(tester, emailField);
    await tester.enterText(emailField, email);
    await tester.tap(find.byKey(const Key('sign-in-get-code')));
    final codeField = find.byKey(const Key('sign-in-code'));
    await pumpUntil(tester, codeField);
    final code = await codeFrom(email);

    // A wrong code is explained, without the server's text.
    final wrong = code == '000000' ? '111111' : '000000';
    await tester.enterText(codeField, wrong);
    await pumpUntil(tester, find.byKey(const Key('auth-error')));

    // The right code leads a new user to registration.
    await tester.enterText(codeField, code);
    final firstName = find.byKey(const Key('sign-in-first-name'));
    await pumpUntil(tester, firstName);
    await tester.enterText(firstName, 'Иван');
    await tester.enterText(
      find.byKey(const Key('sign-in-last-name')),
      'Интеграционный',
    );
    await tester.tap(find.byKey(const Key('sign-in-finish')));
    final settings = find.byIcon(Icons.settings_outlined);
    await pumpUntil(tester, settings);
    expect(
      container.read(authStatusProvider).value,
      AuthenticationStatus.authenticated,
    );

    // Only the refresh token is kept, in the secure storage.
    final saved = await storage.readAll();
    final refresh = saved[AuthStorage.refreshTokenKey];
    expect(refresh, isNotNull);
    expect(saved.keys, {AuthStorage.refreshTokenKey, AuthStorage.deviceIdKey});

    // An expired access token is refreshed, which rotates the refresh
    // token.
    final session = container.read(authSessionProvider);
    final expired = AuthToken(accessToken: 'expired', refreshToken: refresh!);
    await session.setToken(expired);
    await session.refreshToken(tokenUsedForRequest: expired);
    final rotated = await storage.read(key: AuthStorage.refreshTokenKey);
    expect(rotated, isNot(refresh));

    // Signing out from settings ends the session on the server too.
    await tester.tap(settings);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-out')));
    await pumpUntil(tester, emailField);

    final deviceId = await storage.read(key: AuthStorage.deviceIdKey);
    await expectLater(
      AuthenticationClient(container.read(authRefreshDioProvider))
          .refreshTokens(
            body: RefreshInput(refreshToken: rotated!, deviceId: deviceId!),
          ),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(
      container.read(authStatusProvider).value,
      AuthenticationStatus.unauthenticated,
    );
    expect(await storage.read(key: AuthStorage.refreshTokenKey), isNull);
    expect(await storage.read(key: AuthStorage.deviceIdKey), deviceId);
  });
}
