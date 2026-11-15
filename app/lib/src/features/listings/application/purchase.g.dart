// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The account's accepted share of [listingId]; null when it holds none.
///
/// A 404 is the normal answer for a non-participant, not an error.

@ProviderFor(myPurchaseShare)
final myPurchaseShareProvider = MyPurchaseShareFamily._();

/// The account's accepted share of [listingId]; null when it holds none.
///
/// A 404 is the normal answer for a non-participant, not an error.

final class MyPurchaseShareProvider
    extends
        $FunctionalProvider<
          AsyncValue<PurchaseShareOutput?>,
          PurchaseShareOutput?,
          FutureOr<PurchaseShareOutput?>
        >
    with
        $FutureModifier<PurchaseShareOutput?>,
        $FutureProvider<PurchaseShareOutput?> {
  /// The account's accepted share of [listingId]; null when it holds none.
  ///
  /// A 404 is the normal answer for a non-participant, not an error.
  MyPurchaseShareProvider._({
    required MyPurchaseShareFamily super.from,
    required String super.argument,
  }) : super(
         retry: purchaseRetry,
         name: r'myPurchaseShareProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$myPurchaseShareHash();

  @override
  String toString() {
    return r'myPurchaseShareProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PurchaseShareOutput?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PurchaseShareOutput?> create(Ref ref) {
    final argument = this.argument as String;
    return myPurchaseShare(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MyPurchaseShareProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$myPurchaseShareHash() => r'b33b54b75003cf922fc827b81465d09fa7e44032';

/// The account's accepted share of [listingId]; null when it holds none.
///
/// A 404 is the normal answer for a non-participant, not an error.

final class MyPurchaseShareFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PurchaseShareOutput?>, String> {
  MyPurchaseShareFamily._()
    : super(
        retry: purchaseRetry,
        name: r'myPurchaseShareProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The account's accepted share of [listingId]; null when it holds none.
  ///
  /// A 404 is the normal answer for a non-participant, not an error.

  MyPurchaseShareProvider call(String listingId) =>
      MyPurchaseShareProvider._(argument: listingId, from: this);

  @override
  String toString() => r'myPurchaseShareProvider';
}

/// Every accepted share with its amount; the organiser sees the composition.

@ProviderFor(purchaseComposition)
final purchaseCompositionProvider = PurchaseCompositionFamily._();

/// Every accepted share with its amount; the organiser sees the composition.

final class PurchaseCompositionProvider
    extends
        $FunctionalProvider<
          AsyncValue<PurchaseComposition>,
          PurchaseComposition,
          FutureOr<PurchaseComposition>
        >
    with
        $FutureModifier<PurchaseComposition>,
        $FutureProvider<PurchaseComposition> {
  /// Every accepted share with its amount; the organiser sees the composition.
  PurchaseCompositionProvider._({
    required PurchaseCompositionFamily super.from,
    required String super.argument,
  }) : super(
         retry: purchaseRetry,
         name: r'purchaseCompositionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$purchaseCompositionHash();

  @override
  String toString() {
    return r'purchaseCompositionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PurchaseComposition> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PurchaseComposition> create(Ref ref) {
    final argument = this.argument as String;
    return purchaseComposition(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PurchaseCompositionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$purchaseCompositionHash() =>
    r'8d3ddce6c5408d6cf9e422baeec744885aa19901';

/// Every accepted share with its amount; the organiser sees the composition.

final class PurchaseCompositionFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PurchaseComposition>, String> {
  PurchaseCompositionFamily._()
    : super(
        retry: purchaseRetry,
        name: r'purchaseCompositionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every accepted share with its amount; the organiser sees the composition.

  PurchaseCompositionProvider call(String listingId) =>
      PurchaseCompositionProvider._(argument: listingId, from: this);

  @override
  String toString() => r'purchaseCompositionProvider';
}
