// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notifications.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Inbox of the signed-in user: newest first, cursor pages, the read cursor
/// of the server and realtime wakeups.
///
/// The feed is the only source of the read state: it is reloaded through the
/// API after every sign-in and app start, so the unread count and the flags
/// match the server and other devices of the user.

@ProviderFor(NotificationsFeed)
final notificationsFeedProvider = NotificationsFeedProvider._();

/// Inbox of the signed-in user: newest first, cursor pages, the read cursor
/// of the server and realtime wakeups.
///
/// The feed is the only source of the read state: it is reloaded through the
/// API after every sign-in and app start, so the unread count and the flags
/// match the server and other devices of the user.
final class NotificationsFeedProvider
    extends $AsyncNotifierProvider<NotificationsFeed, NotificationFeedState> {
  /// Inbox of the signed-in user: newest first, cursor pages, the read cursor
  /// of the server and realtime wakeups.
  ///
  /// The feed is the only source of the read state: it is reloaded through the
  /// API after every sign-in and app start, so the unread count and the flags
  /// match the server and other devices of the user.
  NotificationsFeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: notificationsRetry,
        name: r'notificationsFeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationsFeedHash();

  @$internal
  @override
  NotificationsFeed create() => NotificationsFeed();
}

String _$notificationsFeedHash() => r'ca0800c9e6c62839acad3d4711ab90284ac589f8';

/// Inbox of the signed-in user: newest first, cursor pages, the read cursor
/// of the server and realtime wakeups.
///
/// The feed is the only source of the read state: it is reloaded through the
/// API after every sign-in and app start, so the unread count and the flags
/// match the server and other devices of the user.

abstract class _$NotificationsFeed
    extends $AsyncNotifier<NotificationFeedState> {
  FutureOr<NotificationFeedState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<NotificationFeedState>, NotificationFeedState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<NotificationFeedState>,
                NotificationFeedState
              >,
              AsyncValue<NotificationFeedState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Unread notifications of the signed-in user, for the badge on the home
/// screen. Watching it starts the feed load after a cold start.

@ProviderFor(unreadNotifications)
final unreadNotificationsProvider = UnreadNotificationsProvider._();

/// Unread notifications of the signed-in user, for the badge on the home
/// screen. Watching it starts the feed load after a cold start.

final class UnreadNotificationsProvider
    extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// Unread notifications of the signed-in user, for the badge on the home
  /// screen. Watching it starts the feed load after a cold start.
  UnreadNotificationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'unreadNotificationsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$unreadNotificationsHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return unreadNotifications(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$unreadNotificationsHash() =>
    r'57d1b7fbdac5eafd724eb007243b51eda0e552b7';
