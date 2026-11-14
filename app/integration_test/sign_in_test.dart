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
import 'package:campus/src/features/consents/application/consents.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/helpers/sign_in_code.dart';

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

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    String Function()? diagnostic,
  }) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets, reason: diagnostic?.call());
  }

  testWidgets(
    'a new user signs up, fills in the profile, refreshes the session '
    'and signs out',
    (tester) async {
      await storage.deleteAll();
      final email = 'it-${DateTime.now().millisecondsSinceEpoch}@$_domain';

      await app.main();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );

      // Record only outcomes: never log addresses, codes or tokens.
      final signInOutcomes = <(int?, String?)>[];
      void record(Response<Object?> response) {
        final problem = switch (response.data) {
          {'code': final String code} => code,
          _ => null,
        };
        signInOutcomes.add((response.statusCode, problem));
        debugPrint('Sign-in outcome: ${signInOutcomes.last}');
      }

      final dio = container.read(apiDioProvider);
      final observer = InterceptorsWrapper(
        onResponse: (response, handler) {
          if (response.requestOptions.path == '/api/v1/auth/sign-in') {
            record(response);
          }
          handler.next(response);
        },
        onError: (error, handler) {
          if (error.requestOptions.path == '/api/v1/auth/sign-in') {
            final response = error.response;
            if (response != null) {
              record(response);
            } else {
              signInOutcomes.add((null, null));
            }
          }
          handler.next(error);
        },
      );
      dio.interceptors.add(observer);
      addTearDown(() => dio.interceptors.remove(observer));

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
      await enterSignInCode(tester, wrong);
      await pumpUntil(tester, find.byKey(const Key('auth-error')));
      expect(signInOutcomes, [(401, 'sign_in_code_invalid')]);

      // The right code leads a new user to registration.
      await enterSignInCode(tester, code);
      final firstName = find.byKey(const Key('sign-in-first-name'));
      await pumpUntil(
        tester,
        firstName,
        diagnostic: () => 'Sign-in outcomes: $signInOutcomes',
      );
      expect(signInOutcomes, [
        (401, 'sign_in_code_invalid'),
        (422, 'registration_required'),
      ]);
      await tester.enterText(firstName, 'Иван');
      await tester.enterText(
        find.byKey(const Key('sign-in-last-name')),
        'Интеграционный',
      );
      // The real IME can still be resizing the viewport after text entry.
      FocusManager.instance.primaryFocus?.unfocus();
      for (var i = 0; i < 100 && tester.view.viewInsets.bottom > 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.view.viewInsets.bottom,
        0,
        reason: 'The IME must be hidden',
      );
      await container.read(documentsProvider.future);
      await tester.pumpAndSettle();
      // Text fields also contain Scrollables; target the page's list.
      final pageScroll = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      final requiredConsent = find.byKey(const Key('consent-required'));
      await tester.scrollUntilVisible(
        requiredConsent.hitTestable(),
        200,
        scrollable: pageScroll,
      );
      await tester.tap(requiredConsent);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(requiredConsent).value, isTrue);
      final finish = find.byKey(const Key('sign-in-finish'));
      await tester.scrollUntilVisible(finish, 200, scrollable: pageScroll);
      await tester.tap(finish);

      // A new user fills in the profile from the stand's reference data.
      Future<void> chooseLast<T>(Finder field) async {
        final dropdown = find.descendant(
          of: field,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DropdownButton<T> &&
                widget.onChanged != null &&
                widget.items?.isNotEmpty == true,
          ),
          matchRoot: true,
        );
        await pumpUntil(tester, dropdown);
        final value = tester
            .widget<DropdownButton<T>>(dropdown)
            .items!
            .last
            .value;
        await tester.ensureVisible(dropdown);
        await tester.pumpAndSettle();
        await pumpUntil(tester, dropdown.hitTestable());
        await tester.tap(dropdown);
        await tester.pumpAndSettle();

        // The field also builds copies of its items under IgnorePointer.
        // Only the popup's item is outside the profile form.
        final item = find.byElementPredicate((element) {
          final widget = element.widget;
          return widget is DropdownMenuItem<T> &&
              widget.value == value &&
              element.findAncestorWidgetOfExactType<Form>() == null;
        });
        await pumpUntil(tester, item);
        final button = find.ancestor(of: item, matching: find.byType(InkWell));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await pumpUntil(tester, button.hitTestable());
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.widget<DropdownButton<T>>(dropdown).value, value);
      }

      Finder byKeyPrefix(String prefix) => find.byWidgetPredicate(
        (widget) => switch (widget.key) {
          ValueKey<String>(:final value) => value.startsWith(prefix),
          _ => false,
        },
      );

      await chooseLast<String>(find.byKey(const Key('profile-city')));
      await chooseLast<String>(byKeyPrefix('profile-dormitory-'));
      await chooseLast<String>(byKeyPrefix('profile-faculty-'));
      await chooseLast<int>(find.byKey(const Key('profile-course')));
      await tester.tap(find.byKey(const Key('profile-save')));
      // The photo and skills steps are optional.
      for (var step = 0; step < 2; step++) {
        final skip = find.byKey(const Key('profile-step-skip'));
        await pumpUntil(tester, skip);
        await tester.ensureVisible(skip);
        await tester.tap(skip);
        await tester.pumpAndSettle();
      }
      final menu = find.byKey(const Key('home-menu'));
      await pumpUntil(tester, menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      final settings = find.byKey(const Key('home-settings'));
      await pumpUntil(tester, settings);
      expect(
        container.read(authStatusProvider).value,
        AuthenticationStatus.authenticated,
      );

      // Only the refresh token is kept, in the secure storage.
      final saved = await storage.readAll();
      final refresh = saved[AuthStorage.refreshTokenKey];
      expect(refresh, isNotNull);
      expect(saved.keys, {
        AuthStorage.refreshTokenKey,
        AuthStorage.deviceIdKey,
        AuthStorage.cacheNamespaceKey,
      });

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
      final signOut = find.byKey(const Key('sign-out'));
      await tester.scrollUntilVisible(signOut, 200, scrollable: pageScroll);
      await tester.tap(signOut);
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
    },
  );
}
