import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../api/network_status.dart';
import '../l10n/l10n.dart';

/// Shows a strip above [child] while the app is offline.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(networkStatusProvider);
    if (online) return child;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: colors.inverseSurface,
          child: SafeArea(
            bottom: false,
            child: Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 18,
                      color: colors.onInverseSurface,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.l10n.offlineBanner,
                        style: TextStyle(color: colors.onInverseSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The strip already takes the status bar area.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
