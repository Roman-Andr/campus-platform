import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../settings/application/settings_controller.dart';

/// Current texts are fetched again when the interface language changes.
final documentsProvider = FutureProvider.autoDispose<List<DocumentOutput>>((
  ref,
) {
  ref.watch(settingsControllerProvider.select((s) => s.value?.language));
  return ref.watch(campusApiProvider).consents.getDocuments();
});

/// Load the effective decision each time settings are opened: another
/// device or a newly published optional version may have changed it.
final consentStatusProvider = FutureProvider.autoDispose<bool>(
  (ref) async => (await ref.watch(campusApiProvider).profile.getMe())
      .crossBorderTransferAllowed,
);

/// A single gate shared by concurrent requests rejected by the server.
final consentGateProvider = NotifierProvider<ConsentGate, bool>(
  ConsentGate.new,
);

class ConsentGate extends Notifier<bool> {
  Completer<bool>? _pending;

  @override
  bool build() {
    ref.onDispose(() => _pending?.complete(false));
    return false;
  }

  Future<bool> require() {
    if (_pending == null) {
      ref.invalidate(documentsProvider);
      _pending = Completer<bool>();
      state = true;
    }
    return _pending!.future;
  }

  void finish({required bool accepted}) {
    final pending = _pending;
    _pending = null;
    state = false;
    pending?.complete(accepted);
  }
}

List<String> requiredDocumentIds(List<DocumentOutput> documents) => [
  for (final document in documents)
    if (document.required2) document.id,
];

DocumentOutput? crossBorderDocument(List<DocumentOutput> documents) {
  for (final document in documents) {
    if (document.kind == DocumentKind.crossBorderTransfer) return document;
  }
  return null;
}
