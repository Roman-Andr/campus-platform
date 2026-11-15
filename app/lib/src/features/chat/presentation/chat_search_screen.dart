import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/generated/campus_api.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../profile/application/my_profile.dart';
import '../application/chat_search.dart';
import '../domain/chat.dart';
import 'chat_labels.dart';
import 'chats_screen.dart' show chatTime;

/// Full-text search across the dialogs of the signed-in user.
///
/// Every hit carries enough context to open the dialog at the matching
/// message; the chat screen then loads the messages around it. The server
/// rechecks membership on that request, so a revoked dialog ends with the
/// same explicit "chat unavailable" refusal as a direct open.
class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  static const _debounce = Duration(milliseconds: 350);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    if (value.trim().isEmpty) {
      ref.read(chatSearchProvider.notifier).clear();
      return;
    }
    _timer = Timer(_debounce, () => _search(value));
  }

  void _onSubmitted(String value) {
    _timer?.cancel();
    unawaited(_search(value));
  }

  Future<void> _search(String value) async {
    await ref.read(chatSearchProvider.notifier).search(value);
  }

  void _clear() {
    _timer?.cancel();
    _input.clear();
    ref.read(chatSearchProvider.notifier).clear();
    setState(() {});
  }

  void _onScroll() {
    if (_loadingMore || _scroll.position.extentAfter > 240) return;
    unawaited(_loadMore());
  }

  Future<void> _loadMore({bool retry = false}) async {
    final state = ref.read(chatSearchProvider);
    if (_loadingMore || !state.hasMore || (!retry && state.moreError != null)) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      await ref.read(chatSearchProvider.notifier).more();
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _retryMore() {
    unawaited(_loadMore(retry: true));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final state = ref.watch(chatSearchProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatSearchTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const Key('chat-search-input'),
              controller: _input,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
              decoration: InputDecoration(
                hintText: l10n.chatSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: state.query.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('chat-search-clear'),
                        tooltip: l10n.chatSearchClear,
                        onPressed: _clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _body(context, state, user)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ChatSearchState state, UserOutput? user) {
    final l10n = context.l10n;
    return switch (state.phase) {
      ChatSearchPhase.idle => _Message(
        key: const Key('chat-search-prompt'),
        icon: Icons.manage_search,
        text: l10n.chatSearchPrompt,
      ),
      ChatSearchPhase.loading => const Center(
        key: Key('chat-search-loading'),
        child: CircularProgressIndicator(),
      ),
      ChatSearchPhase.error => ApiErrorView(
        key: const Key('chat-search-error'),
        error: state.error!,
        message: chatSearchFailureMessage,
        onRetry: () => unawaited(ref.read(chatSearchProvider.notifier).retry()),
      ),
      ChatSearchPhase.ready when state.results.isEmpty => _Message(
        key: const Key('chat-search-empty'),
        icon: Icons.search_off,
        text: l10n.chatSearchEmpty(state.query),
      ),
      ChatSearchPhase.ready => _results(context, state, user),
    };
  }

  Widget _results(
    BuildContext context,
    ChatSearchState state,
    UserOutput? user,
  ) {
    final l10n = context.l10n;
    final showFooter = state.hasMore || state.moreError != null;
    return ListView.builder(
      key: const Key('chat-search-results'),
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: state.results.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.results.length) {
          if (state.moreError != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    l10n.chatSearchLoadMoreFailed,
                    key: const Key('chat-search-more-error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    key: const Key('chat-search-more-retry'),
                    onPressed: _retryMore,
                    child: Text(l10n.chatMessageRetry),
                  ),
                ],
              ),
            );
          }
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                key: Key('chat-search-more-loading'),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton(
              key: const Key('chat-search-more'),
              onPressed: _retryMore,
              child: Text(l10n.chatSearchLoadMore),
            ),
          );
        }
        final result = state.results[index];
        return _ResultTile(
          result: result,
          user: user,
          onTap: () => context.push(
            AppRoutes.chatOf(
              result.chat.id,
              messageSequence: result.message.sequence,
            ),
          ),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.user,
    required this.onTap,
  });

  final ChatSearchResult result;
  final UserOutput? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final other = otherParticipant(result.chat, user?.id);
    final name = other == null ? l10n.chatsUnnamed : participantName(other);
    return ListTile(
      key: ValueKey('chat-search-result-${result.message.id}'),
      onTap: onTap,
      leading: CircleAvatar(
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(
            chatTime(result.message.createdAt, user, l10n),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          result.snippet,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
