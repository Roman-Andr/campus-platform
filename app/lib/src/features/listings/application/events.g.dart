// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Resolves the own seat from the listing, own interactions and the queue.
///
/// Registration is an accepted interaction; the server creates it at signup,
/// so there is no pending stage to wait for.

@ProviderFor(eventSeat)
final eventSeatProvider = EventSeatFamily._();

/// Resolves the own seat from the listing, own interactions and the queue.
///
/// Registration is an accepted interaction; the server creates it at signup,
/// so there is no pending stage to wait for.

final class EventSeatProvider
    extends
        $FunctionalProvider<
          AsyncValue<EventSeat>,
          EventSeat,
          FutureOr<EventSeat>
        >
    with $FutureModifier<EventSeat>, $FutureProvider<EventSeat> {
  /// Resolves the own seat from the listing, own interactions and the queue.
  ///
  /// Registration is an accepted interaction; the server creates it at signup,
  /// so there is no pending stage to wait for.
  EventSeatProvider._({
    required EventSeatFamily super.from,
    required String super.argument,
  }) : super(
         retry: eventRetry,
         name: r'eventSeatProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$eventSeatHash();

  @override
  String toString() {
    return r'eventSeatProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<EventSeat> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<EventSeat> create(Ref ref) {
    final argument = this.argument as String;
    return eventSeat(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is EventSeatProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$eventSeatHash() => r'78cd17ca7da6f45931434bac259de4f2e4dcb118';

/// Resolves the own seat from the listing, own interactions and the queue.
///
/// Registration is an accepted interaction; the server creates it at signup,
/// so there is no pending stage to wait for.

final class EventSeatFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<EventSeat>, String> {
  EventSeatFamily._()
    : super(
        retry: eventRetry,
        name: r'eventSeatProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Resolves the own seat from the listing, own interactions and the queue.
  ///
  /// Registration is an accepted interaction; the server creates it at signup,
  /// so there is no pending stage to wait for.

  EventSeatProvider call(String listingId) =>
      EventSeatProvider._(argument: listingId, from: this);

  @override
  String toString() => r'eventSeatProvider';
}
