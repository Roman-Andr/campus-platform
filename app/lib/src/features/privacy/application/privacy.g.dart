// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'privacy.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Who may start a personal dialog with the signed-in user.
///
/// The value is read from the server on every opening, so a change made on
/// another device is shown on this one too.

@ProviderFor(MessagePolicyController)
final messagePolicyControllerProvider = MessagePolicyControllerProvider._();

/// Who may start a personal dialog with the signed-in user.
///
/// The value is read from the server on every opening, so a change made on
/// another device is shown on this one too.
final class MessagePolicyControllerProvider
    extends $AsyncNotifierProvider<MessagePolicyController, MessagePolicy> {
  /// Who may start a personal dialog with the signed-in user.
  ///
  /// The value is read from the server on every opening, so a change made on
  /// another device is shown on this one too.
  MessagePolicyControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: privacyRetry,
        name: r'messagePolicyControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$messagePolicyControllerHash();

  @$internal
  @override
  MessagePolicyController create() => MessagePolicyController();
}

String _$messagePolicyControllerHash() =>
    r'4cbf15d88ea4840160e63759f8bea64b864e5825';

/// Who may start a personal dialog with the signed-in user.
///
/// The value is read from the server on every opening, so a change made on
/// another device is shown on this one too.

abstract class _$MessagePolicyController extends $AsyncNotifier<MessagePolicy> {
  FutureOr<MessagePolicy> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<MessagePolicy>, MessagePolicy>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MessagePolicy>, MessagePolicy>,
              AsyncValue<MessagePolicy>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The signed-in user's blacklist, newest first, one cursor page at a time.
///
/// The list is loaded from the server, so a block made on another device is
/// visible here. Mutations update the state only after the server confirms
/// them; a failed request leaves the shown list unchanged.

@ProviderFor(BlockedUsers)
final blockedUsersProvider = BlockedUsersProvider._();

/// The signed-in user's blacklist, newest first, one cursor page at a time.
///
/// The list is loaded from the server, so a block made on another device is
/// visible here. Mutations update the state only after the server confirms
/// them; a failed request leaves the shown list unchanged.
final class BlockedUsersProvider
    extends $AsyncNotifierProvider<BlockedUsers, BlockedUsersState> {
  /// The signed-in user's blacklist, newest first, one cursor page at a time.
  ///
  /// The list is loaded from the server, so a block made on another device is
  /// visible here. Mutations update the state only after the server confirms
  /// them; a failed request leaves the shown list unchanged.
  BlockedUsersProvider._()
    : super(
        from: null,
        argument: null,
        retry: privacyRetry,
        name: r'blockedUsersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$blockedUsersHash();

  @$internal
  @override
  BlockedUsers create() => BlockedUsers();
}

String _$blockedUsersHash() => r'a2db8f9a0b5aa6cf98c847e5a1abaa1676405681';

/// The signed-in user's blacklist, newest first, one cursor page at a time.
///
/// The list is loaded from the server, so a block made on another device is
/// visible here. Mutations update the state only after the server confirms
/// them; a failed request leaves the shown list unchanged.

abstract class _$BlockedUsers extends $AsyncNotifier<BlockedUsersState> {
  FutureOr<BlockedUsersState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<BlockedUsersState>, BlockedUsersState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BlockedUsersState>, BlockedUsersState>,
              AsyncValue<BlockedUsersState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether [userId] is in the signed-in user's blacklist.
///
/// The blacklist endpoint is paginated and has no per-user lookup, so the
/// walk follows the cursors until it finds the user or reaches the end.
/// The screen uses this only when the participant is not in the already
/// loaded first page.

@ProviderFor(blockedUser)
final blockedUserProvider = BlockedUserFamily._();

/// Whether [userId] is in the signed-in user's blacklist.
///
/// The blacklist endpoint is paginated and has no per-user lookup, so the
/// walk follows the cursors until it finds the user or reaches the end.
/// The screen uses this only when the participant is not in the already
/// loaded first page.

final class BlockedUserProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether [userId] is in the signed-in user's blacklist.
  ///
  /// The blacklist endpoint is paginated and has no per-user lookup, so the
  /// walk follows the cursors until it finds the user or reaches the end.
  /// The screen uses this only when the participant is not in the already
  /// loaded first page.
  BlockedUserProvider._({
    required BlockedUserFamily super.from,
    required String super.argument,
  }) : super(
         retry: privacyRetry,
         name: r'blockedUserProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blockedUserHash();

  @override
  String toString() {
    return r'blockedUserProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return blockedUser(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is BlockedUserProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blockedUserHash() => r'd79f030c688c834d8476f4aeb08ee62639be2550';

/// Whether [userId] is in the signed-in user's blacklist.
///
/// The blacklist endpoint is paginated and has no per-user lookup, so the
/// walk follows the cursors until it finds the user or reaches the end.
/// The screen uses this only when the participant is not in the already
/// loaded first page.

final class BlockedUserFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  BlockedUserFamily._()
    : super(
        retry: privacyRetry,
        name: r'blockedUserProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether [userId] is in the signed-in user's blacklist.
  ///
  /// The blacklist endpoint is paginated and has no per-user lookup, so the
  /// walk follows the cursors until it finds the user or reaches the end.
  /// The screen uses this only when the participant is not in the already
  /// loaded first page.

  BlockedUserProvider call(String userId) =>
      BlockedUserProvider._(argument: userId, from: this);

  @override
  String toString() => r'blockedUserProvider';
}
