import 'package:campus/src/core/router/app_router.dart';
import 'package:campus/src/features/privacy/application/privacy.dart'
    hide blockedUser;
import 'package:campus/src/features/privacy/data/privacy_api.dart';
import 'package:campus/src/features/privacy/domain/privacy.dart';
import 'package:campus/src/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import 'privacy_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePrivacyApi api;

  setUp(() => api = FakePrivacyApi());

  Future<ProviderContainer> start(WidgetTester tester) async {
    final container = await tester.pumpCampusApp(
      InMemorySettingsRepository(
        const AppSettings(language: AppLanguage.english),
      ),
      overrides: [privacyApiProvider.overrideWithValue(api)],
    );
    return container;
  }

  testWidgets('the policy is saved only after the server confirms it', (
    tester,
  ) async {
    final container = await start(tester);
    container.read(appRouterProvider).go(AppRoutes.messagePolicy);
    await tester.pumpAndSettle();

    expect(find.text('Who can message me'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);
    expect(
      find.text('Only people with a listing or interaction'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('policy-related')));
    await tester.pumpAndSettle();

    expect(api.policy, MessagePolicy.related);
    expect(api.updateCalls.single.policy, MessagePolicy.related);
    expect(api.updateCalls.single.key, isNotEmpty);
    expect(find.byKey(const Key('policy-error')), findsNothing);
  });

  testWidgets(
    'a forbidden policy change stays old and retries with the same key',
    (tester) async {
      final container = await start(tester);
      api.updatePolicyError = forbidden();
      container.read(appRouterProvider).go(AppRoutes.messagePolicy);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('policy-related')));
      await tester.pumpAndSettle();

      expect(api.policy, MessagePolicy.all);
      expect(find.byKey(const Key('policy-error')), findsOneWidget);
      expect(
        find.text("You don't have access to this action."),
        findsOneWidget,
      );

      api.updatePolicyError = null;
      await tester.tap(find.byKey(const Key('policy-retry')));
      await tester.pumpAndSettle();

      expect(api.policy, MessagePolicy.related);
      expect(api.updateCalls.map((call) => call.key).toSet(), hasLength(1));
      expect(find.byKey(const Key('policy-error')), findsNothing);
    },
  );

  testWidgets('a block is removed only after the server confirms the unblock', (
    tester,
  ) async {
    api.blocks.add(blockedUser());
    final container = await start(tester);
    container.read(appRouterProvider).go(AppRoutes.blockedUsers);
    await tester.pumpAndSettle();

    expect(find.text('Blocked users'), findsOneWidget);
    expect(find.text('Мария Петрова'), findsOneWidget);
    expect(find.textContaining('12:00'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('blocked-unblock-$blockedUserId')),
    );
    await tester.pumpAndSettle();

    expect(api.unblockCalls.single.key, isNotEmpty);
    expect(
      find.byKey(const ValueKey('blocked-user-$blockedUserId')),
      findsNothing,
    );
    expect(find.byKey(const Key('blocked-empty')), findsOneWidget);
  });

  testWidgets(
    'a forbidden unblock leaves the row and retries with the same key',
    (tester) async {
      api.blocks.add(blockedUser());
      final container = await start(tester);
      api.unblockError = forbidden();
      container.read(appRouterProvider).go(AppRoutes.blockedUsers);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('blocked-unblock-$blockedUserId')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('blocked-user-$blockedUserId')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('blocked-error')), findsOneWidget);
      expect(
        find.text("You don't have access to this action."),
        findsOneWidget,
      );

      api.unblockError = null;
      await tester.tap(
        find.byKey(const ValueKey('blocked-unblock-$blockedUserId')),
      );
      await tester.pumpAndSettle();

      expect(api.unblockCalls.map((call) => call.key).toSet(), hasLength(1));
      expect(
        find.byKey(const ValueKey('blocked-user-$blockedUserId')),
        findsNothing,
      );
    },
  );

  testWidgets('the profile opens both privacy screens', (tester) async {
    final container = await start(tester);
    container.read(appRouterProvider).go(AppRoutes.profile);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-message-policy')),
      300,
    );
    await tester.tap(find.byKey(const Key('profile-message-policy')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('policy-all')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-blocked-users')),
      300,
    );
    await tester.tap(find.byKey(const Key('profile-blocked-users')));
    await tester.pumpAndSettle();
    expect(find.text('Blocked users'), findsOneWidget);
  });

  testWidgets('a short first page offers an explicit load more', (
    tester,
  ) async {
    api.pageSize = 1;
    api.blocks.addAll([blockedUser(), blockedUser(id: secondBlockedUserId)]);
    final container = await start(tester);
    container.read(appRouterProvider).go(AppRoutes.blockedUsers);
    await tester.pumpAndSettle();

    expect(container.read(blockedUsersProvider).value!.items, hasLength(1));
    expect(find.byKey(const Key('blocked-more')), findsOneWidget);
    expect(find.byKey(const Key('blocked-more-loading')), findsNothing);

    await tester.tap(find.byKey(const Key('blocked-more')));
    await tester.pumpAndSettle();

    expect(container.read(blockedUsersProvider).value!.items, hasLength(2));
    expect(find.byKey(const Key('blocked-more')), findsNothing);
  });

  testWidgets(
    'a failed next page shows a retry instead of an endless spinner',
    (tester) async {
      api.pageSize = 10;
      for (var index = 0; index < 12; index++) {
        api.blocks.add(
          blockedUser(
            id: 'blocked-$index',
            blockedAt: DateTime.utc(2026, 11, 15, 9, index),
          ),
        );
      }
      final container = await start(tester);
      container.read(appRouterProvider).go(AppRoutes.blockedUsers);
      await tester.pumpAndSettle();
      expect(container.read(blockedUsersProvider).value!.items, hasLength(10));

      api.listError = forbidden();
      await tester.drag(
        find.byKey(const Key('blocked-list')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('blocked-more-retry')),
        120,
      );

      expect(find.byKey(const Key('blocked-more-error')), findsOneWidget);
      expect(find.byKey(const Key('blocked-more-loading')), findsNothing);
      expect(container.read(blockedUsersProvider).value!.moreError, isNotNull);

      api.listError = null;
      await tester.tap(find.byKey(const Key('blocked-more-retry')));
      await tester.pumpAndSettle();

      expect(container.read(blockedUsersProvider).value!.items, hasLength(12));
      expect(find.byKey(const Key('blocked-more-error')), findsNothing);
    },
  );
}
