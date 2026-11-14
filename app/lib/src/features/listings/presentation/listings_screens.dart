import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../profile/application/my_profile.dart';
import '../application/listing_photo_draft.dart';
import '../application/listings.dart';
import 'listing_photos.dart';

String scopeName(AppLocalizations l, Visibility scope) => switch (scope) {
  VisibilityKnown(value: VisibilityValue.city) => l.listingsCity,
  VisibilityKnown(value: VisibilityValue.faculty) => l.profileFaculty,
  _ => l.profileDormitory,
};

String interactionName(AppLocalizations l, InteractionStatus status) =>
    switch (status) {
      InteractionStatusKnown(value: InteractionStatusValue.pending) =>
        l.reservationPending,
      InteractionStatusKnown(value: InteractionStatusValue.accepted) =>
        l.reservationAccepted,
      InteractionStatusKnown(value: InteractionStatusValue.rejected) =>
        l.reservationRejected,
      InteractionStatusKnown(value: InteractionStatusValue.cancelled) =>
        l.reservationCancelled,
      InteractionStatusKnown(value: InteractionStatusValue.completed) =>
        l.listingCompleted,
      InteractionStatusKnown(value: InteractionStatusValue.noShow) =>
        l.reservationNoShow,
      _ => l.listingStatusUnknown,
    };

String listingName(AppLocalizations l, ListingStatus status) =>
    switch (status) {
      ListingStatusKnown(value: ListingStatusValue.active) => l.listingActive,
      ListingStatusKnown(value: ListingStatusValue.busy) => l.listingBusy,
      ListingStatusKnown(value: ListingStatusValue.expired) => l.listingExpired,
      ListingStatusKnown(value: ListingStatusValue.cancelled) =>
        l.reservationCancelled,
      ListingStatusKnown(value: ListingStatusValue.draft) => l.listingDraft,
      ListingStatusKnown(value: ListingStatusValue.completed) =>
        l.listingCompleted,
      ListingStatusKnown(value: ListingStatusValue.hidden) => l.listingHidden,
      _ => l.listingStatusUnknown,
    };

/// Mutations keep the current page visible and explain Problem Details locally.
class ListingAction extends ConsumerStatefulWidget {
  const ListingAction({
    required this.label,
    required this.run,
    this.after,
    this.enabled = true,
    super.key,
  });
  final String label;
  final bool enabled;
  final Future<void> Function() run;
  final VoidCallback? after;
  @override
  ConsumerState<ListingAction> createState() => _ListingActionState();
}

class _ListingActionState extends ConsumerState<ListingAction> {
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (error != null) Text(error!, key: const Key('listing-error')),
      FilledButton(
        onPressed: busy || !widget.enabled
            ? null
            : () async {
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  await widget.run();
                  if (!mounted) return;
                  refreshListings(ref);
                  widget.after?.call();
                } on InvalidListingForm {
                  // Field validators already explain what to fix.
                } catch (e) {
                  if (mounted) {
                    setState(() => error = apiFailureMessage(context.l10n, e));
                  }
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(widget.label),
      ),
    ],
  );
}

class FeedBody extends ConsumerStatefulWidget {
  const FeedBody({super.key});
  @override
  ConsumerState<FeedBody> createState() => _FeedBodyState();
}

