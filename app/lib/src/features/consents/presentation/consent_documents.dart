import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/api_error_view.dart';
import '../application/consents.dart';

String documentTitle(AppLocalizations l10n, DocumentKind kind) =>
    switch (kind) {
      DocumentKindKnown(value: DocumentKindValue.communityRules) =>
        l10n.consentRules,
      DocumentKindKnown(value: DocumentKindValue.privacyPolicy) =>
        l10n.consentPrivacy,
      DocumentKindKnown(value: DocumentKindValue.personalDataProcessing) =>
        l10n.consentProcessing,
      DocumentKindKnown(value: DocumentKindValue.crossBorderTransfer) =>
        l10n.consentCrossBorder,
      _ => l10n.consentDocuments,
    };

/// Links open the complete server text in the interface language.
class ConsentDocuments extends ConsumerWidget {
  const ConsentDocuments({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(documentsProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ApiErrorView(
          error: error,
          onRetry: () => ref.invalidate(documentsProvider),
        ),
        data: (documents) => Column(
          children: [
            for (final document in documents)
              ListTile(
                title: Text(documentTitle(context.l10n, document.kind)),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(documentTitle(context.l10n, document.kind)),
                    content: SingleChildScrollView(
                      child: SelectableText(document.text),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.l10n.consentClose),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class ConsentCheckboxes extends StatelessWidget {
  const ConsentCheckboxes({
    required this.requiredAccepted,
    required this.crossBorderAccepted,
    required this.onRequiredChanged,
    required this.onCrossBorderChanged,
    super.key,
  });

  final bool requiredAccepted;
  final bool crossBorderAccepted;
  final ValueChanged<bool>? onRequiredChanged;
  final ValueChanged<bool>? onCrossBorderChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      CheckboxListTile(
        key: const Key('consent-required'),
        value: requiredAccepted,
        onChanged: onRequiredChanged == null
            ? null
            : (value) => onRequiredChanged!(value!),
        title: Text(context.l10n.consentAcceptRequired),
      ),
      CheckboxListTile(
        key: const Key('consent-cross-border'),
        value: crossBorderAccepted,
        onChanged: onCrossBorderChanged == null
            ? null
            : (value) => onCrossBorderChanged!(value!),
        title: Text(context.l10n.consentCrossBorderOptional),
        subtitle: Text(context.l10n.consentCrossBorderEffects),
      ),
    ],
  );
}
