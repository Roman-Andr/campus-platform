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

/// Dialog rows of the signed-in account, as the API returned them.
///
/// The payload is the whole `ChatOutput`, so the list opens offline with the
/// last known participants and last message. Rows are scoped by the local
/// session owner and never shown to another account.
@DataClassName('ChatDialogRow')
class ChatDialogs extends Table {
  TextColumn get owner => text()();
  TextColumn get chatId => text()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {owner, chatId};
}

/// Server messages kept per account and chat for an offline history.
///
/// The server sequence is the authoritative order; the client UUID links a
/// stored message to its outgoing queue row, so a response lost after the
/// server committed the message does not show it twice.
@DataClassName('ChatMessageRow')
class ChatMessages extends Table {
  TextColumn get owner => text()();
  TextColumn get chatId => text()();
  TextColumn get clientId => text()();
  TextColumn get serverId => text()();
  IntColumn get sequence => integer()();
  TextColumn get senderId => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {owner, chatId, clientId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {owner, chatId, sequence},
  ];
}

/// Durable outgoing queue of chat messages.
///
/// A row is written before the first attempt, so the message survives a
/// restart, a lost network and a lost response. The client UUID and the
/// idempotency key are generated once and reused by every retry. Until the
/// server confirms the message, the row stays here; a terminal refusal marks
/// it `failed` instead of pretending it was delivered.
@DataClassName('ChatOutboxRow')
class ChatOutbox extends Table {
  TextColumn get owner => text()();
  TextColumn get chatId => text()();
  TextColumn get clientId => text()();
  TextColumn get idempotencyKey => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get failure => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {owner, chatId, clientId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {owner, idempotencyKey},
  ];
}
