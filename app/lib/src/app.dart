import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/l10n/l10n.dart';
import 'core/realtime/realtime_status_view.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/offline_banner.dart';
import 'features/consents/presentation/consents_screen.dart';
import 'features/settings/application/settings_controller.dart';
import 'features/settings/domain/app_settings.dart';

/// Root widget: applies the router, localization and theme settings.
class CampusApp extends ConsumerWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? const AppSettings();
    return MaterialApp.router(
      routerConfig: ref.watch(appRouterProvider),
      onGenerateTitle: (context) => context.l10n.appTitle,
      locale: settings.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.forPalette(settings.paletteId, Brightness.light),
      darkTheme: AppTheme.forPalette(settings.paletteId, Brightness.dark),
      themeMode: settings.themeMode,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => RealtimeStatusBanner(
        child: OfflineBanner(
          child: ConsentGuard(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
