import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../domain/qr_availability.dart';
import 'qr_presenter_screen.dart';
import 'qr_scanner_screen.dart';

/// Entry point to the online QR confirmation of an accepted interaction.
///
/// One participant presses "show", the other one presses "scan"; the server
/// rejects everybody else (ТЗ п. 5.1.1, модуль 5, пункт 1).
class QrConfirmationSummary extends ConsumerWidget {
  const QrConfirmationSummary({
    required this.item,
    required this.kind,
    super.key,
  });

  final InteractionOutput item;

  /// Kind of the listing the interaction belongs to.
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (qrInteractionState(kind, item) != QrInteractionState.available) {
      return const SizedBox.shrink();
    }
    return Card(
      key: Key('qr-confirmation-${item.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.qr_code_2,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l.qrConfirmationTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l.qrConfirmationHint),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: Key('qr-show-${item.id}'),
                  onPressed: () =>
                      context.push(qrShowPath(item.listingId, item.id)),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: Text(l.qrShowOpen),
                ),
                OutlinedButton.icon(
                  key: Key('qr-scan-${item.id}'),
                  onPressed: () =>
                      context.push(qrScanPath(item.listingId, item.id)),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(l.qrScanOpen),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
