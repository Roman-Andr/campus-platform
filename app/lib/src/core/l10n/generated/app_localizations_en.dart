// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Campus';

  @override
  String get homeWelcome => 'Welcome to Campus';

  @override
  String get homePlaceholder =>
      'Listings, events and group purchases of your community will appear here.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System default';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get errorNetwork =>
      'Can\'t reach the server. Check your internet connection and try again.';

  @override
  String get errorServer =>
      'Something went wrong on the server. Please try again later.';

  @override
  String get errorRequest => 'Couldn\'t complete the action. Please try again.';

  @override
  String get errorNotFound => 'Not found: it may have been deleted.';

  @override
  String get errorValidation => 'Please check the information you entered.';

  @override
  String get errorListChanged => 'The list has changed. Please refresh it.';

  @override
  String get errorUpdateRequired =>
      'This version of the app is out of date. Please update the app.';

  @override
  String get errorUnexpected => 'Something went wrong. Please try again.';

  @override
  String get errorRetry => 'Try again';

  @override
  String get offlineBanner => 'You\'re offline';

  @override
  String get updateTitle => 'Update required';

  @override
  String get updateBody =>
      'This version of the app is no longer supported. Install the new version to continue.';

  @override
  String updateBodyVersion(String version) {
    return 'This version of the app is no longer supported. Install version $version or newer to continue.';
  }

  @override
  String get updateDownload => 'Download update';

  @override
  String get updateDownloadFailed => 'Couldn\'t open the download page.';
}
