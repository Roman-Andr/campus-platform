// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sign_in_flow.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Steps of signing in: e-mail, code, then names for a new account.

@ProviderFor(SignInFlow)
final signInFlowProvider = SignInFlowProvider._();

/// Steps of signing in: e-mail, code, then names for a new account.
final class SignInFlowProvider
    extends $NotifierProvider<SignInFlow, SignInDraft> {
  /// Steps of signing in: e-mail, code, then names for a new account.
  SignInFlowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'signInFlowProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$signInFlowHash();

  @$internal
  @override
  SignInFlow create() => SignInFlow();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SignInDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SignInDraft>(value),
    );
  }
}

String _$signInFlowHash() => r'491625fa0be4d3f6c8f3cbc9c5dd2e6150346ecb';

/// Steps of signing in: e-mail, code, then names for a new account.

abstract class _$SignInFlow extends $Notifier<SignInDraft> {
  SignInDraft build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SignInDraft, SignInDraft>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SignInDraft, SignInDraft>,
              SignInDraft,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
