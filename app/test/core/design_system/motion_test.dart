import 'package:animations/animations.dart';
import 'package:campus/src/core/design_system/components/components.dart';
import 'package:campus/src/core/design_system/foundations/palette.dart';
import 'package:campus/src/core/design_system/motion/campus_motion.dart';
import 'package:campus/src/core/design_system/theme/campus_theme.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget host(Widget child, {bool disabled = false, bool reduced = false}) =>
    MaterialApp(
      theme: CampusTheme.build(PaletteId.sky, Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disabled,
          reduceMotion: reduced,
        ),
        child: Scaffold(body: child),
      ),
    );

void main() {
  for (final flag in ['disableAnimations', 'reduceMotion']) {
    testWidgets('$flag gives final content immediately', (tester) async {
      Widget view(int value) => host(
        CampusContentSwitch(
          stateKey: ValueKey(value),
          child: Text('State $value'),
        ),
        disabled: flag == 'disableAnimations',
        reduced: flag == 'reduceMotion',
      );
      await tester.pumpWidget(view(0));
      await tester.pumpWidget(view(1));
      expect(find.text('State 0'), findsNothing);
      expect(find.text('State 1'), findsOneWidget);
      expect(find.byType(PageTransitionSwitcher), findsNothing);
    });
  }
  testWidgets('rapid changes settle to latest content and dispose tickers', (
    tester,
  ) async {
    for (var i = 0; i < 8; i++) {
      await tester.pumpWidget(
        host(
          CampusContentSwitch(stateKey: ValueKey(i), child: Text('State $i')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.text('State 7'), findsOneWidget);
    expect(find.text('State 0'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets('inactive and background motion scopes mute tickers', (
    tester,
  ) async {
    var ticks = 0;
    Widget view(bool active) => host(
      CampusMotionVisibility(
        active: active,
        child: _Probe(onTick: () => ticks++),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(view(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks, greaterThan(0));
    await tester.pumpWidget(view(false));
    final inactive = ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks, inactive);
    await tester.pumpWidget(view(true));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    final paused = ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks, paused);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks, greaterThan(paused));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reduced sheet and dialog open and close without animation wait',
    (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showCampusSheet<void>(
                    context: context,
                    builder: (_) => const Text('Sheet'),
                  ),
                  child: const Text('Open sheet'),
                ),
                TextButton(
                  onPressed: () => showCampusDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(title: Text('Dialog')),
                  ),
                  child: const Text('Open dialog'),
                ),
              ],
            ),
          ),
          disabled: true,
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pump();
      expect(find.text('Sheet'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Sheet'), findsNothing);
      await tester.tap(find.text('Open dialog'));
      await tester.pump();
      expect(find.text('Dialog'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Dialog'), findsNothing);
    },
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onTick});
  final VoidCallback onTick;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  @override
  void initState() {
    super.initState();
    ticker = createTicker((_) => widget.onTick())..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
