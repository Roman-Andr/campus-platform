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
import 'chat_labels.dart';
import 'chats_screen.dart' show chatTime;

/// One personal dialog: history ordered by the server, a durable composer
/// and live wakeups that reconcile the history through the API.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.id, super.key});

  final String id;

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
  int _shownMessages = 0;

  @override
  void initState() {
    super.initState();
    _historyListener = ref.listenManual(
      chatHistoryProvider(widget.id),
      (_, _) {},
    );
    _history = ref.read(chatHistoryProvider(widget.id).notifier);
    _queue = ref.read(chatQueueProvider.notifier);
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
          onRetry: () => ref.invalidate(chatHistoryProvider(widget.id)),
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
    if (items.length != _shownMessages) {
      _shownMessages = items.length;
      _scrollToEnd();
    }
    return Column(
      children: [
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      if (history.nextPage == null) {
                        return const SizedBox.shrink();
                      }
                      return Center(
                        child: TextButton(
                          key: const Key('chat-load-older'),
                          onPressed: () async {
                            try {
                              await _history.loadOlder();
                            } on Object catch (error) {
                              if (!mounted) return;
                              setState(
                                () => _formError = chatFailureMessage(
                                  context.l10n,
                                  error,
                                ),
                              );
                            }
                          },
                          child: Text(l10n.chatLoadOlder),
                        ),
                      );
                    }
                    final item = items[index - 1];
                    return _MessageBubble(
                      item: item,
                      mine: item.senderId == user?.id,
                      sending: queue.sending.contains(
                        item.outgoing?.localId ?? '',
                      ),
                      user: user,
                      onRetry: item.outgoing == null
                          ? null
                          : () => unawaited(
                              _queue.retry(
                                item.outgoing!.chatId,
                                item.outgoing!.clientId,
                              ),
                            ),
                    );
                  },
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
                    maxLength: ref.watch(chatConfigProvider).maxMessageLength,
                    buildCounter: (
                      context, {
                      required currentLength,
                      required isFocused,
                      required maxLength,
                    }) => null,
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
    this.onRetry,
  });

  final ChatThreadItem item;
  final bool mine;
  final bool sending;
  final UserOutput? user;
  final VoidCallback? onRetry;

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
          border: failed ? Border.all(color: colors.error) : null,
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
                ] else
                  Text(
                    chatTime(item.createdAt, user, l10n),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
