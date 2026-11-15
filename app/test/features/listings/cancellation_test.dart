import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_en.dart';
import 'package:campus/src/core/l10n/generated/app_localizations_ru.dart';
import 'package:campus/src/features/listings/presentation/cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

ListingOutput listing({
  String kind = 'giveaway',
  String status = 'active',
  String? stage,
}) => ListingOutput.fromJson(
  kind == 'purchase'
      ? purchaseListingJson(status: status, stage: stage ?? 'collecting')
      : listingJson(kind: kind, status: status),
);

void main() {
  test('only cancellable listing states offer the owner action', () {
    expect(listingCanBeCancelled(listing()), isTrue);
    expect(listingCanBeCancelled(listing(status: 'busy')), isTrue);
    expect(listingCanBeCancelled(listing(kind: 'publication')), isFalse);
    expect(listingCanBeCancelled(listing(status: 'draft')), isFalse);
    expect(listingCanBeCancelled(listing(status: 'expired')), isFalse);
    expect(
      listingCanBeCancelled(listing(kind: 'purchase', stage: 'collecting')),
      isTrue,
    );
    expect(
      listingCanBeCancelled(listing(kind: 'purchase', stage: 'fixed')),
      isFalse,
    );
  });

  test('cancellation texts are localized in both languages', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();
    expect(en.listingCancel, 'Cancel listing');
    expect(ru.listingCancel, 'Отменить объявление');
    expect(en.listingCancelledByAuthor('gone'), 'The author cancelled: gone');
    expect(ru.listingCancelledByAuthor('нет'), 'Автор отменил: нет');
    expect(en.interactionLateCancellation, contains('late'));
    expect(ru.interactionLateCancellation, contains('поздняя'));
  });
}
