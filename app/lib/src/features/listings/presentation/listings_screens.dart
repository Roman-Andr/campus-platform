import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../profile/application/my_profile.dart';
import '../application/feed_filters.dart';
import '../application/listing_photo_draft.dart';
import '../application/listings.dart';
import '../domain/feed.dart';
import 'interaction_timeline_screen.dart';
import 'listing_photos.dart';
import 'my_screens.dart';
import 'publication_screen.dart';
import 'status_labels.dart';

export 'status_labels.dart';

// Compatibility for existing callers.
String listingName(AppLocalizations l, ListingStatus s) =>
    listingStatusLabel(l, s);
String interactionName(AppLocalizations l, InteractionStatus s) =>
    interactionStatusLabel(l, s);

String scopeName(AppLocalizations l, Visibility scope) => switch (scope) {
  VisibilityKnown(value: VisibilityValue.city) => l.listingsCity,
  VisibilityKnown(value: VisibilityValue.faculty) => l.profileFaculty,
  _ => l.profileDormitory,
};

/// Mutations keep the current page visible and explain Problem Details locally.
class ListingAction extends ConsumerStatefulWidget {
  const ListingAction({
    required this.label,
    required this.run,
    this.after,
    this.failureMessage = listingFailureMessage,
    this.enabled = true,
    super.key,
  });
  final String label;
  final bool enabled;
  final Future<void> Function() run;
  final VoidCallback? after;
  final String Function(AppLocalizations, Object) failureMessage;
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
                    setState(
                      () => error = widget.failureMessage(context.l10n, e),
                    );
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

  void _apply(FeedFilters filters) {
    setState(() => error = null);
    unawaited(ref.read(feedFilterSelectionProvider.notifier).apply(filters));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ref
        .watch(feedFilterSelectionProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(apiFailureMessage(l, e)),
                TextButton(
                  onPressed: () => ref.invalidate(feedFilterSelectionProvider),
                  child: Text(l.errorRetry),
                ),
              ],
            ),
          ),
          data: (filters) {
            final provider = listingFeedProvider(area);
            return Column(
              children: [
                FeedFiltersBar(
                  area: area,
                  filters: filters,
                  onAreaChanged: (value) => setState(() {
                    area = value;
                    error = null;
                  }),
                  onChanged: _apply,
                ),
                Expanded(
                  child: ref
                      .watch(provider)
                      .when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(apiFailureMessage(l, e)),
                              TextButton(
                                onPressed: () => ref.invalidate(provider),
                                child: Text(l.errorRetry),
                              ),
                            ],
                          ),
                        ),
                        data: (page) {
                          final split = splitPinned(page.items, clock.now());
                          return RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(provider);
                              await ref.read(provider.future);
                            },
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (split.pinned.isNotEmpty) ...[
                                  Padding(
                                    key: const Key('feed-pinned-header'),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      4,
                                    ),
                                    child: Text(
                                      l.feedPinned,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  for (final item in split.pinned)
                                    ListingTile(item: item),
                                  const Divider(),
                                ],
                                if (page.items.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(l.listingsEmpty),
                                  ),
                                for (final item in split.ordinary)
                                  ListingTile(item: item),
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
                                                  .read(provider.notifier)
                                                  .more();
                                            } catch (e) {
                                              if (mounted) {
                                                setState(
                                                  () => error =
                                                      apiFailureMessage(l, e),
                                                );
                                              }
                                            } finally {
                                              if (mounted) {
                                                setState(
                                                  () => loadingMore = false,
                                                );
                                              }
                                            }
                                          },
                                    child: Text(l.listingsMore),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                ),
              ],
            );
          },
        );
  }
}

/// Scope and filters above the feed; every change is kept for the next run.
class FeedFiltersBar extends ConsumerWidget {
  const FeedFiltersBar({
    required this.area,
    required this.filters,
    required this.onAreaChanged,
    required this.onChanged,
    super.key,
  });

  /// Sentinel of the "all values" item of a dropdown.
  static const _all = 'all';

