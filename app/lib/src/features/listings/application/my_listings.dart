import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/network_status.dart';
import '../../../core/auth/auth_session.dart';
import '../data/my_cache.dart';
import 'listings.dart';

part 'my_listings.g.dart';

/// A page of a private view; [offline] when it comes from the device cache.
class Snapshot<T> {
  const Snapshot(this.page, {this.offline = false});
  final T page;
  final bool offline;
}

/// Groups of own listings on the "Мои" screen (ТЗ п. 5.1.5).
enum MySection {
  drafts([ListingStatus.draft]),
  active([ListingStatus.active]),
  busy([ListingStatus.busy]),
  archive([
    ListingStatus.expired,
    ListingStatus.completed,
    ListingStatus.cancelled,
    ListingStatus.hidden,
  ]);

  const MySection(this.statuses);
  final List<ListingStatus> statuses;
}

/// Serves the cached page offline or when the server is unreachable;
/// otherwise fetches the first page and refreshes the cache.
Future<Snapshot<P>> _cachedFirstPage<P>(
  Ref ref,
  String key, {
  required Future<P> Function() fetch,
  required P Function(Map<String, Object?> json) decode,
  required Map<String, Object?> Function(P page) encode,
}) async {
  ref.watch(authStatusProvider.select((s) => s.value));
  final online = ref.watch(networkStatusProvider);
  final owner = await ref.read(authStorageProvider).cacheNamespace();
  final cache = ref.read(myCacheProvider);
  P? cached;
  try {
    final json = await cache.load(owner, key);
    if (json != null) cached = decode(json);
  } on Object {
    // A snapshot of an older schema is ignored and replaced.
  }
  if (!online && cached != null) return Snapshot(cached, offline: true);
  try {
    final page = await fetch();
    await cache.save(owner, key, encode(page));
    return Snapshot(page);
  } catch (error) {
    if (ApiFailure.from(error) is NetworkFailure && cached != null) {
      return Snapshot(cached, offline: true);
    }
    rethrow;
  }
}

/// Appends the next page to the loaded ones and caches the combined list.
mixin _Paged<P> {
  Ref get ref;
  AsyncValue<Snapshot<P>> get state;
  set state(AsyncValue<Snapshot<P>> value);

  bool _loading = false;
  String get cacheKey;
  String? nextOf(P page);
  Future<P> fetchAfter(String cursor);
  P merge(P loaded, P next);
  Map<String, Object?> encode(P page);

  Future<void> more() async {
    final previous = state.value;
    final cursor = previous == null ? null : nextOf(previous.page);
    if (_loading || previous == null || previous.offline || cursor == null) {
      return;
    }
    _loading = true;
    try {
      final combined = merge(previous.page, await fetchAfter(cursor));
      final owner = await ref.read(authStorageProvider).cacheNamespace();
      await ref.read(myCacheProvider).save(owner, cacheKey, encode(combined));
      state = AsyncData(Snapshot(combined));
    } finally {
      _loading = false;
    }
  }
}

@Riverpod(retry: listingRetry)
class MyListings extends _$MyListings with _Paged<PageListingOutput> {
  @override
  Future<Snapshot<PageListingOutput>> build(MySection section) =>
      _cachedFirstPage(
        ref,
        cacheKey,
        fetch: () =>
            ref.read(campusApiProvider).listings.myListings(status: _statuses),
        decode: PageListingOutput.fromJson,
        encode: encode,
      );

  List<ListingStatus> get _statuses => section.statuses;

  @override
  String get cacheKey => 'listings/${section.name}';
  @override
  String? nextOf(PageListingOutput page) => page.nextPage;
  @override
  Future<PageListingOutput> fetchAfter(String cursor) => ref
      .read(campusApiProvider)
      .listings
      .myListings(status: _statuses, cursor: cursor);
  @override
  PageListingOutput merge(PageListingOutput loaded, PageListingOutput next) =>
      PageListingOutput(
        items: {
          for (final item in [...loaded.items, ...next.items]) item.id: item,
        }.values.toList(),
        nextPage: next.nextPage,
      );
  @override
  Map<String, Object?> encode(PageListingOutput page) => page.toJson();
}

@Riverpod(retry: listingRetry)
class MyParticipation extends _$MyParticipation
    with _Paged<PageParticipationOutput> {
  @override
  Future<Snapshot<PageParticipationOutput>> build() => _cachedFirstPage(
    ref,
    cacheKey,
    fetch: () => ref.read(campusApiProvider).listings.myReservations(),
    decode: PageParticipationOutput.fromJson,
    encode: encode,
  );

  @override
  String get cacheKey => 'participation';
  @override
  String? nextOf(PageParticipationOutput page) => page.nextPage;
  @override
  Future<PageParticipationOutput> fetchAfter(String cursor) =>
      ref.read(campusApiProvider).listings.myReservations(cursor: cursor);
  @override
  PageParticipationOutput merge(
    PageParticipationOutput loaded,
    PageParticipationOutput next,
  ) => PageParticipationOutput(
    items: {
      for (final item in [...loaded.items, ...next.items]) item.id: item,
    }.values.toList(),
    nextPage: next.nextPage,
  );
  @override
  Map<String, Object?> encode(PageParticipationOutput page) => page.toJson();
}

@Riverpod(retry: listingRetry)
class Favorites extends _$Favorites with _Paged<PageFavoriteOutput> {
  @override
  Future<Snapshot<PageFavoriteOutput>> build() => _cachedFirstPage(
    ref,
    cacheKey,
    fetch: () => ref.read(campusApiProvider).listings.myFavorites(),
    decode: PageFavoriteOutput.fromJson,
    encode: encode,
  );

  @override
  String get cacheKey => 'favorites';
  @override
  String? nextOf(PageFavoriteOutput page) => page.nextPage;
  @override
  Future<PageFavoriteOutput> fetchAfter(String cursor) =>
      ref.read(campusApiProvider).listings.myFavorites(cursor: cursor);
  @override
  PageFavoriteOutput merge(
    PageFavoriteOutput loaded,
    PageFavoriteOutput next,
  ) => PageFavoriteOutput(
    items: {
      for (final item in [...loaded.items, ...next.items]) item.listingId: item,
    }.values.toList(),
    nextPage: next.nextPage,
  );
  @override
  Map<String, Object?> encode(PageFavoriteOutput page) => page.toJson();
}

/// The user's latest favorite choices, ahead of reloaded server pages.
@Riverpod(keepAlive: true)
class FavoriteMarks extends _$FavoriteMarks {
  @override
  Map<String, bool> build() {
    ref.watch(authStatusProvider.select((s) => s.value));
    return const {};
  }

  /// Whether [listing] is a favorite, taking unsynced choices into account.
  bool of(ListingOutput listing) => state[listing.id] ?? listing.favorite;

  /// Bookmarks or un-bookmarks [id]; reverts the mark if the server fails.
  Future<void> set(String id, {required bool favorite}) async {
    final previous = state[id];
    state = {...state, id: favorite};
    try {
      final api = ref.read(campusApiProvider).listings;
      await (favorite
          ? api.addFavorite(listingId: id)
          : api.removeFavorite(listingId: id));
      ref.invalidate(favoritesProvider);
    } catch (_) {
      state = {...state}..remove(id);
      if (previous != null) state = {...state, id: previous};
      rethrow;
    }
  }
}
