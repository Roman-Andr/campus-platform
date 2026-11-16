import 'package:material_ui/material_ui.dart';

import '../foundations/tokens.dart';

/// An action with duplicate-submit protection. Success belongs to its caller.
class BusyAction extends StatelessWidget {
  const BusyAction({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: busy,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: CampusSpace.sm,
        children: [
          if (busy)
            SizedBox.square(
              dimension: CampusSpace.md,
              child: MediaQuery.disableAnimationsOf(context)
                  ? const Icon(Icons.hourglass_top, size: CampusSpace.md)
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
