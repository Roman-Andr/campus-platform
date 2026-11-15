import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/l10n/l10n.dart';
import '../domain/qr_document.dart';

/// The QR code of a signed online payload.
///
/// The content is exactly the scan request body (the encoded payload and its
/// detached signature), so a code scanned by another installation needs no
/// further transformation. The light background and the low error-correction
/// level keep a dense payload readable.
class MeetingQrCode extends ConsumerWidget {
  const MeetingQrCode({required this.document, this.size = 300, super.key});

  final QrScanDocument document;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Container(
      key: const Key('qr-code-image'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: QrImageView(
        data: document.encode(),
        size: size,
        backgroundColor: Colors.white,
        semanticsLabel: context.l10n.qrConfirmationTitle,
      ),
    ),
  );
}
