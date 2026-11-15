import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/generated/campus_api.dart';
import '../../../core/auth/auth_session.dart';
import '../data/privacy_api.dart';
import '../domain/privacy.dart';

part 'privacy.g.dart';

// The HTTP transport already retries transient failures. Expected API errors
// must reach the UI immediately, with an explicit retry action.
Duration? privacyRetry(int retryCount, Object error) => null;

/// Who may start a personal dialog with the signed-in user.
///
/// The value is read from the server on every opening, so a change made on
/// another device is shown on this one too.
@Riverpod(retry: privacyRetry)
class MessagePolicyController extends _$MessagePolicyController {
  String? _owner;
  int _generation = 0;

  @override
  Future<MessagePolicy> build() async {
    final generation = ++_generation;
    _owner = null;
    final status = ref.watch(authStatusProvider).value;
    if (status != AuthenticationStatus.authenticated) {
      return MessagePolicy.all;
    }
    final owner = await ref.read(authStorageProvider).cacheNamespace();
    if (!_isGeneration(generation)) return MessagePolicy.all;
    _owner = owner;
    final policy = await ref.read(privacyApiProvider).getMessagePolicy();
    return _isCurrent(generation, owner) ? policy : MessagePolicy.all;
  }

  /// Saves [policy] and returns the value stored by the server.
  ///
  /// The caller keeps [idempotencyKey] while retrying the same change; a
  /// repeat after a dropped connection is applied once. A response that
  /// arrives after a sign-out or an account switch is not written to the
  /// next session.
  Future<MessagePolicy> set(
    MessagePolicy policy, {
    required String idempotencyKey,
  }) async {
    final generation = _generation;
    final owner = _owner;
    final saved = await ref
        .read(privacyApiProvider)
        .updateMessagePolicy(policy, idempotencyKey: idempotencyKey);
    if (owner != null && _isCurrent(generation, owner)) {
      state = AsyncData(saved);
    }
    return saved;
  }

  bool _isGeneration(int generation) =>
      ref.mounted && _generation == generation;

  bool _isCurrent(int generation, String owner) =>
      _isGeneration(generation) && _owner == owner;
}

/// The signed-in user's blacklist, newest first, one cursor page at a time.
///
/// The list is loaded from the server, so a block made on another device is
/// visible here. Mutations update the state only after the server confirms
/// them; a failed request leaves the shown list unchanged.
@Riverpod(retry: privacyRetry)
class BlockedUsers extends _$BlockedUsers {
  String? _owner;
  int _generation = 0;

  /// Bumped by list-changing work. Reads capture it and apply only while it
  /// is unchanged. A mutation bumps it when it starts (so older reads are
  /// dropped) and again after the server confirms it (so a refresh that
  /// snapshotted the old server state cannot undo the confirmed change).
  int _revision = 0;
  bool _loadingMore = false;

  @override
  Future<BlockedUsersState> build() async {
    final generation = ++_generation;
    _owner = null;
    _revision = 0;
    _loadingMore = false;
    final status = ref.watch(authStatusProvider).value;
    if (status != AuthenticationStatus.authenticated) {
      return const BlockedUsersState();
    }
    final owner = await ref.read(authStorageProvider).cacheNamespace();
    if (!_isGeneration(generation)) return const BlockedUsersState();
    _owner = owner;
    final page = await ref.read(privacyApiProvider).listBlocks();
    if (!_isCurrent(generation, owner)) return const BlockedUsersState();
    return BlockedUsersState(
      items: mergeBlockedUsers(page.items, const []),
      nextPage: page.nextPage,
    );
  }

  /// Loads the first page again, keeping the loaded items while it waits.
  Future<void> refresh() async {
    final generation = _generation;
    final owner = _owner;
    if (owner == null) return;
    final revision = ++_revision;
    final page = await ref.read(privacyApiProvider).listBlocks();
    if (!_isCurrent(generation, owner) || revision != _revision) return;
    state = AsyncData(
      BlockedUsersState(
        items: mergeBlockedUsers(page.items, const []),
        nextPage: page.nextPage,
      ),
    );
  }

