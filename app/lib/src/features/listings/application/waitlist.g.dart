// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waitlist.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The user's own active entry in the queue of [listingId]; null outside it.
///
/// A 404 is the normal answer when the user is not queued, not an error.

@ProviderFor(myWaitlistEntry)
final myWaitlistEntryProvider = MyWaitlistEntryFamily._();

/// The user's own active entry in the queue of [listingId]; null outside it.
///
/// A 404 is the normal answer when the user is not queued, not an error.

final class MyWaitlistEntryProvider
    extends
        $FunctionalProvider<
          AsyncValue<WaitlistEntryOutput?>,
          WaitlistEntryOutput?,
          FutureOr<WaitlistEntryOutput?>
        >
    with
        $FutureModifier<WaitlistEntryOutput?>,
        $FutureProvider<WaitlistEntryOutput?> {
  /// The user's own active entry in the queue of [listingId]; null outside it.
  ///
  /// A 404 is the normal answer when the user is not queued, not an error.
  MyWaitlistEntryProvider._({
    required MyWaitlistEntryFamily super.from,
    required String super.argument,
  }) : super(
         retry: waitlistRetry,
         name: r'myWaitlistEntryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$myWaitlistEntryHash();

  @override
  String toString() {
    return r'myWaitlistEntryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<WaitlistEntryOutput?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<WaitlistEntryOutput?> create(Ref ref) {
    final argument = this.argument as String;
    return myWaitlistEntry(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MyWaitlistEntryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$myWaitlistEntryHash() => r'2e3e8134283eeda1586f097b856f9b2c7ee3a14e';

/// The user's own active entry in the queue of [listingId]; null outside it.
///
/// A 404 is the normal answer when the user is not queued, not an error.

final class MyWaitlistEntryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<WaitlistEntryOutput?>, String> {
  MyWaitlistEntryFamily._()
    : super(
        retry: waitlistRetry,
        name: r'myWaitlistEntryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The user's own active entry in the queue of [listingId]; null outside it.
  ///
  /// A 404 is the normal answer when the user is not queued, not an error.

  MyWaitlistEntryProvider call(String listingId) =>
      MyWaitlistEntryProvider._(argument: listingId, from: this);

  @override
  String toString() => r'myWaitlistEntryProvider';
}
