import 'package:material_ui/material_ui.dart';

import '../api/api_failure.dart';
import '../api/api_failure_message.dart';
import '../l10n/l10n.dart';

/// Shows why loading failed, in place of the content, with a way to try
/// again.
class ApiErrorView extends StatelessWidget {
  const ApiErrorView({
    required this.error,
    this.onRetry,
    this.message,
    super.key,
  });

  /// The error of the request, usually from an `AsyncValue`.
  final Object error;

  final VoidCallback? onRetry;

  /// A feature-specific localized message; the shared API message by default.
  final String Function(AppLocalizations l10n, Object error)? message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final offline = ApiFailure.from(error) is NetworkFailure;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.cloud_off_outlined : Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message?.call(l10n, error) ?? apiFailureMessage(l10n, error),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text(l10n.errorRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
