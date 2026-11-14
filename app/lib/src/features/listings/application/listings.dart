import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/network_status.dart';
import '../../../core/auth/auth_session.dart';
import '../data/listings_repository.dart';

part 'listings.g.dart';

// The HTTP transport already retries transient failures. Expected API errors
// must reach the UI immediately, with an explicit retry action.
Duration? listingRetry(int retryCount, Object error) => null;

@Riverpod(retry: listingRetry)
class ListingFeed extends _$ListingFeed {
  bool _loading = false;

  @override
  Future<PageListingOutput> build(Visibility area) async {
    ref.watch(authStatusProvider.select((s) => s.value));
    final online = ref.watch(networkStatusProvider);
    final owner = await ref.read(authStorageProvider).cacheNamespace();
    final cache = ref.read(listingsCacheProvider);
    final cached = await cache.load(owner, area);
    if (!online && cached != null) return cached;
    try {
      final page = await ref
          .read(campusApiProvider)
          .listings
          .listingFeed(area: area);
      await cache.save(owner, area, page);
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
    try {
      final page = await ref
          .read(campusApiProvider)
          .listings
          .listingFeed(area: area, cursor: previous.nextPage);
      final combined = PageListingOutput(
        items: {
          for (final item in [...previous.items, ...page.items]) item.id: item,
        }.values.toList(),
        nextPage: page.nextPage,
      );
      final owner = await ref.read(authStorageProvider).cacheNamespace();
      await ref.read(listingsCacheProvider).save(owner, area, combined);
      state = AsyncData(combined);
    } finally {
      _loading = false;
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
Future<PageListingOutput> ownListings(Ref ref, String? cursor) =>
    ref.watch(campusApiProvider).listings.myListings(cursor: cursor);

@Riverpod(retry: listingRetry)
Future<PageInteractionOutput> ownReservations(Ref ref, String? cursor) =>
    ref.watch(campusApiProvider).listings.myReservations(cursor: cursor);

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

/// Refresh every affected view after a successful mutation.
void refreshListings(WidgetRef ref) {
  ref.invalidate(listingFeedProvider);
  ref.invalidate(listingProvider);
  ref.invalidate(ownListingsProvider);
  ref.invalidate(ownReservationsProvider);
  ref.invalidate(incomingProvider);
  ref.invalidate(listingPhotosProvider);
}
