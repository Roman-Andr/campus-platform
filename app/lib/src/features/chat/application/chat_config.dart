import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_config.g.dart';

/// Client-side parameters of personal chats.
///
/// The message length matches `CAMPUS_CHAT_MESSAGE_MAX_LENGTH` of the server
/// (ТЗ, Приложение 4). Values come from `--dart-define` at build time.
class ChatConfig {
  const ChatConfig({
    required this.maxMessageLength,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
  });

  factory ChatConfig.fromEnvironment() => const ChatConfig(
    maxMessageLength: int.fromEnvironment(
      'CAMPUS_CHAT_MESSAGE_MAX_LENGTH',
      defaultValue: 4000,
    ),
  );

  final int maxMessageLength;

  /// Pauses of the outgoing queue after a retryable failure; the last one
  /// repeats until the message is delivered or the user retries by hand.
  final List<Duration> retryDelays;
}

@Riverpod(keepAlive: true)
ChatConfig chatConfig(Ref ref) => ChatConfig.fromEnvironment();
