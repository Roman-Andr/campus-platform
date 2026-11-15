import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';

part 'purchase.g.dart';

// Expected API errors must reach the card at once: a repeated join could hide
// the fact that the free volume changed while the form was open.
Duration? purchaseRetry(int retryCount, Object error) => null;

/// The account's accepted share of [listingId]; null when it holds none.
///
/// A 404 is the normal answer for a non-participant, not an error.
@Riverpod(retry: purchaseRetry)
Future<PurchaseShareOutput?> myPurchaseShare(Ref ref, String listingId) async {
  try {
    return await ref
        .watch(campusApiProvider)
        .listings
        .myPurchaseShare(listingId: listingId);
  } on Object catch (error) {
    if (ApiFailure.from(error) case ProblemFailure(status: 404)) return null;
    rethrow;
  }
}

/// Every accepted share with its amount; the organiser sees the composition.
@Riverpod(retry: purchaseRetry)
Future<PurchaseComposition> purchaseComposition(Ref ref, String listingId) =>
    ref
        .watch(campusApiProvider)
        .listings
        .purchaseComposition(listingId: listingId);
