import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/network_status.dart';
import '../../../core/auth/auth_session.dart';
import '../data/listings_repository.dart';
import '../domain/feed.dart';
import 'feed_filters.dart';
import 'interaction_timeline.dart';
import 'my_listings.dart';
import 'waitlist.dart';

part 'listings.g.dart';

// The HTTP transport already retries transient failures. Expected API errors
// must reach the UI immediately, with an explicit retry action.
Duration? listingRetry(int retryCount, Object error) => null;

final feedSearchProvider = NotifierProvider<FeedSearch, String>(FeedSearch.new);

class FeedSearch extends Notifier<String> {
  @override
  String build() => '';
  void search(String value) => state = value.trim();
}

@Riverpod(retry: listingRetry)
class ListingFeed extends _$ListingFeed {
  bool _loading = false;
  Object? _generation;

  @override
  Future<PageListingOutput> build(Visibility area) async {
    _generation = null;
    _loading = false;
    ref.watch(authStatusProvider.select((s) => s.value));
    final search = ref.watch(feedSearchProvider);
    final online = ref.watch(networkStatusProvider);
    final filters = await ref.watch(feedFilterSelectionProvider.future);
    final owner = await ref.read(authStorageProvider).cacheNamespace();
    final cache = ref.read(listingsCacheProvider);
    final key = searchCacheKey(area, filters, search);
    final cached = await cache.load(owner, key);
    if (!online && cached != null) return cached;
    try {
      final page = await ref
          .read(campusApiProvider)
          .listings
          .listingFeed(
            area: area,
            q: search.isEmpty ? null : search,
            kind: filters.kind?.apiValue,
            categoryId: filters.categoryId,
            dormitoryId: filters.dormitoryId,
          );
      await cache.save(owner, key, page);
      return page;
    } catch (error) {
      if (ApiFailure.from(error) is NetworkFailure && cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  Future<void> more() async {
    final previous = state.value;
    if (_loading || previous == null || previous.nextPage == null) return;
    _loading = true;
    final search = ref.read(feedSearchProvider);
    final generation = Object();
    _generation = generation;
    try {
      final filters =
          ref.read(feedFilterSelectionProvider).value ?? FeedFilters.none;
      final page = await ref
          .read(campusApiProvider)
          .listings
          .listingFeed(
            area: area,
            q: search.isEmpty ? null : search,
            kind: filters.kind?.apiValue,
            categoryId: filters.categoryId,
            dormitoryId: filters.dormitoryId,
            cursor: previous.nextPage,
          );
      if (!ref.mounted || _generation != generation) return;
      final combined = PageListingOutput(
        items: {
          for (final item in [...previous.items, ...page.items]) item.id: item,
        }.values.toList(),
        nextPage: page.nextPage,
      );
      final owner = await ref.read(authStorageProvider).cacheNamespace();
      await ref
          .read(listingsCacheProvider)
          .save(owner, searchCacheKey(area, filters, search), combined);
      if (ref.mounted && _generation == generation) state = AsyncData(combined);
    } finally {
      if (_generation == generation) _loading = false;
    }
  }
}

@Riverpod(retry: listingRetry)
Future<List<CategoryOutput>> listingCategories(Ref ref) async =>
    (await ref.watch(campusApiProvider).listings.categories()).items;

@Riverpod(retry: listingRetry)
Future<ListingOutput> listing(Ref ref, String id) =>
    ref.watch(campusApiProvider).listings.getListing(listingId: id);

@Riverpod(retry: listingRetry)
Future<PageInteractionOutput> incoming(Ref ref, String id, String? cursor) =>
    ref
        .watch(campusApiProvider)
        .listings
        .listingInteractions(listingId: id, cursor: cursor);

/// Processed photos of a listing in their order. Their links are signed
/// and short-lived, so the list refreshes itself shortly before they expire.
@Riverpod(retry: listingRetry)
Future<List<PhotoOutput>> listingPhotos(Ref ref, String id) async {
  final photos =
      (await ref.watch(campusApiProvider).photos.listingPhotos(listingId: id))
          .items;
  if (photos.isNotEmpty) {
    final expires = photos
        .map((photo) => photo.expiresAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    // A skewed device clock may see the links as expired already; refetching
    // would not help then, so the list stays until the next refresh.
    final left = expires.difference(clock.now()) * 0.9;
    if (left > Duration.zero) {
      final timer = Timer(left, ref.invalidateSelf);
      ref.onDispose(timer.cancel);
    }
  }
  return photos;
}

/// A participation row as the plain interaction shared with other views.
InteractionOutput asInteraction(ParticipationOutput item) =>
    InteractionOutput.fromJson(item.toJson());

/// Refresh every affected view after a successful mutation.
void refreshListings(WidgetRef ref) {
  ref.invalidate(listingFeedProvider);
  ref.invalidate(listingProvider);
  ref.invalidate(myListingsProvider);
  ref.invalidate(myParticipationProvider);
  ref.invalidate(favoritesProvider);
  ref.invalidate(incomingProvider);
  ref.invalidate(listingPhotosProvider);
  ref.invalidate(interactionReasonProvider);
  ref.invalidate(listingParticipationProvider);
  ref.invalidate(interactionTimelineProvider);
  ref.invalidate(myWaitlistProvider);
  ref.invalidate(myWaitlistEntryProvider);
  ref.invalidate(exchangeOffersProvider);
}

/// Every offer of an exchange listing: all of them for the author, only the
/// caller's own offer otherwise (the server decides).
final exchangeOffersProvider = FutureProvider.autoDispose
    .family<List<InteractionOutput>, String>((ref, listingId) async {
      final page = await ref
          .watch(campusApiProvider)
          .listings
          .exchangeOffers(listingId: listingId);
      return page.items;
    }, retry: listingRetry);

/// The latest reason why an interaction was rejected, cancelled or closed;
/// the reason itself is written on the closing event.
final interactionReasonProvider = FutureProvider.autoDispose
    .family<String?, (String, String)>((ref, ids) async {
      final api = ref.watch(campusApiProvider).listings;
      String? cursor;
      String? reason;
      do {
        final page = await api.interactionEvents(
          listingId: ids.$1,
          interactionId: ids.$2,
          cursor: cursor,
        );
        for (final event in page.items) {
          if (event.reason == null) continue;
          if (event.status == 'rejected' || event.status == 'cancelled') {
            reason = event.reason;
          }
        }
        cursor = page.nextPage;
      } while (cursor != null);
      return reason;
    }, retry: listingRetry);

/// The API exposes participation by account; collect matching rows across pages.
final listingParticipationProvider = FutureProvider.autoDispose
    .family<List<InteractionOutput>, String>((ref, id) async {
      final api = ref.watch(campusApiProvider).listings;
      final items = <InteractionOutput>[];
      String? cursor;
      do {
        final page = await api.myReservations(cursor: cursor);
        items.addAll(
          page.items.where((item) => item.listingId == id).map(asInteraction),
        );
        cursor = page.nextPage;
      } while (cursor != null);
      return items;
    }, retry: listingRetry);
