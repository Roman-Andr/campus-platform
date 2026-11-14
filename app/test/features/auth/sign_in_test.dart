import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/auth/application/sign_in_flow.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

const _codes = '/api/v1/auth/sign-in-codes';
const _signIn = '/api/v1/auth/sign-in';
const _refresh = '/api/v1/auth/token/refresh';

final _email = find.byKey(const Key('sign-in-email'));
final _getCode = find.byKey(const Key('sign-in-get-code'));
final _code = find.byKey(const Key('sign-in-code'));
final _resend = find.byKey(const Key('sign-in-resend'));

void main() {
  late FakeHttpAdapter server;

  setUp(() => server = FakeHttpAdapter());

  List<SentRequest> sentTo(String path) =>
      server.sent.where((request) => request.path == path).toList();

  /// Starts the app signed out, with the interface in [language].
  Future<ProviderContainer> start(
    WidgetTester tester, {
    String language = 'ru',
    Map<String, String> secure = const {},
  }) {
    tester.platformDispatcher.localesTestValue = [Locale(language)];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    return tester.pumpCampusApp(
      InMemorySettingsRepository(),
      adapter: server,
      secure: secure,
    );
  }

  /// Enters [email] and requests a code.
  Future<void> requestCode(
    WidgetTester tester, [
    String email = 'ivanov@edu.hse.ru',
  ]) async {
    await tester.enterText(_email, email);
    await tester.tap(_getCode);
    await tester.pumpAndSettle();
  }

  /// Leaves the screens, so that their timers stop before the test ends.
  Future<void> finish(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// Lets a request started by a tap complete without moving the clock
  /// further than a frame.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(Duration.zero);
    }
  }

  String resendLabel(WidgetTester tester) =>
      (tester.widget<TextButton>(_resend).child! as Text).data!;

  testWidgets('a signed-out user starts on the sign-in screen', (tester) async {
    await start(tester);

    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Почта вуза'), findsOneWidget);
  });

  testWidgets('an existing user signs in with the code from the e-mail', (
    tester,
  ) async {
    final container = await start(tester);
    server.route(
      (options) => options.path == _codes
          ? jsonBody(202, null)
          : jsonBody(200, tokensJson(1)),
    );

    await requestCode(tester, '  Ivanov@EDU.hse.ru ');

    expect(sentTo(_codes).single.json, {'email': 'ivanov@edu.hse.ru'});
    expect(find.textContaining('ivanov@edu.hse.ru'), findsOneWidget);

    // The code is sent as soon as all digits are entered.
    await tester.enterText(_code, '123456');
    await tester.pumpAndSettle();

    expect(sentTo(_signIn).single.json['code'], '123456');
    expect(find.text('Пока ничего нет'), findsOneWidget);
    expect(
      container.read(authStatusProvider).value,
      AuthenticationStatus.authenticated,
    );
  });

  for (final optional in [false, true]) {
    testWidgets('a new user accepts required documents; optional: $optional', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await start(tester);
      server.route((options) {
        if (options.path == _codes) return jsonBody(202, null);
        final body = SentRequest(options).json;
        return body.containsKey('first_name')
            ? jsonBody(200, tokensJson(1))
            : problemBody(422, 'registration_required');
      });
      await requestCode(tester);

      await tester.enterText(_code, '123456');
      await tester.pumpAndSettle();
      expect(find.text('Регистрация'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('sign-in-finish')));
      await tester.tap(find.byKey(const Key('sign-in-finish')));
      await tester.pumpAndSettle();
      expect(find.text('Заполните это поле.'), findsNWidgets(2));

      await tester.enterText(
        find.byKey(const Key('sign-in-first-name')),
        'Иван1',
      );
      await tester.enterText(
        find.byKey(const Key('sign-in-last-name')),
        ' Иванова-Петрова ',
      );
      await tester.ensureVisible(find.byKey(const Key('sign-in-finish')));
      await tester.tap(find.byKey(const Key('sign-in-finish')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Можно использовать только буквы, пробелы, дефисы и апострофы.',
        ),
        findsOneWidget,
      );
      expect(sentTo(_signIn), hasLength(1));

      await tester.enterText(
        find.byKey(const Key('sign-in-first-name')),
        'Иван',
      );
      // Names alone cannot finish registration.
      await tester.ensureVisible(find.byKey(const Key('sign-in-finish')));
      await tester.tap(find.byKey(const Key('sign-in-finish')));
      await tester.pumpAndSettle();
      expect(sentTo(_signIn), hasLength(1));
      await tester.ensureVisible(find.byKey(const Key('consent-required')));
      await tester.tap(find.byKey(const Key('consent-required')));
      await tester.pumpAndSettle();
      if (optional) {
        await tester.tap(find.byKey(const Key('consent-cross-border')));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const Key('sign-in-finish')));
      await tester.tap(find.byKey(const Key('sign-in-finish')));
      await tester.pumpAndSettle();

      expect(sentTo(_signIn).last.json, {
        'email': 'ivanov@edu.hse.ru',
        'code': '123456',
        'device_id': isA<String>(),
        'first_name': 'Иван',
        'last_name': 'Иванова-Петрова',
        if (optional) 'cross_border_document_id': 'cross_border_transfer',
        'accepted_document_ids': [
          'community_rules',
          'privacy_policy',
          'personal_data_processing',
        ],
      });
      expect(find.text('Пока ничего нет'), findsOneWidget);
    });
  }

  testWidgets('registration requires a new decision after documents change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await start(tester);
    container.read(signInFlowProvider.notifier).codeSent('ivanov@edu.hse.ru');
    container.read(signInFlowProvider.notifier).namesRequired('123456');
    container.read(appRouterProvider).go(AppRoutes.signInName);
    var attempts = 0;
    server.route((options) {
      if (++attempts == 1) {
        server.documents = [
          for (final d in consentDocumentsJson)
            {...d, 'id': '${d['id']}-v2', 'version': 2},
        ];
        return problemBody(403, 'consent_required');
      }
      return jsonBody(200, tokensJson(1));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sign-in-first-name')), 'Иван');
    await tester.enterText(
      find.byKey(const Key('sign-in-last-name')),
      'Иванов',
    );
    await tester.tap(find.byKey(const Key('consent-required')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-in-finish')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('consent-required')))
          .value,
      isFalse,
    );
    expect(find.text('Иван'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-in-finish')));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    await tester.tap(find.byKey(const Key('consent-required')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-in-finish')));
    await tester.pumpAndSettle();
    expect(sentTo(_signIn).last.json['accepted_document_ids'], [
      'community_rules-v2',
      'privacy_policy-v2',
      'personal_data_processing-v2',
    ]);
    expect(find.text('Пока ничего нет'), findsOneWidget);
  });

  testWidgets('a wrong code is explained in Russian', (tester) async {
    await start(tester);
    server
      ..reply(202, null)
      ..replyProblem(401, 'sign_in_code_invalid');
    await requestCode(tester);

    await tester.enterText(_code, '000000');
    await tester.pumpAndSettle();

    expect(
      find.text('Неверный код. Проверьте письмо и попробуйте ещё раз.'),
      findsOneWidget,
    );
    expect(find.text('Server detail'), findsNothing);
    await finish(tester);
  });

  testWidgets('a wrong code is explained in English', (tester) async {
    await start(tester, language: 'en');
    server
      ..reply(202, null)
      ..replyProblem(401, 'sign_in_code_invalid');
    await requestCode(tester);

    await tester.enterText(_code, '000000');
    await tester.pumpAndSettle();

    expect(
      find.text('Wrong code. Check the e-mail and try again.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('exceeded attempts and an expired code ask for a new code', (
    tester,
  ) async {
    await start(tester, language: 'en');
    server
      ..reply(202, null)
      ..replyProblem(401, 'sign_in_code_attempts_exceeded')
      ..replyProblem(401, 'sign_in_code_expired');
    await requestCode(tester);

    await tester.enterText(_code, '000000');
    await tester.pumpAndSettle();
    expect(
      find.text('Too many wrong attempts. Request a new code.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The code has expired or was already used. Request a new code.',
      ),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('an exceeded limit of codes tells how long to wait', (
    tester,
  ) async {
    await start(tester);
    server.replyProblem(429, 'rate_limited', retryAfter: 840);

    await requestCode(tester);

    expect(
      find.text('Слишком много попыток. Повторите через 14 мин.'),
      findsOneWidget,
    );
    // The limit is not hit again by automatic repeats.
    expect(sentTo(_codes), hasLength(1));
  });

  testWidgets('an exceeded limit is explained in English', (tester) async {
    await start(tester, language: 'en');
    server.replyProblem(429, 'rate_limited', retryAfter: 42);

    await requestCode(tester);

    expect(find.text('Too many attempts. Try again in 42 s.'), findsOneWidget);
  });

  testWidgets('an address outside the university is rejected', (tester) async {
    await start(tester);
    server.replyProblem(422, 'email_domain_not_allowed');

    await requestCode(tester, 'ivanov@gmail.com');

    expect(
      find.text(
        'Этот адрес не из почты вуза. Войдите с адресом в домене вуза.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a malformed address is not sent', (tester) async {
    await start(tester);

    await requestCode(tester, 'ivanov');

    expect(
      find.text('Введите адрес почты, например ivanov@edu.hse.ru.'),
      findsOneWidget,
    );
    expect(server.sent, isEmpty);
  });

  testWidgets('the code can be sent again after the timer', (tester) async {
    await start(tester);
    server.reply(202, null);
    await requestCode(tester);

    expect(resendLabel(tester), 'Отправить код ещё раз можно через 1:00');
    expect(tester.widget<TextButton>(_resend).onPressed, isNull);

    await tester.pump(const Duration(seconds: 59));
    expect(resendLabel(tester), 'Отправить код ещё раз можно через 0:01');

    await tester.pump(const Duration(seconds: 1));
    expect(resendLabel(tester), 'Отправить код ещё раз');

    await tester.tap(_resend);
    await settle(tester);
    expect(sentTo(_codes), hasLength(2));
    expect(find.text('Новый код отправлен'), findsOneWidget);
    expect(resendLabel(tester), 'Отправить код ещё раз можно через 1:00');

    // The server may ask to wait longer than the timer.
    await tester.pump(const Duration(seconds: 60));
    server.replyProblem(429, 'rate_limited', retryAfter: 300);
    await tester.tap(_resend);
    await settle(tester);
    expect(resendLabel(tester), 'Отправить код ещё раз можно через 5:00');
    expect(
      find.text('Слишком много попыток. Повторите через 5 мин.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('the code step needs a requested code', (tester) async {
    final container = await start(tester);

    container.read(appRouterProvider).go(AppRoutes.signInCode);
    await tester.pumpAndSettle();

    expect(_email, findsOneWidget);
  });

  testWidgets('a revoked session returns to the sign-in screen', (
    tester,
  ) async {
    final container = await start(tester, secure: signedInStorage);
    expect(find.text('Пока ничего нет'), findsOneWidget);
    server.route(
      (options) => options.path == _refresh
          ? problemBody(401, 'refresh_token_invalid')
          : problemBody(401, 'unauthorized'),
    );

    // Not awaited: the test zone runs the request while frames are pumped.
    unawaited(
      container
          .read(apiDioProvider)
          .get<Object?>(
            '/api/v1/things',
            options: Options(extra: {securityExtra: <Object?>[]}),
          )
          .then<void>((_) {}, onError: (Object _) {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsOneWidget);
  });

  testWidgets('signing out from settings returns to the sign-in screen', (
    tester,
  ) async {
    await start(tester, secure: signedInStorage);
    var issued = 0;
    server.route(
      (options) => options.path == _refresh
          ? jsonBody(200, tokensJson(++issued))
          : jsonBody(204, null),
    );

    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('sign-out')), 200);
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();

    expect(sentTo('/api/v1/auth/sign-out'), hasLength(1));
    expect(find.text('Вход'), findsOneWidget);
  });

  testWidgets('other screens need a signed-in user', (tester) async {
    final container = await start(tester);

    container.read(appRouterProvider).go(AppRoutes.settings);
    await tester.pumpAndSettle();

    expect(_email, findsOneWidget);
    expect(find.text('Выйти из аккаунта'), findsNothing);
  });
}
