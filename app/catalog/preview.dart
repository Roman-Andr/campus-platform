import 'package:campus/src/core/design_system/foundations/palette.dart';
import 'package:campus/src/core/design_system/theme/campus_theme.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

/// Tool-only controls. The preview itself uses shipping themes and l10n.
class CatalogPreview extends StatefulWidget {
  const CatalogPreview({required this.child, super.key});
  final Widget child;
  @override
  State<CatalogPreview> createState() => _CatalogPreviewState();
}

class _CatalogPreviewState extends State<CatalogPreview> {
  PaletteId palette = PaletteId.lavender;
  ThemeMode mode = ThemeMode.light;
  String locale = 'ru';
  double width = 390;
  double scale = 1;
  bool reduced = false;

  Widget choice<T>(
    String label,
    T value,
    List<T> values,
    ValueChanged<T> change,
  ) => DropdownButton<T>(
    value: value,
    hint: Text(label),
    items: [
      for (final v in values)
        DropdownMenuItem(value: v, child: Text('$label: $v')),
    ],
    onChanged: (v) {
      if (v != null) setState(() => change(v));
    },
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: CampusTheme.build(palette, Brightness.light),
    darkTheme: CampusTheme.build(palette, Brightness.dark),
    themeMode: mode,
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: 150,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 16,
                    children: [
                      choice(
                        'Palette',
                        palette,
                        PaletteId.values,
                        (v) => palette = v,
                      ),
                      choice('Mode', mode, ThemeMode.values, (v) => mode = v),
                      choice('Locale', locale, ['ru', 'en'], (v) => locale = v),
                      choice('Width', width, [
                        320.0,
                        390.0,
                        720.0,
                        1100.0,
                      ], (v) => width = v),
                      choice('Text', scale, [
                        1.0,
                        1.5,
                        2.0,
                        3.0,
                      ], (v) => scale = v),
                      FilterChip(
                        label: const Text('Reduced motion'),
                        selected: reduced,
                        onSelected: (v) => setState(() => reduced = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width.clamp(0, constraints.maxWidth),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: reduced,
                      ),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
