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

  @override
  String get errorRateLimited =>
      'Too many requests. Wait a little and try again.';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signInEmailIntro =>
      'Sign in with your university e-mail: we will send a sign-in code to it.';

  @override
  String get signInEmailLabel => 'University e-mail';

  @override
  String get signInEmailInvalid =>
      'Enter an e-mail address, e.g. ivanov@edu.hse.ru.';

  @override
  String get signInGetCode => 'Get code';

  @override
  String get signInCodeTitle => 'Code from the e-mail';

  @override
  String signInCodeSent(String email) {
    return 'We sent a code to $email. If there is no e-mail, check the spam folder.';
  }

  @override
  String get signInCodeLabel => '6-digit code';

  @override
  String get signInCodeIncomplete => 'Enter all 6 digits of the code.';

  @override
  String get signInSubmit => 'Sign in';

  @override
  String get signInResend => 'Send the code again';

  @override
  String signInResendIn(String wait) {
    return 'You can send the code again in $wait';
  }

  @override
  String get signInResent => 'A new code has been sent';

  @override
  String get signInChangeEmail => 'Change e-mail';

  @override
  String get signInNameTitle => 'Sign up';

  @override
  String get signInNameIntro =>
      'This is your first sign-in. Enter your first and last names: other students will see them.';

  @override
  String get signInFirstName => 'First name';

  @override
  String get signInLastName => 'Last name';

  @override
  String get signInNameRequired => 'Fill in this field.';

  @override
  String get signInNameInvalid =>
      'Use only letters, spaces, hyphens and apostrophes.';

  @override
  String get signInFinish => 'Sign up';

  @override
  String get authErrorDomain =>
      'This address is not a university e-mail. Sign in with an address in the university domain.';

  @override
  String get authErrorCodeInvalid =>
      'Wrong code. Check the e-mail and try again.';

  @override
  String get authErrorCodeExpired =>
      'The code has expired or was already used. Request a new code.';

  @override
  String get authErrorAttemptsExceeded =>
      'Too many wrong attempts. Request a new code.';

  @override
  String authErrorRateLimitedFor(String wait) {
    return 'Too many attempts. Try again in $wait.';
  }

  @override
  String waitSeconds(int count) {
    return '$count s';
  }

  @override
  String waitMinutes(int count) {
    return '$count min';
  }

  @override
  String get settingsAccount => 'Account';

  @override
  String get signOut => 'Sign out';
}
