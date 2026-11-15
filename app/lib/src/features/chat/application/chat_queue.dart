import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, ProviderSubscription;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/network_status.dart';
import '../../../core/auth/auth_session.dart';
import '../data/chat_api.dart';
import '../data/chat_store.dart';
import '../domain/chat.dart';
import 'chat_config.dart';

part 'chat_queue.g.dart';

/// The whole outbox of the signed-in account and the messages being sent.
class ChatQueueState {
  const ChatQueueState({
    this.messages = const <OutgoingChatMessage>[],
    this.sending = const <String>{},
  });

  /// Outbox rows, oldest first, including rows refused for good.
  final List<OutgoingChatMessage> messages;

  /// Local ids (`chatId/clientId`) whose request is in flight now.
  final Set<String> sending;

  List<OutgoingChatMessage> forChat(String chatId) => [
    for (final message in messages)
      if (message.chatId == chatId) message,
  ];
}

/// Sends queued messages one at a time, in local send order per chat.
///
/// A row is persisted before the first request and removed only after the
/// server returns the stored message. The client UUID and idempotency key
/// are generated once, so a repeat after a lost response is the same
/// operation for the server. A retryable failure keeps the row pending and
/// schedules another attempt; a refusal marks it failed and never shows it
/// as delivered. No later message of the same chat overtakes an earlier one.
@Riverpod(keepAlive: true)
class ChatQueue extends _$ChatQueue {
  StreamController<MessageOutput> _delivered =
      StreamController<MessageOutput>.broadcast();
  final _sending = <String>{};
  Timer? _retryTimer;
  ChatStore? _store;
  ChatApi? _api;
  ChatConfig? _config;
  String? _owner;
  bool _draining = false;
  bool _disposed = false;
  int _retryStep = 0;
  int _generation = 0;

  /// Messages stored by the server during this session, in delivery order.
  Stream<MessageOutput> get delivered => _delivered.stream;

  @override
  Future<ChatQueueState> build() async {
    final generation = ++_generation;
    // A rebuild on a session change must not let an older in-flight drain
    // write to the new account or publish into its screen.
    _disposed = false;
    _owner = null;
    _retryTimer?.cancel();
    _sending.clear();
    if (_delivered.isClosed) {
      _delivered = StreamController<MessageOutput>.broadcast();
    }
    _store = ref.watch(chatStoreProvider);
    _api = ref.watch(chatApiProvider);
    _config = ref.watch(chatConfigProvider);

    ref.onDispose(() {
      // The callback of an older build may run after the next build has
      // started; only the current generation owns the resources.
      if (generation != _generation) return;
      _disposed = true;
      _retryTimer?.cancel();
      unawaited(_delivered.close());
    });
    ref.listen(networkStatusProvider, (_, online) {
      if (!online) return;
      _retryStep = 0;
      _retryTimer?.cancel();
      unawaited(_drain());
    });
    ref.listen(authStatusProvider, (_, next) {
      if (next.value != AuthenticationStatus.unauthenticated) return;
      // Stop a drain that is already in flight before clearing its rows: a
      // late response must not recreate data of the ended session.
      _owner = null;
      _sending.clear();
      _retryTimer?.cancel();
      // Clear eagerly: a sign-out may happen while no chat screen watches
      // the queue, and private rows must not wait for the next read.
      final store = _store;
      if (store != null) unawaited(store.clearAll());
    });

    final auth = ref.watch(authStatusProvider);
    final status = auth.value;
    if (status == null) {
      // The saved session is still being read. Keeping the durable queue
      // untouched is what lets an offline process restart resume it after
      // the session resolves.
      return const ChatQueueState();
    }
    if (status == AuthenticationStatus.unauthenticated) {
      // Only an explicitly ended session clears private data; a loading
      // auth state never does.
      await _store!.clearAll();
      return const ChatQueueState();
    }
    _owner = await ref.read(authStorageProvider).cacheNamespace();
    if (generation != _generation) return const ChatQueueState();
    final messages = await _store!.loadOutbox(_owner!);
    if (generation != _generation) return const ChatQueueState();
    final state = ChatQueueState(messages: messages);
    if (messages.isNotEmpty) {
      // The state must be visible before the first send changes it.
      unawaited(Future<void>.delayed(Duration.zero, _drain));
    }
    return state;
  }

