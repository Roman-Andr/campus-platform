import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/photos/photo_image.dart';
import '../../../core/photos/photo_upload.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../listings/application/listings.dart';
import '../../privacy/application/privacy.dart';
import '../../privacy/presentation/privacy_labels.dart';
import '../../profile/application/my_profile.dart';
import '../application/chat_config.dart';
import '../application/chat_history.dart';
import '../application/chat_message_photos.dart';
import '../application/chat_photo_draft.dart';
import '../application/chat_queue.dart';
import '../application/chats.dart';
import '../data/chat_api.dart';
import '../domain/chat.dart';
import 'chat_input_limit.dart';
import 'chat_labels.dart';
import 'chats_screen.dart' show chatTime;

enum _ChatPrivacyAction { block, unblock }

enum _MessageAction { reply, edit, delete }

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
  String? _privacyError;
  String? _actionError;
  String? _photoNotice;
  ChatQuote? _replyTo;
  String? _blockKey;
  String? _unblockKey;
  bool _privacyBusy = false;
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

  /// The current visible snapshot of the chosen quote.
  ///
  /// The composer never keeps an old text after an edit and never shows the
  /// text of a deleted message; the wire `reply_to_id` is only sent while
  /// the message is still visible.
  ChatQuote? _resolveQuote(ChatHistoryState? history) {
    final chosen = _replyTo;
    if (chosen == null || history == null) return null;
    final message = history.messages
        .where((message) => message.id == chosen.messageId)
        .firstOrNull;
    return message == null ? null : chatQuoteOf(message);
  }

  Future<void> _send() async {
    final l10n = context.l10n;
    final text = _input.text;
    final draft = ref.read(chatPhotoDraftProvider(widget.id).notifier);
    if (draft.busy) {
      setState(() => _formError = l10n.chatPhotoWait);
      return;
    }
    if (draft.failed) {
      setState(() => _formError = l10n.chatPhotoFix);
      return;
    }
    final photoIds = draft.readyIds;
    final replyTo = _resolveQuote(
      ref.read(chatHistoryProvider(widget.id)).value,
    );
    if (_replyTo != null && replyTo == null) {
      setState(() {
        _replyTo = null;
        _formError = l10n.chatQuoteDeleted;
      });
      return;
    }
    try {
      await _queue.send(widget.id, text, replyTo: replyTo, photoIds: photoIds);
      if (!mounted) return;
      draft.clear();
      _input.clear();
      setState(() {
        _formError = null;
        _replyTo = null;
      });
      _scrollToEnd();
    } on ChatMessageEmpty {
      setState(() => _formError = l10n.chatMessageEmpty);
    } on ChatMessageTooLong catch (error) {
      setState(() => _formError = l10n.chatMessageTooLong(error.maxLength));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _formError = chatFailureMessage(l10n, error));
    }
  }

  Future<void> _attachPhotos(bool camera) async {
    final l10n = context.l10n;
    final draft = ref.read(chatPhotoDraftProvider(widget.id).notifier);
    final picker = ref.read(photoPickerProvider);
    final config = ref.read(photoConfigProvider);
    final files = camera
        ? [?await picker.camera()]
        : await picker.gallery(limit: draft.room);
    if (files.isEmpty || !mounted) return;
    final result = await draft.add(files);
    if (!mounted) return;
    setState(() {
      _photoNotice = [
        if (result.overLimit > 0) l10n.photoLimit(draft.limit),
        for (final name in result.tooLarge)
          l10n.photoTooLarge(name, (config.maxBytes / (1024 * 1024)).ceil()),
      ].join('\n');
    });
  }

  Future<void> _showMessageActions(ChatThreadItem item, bool blocked) async {
    if (item.isPending || item.id == null) return;
    final l10n = context.l10n;
    final mine = item.senderId == ref.read(myProfileProvider).value?.id;
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!blocked)
              ListTile(
                key: const Key('chat-action-reply'),
                leading: const Icon(Icons.reply),
                title: Text(l10n.chatReply),
                onTap: () => Navigator.of(context).pop(_MessageAction.reply),
              ),
            if (mine)
              ListTile(
                key: const Key('chat-action-edit'),
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.chatEdit),
                onTap: () => Navigator.of(context).pop(_MessageAction.edit),
              ),
            if (mine)
              ListTile(
                key: const Key('chat-action-delete'),
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.chatDelete),
                onTap: () => Navigator.of(context).pop(_MessageAction.delete),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _MessageAction.reply:
        setState(() {
          _replyTo = ChatQuote(
            messageId: item.id!,
            senderId: item.senderId,
            text: item.text,
            createdAt: item.createdAt,
          );
          _actionError = null;
        });
      case _MessageAction.edit:
        await _editMessage(item);
      case _MessageAction.delete:
        await _deleteMessage(item);
    }
  }

  bool _isGone(Object error) {
    final failure = ApiFailure.from(error);
    return failure is ProblemFailure &&
        (failure.status == 404 ||
            failure.code == ProblemCode.chatMessageDeleted);
  }

  Future<void> _editMessage(ChatThreadItem item) async {
    final l10n = context.l10n;
    final result = await showDialog<_EditOutcome>(
      context: context,
      builder: (_) =>
          _EditMessageDialog(chatId: widget.id, item: item, history: _history),
    );
    if (!mounted) return;
    switch (result) {
      case _EditOutcome.saved:
        setState(() => _actionError = null);
      case _EditOutcome.gone:
        if (_replyTo?.messageId == item.id) {
          setState(() => _replyTo = null);
        }
        setState(() => _actionError = l10n.chatMessageDeleted);
      case null:
        break;
    }
  }

  Future<void> _deleteMessage(ChatThreadItem item) async {
    final l10n = context.l10n;
    final key = const Uuid().v7();
    var error = l10n.chatDeleteFailed;
    var failed = false;
    final deleted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.chatDeleteTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.chatDeleteExplanation),
              if (failed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    key: const Key('chat-delete-error'),
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('chat-delete-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.chatCancel),
            ),
            FilledButton(
              key: const Key('chat-delete-confirm'),
              onPressed: () async {
                try {
                  await ref
                      .read(chatApiProvider)
                      .deleteMessage(widget.id, item.id!, idempotencyKey: key);
                  if (!mounted) return;
                  await _history.removeMessage(
                    item.id!,
                    sequence: item.sequence,
                    version: item.version,
                  );
                  if (!mounted) return;
                  if (_replyTo?.messageId == item.id) {
                    setState(() => _replyTo = null);
                  }
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } on Object catch (failure) {
                  if (!mounted) return;
                  if (_isGone(failure)) {
                    await _history.removeMessage(
                      item.id!,
                      sequence: item.sequence,
                      version: item.version,
                    );
                    if (!mounted) return;
                    if (_replyTo?.messageId == item.id) {
                      setState(() => _replyTo = null);
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop(false);
                    return;
                  }
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    failed = true;
                    error = chatFailureMessage(l10n, failure);
                  });
                }
              },
              child: Text(l10n.chatDelete),
            ),
          ],
        ),
      ),
    );
    if (deleted == true && mounted) setState(() => _actionError = null);
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

  Future<bool> _confirmBlock() async {
    final l10n = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.chatBlockTitle),
            content: Text(l10n.chatBlockExplanation),
            actions: [
              TextButton(
                key: const Key('chat-block-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.chatBlockCancel),
              ),
              FilledButton(
                key: const Key('chat-block-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.chatBlock),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _block(ParticipantOutput other) async {
    if (_privacyBusy || !await _confirmBlock()) return;
    final key = _blockKey ??= const Uuid().v7();
    setState(() {
      _privacyBusy = true;
      _privacyError = null;
    });
    try {
      await ref
          .read(blockedUsersProvider.notifier)
          .block(other.id, idempotencyKey: key);
      if (!mounted) return;
      _blockKey = null;
      refreshListings(ref);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.chatBlocked)));
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _privacyError = privacyFailureMessage(context.l10n, error),
      );
    } finally {
      if (mounted) setState(() => _privacyBusy = false);
    }
  }

  Future<void> _unblock(ParticipantOutput other) async {
    if (_privacyBusy) return;
    final key = _unblockKey ??= const Uuid().v7();
    setState(() {
      _privacyBusy = true;
      _privacyError = null;
    });
    try {
      await ref
          .read(blockedUsersProvider.notifier)
          .unblock(other.id, idempotencyKey: key);
      if (!mounted) return;
      _unblockKey = null;
      refreshListings(ref);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.chatUnblocked)));
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _privacyError = privacyFailureMessage(context.l10n, error),
      );
    } finally {
      if (mounted) setState(() => _privacyBusy = false);
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
    final personal = chat?.kind == 'personal';
    final title = other == null || participantName(other).isEmpty
        ? l10n.chatTitle
        : participantName(other);
    final blockedUsers = ref.watch(blockedUsersProvider).value;
    final knownBlocked =
        personal &&
        other != null &&
        (blockedUsers?.contains(other.id) ?? false);
    // The first loaded page may not contain the participant. Walk the
    // remaining pages before showing the composer as available; a block
    // made on another device must not be mistaken for an unblocked user.
    final checkOther =
        personal &&
        other != null &&
        !knownBlocked &&
        blockedUsers?.nextPage != null;
    final foundBlocked = other != null && checkOther
        ? ref.watch(blockedUserProvider(other.id)).value ?? false
        : false;
    final blocked = knownBlocked || foundBlocked;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (personal && other != null && other.id != user?.id)
            PopupMenuButton<_ChatPrivacyAction>(
              key: const Key('chat-menu'),
              tooltip: l10n.moreActions,
              enabled: !_privacyBusy,
              onSelected: (action) => unawaited(
                action == _ChatPrivacyAction.block
                    ? _block(other)
                    : _unblock(other),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: ValueKey(blocked ? 'chat-unblock' : 'chat-block'),
                  value: blocked
                      ? _ChatPrivacyAction.unblock
                      : _ChatPrivacyAction.block,
                  child: Text(blocked ? l10n.chatUnblock : l10n.chatBlock),
                ),
              ],
            ),
        ],
      ),
      body: switch (history) {
        AsyncValue(value: final state?) => _buildChat(
          context,
          user: user,
          other: other,
          history: state,
          queue: queue,
          blocked: blocked,
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
    required ParticipantOutput? other,
    required ChatHistoryState history,
    required ChatQueueState queue,
    required bool blocked,
  }) {
    final l10n = context.l10n;
    final photoDraft = ref.watch(chatPhotoDraftProvider(widget.id));
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
                      chatId: widget.id,
                      mine: item.senderId == user?.id,
                      sending: queue.sending.contains(
                        item.outgoing?.localId ?? '',
                      ),
                      user: user,
                      other: other,
                      highlighted: target,
                      onLongPress: item.isPending
                          ? null
                          : () => unawaited(_showMessageActions(item, blocked)),
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
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _actionError!,
              key: const Key('chat-action-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_privacyError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _privacyError!,
              key: const Key('chat-privacy-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (blocked)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                key: const Key('chat-blocked-banner'),
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.chatBlockedNotice)),
                ],
              ),
            ),
          )
        else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo case final chosen?)
                    _QuoteBar(
                      key: const Key('chat-quote'),
                      quote: _resolveQuote(history),
                      senderName: _senderName(
                        chosen.senderId,
                        user: user,
                        other: other,
                        l10n: l10n,
                      ),
                      onCancel: () => setState(() {
                        _replyTo = null;
                        _actionError = null;
                      }),
                    ),
                  if (photoDraft.isNotEmpty)
                    _ComposerPhotos(chatId: widget.id, draft: photoDraft),
                  if (_photoNotice case final notice?)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          notice,
                          key: const Key('chat-photo-notice'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      PopupMenuButton<bool>(
                        key: const Key('chat-attach'),
                        tooltip: l10n.chatPhotoAdd,
                        enabled:
                            photoDraft.length <
                            ref.watch(chatConfigProvider).maxPhotos,
                        onSelected: (camera) =>
                            unawaited(_attachPhotos(camera)),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            key: const Key('chat-attach-gallery'),
                            value: false,
                            child: ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: Text(l10n.photoChoose),
                            ),
                          ),
                          PopupMenuItem(
                            key: const Key('chat-attach-camera'),
                            value: true,
                            child: ListTile(
                              leading: const Icon(Icons.photo_camera_outlined),
                              title: Text(l10n.photoTake),
                            ),
                          ),
                        ],
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
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
    required this.chatId,
    required this.mine,
    required this.sending,
    required this.user,
    required this.other,
    this.highlighted = false,
    this.onLongPress,
    this.onRetry,
    this.onDiscard,
  });

  final ChatThreadItem item;
  final String chatId;
  final bool mine;
  final bool sending;
  final UserOutput? user;
  final ParticipantOutput? other;
  final bool highlighted;
  final VoidCallback? onLongPress;
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
      child: GestureDetector(
        onLongPress: item.isPending ? null : onLongPress,
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
              if (item.replyToId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _QuoteBar(
                    key: ValueKey('chat-quote-${item.clientId}'),
                    quote: item.replyTo,
                    senderName: _senderName(
                      item.replyTo?.senderId ?? '',
                      user: user,
                      other: other,
                      l10n: l10n,
                    ),
                  ),
                ),
              if (item.photoIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: item.id == null
                      ? _PendingPhotos(
                          key: ValueKey('chat-photos-${item.clientId}'),
                          photoIds: item.photoIds,
                        )
                      : _MessagePhotos(
                          key: ValueKey('chat-photos-${item.clientId}'),
                          chatId: chatId,
                          messageId: item.id!,
                          photoIds: item.photoIds,
                        ),
                ),
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
                          color: failed
                              ? colors.error
                              : colors.onSurfaceVariant,
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
                  ] else ...[
                    Flexible(
                      child: Text(
                        chatTime(item.createdAt, user, l10n),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                    if (item.edited) ...[
                      const SizedBox(width: 6),
                      Text(
                        l10n.chatMessageEdited,
                        key: ValueKey('chat-edited-${item.clientId}'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                  IconButton(
                    key: ValueKey('chat-message-menu-${item.clientId}'),
                    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                    onPressed: item.isPending ? null : onLongPress,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    iconSize: 18,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _senderName(
  String senderId, {
  required UserOutput? user,
  required ParticipantOutput? other,
  required AppLocalizations l10n,
}) {
  if (user != null && senderId == user.id) return l10n.chatYou;
  if (other != null) return participantName(other);
  return l10n.chatTitle;
}

/// A visible quote, or the fact that the quoted message was deleted.
class _QuoteBar extends StatelessWidget {
  const _QuoteBar({
    required this.quote,
    required this.senderName,
    this.onCancel,
    super.key,
  });

  final ChatQuote? quote;
  final String senderName;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.35),
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quote != null)
                  Text(
                    senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.primary),
                  ),
                Text(
                  quote?.text ?? l10n.chatQuoteDeleted,
                  key: onCancel == null ? null : const Key('chat-quote-text'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: quote == null ? colors.onSurfaceVariant : null,
                    fontStyle: quote == null ? FontStyle.italic : null,
                  ),
                ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              key: const Key('chat-quote-cancel'),
              visualDensity: VisualDensity.compact,
              tooltip: l10n.chatReplyCancel,
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }
}

/// Photos chosen for a pending message; the signed links exist only after
/// the server stored and attached them.
class _PendingPhotos extends StatelessWidget {
  const _PendingPhotos({required this.photoIds, super.key});

  final List<String> photoIds;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final _ in photoIds)
        SizedBox.square(
          dimension: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: const PhotoPlaceholder(),
          ),
        ),
    ],
  );
}

