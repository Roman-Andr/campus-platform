// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_photo_draft.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Photos of one chat composer.
///
/// Uploading starts as soon as files are chosen and the composer may send
/// the message only when every chosen photo is ready: the server rejects an
/// unprocessed id, and a rejected or failed photo never hides that fact.

@ProviderFor(ChatPhotoDraft)
final chatPhotoDraftProvider = ChatPhotoDraftFamily._();

/// Photos of one chat composer.
///
/// Uploading starts as soon as files are chosen and the composer may send
/// the message only when every chosen photo is ready: the server rejects an
/// unprocessed id, and a rejected or failed photo never hides that fact.
final class ChatPhotoDraftProvider
    extends $NotifierProvider<ChatPhotoDraft, List<ChatPhotoSlot>> {
  /// Photos of one chat composer.
  ///
  /// Uploading starts as soon as files are chosen and the composer may send
  /// the message only when every chosen photo is ready: the server rejects an
  /// unprocessed id, and a rejected or failed photo never hides that fact.
  ChatPhotoDraftProvider._({
    required ChatPhotoDraftFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'chatPhotoDraftProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatPhotoDraftHash();

  @override
  String toString() {
    return r'chatPhotoDraftProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ChatPhotoDraft create() => ChatPhotoDraft();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ChatPhotoSlot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ChatPhotoSlot>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatPhotoDraftProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatPhotoDraftHash() => r'0810c8aa3208b6e41ff34ace2553b8dbf1c990b4';

/// Photos of one chat composer.
///
/// Uploading starts as soon as files are chosen and the composer may send
/// the message only when every chosen photo is ready: the server rejects an
/// unprocessed id, and a rejected or failed photo never hides that fact.

final class ChatPhotoDraftFamily extends $Family
    with
        $ClassFamilyOverride<
          ChatPhotoDraft,
          List<ChatPhotoSlot>,
          List<ChatPhotoSlot>,
          List<ChatPhotoSlot>,
          String
        > {
  ChatPhotoDraftFamily._()
    : super(
        retry: null,
        name: r'chatPhotoDraftProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Photos of one chat composer.
  ///
  /// Uploading starts as soon as files are chosen and the composer may send
  /// the message only when every chosen photo is ready: the server rejects an
  /// unprocessed id, and a rejected or failed photo never hides that fact.

  ChatPhotoDraftProvider call(String chatId) =>
      ChatPhotoDraftProvider._(argument: chatId, from: this);

  @override
  String toString() => r'chatPhotoDraftProvider';
}

/// Photos of one chat composer.
///
/// Uploading starts as soon as files are chosen and the composer may send
/// the message only when every chosen photo is ready: the server rejects an
/// unprocessed id, and a rejected or failed photo never hides that fact.

abstract class _$ChatPhotoDraft extends $Notifier<List<ChatPhotoSlot>> {
  late final _$args = ref.$arg as String;
  String get chatId => _$args;

  List<ChatPhotoSlot> build(String chatId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<ChatPhotoSlot>, List<ChatPhotoSlot>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<ChatPhotoSlot>, List<ChatPhotoSlot>>,
              List<ChatPhotoSlot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
