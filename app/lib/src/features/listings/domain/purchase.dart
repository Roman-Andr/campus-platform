import 'package:clock/clock.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';

/// A group purchase: participants collect shares of a shared order.
const purchaseKind = 'purchase';

/// Whether [listing] is a group purchase (ТЗ п. 5.1.1, модуль 4, п. 13).
bool isPurchase(ListingOutput listing) => listing.kind == purchaseKind;

/// The collection stage of a purchase; null for other listings.
PurchaseStage? purchaseStageOf(ListingOutput listing) =>
    switch (listing.purchaseStage) {
      ListingOutputPurchaseStagePurchaseStage(:final value) => value,
      _ => null,
    };

/// The stage stored in an interaction row, for "My participation".
PurchaseStage? purchaseStageValue(String? stage) =>
    stage == null ? null : PurchaseStage.fromJson(stage);

/// The localized name of [stage].
String purchaseStageLabel(AppLocalizations l, PurchaseStage? stage) =>
    switch (stage) {
      PurchaseStageKnown(value: PurchaseStageValue.collecting) =>
        l.purchaseStageCollecting,
      PurchaseStageKnown(value: PurchaseStageValue.fixed) =>
        l.purchaseStageFixed,
      PurchaseStageKnown(value: PurchaseStageValue.cancelled) =>
        l.purchaseStageCancelled,
      _ => l.listingStatusUnknown,
    };

/// The volume the current limit allows: the fixed volume once fixed,
/// otherwise the maximum promised to participants.
int? purchaseLimit(ListingOutput listing) =>
    purchaseStageOf(listing) == PurchaseStage.fixed
    ? listing.purchaseFixedUnits ?? listing.purchaseMaxUnits
    : listing.purchaseMaxUnits;

/// Units a participant may still take, giving back [ownUnits] they hold.
int purchaseAvailableUnits(ListingOutput listing, {int ownUnits = 0}) {
  final limit = purchaseLimit(listing);
  if (limit == null) return 0;
  final available = limit - listing.purchaseTakenUnits + ownUnits;
  return available < 0 ? 0 : available;
}

/// Whether shares may still be taken or changed at [now].
///
/// The server has the final say; this keeps the form from offering an action
/// that the deadline has already closed.
bool purchaseCollectionOpen(ListingOutput listing, DateTime now) {
  final deadline = listing.purchaseCollectionDeadline;
  return purchaseStageOf(listing) == PurchaseStage.collecting &&
      (listing.status == ListingStatus.active ||
          listing.status == ListingStatus.busy) &&
      deadline != null &&
      deadline.isAfter(now);
}

/// Whether [userId] may take a share of [listing].
///
/// [hasShare] is true when the account already holds an accepted share; one
/// share per participant, and the organiser never joins their own purchase.
bool purchaseCanJoin(
  ListingOutput listing,
  String? userId, {
  required bool hasShare,
  DateTime? now,
}) =>
    userId != null &&
    listing.authorId != userId &&
    !hasShare &&
    purchaseCollectionOpen(listing, now ?? clock.now());

/// Why [units] cannot be saved, in the words shown under the field.
String? purchaseUnitsError(
  AppLocalizations l,
  ListingOutput listing,
  int? units, {
  int ownUnits = 0,
}) {
  if (units == null || units < 1) return l.purchaseUnitsPositive;
  final available = purchaseAvailableUnits(listing, ownUnits: ownUnits);
  if (units > available) {
    return available == 0
        ? l.purchaseShareNoUnits
        : l.purchaseUnitsUnavailable(available);
  }
  return null;
}

/// How many units are collected at the moment a purchase is fixed.
int purchaseFixedUnits(ListingOutput listing) =>
    listing.purchaseFixedUnits ?? listing.purchaseTakenUnits;

/// Whether a participant of a fixed purchase can ask the organiser to leave.
bool purchaseCanRequestLeave(
  ListingOutput listing,
  PurchaseShareOutput share,
) =>
    purchaseStageOf(listing) == PurchaseStage.fixed &&
    share.status == InteractionStatus.accepted &&
    share.leaveRequestedAt == null;

/// Whether the participant's leave request already waits for a decision.
bool purchaseLeaveRequested(PurchaseShareOutput share) =>
    share.leaveRequestedAt != null;

/// A fixing deadline is not acceptable when it is past or too far away.
enum PurchaseDeadlineIssue { past, beyondLifetime }

/// The problem of [deadline] as a collection deadline; null when it is valid.
PurchaseDeadlineIssue? purchaseDeadlineIssue(
  DateTime deadline, {
  required Duration lifetime,
  DateTime? now,
}) {
  final at = now ?? clock.now();
  if (!deadline.isAfter(at)) return PurchaseDeadlineIssue.past;
  if (deadline.isAfter(at.add(lifetime))) {
    return PurchaseDeadlineIssue.beyondLifetime;
  }
  return null;
}

/// A localized explanation of [issue] for the deadline field.
String purchaseDeadlineError(
  AppLocalizations l,
  PurchaseDeadlineIssue issue, {
  required int lifetimeDays,
}) => switch (issue) {
  PurchaseDeadlineIssue.past => l.purchaseDeadlinePast,
  PurchaseDeadlineIssue.beyondLifetime => l.purchaseDeadlineTooLate(
    lifetimeDays,
  ),
};

/// Cents of a decimal amount, or null when [raw] is not a valid amount.
///
/// Amounts of the server have two decimal places; parsing them as integer
/// cents keeps the form preview exact.
int? purchaseMoneyCents(String raw) {
  final match = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(raw.trim());
  if (match == null) return null;
  final whole = int.tryParse(match.group(1)!);
  if (whole == null || whole > 9999999999) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}

/// A positive price in the form the server accepts, or null when invalid.
String? normalizePurchasePrice(String raw) {
  final cents = purchaseMoneyCents(raw);
  if (cents == null || cents <= 0) return null;
  return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

/// The amount for [units] at [unitPrice], computed exactly in cents.
String purchaseAmount(String unitPrice, int units) {
  final cents = purchaseMoneyCents(unitPrice);
  if (cents == null) return '0.00';
  final amount = cents * units;
  return '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';
}

/// A localized sum of money, e.g. "1 250,00 ₽".
String formatPurchaseMoney(AppLocalizations l, String amount) {
  final cents = purchaseMoneyCents(amount);
  if (cents == null) return amount;
  return NumberFormat.currency(
    locale: l.localeName,
    symbol: '₽',
    decimalDigits: 2,
  ).format(cents / 100);
}

/// The collected volume in the words of a card.
String purchaseCollectedLabel(AppLocalizations l, ListingOutput listing) {
  final limit = purchaseLimit(listing) ?? 0;
  return l.purchaseCollected(listing.purchaseTakenUnits, limit);
}
