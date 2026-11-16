import 'dart:async';
import 'dart:convert';

import 'package:campus/src/core/design_system/components/components.dart';
import 'package:campus/src/core/design_system/foundations/palette.dart';
import 'package:campus/src/core/design_system/motion/campus_motion.dart';
import 'package:campus/src/core/design_system/theme/campus_theme.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Synthetic profile entry point. Does not initialize API, auth or persistence.
void main() => runApp(const _Profile());

class _Profile extends StatefulWidget {
  const _Profile();
  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  final frames = <String, List<FrameTiming>>{};
  String phase = 'warmup';
  bool reduced = false;
  int value = 0;
  BuildContext? screen;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(record);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(run()));
  }

  void record(List<FrameTiming> batch) =>
      frames.putIfAbsent(phase, () => []).addAll(batch);
  Future<void> run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    for (final mode in [false, true]) {
      if (!mounted) return;
      setState(() => reduced = mode);
      for (final kind in ['content', 'sheet', 'dialog']) {
        phase = '${mode ? 'reduced' : 'normal'}_$kind';
        for (var i = 0; i < 16; i++) {
          if (!mounted) return;
          if (kind == 'content') {
            setState(() => value++);
          } else {
            final target = screen!;
            if (!target.mounted) return;
            final closed = kind == 'sheet'
                ? showCampusSheet<void>(
                    context: target,
                    builder: (_) => const StatePanel(
                      title: 'Fixture sheet',
                      description: 'Synthetic profile',
                      icon: Icons.layers_outlined,
                    ),
                  )
                : showCampusDialog<void>(
                    context: target,
                    builder: (_) =>
                        const AlertDialog(title: Text('Fixture dialog')),
                  );
            await Future<void>.delayed(const Duration(milliseconds: 350));
            if (!mounted) return;
            if (!target.mounted) return;
            Navigator.of(target).pop();
            await closed;
          }
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    SchedulerBinding.instance.removeTimingsCallback(record);
    final report = {
      for (final entry in frames.entries) entry.key: stats(entry.value),
    };
    // ignore: avoid_print
    print('MOTION_PROFILE_JSON ${jsonEncode(report)}');
  }

  Map<String, Object> stats(List<FrameTiming> list) {
    final build =
        list.map((f) => f.buildDuration.inMicroseconds / 1000).toList()..sort();
    final raster =
        list.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
          ..sort();
    double percentile(List<double> values) =>
        values.isEmpty ? 0 : values[((values.length - 1) * .95).round()];
    return {
      'frames': list.length,
      'build_p95_ms': percentile(build),
      'raster_p95_ms': percentile(raster),
      'build_over_16_67_ms': build.where((v) => v > 16.67).length,
      'raster_over_16_67_ms': raster.where((v) => v > 16.67).length,
    };
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(record);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: CampusTheme.build(PaletteId.lavender, Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: reduced, reduceMotion: reduced),
      child: child!,
    ),
    home: Builder(
      builder: (context) {
        screen = context;
        return Scaffold(
          appBar: AppBar(title: const Text('Synthetic motion profile')),
          body: CampusMotionVisibility(
            child: Column(
              children: [
                CampusContentSwitch(
                  stateKey: ValueKey(value),
                  child: StatePanel(
                    title: 'Fixture $value',
                    description: 'Local state, no network',
                    icon: Icons.info_outline,
                  ),
                ),
                CampusSelectionFeedback(
                  selected: value.isOdd,
                  child: const Text('Feedback'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
