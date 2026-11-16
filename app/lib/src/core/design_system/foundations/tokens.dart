import 'package:material_ui/material_ui.dart';

/// Shared geometry. Native controls retain their minimum accessible target.
abstract final class CampusSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const page = EdgeInsets.all(md);
  static const section = EdgeInsets.all(lg);
}

abstract final class CampusGeometry {
  static const controlRadius = 12.0;
  static const cardRadius = 20.0;
  static const sheetRadius = 28.0;
  static const target = 48.0;
  static const focusWidth = 2.0;
  static const raised = 1.0;
  static const readingWidth = 840.0;
  static const railBreakpoint = 720.0;
}

abstract final class CampusMotion {
  static const feedback = Duration(milliseconds: 120);
  static const content = Duration(milliseconds: 180);
  static const transition = Duration(milliseconds: 260);
  static const theme = Duration(milliseconds: 200);
  static const curve = Curves.easeOutCubic;
}
