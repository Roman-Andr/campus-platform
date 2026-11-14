import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
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
    final headman = isHeadman(ref.watch(myProfileProvider).value);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          const NotificationsButton(),
          if (headman)
            IconButton(
              key: const Key('feed-create-publication'),
              icon: const Icon(Icons.campaign_outlined),
              tooltip: l10n.feedCreatePublication,
              onPressed: () => context.push('/publication/new'),
            ),
          IconButton(
            key: const Key('home-favorites'),
            icon: const Icon(Icons.star_border),
            tooltip: l10n.favoritesTitle,
            onPressed: () => context.push('/favorites'),
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: l10n.listingsMine,
            onPressed: () => context.push('/my-listings'),
          ),
          IconButton(
            key: const Key('home-profile'),
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: l10n.profileTitle,
            onPressed: () => context.push(AppRoutes.profile),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push(AppRoutes.settings),
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
