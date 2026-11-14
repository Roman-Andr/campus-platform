// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction_timeline.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The append-only history of an interaction as the server orders it
/// (time, then id). Pages are merged by event id, so a page boundary that
/// moves between requests never shows an event twice.

@ProviderFor(InteractionTimeline)
final interactionTimelineProvider = InteractionTimelineFamily._();

/// The append-only history of an interaction as the server orders it
/// (time, then id). Pages are merged by event id, so a page boundary that
/// moves between requests never shows an event twice.
final class InteractionTimelineProvider
    extends $AsyncNotifierProvider<InteractionTimeline, TimelinePage> {
  /// The append-only history of an interaction as the server orders it
  /// (time, then id). Pages are merged by event id, so a page boundary that
  /// moves between requests never shows an event twice.
  InteractionTimelineProvider._({
    required InteractionTimelineFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: listingRetry,
         name: r'interactionTimelineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$interactionTimelineHash();

  @override
  String toString() {
    return r'interactionTimelineProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  InteractionTimeline create() => InteractionTimeline();

  @override
  bool operator ==(Object other) {
    return other is InteractionTimelineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$interactionTimelineHash() =>
    r'26a3abd5e700ecd10fece5421472364594262874';

/// The append-only history of an interaction as the server orders it
/// (time, then id). Pages are merged by event id, so a page boundary that
/// moves between requests never shows an event twice.

final class InteractionTimelineFamily extends $Family
    with
        $ClassFamilyOverride<
          InteractionTimeline,
          AsyncValue<TimelinePage>,
          TimelinePage,
          FutureOr<TimelinePage>,
          (String, String)
        > {
  InteractionTimelineFamily._()
    : super(
        retry: listingRetry,
        name: r'interactionTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The append-only history of an interaction as the server orders it
  /// (time, then id). Pages are merged by event id, so a page boundary that
  /// moves between requests never shows an event twice.

  InteractionTimelineProvider call(String listingId, String interactionId) =>
      InteractionTimelineProvider._(
        argument: (listingId, interactionId),
        from: this,
      );

  @override
  String toString() => r'interactionTimelineProvider';
}

/// The append-only history of an interaction as the server orders it
/// (time, then id). Pages are merged by event id, so a page boundary that
/// moves between requests never shows an event twice.

abstract class _$InteractionTimeline extends $AsyncNotifier<TimelinePage> {
  late final _$args = ref.$arg as (String, String);
  String get listingId => _$args.$1;
  String get interactionId => _$args.$2;

  FutureOr<TimelinePage> build(String listingId, String interactionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<TimelinePage>, TimelinePage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<TimelinePage>, TimelinePage>,
              AsyncValue<TimelinePage>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
