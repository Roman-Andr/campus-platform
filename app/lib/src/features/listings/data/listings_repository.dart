import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

/// Cache is isolated by account and area; pagination is stored atomically.
abstract interface class ListingsCache {
  Future<PageListingOutput?> load(String owner, Visibility area);
  Future<void> save(String owner, Visibility area, PageListingOutput page);
  Future<void> clear();
}

class DriftListingsCache implements ListingsCache {
  DriftListingsCache(this.db);
  final AppDatabase db;

  @override
  Future<PageListingOutput?> load(String owner, Visibility area) async {
    final row =
        await (db.select(db.listingFeeds)..where(
              (t) => t.owner.equals(owner) & t.area.equals(area.toJson()),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : PageListingOutput.fromJson(
            jsonDecode(row.payload) as Map<String, Object?>,
          );
  }

  @override
  Future<void> save(String owner, Visibility area, PageListingOutput page) => db
      .into(db.listingFeeds)
      .insertOnConflictUpdate(
        ListingFeedsCompanion.insert(
          owner: owner,
          area: area.toJson(),
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