  final Visibility area;
  final FeedFilters filters;
  final ValueChanged<Visibility> onAreaChanged;
  final ValueChanged<FeedFilters> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final categories =
        ref.watch(listingCategoriesProvider).value ?? const <CategoryOutput>[];
    final cityId = ref.watch(myProfileProvider).value?.cityId;
    final dormitories = cityId == null
        ? const <CityPlaceOut>[]
        : ref.watch(dormitoriesProvider(cityId)).value ??
              const <CityPlaceOut>[];
    final kind = filters.kind?.apiValue ?? _all;
    final category = categories.any((item) => item.id == filters.categoryId)
        ? filters.categoryId!
        : _all;
    final dormitory = dormitories.any((item) => item.id == filters.dormitoryId)
        ? filters.dormitoryId!
        : _all;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          DropdownButton<Visibility>(
            key: const Key('feed-filter-area'),
            value: area,
            items: [
              for (final scope in const [
                Visibility.city,
                Visibility.faculty,
                Visibility.dormitory,
              ])
                DropdownMenuItem(
                  value: scope,
                  child: Text(scopeName(l, scope)),
                ),
            ],
            onChanged: (value) {
              if (value != null) onAreaChanged(value);
            },
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            key: const Key('feed-filter-kind'),
            value: kind,
            items: [
              DropdownMenuItem(value: _all, child: Text(l.feedFilterAllKinds)),
              DropdownMenuItem(
                value: FeedKind.giveaway.apiValue,
                child: Text(l.listingKindGiveaway),
              ),
              DropdownMenuItem(
                value: FeedKind.publication.apiValue,
                child: Text(l.listingKindPublication),
              ),
            ],
            onChanged: (value) => onChanged(
              filters.withKind(
                value == null || value == _all ? null : FeedKind.fromApi(value),
              ),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            key: const Key('feed-filter-category'),
            value: category,
            items: [
              DropdownMenuItem(
                value: _all,
                child: Text(l.feedFilterAllCategories),
              ),
              for (final item in categories)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: (value) => onChanged(
              filters.withCategory(
                value == null || value == _all ? null : value,
              ),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            key: const Key('feed-filter-dormitory'),
            value: dormitory,
            items: [
              DropdownMenuItem(
                value: _all,
                child: Text(l.feedFilterAllDormitories),
              ),
              for (final item in dormitories)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: (value) => onChanged(
              filters.withDormitory(
                value == null || value == _all ? null : value,
              ),
            ),
          ),
          if (!filters.isEmpty) ...[
            const SizedBox(width: 8),
            TextButton(
              key: const Key('feed-filters-reset'),
              onPressed: () => onChanged(FeedFilters.none),
              child: Text(l.feedFiltersReset),
            ),
          ],
        ],
      ),
    );
  }
}

class ListingTile extends ConsumerWidget {
  const ListingTile({required this.item, super.key});
  final ListingOutput item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final publication = item.kind == 'publication';
    return Column(
      children: [
        ListTile(
          leading: ListingThumbnail(id: item.id),
          title: Text(item.title),
          subtitle: Text(
            '${item.authorName} · '
            '${publication ? l.listingKindPublication : listingName(l, item.status)}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPinnedAt(item, clock.now()))
                Icon(Icons.push_pin, size: 18, semanticLabel: l.feedPinned),
              FavoriteButton(listing: item),
            ],
          ),
          onTap: () => context.push('/listings/${item.id}'),
        ),
        if (item.authorId == ref.watch(myProfileProvider).value?.id &&
            (item.status == ListingStatus.draft ||
                item.status == ListingStatus.expired))
          ListingOwnerActions(item: item),
      ],
    );
  }
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
                  Text(listingFailureMessage(l, e)),
                  TextButton(
                    onPressed: () => ref.invalidate(listingProvider(id)),
                    child: Text(l.errorRetry),
                  ),
                ],
              ),
            ),
            data: (item) {
              final publication = item.kind == 'publication';
              final pinned = isPinnedAt(item, clock.now());
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListingGallery(id: id),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      FavoriteButton(listing: item),
                    ],
                  ),
                  Text(l.listingAuthor(item.authorName)),
                  if (publication)
                    Text(listingKindName(l, item.kind))
                  else
                    Text(listingName(l, item.status)),
                  if (publication && pinned) ...[
                    Text(l.feedPinned),
                    Text(
                      l.feedPinnedUntil(
                        formatCityTime(
                          item.pinnedUntil!,
                          timezone: item.cityTimezone,
                          city: item.cityTimezone,
                          l10n: l,
                          includeDate: true,
                        ),
                      ),
                    ),
                  ],
                  Text(item.description),
                  if (item.hiddenReason != null)
                    Text(l.listingHiddenReason(item.hiddenReason!)),
                  if (publication && item.authorId == user?.id)
                    PublicationActions(item: item),
                  if (!publication && item.authorId == user?.id)
                    ListingOwnerActions(item: item),
                  if (!publication && item.authorId != user?.id && user != null)
                    if (item.status == ListingStatus.active)
                      ListingAction(
                        label: l.listingReserve,
                        failureMessage: apiFailureMessage,
                        run: () async {
                          await ref
                              .read(campusApiProvider)
                              .listings
                              .reserveGiveaway(listingId: id);
                        },
                        after: () => context.push('/my-listings'),
                      ),
                  if (!publication && item.authorId == user?.id)
                    IncomingList(id: id),
                  if (!publication && user != null && item.authorId != user.id)
                    ListingParticipation(id: id),
                ],
              );
            },
          ),
    );
  }
}

