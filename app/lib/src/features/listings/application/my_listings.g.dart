// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'my_listings.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MyListings)
final myListingsProvider = MyListingsFamily._();

final class MyListingsProvider
    extends $AsyncNotifierProvider<MyListings, Snapshot<PageListingOutput>> {
  MyListingsProvider._({
    required MyListingsFamily super.from,
    required MySection super.argument,
  }) : super(
         retry: listingRetry,
         name: r'myListingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$myListingsHash();

  @override
  String toString() {
    return r'myListingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MyListings create() => MyListings();

  @override
  bool operator ==(Object other) {
    return other is MyListingsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$myListingsHash() => r'ba4e1cbfa3f8f1da53620cbffac57a7487b22479';

final class MyListingsFamily extends $Family
    with
        $ClassFamilyOverride<
          MyListings,
          AsyncValue<Snapshot<PageListingOutput>>,
          Snapshot<PageListingOutput>,
          FutureOr<Snapshot<PageListingOutput>>,
          MySection
        > {
  MyListingsFamily._()
    : super(
        retry: listingRetry,
        name: r'myListingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MyListingsProvider call(MySection section) =>
      MyListingsProvider._(argument: section, from: this);

  @override
  String toString() => r'myListingsProvider';
}

abstract class _$MyListings
    extends $AsyncNotifier<Snapshot<PageListingOutput>> {
  late final _$args = ref.$arg as MySection;
  MySection get section => _$args;

  FutureOr<Snapshot<PageListingOutput>> build(MySection section);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<Snapshot<PageListingOutput>>,
              Snapshot<PageListingOutput>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<Snapshot<PageListingOutput>>,
                Snapshot<PageListingOutput>
              >,
              AsyncValue<Snapshot<PageListingOutput>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(MyParticipation)
final myParticipationProvider = MyParticipationProvider._();

final class MyParticipationProvider
    extends
        $AsyncNotifierProvider<
          MyParticipation,
          Snapshot<PageParticipationOutput>
        > {
  MyParticipationProvider._()
    : super(
        from: null,
        argument: null,
        retry: listingRetry,
        name: r'myParticipationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myParticipationHash();

  @$internal
  @override
  MyParticipation create() => MyParticipation();
}

String _$myParticipationHash() => r'6c87005e4c7c69f8afc920f57b95e87381422560';

abstract class _$MyParticipation
    extends $AsyncNotifier<Snapshot<PageParticipationOutput>> {
  FutureOr<Snapshot<PageParticipationOutput>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<Snapshot<PageParticipationOutput>>,
              Snapshot<PageParticipationOutput>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<Snapshot<PageParticipationOutput>>,
                Snapshot<PageParticipationOutput>
              >,
              AsyncValue<Snapshot<PageParticipationOutput>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Active queues and place offers of the user (ТЗ п. 5.1.1, модуль 4, п. 9).

@ProviderFor(MyWaitlist)
final myWaitlistProvider = MyWaitlistProvider._();

/// Active queues and place offers of the user (ТЗ п. 5.1.1, модуль 4, п. 9).
final class MyWaitlistProvider
    extends
        $AsyncNotifierProvider<MyWaitlist, Snapshot<PageWaitlistEntryOutput>> {
  /// Active queues and place offers of the user (ТЗ п. 5.1.1, модуль 4, п. 9).
  MyWaitlistProvider._()
    : super(
        from: null,
        argument: null,
        retry: listingRetry,
        name: r'myWaitlistProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myWaitlistHash();

  @$internal
  @override
  MyWaitlist create() => MyWaitlist();
}

String _$myWaitlistHash() => r'7fce79d83435f2da78d96aa48f745c9fca3f1292';

/// Active queues and place offers of the user (ТЗ п. 5.1.1, модуль 4, п. 9).

abstract class _$MyWaitlist
    extends $AsyncNotifier<Snapshot<PageWaitlistEntryOutput>> {
  FutureOr<Snapshot<PageWaitlistEntryOutput>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<Snapshot<PageWaitlistEntryOutput>>,
              Snapshot<PageWaitlistEntryOutput>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<Snapshot<PageWaitlistEntryOutput>>,
                Snapshot<PageWaitlistEntryOutput>
              >,
              AsyncValue<Snapshot<PageWaitlistEntryOutput>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(Favorites)
final favoritesProvider = FavoritesProvider._();

final class FavoritesProvider
    extends $AsyncNotifierProvider<Favorites, Snapshot<PageFavoriteOutput>> {
  FavoritesProvider._()
    : super(
        from: null,
        argument: null,
        retry: listingRetry,
        name: r'favoritesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoritesHash();

  @$internal
  @override
  Favorites create() => Favorites();
}

String _$favoritesHash() => r'2c506941ff4ed6697b2dd5aaf23abb3e7efd5648';

abstract class _$Favorites
    extends $AsyncNotifier<Snapshot<PageFavoriteOutput>> {
  FutureOr<Snapshot<PageFavoriteOutput>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<Snapshot<PageFavoriteOutput>>,
              Snapshot<PageFavoriteOutput>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<Snapshot<PageFavoriteOutput>>,
                Snapshot<PageFavoriteOutput>
              >,
              AsyncValue<Snapshot<PageFavoriteOutput>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The user's latest favorite choices, ahead of reloaded server pages.

@ProviderFor(FavoriteMarks)
final favoriteMarksProvider = FavoriteMarksProvider._();

/// The user's latest favorite choices, ahead of reloaded server pages.
final class FavoriteMarksProvider
    extends $NotifierProvider<FavoriteMarks, Map<String, bool>> {
  /// The user's latest favorite choices, ahead of reloaded server pages.
  FavoriteMarksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoriteMarksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoriteMarksHash();

  @$internal
  @override
  FavoriteMarks create() => FavoriteMarks();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, bool> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, bool>>(value),
    );
  }
}

String _$favoriteMarksHash() => r'2409359d406f4258940d7683b062699790220faf';

/// The user's latest favorite choices, ahead of reloaded server pages.

abstract class _$FavoriteMarks extends $Notifier<Map<String, bool>> {
  Map<String, bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Map<String, bool>, Map<String, bool>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, bool>, Map<String, bool>>,
              Map<String, bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