  /// Adds [text] to the durable queue and starts sending.
  ///
  /// Throws [ChatMessageEmpty] or [ChatMessageTooLong] before writing a row,
  /// so the form can explain the problem without a failed request.
  Future<OutgoingChatMessage> send(String chatId, String text) async {
    await future;
    final config = _config!;
    if (text.trim().isEmpty) throw const ChatMessageEmpty();
    if (text.length > config.maxMessageLength) {
      throw ChatMessageTooLong(config.maxMessageLength);
    }
    final owner = _owner;
    if (owner == null) throw const ChatQueueUnauthorized();
    final now = clock.now().toUtc();
    final message = await _store!.enqueue(
      owner: owner,
      chatId: chatId,
      clientId: const Uuid().v7(),
      idempotencyKey: const Uuid().v7(),
      text: text,
      createdAt: now,
    );
    await _reload();
    unawaited(_drain());
    return message;
  }

  /// Puts a refused message back into the queue after an explicit retry.
  Future<void> retry(String chatId, String clientId) async {
    await future;
    final owner = _owner;
    if (owner == null) return;
    final message = state.value?.messages
        .where((row) => row.chatId == chatId && row.clientId == clientId)
        .firstOrNull;
    if (message == null) return;
    await _store!.retry(owner: owner, message: message);
    _retryStep = 0;
    await _reload();
    unawaited(_drain());
  }