class _FeedBodyState extends ConsumerState<FeedBody> {
  Visibility area = Visibility.city;
  String? error;
  bool loadingMore = false;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final feed = ref.watch(listingFeedProvider(area));
    return Column(
      children: [
        DropdownButton<Visibility>(
          value: area,
          onChanged: (value) => setState(() {
            area = value!;
            error = null;
          }),
          items: [
            for (final scope in [
              Visibility.city,
              Visibility.faculty,
              Visibility.dormitory,
            ])
              DropdownMenuItem(value: scope, child: Text(scopeName(l, scope))),
          ],
        ),
        Expanded(
          child: feed.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(apiFailureMessage(l, e)),
                  TextButton(
                    onPressed: () => ref.invalidate(listingFeedProvider(area)),
                    child: Text(l.errorRetry),
                  ),
                ],
              ),
            ),
            data: (page) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(listingFeedProvider(area));
                await ref.read(listingFeedProvider(area).future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (page.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l.listingsEmpty),
                    ),
                  for (final item in page.items) ListingTile(item: item),
                  if (error != null) Text(error!),
                  if (page.nextPage != null)
                    TextButton(
                      onPressed: loadingMore
                          ? null
                          : () async {
                              setState(() {
                                loadingMore = true;
                                error = null;
                              });
                              try {
                                await ref
                                    .read(listingFeedProvider(area).notifier)
                                    .more();
                              } catch (e) {
                                if (mounted) {
                                  setState(
                                    () => error = apiFailureMessage(l, e),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => loadingMore = false);
                                }
                              }
                            },
                      child: Text(l.listingsMore),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ListingTile extends StatelessWidget {
  const ListingTile({required this.item, super.key});
  final ListingOutput item;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: ListingThumbnail(id: item.id),
    title: Text(item.title),
    subtitle: Text(
      '${item.authorName} · ${listingName(context.l10n, item.status)}',
    ),
    onTap: () => context.push('/listings/${item.id}'),
  );
}

class ListingScreen extends ConsumerWidget {
  const ListingScreen({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.listingDetails)),
      body: ref
          .watch(listingProvider(id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(apiFailureMessage(l, e)),
                  TextButton(
                    onPressed: () => ref.invalidate(listingProvider(id)),
                    child: Text(l.errorRetry),
                  ),
                ],
              ),
            ),
            data: (item) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListingGallery(id: id),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(l.listingAuthor(item.authorName)),
                Text(listingName(l, item.status)),
                Text(item.description),
                if (item.authorId != user?.id && user != null)
                  if (item.status == ListingStatus.active)
                    ListingAction(
                      label: l.listingReserve,
                      run: () async {
                        await ref
                            .read(campusApiProvider)
                            .listings
                            .reserveGiveaway(listingId: id);
                      },
                      after: () => context.push('/my-listings'),
                    ),
                if (item.authorId == user?.id) IncomingList(id: id),
              ],
            ),
          ),
    );
  }
}

class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key});
  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  Visibility scope = Visibility.city;
  Audience audience = Audience.students;
  String? categoryId;

  /// Set once the listing exists, so a retry only attaches the photos.
  ListingOutput? published;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final categories = ref.watch(listingCategoriesProvider);
    final photosBusy = ref.watch(
      listingPhotoDraftProvider.select((slots) => slots.any((s) => s.busy)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.listingCreate)),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            categories.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Column(
                children: [
                  Text(apiFailureMessage(l, error)),
                  TextButton(
                    onPressed: () => ref.invalidate(listingCategoriesProvider),
                    child: Text(l.errorRetry),
                  ),
                ],
              ),
              data: (items) => items.isEmpty
                  ? Text(l.listingCategoriesEmpty)
                  : DropdownButtonFormField<String>(
                      key: const Key('listing-category'),
                      initialValue: items.any((item) => item.id == categoryId)
                          ? categoryId
                          : null,
                      decoration: InputDecoration(labelText: l.listingCategory),
                      items: [
                        for (final item in items)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                      ],
                      validator: (value) =>
                          items.any((item) => item.id == value)
                          ? null
                          : l.profileChoose,
                      onChanged: (value) => setState(() => categoryId = value),
                    ),
            ),
            TextFormField(
              key: const Key('listing-title'),
              controller: title,
              decoration: InputDecoration(labelText: l.listingTitle),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l.signInNameRequired : null,
            ),
            TextFormField(
              key: const Key('listing-description'),
              controller: description,
              decoration: InputDecoration(labelText: l.listingDescription),
              minLines: 3,
              maxLines: null,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l.signInNameRequired : null,
            ),
            DropdownButtonFormField<Visibility>(
              initialValue: scope,
              decoration: InputDecoration(labelText: l.listingScope),
              items: [
                for (final s in [
                  Visibility.city,
                  if (user?.facultyId != null) Visibility.faculty,
                  if (user?.dormitoryId != null &&
                      user?.accountType == UserOutputAccountType.student)
                    Visibility.dormitory,
                ])
                  DropdownMenuItem(value: s, child: Text(scopeName(l, s))),
              ],
              onChanged: (v) => setState(() => scope = v!),
            ),
            DropdownButtonFormField<Audience>(
              initialValue: audience,
              decoration: InputDecoration(labelText: l.listingAudience),
              items: [
                DropdownMenuItem(
                  value: Audience.students,
                  child: Text(l.listingStudents),
                ),
                DropdownMenuItem(
                  value: Audience.community,
                  child: Text(l.listingCommunity),
                ),
              ],
              onChanged: (v) => setState(() => audience = v!),
            ),
            const ListingPhotosField(),
            if (photosBusy) Text(l.photoWait),
            ListingAction(
              label: l.listingPublish,
              enabled: (categories.value?.isNotEmpty ?? false) && !photosBusy,
              run: () async {
                if (!form.currentState!.validate()) {
                  throw const InvalidListingForm();
                }
                final listing = published ??= await ref
                    .read(campusApiProvider)
                    .listings
                    .publishGiveaway(
                      body: GiveawayInput(
                        title: title.text.trim(),
                        description: description.text.trim(),
                        visibility: scope,
                        audience: audience,
                        categoryId: categoryId,
                      ),
                    );
                // Rejected and failed photos are left out; the rest attach.
                final photos = ref
                    .read(listingPhotoDraftProvider.notifier)
                    .readyIds;
                if (photos.isNotEmpty) {
                  await ref
                      .read(campusApiProvider)
                      .photos
                      .setListingPhotos(
                        listingId: listing.id,
                        body: PhotoOrder(fileIds: photos),
                      );
                }
              },
              after: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class InvalidListingForm implements Exception {
  const InvalidListingForm();
}

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
          children: [MyPage(reservations: false), MyPage(reservations: true)],
        ),
      ),
    );
  }
}

