import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/generated/campus_api.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/time/city_time.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../profile/application/my_profile.dart';
import '../application/chats.dart';
import '../domain/chat.dart';
import 'chat_labels.dart';

/// The dialogs of the signed-in user, the most recently active first.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final _scroll = ScrollController();
  bool _loadingMore = false;
  Object? _moreError;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _moreError != null) return;
    if (_scroll.position.extentAfter > 240) return;
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final state = ref.read(chatDialogsProvider).value;
    if (state == null || state.nextPage == null) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      await ref.read(chatDialogsProvider.notifier).more();
    } on Object catch (error) {
      if (mounted) setState(() => _moreError = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _retryMore() {
    setState(() => _moreError = null);
    unawaited(_loadMore());
  }

  Future<void> _refresh() async {
    try {
      await ref.read(chatDialogsProvider.notifier).refresh();
      if (mounted) setState(() => _moreError = null);
    } on Object catch (error) {
      _showFailure(error);
    }
  }

  Future<void> _open(ChatOutput chat) async {
    await context.push(AppRoutes.chatOf(chat.id));
    if (!mounted) return;
    try {
      await ref.read(chatDialogsProvider.notifier).refresh();
    } on Object {
      // The loaded list stays; the next open or pull refreshes it.
    }
  }

  void _showFailure(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(chatFailureMessage(context.l10n, error))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final dialogs = ref.watch(chatDialogsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatsTitle),
        actions: [
          IconButton(
            key: const Key('chats-search'),
            tooltip: l10n.chatSearchTitle,
            onPressed: () => context.push(AppRoutes.chatSearch),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: switch (dialogs) {
        AsyncValue(value: final value?) => _Body(
          state: value,
          user: user,
          scroll: _scroll,
          onRefresh: _refresh,
          onOpen: _open,
          loadingMore: _loadingMore,
          moreError: _moreError,
          onLoadMore: _retryMore,
        ),
        AsyncValue(:final error?) => ApiErrorView(
          error: error,
          message: chatFailureMessage,
          onRetry: () => ref.invalidate(chatDialogsProvider),
        ),
        _ => const Center(
          key: Key('chats-loading'),
          child: CircularProgressIndicator(),
        ),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.user,
    required this.scroll,
    required this.onRefresh,
    required this.onOpen,
    required this.loadingMore,
    required this.moreError,
    required this.onLoadMore,
  });

  final ChatDialogsState state;
  final UserOutput? user;
  final ScrollController scroll;
  final Future<void> Function() onRefresh;
  final void Function(ChatOutput chat) onOpen;
  final bool loadingMore;
  final Object? moreError;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.chatsEmpty,
                    key: const Key('chats-empty'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        key: const Key('chats-list'),
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + 1,
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            if (state.nextPage == null) return const SizedBox.shrink();
            if (moreError != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      l10n.chatLoadMoreFailed,
                      key: const Key('chats-more-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const Key('chats-more-retry'),
                      onPressed: onLoadMore,
                      child: Text(l10n.chatMessageRetry),
                    ),
                  ],
                ),
              );
            }
            if (!loadingMore) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                key: Key('chats-more-loading'),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _ChatTile(
            chat: state.items[index],
            user: user,
            onOpen: onOpen,
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.user,
    required this.onOpen,
  });

  final ChatOutput chat;
  final UserOutput? user;
  final void Function(ChatOutput chat) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final other = otherParticipant(chat, user?.id);
    final name = other == null ? l10n.chatsUnnamed : participantName(other);
    final last = lastMessageOf(chat);
    return ListTile(
      key: ValueKey('chat-tile-${chat.id}'),
      leading: CircleAvatar(
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
      ),
      title: Text(name),
      subtitle: Text(
        last == null ? l10n.chatsNoMessages : last.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: last == null
          ? null
          : Text(
              chatTime(last.createdAt, user, l10n),
              style: Theme.of(context).textTheme.bodySmall,
            ),
      onTap: () => onOpen(chat),
    );
  }
}

/// The moment of a chat message in the city zone of the user (ТЗ #44).
String chatTime(DateTime instant, UserOutput? user, AppLocalizations l10n) {
  final timezone = user?.cityTimezone;
  if (timezone == null) {
    return DateFormat.Hm(l10n.localeName).format(instant.toLocal());
  }
  return formatCityTime(
    instant,
    timezone: timezone,
    city: timezone,
    l10n: l10n,
  );
}
