// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_photo_uploader.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatPhotoUploader)
final chatPhotoUploaderProvider = ChatPhotoUploaderProvider._();

final class ChatPhotoUploaderProvider
    extends
        $FunctionalProvider<
          ChatPhotoUploader,
          ChatPhotoUploader,
          ChatPhotoUploader
        >
    with $Provider<ChatPhotoUploader> {
  ChatPhotoUploaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatPhotoUploaderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatPhotoUploaderHash();

  @$internal
  @override
  $ProviderElement<ChatPhotoUploader> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ChatPhotoUploader create(Ref ref) {
    return chatPhotoUploader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatPhotoUploader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatPhotoUploader>(value),
    );
  }
}

String _$chatPhotoUploaderHash() => r'a81f35064c4876b4d74cdaaf027f77f4b423660a';
