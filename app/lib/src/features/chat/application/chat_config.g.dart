// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatConfig)
final chatConfigProvider = ChatConfigProvider._();

final class ChatConfigProvider
    extends $FunctionalProvider<ChatConfig, ChatConfig, ChatConfig>
    with $Provider<ChatConfig> {
  ChatConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatConfigHash();

  @$internal
  @override
  $ProviderElement<ChatConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ChatConfig create(Ref ref) {
    return chatConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatConfig>(value),
    );
  }
}

String _$chatConfigHash() => r'dfa2cff9c4108f2f13feba2d2e448d0e6e6de870';
