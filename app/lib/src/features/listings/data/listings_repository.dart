import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

/// Cache is isolated by account and feed key; pagination is stored atomically.
///
/// A feed key is a scope plus the applied filters, so a filtered feed never
/// shows the snapshot of another selection.
abstract interface class ListingsCache {
  Future<PageListingOutput?> load(String owner, String key);
  Future<void> save(String owner, String key, PageListingOutput page);
  Future<void> clear();
}

class DriftListingsCache implements ListingsCache {
  DriftListingsCache(this.db);
  final AppDatabase db;

  @override
  Future<PageListingOutput?> load(String owner, String key) async {
    final row =
        await (db.select(db.listingFeeds)
              ..where((t) => t.owner.equals(owner) & t.area.equals(key)))
            .getSingleOrNull();
    if (row == null) return null;
    final json = jsonDecode(row.payload) as Map<String, Object?>;
    // Snapshots written before shared mechanics lack the new nullable fields.
    final items = (json['items']! as List<Object?>)
        .cast<Map<String, Object?>>();
    return PageListingOutput.fromJson({
      ...json,
      'items': [
        for (final item in items)
          {
            'category_id': null,
            'hidden_reason': null,
            'archived_at': null,
            'purged_at': null,
            ...item,
          },
      ],
    });
  }

  @override
  Future<void> save(String owner, String key, PageListingOutput page) => db
      .into(db.listingFeeds)
      .insertOnConflictUpdate(
        ListingFeedsCompanion.insert(
          owner: owner,
          area: key,
          payload: jsonEncode(page.toJson()),
        ),
      );

  @override
  Future<void> clear() => db.delete(db.listingFeeds).go();
}

final listingsCacheProvider = Provider<ListingsCache>((ref) {
  final cache = DriftListingsCache(ref.watch(appDatabaseProvider));
  ref.listen(authStatusProvider, (_, next) {
    if (next.value == AuthenticationStatus.unauthenticated) {
      unawaited(cache.clear());
    }
  });
  return cache;
});
