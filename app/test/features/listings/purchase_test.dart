import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:campus/src/core/router/notification_route.dart';
import 'package:campus/src/features/listings/domain/purchase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures.dart';

ListingOutput purchase({
  String stage = 'collecting',
  int maxUnits = 10,
  int taken = 0,
  int? fixedUnits,
  String? deadline,
}) => ListingOutput.fromJson(
  purchaseListingJson(
    stage: stage,
    maxUnits: maxUnits,
    takenUnits: taken,
    fixedUnits: fixedUnits,
    deadline: deadline,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only purchases expose a collection stage', () {
    expect(purchaseStageOf(purchase()), PurchaseStage.collecting);
    expect(
      purchaseStageOf(purchase(stage: 'fixed', fixedUnits: 3)),
      PurchaseStage.fixed,
    );
    expect(purchaseStageOf(ListingOutput.fromJson(listingJson())), isNull);
    expect(isPurchase(ListingOutput.fromJson(listingJson())), isFalse);
  });

  test('free volume is bounded by the maximum and the own share', () {
    final collecting = purchase(taken: 7);
    expect(purchaseLimit(collecting), 10);
    expect(purchaseAvailableUnits(collecting), 3);
    expect(purchaseAvailableUnits(collecting, ownUnits: 2), 5);
    expect(purchaseAvailableUnits(purchase(taken: 12)), 0);

    final fixed = purchase(stage: 'fixed', taken: 6, fixedUnits: 6);
    expect(purchaseLimit(fixed), 6);
    expect(purchaseAvailableUnits(fixed), 0);
    expect(purchaseAvailableUnits(fixed, ownUnits: 2), 2);
  });

  test('a share cannot exceed the free volume', () async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    final listing = purchase(taken: 6);

    expect(purchaseUnitsError(l, listing, 1), isNull);
    expect(purchaseUnitsError(l, listing, 4), isNull);
    expect(purchaseUnitsError(l, listing, 5), 'Only 4 units are available.');
    expect(purchaseUnitsError(l, listing, 0), 'Enter at least one unit.');
    expect(purchaseUnitsError(l, purchase(taken: 10), 1), 'No units are left.');
  });

  test('collection is open only before the deadline of a live purchase', () {
    final now = DateTime.utc(2026, 11, 15, 12);
    final open = purchase(deadline: '2026-11-16T12:00:00Z');
    expect(purchaseCollectionOpen(open, now), isTrue);
    expect(
      purchaseCollectionOpen(purchase(deadline: '2026-11-15T12:00:00Z'), now),
      isFalse,
    );
    expect(purchaseCollectionOpen(purchase(stage: 'fixed'), now), isFalse);
    expect(purchaseCanJoin(open, 'user-1', hasShare: false, now: now), isTrue);
    expect(purchaseCanJoin(open, 'user-1', hasShare: true, now: now), isFalse);
    expect(
      purchaseCanJoin(open, open.authorId, hasShare: false, now: now),
      isFalse,
    );
  });

  test('a fixing deadline is in the future and within the lifetime', () {
    final now = DateTime.utc(2026, 11, 15, 12);
    const lifetime = Duration(days: 30);
    expect(
      purchaseDeadlineIssue(
        now.add(const Duration(days: 3)),
        lifetime: lifetime,
        now: now,
      ),
      isNull,
    );
    expect(
      purchaseDeadlineIssue(now, lifetime: lifetime, now: now),
      PurchaseDeadlineIssue.past,
    );
    expect(
      purchaseDeadlineIssue(
        now.add(const Duration(days: 31)),
        lifetime: lifetime,
        now: now,
      ),
      PurchaseDeadlineIssue.beyondLifetime,
    );
  });

  test('amounts are exact to the cent', () {
    expect(normalizePurchasePrice('12,5'), '12.50');
    expect(normalizePurchasePrice(' 0,01 '), '0.01');
    expect(normalizePurchasePrice('0'), isNull);
    expect(normalizePurchasePrice('-1'), isNull);
    expect(normalizePurchasePrice('1.234'), isNull);
    expect(purchaseAmount('12.50', 3), '37.50');
    expect(purchaseAmount('0.10', 3), '0.30');
    expect(purchaseAmount('9999999999.99', 1), '9999999999.99');
  });

  test('purchase notifications open the purchase card', () {
    for (final type in [
      'listing.purchase.conditions_changed',
      'listing.purchase.fixed',
      'listing.purchase.cancelled',
      'listing.purchase.reminder',
      'listing.purchase.withdrawal_requested',
      'listing.purchase.withdrawal_decided',
    ]) {
      expect(
        notificationRoute(type, {
          'listing_id': 'purchase-1',
          'interaction_id': 'share-1',
        }),
        '/listings/purchase-1',
      );
    }
    expect(notificationRoute('listing.purchase.fixed', const {}), isNull);
  });

  test('a fixed purchase only accepts a leave request', () async {
    final fixed = purchase(stage: 'fixed', taken: 3, fixedUnits: 3);
    final share = PurchaseShareOutput.fromJson(
      purchaseShareJson(units: 3, stage: 'fixed'),
    );
    expect(purchaseStageOf(fixed), PurchaseStage.fixed);
    expect(purchaseCanRequestLeave(fixed, share), isTrue);
    expect(purchaseLeaveRequested(share), isFalse);

    final requested = PurchaseShareOutput.fromJson(
      purchaseShareJson(
        units: 3,
        stage: 'fixed',
        leaveRequestedAt: '2026-11-15T12:00:00Z',
      ),
    );
    expect(purchaseLeaveRequested(requested), isTrue);
    expect(purchaseCanRequestLeave(fixed, requested), isFalse);
    expect(purchaseCanRequestLeave(purchase(taken: 3), share), isFalse);
  });
}
