import 'dart:async';

import 'package:campus/src/core/api/generated/campus_api.dart';
import 'package:campus/src/core/realtime/realtime_channel.dart';
import 'package:campus/src/core/realtime/realtime_models.dart';
import 'package:campus/src/features/chat/application/chat_history.dart';
import 'package:campus/src/features/chat/data/chat_api.dart';

/// A canonical UUID the realtime channel accepts for a test dialog.
const testChatId = '01890a5d-ac96-774b-bcce-b302099a8060';

MessageOutput messageJson({
  required String chatId,
  required int sequence,
  String? clientId,
  String? id,
  String senderId = '01890a5d-ac96-774b-bcce-b302099a8058',
  String text = 'Hello',
  DateTime? createdAt,
}) => MessageOutput(
  id: id ?? 'server-$sequence',
  chatId: chatId,
  senderId: senderId,
  clientId: clientId ?? '01890a5d-ac96-774b-bcce-b302099a80$sequence',
  sequence: sequence,
  text: text,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 14, 12, sequence),
);

ParticipantOutput participantJson({
  required String id,
  String firstName = 'Иван',
  String lastName = 'Иванов',
  String accountType = 'student',
}) => ParticipantOutput(
  id: id,
  firstName: firstName,
  lastName: lastName,
  accountType: accountType,
);

ChatOutput chatJson({
  String id = 'chat-1',
  List<ParticipantOutput>? participants,
  MessageOutput? lastMessage,
  String? listingId = 'listing-1',
  DateTime? updatedAt,
}) => ChatOutput(
  id: id,
  kind: 'personal',
  listingId: listingId,
  interactionId: null,
  createdAt: DateTime.utc(2026, 11, 14, 10),
  updatedAt: updatedAt ?? DateTime.utc(2026, 11, 14, 12),
  participants:
      participants ??
      [
        participantJson(id: '01890a5d-ac96-774b-bcce-b302099a8058'),
        participantJson(
          id: '01890a5d-ac96-774b-bcce-b302099a8059',
          firstName: 'Мария',
          lastName: 'Петрова',
        ),
      ],
  lastMessage: lastMessage,
);

/// An in-memory server of chat operations with controllable failures.
class FakeChatApi implements ChatApi {
  FakeChatApi({
    List<ChatOutput>? chats,
    Map<String, List<MessageOutput>>? messages,
  }) : chats = chats ?? [chatJson()],
       messages = messages ?? {};

  final List<ChatOutput> chats;
  final Map<String, List<MessageOutput>> messages;

  final createCalls = <ChatInput>[];
  final sendCalls =
      <({String chatId, String clientId, String key, String text})>[];
  final listMessageCalls = <({String chatId, int? after, bool? ascending})>[];

  /// While set, every send waits for this future before replying.
  Completer<void>? sendGate;

  /// While set, messages requests snapshot the data, then wait for it.
  Completer<void>? listGate;

  /// While set, dialogs requests snapshot the data, then wait for it.
  Completer<void>? listChatsGate;

  /// Maximum dialogs per page; the next cursor is the last dialog id.
  int? listChatsPageLimit;

  /// Throws this instead of answering the next dialogs request.
  Object? listChatsError;

  final listChatsCalls = <String?>[];

  /// Maximum rows per messages page; the next cursor is the last sequence.
  int? pageLimit;

  /// Throws this instead of returning from the next list request.
  Object? listError;

  /// Throws this instead of answering a send, but stores the message first:
  /// this is a response lost after the server committed.
  bool loseNextResponse = false;

  /// The next send fails before reaching the server.
  Object? sendError;

  /// The next dialog creation fails with this error.
  Object? createError;

  final _storedByKey = <String, MessageOutput>{};
  int _serverSequence = 100;

  @override
  Future<PageChatOutput> listChats({String? cursor}) async {
    listChatsCalls.add(cursor);
    final snapshot = List<ChatOutput>.of(chats);
    final gate = listChatsGate;
    if (gate != null) await gate.future;
    final error = listChatsError;
    if (error != null) {
      listChatsError = null;
      throw error;
    }
    var start = 0;
    if (cursor != null) {
      final index = snapshot.indexWhere((chat) => chat.id == cursor);
      start = index < 0 ? 0 : index + 1;
    }
    final limit = listChatsPageLimit ?? snapshot.length;
    final end = start + limit > snapshot.length
        ? snapshot.length
        : start + limit;
    final items = snapshot.sublist(start, end);
    return PageChatOutput(
      items: items,
      nextPage: end < snapshot.length && items.isNotEmpty
          ? items.last.id
          : null,
    );
  }