  /// Appends the next page, unless the list changed while it was loading.
  Future<void> more() async {
    final generation = _generation;
    final owner = _owner;
    final current = state.value;
    final cursor = current?.nextPage;
    if (owner == null || _loadingMore || current == null || cursor == null) {
      return;
    }
    final revision = _revision;
    _loadingMore = true;
    state = AsyncData(
      BlockedUsersState(
        items: current.items,
        nextPage: current.nextPage,
        loadingMore: true,
      ),
    );
    try {
      final page = await ref
          .read(privacyApiProvider)
          .listBlocks(cursor: cursor);
      if (!_isCurrent(generation, owner) || revision != _revision) return;
      final latest = state.value ?? current;
      state = AsyncData(
        BlockedUsersState(
          items: mergeBlockedUsers(latest.items, page.items),
          nextPage: page.nextPage,
        ),
      );
    } on Object catch (error) {
      if (!_isCurrent(generation, owner) || revision != _revision) return;
      final latest = state.value ?? current;
      state = AsyncData(
        BlockedUsersState(
          items: latest.items,
          nextPage: latest.nextPage,
          moreError: error,
        ),
      );
    } finally {
      if (_generation == generation) _loadingMore = false;
    }
  }

  /// Blocks [userId] and adds the server's stored block to the loaded list.
  ///
  /// The caller keeps [idempotencyKey] while retrying the same request. A
  /// response that arrives after a sign-out or an account switch is not
  /// written to the next session. A confirmed block is applied even when a
  /// refresh started while it was in flight; that refresh cannot put the
  /// old list back.
  Future<BlockedUserOutput> block(
    String userId, {
    required String idempotencyKey,
  }) async {
    final generation = _generation;
    final owner = _owner;
    // Reads started before the change must not overwrite its result.
    _revision++;
    final entry = await ref
        .read(privacyApiProvider)
        .blockUser(userId, idempotencyKey: idempotencyKey);
    if (owner == null || !_isCurrent(generation, owner)) return entry;
    // Reads that snapshotted the server before this confirmation are stale.
    _revision++;
    ref.invalidate(blockedUserProvider(userId));
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return entry;
    }
    state = AsyncData(
      BlockedUsersState(
        items: mergeBlockedUsers([entry], current.items),
        nextPage: current.nextPage,
      ),
    );
    return entry;
  }

  /// Removes [userId] from the blacklist after the server confirms it.
  ///
  /// A failure throws and leaves the shown list unchanged. A confirmed
  /// unblock is applied even when a refresh started while it was in flight.
  Future<void> unblock(String userId, {required String idempotencyKey}) async {
    final generation = _generation;
    final owner = _owner;
    _revision++;
    await ref
        .read(privacyApiProvider)
        .unblockUser(userId, idempotencyKey: idempotencyKey);
    if (owner == null || !_isCurrent(generation, owner)) return;
    _revision++;
    ref.invalidate(blockedUserProvider(userId));
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(
      BlockedUsersState(
        items: [
          for (final item in current.items)
            if (item.id != userId) item,
        ],
        nextPage: current.nextPage,
      ),
    );
  }

  bool _isGeneration(int generation) =>
      ref.mounted && _generation == generation;

  bool _isCurrent(int generation, String owner) =>
      _isGeneration(generation) && _owner == owner;
}

/// Whether [userId] is in the signed-in user's blacklist.
///
/// The blacklist endpoint is paginated and has no per-user lookup, so the
/// walk follows the cursors until it finds the user or reaches the end.
/// The screen uses this only when the participant is not in the already
/// loaded first page.
@Riverpod(retry: privacyRetry)
Future<bool> blockedUser(Ref ref, String userId) async {
  final status = ref.watch(authStatusProvider).value;
  if (status != AuthenticationStatus.authenticated) return false;
  final owner = await ref.read(authStorageProvider).cacheNamespace();
  final api = ref.read(privacyApiProvider);
  String? cursor;
  do {
    final page = await api.listBlocks(cursor: cursor);
    if (!ref.mounted) return false;
    final current = await ref.read(authStorageProvider).cacheNamespace();
    if (current != owner) return false;
    if (page.items.any((item) => item.id == userId)) return true;
    cursor = page.nextPage;
  } while (cursor != null);
  return false;
}