  /// Runs the queue now; safe to call while another run is active.
  Future<void> drain() => _drain();

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    final generation = _generation;
    final owner = _owner;
    final api = _api;
    final store = _store;
    if (owner == null || api == null || store == null) return;
    if (ref.read(authStatusProvider).value !=
        AuthenticationStatus.authenticated) {
      return;
    }
    if (!ref.read(networkStatusProvider)) return;
    _draining = true;
    try {
      while (_isCurrent(owner, generation)) {
        final next = await _next(owner, store);
        if (next == null || !_isCurrent(owner, generation)) break;
        final localId = next.localId;
        _sending.add(localId);
        await _publish(owner, generation, await store.loadOutbox(owner));
        if (!_isCurrent(owner, generation)) break;
        try {
          final delivered = await api.sendMessage(
            next.chatId,
            clientId: next.clientId,
            text: next.text,
            idempotencyKey: next.idempotencyKey,
          );
          if (!_isCurrent(owner, generation)) return;
          await store.complete(
            owner: owner,
            message: next,
            delivered: delivered,
          );
          if (!_isCurrent(owner, generation)) return;
          _retryStep = 0;
          _retryTimer?.cancel();
          if (!_delivered.isClosed) _delivered.add(delivered);
          _sending.remove(localId);
          await _publish(owner, generation, await store.loadOutbox(owner));
        } on Object catch (error) {
          if (!_isCurrent(owner, generation)) return;
          _sending.remove(localId);
          final failure = _classify(error);
          if (failure.retryable) {
            await store.markAttempt(
              owner: owner,
              message: next,
              failure: failure.failure,
            );
            if (!_isCurrent(owner, generation)) return;
            await _publish(owner, generation, await store.loadOutbox(owner));
            _scheduleRetry(failure.retryAfter);
            break;
          }
          await store.fail(
            owner: owner,
            message: next,
            failure: failure.failure,
          );
          if (!_isCurrent(owner, generation)) return;
          await _publish(owner, generation, await store.loadOutbox(owner));
          // The refused row blocks its chat but not other dialogs.
        }
      }
    } finally {
      _draining = false;
      // A rebuild may have happened while the old request was in flight;
      // its new account or session now gets its own drain.
      if (!_disposed &&
          _generation != generation &&
          _owner != null &&
          !_draining) {
        unawaited(_drain());
      }
    }
  }

  bool _isCurrent(String owner, int generation) =>
      !_disposed && _owner == owner && _generation == generation;

  /// The oldest pending row whose chat has no earlier blocked row.
  Future<OutgoingChatMessage?> _next(String owner, ChatStore store) async {
    final ordered = await store.loadOutbox(owner);
    final byChat = <String, List<OutgoingChatMessage>>{};
    for (final message in ordered) {
      byChat.putIfAbsent(message.chatId, () => []).add(message);
    }
    final heads = <OutgoingChatMessage>[];
    for (final rows in byChat.values) {
      final head = rows.first;
      if (head.state == OutgoingChatState.pending) heads.add(head);
    }
    if (heads.isEmpty) return null;
    heads.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.clientId.compareTo(b.clientId);
    });
    return heads.first;
  }

  void _scheduleRetry(Duration? requested) {
    _retryTimer?.cancel();
    if (_disposed) return;
    final generation = _generation;
    final delays = _config?.retryDelays ?? const <Duration>[];
    final delay = requested ?? (delays.isEmpty ? null : delays[_retryStep]);
    if (delay == null) return;
    if (requested == null && _retryStep < delays.length - 1) _retryStep++;
    _retryTimer = Timer(delay, () {
      if (!_disposed && _generation == generation) unawaited(_drain());
    });
  }

  ({OutgoingChatFailure failure, bool retryable, Duration? retryAfter})
  _classify(Object error) {
    final apiFailure = ApiFailure.from(error);
    switch (apiFailure) {
      case NetworkFailure():
        return (
          failure: OutgoingChatFailure.network,
          retryable: true,
          retryAfter: null,
        );
      case CancelledFailure():
        return (
          failure: OutgoingChatFailure.unexpected,
          retryable: false,
          retryAfter: null,
        );
      case UnexpectedFailure():
        return (
          failure: OutgoingChatFailure.unexpected,
          retryable: true,
          retryAfter: null,
        );
      case UpdateRequiredFailure():
        return (
          failure: OutgoingChatFailure.unexpected,
          retryable: false,
          retryAfter: null,
        );
      case ProblemFailure(:final code, :final status, :final retryAfter):
        return switch (code) {
          ProblemCodeKnown(value: ProblemCodeValue.chatRateLimited) => (
            failure: OutgoingChatFailure.rateLimited,
            retryable: true,
            retryAfter: retryAfter,
          ),
          ProblemCodeKnown(value: ProblemCodeValue.chatMessageConflict) => (
            failure: OutgoingChatFailure.conflict,
            retryable: false,
            retryAfter: null,
          ),
          ProblemCodeKnown(value: ProblemCodeValue.chatForbidden) => (
            failure: OutgoingChatFailure.forbidden,
            retryable: false,
            retryAfter: null,
          ),
          ProblemCodeKnown(value: ProblemCodeValue.chatNotFound) => (
            failure: OutgoingChatFailure.notFound,
            retryable: false,
            retryAfter: null,
          ),
          ProblemCodeKnown(
            value: ProblemCodeValue.chatMessageInvalid ||
                ProblemCodeValue.validationFailed,
          ) =>
            (
              failure: OutgoingChatFailure.invalid,
              retryable: false,
              retryAfter: null,
            ),
          _ when status == 401 => (
            failure: OutgoingChatFailure.unauthorized,
            retryable: false,
            retryAfter: null,
          ),
          _ when status == 429 => (
            failure: OutgoingChatFailure.rateLimited,
            retryable: true,
            retryAfter: retryAfter,
          ),
          _ when status >= 500 => (
            failure: OutgoingChatFailure.server,
            retryable: true,
            retryAfter: null,
          ),
          _ => (
            failure: OutgoingChatFailure.unexpected,
            retryable: false,
            retryAfter: null,
          ),
        };
    }
  }

  Future<void> _reload() async {
    final owner = _owner;
    if (owner == null || _store == null) return;
    await _publish(owner, _generation, await _store!.loadOutbox(owner));
  }

  Future<void> _publish(
    String owner,
    int generation,
    List<OutgoingChatMessage> messages,
  ) async {
    if (!_isCurrent(owner, generation) || !ref.mounted) return;
    state = AsyncData(
      ChatQueueState(messages: messages, sending: {..._sending}),
    );
  }
}

/// Keeps the durable queue running for the whole signed-in app session.
///
/// The listener is started explicitly by `main` (not only by an open chat
/// screen), so saved messages are sent after a process restart and the
/// network listener is active from the first frame. The returned
/// subscription is kept by the app container; tests may close it.
ProviderSubscription<AsyncValue<ChatQueueState>> startChatQueueRuntime(
  ProviderContainer container,
) => container.listen(chatQueueProvider, (_, _) {});

/// The message text is empty; the form explains it next to the field.
class ChatMessageEmpty implements Exception {
  const ChatMessageEmpty();
}

/// The message is longer than the configured limit.
class ChatMessageTooLong implements Exception {
  const ChatMessageTooLong(this.maxLength);
  final int maxLength;
}

/// The queue has no signed-in owner; the screen is already leaving.
class ChatQueueUnauthorized implements Exception {
  const ChatQueueUnauthorized();
}
