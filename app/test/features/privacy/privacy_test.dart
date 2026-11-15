import 'dart:async';

import 'package:campus/src/core/api/api_failure.dart';
import 'package:campus/src/core/auth/auth_session.dart';
import 'package:campus/src/core/auth/auth_token.dart';
import 'package:campus/src/features/privacy/application/privacy.dart'
    hide blockedUser;
import 'package:campus/src/features/privacy/data/privacy_api.dart';
import 'package:campus/src/features/privacy/domain/privacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';
import 'privacy_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePrivacyApi api;

  setUp(() => api = FakePrivacyApi());

  Future<ProviderContainer> start() async {
    final container = ProviderContainer(
      overrides: [
        ...apiOverrides(adapter: FakeHttpAdapter(), secure: signedInStorage),
        privacyApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStatusProvider.future);
    return container;
  }

  /// Signs the same container out and in again: the next session gets its
  /// own cache namespace, as after a real account switch.
  Future<void> switchAccount(ProviderContainer container) async {
    await container.read(authSessionProvider).clearToken();
    await container
        .read(authStorageProvider)
        .write(const AuthToken.restored('account-b-refresh'));
    container.invalidate(authStatusProvider);
    await container.read(authStatusProvider.future);
  }

  test('the policy is loaded and saved through the API', () async {
    final container = await start();

    expect(
      await container.read(messagePolicyControllerProvider.future),
      MessagePolicy.all,
    );
    await container
        .read(messagePolicyControllerProvider.notifier)
        .set(MessagePolicy.related, idempotencyKey: 'policy-key');

    expect(api.policy, MessagePolicy.related);
    expect(
      container.read(messagePolicyControllerProvider).value,
      MessagePolicy.related,
    );
    expect(api.updateCalls.single.key, 'policy-key');
    expect(api.updateCalls.single.policy, MessagePolicy.related);
  });

  test(
    'a failed policy change leaves the loaded value and can be retried',
    () async {
      final container = await start();
      await container.read(messagePolicyControllerProvider.future);
      api.updatePolicyError = forbidden();

      await expectLater(
        container
            .read(messagePolicyControllerProvider.notifier)
            .set(MessagePolicy.related, idempotencyKey: 'same-key'),
        throwsA(isA<ProblemFailure>()),
      );
      expect(
        container.read(messagePolicyControllerProvider).value,
        MessagePolicy.all,
      );
      expect(api.policy, MessagePolicy.all);

      api.updatePolicyError = null;
      await container
          .read(messagePolicyControllerProvider.notifier)
          .set(MessagePolicy.related, idempotencyKey: 'same-key');
      expect(
        container.read(messagePolicyControllerProvider).value,
        MessagePolicy.related,
      );
      expect(api.updateCalls.map((call) => call.key).toSet(), {'same-key'});
    },
  );

  test(
    'blocking and unblocking update the list only after confirmation',
    () async {
      api.blocks.add(blockedUser());
      final container = await start();

      final loaded = await container.read(blockedUsersProvider.future);
      expect(loaded.items.single.id, blockedUserId);

      await container
          .read(blockedUsersProvider.notifier)
          .block(secondBlockedUserId, idempotencyKey: 'block-key');
      final afterBlock = container.read(blockedUsersProvider).value!;
      expect(
        afterBlock.items.map((item) => item.id),
        contains(secondBlockedUserId),
      );
      expect(api.blockCalls.single.key, 'block-key');

      await container
          .read(blockedUsersProvider.notifier)
          .unblock(blockedUserId, idempotencyKey: 'unblock-key');
      final afterUnblock = container.read(blockedUsersProvider).value!;
      expect(
        afterUnblock.items.map((item) => item.id),
        isNot(contains(blockedUserId)),
      );
      expect(api.unblockCalls.single.key, 'unblock-key');
    },
  );

  test('a failed block or unblock leaves the list unchanged', () async {
    api.blocks.add(blockedUser());
    final container = await start();
    await container.read(blockedUsersProvider.future);
    api
      ..blockError = forbidden()
      ..unblockError = forbidden();

    await expectLater(
      container
          .read(blockedUsersProvider.notifier)
          .block(secondBlockedUserId, idempotencyKey: 'block-key'),
      throwsA(isA<ProblemFailure>()),
    );
    expect(
      container.read(blockedUsersProvider).value!.items.map((item) => item.id),
      isNot(contains(secondBlockedUserId)),
    );
    await expectLater(
      container
          .read(blockedUsersProvider.notifier)
          .unblock(blockedUserId, idempotencyKey: 'unblock-key'),
      throwsA(isA<ProblemFailure>()),
    );
    expect(
      container.read(blockedUsersProvider).value!.items.map((item) => item.id),
      contains(blockedUserId),
    );
  });

  test('privacy choices made on one device are loaded on another', () async {
    final first = await start();
    await first
        .read(messagePolicyControllerProvider.notifier)
        .set(MessagePolicy.related, idempotencyKey: 'policy-key');
    await first
        .read(blockedUsersProvider.notifier)
        .block(secondBlockedUserId, idempotencyKey: 'block-key');

    final second = await start();
    expect(
      await second.read(messagePolicyControllerProvider.future),
      MessagePolicy.related,
    );
    final loaded = await second.read(blockedUsersProvider.future);
    expect(loaded.items.map((item) => item.id), contains(secondBlockedUserId));
  });

  test(
    'a failed first blacklist page is an error that can be retried',
    () async {
      api.listError = forbidden();
      final container = await start();

      await expectLater(
        container.read(blockedUsersProvider.future),
        throwsA(isA<ProblemFailure>()),
      );

      api.listError = null;
      container.invalidate(blockedUsersProvider);
      expect(
        (await container.read(blockedUsersProvider.future)).items,
        isEmpty,
      );
    },
  );

  test(
    'a policy change of the previous session does not overwrite the next one',
    () async {
      final container = await start();
      final subscription = container.listen(
        messagePolicyControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(messagePolicyControllerProvider.future);

      final gate = Completer<void>();
      api.updateGate = gate.future;
      final saving = container
          .read(messagePolicyControllerProvider.notifier)
          .set(MessagePolicy.related, idempotencyKey: 'old-session-key');

      await switchAccount(container);
      await pumpEventQueue();
      expect(
        await container.read(messagePolicyControllerProvider.future),
        MessagePolicy.all,
      );

      gate.complete();
      await saving;
      expect(
        container.read(messagePolicyControllerProvider).value,
        MessagePolicy.all,
      );
      expect(api.updateCalls.single.key, 'old-session-key');
    },
  );

  test(
    'a block stored for the previous session is not added after a switch',
    () async {
      final container = await start();
      final subscription = container.listen(blockedUsersProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(blockedUsersProvider.future);

      final gate = Completer<void>();
      api.blockGate = gate.future;
      final blocking = container
          .read(blockedUsersProvider.notifier)
          .block(secondBlockedUserId, idempotencyKey: 'old-session-key');

      api.blocks.add(blockedUser());
      await switchAccount(container);
      await pumpEventQueue();
      final loaded = await container.read(blockedUsersProvider.future);
      expect(loaded.items.map((item) => item.id), [blockedUserId]);

      gate.complete();
      await blocking;
      final after = container.read(blockedUsersProvider).value!;
      expect(after.items.map((item) => item.id), [blockedUserId]);
      expect(api.blocks.map((item) => item.id), contains(secondBlockedUserId));
    },
  );

  test(
    'a next page requested before an unblock cannot restore the user',
    () async {
      api.pageSize = 1;
      api.blocks.addAll([
        blockedUser(),
        blockedUser(id: secondBlockedUserId),
        blockedUser(id: '01890a5d-ac96-774b-bcce-b302099a8062'),
      ]);
      final container = await start();
      final subscription = container.listen(blockedUsersProvider, (_, _) {});
      addTearDown(subscription.close);
      final first = await container.read(blockedUsersProvider.future);
      expect(first.nextPage, '1');

      final gate = Completer<void>();
      api.moreGate = gate.future;
      final loading = container.read(blockedUsersProvider.notifier).more();
      await pumpEventQueue();
      expect(api.listCalls, [null, '1']);

      await container
          .read(blockedUsersProvider.notifier)
          .unblock(secondBlockedUserId, idempotencyKey: 'unblock-key');
      expect(
        container
            .read(blockedUsersProvider)
            .value!
            .items
            .map((item) => item.id),
        isNot(contains(secondBlockedUserId)),
      );

      gate.complete();
      await loading;
      final after = container.read(blockedUsersProvider).value!;
      expect(
        after.items.map((item) => item.id),
        isNot(contains(secondBlockedUserId)),
      );
      expect(after.moreError, isNull);
    },
  );

  test('a confirmed block survives a refresh that started during it', () async {
    api.blocks.add(blockedUser());
    final container = await start();
    final subscription = container.listen(blockedUsersProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(blockedUsersProvider.future);

    final blockGate = Completer<void>();
    api.blockGate = blockGate.future;
    final blocking = container
        .read(blockedUsersProvider.notifier)
        .block(secondBlockedUserId, idempotencyKey: 'block-key');
    await pumpEventQueue();

    final refreshGate = Completer<void>();
    api.listGate = refreshGate.future;
    final refreshing = container.read(blockedUsersProvider.notifier).refresh();
    await pumpEventQueue();
    refreshGate.complete();
    await refreshing;
    // The refresh saw the list before the block was confirmed.
    expect(
      container.read(blockedUsersProvider).value!.items.map((item) => item.id),
      [blockedUserId],
    );

    blockGate.complete();
    await blocking;
    expect(
      container.read(blockedUsersProvider).value!.items.map((item) => item.id),
      containsAll([blockedUserId, secondBlockedUserId]),
    );
  });

  test(
    'a confirmed unblock survives a refresh that started during it',
    () async {
      api.blocks.addAll([blockedUser(), blockedUser(id: secondBlockedUserId)]);
      final container = await start();
      final subscription = container.listen(blockedUsersProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(blockedUsersProvider.future);

      final unblockGate = Completer<void>();
      api.unblockGate = unblockGate.future;
      final unblocking = container
          .read(blockedUsersProvider.notifier)
          .unblock(blockedUserId, idempotencyKey: 'unblock-key');
      await pumpEventQueue();

      final refreshGate = Completer<void>();
      api.listGate = refreshGate.future;
      final refreshing = container
          .read(blockedUsersProvider.notifier)
          .refresh();
      await pumpEventQueue();
      refreshGate.complete();
      await refreshing;
      expect(
        container
            .read(blockedUsersProvider)
            .value!
            .items
            .map((item) => item.id),
        containsAll([blockedUserId, secondBlockedUserId]),
      );

      unblockGate.complete();
      await unblocking;
      expect(
        container
            .read(blockedUsersProvider)
            .value!
            .items
            .map((item) => item.id),
        [secondBlockedUserId],
      );
    },
  );

  test('a failed next page keeps the loaded list and can be retried', () async {
    api.pageSize = 1;
    api.blocks.addAll([blockedUser(), blockedUser(id: secondBlockedUserId)]);
    final container = await start();
    final subscription = container.listen(blockedUsersProvider, (_, _) {});
    addTearDown(subscription.close);
    final first = await container.read(blockedUsersProvider.future);
    expect(first.nextPage, '1');

    api.moreListError = forbidden();
    await container.read(blockedUsersProvider.notifier).more();
    final failed = container.read(blockedUsersProvider).value!;
    expect(failed.items.map((item) => item.id), [blockedUserId]);
    expect(failed.moreError, isA<ProblemFailure>());
    expect(failed.nextPage, '1');

    api.moreListError = null;
    await container.read(blockedUsersProvider.notifier).more();
    final loaded = container.read(blockedUsersProvider).value!;
    expect(
      loaded.items.map((item) => item.id),
      containsAll([blockedUserId, secondBlockedUserId]),
    );
    expect(loaded.moreError, isNull);
  });
}
