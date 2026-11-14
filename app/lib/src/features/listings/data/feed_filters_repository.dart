import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/feed.dart';

/// Storage of the selected feed filters on this device.
abstract interface class FeedFiltersRepository {
  Future<FeedFilters> load();

  Future<void> save(FeedFilters filters);
}

/// Persists the filters in the local database, next to the other
/// device-wide preferences.
class DriftFeedFiltersRepository implements FeedFiltersRepository {
  DriftFeedFiltersRepository(this._db);

  final AppDatabase _db;

  static const _key = 'listings.feed_filters';

  @override
  Future<FeedFilters> load() async {
    final row = await (_db.select(
      _db.preferences,
    )..where((table) => table.key.equals(_key))).getSingleOrNull();
    if (row == null) return FeedFilters.none;
    try {
      return FeedFilters.fromJson(jsonDecode(row.value));
    } on FormatException {
      // A broken or foreign value must not hide the feed.
      return FeedFilters.none;
    }
  }

  @override
  Future<void> save(FeedFilters filters) => _db
      .into(_db.preferences)
      .insertOnConflictUpdate(
        PreferencesCompanion.insert(
          key: _key,
          value: jsonEncode(filters.toJson()),
        ),
      );
}

final feedFiltersRepositoryProvider = Provider<FeedFiltersRepository>(
  (ref) => DriftFeedFiltersRepository(ref.watch(appDatabaseProvider)),
);
