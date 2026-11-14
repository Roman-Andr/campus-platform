import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../profile/application/my_profile.dart';
import '../application/listings.dart';
import '../application/my_listings.dart';
import '../application/waitlist.dart';
import '../domain/help.dart';
import '../domain/skills.dart';
import 'interaction_timeline_screen.dart';
import 'lesson_widgets.dart';
import 'listings_screens.dart';
import 'meeting_screen.dart';
import 'waitlist_widgets.dart';

String mySectionName(AppLocalizations l, MySection section) =>
    switch (section) {
      MySection.drafts => l.mySectionDrafts,
      MySection.active => l.mySectionActive,
      MySection.busy => l.mySectionBusy,
      MySection.archive => l.listingsArchive,
    };

String listingKindName(AppLocalizations l, String kind) => switch (kind) {
  'giveaway' => l.listingKindGiveaway,
  'skill' => l.listingKindSkill,
  'publication' => l.listingKindPublication,
  'event' => l.listingKindEvent,
  'help' => l.listingKindHelp,
  _ => kind,
};

/// "Мои объявления и взаимодействия" (ТЗ п. 5.1.5): own listings grouped by
/// status, own participation in listings of every kind, and active queues and
/// place offers (ТЗ п. 5.1.1, модуль 4, пп. 9, 14).
class MyListingsScreen extends StatelessWidget {
  const MyListingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.listingsMine),
          bottom: TabBar(
            tabs: [
              Tab(text: l.listingsOwn),
              Tab(text: l.listingsReservations),
              Tab(text: l.listingsQueue),
            ],
          ),
        ),
        body: const TabBarView(
          children: [OwnListingsTab(), ParticipationTab(), WaitlistTab()],
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

/// Active queues and place offers of the user, offers first.
class WaitlistTab extends ConsumerWidget {
  const WaitlistTab({super.key});

  static int _order(WaitlistStatus status) =>
      status == WaitlistStatus.offered ? 0 : 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return PagedSnapshot(
      snapshot: ref.watch(myWaitlistProvider),
      empty: l.waitlistEmpty,
      rows: (page) {
        final active = page.items.where(
          (item) => waitlistIsActive(item.status),
        );
        final entries = active.toList()
          ..sort((a, b) {
            final byStatus = _order(a.status).compareTo(_order(b.status));
            return byStatus != 0
                ? byStatus
                : b.createdAt.compareTo(a.createdAt);
          });
        final offers = [
          for (final item in entries)
            if (item.status == WaitlistStatus.offered) item,
        ];
        final queues = [
          for (final item in entries)
            if (item.status == WaitlistStatus.waiting) item,
        ];
        return [
          if (offers.isNotEmpty) _MySectionHeader(text: l.offerSection),
          for (final item in offers) WaitlistEntryTile(entry: item),
          if (queues.isNotEmpty) _MySectionHeader(text: l.waitlistSection),
          for (final item in queues) WaitlistEntryTile(entry: item),
        ];
      },
      hasMore: (page) => page.nextPage != null,
      more: () => ref.read(myWaitlistProvider.notifier).more(),
      reload: () => ref.invalidate(myWaitlistProvider),
    );
  }
}

class _MySectionHeader extends StatelessWidget {
  const _MySectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
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
        TimelineButton(item: interaction),
        MeetingSummary(
          item: interaction,
          timezone: item.listing.cityTimezone,
          city: item.listing.cityTimezone,
        ),
        if (item.listing.kind == helpKind) ...[
          if (interaction.executor)
            Text(
              l.helpYouAreExecutor,
              key: Key('help-executor-${interaction.id}'),
            ),
          if (interaction.status == InteractionStatus.pending &&
              item.listing.status == ListingStatus.busy)
            Text(
              l.helpReserveNotice,
              key: Key('help-reserve-${interaction.id}'),
            ),
        ],
        if (item.listing.kind == skillKind)
          _SkillLessonActions(item: interaction),
        ParticipantCancel(item: interaction),
      ],
    );
  }
}

/// Lesson options and the repeat action of a skill row in "My participation";
/// the full listing carries the author and the time zone.
class _SkillLessonActions extends ConsumerWidget {
  const _SkillLessonActions({required this.item});

  final InteractionOutput item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(listingProvider(item.listingId))
      .when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (listing) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.status == InteractionStatus.pending)
              LessonOptionsCard(item: item, listing: listing),
            LessonRepeatButton(item: item, listing: listing),
          ],
        ),
      );
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
