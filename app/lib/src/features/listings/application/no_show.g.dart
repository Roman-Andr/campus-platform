// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'no_show.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(noShowConfig)
final noShowConfigProvider = NoShowConfigProvider._();

final class NoShowConfigProvider
    extends $FunctionalProvider<NoShowConfig, NoShowConfig, NoShowConfig>
    with $Provider<NoShowConfig> {
  NoShowConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'noShowConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$noShowConfigHash();

  @$internal
  @override
  $ProviderElement<NoShowConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NoShowConfig create(Ref ref) {
    return noShowConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NoShowConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NoShowConfig>(value),
    );
  }
}

String _$noShowConfigHash() => r'9cf77d1f8f124eeefbb84a6f6f03adbdb6461dd0';

/// The current result of a personal interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a mark made on another device, a
/// mutual allegation, a late QR lift and an automatic rule are never hidden
/// behind a stale response. A realtime publication only wakes [sync] up,
/// which loads the whole state again.

@ProviderFor(InteractionNoShow)
final interactionNoShowProvider = InteractionNoShowFamily._();

/// The current result of a personal interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a mark made on another device, a
/// mutual allegation, a late QR lift and an automatic rule are never hidden
/// behind a stale response. A realtime publication only wakes [sync] up,
/// which loads the whole state again.
final class InteractionNoShowProvider
    extends $AsyncNotifierProvider<InteractionNoShow, NoShowOutput> {
  /// The current result of a personal interaction.
  ///
  /// The state always comes from the server: the screen reloads it after every
  /// attempt, including a refused one, so a mark made on another device, a
  /// mutual allegation, a late QR lift and an automatic rule are never hidden
  /// behind a stale response. A realtime publication only wakes [sync] up,
  /// which loads the whole state again.
  InteractionNoShowProvider._({
    required InteractionNoShowFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: listingRetry,
         name: r'interactionNoShowProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$interactionNoShowHash();

  @override
  String toString() {
    return r'interactionNoShowProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  InteractionNoShow create() => InteractionNoShow();

  @override
  bool operator ==(Object other) {
    return other is InteractionNoShowProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$interactionNoShowHash() => r'df0d60816544456b3048dbbd928c78932447c417';

/// The current result of a personal interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a mark made on another device, a
/// mutual allegation, a late QR lift and an automatic rule are never hidden
/// behind a stale response. A realtime publication only wakes [sync] up,
/// which loads the whole state again.

final class InteractionNoShowFamily extends $Family
    with
        $ClassFamilyOverride<
          InteractionNoShow,
          AsyncValue<NoShowOutput>,
          NoShowOutput,
          FutureOr<NoShowOutput>,
          (String, String)
        > {
  InteractionNoShowFamily._()
    : super(
        retry: listingRetry,
        name: r'interactionNoShowProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The current result of a personal interaction.
  ///
  /// The state always comes from the server: the screen reloads it after every
  /// attempt, including a refused one, so a mark made on another device, a
  /// mutual allegation, a late QR lift and an automatic rule are never hidden
  /// behind a stale response. A realtime publication only wakes [sync] up,
  /// which loads the whole state again.

  InteractionNoShowProvider call((String, String) ids) =>
      InteractionNoShowProvider._(argument: ids, from: this);

  @override
  String toString() => r'interactionNoShowProvider';
}

/// The current result of a personal interaction.
///
/// The state always comes from the server: the screen reloads it after every
/// attempt, including a refused one, so a mark made on another device, a
/// mutual allegation, a late QR lift and an automatic rule are never hidden
/// behind a stale response. A realtime publication only wakes [sync] up,
/// which loads the whole state again.

abstract class _$InteractionNoShow extends $AsyncNotifier<NoShowOutput> {
  late final _$args = ref.$arg as (String, String);
  (String, String) get ids => _$args;

  FutureOr<NoShowOutput> build((String, String) ids);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<NoShowOutput>, NoShowOutput>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<NoShowOutput>, NoShowOutput>,
              AsyncValue<NoShowOutput>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Votes and marks of one event.
///
/// Like the personal state, it is reloaded after every attempt and woken by
/// the publications of the event, so a vote of another participant, the
/// organiser's dispute and the automatic marks appear without a restart.

@ProviderFor(EventNoShow)
final eventNoShowProvider = EventNoShowFamily._();

/// Votes and marks of one event.
///
/// Like the personal state, it is reloaded after every attempt and woken by
/// the publications of the event, so a vote of another participant, the
/// organiser's dispute and the automatic marks appear without a restart.
final class EventNoShowProvider
    extends $AsyncNotifierProvider<EventNoShow, EventNoShowOutput> {
  /// Votes and marks of one event.
  ///
  /// Like the personal state, it is reloaded after every attempt and woken by
  /// the publications of the event, so a vote of another participant, the
  /// organiser's dispute and the automatic marks appear without a restart.
  EventNoShowProvider._({
    required EventNoShowFamily super.from,
    required String super.argument,
  }) : super(
         retry: listingRetry,
         name: r'eventNoShowProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$eventNoShowHash();

  @override
  String toString() {
    return r'eventNoShowProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  EventNoShow create() => EventNoShow();

  @override
  bool operator ==(Object other) {
    return other is EventNoShowProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$eventNoShowHash() => r'f4139c0b227d0129b8e37fae1ebf21df9e627bae';

/// Votes and marks of one event.
///
/// Like the personal state, it is reloaded after every attempt and woken by
/// the publications of the event, so a vote of another participant, the
/// organiser's dispute and the automatic marks appear without a restart.

final class EventNoShowFamily extends $Family
    with
        $ClassFamilyOverride<
          EventNoShow,
          AsyncValue<EventNoShowOutput>,
          EventNoShowOutput,
          FutureOr<EventNoShowOutput>,
          String
        > {
  EventNoShowFamily._()
    : super(
        retry: listingRetry,
        name: r'eventNoShowProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Votes and marks of one event.
  ///
  /// Like the personal state, it is reloaded after every attempt and woken by
  /// the publications of the event, so a vote of another participant, the
  /// organiser's dispute and the automatic marks appear without a restart.

  EventNoShowProvider call(String listingId) =>
      EventNoShowProvider._(argument: listingId, from: this);

  @override
  String toString() => r'eventNoShowProvider';
}

/// Votes and marks of one event.
///
/// Like the personal state, it is reloaded after every attempt and woken by
/// the publications of the event, so a vote of another participant, the
/// organiser's dispute and the automatic marks appear without a restart.

abstract class _$EventNoShow extends $AsyncNotifier<EventNoShowOutput> {
  late final _$args = ref.$arg as String;
  String get listingId => _$args;

  FutureOr<EventNoShowOutput> build(String listingId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<EventNoShowOutput>, EventNoShowOutput>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<EventNoShowOutput>, EventNoShowOutput>,
              AsyncValue<EventNoShowOutput>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
