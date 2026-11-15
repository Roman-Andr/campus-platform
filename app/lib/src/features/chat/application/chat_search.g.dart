// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_search.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Search over the dialogs of the signed-in user.
///
/// The server checks membership on every request, so a stale result can
/// exist only in the UI: opening it rechecks access through the normal chat
/// history call. A query is sent only after the screen's debounce, and a
/// response of an older query never replaces a newer one. The provider is
/// disposed with the search screen, so results of one account never leak
/// into the next session.

@ProviderFor(ChatSearch)
final chatSearchProvider = ChatSearchProvider._();

/// Search over the dialogs of the signed-in user.
///
/// The server checks membership on every request, so a stale result can
/// exist only in the UI: opening it rechecks access through the normal chat
/// history call. A query is sent only after the screen's debounce, and a
/// response of an older query never replaces a newer one. The provider is
/// disposed with the search screen, so results of one account never leak
/// into the next session.
final class ChatSearchProvider
    extends $NotifierProvider<ChatSearch, ChatSearchState> {
  /// Search over the dialogs of the signed-in user.
  ///
  /// The server checks membership on every request, so a stale result can
  /// exist only in the UI: opening it rechecks access through the normal chat
  /// history call. A query is sent only after the screen's debounce, and a
  /// response of an older query never replaces a newer one. The provider is
  /// disposed with the search screen, so results of one account never leak
  /// into the next session.
  ChatSearchProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatSearchProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatSearchHash();

  @$internal
  @override
  ChatSearch create() => ChatSearch();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatSearchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatSearchState>(value),
    );
  }
}

String _$chatSearchHash() => r'fb010ad1b9adcf7fdda5e84865cf582515a2a3f7';

/// Search over the dialogs of the signed-in user.
///
/// The server checks membership on every request, so a stale result can
/// exist only in the UI: opening it rechecks access through the normal chat
/// history call. A query is sent only after the screen's debounce, and a
/// response of an older query never replaces a newer one. The provider is
/// disposed with the search screen, so results of one account never leak
/// into the next session.

abstract class _$ChatSearch extends $Notifier<ChatSearchState> {
  ChatSearchState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ChatSearchState, ChatSearchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ChatSearchState, ChatSearchState>,
              ChatSearchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
