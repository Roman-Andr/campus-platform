import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/realtime/realtime_channel.dart';
import '../../../core/realtime/realtime_models.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../profile/application/my_profile.dart';
import '../domain/notification_feed.dart';

part 'notifications.g.dart';

// The HTTP transport already retries transient failures. Expected API errors
// must reach the UI immediately, with an explicit retry action.
Duration? notificationsRetry(int retryCount, Object error) => null;

/// Inbox of the signed-in user: newest first, cursor pages, the read cursor
/// of the server and realtime wakeups.
///
/// The feed is the only source of the read state: it is reloaded through the
/// API after every sign-in and app start, so the unread count and the flags
/// match the server and other devices of the user.
@Riverpod(keepAlive: true, retry: notificationsRetry)
class NotificationsFeed extends _$NotificationsFeed {
  RealtimeSubscription? _subscription;
  final _events = <StreamSubscription<Object?>>[];
  bool _syncing = false;
  bool _loadingMore = false;

  /// Tells a subscription of a closed screen from one of a reopened one.
  int _realtimeGeneration = 0;

  @override
  Future<NotificationFeedState> build() async {
    final status = ref.watch(authStatusProvider).value;
    if (status != AuthenticationStatus.authenticated) {
      return const NotificationFeedState();
    }
    ref.onDispose(() {
      unawaited(_stopRealtime());
    });
    return _firstPage();
  }

  /// Loads the first page again, keeping it as the whole feed.
  Future<void> refresh() async {
    try {
      final page = await _firstPage();
      if (!ref.mounted) return;
      state = AsyncData(page);
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      if (state.value != null) rethrow;
      state = AsyncError(error, stackTrace);
    }
  }

  /// Appends the next page; the caller shows a failure of the request.
  Future<void> more() async {
    final current = state.value;
    final cursor = current?.nextPage;
    if (_loadingMore || current == null || cursor == null) return;
    _loadingMore = true;
    try {
      final page = await ref
          .read(campusApiProvider)
          .notifications
          .notificationFeed(cursor: cursor);
      if (!ref.mounted) return;
      final latest = state.value ?? current;
      state = AsyncData(
        NotificationFeedState(
          items: mergeNotifications(latest.items, page.items),
          nextPage: page.nextPage,
          unreadCount: page.unreadCount,
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Loads the notifications that arrived after the newest loaded one.
  ///
  /// This is the recovery path for a realtime gap: the personal channel only
  /// wakes the client up, and the API is the source of truth. Failing to
  /// load keeps the loaded feed: the realtime banner already reports the
  /// connection, and the next wakeup retries.
  Future<void> sync() async {
    if (_syncing) return;
    final current = await _loaded();
    if (current == null) return;
    _syncing = true;
    try {
      final page = current.items.isEmpty
          ? await _firstPage()
          : await _newerThan(current.items.first.sequence);
      if (!ref.mounted) return;
      final latest = state.value ?? current;
      state = AsyncData(
        NotificationFeedState(
          items: mergeNotifications(latest.items, page.items),
          nextPage: latest.nextPage ?? page.nextPage,
          unreadCount: page.unreadCount,
        ),
      );
    } on Object {
      // Kept as is; see the doc comment.
    } finally {
      _syncing = false;
    }
  }

  /// Marks [notification] and all earlier ones read on the server.
  ///
  /// The returned cursor is applied to the loaded pages, so the unread count
  /// follows the server exactly, including notifications not loaded yet.
  Future<void> markRead(NotificationOutput notification) async {
    final cursor = await ref
        .read(campusApiProvider)
        .notifications
        .readNotifications(body: ReadInput(throughId: notification.id));
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      NotificationFeedState(
        items: applyReadCursor(current.items, cursor.sequence),
        nextPage: current.nextPage,
        unreadCount: cursor.unreadCount,
      ),
    );
  }

  /// Marks every loaded notification read through the newest one.
  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null || current.items.isEmpty || current.unreadCount == 0) {
      return;
    }
    await markRead(current.items.first);
  }

  /// Reloads the first page without surfacing a failure.
  ///
  /// Another device advances the read cursor without creating a
  /// notification, so neither a realtime wakeup nor [sync] sees it. The
  /// screen reconciles when it returns to the foreground, and the realtime
  /// subscription does it before its first subscribe and after a recovery.
  /// A failed reload keeps the loaded feed: the next focus or wakeup retries.
  Future<void> reconcile() async {
    try {
      await refresh();
    } on Object {
      // Kept as is; see the doc comment.
    }
  }

  /// Starts live updates of the inbox while the notification screen is open.
  ///
  /// The personal channel carries only a wakeup with the notification id:
  /// every event is followed by [sync], which loads the missed records from
  /// the API, so a lost publication never loses a notification.
  Future<void> watchRealtime() async {
    if (_subscription != null) return;
    if (ref.read(authStatusProvider).value !=
        AuthenticationStatus.authenticated) {
      return;
    }
    final generation = ++_realtimeGeneration;
    try {
      final user = await ref.read(myProfileProvider.future);
      if (!ref.mounted || generation != _realtimeGeneration || user == null) {
        return;
      }
      final subscription = ref
          .read(realtimeServiceProvider.notifier)
          .subscribe(RealtimeChannel.personal(user.id), reload: reconcile);
      if (!ref.mounted || generation != _realtimeGeneration) {
        await subscription.close();
        return;
      }
      _events.add(subscription.events.listen((_) => unawaited(sync())));
      _subscription = subscription;
    } on Object {
      // Realtime is a wakeup only: the inbox works without it, and a profile
      // that could not be loaded is reported by the screens that need it.
    }
  }

  /// Stops realtime updates; the screen calls it when it closes.
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

  Future<NotificationFeedState> _firstPage() async {
    final page = await ref
        .read(campusApiProvider)
        .notifications
        .notificationFeed();
    return NotificationFeedState(
      items: mergeNotifications(const [], page.items),
      nextPage: page.nextPage,
      unreadCount: page.unreadCount,
    );
  }

  /// Every notification after [sequence], in commit order, over all pages.
  Future<NotificationFeedState> _newerThan(int sequence) async {
    final api = ref.read(campusApiProvider).notifications;
    final items = <NotificationOutput>[];
    var unreadCount = 0;
    String? cursor;
    do {
      final page = await api.notificationFeed(
        afterSequence: sequence,
        ascending: true,
        cursor: cursor,
      );
      items.addAll(page.items);
      unreadCount = page.unreadCount;
      cursor = page.nextPage;
    } while (cursor != null);
    return NotificationFeedState(items: items, unreadCount: unreadCount);
  }

  /// The current feed, or the one being loaded; null when it failed.
  Future<NotificationFeedState?> _loaded() async {
    final value = state.value;
    if (value != null) return value;
    try {
      return await future;
    } on Object {
      return null;
    }
  }
}

/// Unread notifications of the signed-in user, for the badge on the home
/// screen. Watching it starts the feed load after a cold start.
@riverpod
int unreadNotifications(Ref ref) {
  final status = ref.watch(authStatusProvider).value;
  if (status != AuthenticationStatus.authenticated) return 0;
  return ref.watch(notificationsFeedProvider).value?.unreadCount ?? 0;
}
