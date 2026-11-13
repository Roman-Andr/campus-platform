import 'package:material_ui/material_ui.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  /// Localized strings for the current locale.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