  @override
  Future<ChatOutput> createChat({
    required String recipientId,
    String? listingId,
  }) async {
    createCalls.add(ChatInput(recipientId: recipientId, listingId: listingId));
    final error = createError;
    if (error != null) {
      createError = null;
      throw error;
    }
    return chats.first;
  }

  @override
  Future<ChatOutput> readChat(String chatId) async =>
      chats.firstWhere((chat) => chat.id == chatId);

  @override
  Future<PageMessageOutput> listMessages(
    String chatId, {
    int? afterSequence,
    bool? ascending,
    String? cursor,
    int? size,
  }) async {
    listMessageCalls.add((
      chatId: chatId,
      after: afterSequence,
      ascending: ascending,
    ));
    final snapshot = List<MessageOutput>.of(messages[chatId] ?? const [])
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    if (listGate != null) await listGate!.future;
    final error = listError;
    if (error != null) {
      listError = null;
      throw error;
    }
    var rows = snapshot
        .where((row) => afterSequence == null || row.sequence > afterSequence)
        .toList();
    if (ascending == true) {
      rows.sort((a, b) => a.sequence.compareTo(b.sequence));
    } else {
      rows.sort((a, b) => b.sequence.compareTo(a.sequence));
    }
    if (cursor != null) {
      final at = int.parse(cursor);
      rows = rows
          .where(
            (row) => ascending == true ? row.sequence > at : row.sequence < at,
          )
          .toList();
    }
    String? nextPage;
    final limit = pageLimit;
    if (limit != null && rows.length > limit) {
      rows = rows.take(limit).toList();
      nextPage = '${rows.last.sequence}';
    }
    return PageMessageOutput(items: rows, nextPage: nextPage);
  }

  @override
  Future<MessageOutput> sendMessage(
    String chatId, {
    required String clientId,
    required String text,
    required String idempotencyKey,
  }) async {
    sendCalls.add((
      chatId: chatId,
      clientId: clientId,
      key: idempotencyKey,
      text: text,
    ));
    final gate = sendGate;
    if (gate != null) await gate.future;
    final stored = _storedByKey[idempotencyKey];
    if (stored != null) return stored;
    final error = sendError;
    if (error != null) {
      sendError = null;
      throw error;
    }
    final message = messageJson(
      chatId: chatId,
      sequence: ++_serverSequence,
      clientId: clientId,
      text: text,
    );
    _storedByKey[idempotencyKey] = message;
    messages.putIfAbsent(chatId, () => []).add(message);
    if (loseNextResponse) {
      loseNextResponse = false;
      throw StateError('connection lost after commit');
    }
    return message;
  }
}

/// A realtime service double: the test emits publications and calls reload.
class FakeChatRealtime implements ChatRealtime {
  Future<void> Function()? reload;
  FakeChatSubscription? subscription;
  int subscribeCalls = 0;

  @override
  Future<RealtimeSubscription> subscribe(
    RealtimeChannel channel, {
    required Future<void> Function() reload,
  }) async {
    subscribeCalls++;
    this.reload = reload;
    return subscription = FakeChatSubscription(channel);
  }

  void emit({int offset = 1, Object? data}) {
    subscription?.emit(
      RealtimeEvent(
        channel: subscription!.channel.name,
        offset: offset,
        data: data ?? const {'type': 'chat.message'},
      ),
    );
  }
}

class FakeChatSubscription implements RealtimeSubscription {
  FakeChatSubscription(this.channel);

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _statuses = StreamController<RealtimeChannelStatus>.broadcast();
  bool closed = false;

  @override
  final RealtimeChannel channel;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<RealtimeChannelStatus> get status => _statuses.stream;

  @override
  RealtimeChannelStatus get currentStatus => RealtimeChannelStatus(
    channel: channel,
    phase: RealtimeSubscriptionPhase.subscribed,
  );

  void emit(RealtimeEvent event) => _events.add(event);

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
    await _statuses.close();
  }
}
