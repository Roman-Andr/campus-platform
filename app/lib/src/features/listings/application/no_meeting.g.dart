// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'no_meeting.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Both consents and the completion state of one interaction.
///
/// The state always comes from the server, so a screen restored after a
/// network failure, an app restart or on another device shows the same
/// consents and completion. [confirm] stores the server response, so the
/// caller sees the waiting or completed state without a second request.

@ProviderFor(NoMeetingState)
final noMeetingStateProvider = NoMeetingStateFamily._();

/// Both consents and the completion state of one interaction.
///
/// The state always comes from the server, so a screen restored after a
/// network failure, an app restart or on another device shows the same
/// consents and completion. [confirm] stores the server response, so the
/// caller sees the waiting or completed state without a second request.
final class NoMeetingStateProvider
    extends $AsyncNotifierProvider<NoMeetingState, NoMeetingOutput> {
  /// Both consents and the completion state of one interaction.
  ///
  /// The state always comes from the server, so a screen restored after a
  /// network failure, an app restart or on another device shows the same
  /// consents and completion. [confirm] stores the server response, so the
  /// caller sees the waiting or completed state without a second request.
  NoMeetingStateProvider._({
    required NoMeetingStateFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: listingRetry,
         name: r'noMeetingStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$noMeetingStateHash();

  @override
  String toString() {
    return r'noMeetingStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  NoMeetingState create() => NoMeetingState();

  @override
  bool operator ==(Object other) {
    return other is NoMeetingStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$noMeetingStateHash() => r'dae6bdd0a60b4de81201176bdef1f6efbb56dcb0';

/// Both consents and the completion state of one interaction.
///
/// The state always comes from the server, so a screen restored after a
/// network failure, an app restart or on another device shows the same
/// consents and completion. [confirm] stores the server response, so the
/// caller sees the waiting or completed state without a second request.

final class NoMeetingStateFamily extends $Family
    with
        $ClassFamilyOverride<
          NoMeetingState,
          AsyncValue<NoMeetingOutput>,
          NoMeetingOutput,
          FutureOr<NoMeetingOutput>,
          (String, String)
        > {
  NoMeetingStateFamily._()
    : super(
        retry: listingRetry,
        name: r'noMeetingStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Both consents and the completion state of one interaction.
  ///
  /// The state always comes from the server, so a screen restored after a
  /// network failure, an app restart or on another device shows the same
  /// consents and completion. [confirm] stores the server response, so the
  /// caller sees the waiting or completed state without a second request.

  NoMeetingStateProvider call((String, String) ids) =>
      NoMeetingStateProvider._(argument: ids, from: this);

  @override
  String toString() => r'noMeetingStateProvider';
}

/// Both consents and the completion state of one interaction.
///
/// The state always comes from the server, so a screen restored after a
/// network failure, an app restart or on another device shows the same
/// consents and completion. [confirm] stores the server response, so the
/// caller sees the waiting or completed state without a second request.

abstract class _$NoMeetingState extends $AsyncNotifier<NoMeetingOutput> {
  late final _$args = ref.$arg as (String, String);
  (String, String) get ids => _$args;

  FutureOr<NoMeetingOutput> build((String, String) ids);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<NoMeetingOutput>, NoMeetingOutput>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<NoMeetingOutput>, NoMeetingOutput>,
              AsyncValue<NoMeetingOutput>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
