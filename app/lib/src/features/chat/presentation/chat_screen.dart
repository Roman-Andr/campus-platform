import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/generated/campus_api.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../profile/application/my_profile.dart';
import '../application/chat_config.dart';
import '../application/chat_history.dart';
import '../application/chat_queue.dart';
import '../application/chats.dart';
import '../domain/chat.dart';
import 'chat_input_limit.dart';
import 'chat_labels.dart';
import 'chats_screen.dart' show chatTime;

/// One personal dialog: history ordered by the server, a durable composer
/// and live wakeups that reconcile the history through the API.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.id, this.initialSequence, super.key});

  final String id;

  /// Message sequence of a search hit to reveal when the screen opens.
  final int? initialSequence;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  ProviderSubscription<AsyncValue<ChatHistoryState>>? _historyListener;
  StreamSubscription<MessageOutput>? _delivered;
  late final ChatHistory _history;
  late final ChatQueue _queue;
  String? _formError;
  String? _olderError;
  bool _prependInProgress = false;
  bool _initialScrollDone = false;
  bool _jumpLoading = false;
  bool _targetRevealed = false;
  int _shownMessages = 0;
  int? _targetSequence;
  String? _jumpError;
  final _targetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _historyListener = ref.listenManual(
      chatHistoryProvider(widget.id),
      (_, _) {},
    );
    _history = ref.read(chatHistoryProvider(widget.id).notifier);
    _queue = ref.read(chatQueueProvider.notifier);
    _targetSequence = widget.initialSequence;
    if (_targetSequence != null) unawaited(_openSearchHit());
    _delivered = _queue.delivered.listen((message) {
      if (message.chatId == widget.id) {
        unawaited(_history.mergeDelivered(message));
      }
    });
    unawaited(_history.watchRealtime(ref.read(chatRealtimeProvider)));
  }

  @override
  void dispose() {
    _historyListener?.close();
    unawaited(_delivered?.cancel());
    unawaited(_history.unwatchRealtime());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openSearchHit() async {
    if (_jumpLoading || !mounted) return;
    _jumpLoading = true;
    try {
      await ref.read(chatHistoryProvider(widget.id).future);
      if (!mounted) return;
      await _history.openAt(_targetSequence!);
      if (mounted) setState(() => _jumpError = null);
    } on ChatMessageContextUnavailable {
      if (mounted) {
        setState(() => _jumpError = context.l10n.chatSearchMessageUnavailable);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _jumpError = chatFailureMessage(context.l10n, error));
      }
    } finally {
      _jumpLoading = false;
    }
  }

  void _retrySearchHit() {
    _targetRevealed = false;
    setState(() => _jumpError = null);
    unawaited(_openSearchHit());
  }

  void _retryHistory() {
    ref.invalidate(chatHistoryProvider(widget.id));
    if (_targetSequence != null) {
      _targetRevealed = false;
      unawaited(_openSearchHit());
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    try {
      await _queue.send(widget.id, text);
      if (!mounted) return;
      _input.clear();
      setState(() => _formError = null);
      _scrollToEnd();
    } on ChatMessageEmpty {
      setState(() => _formError = context.l10n.chatMessageEmpty);
    } on ChatMessageTooLong catch (error) {
      setState(
        () => _formError = context.l10n.chatMessageTooLong(error.maxLength),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _formError = chatFailureMessage(context.l10n, error));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  bool get _isNearBottom =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.position.pixels <= 80;

  Future<void> _loadOlder() async {
    if (_prependInProgress || !_scroll.hasClients) return;
    final oldMax = _scroll.position.maxScrollExtent;
    final oldPixels = _scroll.position.pixels;
    _prependInProgress = true;
    try {
      await _history.loadOlder();
      if (!mounted) return;
      // The error belongs to the button at the top of the list, not to the
      // composer at the bottom; a successful page clears it.
      setState(() => _olderError = null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) {
          _prependInProgress = false;
          return;
        }
        final added = _scroll.position.maxScrollExtent - oldMax;
        if (added > 0) {
          _scroll.jumpTo(
            (oldPixels + added).clamp(0.0, _scroll.position.maxScrollExtent),
          );
        }
        _prependInProgress = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _olderError = chatFailureMessage(context.l10n, error);
        _prependInProgress = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final chat = ref.watch(chatProvider(widget.id)).value;
    final history = ref.watch(chatHistoryProvider(widget.id));
    final queue = ref.watch(chatQueueProvider).value ?? const ChatQueueState();
    final other = chat == null ? null : otherParticipant(chat, user?.id);
    final title = other == null || participantName(other).isEmpty
        ? l10n.chatTitle
        : participantName(other);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: switch (history) {
        AsyncValue(value: final state?) => _buildChat(
          context,
          user: user,
          history: state,
          queue: queue,
        ),
        AsyncValue(:final error?) => ApiErrorView(
          error: error,
          message: chatFailureMessage,
          onRetry: _retryHistory,
        ),
        _ => const Center(
          key: Key('chat-loading'),
          child: CircularProgressIndicator(),
        ),
      },
    );
  }

  Widget _buildChat(
    BuildContext context, {
    required UserOutput? user,
    required ChatHistoryState history,
    required ChatQueueState queue,
  }) {
    final l10n = context.l10n;
    final items = chatThread(
      delivered: history.messages,
      outgoing: queue.forChat(widget.id),
      myId: user?.id ?? '',
    );
    if (_targetSequence case final sequence?
        when !_targetRevealed &&
            items.any((item) => item.sequence == sequence)) {
      _targetRevealed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _targetKey.currentContext;
        if (!mounted || target == null) return;
        Scrollable.ensureVisible(
          target,
          alignment: 0.45,
          duration: const Duration(milliseconds: 250),
        );
      });
    }
    if (items.length != _shownMessages) {
      final grew = items.length > _shownMessages;
      final nearBottom = _isNearBottom;
      _shownMessages = items.length;
      if (!_initialScrollDone && items.isNotEmpty) {
        _initialScrollDone = true;
        if (_targetSequence == null) _scrollToEnd();
      } else if (grew &&
          nearBottom &&
          !_prependInProgress &&
          _targetSequence == null) {
        // Do not pull the reader away from older messages; only follow new
        // messages when the viewport was already at the bottom.
        _scrollToEnd();
      }
    }
    return Column(
      children: [
        if (_jumpError case final error?)
          Container(
            key: const Key('chat-jump-error'),
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Expanded(child: Text(error)),
                TextButton(
                  key: const Key('chat-jump-retry'),
                  onPressed: _retrySearchHit,
                  child: Text(l10n.chatMessageRetry),
                ),
              ],
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  key: const Key('chat-empty'),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.chatEmpty, textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  key: const Key('chat-messages'),
                  controller: _scroll,
                  // A search jump must build the target before
                  // Scrollable.ensureVisible can receive its key.
                  scrollCacheExtent: _targetSequence == null
                      ? null
                      : const ScrollCacheExtent.pixels(5000),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      if (history.nextPage == null &&
                          history.olderBefore == null) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            key: const Key('chat-load-older'),
                            onPressed: _loadOlder,
                            child: Text(l10n.chatLoadOlder),
                          ),
                          if (_olderError case final error?)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Text(
                                error,
                                key: const Key('chat-older-error'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      );
                    }
                    final item = items[index - 1];
                    final target = item.sequence == _targetSequence;
                    final bubble = _MessageBubble(
                      item: item,
                      mine: item.senderId == user?.id,
                      sending: queue.sending.contains(
                        item.outgoing?.localId ?? '',
                      ),
                      user: user,
                      highlighted: target,
                      onRetry: item.outgoing == null
                          ? null
                          : () => unawaited(
                              _queue.retry(
                                item.outgoing!.chatId,
                                item.outgoing!.clientId,
                              ),
                            ),
                      onDiscard: item.outgoing == null
                          ? null
                          : () => unawaited(
                              _queue.discard(
                                item.outgoing!.chatId,
                                item.outgoing!.clientId,
                              ),
                            ),
                    );
                    return target
                        ? KeyedSubtree(
                            key: _targetKey,
                            child: KeyedSubtree(
                              key: ValueKey('chat-target-${item.sequence}'),
                              child: bubble,
                            ),
                          )
                        : bubble;
                  },
                ),
        ),
        if (history.syncError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              key: const Key('chat-sync-error'),
              children: [
                Expanded(
                  child: Text(
                    l10n.chatSyncFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('chat-sync-retry'),
                  onPressed: () => unawaited(_history.retrySync()),
                  child: Text(l10n.chatMessageRetry),
                ),
              ],
            ),
          ),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _formError!,
              key: const Key('chat-form-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('chat-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    inputFormatters: [
                      ChatMessageLengthFormatter(
                        ref.watch(chatConfigProvider).maxMessageLength,
                      ),
                    ],
                    decoration: InputDecoration(
                      hintText: l10n.chatInputHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('chat-send'),
                  tooltip: l10n.chatSend,
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.item,
    required this.mine,
    required this.sending,
    required this.user,
    this.highlighted = false,
    this.onRetry,
    this.onDiscard,
  });

  final ChatThreadItem item;
  final bool mine;
  final bool sending;
  final UserOutput? user;
  final bool highlighted;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final pending = item.outgoing;
    final failed = pending?.state == OutgoingChatState.failed;
    final status = pending == null
        ? null
        : failed
        ? l10n.chatMessageFailed
        : sending
        ? l10n.chatMessageSending
        : outgoingFailureMessage(l10n, pending.failure);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('chat-message-${item.clientId}'),
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: pending != null
              ? colors.surfaceContainerHighest
              : mine
              ? colors.primaryContainer
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: highlighted
              ? Border.all(color: colors.tertiary, width: 2)
              : failed
              ? Border.all(color: colors.error)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(item.text),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status != null) ...[
                  Icon(
                    failed ? Icons.error_outline : Icons.schedule,
                    size: 14,
                    color: failed ? colors.error : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      status,
                      key: ValueKey(
                        failed
                            ? 'chat-failed-${item.clientId}'
                            : 'chat-pending-${item.clientId}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: failed ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (failed && onRetry != null) ...[
                    const SizedBox(width: 4),
                    TextButton(
                      key: ValueKey('chat-retry-${item.clientId}'),
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(l10n.chatMessageRetry),
                    ),
                  ],
                  if (failed && onDiscard != null)
                    TextButton(
                      key: ValueKey('chat-discard-${item.clientId}'),
                      onPressed: onDiscard,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(l10n.chatMessageDiscard),
                    ),
                ] else
                  Flexible(
                    child: Text(
                      chatTime(item.createdAt, user, l10n),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
