import 'dart:async';

import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/api/interceptors.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/consents/application/consents.dart';
import 'package:campus/src/features/settings/application/settings_controller.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

void main() {
  test('required documents exclude the optional cross-border decision', () {
    final documents = consentDocumentsJson
        .map(DocumentOutput.fromJson)
        .toList();
    expect(requiredDocumentIds(documents), [
      'community_rules',
      'privacy_policy',
      'personal_data_processing',
    ]);
    expect(crossBorderDocument(documents)?.id, 'cross_border_transfer');
  });

  test(
    'concurrent operations share acceptance; sign-out releases waiters',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gate = container.read(consentGateProvider.notifier);
      final first = gate.require();
      final second = gate.require();
      expect(identical(first, second), isTrue);
      expect(container.read(consentGateProvider), isTrue);
      gate.finish(accepted: true);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(container.read(consentGateProvider), isFalse);
      final next = gate.require();
      gate.finish(accepted: false);
      expect(await next, isFalse);
    },
  );

  test(
    'a denied operation retries with its body and idempotency key',
    () async {
      final server = FakeHttpAdapter()
        ..replyProblem(403, 'consent_required')
        ..reply(204, null);
      final dio = Dio(BaseOptions(baseUrl: 'https://campus.test'));
      addTearDown(dio.close);
      dio.httpClientAdapter = server;
      var prompted = 0;
      dio.interceptors.add(
        ConsentInterceptor(dio, () async {
          prompted++;
          return true;
        }),
      );
      await dio.post<void>(
        '/operation',
        data: {'value': 1},
        options: Options(
          headers: {idempotencyKeyHeader: 'same-operation'},
          extra: {securityExtra: <Object?>[]},
        ),
      );
      expect(prompted, 1);
      expect(server.sent, hasLength(2));
      expect(server.sent.last.data, server.sent.first.data);
      expect(server.sent.last.headers[idempotencyKeyHeader], 'same-operation');
    },
  );

  testWidgets(
    'new versions block controls, then retry and restore the screen',
    (tester) async {
      final server = FakeHttpAdapter();
      var accepted = false;
      server.route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path == '/api/v1/me/consents') {
          accepted = true;
          return jsonBody(204, null);
        }
        return accepted
            ? jsonBody(200, {'ok': true})
            : problemBody(403, 'consent_required');
      });
      final container = await tester.pumpCampusApp(
        InMemorySettingsRepository(
          const AppSettings(language: AppLanguage.russian),
        ),
        adapter: server,
      );
      container.read(appRouterProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();
      final originalLocation = container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri;
      var completed = false;
      unawaited(
        container
            .read(apiDioProvider)
            .get<Object?>(
              '/operation',
              options: Options(extra: {securityExtra: <Object?>[]}),
            )
            .then((_) {
              completed = true;
            }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Обновление документов'), findsOneWidget);
      expect(find.byKey(const Key('consent-accept')), findsOneWidget);
      expect(completed, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('consent-accept')))
            .onPressed,
        isNull,
      );
      // Back and changing the underlying route cannot expose its controls.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Обновление документов'), findsOneWidget);
      await tester.tap(find.byKey(const Key('consent-required')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('consent-accept')));
      await tester.tap(find.byKey(const Key('consent-accept')));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(find.text('Обновление документов'), findsNothing);
      expect(
        container.read(appRouterProvider).routeInformationProvider.value.uri,
        originalLocation,
      );
      final acceptance = server.sent.singleWhere(
        (r) => r.path == '/api/v1/me/consents',
      );
      expect(acceptance.json['document_ids'], hasLength(3));
      expect(
        server.sent.where((r) => r.path.endsWith('/cross-border')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'acceptance failure keeps the gate and asks for a fresh decision',
    (tester) async {
      final server = FakeHttpAdapter();
      server.route((options) {
        if (options.path.endsWith('/token/refresh')) {
          return jsonBody(200, tokensJson(1));
        }
        if (options.path == '/api/v1/me/consents') {
          server.documents = [
            for (final d in consentDocumentsJson)
              {...d, 'id': '${d['id']}-v2', 'version': 2},
          ];
          return problemBody(422, 'consent_invalid');
        }
        return problemBody(403, 'consent_required');
      });
      final container = await tester.pumpCampusApp(
        InMemorySettingsRepository(
          const AppSettings(language: AppLanguage.english),
        ),
        adapter: server,
      );
      unawaited(
        container
            .read(apiDioProvider)
            .get<Object?>(
              '/operation',
              options: Options(extra: {securityExtra: <Object?>[]}),
            )
            .then<void>((_) {}, onError: (Object _) {}),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consent-required')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('consent-accept')));
      await tester.tap(find.byKey(const Key('consent-accept')));
      await tester.pumpAndSettle();
      expect(container.read(consentGateProvider), isTrue);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('consent-accept')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('consent-required')))
            .value,
        isFalse,
      );
      expect(
        server.sent.where((r) => r.path.endsWith('/documents')),
        hasLength(2),
      );
      expect(container.read(documentsProvider).value!.first.version, 2);
      expect(server.sent.where((r) => r.path == '/operation'), hasLength(1));
    },
  );

  testWidgets('the gate allows signing out without replaying operations', (
    tester,
  ) async {
    final server = FakeHttpAdapter();
    server.route((options) {
      if (options.path.endsWith('/token/refresh')) {
        return jsonBody(200, tokensJson(1));
      }
      if (options.path.endsWith('/sign-out')) return jsonBody(204, null);
      return problemBody(403, 'consent_required');
    });
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(
        const AppSettings(language: AppLanguage.russian),
      ),
      adapter: server,
    );
    var rejected = false;
    unawaited(
      container
          .read(apiDioProvider)
          .get<Object?>(
            '/operation',
            options: Options(extra: {securityExtra: <Object?>[]}),
          )
          .then<void>(
            (_) {},
            onError: (Object _) {
              rejected = true;
            },
          ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти из аккаунта'));
    await tester.pumpAndSettle();
    expect(rejected, isTrue);
    expect(find.text('Вход'), findsOneWidget);
    expect(server.sent.where((r) => r.path == '/operation'), hasLength(1));
  });

  testWidgets(
    'settings reload the effective consent instead of a cached profile',
    (tester) async {
      final server = FakeHttpAdapter()..reply(200, tokensJson(1));
      final container = await tester.pumpCampusApp(
        InMemorySettingsRepository(),
        adapter: server,
      );
      server.me = {...server.me!, 'cross_border_transfer_allowed': true};
      container.read(appRouterProvider).go(AppRoutes.consents);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('consent-transfer-switch')),
            )
            .value,
        isTrue,
      );
      expect(server.sent.where((r) => r.path == mePath), hasLength(2));
    },
  );

  for (final language in [AppLanguage.russian, AppLanguage.english]) {
    testWidgets(
      'settings read localized documents and confirm revocation: $language',
      (tester) async {
        final server = FakeHttpAdapter(documents: null);
        var allowed = true;
        server.me = {
          ...userJson,
          ...filledProfileJson,
          'cross_border_transfer_allowed': allowed,
        };
        server.route((options) {
          if (options.path.endsWith('/token/refresh')) {
            return jsonBody(200, tokensJson(1));
          }
          if (options.path.endsWith('/documents')) {
            final lang = options.headers['Accept-Language'];
            return jsonBody(200, [
              for (final d in consentDocumentsJson)
                {...d, 'text': 'Legal document $lang'},
            ]);
          }
          if (options.path.endsWith('/cross-border')) {
            allowed = SentRequest(options).json['accepted']! as bool;
            server.me = {
              ...server.me!,
              'cross_border_transfer_allowed': allowed,
            };
            return jsonBody(204, null);
          }
          return jsonBody(204, null);
        });
        final container = await tester.pumpCampusApp(
          InMemorySettingsRepository(AppSettings(language: language)),
          adapter: server,
        );
        container.read(appRouterProvider).go(AppRoutes.consents);
        await tester.pumpAndSettle();
        final ru = language == AppLanguage.russian;
        await tester.tap(
          find.text(ru ? 'Правила сообщества' : 'Community rules'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Legal document ${ru ? 'ru' : 'en'}'), findsOneWidget);
        await tester.tap(find.text(ru ? 'Закрыть' : 'Close'));
        await tester.pumpAndSettle();
        final toggle = find.byKey(const Key('consent-transfer-switch'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            ru ? 'без имён и текста' : 'no names or message text',
          ),
          findsOneWidget,
        );
        expect(
          server.sent.where((r) => r.path.endsWith('/cross-border')),
          isEmpty,
        );
        await tester.tap(find.text(ru ? 'Отмена' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(allowed, isTrue);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(ru ? 'Отозвать согласие' : 'Revoke consent'),
        );
        await tester.pumpAndSettle();
        expect(allowed, isFalse);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(allowed, isTrue);
        expect(
          server.sent.where((r) => r.path.endsWith('/cross-border')),
          hasLength(2),
        );
        // Changing language reloads the texts rather than retaining the old locale.
        await container
            .read(settingsControllerProvider.notifier)
            .setLanguage(ru ? AppLanguage.english : AppLanguage.russian);
        await tester.pumpAndSettle();
        expect(
          server.sent
              .lastWhere((r) => r.path.endsWith('/documents'))
              .headers['Accept-Language'],
          ru ? 'en' : 'ru',
        );
      },
    );
  }
}
