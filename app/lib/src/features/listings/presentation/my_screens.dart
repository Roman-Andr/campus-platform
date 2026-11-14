import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../profile/application/my_profile.dart';
import '../application/listings.dart';
import '../application/my_listings.dart';
import 'listings_screens.dart';

String mySectionName(AppLocalizations l, MySection section) =>
    switch (section) {
      MySection.drafts => l.mySectionDrafts,
      MySection.active => l.mySectionActive,
      MySection.busy => l.mySectionBusy,
      MySection.archive => l.listingsArchive,
    };

String listingKindName(AppLocalizations l, String kind) => switch (kind) {
  'giveaway' => l.listingKindGiveaway,
  _ => kind,
};

/// "Мои объявления и взаимодействия" (ТЗ п. 5.1.5): own listings grouped by
/// status and own participation in listings of every kind.
class MyListingsScreen extends StatelessWidget {
  const MyListingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.listingsMine),
          bottom: TabBar(
            tabs: [
              Tab(text: l.listingsOwn),
              Tab(text: l.listingsReservations),
            ],
          ),
        ),
        body: const TabBarView(
          children: [OwnListingsTab(), ParticipationTab()],
        ),
      ),
    );
  }
}

class OwnListingsTab extends ConsumerStatefulWidget {
  const OwnListingsTab({super.key});
  @override
  ConsumerState<OwnListingsTab> createState() => _OwnListingsTabState();
}

class _OwnListingsTabState extends ConsumerState<OwnListingsTab> {
  MySection section = MySection.active;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final provider = myListingsProvider(section);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final value in MySection.values)
                ChoiceChip(
                  key: Key('my-section-${value.name}'),
                  label: Text(mySectionName(l, value)),
                  selected: section == value,
                  onSelected: (_) => setState(() => section = value),
                ),
            ],
          ),
        ),
        Expanded(
          child: PagedSnapshot(
            snapshot: ref.watch(provider),
            rows: (page) => [
              for (final item in page.items) ListingTile(item: item),
            ],
            hasMore: (page) => page.nextPage != null,
            more: () => ref.read(provider.notifier).more(),
            reload: () => ref.invalidate(provider),
          ),
        ),
      ],
    );
  }
}

class ParticipationTab extends ConsumerWidget {
  const ParticipationTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PagedSnapshot(
    snapshot: ref.watch(myParticipationProvider),
    rows: (page) => [
      for (final item in page.items) ParticipationTile(item: item),
    ],
    hasMore: (page) => page.nextPage != null,
    more: () => ref.read(myParticipationProvider.notifier).more(),
    reload: () => ref.invalidate(myParticipationProvider),
  );
}

/// Own interaction with its listing, status, scenario stage and the
/// participant's cancellation; the listing summary comes with the row, so
/// it is shown offline too.
class ParticipationTile extends StatelessWidget {
  const ParticipationTile({required this.item, super.key});
  final ParticipationOutput item;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final stage = item.stage;
    final interaction = asInteraction(item);
    return Column(
      children: [
        ListTile(
          title: Text(item.listing.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  listingKindName(l, item.listing.kind),
                  if (stage != null) l.participationStage(stage),
                ].join(' · '),
              ),
              InteractionStatusText(item: interaction),
            ],
          ),
          onTap: () => context.push('/listings/${item.listing.id}'),
        ),
        ParticipantCancel(item: interaction),
      ],
    );
  }
}

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.favoritesTitle)),
      body: PagedSnapshot(
        snapshot: ref.watch(favoritesProvider),
        empty: l.favoritesEmpty,
        rows: (page) => [
          for (final item in page.items)
            if (item.listing case final listing?)
              ListingTile(item: listing)
            else
              UnavailableFavoriteTile(id: item.listingId),
        ],
        hasMore: (page) => page.nextPage != null,
        more: () => ref.read(favoritesProvider.notifier).more(),
        reload: () => ref.invalidate(favoritesProvider),
      ),
    );
  }
}

/// A bookmark whose listing was hidden, expired or left the user's area:
/// no content is shown, only the way to remove it.
class UnavailableFavoriteTile extends ConsumerWidget {
  const UnavailableFavoriteTile({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ListTile(
      key: Key('favorite-unavailable-$id'),
      leading: const Icon(Icons.block),
      title: Text(l.favoriteUnavailable),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l.favoriteRemove,
        onPressed: () => _toggle(context, ref, id, favorite: false),
      ),
    );
  }
}

/// Bookmark toggle on cards and feed rows; hidden on the user's own listings.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({required this.listing, super.key});
  final ListingOutput listing;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final me = ref.watch(myProfileProvider).value;
    if (me == null || me.id == listing.authorId) {
      return const SizedBox.shrink();
    }
    ref.watch(favoriteMarksProvider);
    final favorite = ref.read(favoriteMarksProvider.notifier).of(listing);
    return IconButton(
      key: Key('favorite-${listing.id}'),
      icon: Icon(favorite ? Icons.star : Icons.star_border),
      tooltip: favorite ? l.favoriteRemove : l.favoriteAdd,
      onPressed: () => _toggle(context, ref, listing.id, favorite: !favorite),
    );
  }
}

Future<void> _toggle(
  BuildContext context,
  WidgetRef ref,
  String id, {
  required bool favorite,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = context.l10n;
  try {
    await ref.read(favoriteMarksProvider.notifier).set(id, favorite: favorite);
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(apiFailureMessage(l, e))));
  }
}

/// A cached, paginated private list with offline, empty and error states.
class PagedSnapshot<P> extends StatefulWidget {
  const PagedSnapshot({
    required this.snapshot,
    required this.rows,
    required this.hasMore,
    required this.more,
    required this.reload,
    this.empty,
    super.key,
  });
  final AsyncValue<Snapshot<P>> snapshot;
  final List<Widget> Function(P page) rows;
  final bool Function(P page) hasMore;
  final Future<void> Function() more;
  final VoidCallback reload;
  final String? empty;
  @override
  State<PagedSnapshot<P>> createState() => _PagedSnapshotState<P>();
}

class _PagedSnapshotState<P> extends State<PagedSnapshot<P>> {
  bool loadingMore = false;
  String? error;

  Future<void> _more() async {
    final l = context.l10n;
    setState(() {
      loadingMore = true;
      error = null;
    });
    try {
      await widget.more();
    } catch (e) {
      if (mounted) setState(() => error = apiFailureMessage(l, e));
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return widget.snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(apiFailureMessage(l, e)),
            TextButton(onPressed: widget.reload, child: Text(l.errorRetry)),
          ],
        ),
      ),
      data: (snapshot) {
        final rows = widget.rows(snapshot.page);
        return RefreshIndicator(
          onRefresh: () async => widget.reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (snapshot.offline)
                ListTile(
                  key: const Key('my-offline'),
                  leading: const Icon(Icons.cloud_off),
                  title: Text(l.savedCopy),
                ),
              if (rows.isEmpty)
                ListTile(title: Text(widget.empty ?? l.listingsEmpty)),
              ...rows,
              if (error != null) Text(error!),
              if (!snapshot.offline && widget.hasMore(snapshot.page))
                TextButton(
                  onPressed: loadingMore ? null : _more,
                  child: Text(l.listingsMore),
                ),
            ],
          ),
        );
      },
    );
  }
}
