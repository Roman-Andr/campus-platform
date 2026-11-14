import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/l10n/l10n.dart';
import '../application/settings_controller.dart';
import '../domain/app_settings.dart';

/// Device settings: interface language and theme; signing out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings =
        ref.watch(settingsControllerProvider).value ?? const AppSettings();
    final controller = ref.read(settingsControllerProvider.notifier);
    final signedIn =
        ref.watch(authStatusProvider).value ==
        AuthenticationStatus.authenticated;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          _SectionHeader(l10n.settingsLanguage),
          RadioGroup<AppLanguage>(
            groupValue: settings.language,
            onChanged: (value) {
              if (value != null) unawaited(controller.setLanguage(value));
            },
            child: Column(
              children: [
                for (final language in AppLanguage.values)
                  RadioListTile<AppLanguage>(
                    key: ValueKey(language),
                    value: language,
                    title: Text(_languageLabel(l10n, language)),
                  ),
              ],
            ),
          ),
          const Divider(),
          _SectionHeader(l10n.settingsTheme),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (value) {
              if (value != null) unawaited(controller.setThemeMode(value));
            },
            child: Column(
              children: [
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    key: ValueKey(mode),
                    value: mode,
                    title: Text(_themeLabel(l10n, mode)),
                  ),
              ],
            ),
          ),
          if (signedIn) ...[
            const Divider(),
            _SectionHeader(l10n.settingsAccount),
            ListTile(
              key: const Key('sign-out'),
              leading: const Icon(Icons.logout),
              title: Text(l10n.signOut),
              onTap: () => unawaited(ref.read(authServiceProvider).signOut()),
            ),
          ],
        ],
      ),
    );
  }

  static String _languageLabel(AppLocalizations l10n, AppLanguage language) =>
      switch (language) {
        AppLanguage.system => l10n.settingsLanguageSystem,
        AppLanguage.russian => l10n.settingsLanguageRussian,
        AppLanguage.english => l10n.settingsLanguageEnglish,
      };

  static String _themeLabel(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => l10n.settingsThemeSystem,
        ThemeMode.light => l10n.settingsThemeLight,
        ThemeMode.dark => l10n.settingsThemeDark,
      };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
