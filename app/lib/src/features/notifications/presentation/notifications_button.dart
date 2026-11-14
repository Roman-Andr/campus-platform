import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../application/notifications.dart';

/// Bell of the home screen with the number of unread notifications.
///
/// Watching the count starts the inbox load, so the badge is filled after a
/// cold start even before the notification screen is opened.
class NotificationsButton extends ConsumerWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final unread = ref.watch(unreadNotificationsProvider);
    return IconButton(
      key: const Key('home-notifications'),
      tooltip: l10n.notificationsTitle,
      onPressed: () => context.push(AppRoutes.notifications),
      icon: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
