import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/network_status.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/realtime/realtime_channel.dart';
import '../../../core/realtime/realtime_models.dart';
import '../../../core/realtime/realtime_service.dart';
import '../data/chat_api.dart';
import '../data/chat_store.dart';
import '../domain/chat.dart';
import 'chats.dart';

part 'chat_history.g.dart';

/// Delivered messages of one dialog and the cursor of the older page.
class ChatHistoryState {
  const ChatHistoryState({
    this.messages = const <MessageOutput>[],
    this.nextPage,
  });

  /// Ordered by the server sequence, oldest first.
  final List<MessageOutput> messages;

  /// Cursor of the next older page; null when the beginning is loaded.
  final String? nextPage;
}

/// Loads and reconciles the history of one personal dialog.
///
/// The stored messages open the screen offline. Realtime is only a wakeup:
/// every publication is followed by an API request for messages after the
/// newest loaded sequence, so a lost or duplicated publication cannot change
/// the order — the server sequence does. On the first subscription, after
/// the app returns and after an exhausted realtime history the service calls
/// [sync] again.
@Riverpod(retry: chatRetry)
class ChatHistory extends _$ChatHistory {
  String? _owner;
  ChatStore? _store;
  bool _loadingOlder = false;
  bool _syncing = false;
  bool _syncRequested = false;
  int _generation = 0;
  int _realtimeGeneration = 0;
  RealtimeSubscription? _subscription;
  final _events = <StreamSubscription<Object?>>[];

  @override
  Future<ChatHistoryState> build(String chatId) async {
    final generation = ++_generation;
    _owner = null;
    _store = null;
    _loadingOlder = false;
    _syncing = false;
    _syncRequested = false;
    ref.onDispose(() {
      unawaited(_stopRealtime());
    });
    final status = ref.watch(authStatusProvider).value;
    if (status != AuthenticationStatus.authenticated) {
      return const ChatHistoryState();
    }
    final owner = await ref.read(authStorageProvider).cacheNamespace();
    if (!_isGeneration(generation)) return const ChatHistoryState();
    final store = ref.read(chatStoreProvider);
    final cached = await store.loadMessages(owner, chatId);
    if (!_isGeneration(generation)) return const ChatHistoryState();
    _owner = owner;
    _store = store;
    final online = ref.watch(networkStatusProvider);
    if (!online) return ChatHistoryState(messages: cached);
    try {
      final page = await ref.read(chatApiProvider).listMessages(chatId);
      if (!_isCurrent(generation, owner)) return const ChatHistoryState();
      await store.saveMessages(owner, chatId, page.items);
      if (!_isCurrent(generation, owner)) return const ChatHistoryState();
      return ChatHistoryState(
        messages: mergeMessages(const [], page.items),
        nextPage: page.nextPage,
      );
    } on Object catch (error) {
      if (ApiFailure.from(error) is NetworkFailure &&
          _isCurrent(generation, owner)) {
        return ChatHistoryState(messages: cached);
      }
      rethrow;
    }
  }

  /// Loads the page before the oldest loaded message.
  Future<void> loadOlder() async {
    final generation = _generation;
    final owner = _owner;
    final store = _store;
    final current = state.value;
    final cursor = current?.nextPage;
    if (owner == null ||
        store == null ||
        _loadingOlder ||
        current == null ||
        cursor == null) {
      return;
    }
    _loadingOlder = true;
    try {
      final page = await ref
          .read(chatApiProvider)
          .listMessages(chatId, cursor: cursor);
      if (!_isCurrent(generation, owner)) return;
      await store.saveMessages(owner, chatId, page.items);
      if (!_isCurrent(generation, owner)) return;
      final latest = state.value ?? current;
      state = AsyncData(
        ChatHistoryState(
          messages: mergeMessages(latest.messages, page.items),
          nextPage: page.nextPage,
        ),
      );
    } finally {
      if (_generation == generation) _loadingOlder = false;
    }
  }

  /// Fetches every message after the newest loaded sequence.
  ///
  /// This is the recovery path for a realtime gap, a reconnect and a return
  /// from the background. Pages are requested by sequence, not by time, so a
  /// late message is inserted at its server position and nothing is skipped
  /// or repeated. A wakeup that arrives while a request is in flight is
  /// coalesced into one more pass instead of being dropped: the response of
  /// the first pass may predate the message that caused the second wakeup.
  Future<void> sync() async {
    final generation = _generation;
    if (!_isGeneration(generation)) return;
    if (_syncing) {
      _syncRequested = true;
      return;
    }
    _syncing = true;
    try {
      do {
        if (!_isGeneration(generation)) return;
        _syncRequested = false;
        await _syncOnce(generation);
        if (!_isGeneration(generation)) return;
      } while (_syncRequested);
    } finally {
      // A rebuild owns a new generation; its flags must not be reset by the
      // request of the previous session.
      if (_generation == generation) {
        _syncing = false;
        _syncRequested = false;
      }
    }
  }

