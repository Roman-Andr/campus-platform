// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chats.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Dialogs of the signed-in user, the most recently active first.
///
/// The server list is the source of truth; the last loaded snapshot opens
/// offline. Rows are cached per local session, so another account never
/// sees them.

@ProviderFor(ChatDialogs)
final chatDialogsProvider = ChatDialogsProvider._();

/// Dialogs of the signed-in user, the most recently active first.
///
/// The server list is the source of truth; the last loaded snapshot opens
/// offline. Rows are cached per local session, so another account never
/// sees them.
final class ChatDialogsProvider
    extends $AsyncNotifierProvider<ChatDialogs, ChatDialogsState> {
  /// Dialogs of the signed-in user, the most recently active first.
  ///
  /// The server list is the source of truth; the last loaded snapshot opens
  /// offline. Rows are cached per local session, so another account never
  /// sees them.
  ChatDialogsProvider._()
    : super(
        from: null,
        argument: null,
        retry: chatRetry,
        name: r'chatDialogsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatDialogsHash();

  @$internal
  @override
  ChatDialogs create() => ChatDialogs();
}

String _$chatDialogsHash() => r'cdd35ca1b909a41553dbf6b7c7ef0bf20f6d967f';

/// Dialogs of the signed-in user, the most recently active first.
///
/// The server list is the source of truth; the last loaded snapshot opens
/// offline. Rows are cached per local session, so another account never
/// sees them.

abstract class _$ChatDialogs extends $AsyncNotifier<ChatDialogsState> {
  FutureOr<ChatDialogsState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ChatDialogsState>, ChatDialogsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ChatDialogsState>, ChatDialogsState>,
              AsyncValue<ChatDialogsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// One dialog of the signed-in user, with the cached copy as an offline
/// fallback. Somebody else's dialog is `404` and never appears here.

@ProviderFor(chat)
final chatProvider = ChatFamily._();

/// One dialog of the signed-in user, with the cached copy as an offline
/// fallback. Somebody else's dialog is `404` and never appears here.

final class ChatProvider
    extends
        $FunctionalProvider<
          AsyncValue<ChatOutput?>,
          ChatOutput?,
          FutureOr<ChatOutput?>
        >
    with $FutureModifier<ChatOutput?>, $FutureProvider<ChatOutput?> {
  /// One dialog of the signed-in user, with the cached copy as an offline
  /// fallback. Somebody else's dialog is `404` and never appears here.
  ChatProvider._({
    required ChatFamily super.from,
    required String super.argument,
  }) : super(
         retry: chatRetry,
         name: r'chatProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatHash();

  @override
  String toString() {
    return r'chatProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ChatOutput?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ChatOutput?> create(Ref ref) {
    final argument = this.argument as String;
    return chat(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatHash() => r'0f6c99ab007f59215d83aca0f175dbab31f0dcbf';

/// One dialog of the signed-in user, with the cached copy as an offline
/// fallback. Somebody else's dialog is `404` and never appears here.

final class ChatFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ChatOutput?>, String> {
  ChatFamily._()
    : super(
        retry: chatRetry,
        name: r'chatProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One dialog of the signed-in user, with the cached copy as an offline
  /// fallback. Somebody else's dialog is `404` and never appears here.

  ChatProvider call(String chatId) =>
      ChatProvider._(argument: chatId, from: this);

  @override
  String toString() => r'chatProvider';
}

@ProviderFor(chatStarter)
final chatStarterProvider = ChatStarterProvider._();

final class ChatStarterProvider
    extends $FunctionalProvider<ChatStarter, ChatStarter, ChatStarter>
    with $Provider<ChatStarter> {
  ChatStarterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatStarterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatStarterHash();

  @$internal
  @override
  $ProviderElement<ChatStarter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ChatStarter create(Ref ref) {
    return chatStarter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatStarter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatStarter>(value),
    );
  }
}

String _$chatStarterHash() => r'1506328218b8b38bea0cea67a92634a66d53f410';
