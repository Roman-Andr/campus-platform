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
import 'chat_queue.dart';
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
/// a publication carries the action, the server sequence and the version,
/// never the text. A `created` or `edited` publication is resolved by one
/// history request at that sequence, so an edit of an old message is found
/// even though it keeps its sequence. A `deleted` publication removes the
/// row and the stored quote snapshots of it. When publications were missed
/// (a reconnect, a return from the background, an exhausted Centrifugo
/// history, an offline period), every stored message of the loaded window
/// is refetched and compared, so a deleted or edited old message cannot
/// stay in Drift, a quote or the UI.
@Riverpod(retry: chatRetry)
class ChatHistory extends _$ChatHistory {
  static const _jumpBefore = 20;
  static const _pageSize = 100;

  String? _owner;
  ChatStore? _store;
  bool _loadingOlder = false;
  bool _syncing = false;
  bool _syncRequested = false;
  int _generation = 0;
  int _realtimeGeneration = 0;
  RealtimeSubscription? _subscription;
  final _events = <StreamSubscription<Object?>>[];

  /// Serialized reconciliation of realtime publications.
  bool _fullRequested = false;
  final _pendingEvents = <Map<String, Object?>>[];
  Completer<void>? _reconcile;

  @override
  Future<ChatHistoryState> build(String chatId) async {
    final generation = ++_generation;
    _owner = null;
    _store = null;
    _loadingOlder = false;
    _syncing = false;
    _syncRequested = false;
    _fullRequested = false;
    _pendingEvents.clear();
    _reconcile = null;
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
      final quoteRevision = store.beginQuoteRequest();
      final page = await ref.read(chatApiProvider).listMessages(chatId);
      if (!_isCurrent(generation, owner)) return const ChatHistoryState();
      await store.saveMessages(
        owner,
        chatId,
        page.items,
        quoteRevision: quoteRevision,
      );
      if (!_isCurrent(generation, owner)) return const ChatHistoryState();
      // The newest page refreshes only its own rows. The rest of the cached
      // window may have been edited or deleted while the app was away, so
      // it is reconciled against the server before the screen opens.
      if (cached.isNotEmpty) {
        await _reconcileStored(generation, owner, cached);
        if (!_isCurrent(generation, owner)) return const ChatHistoryState();
        await _refreshDialog(generation, owner, notify: false);
        if (!_isCurrent(generation, owner)) return const ChatHistoryState();
      }
      final messages = await store.loadMessages(owner, chatId);
      if (!_isCurrent(generation, owner)) return const ChatHistoryState();
      return ChatHistoryState(messages: messages, nextPage: page.nextPage);
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
      final quoteRevision = store.beginQuoteRequest();
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
      await store.saveMessages(
        owner,
        chatId,
        items,
        quoteRevision: quoteRevision,
      );
      if (!_isCurrent(generation, owner)) return;
      final latest = state.value ?? current;
      final messages = await store.loadMessages(owner, chatId);
      if (!_isCurrent(generation, owner)) return;
      final oldest = items.isEmpty ? null : items.first.sequence;
      state = AsyncData(
        ChatHistoryState(
          messages: messages,
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
    final quoteRevision = store.beginQuoteRequest();
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
    await store.saveMessages(
      owner,
      chatId,
      page.items,
      quoteRevision: quoteRevision,
    );
    if (!_isCurrent(generation, owner)) return;
    final latest = state.value ?? current;
    final messages = await store.loadMessages(owner, chatId);
    if (!_isCurrent(generation, owner)) return;
    final oldest = page.items.isEmpty ? null : page.items.first.sequence;
    state = AsyncData(
      ChatHistoryState(
        messages: messages,
        olderBefore: oldest != null && oldest > 1 ? oldest : null,
        syncError: latest.syncError,
      ),
    );
  }

  /// Fetches every message after the newest loaded sequence.
  ///
  /// This is the fast path for a new message and the recovery path of the
  /// upper bound of the window. Pages are requested by sequence, not by
  /// time, so a late message is inserted at its server position and
  /// nothing is skipped or repeated. A wakeup that arrives while a request
  /// is in flight is coalesced into one more pass instead of being dropped.
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
    _clearSyncError();
    final api = ref.read(chatApiProvider);
    final quoteRevision = store.beginQuoteRequest();
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
    await store.saveMessages(
      owner,
      chatId,
      loaded,
      quoteRevision: quoteRevision,
    );
    if (!_isCurrent(generation, owner)) return;
    // Another page or a delivered message may have landed while the rows
    // were being saved. Re-read the store so this result extends the latest
    // state instead of publishing the snapshot captured before the await.
    final latest = state.value ?? current;
    final messages = await store.loadMessages(owner, chatId);
    if (!_isCurrent(generation, owner)) return;
    state = AsyncData(
      ChatHistoryState(
        messages: messages,
        // A request after the newest message never replaces the older
        // cursor; only the initial load adds one.
        nextPage: latest.nextPage ?? olderCursor,
        olderBefore: latest.olderBefore,
        syncError: latest.syncError,
      ),
    );
  }

  Future<void> _syncFromEvent() async {
    await _scheduleReconcile(full: true);
  }

  /// Retries the realtime gap load from the stale-state banner.
  Future<void> retrySync() => _syncFromEvent();

  /// A revision of the current history state for a request that is about to
  /// start. Pass it to [applyMessage] so a reply cannot restore an older
  /// quote snapshot.
  int beginQuoteRequest() => _store?.beginQuoteRequest() ?? 0;

  /// Applies a message returned by an edit or a delivery of our own outbox.
  Future<void> applyMessage(MessageOutput message, {int? quoteRevision}) async {
    final generation = _generation;
    final owner = _owner;
    final store = _store;
    if (owner == null || store == null || !_isCurrent(generation, owner)) {
      return;
    }
    await store.saveMessages(owner, chatId, [
      message,
    ], quoteRevision: quoteRevision);
    if (!_isCurrent(generation, owner)) return;
    // A concurrent deletion may have tombstoned this row between the
    // response and the write; a quote must never be restored from a row the
    // store rejected.
    final stored = (await store.loadMessages(
      owner,
      chatId,
    )).where((row) => row.id == message.id).firstOrNull;
    if (!_isCurrent(generation, owner)) return;
    await _syncQuotes(generation, owner, {
      message.id: stored == null ? null : chatQuoteOf(stored),
    });
    if (!_isCurrent(generation, owner)) return;
    await _publishFromStore(generation, owner);
    await _refreshDialog(generation, owner);
  }

  /// Applies a deletion made by this device without waiting for a wakeup.
  Future<void> removeMessage(
    String id, {
    int? sequence,
    int version = 0,
  }) async {
    final generation = _generation;
    final owner = _owner;
    final store = _store;
    if (owner == null || store == null || !_isCurrent(generation, owner)) {
      return;
    }
    if (sequence == null) {
      await store.removeMessages(owner, chatId, serverIds: [id]);
    } else {
      await store.markDeleted(
        owner,
        chatId,
        messageId: id,
        sequence: sequence,
        version: version,
      );
    }
    if (!_isCurrent(generation, owner)) return;
    await _syncQuotes(generation, owner, {id: null});
    if (!_isCurrent(generation, owner)) return;
    await _publishFromStore(generation, owner);
    await _refreshDialog(generation, owner);
  }

  /// Reloads the dialog list row after an edit, a deletion or a new message.
  Future<void> refreshDialog() async {
    final generation = _generation;
    final owner = _owner;
    if (owner == null) return;
    await _refreshDialog(generation, owner);
  }

  /// Applies a message delivered by our own outbox without another request.
  /// A delivery was already written atomically by the queue. Re-applying
  /// it must not replace a quote that the target edit refreshed meanwhile.
  Future<void> mergeDelivered(MessageOutput message) =>
      applyMessage(message, quoteRevision: 0);

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
        subscription.events.listen((event) => unawaited(_onEvent(event))),
      );
      _subscription = subscription;
    } on Object {
      // Realtime is a wakeup only: the history still loads and refreshes
      // through the API, and the global realtime banner explains failures.
    }
  }

  /// Handles a publication: the payload itself never carries message text.
  Future<void> _onEvent(RealtimeEvent event) async {
    final data = event.data;
    if (data is Map<String, Object?>) {
      await _scheduleReconcile(event: data);
    } else {
      await _scheduleReconcile(full: true);
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

  /// Serializes publications and full reconciliations into one pass.
  ///
  /// A publication that arrives during an in-flight request is queued, not
  /// lost; a full reconciliation requested meanwhile subsumes the queued
  /// events, because it compares every stored message anyway.
  Future<void> _scheduleReconcile({
    Map<String, Object?>? event,
    bool full = false,
  }) {
    if (full) {
      _fullRequested = true;
    } else if (event != null) {
      _pendingEvents.add(event);
    }
    final running = _reconcile;
    if (running != null) return running.future;
    final completer = Completer<void>();
    _reconcile = completer;
    unawaited(_runReconcile(completer));
    return completer.future;
  }

  Future<void> _runReconcile(Completer<void> done) async {
    final generation = _generation;
    try {
      while (_isGeneration(generation)) {
        if (_fullRequested) {
          _fullRequested = false;
          _pendingEvents.clear();
          _clearSyncError();
          final owner = _owner;
          final current = state.value;
          if (owner == null || current == null) break;
          if (current.messages.isEmpty) {
            await _syncOnce(generation);
          } else {
            await _reconcileStored(generation, owner, current.messages);
            if (!_isCurrent(generation, owner)) break;
            await _refreshDialog(generation, owner);
            if (!_isCurrent(generation, owner)) break;
            await _publishFromStore(generation, owner);
          }
          continue;
        }
        if (_pendingEvents.isEmpty) break;
        _clearSyncError();
        final events = _pendingEvents.toList();
        _pendingEvents.clear();
        for (final event in events) {
          if (!_isGeneration(generation)) break;
          final owner = _owner;
          if (owner == null) break;
          await _applyEvent(generation, owner, event);
        }
      }
    } on Object catch (error) {
      if (_isGeneration(generation)) _setSyncError(error);
    } finally {
      if (identical(_reconcile, done)) _reconcile = null;
      if (!done.isCompleted) done.complete();
      if (_isGeneration(generation) &&
          (_fullRequested || _pendingEvents.isNotEmpty)) {
        unawaited(_scheduleReconcile());
      }
    }
  }

  /// Resolves one metadata-only publication with one history request.
  ///
  /// The server cannot return a message by id; the first visible message at
  /// or after its sequence is enough because sequences are unique and never
  /// reused. If that row has another sequence, the published message has
  /// been deleted (for example an edit followed by a delete).
  Future<void> _applyEvent(
    int generation,
    String owner,
    Map<String, Object?> event,
  ) async {
    final action = event['action'];
    final sequence = _intOf(event['sequence']);
    final messageId = event['message_id'];
    final version = _intOf(event['version']);
    if (action is! String ||
        sequence == null ||
        messageId is! String ||
        (action != 'created' && action != 'edited' && action != 'deleted')) {
      // A legacy publication without metadata (for example a queued wakeup
      // from before the action contract) only says that this chat changed.
      // New rows after the loaded window are invisible to a window-only
      // reconcile, so fetch them first, then compare the old window.
      await _syncOnce(generation);
      if (!_isCurrent(generation, owner)) return;
      await _reconcileStored(
        generation,
        owner,
        state.value?.messages ?? const [],
      );
      if (!_isCurrent(generation, owner)) return;
      await _refreshDialog(generation, owner);
      if (!_isCurrent(generation, owner)) return;
      await _publishFromStore(generation, owner);
      return;
    }
    final known = state.value?.messages ?? const <MessageOutput>[];
    final local = known.where((message) => message.id == messageId).firstOrNull;
    if (action == 'deleted') {
      await _store!.markDeleted(
        owner,
        chatId,
        messageId: messageId,
        sequence: sequence,
        version: version ?? local?.version ?? 0,
      );
      if (!_isCurrent(generation, owner)) return;
      await _syncQuotes(generation, owner, {messageId: null});
      if (!_isCurrent(generation, owner)) return;
      await _refreshDialog(generation, owner);
      if (!_isCurrent(generation, owner)) return;
      await _publishFromStore(generation, owner);
      return;
    }
    // A repeated or late publication of an already newer row changes
    // nothing and must not downgrade the text back to an older version.
    if (local != null && version != null && local.version >= version) return;
    final quoteRevision = _store!.beginQuoteRequest();
    final page = await ref
        .read(chatApiProvider)
        .listMessages(
          chatId,
          afterSequence: math.max(0, sequence - 1),
          ascending: true,
          size: 1,
        );
    if (!_isCurrent(generation, owner)) return;
    final fetched = page.items
        .where((message) => message.sequence == sequence)
        .firstOrNull;
    if (fetched != null && local != null && fetched.version < local.version) {
      // A stale read (for example a request that started before this edit)
      // is not proof of deletion: the monotonic store guard keeps the newer
      // row, and the event carries no authority to erase it.
      return;
    }
    if (fetched == null) {
      // Absence is only evidence of deletion for a row this device already
      // holds. Without a local row the read may simply have raced a new
      // publication, and a tombstone would block that message forever.
      if (local == null) return;
      await _store!.markDeleted(
        owner,
        chatId,
        messageId: messageId,
        sequence: sequence,
        version: version ?? local.version,
      );
      if (!_isCurrent(generation, owner)) return;
      await _syncQuotes(generation, owner, {messageId: null});
    } else {
      await _store!.saveMessages(owner, chatId, [
        fetched,
      ], quoteRevision: quoteRevision);
      if (!_isCurrent(generation, owner)) return;
      final kept = (await _store!.loadMessages(
        owner,
        chatId,
      )).where((message) => message.id == fetched.id).firstOrNull;
      if (!_isCurrent(generation, owner)) return;
      if (kept == null) {
        // A deletion won the race; do not resurrect the text as a quote.
        await _syncQuotes(generation, owner, {messageId: null});
      } else if (kept.version <= fetched.version) {
        await _syncQuotes(generation, owner, {fetched.id: chatQuoteOf(kept)});
      } else {
        return;
      }
    }
    if (!_isCurrent(generation, owner)) return;
    await _refreshDialog(generation, owner);
    if (!_isCurrent(generation, owner)) return;
    await _publishFromStore(generation, owner);
  }

  /// Refetches every visible message of the loaded window and compares it.
  ///
  /// Sequences are only assigned to new messages, so the window is walked
  /// from its oldest row. A stored row missing from the response was
  /// deleted; a returned row with a greater version replaced its text.
  Future<void> _reconcileStored(
    int generation,
    String owner,
    List<MessageOutput> known,
  ) async {
    if (known.isEmpty) return;
    // A search jump leaves the loaded window sparse: replaying every
    // sequence between its first and last row could walk an entire chat.
    // Only contiguous clusters (a gap of at most one page is still nearby)
    // are fetched, so the work is bounded by what the device actually keeps.
    final clusters = <List<MessageOutput>>[];
    for (final message in known) {
      final cluster = clusters.isEmpty ? null : clusters.last;
      if (cluster == null ||
          message.sequence - cluster.last.sequence > _pageSize) {
        clusters.add([message]);
      } else {
        cluster.add(message);
      }
    }
    final fetched = <MessageOutput>[];
    final api = ref.read(chatApiProvider);
    final quoteRevision = _store!.beginQuoteRequest();
    for (final cluster in clusters) {
      var after = math.max(0, cluster.first.sequence - 1);
      final newest = cluster.last.sequence;
      while (true) {
        final page = await api.listMessages(
          chatId,
          afterSequence: after,
          ascending: true,
          size: _pageSize,
        );
        if (!_isCurrent(generation, owner)) return;
        fetched.addAll(page.items);
        if (page.items.isEmpty ||
            page.items.last.sequence >= newest ||
            page.nextPage == null) {
          break;
        }
        after = page.items.last.sequence;
      }
    }
    if (!_isCurrent(generation, owner)) return;
    final fetchedIds = {for (final message in fetched) message.id};
    final removed = [
      for (final message in known)
        if (!fetchedIds.contains(message.id)) message,
    ];
    if (removed.isNotEmpty) {
      await _store!.removeMessages(
        owner,
        chatId,
        serverIds: [for (final message in removed) message.id],
      );
      if (!_isCurrent(generation, owner)) return;
    }
    await _store!.saveMessages(
      owner,
      chatId,
      fetched,
      quoteRevision: quoteRevision,
    );
    if (!_isCurrent(generation, owner)) return;
    // A quote is a snapshot of the visible text. An edit of a quoted
    // message must replace the old snapshot in every stored reply and in a
    // pending outgoing message, without changing its wire reply_to_id.
    // The snapshots come from the stored rows, never from the response:
    // a tombstone may have rejected a stale fetched row.
    final storedById = {
      for (final message in await _store!.loadMessages(owner, chatId))
        message.id: message,
    };
    if (!_isCurrent(generation, owner)) return;
    final quotes = <String, ChatQuote?>{
      for (final message in removed) message.id: null,
    };
    for (final message in fetched) {
      final stored = storedById[message.id];
      quotes[message.id] = stored == null ? null : chatQuoteOf(stored);
    }
    await _syncQuotes(generation, owner, quotes);
  }

  /// Updates the visible quote snapshot in stored replies and in the
  /// outbox, then refreshes the queue state shown by an open dialog.
  Future<void> _syncQuotes(
    int generation,
    String owner,
    Map<String, ChatQuote?> quotes,
  ) async {
    final store = _store;
    if (store == null) return;
    for (final entry in quotes.entries) {
      await store.updateQuote(owner, chatId, entry.key, quote: entry.value);
      if (!_isCurrent(generation, owner)) return;
      await store.updateOutgoingQuote(owner, entry.key, quote: entry.value);
      if (!_isCurrent(generation, owner)) return;
    }
    await ref.read(chatQueueProvider.notifier).reloadQuotes();
  }

  /// Reloads the dialog row (last message, updated time) after a change.
  Future<void> _refreshDialog(
    int generation,
    String owner, {
    bool notify = true,
  }) async {
    final store = _store;
    if (store == null || !_isCurrent(generation, owner)) return;
    try {
      final chat = await ref.read(chatApiProvider).readChat(chatId);
      if (!_isCurrent(generation, owner)) return;
      await store.upsertDialogs(owner, [chat]);
      if (!_isCurrent(generation, owner) || !notify) return;
      ref.invalidate(chatDialogsProvider);
      ref.invalidate(chatProvider(chatId));
    } on Object {
      // The history is still correct; the next list refresh updates the row.
    }
  }

  Future<void> _publishFromStore(int generation, String owner) async {
    final store = _store;
    if (store == null) return;
    final messages = await store.loadMessages(owner, chatId);
    if (!_isCurrent(generation, owner)) return;
    final latest = state.value;
    state = AsyncData(
      ChatHistoryState(
        messages: messages,
        nextPage: latest?.nextPage,
        olderBefore: latest?.olderBefore,
        syncError: latest?.syncError,
      ),
    );
  }

  void _clearSyncError() {
    final current = state.value;
    if (current == null || current.syncError == null) return;
    state = AsyncData(
      ChatHistoryState(
        messages: current.messages,
        nextPage: current.nextPage,
        olderBefore: current.olderBefore,
      ),
    );
  }

  void _setSyncError(Object error) {
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

  int? _intOf(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : null;

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