class MyPage extends ConsumerStatefulWidget {
  const MyPage({required this.reservations, super.key});
  final bool reservations;
  @override
  ConsumerState<MyPage> createState() => _MyPageState();
}

class _MyPageState extends ConsumerState<MyPage> {
  String? cursor;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final AsyncValue<({List<Widget> rows, String? next})> page =
        widget.reservations
        ? ref
              .watch(ownReservationsProvider(cursor))
              .whenData(
                (p) => (
                  rows: [for (final i in p.items) ReservationTile(item: i)],
                  next: p.nextPage,
                ),
              )
        : ref
              .watch(ownListingsProvider(cursor))
              .whenData(
                (p) => (
                  rows: [for (final i in p.items) ListingTile(item: i)],
                  next: p.nextPage,
                ),
              );
    return page.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(apiFailureMessage(l, e)),
            TextButton(
              onPressed: () {
                ref.invalidate(ownListingsProvider);
                ref.invalidate(ownReservationsProvider);
              },
              child: Text(l.errorRetry),
            ),
          ],
        ),
      ),
      data: (data) => RefreshIndicator(
        onRefresh: () async {
          setState(() => cursor = null);
          ref.invalidate(ownListingsProvider);
          ref.invalidate(ownReservationsProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (data.rows.isEmpty) ListTile(title: Text(l.listingsEmpty)),
            ...data.rows,
            if (data.next != null)
              TextButton(
                onPressed: () => setState(() => cursor = data.next),
                child: Text(l.listingsMore),
              ),
            if (cursor != null)
              TextButton(
                onPressed: () => setState(() => cursor = null),
                child: Text(l.listingsFirst),
              ),
          ],
        ),
      ),
    );
  }
}

class ReservationTile extends ConsumerWidget {
  const ReservationTile({required this.item, super.key});
  final InteractionOutput item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(listingProvider(item.listingId));
    return ListTile(
      title: Text(listing.value?.title ?? context.l10n.listingDetails),
      subtitle: Text(interactionName(context.l10n, item.status)),
      onTap: () => context.push('/listings/${item.listingId}'),
    );
  }
}

class IncomingList extends ConsumerStatefulWidget {
  const IncomingList({required this.id, super.key});
  final String id;
  @override
  ConsumerState<IncomingList> createState() => _IncomingListState();
}

class _IncomingListState extends ConsumerState<IncomingList> {
  String? cursor;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ref
        .watch(incomingProvider(widget.id, cursor))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Column(
            children: [
              Text(apiFailureMessage(l, e)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(incomingProvider(widget.id, cursor)),
                child: Text(l.errorRetry),
              ),
            ],
          ),
          data: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.listingIncoming,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (page.items.isEmpty) Text(l.listingsEmpty),
              for (final item in page.items)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.participantName),
                    Text(interactionName(l, item.status)),
                    if (item.status == InteractionStatus.pending)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final status in [
                            InteractionStatus.accepted,
                            InteractionStatus.rejected,
                          ])
                            ListingAction(
                              label: status == InteractionStatus.accepted
                                  ? l.reservationAccept
                                  : l.reservationReject,
                              run: () async {
                                await ref
                                    .read(campusApiProvider)
                                    .listings
                                    .transitionInteraction(
                                      listingId: widget.id,
                                      interactionId: item.id,
                                      body: TransitionInput(status: status),
                                    );
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              if (page.nextPage != null)
                TextButton(
                  onPressed: () => setState(() => cursor = page.nextPage),
                  child: Text(l.listingsMore),
                ),
              if (cursor != null)
                TextButton(
                  onPressed: () => setState(() => cursor = null),
                  child: Text(l.listingsFirst),
                ),
            ],
          ),
        );
  }
}
