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

@ProviderFor(ownListings)
final ownListingsProvider = OwnListingsFamily._();

final class OwnListingsProvider
    extends
        $FunctionalProvider<
          AsyncValue<PageListingOutput>,
          PageListingOutput,
          FutureOr<PageListingOutput>
        >
    with
        $FutureModifier<PageListingOutput>,
        $FutureProvider<PageListingOutput> {
  OwnListingsProvider._({
    required OwnListingsFamily super.from,
    required String? super.argument,
  }) : super(
         retry: listingRetry,
         name: r'ownListingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ownListingsHash();

  @override
  String toString() {
    return r'ownListingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PageListingOutput> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PageListingOutput> create(Ref ref) {
    final argument = this.argument as String?;
    return ownListings(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OwnListingsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ownListingsHash() => r'65d6edbf32ac4c13fea00b9cf5de3d8b8fca2974';

final class OwnListingsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PageListingOutput>, String?> {
  OwnListingsFamily._()
    : super(
        retry: listingRetry,
        name: r'ownListingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  OwnListingsProvider call(String? cursor) =>
      OwnListingsProvider._(argument: cursor, from: this);

  @override
  String toString() => r'ownListingsProvider';
}

@ProviderFor(ownReservations)
final ownReservationsProvider = OwnReservationsFamily._();

final class OwnReservationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<PageInteractionOutput>,
          PageInteractionOutput,
          FutureOr<PageInteractionOutput>
        >
    with
        $FutureModifier<PageInteractionOutput>,
        $FutureProvider<PageInteractionOutput> {
  OwnReservationsProvider._({
    required OwnReservationsFamily super.from,
    required String? super.argument,
  }) : super(
         retry: listingRetry,
         name: r'ownReservationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ownReservationsHash();

  @override
  String toString() {
    return r'ownReservationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PageInteractionOutput> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PageInteractionOutput> create(Ref ref) {
    final argument = this.argument as String?;
    return ownReservations(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OwnReservationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ownReservationsHash() => r'a27c284e96eba8f354b9dde7629570ec887926a8';

final class OwnReservationsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PageInteractionOutput>, String?> {
  OwnReservationsFamily._()
    : super(
        retry: listingRetry,
        name: r'ownReservationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  OwnReservationsProvider call(String? cursor) =>
      OwnReservationsProvider._(argument: cursor, from: this);

  @override
  String toString() => r'ownReservationsProvider';
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
