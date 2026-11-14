// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feed_filters.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Feed filters selected by the user, restored on the next app start.

@ProviderFor(FeedFilterSelection)
final feedFilterSelectionProvider = FeedFilterSelectionProvider._();

/// Feed filters selected by the user, restored on the next app start.
final class FeedFilterSelectionProvider
    extends $AsyncNotifierProvider<FeedFilterSelection, FeedFilters> {
  /// Feed filters selected by the user, restored on the next app start.
  FeedFilterSelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'feedFilterSelectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$feedFilterSelectionHash();

  @$internal
  @override
  FeedFilterSelection create() => FeedFilterSelection();
}

String _$feedFilterSelectionHash() =>
    r'2b1319b52b366e0823379f7ddee1462a1ec93f6c';

/// Feed filters selected by the user, restored on the next app start.

abstract class _$FeedFilterSelection extends $AsyncNotifier<FeedFilters> {
  FutureOr<FeedFilters> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<FeedFilters>, FeedFilters>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<FeedFilters>, FeedFilters>,
              AsyncValue<FeedFilters>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
