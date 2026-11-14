import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/notification_route.dart';
import '../../../core/time/city_time.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../profile/application/my_profile.dart';
import '../application/notifications.dart';
import '../domain/notification_feed.dart';

/// The in-app notification centre (ТЗ п. 5.1.1, модуль 7).
///
/// Newest first, newest pages on scroll and a pull-to-refresh; realtime only
/// wakes the screen up, every change is reloaded from the API.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _scroll = ScrollController();
  late final NotificationsFeed _feed;

  @override
  void initState() {
    super.initState();
    _feed = ref.read(notificationsFeedProvider.notifier);
    _scroll.addListener(_onScroll);
    unawaited(_feed.watchRealtime());
  }

  @override
  void dispose() {
    _scroll.dispose();
    unawaited(_feed.unwatchRealtime());
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter > 240) return;
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    try {
      await _feed.more();
    } on Object catch (error) {
      if (mounted) _showFailure(error);
    }
  }

  Future<void> _refresh() async {
    try {
      await _feed.refresh();
    } on Object catch (error) {
      if (mounted) _showFailure(error);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _feed.markAllRead();
    } on Object catch (error) {
      if (mounted) _showFailure(error);
    }
  }

  Future<void> _markRead(NotificationOutput notification) async {
    try {
      await _feed.markRead(notification);
    } on Object catch (error) {
      if (mounted) _showFailure(error);
    }
  }

  Future<void> _open(NotificationOutput notification) async {
    final route = notificationRoute(notification.type, notification.params);
    if (route == null) {
      _showMessage(context.l10n.notificationsNoScreen);
      return;
    }
    if (!notification.read) unawaited(_markRead(notification));
    await context.push(route);
  }

  void _showFailure(Object error) =>
      _showMessage(apiFailureMessage(context.l10n, error));

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final feed = ref.watch(notificationsFeedProvider);
    final value = feed.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
        actions: [
          IconButton(
            key: const Key('notifications-mark-all-read'),
            tooltip: l10n.notificationsMarkAllRead,
            onPressed: (value?.unreadCount ?? 0) == 0
                ? null
                : () => unawaited(_markAllRead()),
            icon: const Icon(Icons.done_all),
          ),
        ],
      ),
      body: switch (feed) {
        AsyncValue(value: final feed?) => _Body(
          feed: feed,
          user: user,
          scroll: _scroll,
          onRefresh: _refresh,
          onOpen: (notification) => unawaited(_open(notification)),
        ),
        AsyncValue(:final error?) => ApiErrorView(
          error: error,
          onRetry: () => ref.invalidate(notificationsFeedProvider),
        ),
        _ => const Center(
          key: Key('notifications-loading'),
          child: CircularProgressIndicator(),
        ),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.feed,
    required this.user,
    required this.scroll,
    required this.onRefresh,
    required this.onOpen,
  });

  final NotificationFeedState feed;
  final UserOutput? user;
  final ScrollController scroll;
  final Future<void> Function() onRefresh;
  final void Function(NotificationOutput notification) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (feed.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.notificationsEmpty,
                    key: const Key('notifications-empty'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final language = Localizations.localeOf(context).languageCode;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        key: const Key('notifications-list'),
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: feed.items.length + 1,
        itemBuilder: (context, index) {
          if (index == feed.items.length) {
            // The footer keeps the list scrollable above the pull-to-refresh
            // threshold and shows that another page is on its way.
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: feed.nextPage == null
                    ? const SizedBox.shrink()
                    : const CircularProgressIndicator(),
              ),
            );
          }
          final notification = feed.items[index];
          return _NotificationTile(
            notification: notification,
            language: language,
            user: user,
            onTap: () => onOpen(notification),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.language,
    required this.user,
    required this.onTap,
  });

  final NotificationOutput notification;
  final String language;
  final UserOutput? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey('notification-${notification.id}'),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: notification.read
            ? colors.surfaceContainerHighest
            : colors.primaryContainer,
        child: Icon(
          notificationIcon(notification.type),
          color: notification.read
              ? colors.onSurfaceVariant
              : colors.onPrimaryContainer,
        ),
      ),
      title: Text(
        notificationText(notification, language),
        style: notification.read
            ? null
            : const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(notificationTime(notification, user, l10n)),
      trailing: notification.read
          ? null
          : Icon(Icons.circle, size: 10, color: colors.primary),
    );
  }
}

/// The icon of a notification kind; unknown kinds stay generic.
IconData notificationIcon(String type) => switch (type) {
  'listing.offer' || 'listing.offer_expired' => Icons.local_offer_outlined,
  _ when type.startsWith('listing.meeting') => Icons.event_outlined,
  _ when type.startsWith('listing.waitlist') => Icons.groups_outlined,
  _ when type.startsWith('listing.event') => Icons.campaign_outlined,
  _ when type.startsWith('listing.') => Icons.inventory_2_outlined,
  _ => Icons.notifications_outlined,
};

/// The moment of [notification] in the city zone of the user (ТЗ #44).
///
/// Without a city, e.g. before the profile is filled in, the device zone is
/// the best available and needs no city annotation.
String notificationTime(
  NotificationOutput notification,
  UserOutput? user,
  AppLocalizations l10n,
) {
  final timezone = user?.cityTimezone;
  if (timezone == null) {
    return DateFormat.yMd(l10n.localeName)
        .add_Hm()
        .format(notification.occurredAt.toLocal());
  }
  return formatCityTime(
    notification.occurredAt,
    timezone: timezone,
    city: timezone,
    l10n: l10n,
    includeDate: true,
  );
}