class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({this.initial, super.key});
  final ListingOutput? initial;
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
  bool saving = false;
  bool savingDraft = false;

  /// Set once the listing exists, so a retry only attaches the photos.
  ListingOutput? saved;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    if (item != null) {
      title.text = item.title;
      description.text = item.description;
      scope = item.visibility;
      audience = item.audience;
      categoryId = item.categoryId;
      unawaited(_showAttachedPhotos(item.id));
    }
  }

  /// Shows the photos already attached to the listing being edited.
  Future<void> _showAttachedPhotos(String id) async {
    try {
      final photos = await ref.read(listingPhotosProvider(id).future);
      if (!mounted || ref.read(listingPhotoDraftProvider).isNotEmpty) return;
      ref.read(listingPhotoDraftProvider.notifier).attached(photos);
    } catch (_) {
      // The gallery simply starts empty; the form still works without it.
    }
  }

  Future<void> save({required bool draft}) async {
    savingDraft = draft;
    if (!form.currentState!.validate()) throw const InvalidListingForm();
    setState(() => saving = true);
    try {
      final api = ref.read(campusApiProvider);
      final item = widget.initial;
      final ListingOutput listing;
      if (item != null) {
        final current = saved ?? item;
        listing = saved = await api.listings.editListing(
          listingId: current.id,
          body: ListingEdit(
            title: title.text.trim(),
            description: description.text.trim(),
            version: current.version,
            categoryId: categoryId,
          ),
        );
      } else {
        final employee =
            ref.read(myProfileProvider).value?.accountType ==
            UserOutputAccountType.employee;
        listing = saved ??= await api.listings.publishGiveaway(
          body: GiveawayInput(
            title: title.text.trim(),
            description: description.text.trim(),
            visibility: scope,
            audience: employee ? Audience.community : audience,
            categoryId: categoryId,
            draft: draft,
          ),
        );
      }
      // Rejected and failed photos are left out; the rest attach in order.
      final photos = ref.read(listingPhotoDraftProvider.notifier).readyIds;
      if (photos.isNotEmpty) {
        await api.photos.setListingPhotos(
          listingId: listing.id,
          body: PhotoOrder(fileIds: photos),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

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
      appBar: AppBar(
        title: Text(
          widget.initial == null ? l.listingCreate : l.listingEditDraft,
        ),
      ),
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
                          (savingDraft && value == null) ||
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
                  if (user?.facultyId != null ||
                      widget.initial?.visibility == Visibility.faculty)
                    Visibility.faculty,
                  if (user?.dormitoryId != null &&
                          user?.accountType == UserOutputAccountType.student ||
                      widget.initial?.visibility == Visibility.dormitory)
                    Visibility.dormitory,
                ])
                  DropdownMenuItem(value: s, child: Text(scopeName(l, s))),
              ],
              onChanged: widget.initial != null
                  ? null
                  : (v) => setState(() => scope = v!),
            ),
            DropdownButtonFormField<Audience>(
              key: ValueKey(
                'audience-${user?.accountType}-${widget.initial?.id}',
              ),
              initialValue: user?.accountType == UserOutputAccountType.employee
                  ? Audience.community
                  : audience,
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
              onChanged:
                  widget.initial != null ||
                      user == null ||
                      user.accountType == UserOutputAccountType.employee
                  ? null
                  : (v) => setState(() => audience = v!),
            ),
            const ListingPhotosField(),
            if (photosBusy) Text(l.photoWait),
            if (widget.initial == null)
              ListingAction(
                label: l.listingPublish,
                enabled:
                    !saving &&
                    !photosBusy &&
                    user != null &&
                    (categories.value?.isNotEmpty ?? false),
                run: () => save(draft: false),
                after: () => context.pop(),
              ),
            ListingAction(
              label: widget.initial == null
                  ? l.listingSaveDraft
                  : l.listingSaveChanges,
              enabled: !saving && !photosBusy && user != null,
              run: () => save(draft: true),
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

class ReservationTile extends ConsumerWidget {
  const ReservationTile({required this.item, super.key});
  final InteractionOutput item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(listingProvider(item.listingId));
    return Column(
      children: [
        ListTile(
          title: Text(listing.value?.title ?? context.l10n.listingDetails),
          subtitle: InteractionStatusText(item: item),
          onTap: () => context.push('/listings/${item.listingId}'),
        ),
        TimelineButton(item: item),
        ParticipantCancel(item: item),
      ],
    );
  }
}

