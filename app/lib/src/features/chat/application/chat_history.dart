import 'dart:async';
import 'dart:math' as math;

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
    this.olderBefore,
    this.syncError,
  });

  /// Ordered by the server sequence, oldest first.
  final List<MessageOutput> messages;

  /// Cursor of the next older page; null when the beginning is loaded.
  final String? nextPage;

  /// In jump mode the sequence below which older messages are requested.
  /// The server cursor belongs to the newest-first query, so jumping to an
  /// old hit uses an explicit sequence boundary instead.
  final int? olderBefore;

  /// A realtime wakeup could not load the gap; the loaded messages stay and
  /// the screen offers a retry instead of silently dropping the event.
  final Object? syncError;
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
  static const _jumpBefore = 20;

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
    final olderBefore = current?.olderBefore;
    if (owner == null ||
        store == null ||
        _loadingOlder ||
        current == null ||
        (cursor == null && (olderBefore == null || olderBefore <= 1))) {
      return;
    }
    _loadingOlder = true;
    try {
      final page = cursor != null
          ? await ref.read(chatApiProvider).listMessages(chatId, cursor: cursor)
          : await ref
                .read(chatApiProvider)
                .listMessages(
                  chatId,
                  afterSequence: math.max(0, olderBefore! - _jumpBefore - 1),
                  ascending: true,
                  size: _jumpBefore,
                );
      if (!_isCurrent(generation, owner)) return;
      final items = cursor != null
          ? page.items
          : page.items
                .where((message) => message.sequence < olderBefore!)
                .toList();
      await store.saveMessages(owner, chatId, items);
      if (!_isCurrent(generation, owner)) return;
      final latest = state.value ?? current;
      final merged = mergeMessages(latest.messages, items);
      final oldest = merged.isEmpty ? null : merged.first.sequence;
      state = AsyncData(
        ChatHistoryState(
          messages: merged,
          nextPage: cursor != null ? page.nextPage : null,
          olderBefore: cursor != null
              ? latest.olderBefore
              : (items.isNotEmpty && oldest != null && oldest > 1
                    ? oldest
                    : null),
          syncError: latest.syncError,
        ),
      );
    } finally {
      if (_generation == generation) _loadingOlder = false;
    }
  }

  /// Loads the context around a search hit and makes it the visible place.
  ///
  /// The history API has no "around" cursor: an ascending page after
  /// ``sequence - _jumpBefore`` gives at least the requested message while
  /// keeping the response bounded. The page replaces the newest-first older
  /// cursor with [ChatHistoryState.olderBefore], so "show earlier" keeps
  /// working from the loaded context.
  Future<void> openAt(int sequence) async {
    final generation = _generation;
    final owner = _owner;
    final store = _store;
    final current = state.value;
    if (owner == null || store == null || current == null) return;
    final lower = math.max(0, sequence - _jumpBefore);
    final page = await ref
        .read(chatApiProvider)
        .listMessages(
          chatId,
          afterSequence: lower,
          ascending: true,
          size: _jumpBefore * 2 + 1,
        );
    if (!_isCurrent(generation, owner)) return;
    if (!page.items.any((message) => message.sequence == sequence)) {
      throw const ChatMessageContextUnavailable();
    }
    final messages = mergeMessages(current.messages, page.items);
    await store.saveMessages(owner, chatId, messages);
    if (!_isCurrent(generation, owner)) return;
    final latest = state.value ?? current;
    final loaded = mergeMessages(latest.messages, messages);
    final oldest = page.items.isEmpty ? null : page.items.first.sequence;
    state = AsyncData(
      ChatHistoryState(
        messages: loaded,
        olderBefore: oldest != null && oldest > 1 ? oldest : null,
        syncError: latest.syncError,
      ),
    );
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
    // A new attempt invalidates the previous failure banner. If this attempt
    // fails again, _syncFromEvent restores the error after the request.
    if (current.syncError != null) {
      state = AsyncData(
        ChatHistoryState(
          messages: current.messages,
          nextPage: current.nextPage,
          olderBefore: current.olderBefore,
        ),
      );
    }
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
    await store.saveMessages(owner, chatId, loaded);
    if (!_isCurrent(generation, owner)) return;
    // Another page or a delivered message may have landed while the rows
    // were being saved. Re-read the state so this result extends it instead
    // of publishing the snapshot captured before the await.
    final latest = state.value ?? current;
    state = AsyncData(
      ChatHistoryState(
        messages: mergeMessages(latest.messages, loaded),
        // A request after the newest message never replaces the older
        // cursor; only the initial load adds one.
        nextPage: latest.nextPage ?? olderCursor,
        olderBefore: latest.olderBefore,
        syncError: latest.syncError,
      ),
    );
  }

  Future<void> _syncFromEvent() async {
    final generation = _generation;
    try {
      await sync();
    } on Object catch (error) {
      if (!_isGeneration(generation)) return;
      final current = state.value;
      if (current == null) return;
      state = AsyncData(
        ChatHistoryState(
          messages: current.messages,
          nextPage: current.nextPage,
          olderBefore: current.olderBefore,
          syncError: error,
        ),
      );
    }
  }

  /// Retries the realtime gap load from the stale-state banner.
  Future<void> retrySync() => _syncFromEvent();

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
    // Keep an older page or a newer sync result that landed during the save;
    // `current` is only the fallback when the provider was disposed.
    final latest = state.value ?? current;
    state = AsyncData(
      ChatHistoryState(
        messages: mergeMessages(latest?.messages ?? const [], [message]),
        nextPage: latest?.nextPage,
        olderBefore: latest?.olderBefore,
        syncError: latest?.syncError,
      ),
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
        reload: _syncFromEvent,
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

/// The search hit is no longer in the visible history (for example, it was
/// deleted between the search response and opening the chat).
class ChatMessageContextUnavailable implements Exception {
  const ChatMessageContextUnavailable();
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
