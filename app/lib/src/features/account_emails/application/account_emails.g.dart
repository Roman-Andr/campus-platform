// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_emails.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Verified e-mail addresses of the signed-in account.

@ProviderFor(accountEmails)
final accountEmailsProvider = AccountEmailsProvider._();

/// Verified e-mail addresses of the signed-in account.

final class AccountEmailsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AddressOutput>>,
          List<AddressOutput>,
          FutureOr<List<AddressOutput>>
        >
    with
        $FutureModifier<List<AddressOutput>>,
        $FutureProvider<List<AddressOutput>> {
  /// Verified e-mail addresses of the signed-in account.
  AccountEmailsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountEmailsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountEmailsHash();

  @$internal
  @override
  $FutureProviderElement<List<AddressOutput>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AddressOutput>> create(Ref ref) {
    return accountEmails(ref);
  }
}

String _$accountEmailsHash() => r'b42660f9df4904d688e14fc2d20e7eb81f997da8';

/// Changing the account's e-mail addresses.
///
/// A new address appears in the list only after the server accepts its
/// code. Corporate addresses change the account type, so the profile is
/// reloaded after adding or deleting one.

@ProviderFor(AccountEmailActions)
final accountEmailActionsProvider = AccountEmailActionsProvider._();

/// Changing the account's e-mail addresses.
///
/// A new address appears in the list only after the server accepts its
/// code. Corporate addresses change the account type, so the profile is
/// reloaded after adding or deleting one.
final class AccountEmailActionsProvider
    extends $NotifierProvider<AccountEmailActions, void> {
  /// Changing the account's e-mail addresses.
  ///
  /// A new address appears in the list only after the server accepts its
  /// code. Corporate addresses change the account type, so the profile is
  /// reloaded after adding or deleting one.
  AccountEmailActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountEmailActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountEmailActionsHash();

  @$internal
  @override
  AccountEmailActions create() => AccountEmailActions();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$accountEmailActionsHash() =>
    r'053eead5013a423d7c08ad9c894c6b4965d44a3c';

/// Changing the account's e-mail addresses.
///
/// A new address appears in the list only after the server accepts its
/// code. Corporate addresses change the account type, so the profile is
/// reloaded after adding or deleting one.

abstract class _$AccountEmailActions extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