/// Lets the participant withdraw a pending or accepted interaction.
class ParticipantCancel extends ConsumerWidget {
  const ParticipantCancel({required this.item, super.key});
  final InteractionOutput item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.participantId != ref.watch(myProfileProvider).value?.id ||
        (item.status != InteractionStatus.pending &&
            item.status != InteractionStatus.accepted)) {
      return const SizedBox.shrink();
    }
    return ListingAction(
      label: context.l10n.reservationCancel,
      run: () async {
        await ref
            .read(campusApiProvider)
            .listings
            .transitionInteraction(
              listingId: item.listingId,
              interactionId: item.id,
              body: const TransitionInput(status: InteractionStatus.cancelled),
            );
      },
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
                    InteractionStatusText(item: item),
                    TimelineButton(item: item),
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

class ListingOwnerActions extends ConsumerWidget {
  const ListingOwnerActions({required this.item, super.key});
  final ListingOutput item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      children: [
        if (item.status == ListingStatus.draft)
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CreateListingScreen(initial: item),
              ),
            ),
            child: Text(l.listingEditDraft),
          ),
        if (item.status == ListingStatus.draft ||
            item.status == ListingStatus.expired)
          ListingAction(
            label: item.status == ListingStatus.draft
                ? l.listingPublish
                : l.listingRepublish,
            run: () async {
              await ref
                  .read(campusApiProvider)
                  .listings
                  .publishListing(listingId: item.id);
            },
          ),
        if (item.status == ListingStatus.active ||
            item.status == ListingStatus.busy)
          ListingAction(
            label: l.listingExtend,
            after: () =>
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.listingExtended))),
            run: () async {
              await ref
                  .read(campusApiProvider)
                  .listings
                  .extendListing(listingId: item.id);
            },
          ),
      ],
    );
  }
}

/// Only the rejection reason is shown; the timeline belongs to #67.
class InteractionStatusText extends ConsumerWidget {
  const InteractionStatusText({required this.item, super.key});
  final InteractionOutput item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (item.status != InteractionStatus.rejected) {
      return Text(interactionStatusLabel(l, item.status));
    }
    final provider = interactionRejectionProvider((item.listingId, item.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(interactionStatusLabel(l, item.status)),
        ref
            .watch(provider)
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => TextButton(
                onPressed: () => ref.invalidate(provider),
                child: Text(l.errorRetry),
              ),
              data: (reason) => Text(switch (reason) {
                'listing_expired' => l.reservationRejectedExpired,
                'listing_cancelled' => l.reservationRejectedClosed,
                'author_timeout' => l.reservationRejectedTimeout,
                null => l.reservationRejectedAuthor,
                _ => l.reservationRejectedOther,
              }),
            ),
      ],
    );
  }
}

String listingFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.listingConflict),
      ) =>
        l.listingTransitionConflict,
      ProblemFailure(status: 404) => l.listingUnavailable,
      _ => apiFailureMessage(l, error),
    };

class ListingParticipation extends ConsumerWidget {
  const ListingParticipation({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(listingParticipationProvider(id))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Column(
          children: [
            Text(listingFailureMessage(context.l10n, e)),
            TextButton(
              onPressed: () => ref.invalidate(listingParticipationProvider(id)),
              child: Text(context.l10n.errorRetry),
            ),
          ],
        ),
        data: (items) => Column(
          children: [for (final item in items) ReservationTile(item: item)],
        ),
      );
}
