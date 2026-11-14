/// The kinds of realtime channels the server issues tokens for.
enum RealtimeChannelKind { personal, chat }

/// A checked Centrifugo channel name.
///
/// The server accepts only two canonical forms: `user#<uuid>` for the
/// personal channel of a user and `chat:<uuid>` for a chat. Building names
/// through this class keeps the client from subscribing to anything else.
class RealtimeChannel {
  RealtimeChannel._(this.name, this.kind, this.targetId);

  /// The personal channel of [userId].
  factory RealtimeChannel.personal(String userId) =>
      RealtimeChannel._checked(RealtimeChannelKind.personal, userId);

  /// The channel of the chat [chatId].
  factory RealtimeChannel.chat(String chatId) =>
      RealtimeChannel._checked(RealtimeChannelKind.chat, chatId);

  /// Parses a channel name returned by the server.
  factory RealtimeChannel.parse(String name) {
    if (name.startsWith('user#')) {
      return RealtimeChannel.personal(name.substring('user#'.length));
    }
    if (name.startsWith('chat:')) {
      return RealtimeChannel.chat(name.substring('chat:'.length));
    }
    throw const FormatException('Not a Campus realtime channel');
  }

  factory RealtimeChannel._checked(RealtimeChannelKind kind, String targetId) {
    if (!_uuid.hasMatch(targetId)) {
      throw ArgumentError.value(targetId, 'targetId', 'Not a canonical UUID');
    }
    final name = switch (kind) {
      RealtimeChannelKind.personal => 'user#$targetId',
      RealtimeChannelKind.chat => 'chat:$targetId',
    };
    return RealtimeChannel._(name, kind, targetId);
  }

  // The server accepts only lower-case canonical UUIDs, so one object has
  // exactly one channel name.
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// The channel name sent to Centrifugo and the API.
  final String name;

  final RealtimeChannelKind kind;

  /// The user or chat identifier of the channel.
  final String targetId;

  @override
  bool operator ==(Object other) =>
      other is RealtimeChannel && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}