/// Signed photos of a delivered message.
///
/// Links expire quickly, so the widget requests a fresh set when the earliest
/// one is about to expire and offers an explicit retry when the request fails
/// (for example, the message was deleted on another device).
class _MessagePhotos extends ConsumerStatefulWidget {
  const _MessagePhotos({
    required this.chatId,
    required this.messageId,
    required this.photoIds,
    super.key,
  });

  final String chatId;
  final String messageId;
  final List<String> photoIds;

  @override
  ConsumerState<_MessagePhotos> createState() => _MessagePhotosState();
}

class _MessagePhotosState extends ConsumerState<_MessagePhotos> {
  Timer? _refresh;
  DateTime? _scheduledFor;

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  void _schedule(List<ChatPhotoOutput> photos) {
    if (photos.isEmpty) return;
    final expiresAt = photos
        .map((photo) => photo.expiresAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    if (_scheduledFor == expiresAt) return;
    _scheduledFor = expiresAt;
    _refresh?.cancel();
    final wait = expiresAt.difference(clock.now());
    _refresh = Timer(wait.isNegative ? const Duration(seconds: 1) : wait, () {
      if (!mounted) return;
      _scheduledFor = null;
      ref.invalidate(
        chatMessagePhotosProvider(widget.chatId, widget.messageId),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final photos = ref.watch(
      chatMessagePhotosProvider(widget.chatId, widget.messageId),
    );
    return switch (photos) {
      AsyncValue(value: final items?) when items.isNotEmpty => _grid(items),
      AsyncValue(hasValue: true) => const SizedBox.shrink(),
      AsyncValue(hasError: true) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(l10n.chatPhotosUnavailable)),
          IconButton(
            key: ValueKey('chat-photos-retry-${widget.messageId}'),
            visualDensity: VisualDensity.compact,
            tooltip: l10n.chatMessageRetry,
            onPressed: () => ref.invalidate(
              chatMessagePhotosProvider(widget.chatId, widget.messageId),
            ),
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
      _ => const SizedBox(width: 72, height: 72, child: PhotoPlaceholder()),
    };
  }

  Widget _grid(List<ChatPhotoOutput> photos) {
    _schedule(photos);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final photo in photos)
          SizedBox.square(
            dimension: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CampusPhoto(
                url: photo.url,
                cacheKey: 'chat-photo:${photo.id}',
              ),
            ),
          ),
      ],
    );
  }
}

