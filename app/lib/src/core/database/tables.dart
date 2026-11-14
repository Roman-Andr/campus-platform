import 'package:drift/drift.dart';

/// Device-local key-value preferences such as the interface language and
/// theme. Values are stored as text; each feature owns its keys.
@DataClassName('PreferenceRow')
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Server feed snapshots, partitioned by local session and scope.
class ListingFeeds extends Table {
  TextColumn get owner => text()();
  TextColumn get area => text()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {owner, area};
}
