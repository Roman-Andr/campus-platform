import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/network_status.dart';
import '../../../core/auth/auth_session.dart';
import '../data/chat_api.dart';
import '../data/chat_store.dart';

part 'chats.g.dart';

// The HTTP transport already retries transient failures. Expected API errors
// must reach the UI immediately, with an explicit retry action.
Duration? chatRetry(int retryCount, Object error) => null;

/// The first page of dialogs and the cursor of the next one.
class ChatDialogsState {
  const ChatDialogsState({this.items = const <ChatOutput>[], this.nextPage});

  final List<ChatOutput> items;
  final String? nextPage;
}

/// Dialogs of the signed-in user, the most recently active first.
///
/// The server list is the source of truth; the last loaded snapshot opens
/// offline. Rows are cached per local session, so another account never
/// sees them.
@Riverpod(keepAlive: true, retry: chatRetry)
class ChatDialogs extends _$ChatDialogs {
  String? _owner;
  bool _loadingMore = false;

  @override
  Future<ChatDialogsState> build() async {
    final status = ref.watch(authStatusProvider).value;
    if (status != AuthenticationStatus.authenticated) {
      return const ChatDialogsState();
    }
    final owner = await ref.read(authStorageProvider).cacheNamespace();
    _owner = owner;
    final cache = ref.read(chatStoreProvider);
    final cached = await cache.loadDialogs(owner);
    final online = ref.watch(networkStatusProvider);
    if (!online) {
      return ChatDialogsState(items: cached);
    }
    try {
      final page = await ref.read(chatApiProvider).listChats();
      await cache.replaceDialogs(owner, page.items);
      return ChatDialogsState(items: page.items, nextPage: page.nextPage);
    } on Object catch (error) {
      if (ApiFailure.from(error) is NetworkFailure) {
        return ChatDialogsState(items: cached);
      }
      rethrow;
    }
  }

  /// Reloads the first page, replacing the cached list.
  Future<void> refresh() async {
    final owner = _owner;
    if (owner == null) return;
    final page = await ref.read(chatApiProvider).listChats();
    await ref.read(chatStoreProvider).replaceDialogs(owner, page.items);
    if (!ref.mounted) return;
    state = AsyncData(
      ChatDialogsState(items: page.items, nextPage: page.nextPage),
    );
  }

  /// Appends the next page, without repeating a dialog.
  Future<void> more() async {
    final current = state.value;
    final cursor = current?.nextPage;
    if (_loadingMore || current == null || cursor == null) return;
    _loadingMore = true;
    try {
      final page = await ref.read(chatApiProvider).listChats(cursor: cursor);
      if (!ref.mounted) return;
      final latest = state.value ?? current;
      final byId = <String, ChatOutput>{
        for (final chat in [...latest.items, ...page.items]) chat.id: chat,
      };
      final items = byId.values.toList()
        ..sort((a, b) {
          final byTime = b.updatedAt.compareTo(a.updatedAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
      final owner = _owner;
      if (owner != null) {
        await ref.read(chatStoreProvider).upsertDialogs(owner, page.items);
      }
      if (!ref.mounted) return;
      state = AsyncData(
        ChatDialogsState(items: items, nextPage: page.nextPage),
      );
    } finally {
      _loadingMore = false;
    }
  }
}

/// One dialog of the signed-in user, with the cached copy as an offline
/// fallback. Somebody else's dialog is `404` and never appears here.
@Riverpod(retry: chatRetry)
Future<ChatOutput?> chat(Ref ref, String chatId) async {
  final status = ref.watch(authStatusProvider).value;
  if (status != AuthenticationStatus.authenticated) return null;
  final owner = await ref.read(authStorageProvider).cacheNamespace();
  final store = ref.read(chatStoreProvider);
  ChatOutput? cached;
  for (final chat in await store.loadDialogs(owner)) {
    if (chat.id == chatId) {
      cached = chat;
      break;
    }
  }
  try {
    final chat = await ref.read(chatApiProvider).readChat(chatId);
    await store.upsertDialogs(owner, [chat]);
    return chat;
  } on Object catch (error) {
    if (ApiFailure.from(error) is NetworkFailure && cached != null) {
      return cached;
    }
    rethrow;
  }
}

/// Creates a dialog from a profile or listing, or returns the stored one.
class ChatStarter {
  ChatStarter(this._ref);

  final Ref _ref;

  Future<ChatOutput> start({
    required String recipientId,
    String? listingId,
  }) async {
    final owner = await _ref.read(authStorageProvider).cacheNamespace();
    final chat = await _ref
        .read(chatApiProvider)
        .createChat(recipientId: recipientId, listingId: listingId);
    // A sign-out or account switch while the request is in flight must not
    // leave the old dialog in the cache of the next local session.
    final current = await _ref.read(authStorageProvider).cacheNamespace();
    if (current != owner) return chat;
    await _ref.read(chatStoreProvider).upsertDialogs(owner, [chat]);
    _ref.invalidate(chatDialogsProvider);
    return chat;
  }
}

@Riverpod(keepAlive: true)
ChatStarter chatStarter(Ref ref) => ChatStarter(ref);
