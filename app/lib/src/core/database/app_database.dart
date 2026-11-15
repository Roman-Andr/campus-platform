import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Local SQLite database of the client: offline cache, outgoing queue and
/// device preferences.
///
/// Schema changes must bump [schemaVersion], add a step to [migration] and
/// be exported with `dart run drift_dev make-migrations` (see README).
@DriftDatabase(
  tables: [
    Preferences,
    ListingFeeds,
    ChatDialogs,
    ChatMessages,
    ChatMessageTombstones,
    ChatOutbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  static const databaseName = 'campus';

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(listingFeeds);
      if (from < 3 && to >= 3) {
        await m.createTable(chatDialogs);
        // The app first shipped chats in v3, before quotes, photos and
        // edits. Creating the current table here would put v4 columns into
        // a v3 database, so recreate the exact v3 shape and let the v4
        // step below add its columns.
        await customStatement(
          'CREATE TABLE chat_messages ('
          'owner TEXT NOT NULL, '
          'chat_id TEXT NOT NULL, '
          'client_id TEXT NOT NULL, '
          'server_id TEXT NOT NULL, '
          'sequence INTEGER NOT NULL, '
          'sender_id TEXT NOT NULL, '
          'body TEXT NOT NULL, '
          'created_at TEXT NOT NULL, '
          'PRIMARY KEY(owner, chat_id, client_id), '
          'UNIQUE(owner, chat_id, sequence))',
        );
        await customStatement(
          'CREATE TABLE chat_outbox ('
          'owner TEXT NOT NULL, '
          'chat_id TEXT NOT NULL, '
          'client_id TEXT NOT NULL, '
          'idempotency_key TEXT NOT NULL, '
          'body TEXT NOT NULL, '
          'created_at TEXT NOT NULL, '
          'attempts INTEGER NOT NULL DEFAULT 0, '
          'status TEXT NOT NULL DEFAULT \'pending\', '
          'failure TEXT NULL, '
          'PRIMARY KEY(owner, chat_id, client_id), '
          'UNIQUE(owner, idempotency_key))',
        );
      }
      if (from < 4 && to >= 4) {
        await m.createTable(chatMessageTombstones);
        // A database older than v3 was created above with the v3 shape and
        // needs these columns too; a database that started at v3 gets them
        // from this same step.
        await m.addColumn(chatMessages, chatMessages.version);
        await m.addColumn(chatMessages, chatMessages.replyToId);
        await m.addColumn(chatMessages, chatMessages.replyToPayload);
        await m.addColumn(chatMessages, chatMessages.photoIds);
        await m.addColumn(chatMessages, chatMessages.quoteRevision);
        await m.addColumn(chatOutbox, chatOutbox.replyToId);
        await m.addColumn(chatOutbox, chatOutbox.replyToPayload);
        await m.addColumn(chatOutbox, chatOutbox.quoteRevision);
        await m.addColumn(chatOutbox, chatOutbox.photoIds);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openDefault() => driftDatabase(
    name: databaseName,
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}

/// The app-wide database. Overridden with an in-memory database in tests.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
}
