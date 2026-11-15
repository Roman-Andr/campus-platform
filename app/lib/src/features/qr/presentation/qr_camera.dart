import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/l10n/l10n.dart';

/// Builds the camera area of the scanner screen; tests replace it to feed a
/// scanned code without a camera.
typedef QrCameraBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onDetect,
);

/// The camera of the scanner screen.
final qrCameraBuilderProvider = Provider<QrCameraBuilder>(
  (ref) => buildQrCamera,
);

/// Whether the camera scanner supports the running platform.
///
/// Android is the target of the online QR scenario; the other supported
/// platforms of the plugin get the same camera, and desktop Linux, Windows and
/// other builds show an explanation instead of a broken preview.
bool qrCameraSupported([TargetPlatform? platform]) =>
    kIsWeb ||
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      _ => false,
    };

/// The live camera preview that reports a scanned QR code.
Widget buildQrCamera(BuildContext context, ValueChanged<String> onDetect) {
  if (!qrCameraSupported()) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          context.l10n.qrScannerCameraUnsupported,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
  return _CameraPreview(onDetect: onDetect);
}

class _CameraPreview extends StatefulWidget {
  const _CameraPreview({required this.onDetect});

  final ValueChanged<String> onDetect;

  @override
  State<_CameraPreview> createState() => _CameraPreviewState();
}

class _CameraPreviewState extends State<_CameraPreview> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _handle(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        widget.onDetect(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MobileScanner(
      controller: _controller,
      onDetect: _handle,
      errorBuilder: (context, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(switch (error.errorCode) {
            MobileScannerErrorCode.permissionDenied => l.qrScannerCameraDenied,
            MobileScannerErrorCode.unsupported => l.qrScannerCameraUnsupported,
            _ => l.qrScannerCameraError,
          }, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
