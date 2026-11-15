import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/generated/campus_api.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../listings/application/listings.dart';
import '../../profile/application/my_profile.dart';
import '../application/privacy.dart';
import '../domain/privacy.dart';
import 'privacy_labels.dart';

/// The signed-in user's blacklist, loaded from the server.
///
/// A row disappears only after the server confirms the unblock; a failed
/// request leaves it visible and shows a localized error. The retry of a
/// failed unblock reuses its idempotency key.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  final _scroll = ScrollController();
  final _unblockKeys = <String, String>{};
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter >= 240) return;
    final state = ref.read(blockedUsersProvider).value;
    // A failed page is retried by the explicit footer action, not by every
    // scroll notification; otherwise a broken connection would hammer the
    // server while the spinner stays on screen.
    if (state == null || state.moreError != null) return;
    unawaited(ref.read(blockedUsersProvider.notifier).more());
  }

  Future<void> _refresh() async {
    try {
      await ref.read(blockedUsersProvider.notifier).refresh();
      if (mounted) setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = privacyFailureMessage(context.l10n, error));
      }
    }
  }

  Future<void> _unblock(BlockedUserOutput entry) async {
    if (_busyId != null) return;
    final key = _unblockKeys.putIfAbsent(entry.id, () => const Uuid().v7());
    setState(() {
      _busyId = entry.id;
      _error = null;
    });
    try {
      await ref
          .read(blockedUsersProvider.notifier)
          .unblock(entry.id, idempotencyKey: key);
      if (!mounted) return;
      _unblockKeys.remove(entry.id);
      refreshListings(ref);
      setState(() => _error = null);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = privacyFailureMessage(context.l10n, error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blocked = ref.watch(blockedUsersProvider);
    final signedIn = ref.watch(myProfileProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.blockedUsersTitle)),
      body: switch (blocked) {
        AsyncValue(value: final state?) => Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _error!,
                  key: const Key('blocked-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(child: _list(state, signedIn)),
          ],
        ),
        AsyncValue(:final error?) => ApiErrorView(
          error: error,
          message: privacyFailureMessage,
          onRetry: () => ref.invalidate(blockedUsersProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _list(BlockedUsersState state, UserOutput? signedIn) {
    final l10n = context.l10n;
    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const Key('blocked-list'),
          children: [
            const SizedBox(height: 120),
            Icon(
              Icons.shield_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.blockedUsersEmpty,
                key: const Key('blocked-empty'),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    final hasMore = state.nextPage != null;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        key: const Key('blocked-list'),
        controller: _scroll,
        itemCount: state.items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.items.length) return _moreFooter(state);
          final entry = state.items[index];
          final name = blockedUserName(entry);
          final busy = _busyId == entry.id;
          return ListTile(
            key: ValueKey('blocked-user-${entry.id}'),
            leading: CircleAvatar(
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              ),
            ),
            title: Text(name),
            subtitle: Text(
              '${blockedAccountLabel(l10n, entry.accountType)}\n'
              '${l10n.blockedUsersBlockedAt(blockedAtText(entry.blockedAt, signedIn, l10n))}',
            ),
            isThreeLine: true,
            trailing: TextButton(
              key: ValueKey('blocked-unblock-${entry.id}'),
              onPressed: _busyId == null
                  ? () => unawaited(_unblock(entry))
                  : null,
              child: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.blockedUsersUnblock),
            ),
          );
        },
      ),
    );
  }

  /// The end of the loaded list: an explicit next-page action, a spinner
  /// while the page is on its way, or a localized error with a retry.
  Widget _moreFooter(BlockedUsersState state) {
    final l10n = context.l10n;
    final error = state.moreError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              privacyFailureMessage(l10n, error),
              key: const Key('blocked-more-error'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              key: const Key('blocked-more-retry'),
              onPressed: () =>
                  unawaited(ref.read(blockedUsersProvider.notifier).more()),
              child: Text(l10n.errorRetry),
            ),
          ],
        ),
      );
    }
    if (!state.loadingMore) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: TextButton(
          key: const Key('blocked-more'),
          onPressed: () =>
              unawaited(ref.read(blockedUsersProvider.notifier).more()),
          child: Text(l10n.blockedUsersMore),
        ),
      );
    }
    return const Padding(
      key: Key('blocked-more-loading'),
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
