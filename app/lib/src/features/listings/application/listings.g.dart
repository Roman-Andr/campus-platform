// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listings.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ListingFeed)
final listingFeedProvider = ListingFeedFamily._();

final class ListingFeedProvider
    extends $AsyncNotifierProvider<ListingFeed, PageListingOutput> {
  ListingFeedProvider._({
    required ListingFeedFamily super.from,
    required Visibility super.argument,
  }) : super(
         retry: listingRetry,
         name: r'listingFeedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$listingFeedHash();

  @override
  String toString() {
    return r'listingFeedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ListingFeed create() => ListingFeed();

  @override
  bool operator ==(Object other) {
    return other is ListingFeedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$listingFeedHash() => r'f0aed3640dfc64b41e71f641d4677397242f9465';

final class ListingFeedFamily extends $Family
    with
        $ClassFamilyOverride<
          ListingFeed,
          AsyncValue<PageListingOutput>,
          PageListingOutput,
          FutureOr<PageListingOutput>,
          Visibility
        > {
  ListingFeedFamily._()
    : super(
        retry: listingRetry,
        name: r'listingFeedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ListingFeedProvider call(Visibility area) =>
      ListingFeedProvider._(argument: area, from: this);

  @override
  String toString() => r'listingFeedProvider';
}

abstract class _$ListingFeed extends $AsyncNotifier<PageListingOutput> {
  late final _$args = ref.$arg as Visibility;
  Visibility get area => _$args;

  FutureOr<PageListingOutput> build(Visibility area);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<PageListingOutput>, PageListingOutput>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<PageListingOutput>, PageListingOutput>,
              AsyncValue<PageListingOutput>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(listingCategories)
final listingCategoriesProvider = ListingCategoriesProvider._();

final class ListingCategoriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CategoryOutput>>,
          List<CategoryOutput>,
          FutureOr<List<CategoryOutput>>
        >
    with
        $FutureModifier<List<CategoryOutput>>,
        $FutureProvider<List<CategoryOutput>> {
  ListingCategoriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: listingRetry,
        name: r'listingCategoriesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$listingCategoriesHash();

  @$internal
  @override
  $FutureProviderElement<List<CategoryOutput>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CategoryOutput>> create(Ref ref) {
    return listingCategories(ref);
  }
}

String _$listingCategoriesHash() => r'f37a678c15e994bee91872249da31a32a7f3fac9';

@ProviderFor(listing)
final listingProvider = ListingFamily._();

final class ListingProvider
    extends
        $FunctionalProvider<
          AsyncValue<ListingOutput>,
          ListingOutput,
          FutureOr<ListingOutput>
        >
    with $FutureModifier<ListingOutput>, $FutureProvider<ListingOutput> {
  ListingProvider._({
    required ListingFamily super.from,
    required String super.argument,
  }) : super(
         retry: listingRetry,
         name: r'listingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$listingHash();

  @override
  String toString() {
    return r'listingProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ListingOutput> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ListingOutput> create(Ref ref) {
    final argument = this.argument as String;
    return listing(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ListingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$listingHash() => r'09a7f2ea7b1dd4c6cee226f5624817553e936bfd';

final class ListingFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ListingOutput>, String> {
  ListingFamily._()
    : super(
        retry: listingRetry,
        name: r'listingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ListingProvider call(String id) =>
      ListingProvider._(argument: id, from: this);

  @override
  String toString() => r'listingProvider';
}

@ProviderFor(incoming)
final incomingProvider = IncomingFamily._();

final class IncomingProvider
    extends
        $FunctionalProvider<
          AsyncValue<PageInteractionOutput>,
          PageInteractionOutput,
          FutureOr<PageInteractionOutput>
        >
    with
        $FutureModifier<PageInteractionOutput>,
        $FutureProvider<PageInteractionOutput> {
  IncomingProvider._({
    required IncomingFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: listingRetry,
         name: r'incomingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$incomingHash();

  @override
  String toString() {
    return r'incomingProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<PageInteractionOutput> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PageInteractionOutput> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return incoming(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is IncomingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$incomingHash() => r'c37e15f177960a4149ece3132baf671f531fb51b';

final class IncomingFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<PageInteractionOutput>,
          (String, String?)
        > {
  IncomingFamily._()
    : super(
        retry: listingRetry,
        name: r'incomingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  IncomingProvider call(String id, String? cursor) =>
      IncomingProvider._(argument: (id, cursor), from: this);

  @override
  String toString() => r'incomingProvider';
}

/// Processed photos of a listing in their order. Their links are signed
/// and short-lived, so the list refreshes itself shortly before they expire.

@ProviderFor(listingPhotos)
final listingPhotosProvider = ListingPhotosFamily._();

/// Processed photos of a listing in their order. Their links are signed
/// and short-lived, so the list refreshes itself shortly before they expire.

final class ListingPhotosProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PhotoOutput>>,
          List<PhotoOutput>,
          FutureOr<List<PhotoOutput>>
        >
    with
        $FutureModifier<List<PhotoOutput>>,
        $FutureProvider<List<PhotoOutput>> {
  /// Processed photos of a listing in their order. Their links are signed
  /// and short-lived, so the list refreshes itself shortly before they expire.
  ListingPhotosProvider._({
    required ListingPhotosFamily super.from,
    required String super.argument,
  }) : super(
         retry: listingRetry,
         name: r'listingPhotosProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$listingPhotosHash();

  @override
  String toString() {
    return r'listingPhotosProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<PhotoOutput>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<PhotoOutput>> create(Ref ref) {
    final argument = this.argument as String;
    return listingPhotos(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ListingPhotosProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$listingPhotosHash() => r'e1d8cb0399a22e57e90a3ea44f4490fcbe0da0e3';

/// Processed photos of a listing in their order. Their links are signed
/// and short-lived, so the list refreshes itself shortly before they expire.

final class ListingPhotosFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<PhotoOutput>>, String> {
  ListingPhotosFamily._()
    : super(
        retry: listingRetry,
        name: r'listingPhotosProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Processed photos of a listing in their order. Their links are signed
  /// and short-lived, so the list refreshes itself shortly before they expire.

  ListingPhotosProvider call(String id) =>
      ListingPhotosProvider._(argument: id, from: this);

  @override
  String toString() => r'listingPhotosProvider';
}
