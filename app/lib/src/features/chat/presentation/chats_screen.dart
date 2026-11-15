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
    if (_scroll.position.extentAfter > 240) return;
    unawaited(
      ref.read(chatDialogsProvider.notifier).more().catchError((Object _) {}),
    );
  }

  Future<void> _refresh() async {
    try {
      await ref.read(chatDialogsProvider.notifier).refresh();
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
      appBar: AppBar(title: Text(l10n.chatsTitle)),
      body: switch (dialogs) {
        AsyncValue(value: final value?) => _Body(
          state: value,
          user: user,
          scroll: _scroll,
          onRefresh: _refresh,
          onOpen: _open,
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
  });

  final ChatDialogsState state;
  final UserOutput? user;
  final ScrollController scroll;
  final Future<void> Function() onRefresh;
  final void Function(ChatOutput chat) onOpen;

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
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: state.nextPage == null
                    ? const SizedBox.shrink()
                    : const CircularProgressIndicator(),
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