  Future<void> _syncOnce(int generation) async {
    final owner = _owner;
    final store = _store;
    final current = state.value;
    if (owner == null || store == null || current == null) return;
    if (!_isCurrent(generation, owner)) return;
    final api = ref.read(chatApiProvider);
    final newest = current.messages.isEmpty
        ? null
        : current.messages.last.sequence;
    final loaded = <MessageOutput>[];
    String? cursor;
    String? olderCursor;
    do {
      final page = await api.listMessages(
        chatId,
        afterSequence: newest,
        ascending: newest == null ? null : true,
        cursor: cursor,
      );
      if (!_isCurrent(generation, owner)) return;
      loaded.addAll(page.items);
      // Only the initial (newest-first) load can supply the older-history
      // cursor. A forward recovery paginates by sequence; reusing its
      // cursor later with another filter would be invalid on the server.
      if (newest == null) olderCursor ??= page.nextPage;
      cursor = page.nextPage;
    } while (cursor != null);
    if (!_isCurrent(generation, owner)) return;
    final latest = state.value ?? current;
    final messages = mergeMessages(latest.messages, loaded);
    await store.saveMessages(owner, chatId, loaded);
    if (!_isCurrent(generation, owner)) return;
    state = AsyncData(
      ChatHistoryState(
        messages: messages,
        // A request after the newest message never replaces the older
        // cursor; only the initial load adds one.
        nextPage: latest.nextPage ?? olderCursor,
      ),
    );
  }

  Future<void> _syncFromEvent() async {
    try {
      await sync();
    } on Object {
      // The realtime banner reports connectivity; the next wakeup or the
      // explicit retry of the screen loads the history again.
    }
  }

  /// Applies a message delivered by our own outbox without another request.
  Future<void> mergeDelivered(MessageOutput message) async {
    final generation = _generation;
    final owner = _owner;
    final store = _store;
    final current = state.value;
    if (owner == null || store == null || !_isCurrent(generation, owner)) {
      return;
    }
    await store.saveMessages(owner, chatId, [message]);
    if (!_isCurrent(generation, owner)) return;
    final messages = mergeMessages(current?.messages ?? const [], [message]);
    state = AsyncData(
      ChatHistoryState(messages: messages, nextPage: current?.nextPage),
    );
  }

  /// Starts live updates while the dialog is open.
  Future<void> watchRealtime(ChatRealtime realtime) async {
    if (_subscription != null) return;
    if (ref.read(authStatusProvider).value !=
        AuthenticationStatus.authenticated) {
      return;
    }
    final generation = ++_realtimeGeneration;
    try {
      final subscription = await realtime.subscribe(
        RealtimeChannel.chat(chatId),
        reload: sync,
      );
      if (!ref.mounted || generation != _realtimeGeneration) {
        await subscription.close();
        return;
      }
      _events.add(
        subscription.events.listen((_) => unawaited(_syncFromEvent())),
      );
      _subscription = subscription;
    } on Object {
      // Realtime is a wakeup only: the history still loads and refreshes
      // through the API, and the global realtime banner explains failures.
    }
  }

  /// Stops live updates when the screen closes.
  Future<void> unwatchRealtime() {
    _realtimeGeneration++;
    return _stopRealtime();
  }

  Future<void> _stopRealtime() async {
    final events = _events.toList();
    final subscription = _subscription;
    _events.clear();
    _subscription = null;
    for (final listener in events) {
      await listener.cancel();
    }
    await subscription?.close();
  }

  bool _isGeneration(int generation) =>
      ref.mounted && _generation == generation;

  bool _isCurrent(int generation, String owner) =>
      _isGeneration(generation) && _owner == owner;
}

/// Subscription API of the realtime service, replaceable in tests.
abstract interface class ChatRealtime {
  Future<RealtimeSubscription> subscribe(
    RealtimeChannel channel, {
    required Future<void> Function() reload,
  });
}

class ServiceChatRealtime implements ChatRealtime {
  ServiceChatRealtime(this._ref);

  final Ref _ref;

  @override
  Future<RealtimeSubscription> subscribe(
    RealtimeChannel channel, {
    required Future<void> Function() reload,
  }) async => _ref
      .read(realtimeServiceProvider.notifier)
      .subscribe(channel, reload: reload);
}

@Riverpod(keepAlive: true)
ChatRealtime chatRealtime(Ref ref) => ServiceChatRealtime(ref);
