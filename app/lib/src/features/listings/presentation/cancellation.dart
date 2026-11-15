import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../domain/purchase.dart';

/// The participant kept the interaction; action wrappers treat it as a
/// successful no-op so they do not refresh or show a success message.
class CancellationDismissed implements Exception {
  const CancellationDismissed();
}

/// The server's answer to whether the participant may cancel and whether
/// that would count as late.
Future<InteractionCancellationPreview> loadInteractionCancellationPreview(
  WidgetRef ref, {
  required String listingId,
  required String interactionId,
}) => ref
    .read(campusApiProvider)
    .listings
    .interactionCancellationPreview(
      listingId: listingId,
      interactionId: interactionId,
    );

/// The late-cancellation and approval notices shown before an action.
Widget interactionCancellationWarning(
  BuildContext context,
  AppLocalizations l,
  InteractionCancellationPreview preview,
) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (preview.late2)
      Text(
        l.interactionLateCancellation,
        key: const Key('late-cancellation-warning'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    if (preview.requiresApproval)
      Text(
        l.interactionCancellationApproval,
        key: const Key('cancellation-approval-warning'),
      ),
  ],
);

/// Whether the owner may cancel this listing at all; the server has the
/// final say, but hidden and fixed states should not offer the action.
bool listingCanBeCancelled(ListingOutput listing) =>
    listing.kind != 'publication' &&
    (listing.status == ListingStatus.active ||
        listing.status == ListingStatus.busy) &&
    (!isPurchase(listing) ||
        purchaseStageOf(listing) == PurchaseStage.collecting);

/// Warns a participant before a late cancellation and asks for confirmation.
///
/// A cancellation that is neither late nor approval-bound proceeds without a
/// dialog, exactly as before. A dismissed warning aborts the action.
Future<void> ensureParticipantCancellation(
  BuildContext context,
  WidgetRef ref, {
  required String listingId,
  required String interactionId,
}) async {
  final preview = await loadInteractionCancellationPreview(
    ref,
    listingId: listingId,
    interactionId: interactionId,
  );
  if (!context.mounted) throw const CancellationDismissed();
  if (!preview.allowed) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.listingTransitionConflict)),
    );
    throw const CancellationDismissed();
  }
  if (!preview.late2 && !preview.requiresApproval) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.interactionCancelTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.interactionCancelBody),
          interactionCancellationWarning(context, context.l10n, preview),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('interaction-cancel-keep'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.interactionCancelKeep),
        ),
        FilledButton(
          key: const Key('interaction-cancel-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.interactionCancelConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true) throw const CancellationDismissed();
}

/// Asks the author for an optional or required cancellation reason.
///
/// Returns the trimmed reason, an empty string when the author confirmed
/// without one, or null when the dialog was dismissed.
Future<String?> showListingCancellationDialog(
  BuildContext context, {
  required ListingCancellationPreview preview,
}) => showDialog<String>(
  context: context,
  builder: (context) => _ListingCancellationDialog(preview: preview),
);

class _ListingCancellationDialog extends StatefulWidget {
  const _ListingCancellationDialog({required this.preview});

  final ListingCancellationPreview preview;

  @override
  State<_ListingCancellationDialog> createState() =>
      _ListingCancellationDialogState();
}

class _ListingCancellationDialogState
    extends State<_ListingCancellationDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final preview = widget.preview;
    return AlertDialog(
      key: const Key('listing-cancellation-dialog'),
      title: Text(l.listingCancelTitle),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.listingCancelBody),
              if (preview.acceptedInteractions > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l.listingCancelAcceptedWarning(
                      preview.acceptedInteractions,
                    ),
                    key: const Key('listing-cancel-accepted-warning'),
                  ),
                ),
              TextFormField(
                key: const Key('listing-cancel-reason'),
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                maxLength: preview.reasonMaxLength,
                decoration: InputDecoration(
                  labelText: l.listingCancelReason,
                  helperText: preview.reasonRequired
                      ? l.listingCancelReasonRequired
                      : null,
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (preview.reasonRequired && text.isEmpty) {
                    return l.listingCancelReasonMissing;
                  }
                  if (text.length > preview.reasonMaxLength) {
                    return l.listingCancelReasonTooLong(
                      preview.reasonMaxLength,
                    );
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('listing-cancel-keep'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.listingCancelKeep),
        ),
        FilledButton(
          key: const Key('listing-cancel-confirm'),
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_reason.text.trim());
          },
          child: Text(l.listingCancelConfirm),
        ),
      ],
    );
  }
}
