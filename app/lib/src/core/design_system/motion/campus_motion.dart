import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';

import '../foundations/tokens.dart';

/// A local content replacement. Domain state changes immediately on rebuild.
/// This is not a route transition; platform Back gestures remain native.
class CampusContentSwitch extends StatelessWidget {
  const CampusContentSwitch({
    required this.stateKey,
    required this.child,
    super.key,
  });
  final Key stateKey;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: stateKey, child: child);
    if (CampusMotion.reduced(context)) return content;
    return PageTransitionSwitcher(
      duration: CampusMotion.content,
      layoutBuilder: (entries) => Stack(
        alignment: Alignment.topLeft,
        children: [
          for (var i = 0; i < entries.length; i++)
            IgnorePointer(
              ignoring: i != entries.length - 1,
              child: ExcludeSemantics(
                excluding: i != entries.length - 1,
                child: entries[i],
              ),
            ),
        ],
      ),
      transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
        animation: primary,
        secondaryAnimation: secondary,
        fillColor: Theme.of(context).colorScheme.surface,
        child: child,
      ),
      child: content,
    );
  }
}

/// Native implicit feedback with no movement or decorative repetition.
class CampusSelectionFeedback extends StatelessWidget {
  const CampusSelectionFeedback({
    required this.selected,
    required this.child,
    super.key,
  });
  final bool selected;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: CampusMotion.duration(context, CampusMotion.feedback),
      curve: CampusMotion.curve,
      padding: const EdgeInsets.all(CampusSpace.sm),
      decoration: BoxDecoration(
        color: selected ? colors.primaryContainer : colors.surface,
        border: Border.all(color: selected ? colors.primary : colors.outline),
        borderRadius: BorderRadius.circular(CampusGeometry.controlRadius),
      ),
      child: child,
    );
  }
}

/// Stops animation work on inactive branches and while the app is backgrounded.
class CampusMotionVisibility extends StatefulWidget {
  const CampusMotionVisibility({
    required this.child,
    this.active = true,
    super.key,
  });
  final Widget child;
  final bool active;
  @override
  State<CampusMotionVisibility> createState() => _CampusMotionVisibilityState();
}

class _CampusMotionVisibilityState extends State<CampusMotionVisibility> {
  late final AppLifecycleListener listener;
  late AppLifecycleState lifecycle;
  @override
  void initState() {
    super.initState();
    lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    listener = AppLifecycleListener(
      onStateChange: (value) {
        if (mounted) setState(() => lifecycle = value);
      },
    );
  }

  @override
  void dispose() {
    listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: widget.active && lifecycle == AppLifecycleState.resumed,
    child: widget.child,
  );
}
