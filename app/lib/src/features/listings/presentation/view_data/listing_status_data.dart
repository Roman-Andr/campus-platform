import '../../../../core/api/generated/listings/models/listing_status.dart';
import '../../../../core/design_system/components/feedback_panel.dart';
import '../../../../core/design_system/patterns/metadata.dart';
import '../../../../core/l10n/l10n.dart';
import '../status_labels.dart';

/// Maps display tone only. It grants no action or domain transition.
StatusViewData listingStatusData(AppLocalizations l10n, ListingStatus status) =>
    StatusViewData(
      label: listingStatusLabel(l10n, status),
      tone: switch (status) {
        ListingStatusKnown(value: ListingStatusValue.completed) =>
          NoticeTone.success,
        ListingStatusKnown(value: ListingStatusValue.expired) =>
          NoticeTone.warning,
        _ => NoticeTone.information,
      },
    );
