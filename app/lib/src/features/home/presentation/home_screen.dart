import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../listings/domain/event.dart';
import '../../listings/domain/publication.dart';
import '../../listings/presentation/listings_screens.dart';
import '../../notifications/presentation/notifications_button.dart';
import '../../profile/application/my_profile.dart';

/// Listings feed and entry points to account and giveaway workflows.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final headman = isHeadman(user);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          const NotificationsButton(),
          if (canCreateEvent(user))
            IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              key: const Key('feed-create-event'),
              icon: const Icon(Icons.event_outlined),
              tooltip: l10n.eventCreate,
              onPressed: () => context.push('/event/new'),
            ),
          if (headman)
            IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              key: const Key('feed-create-publication'),
              icon: const Icon(Icons.campaign_outlined),
              tooltip: l10n.feedCreatePublication,
              onPressed: () => context.push('/publication/new'),
            ),
          IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            key: const Key('feed-create-skill'),
            icon: const Icon(Icons.school_outlined),
            tooltip: l10n.skillCreateTitle,
            onPressed: () => context.push('/skills/new'),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            key: const Key('feed-create-help'),
            icon: const Icon(Icons.volunteer_activism_outlined),
            tooltip: l10n.feedCreateHelp,
            onPressed: () => context.push('/help/new'),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            key: const Key('home-favorites'),
            icon: const Icon(Icons.star_border),
            tooltip: l10n.favoritesTitle,
            onPressed: () => context.push('/favorites'),
          ),
          PopupMenuButton<String>(
            key: const Key('home-menu'),
            tooltip: l10n.moreActions,
            icon: const Icon(Icons.more_vert),
            onSelected: (route) => context.push(route),
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('home-my-listings'),
                value: '/my-listings',
                child: Text(l10n.listingsMine),
              ),
              PopupMenuItem(
                key: const Key('home-profile'),
                value: AppRoutes.profile,
                child: Text(l10n.profileTitle),
              ),
              PopupMenuItem(
                key: const Key('home-settings'),
                value: AppRoutes.settings,
                child: Text(l10n.settingsTitle),
              ),
            ],
          ),
        ],
      ),
      body: const FeedBody(),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.listingCreate,
        onPressed: () => context.push('/giveaway/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
