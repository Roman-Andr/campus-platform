// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_history.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Loads and reconciles the history of one personal dialog.
///
/// The stored messages open the screen offline. Realtime is only a wakeup:
/// every publication is followed by an API request for messages after the
/// newest loaded sequence, so a lost or duplicated publication cannot change
/// the order — the server sequence does. On the first subscription, after
/// the app returns and after an exhausted realtime history the service calls
/// [sync] again.

@ProviderFor(ChatHistory)
final chatHistoryProvider = ChatHistoryFamily._();

/// Loads and reconciles the history of one personal dialog.
///
/// The stored messages open the screen offline. Realtime is only a wakeup:
/// every publication is followed by an API request for messages after the
/// newest loaded sequence, so a lost or duplicated publication cannot change
/// the order — the server sequence does. On the first subscription, after
/// the app returns and after an exhausted realtime history the service calls
/// [sync] again.
final class ChatHistoryProvider
    extends $AsyncNotifierProvider<ChatHistory, ChatHistoryState> {
  /// Loads and reconciles the history of one personal dialog.
  ///
  /// The stored messages open the screen offline. Realtime is only a wakeup:
  /// every publication is followed by an API request for messages after the
  /// newest loaded sequence, so a lost or duplicated publication cannot change
  /// the order — the server sequence does. On the first subscription, after
  /// the app returns and after an exhausted realtime history the service calls
  /// [sync] again.
  ChatHistoryProvider._({
    required ChatHistoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: chatRetry,
         name: r'chatHistoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatHistoryHash();

  @override
  String toString() {
    return r'chatHistoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ChatHistory create() => ChatHistory();

  @override
  bool operator ==(Object other) {
    return other is ChatHistoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatHistoryHash() => r'ef28548b13995b6f5545cb4b7af6c619aa1ebb7e';

/// Loads and reconciles the history of one personal dialog.
///
/// The stored messages open the screen offline. Realtime is only a wakeup:
/// every publication is followed by an API request for messages after the
/// newest loaded sequence, so a lost or duplicated publication cannot change
/// the order — the server sequence does. On the first subscription, after
/// the app returns and after an exhausted realtime history the service calls
/// [sync] again.

final class ChatHistoryFamily extends $Family
    with
        $ClassFamilyOverride<
          ChatHistory,
          AsyncValue<ChatHistoryState>,
          ChatHistoryState,
          FutureOr<ChatHistoryState>,
          String
        > {
  ChatHistoryFamily._()
    : super(
        retry: chatRetry,
        name: r'chatHistoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Loads and reconciles the history of one personal dialog.
  ///
  /// The stored messages open the screen offline. Realtime is only a wakeup:
  /// every publication is followed by an API request for messages after the
  /// newest loaded sequence, so a lost or duplicated publication cannot change
  /// the order — the server sequence does. On the first subscription, after
  /// the app returns and after an exhausted realtime history the service calls
  /// [sync] again.

  ChatHistoryProvider call(String chatId) =>
      ChatHistoryProvider._(argument: chatId, from: this);

  @override
  String toString() => r'chatHistoryProvider';
}

/// Loads and reconciles the history of one personal dialog.
///
/// The stored messages open the screen offline. Realtime is only a wakeup:
/// every publication is followed by an API request for messages after the
/// newest loaded sequence, so a lost or duplicated publication cannot change
/// the order — the server sequence does. On the first subscription, after
/// the app returns and after an exhausted realtime history the service calls
/// [sync] again.

abstract class _$ChatHistory extends $AsyncNotifier<ChatHistoryState> {
  late final _$args = ref.$arg as String;
  String get chatId => _$args;

  FutureOr<ChatHistoryState> build(String chatId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ChatHistoryState>, ChatHistoryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ChatHistoryState>, ChatHistoryState>,
              AsyncValue<ChatHistoryState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(chatRealtime)
final chatRealtimeProvider = ChatRealtimeProvider._();

final class ChatRealtimeProvider
    extends $FunctionalProvider<ChatRealtime, ChatRealtime, ChatRealtime>
    with $Provider<ChatRealtime> {
  ChatRealtimeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatRealtimeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatRealtimeHash();

  @$internal
  @override
  $ProviderElement<ChatRealtime> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ChatRealtime create(Ref ref) {
    return chatRealtime(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatRealtime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatRealtime>(value),
    );
  }
}

String _$chatRealtimeHash() => r'86d7e0437a5f861519ac16b3812544333556228f';
