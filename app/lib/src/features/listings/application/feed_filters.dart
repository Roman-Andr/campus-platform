import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/feed_filters_repository.dart';
import '../domain/feed.dart';

part 'feed_filters.g.dart';

/// Feed filters selected by the user, restored on the next app start.
@Riverpod(keepAlive: true)
class FeedFilterSelection extends _$FeedFilterSelection {
  /// A choice made while the stored value is still loading; it wins.
  FeedFilters? _selected;

  @override
  Future<FeedFilters> build() async {
    FeedFilters stored;
    try {
      stored = await ref.watch(feedFiltersRepositoryProvider).load();
    } on Object {
      // Storage trouble falls back to the unfiltered feed.
      stored = FeedFilters.none;
    }
    return _selected ?? stored;
  }

  /// Applies the choice in memory at once and writes it for the next start.
  Future<void> apply(FeedFilters filters) async {
    _selected = filters;
    state = AsyncData(filters);
    try {
      await ref.read(feedFiltersRepositoryProvider).save(filters);
    } on Object {
      // The choice still applies until the app closes; the next one retries.
    }
  }
}
