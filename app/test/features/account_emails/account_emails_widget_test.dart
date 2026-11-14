import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

const _emails = '/api/v1/me/emails';
const _codes = '/api/v1/me/emails/codes';

Map<String, Object?> address(String id, String email, String kind) => {
  'id': id,
  'email': email,
  'kind': kind,
  'verified_at': '2026-11-14T10:00:00Z',
};

void main() {
  late FakeHttpAdapter server;
  late List<Map<String, Object?>> addresses;
  ResponseBody Function()? codeFailure;
  ResponseBody Function()? confirmFailure;
  ResponseBody Function()? deleteFailure;

  setUp(() {
    addresses = [address('corp-1', 'ivanov@edu.hse.ru', 'corporate')];
    codeFailure = null;
    confirmFailure = null;
    deleteFailure = null;
    server = FakeHttpAdapter(
      me: {...userJson, ...filledProfileJson, 'account_type': 'employee'},
    );
    server.route((options) {
      if (options.path == '/api/v1/auth/token/refresh') {
        return jsonBody(200, tokensJson(1));
      }
      if (options.method == 'GET' && options.path == _emails) {
        return jsonBody(200, addresses);
      }
      if (options.method == 'POST' && options.path == _codes) {
        if (codeFailure case final failure?) return failure();
        return jsonBody(202, null);
      }
      if (options.method == 'POST' && options.path == _emails) {
        if (confirmFailure case final failure?) return failure();
        final body = SentRequest(options).json;
        final kind = body['kind']! as String;
        if (kind == 'backup') {
          addresses.removeWhere((row) => row['kind'] == 'backup');
        } else {
          server.me = {...server.me!, 'account_type': 'student'};
        }
        final added = address('new-1', body['email']! as String, kind);
        addresses.add(added);
        return jsonBody(201, added);
      }
      if (options.method == 'DELETE') {
        if (deleteFailure case final failure?) return failure();
        addresses.removeWhere((row) => options.path.endsWith('/${row['id']}'));
        return jsonBody(204, null);
      }
      throw StateError('Unexpected ${options.method} ${options.path}');
    });
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    bool russian = false,
    String route = AppRoutes.profileEmails,
  }) async {
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(
        AppSettings(
          language: russian ? AppLanguage.russian : AppLanguage.english,
        ),
      ),
      adapter: server,
    );
    container.read(appRouterProvider).go(route);
    await tester.pumpAndSettle();
    return container;
  }

  Finder deleteOf(String id) => find.byKey(ValueKey('email-delete-$id'));

  Future<void> requestCode(WidgetTester tester, String email) async {
    await tester.enterText(find.byKey(const Key('email-input')), email);
    await tester.tap(find.byKey(const Key('email-get-code')));
    await tester.pumpAndSettle();
  }

  Future<void> confirmCode(
    WidgetTester tester, [
    String code = '123456',
  ]) async {
    await tester.enterText(find.byKey(const Key('email-code-input')), code);
    await tester.tap(find.byKey(const Key('email-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('the profile links to addresses and explains the backup one', (
    tester,
  ) async {
    await open(tester, route: AppRoutes.profile);

    await tester.tap(find.byKey(const Key('profile-emails')));
    await tester.pumpAndSettle();

    expect(find.text('E-mail addresses'), findsOneWidget);
    expect(find.text('ivanov@edu.hse.ru'), findsOneWidget);
    expect(find.text('Corporate'), findsOneWidget);
    expect(find.textContaining('only for signing in'), findsOneWidget);
    expect(find.byKey(const Key('emails-add-corporate')), findsOneWidget);
    expect(find.byKey(const Key('emails-add-backup')), findsOneWidget);
    expect(
      find.text('The only corporate address cannot be deleted.'),
      findsOneWidget,
    );
    expect(deleteOf('corp-1'), findsNothing);
  });

  testWidgets('a corporate address is added only after its code', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('emails-add-corporate')));
    await tester.pumpAndSettle();

    expect(find.text('Add corporate address'), findsWidgets);
    await requestCode(tester, 'student@edu.hse.ru');

    expect(find.byKey(const ValueKey('email-new-1')), findsNothing);
    expect(
      find.textContaining('We sent a code to student@edu.hse.ru'),
      findsOneWidget,
    );
    final requested = server.sent.singleWhere(
      (request) => request.method == 'POST' && request.path == _codes,
    );
    expect(requested.json, {
      'email': 'student@edu.hse.ru',
      'kind': 'corporate',
    });

    await confirmCode(tester);

    expect(find.text('Address added'), findsOneWidget);
    expect(find.byKey(const ValueKey('email-new-1')), findsOneWidget);
    expect(find.text('student@edu.hse.ru'), findsOneWidget);
    expect(
      server.sent
          .singleWhere(
            (request) => request.method == 'POST' && request.path == _emails,
          )
          .json,
      {'email': 'student@edu.hse.ru', 'kind': 'corporate', 'code': '123456'},
    );
    // A second corporate address may be deleted, so the note is gone.
    expect(
      find.text('The only corporate address cannot be deleted.'),
      findsNothing,
    );
    expect(deleteOf('corp-1'), findsOneWidget);
  });

  testWidgets('a backup address is replaced after its code', (tester) async {
    addresses.add(address('backup-1', 'ivanov@mail.ru', 'backup'));
    await open(tester);

    expect(find.text('Backup'), findsOneWidget);
    expect(find.byKey(const Key('emails-replace-backup')), findsOneWidget);

    await tester.tap(find.byKey(const Key('emails-replace-backup')));
    await tester.pumpAndSettle();
    expect(find.text('Replace backup address'), findsWidgets);

    await requestCode(tester, 'new@mail.ru');
    await confirmCode(tester);

    expect(find.text('new@mail.ru'), findsOneWidget);
    expect(find.text('ivanov@mail.ru'), findsNothing);
    expect(find.text('Backup'), findsOneWidget);
    expect(
      server.sent
          .singleWhere(
            (request) => request.method == 'POST' && request.path == _emails,
          )
          .json['kind'],
      'backup',
    );
  });

  testWidgets('deleting an address asks first and removes it', (tester) async {
    addresses.add(address('corp-2', 'student@edu.hse.ru', 'corporate'));
    await open(tester);

    expect(deleteOf('corp-2'), findsOneWidget);
    await tester.tap(deleteOf('corp-2'));
    await tester.pumpAndSettle();
    expect(find.text('Delete the address student@edu.hse.ru?'), findsOneWidget);
    expect(server.sent.where((request) => request.method == 'DELETE'), isEmpty);

    await tester.tap(find.byKey(const Key('emails-confirm-delete')));
    await tester.pumpAndSettle();

    expect(find.text('Address deleted'), findsOneWidget);
    expect(find.byKey(const ValueKey('email-corp-2')), findsNothing);
    final deleted = server.sent.singleWhere(
      (request) => request.method == 'DELETE',
    );
    expect(deleted.path, '$_emails/corp-2');
    expect(deleted.headers['Idempotency-Key'], isNotEmpty);
  });

  testWidgets('the last corporate address has no delete control', (
    tester,
  ) async {
    await open(tester);

    expect(deleteOf('corp-1'), findsNothing);
    expect(
      find.text('The only corporate address cannot be deleted.'),
      findsOneWidget,
    );
  });

  testWidgets('a taken address is reported at the field', (tester) async {
    codeFailure = () => problemBody(409, 'email_conflict');
    await open(tester);
    await tester.tap(find.byKey(const Key('emails-add-corporate')));
    await tester.pumpAndSettle();

    await requestCode(tester, 'student@edu.hse.ru');

    expect(
      find.text('This address is already in use. Use another one.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('email-input')), findsOneWidget);
    expect(find.byKey(const Key('email-code-input')), findsNothing);
  });

  testWidgets(
    'a university domain for a backup address is reported at the field',
    (tester) async {
      codeFailure = () => problemBody(422, 'email_kind_invalid');
      await open(tester);
      await tester.tap(find.byKey(const Key('emails-add-backup')));
      await tester.pumpAndSettle();

      await requestCode(tester, 'ivanov@edu.hse.ru');

      expect(
        find.text('A backup address must not be in a university domain.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('rate limiting is reported at the field with the wait', (
    tester,
  ) async {
    codeFailure = () => problemBody(429, 'rate_limited', retryAfter: 30);
    await open(tester);
    await tester.tap(find.byKey(const Key('emails-add-corporate')));
    await tester.pumpAndSettle();

    await requestCode(tester, 'student@edu.hse.ru');

    expect(find.text('Too many requests. Try again in 30 s.'), findsOneWidget);
  });

  testWidgets('a wrong code is reported at the code field', (tester) async {
    confirmFailure = () => problemBody(401, 'sign_in_code_invalid');
    await open(tester);
    await tester.tap(find.byKey(const Key('emails-add-corporate')));
    await tester.pumpAndSettle();

    await requestCode(tester, 'student@edu.hse.ru');
    await confirmCode(tester);

    expect(
      find.text('Wrong code. Check the e-mail and try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('email-code-input')), findsOneWidget);
  });

  testWidgets('the account type label changes after a student address', (
    tester,
  ) async {
    final container = await open(tester, route: AppRoutes.profile);
    expect(find.text('Employee'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-emails')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('emails-add-corporate')));
    await tester.pumpAndSettle();
    await requestCode(tester, 'student@edu.hse.ru');
    await confirmCode(tester);

    container.read(appRouterProvider).pop();
    await tester.pumpAndSettle();

    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Employee'), findsNothing);
  });

  testWidgets('Russian address texts', (tester) async {
    addresses.add(address('backup-1', 'ivanov@mail.ru', 'backup'));
    await open(tester, russian: true);

    expect(find.text('Адреса почты'), findsOneWidget);
    expect(find.text('Корпоративный'), findsOneWidget);
    expect(find.text('Резервный'), findsOneWidget);
    expect(find.textContaining('только для входа'), findsOneWidget);
    expect(find.text('Заменить резервный адрес'), findsOneWidget);

    await tester.tap(find.byKey(const Key('emails-add-corporate')));
    await tester.pumpAndSettle();
    expect(find.text('Добавить корпоративный адрес'), findsWidgets);
    expect(find.text('Получить код'), findsOneWidget);
  });
}
