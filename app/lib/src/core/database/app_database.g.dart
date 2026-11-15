// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PreferencesTable extends Preferences
    with TableInfo<$PreferencesTable, PreferenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<PreferenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  PreferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PreferenceRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $PreferencesTable createAlias(String alias) {
    return $PreferencesTable(attachedDatabase, alias);
  }
}

class PreferenceRow extends DataClass implements Insertable<PreferenceRow> {
  final String key;
  final String value;
  const PreferenceRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  PreferencesCompanion toCompanion(bool nullToAbsent) {
    return PreferencesCompanion(key: Value(key), value: Value(value));
  }

  factory PreferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PreferenceRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  PreferenceRow copyWith({String? key, String? value}) =>
      PreferenceRow(key: key ?? this.key, value: value ?? this.value);
  PreferenceRow copyWithCompanion(PreferencesCompanion data) {
    return PreferenceRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PreferenceRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PreferenceRow &&
          other.key == this.key &&
          other.value == this.value);
}

class PreferencesCompanion extends UpdateCompanion<PreferenceRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const PreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PreferencesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<PreferenceRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PreferencesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return PreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ListingFeedsTable extends ListingFeeds
    with TableInfo<$ListingFeedsTable, ListingFeed> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListingFeedsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaMeta = const VerificationMeta('area');
  @override
  late final GeneratedColumn<String> area = GeneratedColumn<String>(
    'area',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [owner, area, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'listing_feeds';
  @override
  VerificationContext validateIntegrity(
    Insertable<ListingFeed> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('area')) {
      context.handle(
        _areaMeta,
        area.isAcceptableOrUnknown(data['area']!, _areaMeta),
      );
    } else if (isInserting) {
      context.missing(_areaMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {owner, area};
  @override
  ListingFeed map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ListingFeed(
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      area: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $ListingFeedsTable createAlias(String alias) {
    return $ListingFeedsTable(attachedDatabase, alias);
  }
}

class ListingFeed extends DataClass implements Insertable<ListingFeed> {
  final String owner;
  final String area;
  final String payload;
  const ListingFeed({
    required this.owner,
    required this.area,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner'] = Variable<String>(owner);
    map['area'] = Variable<String>(area);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  ListingFeedsCompanion toCompanion(bool nullToAbsent) {
    return ListingFeedsCompanion(
      owner: Value(owner),
      area: Value(area),
      payload: Value(payload),
    );
  }

  factory ListingFeed.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ListingFeed(
      owner: serializer.fromJson<String>(json['owner']),
      area: serializer.fromJson<String>(json['area']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'owner': serializer.toJson<String>(owner),
      'area': serializer.toJson<String>(area),
      'payload': serializer.toJson<String>(payload),
    };
  }

  ListingFeed copyWith({String? owner, String? area, String? payload}) =>
      ListingFeed(
        owner: owner ?? this.owner,
        area: area ?? this.area,
        payload: payload ?? this.payload,
      );
  ListingFeed copyWithCompanion(ListingFeedsCompanion data) {
    return ListingFeed(
      owner: data.owner.present ? data.owner.value : this.owner,
      area: data.area.present ? data.area.value : this.area,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ListingFeed(')
          ..write('owner: $owner, ')
          ..write('area: $area, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(owner, area, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ListingFeed &&
          other.owner == this.owner &&
          other.area == this.area &&
          other.payload == this.payload);
}

class ListingFeedsCompanion extends UpdateCompanion<ListingFeed> {
  final Value<String> owner;
  final Value<String> area;
  final Value<String> payload;
  final Value<int> rowid;
  const ListingFeedsCompanion({
    this.owner = const Value.absent(),
    this.area = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ListingFeedsCompanion.insert({
    required String owner,
    required String area,
    required String payload,
    this.rowid = const Value.absent(),
  }) : owner = Value(owner),
       area = Value(area),
       payload = Value(payload);
  static Insertable<ListingFeed> custom({
    Expression<String>? owner,
    Expression<String>? area,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (owner != null) 'owner': owner,
      if (area != null) 'area': area,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ListingFeedsCompanion copyWith({
    Value<String>? owner,
    Value<String>? area,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return ListingFeedsCompanion(
      owner: owner ?? this.owner,
      area: area ?? this.area,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (area.present) {
      map['area'] = Variable<String>(area.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ListingFeedsCompanion(')
          ..write('owner: $owner, ')
          ..write('area: $area, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatDialogsTable extends ChatDialogs
    with TableInfo<$ChatDialogsTable, ChatDialogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatDialogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [owner, chatId, updatedAt, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_dialogs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatDialogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {owner, chatId};
  @override
  ChatDialogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatDialogRow(
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $ChatDialogsTable createAlias(String alias) {
    return $ChatDialogsTable(attachedDatabase, alias);
  }
}

class ChatDialogRow extends DataClass implements Insertable<ChatDialogRow> {
  final String owner;
  final String chatId;
  final DateTime updatedAt;
  final String payload;
  const ChatDialogRow({
    required this.owner,
    required this.chatId,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner'] = Variable<String>(owner);
    map['chat_id'] = Variable<String>(chatId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  ChatDialogsCompanion toCompanion(bool nullToAbsent) {
    return ChatDialogsCompanion(
      owner: Value(owner),
      chatId: Value(chatId),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory ChatDialogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatDialogRow(
      owner: serializer.fromJson<String>(json['owner']),
      chatId: serializer.fromJson<String>(json['chatId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'owner': serializer.toJson<String>(owner),
      'chatId': serializer.toJson<String>(chatId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  ChatDialogRow copyWith({
    String? owner,
    String? chatId,
    DateTime? updatedAt,
    String? payload,
  }) => ChatDialogRow(
    owner: owner ?? this.owner,
    chatId: chatId ?? this.chatId,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  ChatDialogRow copyWithCompanion(ChatDialogsCompanion data) {
    return ChatDialogRow(
      owner: data.owner.present ? data.owner.value : this.owner,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatDialogRow(')
          ..write('owner: $owner, ')
          ..write('chatId: $chatId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(owner, chatId, updatedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatDialogRow &&
          other.owner == this.owner &&
          other.chatId == this.chatId &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class ChatDialogsCompanion extends UpdateCompanion<ChatDialogRow> {
  final Value<String> owner;
  final Value<String> chatId;
  final Value<DateTime> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const ChatDialogsCompanion({
    this.owner = const Value.absent(),
    this.chatId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatDialogsCompanion.insert({
    required String owner,
    required String chatId,
    required DateTime updatedAt,
    required String payload,
    this.rowid = const Value.absent(),
  }) : owner = Value(owner),
       chatId = Value(chatId),
       updatedAt = Value(updatedAt),
       payload = Value(payload);
  static Insertable<ChatDialogRow> custom({
    Expression<String>? owner,
    Expression<String>? chatId,
    Expression<DateTime>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (owner != null) 'owner': owner,
      if (chatId != null) 'chat_id': chatId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatDialogsCompanion copyWith({
    Value<String>? owner,
    Value<String>? chatId,
    Value<DateTime>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return ChatDialogsCompanion(
      owner: owner ?? this.owner,
      chatId: chatId ?? this.chatId,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatDialogsCompanion(')
          ..write('owner: $owner, ')
          ..write('chatId: $chatId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _replyToIdMeta = const VerificationMeta(
    'replyToId',
  );
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
    'reply_to_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToPayloadMeta = const VerificationMeta(
    'replyToPayload',
  );
  @override
  late final GeneratedColumn<String> replyToPayload = GeneratedColumn<String>(
    'reply_to_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoIdsMeta = const VerificationMeta(
    'photoIds',
  );
  @override
  late final GeneratedColumn<String> photoIds = GeneratedColumn<String>(
    'photo_ids',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quoteRevisionMeta = const VerificationMeta(
    'quoteRevision',
  );
  @override
  late final GeneratedColumn<int> quoteRevision = GeneratedColumn<int>(
    'quote_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    owner,
    chatId,
    clientId,
    serverId,
    sequence,
    senderId,
    body,
    version,
    replyToId,
    replyToPayload,
    photoIds,
    quoteRevision,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
        _replyToIdMeta,
        replyToId.isAcceptableOrUnknown(data['reply_to_id']!, _replyToIdMeta),
      );
    }
    if (data.containsKey('reply_to_payload')) {
      context.handle(
        _replyToPayloadMeta,
        replyToPayload.isAcceptableOrUnknown(
          data['reply_to_payload']!,
          _replyToPayloadMeta,
        ),
      );
    }
    if (data.containsKey('photo_ids')) {
      context.handle(
        _photoIdsMeta,
        photoIds.isAcceptableOrUnknown(data['photo_ids']!, _photoIdsMeta),
      );
    }
    if (data.containsKey('quote_revision')) {
      context.handle(
        _quoteRevisionMeta,
        quoteRevision.isAcceptableOrUnknown(
          data['quote_revision']!,
          _quoteRevisionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {owner, chatId, clientId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {owner, chatId, sequence},
  ];
  @override
  ChatMessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessageRow(
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      replyToId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_id'],
      ),
      replyToPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_payload'],
      ),
      photoIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_ids'],
      ),
      quoteRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quote_revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessageRow extends DataClass implements Insertable<ChatMessageRow> {
  final String owner;
  final String chatId;
  final String clientId;
  final String serverId;
  final int sequence;
  final String senderId;
  final String body;
  final int version;
  final String? replyToId;

  /// `QuoteOutput` of the quoted message, as returned with this message.
  final String? replyToPayload;

  /// Ready photo ids of the message, in display order, as a JSON array.
  final String? photoIds;

  /// Local revision of [replyToPayload].
  ///
  /// A reply keeps its own server version when the quoted message is edited
  /// or deleted, so a delayed page with the same version could otherwise
  /// restore the old quote text. Every authoritative quote update gets a
  /// newer local revision; a page response only replaces the snapshot when
  /// its request started after that revision.
  final int quoteRevision;
  final DateTime createdAt;
  const ChatMessageRow({
    required this.owner,
    required this.chatId,
    required this.clientId,
    required this.serverId,
    required this.sequence,
    required this.senderId,
    required this.body,
    required this.version,
    this.replyToId,
    this.replyToPayload,
    this.photoIds,
    required this.quoteRevision,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner'] = Variable<String>(owner);
    map['chat_id'] = Variable<String>(chatId);
    map['client_id'] = Variable<String>(clientId);
    map['server_id'] = Variable<String>(serverId);
    map['sequence'] = Variable<int>(sequence);
    map['sender_id'] = Variable<String>(senderId);
    map['body'] = Variable<String>(body);
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    if (!nullToAbsent || replyToPayload != null) {
      map['reply_to_payload'] = Variable<String>(replyToPayload);
    }
    if (!nullToAbsent || photoIds != null) {
      map['photo_ids'] = Variable<String>(photoIds);
    }
    map['quote_revision'] = Variable<int>(quoteRevision);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      owner: Value(owner),
      chatId: Value(chatId),
      clientId: Value(clientId),
      serverId: Value(serverId),
      sequence: Value(sequence),
      senderId: Value(senderId),
      body: Value(body),
      version: Value(version),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      replyToPayload: replyToPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToPayload),
      photoIds: photoIds == null && nullToAbsent
          ? const Value.absent()
          : Value(photoIds),
      quoteRevision: Value(quoteRevision),
      createdAt: Value(createdAt),
    );
  }

  factory ChatMessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessageRow(
      owner: serializer.fromJson<String>(json['owner']),
      chatId: serializer.fromJson<String>(json['chatId']),
      clientId: serializer.fromJson<String>(json['clientId']),
      serverId: serializer.fromJson<String>(json['serverId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      senderId: serializer.fromJson<String>(json['senderId']),
      body: serializer.fromJson<String>(json['body']),
      version: serializer.fromJson<int>(json['version']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      replyToPayload: serializer.fromJson<String?>(json['replyToPayload']),
      photoIds: serializer.fromJson<String?>(json['photoIds']),
      quoteRevision: serializer.fromJson<int>(json['quoteRevision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'owner': serializer.toJson<String>(owner),
      'chatId': serializer.toJson<String>(chatId),
      'clientId': serializer.toJson<String>(clientId),
      'serverId': serializer.toJson<String>(serverId),
      'sequence': serializer.toJson<int>(sequence),
      'senderId': serializer.toJson<String>(senderId),
      'body': serializer.toJson<String>(body),
      'version': serializer.toJson<int>(version),
      'replyToId': serializer.toJson<String?>(replyToId),
      'replyToPayload': serializer.toJson<String?>(replyToPayload),
      'photoIds': serializer.toJson<String?>(photoIds),
      'quoteRevision': serializer.toJson<int>(quoteRevision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ChatMessageRow copyWith({
    String? owner,
    String? chatId,
    String? clientId,
    String? serverId,
    int? sequence,
    String? senderId,
    String? body,
    int? version,
    Value<String?> replyToId = const Value.absent(),
    Value<String?> replyToPayload = const Value.absent(),
    Value<String?> photoIds = const Value.absent(),
    int? quoteRevision,
    DateTime? createdAt,
  }) => ChatMessageRow(
    owner: owner ?? this.owner,
    chatId: chatId ?? this.chatId,
    clientId: clientId ?? this.clientId,
    serverId: serverId ?? this.serverId,
    sequence: sequence ?? this.sequence,
    senderId: senderId ?? this.senderId,
    body: body ?? this.body,
    version: version ?? this.version,
    replyToId: replyToId.present ? replyToId.value : this.replyToId,
    replyToPayload: replyToPayload.present
        ? replyToPayload.value
        : this.replyToPayload,
    photoIds: photoIds.present ? photoIds.value : this.photoIds,
    quoteRevision: quoteRevision ?? this.quoteRevision,
    createdAt: createdAt ?? this.createdAt,
  );
  ChatMessageRow copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessageRow(
      owner: data.owner.present ? data.owner.value : this.owner,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      body: data.body.present ? data.body.value : this.body,
      version: data.version.present ? data.version.value : this.version,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      replyToPayload: data.replyToPayload.present
          ? data.replyToPayload.value
          : this.replyToPayload,
      photoIds: data.photoIds.present ? data.photoIds.value : this.photoIds,
      quoteRevision: data.quoteRevision.present
          ? data.quoteRevision.value
          : this.quoteRevision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessageRow(')
          ..write('owner: $owner, ')
          ..write('chatId: $chatId, ')
          ..write('clientId: $clientId, ')
          ..write('serverId: $serverId, ')
          ..write('sequence: $sequence, ')
          ..write('senderId: $senderId, ')
          ..write('body: $body, ')
          ..write('version: $version, ')
          ..write('replyToId: $replyToId, ')
          ..write('replyToPayload: $replyToPayload, ')
          ..write('photoIds: $photoIds, ')
          ..write('quoteRevision: $quoteRevision, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    owner,
    chatId,
    clientId,
    serverId,
    sequence,
    senderId,
    body,
    version,
    replyToId,
    replyToPayload,
    photoIds,
    quoteRevision,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessageRow &&
          other.owner == this.owner &&
          other.chatId == this.chatId &&
          other.clientId == this.clientId &&
          other.serverId == this.serverId &&
          other.sequence == this.sequence &&
          other.senderId == this.senderId &&
          other.body == this.body &&
          other.version == this.version &&
          other.replyToId == this.replyToId &&
          other.replyToPayload == this.replyToPayload &&
          other.photoIds == this.photoIds &&
          other.quoteRevision == this.quoteRevision &&
          other.createdAt == this.createdAt);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessageRow> {
  final Value<String> owner;
  final Value<String> chatId;
  final Value<String> clientId;
  final Value<String> serverId;
  final Value<int> sequence;
  final Value<String> senderId;
  final Value<String> body;
  final Value<int> version;
  final Value<String?> replyToId;
  final Value<String?> replyToPayload;
  final Value<String?> photoIds;
  final Value<int> quoteRevision;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ChatMessagesCompanion({
    this.owner = const Value.absent(),
    this.chatId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.senderId = const Value.absent(),
    this.body = const Value.absent(),
    this.version = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.replyToPayload = const Value.absent(),
    this.photoIds = const Value.absent(),
    this.quoteRevision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    required String owner,
    required String chatId,
    required String clientId,
    required String serverId,
    required int sequence,
    required String senderId,
    required String body,
    this.version = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.replyToPayload = const Value.absent(),
    this.photoIds = const Value.absent(),
    this.quoteRevision = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : owner = Value(owner),
       chatId = Value(chatId),
       clientId = Value(clientId),
       serverId = Value(serverId),
       sequence = Value(sequence),
       senderId = Value(senderId),
       body = Value(body),
       createdAt = Value(createdAt);
  static Insertable<ChatMessageRow> custom({
    Expression<String>? owner,
    Expression<String>? chatId,
    Expression<String>? clientId,
    Expression<String>? serverId,
    Expression<int>? sequence,
    Expression<String>? senderId,
    Expression<String>? body,
    Expression<int>? version,
    Expression<String>? replyToId,
    Expression<String>? replyToPayload,
    Expression<String>? photoIds,
    Expression<int>? quoteRevision,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (owner != null) 'owner': owner,
      if (chatId != null) 'chat_id': chatId,
      if (clientId != null) 'client_id': clientId,
      if (serverId != null) 'server_id': serverId,
      if (sequence != null) 'sequence': sequence,
      if (senderId != null) 'sender_id': senderId,
      if (body != null) 'body': body,
      if (version != null) 'version': version,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (replyToPayload != null) 'reply_to_payload': replyToPayload,
      if (photoIds != null) 'photo_ids': photoIds,
      if (quoteRevision != null) 'quote_revision': quoteRevision,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<String>? owner,
    Value<String>? chatId,
    Value<String>? clientId,
    Value<String>? serverId,
    Value<int>? sequence,
    Value<String>? senderId,
    Value<String>? body,
    Value<int>? version,
    Value<String?>? replyToId,
    Value<String?>? replyToPayload,
    Value<String?>? photoIds,
    Value<int>? quoteRevision,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ChatMessagesCompanion(
      owner: owner ?? this.owner,
      chatId: chatId ?? this.chatId,
      clientId: clientId ?? this.clientId,
      serverId: serverId ?? this.serverId,
      sequence: sequence ?? this.sequence,
      senderId: senderId ?? this.senderId,
      body: body ?? this.body,
      version: version ?? this.version,
      replyToId: replyToId ?? this.replyToId,
      replyToPayload: replyToPayload ?? this.replyToPayload,
      photoIds: photoIds ?? this.photoIds,
      quoteRevision: quoteRevision ?? this.quoteRevision,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (replyToPayload.present) {
      map['reply_to_payload'] = Variable<String>(replyToPayload.value);
    }
    if (photoIds.present) {
      map['photo_ids'] = Variable<String>(photoIds.value);
    }
    if (quoteRevision.present) {
      map['quote_revision'] = Variable<int>(quoteRevision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('owner: $owner, ')
          ..write('chatId: $chatId, ')
          ..write('clientId: $clientId, ')
          ..write('serverId: $serverId, ')
          ..write('sequence: $sequence, ')
          ..write('senderId: $senderId, ')
          ..write('body: $body, ')
          ..write('version: $version, ')
          ..write('replyToId: $replyToId, ')
          ..write('replyToPayload: $replyToPayload, ')
          ..write('photoIds: $photoIds, ')
          ..write('quoteRevision: $quoteRevision, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessageTombstonesTable extends ChatMessageTombstones
    with TableInfo<$ChatMessageTombstonesTable, ChatMessageTombstoneRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessageTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    owner,
    chatId,
    messageId,
    sequence,
    version,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_message_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessageTombstoneRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {owner, chatId, messageId};
  @override
  ChatMessageTombstoneRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessageTombstoneRow(
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $ChatMessageTombstonesTable createAlias(String alias) {
    return $ChatMessageTombstonesTable(attachedDatabase, alias);
  }
}

class ChatMessageTombstoneRow extends DataClass
    implements Insertable<ChatMessageTombstoneRow> {
  final String owner;
  final String chatId;
  final String messageId;
  final int sequence;
  final int version;
  final DateTime deletedAt;
  const ChatMessageTombstoneRow({
    required this.owner,
    required this.chatId,
    required this.messageId,
    required this.sequence,
    required this.version,
    required this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner'] = Variable<String>(owner);
    map['chat_id'] = Variable<String>(chatId);
    map['message_id'] = Variable<String>(messageId);
    map['sequence'] = Variable<int>(sequence);
    map['version'] = Variable<int>(version);
    map['deleted_at'] = Variable<DateTime>(deletedAt);
    return map;
  }

  ChatMessageTombstonesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessageTombstonesCompanion(
      owner: Value(owner),
      chatId: Value(chatId),
      messageId: Value(messageId),
      sequence: Value(sequence),
      version: Value(version),
      deletedAt: Value(deletedAt),
    );
  }

  factory ChatMessageTombstoneRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessageTombstoneRow(
      owner: serializer.fromJson<String>(json['owner']),
      chatId: serializer.fromJson<String>(json['chatId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      version: serializer.fromJson<int>(json['version']),
      deletedAt: serializer.fromJson<DateTime>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'owner': serializer.toJson<String>(owner),
      'chatId': serializer.toJson<String>(chatId),
      'messageId': serializer.toJson<String>(messageId),
      'sequence': serializer.toJson<int>(sequence),
      'version': serializer.toJson<int>(version),
      'deletedAt': serializer.toJson<DateTime>(deletedAt),
    };
  }

  ChatMessageTombstoneRow copyWith({
    String? owner,
    String? chatId,
    String? messageId,
    int? sequence,
    int? version,
    DateTime? deletedAt,
  }) => ChatMessageTombstoneRow(
    owner: owner ?? this.owner,
    chatId: chatId ?? this.chatId,
    messageId: messageId ?? this.messageId,
    sequence: sequence ?? this.sequence,
    version: version ?? this.version,
    deletedAt: deletedAt ?? this.deletedAt,
  );
  ChatMessageTombstoneRow copyWithCompanion(
    ChatMessageTombstonesCompanion data,
  ) {
    return ChatMessageTombstoneRow(
      owner: data.owner.present ? data.owner.value : this.owner,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      version: data.version.present ? data.version.value : this.version,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessageTombstoneRow(')
          ..write('owner: $owner, ')
          ..write('chatId: $chatId, ')
          ..write('messageId: $messageId, ')
          ..write('sequence: $sequence, ')
          ..write('version: $version, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(owner, chatId, messageId, sequence, version, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessageTombstoneRow &&
          other.owner == this.owner &&
          other.chatId == this.chatId &&
          other.messageId == this.messageId &&
          other.sequence == this.sequence &&
          other.version == this.version &&
          other.deletedAt == this.deletedAt);
}

class ChatMessageTombstonesCompanion
    extends UpdateCompanion<ChatMessageTombstoneRow> {
  final Value<String> owner;
  final Value<String> chatId;
  final Value<String> messageId;
  final Value<int> sequence;
  final Value<int> version;
  final Value<DateTime> deletedAt;
  final Value<int> rowid;
  const ChatMessageTombstonesCompanion({
    this.owner = const Value.absent(),
    this.chatId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.version = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMessageTombstonesCompanion.insert({
    required String owner,
    required String chatId,
    required String messageId,
    required int sequence,
    this.version = const Value.absent(),
    required DateTime deletedAt,
    this.rowid = const Value.absent(),
  }) : owner = Value(owner),
       chatId = Value(chatId),
       messageId = Value(messageId),
       sequence = Value(sequence),
       deletedAt = Value(deletedAt);
  static Insertable<ChatMessageTombstoneRow> custom({
    Expression<String>? owner,
    Expression<String>? chatId,
    Expression<String>? messageId,
    Expression<int>? sequence,
    Expression<int>? version,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (owner != null) 'owner': owner,
      if (chatId != null) 'chat_id': chatId,
      if (messageId != null) 'message_id': messageId,
      if (sequence != null) 'sequence': sequence,
      if (version != null) 'version': version,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMessageTombstonesCompanion copyWith({
    Value<String>? owner,
    Value<String>? chatId,
    Value<String>? messageId,
    Value<int>? sequence,
    Value<int>? version,
    Value<DateTime>? deletedAt,
    Value<int>? rowid,
  }) {
    return ChatMessageTombstonesCompanion(
      owner: owner ?? this.owner,
      chatId: chatId ?? this.chatId,
      messageId: messageId ?? this.messageId,
      sequence: sequence ?? this.sequence,
      version: version ?? this.version,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessageTombstonesCompanion(')
          ..write('owner: $owner, ')
          ..write('chatId: $chatId, ')
          ..write('messageId: $messageId, ')
          ..write('sequence: $sequence, ')
          ..write('version: $version, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatOutboxTable extends ChatOutbox
    with TableInfo<$ChatOutboxTable, ChatOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replyToIdMeta = const VerificationMeta(
    'replyToId',
  );
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
    'reply_to_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToPayloadMeta = const VerificationMeta(
    'replyToPayload',
  );
  @override
  late final GeneratedColumn<String> replyToPayload = GeneratedColumn<String>(
    'reply_to_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quoteRevisionMeta = const VerificationMeta(
    'quoteRevision',
  );
  @override
  late final GeneratedColumn<int> quoteRevision = GeneratedColumn<int>(
    'quote_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _photoIdsMeta = const VerificationMeta(
    'photoIds',
  );
  @override
  late final GeneratedColumn<String> photoIds = GeneratedColumn<String>(
    'photo_ids',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _failureMeta = const VerificationMeta(
    'failure',
  );
  @override
  late final GeneratedColumn<String> failure = GeneratedColumn<String>(
    'failure',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    owner,
    chatId,
    clientId,
    idempotencyKey,
    body,
    replyToId,
    replyToPayload,
    quoteRevision,
    photoIds,
    createdAt,
    attempts,
    status,
    failure,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
        _replyToIdMeta,
        replyToId.isAcceptableOrUnknown(data['reply_to_id']!, _replyToIdMeta),
      );
    }
    if (data.containsKey('reply_to_payload')) {
      context.handle(
        _replyToPayloadMeta,
        replyToPayload.isAcceptableOrUnknown(
          data['reply_to_payload']!,
          _replyToPayloadMeta,
        ),
      );
    }
    if (data.containsKey('quote_revision')) {
      context.handle(
        _quoteRevisionMeta,
        quoteRevision.isAcceptableOrUnknown(
          data['quote_revision']!,
          _quoteRevisionMeta,
        ),
      );
    }
    if (data.containsKey('photo_ids')) {
      context.handle(
        _photoIdsMeta,
        photoIds.isAcceptableOrUnknown(data['photo_ids']!, _photoIdsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('failure')) {
      context.handle(
        _failureMeta,
        failure.isAcceptableOrUnknown(data['failure']!, _failureMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {owner, chatId, clientId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {owner, idempotencyKey},
  ];
  @override
  ChatOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatOutboxRow(
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      replyToId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_id'],
      ),
      replyToPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_payload'],
      ),
      quoteRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quote_revision'],
      )!,
      photoIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_ids'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      failure: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure'],
      ),
    );
  }

  @override
  $ChatOutboxTable createAlias(String alias) {
    return $ChatOutboxTable(attachedDatabase, alias);
  }
}

class ChatOutboxRow extends DataClass implements Insertable<ChatOutboxRow> {
  final String owner;
  final String chatId;
  final String clientId;
  final String idempotencyKey;
  final String body;
  final String? replyToId;

  /// Quote shown above the pending text; the server validates only the id.
  final String? replyToPayload;

  /// Local revision of [replyToPayload]; a delivery compares it with the
  /// revision captured when the send request started.
  final int quoteRevision;

  /// Ready photo ids chosen before the first attempt, as a JSON array.
  final String? photoIds;
  final DateTime createdAt;
  final int attempts;
  final String status;
  final String? failure;
  const ChatOutboxRow({
    required this.owner,
    required this.chatId,
    required this.clientId,
    required this.idempotencyKey,
    required this.body,
    this.replyToId,
    this.replyToPayload,
    required this.quoteRevision,
    this.photoIds,
    required this.createdAt,
    required this.attempts,
    required this.status,
    this.failure,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner'] = Variable<String>(owner);
    map['chat_id'] = Variable<String>(chatId);
    map['client_id'] = Variable<String>(clientId);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    if (!nullToAbsent || replyToPayload != null) {
      map['reply_to_payload'] = Variable<String>(replyToPayload);
    }
    map['quote_revision'] = Variable<int>(quoteRevision);
    if (!nullToAbsent || photoIds != null) {
      map['photo_ids'] = Variable<String>(photoIds);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || failure != null) {
      map['failure'] = Variable<String>(failure);
    }
    return map;
  }

  ChatOutboxCompanion toCompanion(bool nullToAbsent) {
    return ChatOutboxCompanion(
      owner: Value(owner),
      chatId: Value(chatId),
      clientId: Value(clientId),
      idempotencyKey: Value(idempotencyKey),
      body: Value(body),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      replyToPayload: replyToPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToPayload),
      quoteRevision: Value(quoteRevision),
      photoIds: photoIds == null && nullToAbsent
          ? const Value.absent()
          : Value(photoIds),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      status: Value(status),
      failure: failure == null && nullToAbsent
          ? const Value.absent()
          : Value(failure),
    );
  }

  factory ChatOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatOutboxRow(
      owner: serializer.fromJson<String>(json['owner']),
      chatId: serializer.fromJson<String>(json['chatId']),
      clientId: serializer.fromJson<String>(json['clientId']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      body: serializer.fromJson<String>(json['body']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      replyToPayload: serializer.fromJson<String?>(json['replyToPayload']),
      quoteRevision: serializer.fromJson<int>(json['quoteRevision']),
      photoIds: serializer.fromJson<String?>(json['photoIds']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      status: serializer.fromJson<String>(json['status']),
      failure: serializer.fromJson<String?>(json['failure']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'owner': serializer.toJson<String>(owner),
      'chatId': serializer.toJson<String>(chatId),
      'clientId': serializer.toJson<String>(clientId),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'body': serializer.toJson<String>(body),
      'replyToId': serializer.toJson<String?>(replyToId),
      'replyToPayload': serializer.toJson<String?>(replyToPayload),
      'quoteRevision': serializer.toJson<int>(quoteRevision),
      'photoIds': serializer.toJson<String?>(photoIds),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'status': serializer.toJson<String>(status),
      'failure': serializer.toJson<String?>(failure),
    };
  }

  ChatOutboxRow copyWith({
    String? owner,
    String? chatId,
    String? clientId,
    String? idempotencyKey,
    String? body,
    Value<String?> replyToId = const Value.absent(),
    Value<String?> replyToPayload = const Value.absent(),
    int? quoteRevision,
    Value<String?> photoIds = const Value.absent(),
    DateTime? createdAt,
    int? attempts,
    String? status,
    Value<String?> failure = const Value.absent(),
  }) => ChatOutboxRow(
    owner: owner ?? this.owner,
    chatId: chatId ?? this.chatId,
    clientId: clientId ?? this.clientId,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    body: body ?? this.body,
    replyToId: replyToId.present ? replyToId.value : this.replyToId,
    replyToPayload: replyToPayload.present
        ? replyToPayload.value
        : this.replyToPayload,
    quoteRevision: quoteRevision ?? this.quoteRevision,
    photoIds: photoIds.present ? photoIds.value : this.photoIds,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    status: status ?? this.status,
    failure: failure.present ? failure.value : this.failure,
  );
  ChatOutboxRow copyWithCompanion(ChatOutboxCompanion data) {
    return ChatOutboxRow(
      owner: data.owner.present ? data.owner.value : this.owner,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      body: data.body.present ? data.body.value : this.body,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      replyToPayload: data.replyToPayload.present
          ? data.replyToPayload.value
          : this.replyToPayload,
      quoteRevision: data.quoteRevision.present
          ? data.quoteRevision.value
          : this.quoteRevision,
      photoIds: data.photoIds.present ? data.photoIds.value : this.photoIds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      status: data.status.present ? data.status.value : this.status,
      failure: data.failure.present ? data.failure.value : this.failure,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatOutboxRow(')
          ..write('owner: $owner, ')
          ..write('chatId: $chatId, ')
          ..write('clientId: $clientId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('body: $body, ')
          ..write('replyToId: $replyToId, ')
          ..write('replyToPayload: $replyToPayload, ')
          ..write('quoteRevision: $quoteRevision, ')
          ..write('photoIds: $photoIds, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('status: $status, ')
          ..write('failure: $failure')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    owner,
    chatId,
    clientId,
    idempotencyKey,
    body,
    replyToId,
    replyToPayload,
    quoteRevision,
    photoIds,
    createdAt,
    attempts,
    status,
    failure,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatOutboxRow &&
          other.owner == this.owner &&
          other.chatId == this.chatId &&
          other.clientId == this.clientId &&
          other.idempotencyKey == this.idempotencyKey &&
          other.body == this.body &&
          other.replyToId == this.replyToId &&
          other.replyToPayload == this.replyToPayload &&
          other.quoteRevision == this.quoteRevision &&
          other.photoIds == this.photoIds &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.status == this.status &&
          other.failure == this.failure);
}

class ChatOutboxCompanion extends UpdateCompanion<ChatOutboxRow> {
  final Value<String> owner;
  final Value<String> chatId;
  final Value<String> clientId;
  final Value<String> idempotencyKey;
  final Value<String> body;
  final Value<String?> replyToId;
  final Value<String?> replyToPayload;
  final Value<int> quoteRevision;
  final Value<String?> photoIds;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String> status;
  final Value<String?> failure;
  final Value<int> rowid;
  const ChatOutboxCompanion({
    this.owner = const Value.absent(),
    this.chatId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.body = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.replyToPayload = const Value.absent(),
    this.quoteRevision = const Value.absent(),
    this.photoIds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.status = const Value.absent(),
    this.failure = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatOutboxCompanion.insert({
    required String owner,
    required String chatId,
    required String clientId,
    required String idempotencyKey,
    required String body,
    this.replyToId = const Value.absent(),
    this.replyToPayload = const Value.absent(),
    this.quoteRevision = const Value.absent(),
    this.photoIds = const Value.absent(),
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.status = const Value.absent(),
    this.failure = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : owner = Value(owner),
       chatId = Value(chatId),
       clientId = Value(clientId),
       idempotencyKey = Value(idempotencyKey),
       body = Value(body),
       createdAt = Value(createdAt);
  static Insertable<ChatOutboxRow> custom({
    Expression<String>? owner,
    Expression<String>? chatId,
    Expression<String>? clientId,
    Expression<String>? idempotencyKey,
    Expression<String>? body,
    Expression<String>? replyToId,
    Expression<String>? replyToPayload,
    Expression<int>? quoteRevision,
    Expression<String>? photoIds,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? status,
    Expression<String>? failure,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (owner != null) 'owner': owner,
      if (chatId != null) 'chat_id': chatId,
      if (clientId != null) 'client_id': clientId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (body != null) 'body': body,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (replyToPayload != null) 'reply_to_payload': replyToPayload,
      if (quoteRevision != null) 'quote_revision': quoteRevision,
      if (photoIds != null) 'photo_ids': photoIds,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (status != null) 'status': status,
      if (failure != null) 'failure': failure,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatOutboxCompanion copyWith({
    Value<String>? owner,
    Value<String>? chatId,
    Value<String>? clientId,
    Value<String>? idempotencyKey,
    Value<String>? body,
    Value<String?>? replyToId,
    Value<String?>? replyToPayload,
    Value<int>? quoteRevision,
    Value<String?>? photoIds,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<String>? status,
    Value<String?>? failure,
    Value<int>? rowid,
  }) {
    return ChatOutboxCompanion(
      owner: owner ?? this.owner,
      chatId: chatId ?? this.chatId,
      clientId: clientId ?? this.clientId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      body: body ?? this.body,
      replyToId: replyToId ?? this.replyToId,
      replyToPayload: replyToPayload ?? this.replyToPayload,
      quoteRevision: quoteRevision ?? this.quoteRevision,
      photoIds: photoIds ?? this.photoIds,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      status: status ?? this.status,
      failure: failure ?? this.failure,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (replyToPayload.present) {
      map['reply_to_payload'] = Variable<String>(replyToPayload.value);
    }
    if (quoteRevision.present) {
      map['quote_revision'] = Variable<int>(quoteRevision.value);
    }
    if (photoIds.present) {
      map['photo_ids'] = Variable<String>(photoIds.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (failure.present) {
      map['failure'] = Variable<String>(failure.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatOutboxCompanion(')
          ..write('owner: $owner, ')
          ..write('chatId: $chatId, ')
          ..write('clientId: $clientId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('body: $body, ')
          ..write('replyToId: $replyToId, ')
          ..write('replyToPayload: $replyToPayload, ')
          ..write('quoteRevision: $quoteRevision, ')
          ..write('photoIds: $photoIds, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('status: $status, ')
          ..write('failure: $failure, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PreferencesTable preferences = $PreferencesTable(this);
  late final $ListingFeedsTable listingFeeds = $ListingFeedsTable(this);
  late final $ChatDialogsTable chatDialogs = $ChatDialogsTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $ChatMessageTombstonesTable chatMessageTombstones =
      $ChatMessageTombstonesTable(this);
  late final $ChatOutboxTable chatOutbox = $ChatOutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    preferences,
    listingFeeds,
    chatDialogs,
    chatMessages,
    chatMessageTombstones,
    chatOutbox,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$PreferencesTableCreateCompanionBuilder =
    PreferencesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$PreferencesTableUpdateCompanionBuilder =
    PreferencesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$PreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$PreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PreferencesTable,
          PreferenceRow,
          $$PreferencesTableFilterComposer,
          $$PreferencesTableOrderingComposer,
          $$PreferencesTableAnnotationComposer,
          $$PreferencesTableCreateCompanionBuilder,
          $$PreferencesTableUpdateCompanionBuilder,
          (
            PreferenceRow,
            BaseReferences<_$AppDatabase, $PreferencesTable, PreferenceRow>,
          ),
          PreferenceRow,
          PrefetchHooks Function()
        > {
  $$PreferencesTableTableManager(_$AppDatabase db, $PreferencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => PreferencesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => PreferencesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PreferencesTable, PreferenceRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PreferencesTable,
                    PreferenceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PreferencesTable,
      PreferenceRow,
      $$PreferencesTableFilterComposer,
      $$PreferencesTableOrderingComposer,
      $$PreferencesTableAnnotationComposer,
      $$PreferencesTableCreateCompanionBuilder,
      $$PreferencesTableUpdateCompanionBuilder,
      (
        PreferenceRow,
        BaseReferences<_$AppDatabase, $PreferencesTable, PreferenceRow>,
      ),
      PreferenceRow,
      PrefetchHooks Function()
    >;
typedef $$ListingFeedsTableCreateCompanionBuilder =
    ListingFeedsCompanion Function({
      required String owner,
      required String area,
      required String payload,
      Value<int> rowid,
    });
typedef $$ListingFeedsTableUpdateCompanionBuilder =
    ListingFeedsCompanion Function({
      Value<String> owner,
      Value<String> area,
      Value<String> payload,
      Value<int> rowid,
    });

class $$ListingFeedsTableFilterComposer
    extends Composer<_$AppDatabase, $ListingFeedsTable> {
  $$ListingFeedsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get area => $composableBuilder(
    column: $table.area,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ListingFeedsTableOrderingComposer
    extends Composer<_$AppDatabase, $ListingFeedsTable> {
  $$ListingFeedsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get area => $composableBuilder(
    column: $table.area,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ListingFeedsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ListingFeedsTable> {
  $$ListingFeedsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get area =>
      $composableBuilder(column: $table.area, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$ListingFeedsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ListingFeedsTable,
          ListingFeed,
          $$ListingFeedsTableFilterComposer,
          $$ListingFeedsTableOrderingComposer,
          $$ListingFeedsTableAnnotationComposer,
          $$ListingFeedsTableCreateCompanionBuilder,
          $$ListingFeedsTableUpdateCompanionBuilder,
          (
            ListingFeed,
            BaseReferences<_$AppDatabase, $ListingFeedsTable, ListingFeed>,
          ),
          ListingFeed,
          PrefetchHooks Function()
        > {
  $$ListingFeedsTableTableManager(_$AppDatabase db, $ListingFeedsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ListingFeedsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ListingFeedsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ListingFeedsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> owner = const Value.absent(),
                Value<String> area = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ListingFeedsCompanion(
                owner: owner,
                area: area,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String owner,
                required String area,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => ListingFeedsCompanion.insert(
                owner: owner,
                area: area,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ListingFeedsTable, ListingFeed>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ListingFeedsTable,
                    ListingFeed
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ListingFeedsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ListingFeedsTable,
      ListingFeed,
      $$ListingFeedsTableFilterComposer,
      $$ListingFeedsTableOrderingComposer,
      $$ListingFeedsTableAnnotationComposer,
      $$ListingFeedsTableCreateCompanionBuilder,
      $$ListingFeedsTableUpdateCompanionBuilder,
      (
        ListingFeed,
        BaseReferences<_$AppDatabase, $ListingFeedsTable, ListingFeed>,
      ),
      ListingFeed,
      PrefetchHooks Function()
    >;
typedef $$ChatDialogsTableCreateCompanionBuilder =
    ChatDialogsCompanion Function({
      required String owner,
      required String chatId,
      required DateTime updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$ChatDialogsTableUpdateCompanionBuilder =
    ChatDialogsCompanion Function({
      Value<String> owner,
      Value<String> chatId,
      Value<DateTime> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$ChatDialogsTableFilterComposer
    extends Composer<_$AppDatabase, $ChatDialogsTable> {
  $$ChatDialogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatDialogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatDialogsTable> {
  $$ChatDialogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatDialogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatDialogsTable> {
  $$ChatDialogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$ChatDialogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatDialogsTable,
          ChatDialogRow,
          $$ChatDialogsTableFilterComposer,
          $$ChatDialogsTableOrderingComposer,
          $$ChatDialogsTableAnnotationComposer,
          $$ChatDialogsTableCreateCompanionBuilder,
          $$ChatDialogsTableUpdateCompanionBuilder,
          (
            ChatDialogRow,
            BaseReferences<_$AppDatabase, $ChatDialogsTable, ChatDialogRow>,
          ),
          ChatDialogRow,
          PrefetchHooks Function()
        > {
  $$ChatDialogsTableTableManager(_$AppDatabase db, $ChatDialogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatDialogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatDialogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatDialogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> owner = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatDialogsCompanion(
                owner: owner,
                chatId: chatId,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String owner,
                required String chatId,
                required DateTime updatedAt,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => ChatDialogsCompanion.insert(
                owner: owner,
                chatId: chatId,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatDialogsTable, ChatDialogRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatDialogsTable,
                    ChatDialogRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatDialogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatDialogsTable,
      ChatDialogRow,
      $$ChatDialogsTableFilterComposer,
      $$ChatDialogsTableOrderingComposer,
      $$ChatDialogsTableAnnotationComposer,
      $$ChatDialogsTableCreateCompanionBuilder,
      $$ChatDialogsTableUpdateCompanionBuilder,
      (
        ChatDialogRow,
        BaseReferences<_$AppDatabase, $ChatDialogsTable, ChatDialogRow>,
      ),
      ChatDialogRow,
      PrefetchHooks Function()
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      required String owner,
      required String chatId,
      required String clientId,
      required String serverId,
      required int sequence,
      required String senderId,
      required String body,
      Value<int> version,
      Value<String?> replyToId,
      Value<String?> replyToPayload,
      Value<String?> photoIds,
      Value<int> quoteRevision,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<String> owner,
      Value<String> chatId,
      Value<String> clientId,
      Value<String> serverId,
      Value<int> sequence,
      Value<String> senderId,
      Value<String> body,
      Value<int> version,
      Value<String?> replyToId,
      Value<String?> replyToPayload,
      Value<String?> photoIds,
      Value<int> quoteRevision,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToPayload => $composableBuilder(
    column: $table.replyToPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoIds => $composableBuilder(
    column: $table.photoIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quoteRevision => $composableBuilder(
    column: $table.quoteRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToPayload => $composableBuilder(
    column: $table.replyToPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoIds => $composableBuilder(
    column: $table.photoIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quoteRevision => $composableBuilder(
    column: $table.quoteRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get replyToId =>
      $composableBuilder(column: $table.replyToId, builder: (column) => column);

  GeneratedColumn<String> get replyToPayload => $composableBuilder(
    column: $table.replyToPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoIds =>
      $composableBuilder(column: $table.photoIds, builder: (column) => column);

  GeneratedColumn<int> get quoteRevision => $composableBuilder(
    column: $table.quoteRevision,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatMessagesTable,
          ChatMessageRow,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            ChatMessageRow,
            BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessageRow>,
          ),
          ChatMessageRow,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$AppDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> owner = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> serverId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> replyToPayload = const Value.absent(),
                Value<String?> photoIds = const Value.absent(),
                Value<int> quoteRevision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion(
                owner: owner,
                chatId: chatId,
                clientId: clientId,
                serverId: serverId,
                sequence: sequence,
                senderId: senderId,
                body: body,
                version: version,
                replyToId: replyToId,
                replyToPayload: replyToPayload,
                photoIds: photoIds,
                quoteRevision: quoteRevision,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String owner,
                required String chatId,
                required String clientId,
                required String serverId,
                required int sequence,
                required String senderId,
                required String body,
                Value<int> version = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> replyToPayload = const Value.absent(),
                Value<String?> photoIds = const Value.absent(),
                Value<int> quoteRevision = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                owner: owner,
                chatId: chatId,
                clientId: clientId,
                serverId: serverId,
                sequence: sequence,
                senderId: senderId,
                body: body,
                version: version,
                replyToId: replyToId,
                replyToPayload: replyToPayload,
                photoIds: photoIds,
                quoteRevision: quoteRevision,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatMessagesTable, ChatMessageRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatMessagesTable,
                    ChatMessageRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatMessagesTable,
      ChatMessageRow,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        ChatMessageRow,
        BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessageRow>,
      ),
      ChatMessageRow,
      PrefetchHooks Function()
    >;
typedef $$ChatMessageTombstonesTableCreateCompanionBuilder =
    ChatMessageTombstonesCompanion Function({
      required String owner,
      required String chatId,
      required String messageId,
      required int sequence,
      Value<int> version,
      required DateTime deletedAt,
      Value<int> rowid,
    });
typedef $$ChatMessageTombstonesTableUpdateCompanionBuilder =
    ChatMessageTombstonesCompanion Function({
      Value<String> owner,
      Value<String> chatId,
      Value<String> messageId,
      Value<int> sequence,
      Value<int> version,
      Value<DateTime> deletedAt,
      Value<int> rowid,
    });

class $$ChatMessageTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMessageTombstonesTable> {
  $$ChatMessageTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessageTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMessageTombstonesTable> {
  $$ChatMessageTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessageTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMessageTombstonesTable> {
  $$ChatMessageTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ChatMessageTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatMessageTombstonesTable,
          ChatMessageTombstoneRow,
          $$ChatMessageTombstonesTableFilterComposer,
          $$ChatMessageTombstonesTableOrderingComposer,
          $$ChatMessageTombstonesTableAnnotationComposer,
          $$ChatMessageTombstonesTableCreateCompanionBuilder,
          $$ChatMessageTombstonesTableUpdateCompanionBuilder,
          (
            ChatMessageTombstoneRow,
            BaseReferences<
              _$AppDatabase,
              $ChatMessageTombstonesTable,
              ChatMessageTombstoneRow
            >,
          ),
          ChatMessageTombstoneRow,
          PrefetchHooks Function()
        > {
  $$ChatMessageTombstonesTableTableManager(
    _$AppDatabase db,
    $ChatMessageTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessageTombstonesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ChatMessageTombstonesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ChatMessageTombstonesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> owner = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessageTombstonesCompanion(
                owner: owner,
                chatId: chatId,
                messageId: messageId,
                sequence: sequence,
                version: version,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String owner,
                required String chatId,
                required String messageId,
                required int sequence,
                Value<int> version = const Value.absent(),
                required DateTime deletedAt,
                Value<int> rowid = const Value.absent(),
              }) => ChatMessageTombstonesCompanion.insert(
                owner: owner,
                chatId: chatId,
                messageId: messageId,
                sequence: sequence,
                version: version,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ChatMessageTombstonesTable,
                    ChatMessageTombstoneRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatMessageTombstonesTable,
                    ChatMessageTombstoneRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessageTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatMessageTombstonesTable,
      ChatMessageTombstoneRow,
      $$ChatMessageTombstonesTableFilterComposer,
      $$ChatMessageTombstonesTableOrderingComposer,
      $$ChatMessageTombstonesTableAnnotationComposer,
      $$ChatMessageTombstonesTableCreateCompanionBuilder,
      $$ChatMessageTombstonesTableUpdateCompanionBuilder,
      (
        ChatMessageTombstoneRow,
        BaseReferences<
          _$AppDatabase,
          $ChatMessageTombstonesTable,
          ChatMessageTombstoneRow
        >,
      ),
      ChatMessageTombstoneRow,
      PrefetchHooks Function()
    >;
typedef $$ChatOutboxTableCreateCompanionBuilder = ChatOutboxCompanion Function({
  required String owner,
  required String chatId,
  required String clientId,
  required String idempotencyKey,
  required String body,
  Value<String?> replyToId,
  Value<String?> replyToPayload,
  Value<int> quoteRevision,
  Value<String?> photoIds,
  required DateTime createdAt,
  Value<int> attempts,
  Value<String> status,
  Value<String?> failure,
  Value<int> rowid,
});
typedef $$ChatOutboxTableUpdateCompanionBuilder = ChatOutboxCompanion Function({
  Value<String> owner,
  Value<String> chatId,
  Value<String> clientId,
  Value<String> idempotencyKey,
  Value<String> body,
  Value<String?> replyToId,
  Value<String?> replyToPayload,
  Value<int> quoteRevision,
  Value<String?> photoIds,
  Value<DateTime> createdAt,
  Value<int> attempts,
  Value<String> status,
  Value<String?> failure,
  Value<int> rowid,
});

class $$ChatOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $ChatOutboxTable> {
  $$ChatOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToPayload => $composableBuilder(
    column: $table.replyToPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quoteRevision => $composableBuilder(
    column: $table.quoteRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoIds => $composableBuilder(
    column: $table.photoIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failure => $composableBuilder(
    column: $table.failure,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatOutboxTable> {
  $$ChatOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToPayload => $composableBuilder(
    column: $table.replyToPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quoteRevision => $composableBuilder(
    column: $table.quoteRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoIds => $composableBuilder(
    column: $table.photoIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failure => $composableBuilder(
    column: $table.failure,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatOutboxTable> {
  $$ChatOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get replyToId =>
      $composableBuilder(column: $table.replyToId, builder: (column) => column);

  GeneratedColumn<String> get replyToPayload => $composableBuilder(
    column: $table.replyToPayload,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quoteRevision => $composableBuilder(
    column: $table.quoteRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoIds =>
      $composableBuilder(column: $table.photoIds, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get failure =>
      $composableBuilder(column: $table.failure, builder: (column) => column);
}

class $$ChatOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatOutboxTable,
          ChatOutboxRow,
          $$ChatOutboxTableFilterComposer,
          $$ChatOutboxTableOrderingComposer,
          $$ChatOutboxTableAnnotationComposer,
          $$ChatOutboxTableCreateCompanionBuilder,
          $$ChatOutboxTableUpdateCompanionBuilder,
          (
            ChatOutboxRow,
            BaseReferences<_$AppDatabase, $ChatOutboxTable, ChatOutboxRow>,
          ),
          ChatOutboxRow,
          PrefetchHooks Function()
        > {
  $$ChatOutboxTableTableManager(_$AppDatabase db, $ChatOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> owner = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> replyToPayload = const Value.absent(),
                Value<int> quoteRevision = const Value.absent(),
                Value<String?> photoIds = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> failure = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatOutboxCompanion(
                owner: owner,
                chatId: chatId,
                clientId: clientId,
                idempotencyKey: idempotencyKey,
                body: body,
                replyToId: replyToId,
                replyToPayload: replyToPayload,
                quoteRevision: quoteRevision,
                photoIds: photoIds,
                createdAt: createdAt,
                attempts: attempts,
                status: status,
                failure: failure,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String owner,
                required String chatId,
                required String clientId,
                required String idempotencyKey,
                required String body,
                Value<String?> replyToId = const Value.absent(),
                Value<String?> replyToPayload = const Value.absent(),
                Value<int> quoteRevision = const Value.absent(),
                Value<String?> photoIds = const Value.absent(),
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> failure = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatOutboxCompanion.insert(
                owner: owner,
                chatId: chatId,
                clientId: clientId,
                idempotencyKey: idempotencyKey,
                body: body,
                replyToId: replyToId,
                replyToPayload: replyToPayload,
                quoteRevision: quoteRevision,
                photoIds: photoIds,
                createdAt: createdAt,
                attempts: attempts,
                status: status,
                failure: failure,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatOutboxTable, ChatOutboxRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatOutboxTable,
                    ChatOutboxRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatOutboxTable,
      ChatOutboxRow,
      $$ChatOutboxTableFilterComposer,
      $$ChatOutboxTableOrderingComposer,
      $$ChatOutboxTableAnnotationComposer,
      $$ChatOutboxTableCreateCompanionBuilder,
      $$ChatOutboxTableUpdateCompanionBuilder,
      (
        ChatOutboxRow,
        BaseReferences<_$AppDatabase, $ChatOutboxTable, ChatOutboxRow>,
      ),
      ChatOutboxRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PreferencesTableTableManager get preferences =>
      $$PreferencesTableTableManager(_db, _db.preferences);
  $$ListingFeedsTableTableManager get listingFeeds =>
      $$ListingFeedsTableTableManager(_db, _db.listingFeeds);
  $$ChatDialogsTableTableManager get chatDialogs =>
      $$ChatDialogsTableTableManager(_db, _db.chatDialogs);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$ChatMessageTombstonesTableTableManager get chatMessageTombstones =>
      $$ChatMessageTombstonesTableTableManager(_db, _db.chatMessageTombstones);
  $$ChatOutboxTableTableManager get chatOutbox =>
      $$ChatOutboxTableTableManager(_db, _db.chatOutbox);
}

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app-wide database. Overridden with an in-memory database in tests.

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

/// The app-wide database. Overridden with an in-memory database in tests.

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  /// The app-wide database. Overridden with an in-memory database in tests.
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'44154e51c3f3079ee293d8ad0ebd1e17cca871ed';
