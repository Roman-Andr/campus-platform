import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';

/// JSON page snapshots of private views ("Мои", favorites) per account.
///
/// Rows share the feed snapshot table under a `my:` key prefix, which never
/// collides with feed areas; signing out clears the table as a whole.
abstract interface class MyCache {
  Future<Map<String, Object?>?> load(String owner, String key);
  Future<void> save(String owner, String key, Map<String, Object?> page);
}

class DriftMyCache implements MyCache {
  DriftMyCache(this.db);
  final AppDatabase db;

  static String _area(String key) => 'my:$key';

  @override
  Future<Map<String, Object?>?> load(String owner, String key) async {
    final row =
        await (db.select(db.listingFeeds)
              ..where((t) => t.owner.equals(owner) & t.area.equals(_area(key))))
            .getSingleOrNull();
    return row == null ? null : jsonDecode(row.payload) as Map<String, Object?>;
  }

  @override
  Future<void> save(String owner, String key, Map<String, Object?> page) => db
      .into(db.listingFeeds)
      .insertOnConflictUpdate(
        ListingFeedsCompanion.insert(
          owner: owner,
          area: _area(key),
          payload: jsonEncode(page),
        ),
      );
}

final myCacheProvider = Provider<MyCache>(
  (ref) => DriftMyCache(ref.watch(appDatabaseProvider)),
);
