import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/features/account_emails/application/account_emails.dart';
import 'package:campus/src/features/account_emails/presentation/account_email_failure.dart';
import 'package:campus/src/features/profile/application/my_profile.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter server;
  late List<Map<String, Object?>> addresses;

  setUp(() {
    addresses = [
      address('corporate-1', 'ivanov@edu.hse.ru', 'corporate'),
      address('backup-1', 'ivanov@mail.ru', 'backup'),
    ];
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
        return jsonBody(202, null);
      }
      if (options.method == 'POST' && options.path == _emails) {
        final body = SentRequest(options).json;
        final added = address(
          'added',
          body['email']! as String,
          body['kind']! as String,
        );
        addresses.add(added);
        return jsonBody(201, added);
      }
      if (options.method == 'DELETE') {
        addresses.removeWhere((row) => options.path.endsWith('/${row['id']}'));
        return jsonBody(204, null);
      }
      throw StateError('Unexpected ${options.method} ${options.path}');
    });
  });

  Future<ProviderContainer> start({
    Map<String, String> secure = signedInStorage,
  }) async {
    final container = ProviderContainer(
      overrides: apiOverrides(adapter: server, secure: secure),
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    return container;
  }

  int requestsTo(String path, {String? method}) => server.sent
      .where(
        (request) =>
            request.path == path &&
            (method == null || request.method == method),
      )
      .length;

  test('nobody signed in has no addresses and asks nothing', () async {
    final container = await start(secure: const {});

    expect(await container.read(accountEmailsProvider.future), isEmpty);
    expect(requestsTo(_emails, method: 'GET'), 0);
  });

  test('addresses and their kinds come from the server', () async {
    final container = await start();

    final emails = await container.read(accountEmailsProvider.future);

    expect(emails.map((row) => row.email), [
      'ivanov@edu.hse.ru',
      'ivanov@mail.ru',
    ]);
    expect(emails.first.kind, AddressOutputKind.corporate);
    expect(emails.last.kind, AddressOutputKind.backup);
  });

  test('requesting a code sends the address and its kind', () async {
    final container = await start();

    await container
        .read(accountEmailActionsProvider.notifier)
        .requestCode(
          email: 'student@edu.hse.ru',
          kind: AddressInputKind.corporate,
        );

    final sent = server.sent.singleWhere(
      (request) => request.method == 'POST' && request.path == _codes,
    );
    expect(sent.json, {'email': 'student@edu.hse.ru', 'kind': 'corporate'});
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
  });

  test('only the code accepted by the server adds an address', () async {
    final container = await start();
    await container.read(accountEmailsProvider.future);

    await container
        .read(accountEmailActionsProvider.notifier)
        .requestCode(
          email: 'student@edu.hse.ru',
          kind: AddressInputKind.corporate,
        );
    expect(await container.read(accountEmailsProvider.future), hasLength(2));

    await container
        .read(accountEmailActionsProvider.notifier)
        .confirm(
          email: 'student@edu.hse.ru',
          kind: AddressInputKind.corporate,
          code: '123456',
        );

    final sent = server.sent.singleWhere(
      (request) => request.method == 'POST' && request.path == _emails,
    );
    expect(sent.json, {
      'email': 'student@edu.hse.ru',
      'kind': 'corporate',
      'code': '123456',
    });
    expect(await container.read(accountEmailsProvider.future), hasLength(3));
  });

  test('a corporate address refreshes the account type', () async {
    final container = await start();
    container.listen(myProfileProvider, (_, _) {}, fireImmediately: true);
    final before = await container.read(myProfileProvider.future);
    expect(before!.accountType, UserOutputAccountType.employee);

    server.me = {...server.me!, 'account_type': 'student'};
    await container
        .read(accountEmailActionsProvider.notifier)
        .confirm(
          email: 'student@edu.hse.ru',
          kind: AddressInputKind.corporate,
          code: '123456',
        );

    final after = await container.read(myProfileProvider.future);
    expect(after!.accountType, UserOutputAccountType.student);
    expect(requestsTo(mePath, method: 'GET'), greaterThanOrEqualTo(2));
  });

  test('a backup address leaves the account type alone', () async {
    final container = await start();
    container.listen(myProfileProvider, (_, _) {}, fireImmediately: true);
    final before = await container.read(myProfileProvider.future);

    await container
        .read(accountEmailActionsProvider.notifier)
        .confirm(
          email: 'new@mail.ru',
          kind: AddressInputKind.backup,
          code: '123456',
        );

    final after = await container.read(myProfileProvider.future);
    expect(after!.accountType, before!.accountType);
    expect(requestsTo(mePath, method: 'GET'), 1);
  });

  test('deleting a corporate address refreshes the account type', () async {
    final container = await start();
    final emails = await container.read(accountEmailsProvider.future);
    container.listen(myProfileProvider, (_, _) {}, fireImmediately: true);
    await container.read(myProfileProvider.future);
    server.me = {...server.me!, 'account_type': 'student'};

    await container
        .read(accountEmailActionsProvider.notifier)
        .delete(emails.first);

    expect(
      (await container.read(myProfileProvider.future))!.accountType,
      UserOutputAccountType.student,
    );
    expect(requestsTo(mePath, method: 'GET'), greaterThanOrEqualTo(2));
  });

  group('canDeleteAddress', () {
    final corporate = AddressOutput(
      id: 'corporate-1',
      email: 'ivanov@edu.hse.ru',
      kind: AddressOutputKind.corporate,
      verifiedAt: DateTime.utc(2026),
    );
    final second = AddressOutput(
      id: 'corporate-2',
      email: 'student@edu.hse.ru',
      kind: AddressOutputKind.corporate,
      verifiedAt: DateTime.utc(2026),
    );
    final backup = AddressOutput(
      id: 'backup-1',
      email: 'ivanov@mail.ru',
      kind: AddressOutputKind.backup,
      verifiedAt: DateTime.utc(2026),
    );

    test('rejects the only corporate address', () {
      expect(canDeleteAddress(corporate, [corporate, backup]), isFalse);
    });

    test('allows another corporate address and the backup one', () {
      expect(canDeleteAddress(corporate, [corporate, second]), isTrue);
      expect(canDeleteAddress(second, [corporate, second]), isTrue);
      expect(canDeleteAddress(backup, [corporate, backup]), isTrue);
    });
  });

  group('accountEmailFailureMessage', () {
    final ru = lookupAppLocalizations(const Locale('ru'));
    final en = lookupAppLocalizations(const Locale('en'));

    ProblemFailure failure(int status, String code, {Duration? retryAfter}) =>
        ProblemFailure(
          Problem(
            type: 'urn:problem:campus:$code',
            title: 'Server title',
            status: status,
            code: ProblemCode.fromJson(code),
          ),
          retryAfter: retryAfter,
        );

    test('explains a taken address', () {
      expect(
        accountEmailFailureMessage(ru, failure(409, 'email_conflict')),
        'Этот адрес уже занят. Укажите другой.',
      );
    });

    test('explains the domain rule of the requested kind', () {
      expect(
        accountEmailFailureMessage(
          ru,
          failure(422, 'email_kind_invalid'),
          kind: AddressInputKind.backup,
        ),
        'Резервный адрес не должен быть в домене вуза.',
      );
      expect(
        accountEmailFailureMessage(
          en,
          failure(422, 'email_kind_invalid'),
          kind: AddressInputKind.corporate,
        ),
        'Use an address in a university domain.',
      );
    });

    test('explains rate limiting with the time to wait', () {
      expect(
        accountEmailFailureMessage(
          ru,
          failure(429, 'rate_limited', retryAfter: const Duration(seconds: 30)),
        ),
        'Слишком много запросов. Повторите через 30 с.',
      );
    });

    test('explains rejected and expired codes', () {
      expect(
        accountEmailFailureMessage(ru, failure(401, 'sign_in_code_invalid')),
        'Неверный код. Проверьте письмо и попробуйте ещё раз.',
      );
      expect(
        accountEmailFailureMessage(ru, failure(401, 'sign_in_code_expired')),
        'Код истёк или уже использован. Запросите новый код.',
      );
    });

    test('tells which field carries the error', () {
      expect(isAddressRejected(failure(409, 'email_conflict')), isTrue);
      expect(isAddressRejected(failure(422, 'email_kind_invalid')), isTrue);
      expect(isAddressRejected(failure(401, 'sign_in_code_invalid')), isFalse);
    });
  });
}
