// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listing_photo_draft.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Photos of one listing form. Uploads start as soon as files are chosen;
/// a rejected or failed photo never blocks publishing the others.

@ProviderFor(ListingPhotoDraft)
final listingPhotoDraftProvider = ListingPhotoDraftProvider._();

/// Photos of one listing form. Uploads start as soon as files are chosen;
/// a rejected or failed photo never blocks publishing the others.
final class ListingPhotoDraftProvider
    extends $NotifierProvider<ListingPhotoDraft, List<PhotoSlot>> {
  /// Photos of one listing form. Uploads start as soon as files are chosen;
  /// a rejected or failed photo never blocks publishing the others.
  ListingPhotoDraftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'listingPhotoDraftProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$listingPhotoDraftHash();

  @$internal
  @override
  ListingPhotoDraft create() => ListingPhotoDraft();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PhotoSlot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PhotoSlot>>(value),
    );
  }
}

String _$listingPhotoDraftHash() => r'32e10a3d0fb799c9cc1816e48c8da7e5ebf3ff93';

/// Photos of one listing form. Uploads start as soon as files are chosen;
/// a rejected or failed photo never blocks publishing the others.

abstract class _$ListingPhotoDraft extends $Notifier<List<PhotoSlot>> {
  List<PhotoSlot> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<PhotoSlot>, List<PhotoSlot>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<PhotoSlot>, List<PhotoSlot>>,
              List<PhotoSlot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
