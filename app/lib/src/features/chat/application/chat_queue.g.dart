// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_queue.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Sends queued messages one at a time, in local send order per chat.
///
/// A row is persisted before the first request and removed only after the
/// server returns the stored message. The client UUID and idempotency key
/// are generated once, so a repeat after a lost response is the same
/// operation for the server. A retryable failure keeps the row pending and
/// schedules another attempt; a refusal marks it failed and never shows it
/// as delivered. No later message of the same chat overtakes an earlier one.

@ProviderFor(ChatQueue)
final chatQueueProvider = ChatQueueProvider._();

/// Sends queued messages one at a time, in local send order per chat.
///
/// A row is persisted before the first request and removed only after the
/// server returns the stored message. The client UUID and idempotency key
/// are generated once, so a repeat after a lost response is the same
/// operation for the server. A retryable failure keeps the row pending and
/// schedules another attempt; a refusal marks it failed and never shows it
/// as delivered. No later message of the same chat overtakes an earlier one.
final class ChatQueueProvider
    extends $AsyncNotifierProvider<ChatQueue, ChatQueueState> {
  /// Sends queued messages one at a time, in local send order per chat.
  ///
  /// A row is persisted before the first request and removed only after the
  /// server returns the stored message. The client UUID and idempotency key
  /// are generated once, so a repeat after a lost response is the same
  /// operation for the server. A retryable failure keeps the row pending and
  /// schedules another attempt; a refusal marks it failed and never shows it
  /// as delivered. No later message of the same chat overtakes an earlier one.
  ChatQueueProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatQueueProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatQueueHash();

  @$internal
  @override
  ChatQueue create() => ChatQueue();
}

String _$chatQueueHash() => r'04adecf7be7877cf763ecc4ab412f049f871f46f';

/// Sends queued messages one at a time, in local send order per chat.
///
/// A row is persisted before the first request and removed only after the
/// server returns the stored message. The client UUID and idempotency key
/// are generated once, so a repeat after a lost response is the same
/// operation for the server. A retryable failure keeps the row pending and
/// schedules another attempt; a refusal marks it failed and never shows it
/// as delivered. No later message of the same chat overtakes an earlier one.

abstract class _$ChatQueue extends $AsyncNotifier<ChatQueueState> {
  FutureOr<ChatQueueState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ChatQueueState>, ChatQueueState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ChatQueueState>, ChatQueueState>,
              AsyncValue<ChatQueueState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
