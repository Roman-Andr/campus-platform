import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_config.dart';
import '../../../core/api/client_update.dart';
import '../../../core/l10n/l10n.dart';

/// Shown instead of the app once the server stops supporting this
/// version; offers the download page of the new one (ТЗ п. 4.6).
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final minVersion = ref.watch(clientUpdateRequiredProvider)?.minVersion;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.system_update_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.updateTitle,
                      style: textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      minVersion == null
                          ? l10n.updateBody
                          : l10n.updateBodyVersion(minVersion),
                      style: textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.download_outlined),
                      label: Text(l10n.updateDownload),
                      onPressed: () => unawaited(_download(context, ref)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = context.l10n.updateDownloadFailed;
    final url = ref.read(apiConfigProvider).downloadUrl;
    final opened = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    ).then((ok) => ok, onError: (Object _) => false);
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