/// Photo slots of the composer with their upload state and retry actions.
class _ComposerPhotos extends ConsumerWidget {
  const _ComposerPhotos({required this.chatId, required this.draft});

  final String chatId;
  final List<ChatPhotoSlot> draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(chatPhotoDraftProvider(chatId).notifier);
    return SizedBox(
      height: 104,
      child: ListView.separated(
        key: const Key('chat-photo-strip'),
        scrollDirection: Axis.horizontal,
        itemCount: draft.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final slot = draft[index];
          final problem =
              slot.phase == ChatPhotoPhase.rejected ||
              slot.phase == ChatPhotoPhase.failed;
          final status = switch (slot.phase) {
            ChatPhotoPhase.uploading => l10n.photoUploading(
              (slot.progress * 100).round(),
            ),
            ChatPhotoPhase.processing => l10n.photoProcessing,
            ChatPhotoPhase.ready => null,
            ChatPhotoPhase.rejected => l10n.chatPhotoInvalid,
            ChatPhotoPhase.failed => l10n.chatPhotoFailed,
          };
          return SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 88,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (slot.bytes != null)
                          Opacity(
                            opacity: problem ? 0.4 : 1,
                            child: Image.memory(
                              slot.bytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const PhotoPlaceholder(),
                            ),
                          )
                        else
                          const PhotoPlaceholder(),
                        if (slot.busy)
                          Center(
                            child: CircularProgressIndicator(
                              value: slot.phase == ChatPhotoPhase.uploading
                                  ? slot.progress
                                  : null,
                            ),
                          ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton.filledTonal(
                            key: ValueKey('chat-photo-remove-$index'),
                            visualDensity: VisualDensity.compact,
                            tooltip: l10n.photoRemove,
                            onPressed: () => notifier.remove(slot.key),
                            icon: const Icon(Icons.close, size: 14),
                          ),
                        ),
                        if (slot.phase == ChatPhotoPhase.failed)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: IconButton.filled(
                              key: ValueKey('chat-photo-retry-$index'),
                              visualDensity: VisualDensity.compact,
                              tooltip: l10n.chatMessageRetry,
                              onPressed: () => notifier.retry(slot.key),
                              icon: const Icon(Icons.refresh, size: 14),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (status != null)
                  Text(
                    status,
                    key: ValueKey('chat-photo-status-$index'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: problem
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _EditOutcome { saved, gone }

/// Owns the text controller for the whole route lifetime: disposing it as
/// soon as [showDialog] resolves would happen before the pop animation ends.
class _EditMessageDialog extends ConsumerStatefulWidget {
  const _EditMessageDialog({
    required this.chatId,
    required this.item,
    required this.history,
  });

  final String chatId;
  final ChatThreadItem item;
  final ChatHistory history;

  @override
  ConsumerState<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends ConsumerState<_EditMessageDialog> {
  late final TextEditingController _input;
  // One key for the whole dialog: a retry after a lost response repeats the
  // same operation instead of creating another edit.
  final _key = const Uuid().v7();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.item.text);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final text = _input.text;
    if (text.trim().isEmpty ||
        text.runes.length > ref.read(chatConfigProvider).maxMessageLength) {
      setState(() => _error = l10n.chatFailureInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final quoteRevision = widget.history.beginQuoteRequest();
      final updated = await ref
          .read(chatApiProvider)
          .editMessage(
            widget.chatId,
            widget.item.id!,
            text: text,
            idempotencyKey: _key,
          );
      if (!mounted) return;
      await widget.history.applyMessage(updated, quoteRevision: quoteRevision);
      if (!mounted) return;
      Navigator.of(context).pop(_EditOutcome.saved);
    } on Object catch (failure) {
      if (!mounted) return;
      final gone =
          failure is ProblemFailure &&
          (failure.status == 404 ||
              failure.code == ProblemCode.chatMessageDeleted);
      if (gone) {
        await widget.history.removeMessage(
          widget.item.id!,
          sequence: widget.item.sequence,
          version: widget.item.version,
        );
        if (!mounted) return;
        Navigator.of(context).pop(_EditOutcome.gone);
        return;
      }
      setState(() {
        _busy = false;
        _error = chatFailureMessage(l10n, failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.chatEditTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('chat-edit-input'),
            controller: _input,
            autofocus: true,
            minLines: 1,
            maxLines: 5,
            inputFormatters: [
              ChatMessageLengthFormatter(
                ref.read(chatConfigProvider).maxMessageLength,
              ),
            ],
            decoration: InputDecoration(
              hintText: l10n.chatInputHint,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                key: const Key('chat-edit-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('chat-edit-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.chatCancel),
        ),
        FilledButton(
          key: const Key('chat-edit-save'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.chatSave),
        ),
      ],
    );
  }
}
