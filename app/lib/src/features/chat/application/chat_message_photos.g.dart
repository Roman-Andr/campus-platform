// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message_photos.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Signed short-lived links of the ready photos of one visible message.
///
/// The links are never stored: the API issues new ones on every read, and
/// an expired link is replaced by watching the provider again. A message
/// that was deleted in the meantime no longer has photos, so the request
/// fails with the same not-found problem as the history.

@ProviderFor(chatMessagePhotos)
final chatMessagePhotosProvider = ChatMessagePhotosFamily._();

/// Signed short-lived links of the ready photos of one visible message.
///
/// The links are never stored: the API issues new ones on every read, and
/// an expired link is replaced by watching the provider again. A message
/// that was deleted in the meantime no longer has photos, so the request
/// fails with the same not-found problem as the history.

final class ChatMessagePhotosProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ChatPhotoOutput>>,
          List<ChatPhotoOutput>,
          FutureOr<List<ChatPhotoOutput>>
        >
    with
        $FutureModifier<List<ChatPhotoOutput>>,
        $FutureProvider<List<ChatPhotoOutput>> {
  /// Signed short-lived links of the ready photos of one visible message.
  ///
  /// The links are never stored: the API issues new ones on every read, and
  /// an expired link is replaced by watching the provider again. A message
  /// that was deleted in the meantime no longer has photos, so the request
  /// fails with the same not-found problem as the history.
  ChatMessagePhotosProvider._({
    required ChatMessagePhotosFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'chatMessagePhotosProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatMessagePhotosHash();

  @override
  String toString() {
    return r'chatMessagePhotosProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<ChatPhotoOutput>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ChatPhotoOutput>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return chatMessagePhotos(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatMessagePhotosProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatMessagePhotosHash() => r'c00ae5ce9d1b6dbdf41d57b41a6053f8e168418a';

/// Signed short-lived links of the ready photos of one visible message.
///
/// The links are never stored: the API issues new ones on every read, and
/// an expired link is replaced by watching the provider again. A message
/// that was deleted in the meantime no longer has photos, so the request
/// fails with the same not-found problem as the history.

final class ChatMessagePhotosFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<ChatPhotoOutput>>,
          (String, String)
        > {
  ChatMessagePhotosFamily._()
    : super(
        retry: null,
        name: r'chatMessagePhotosProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Signed short-lived links of the ready photos of one visible message.
  ///
  /// The links are never stored: the API issues new ones on every read, and
  /// an expired link is replaced by watching the provider again. A message
  /// that was deleted in the meantime no longer has photos, so the request
  /// fails with the same not-found problem as the history.

  ChatMessagePhotosProvider call(String chatId, String messageId) =>
      ChatMessagePhotosProvider._(argument: (chatId, messageId), from: this);

  @override
  String toString() => r'chatMessagePhotosProvider';
}
