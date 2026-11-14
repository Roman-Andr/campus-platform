import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Application name shown in the app bar, task switcher and browser tab.
  ///
  /// In ru, this message translates to:
  /// **'Кампус'**
  String get appTitle;

  /// Heading on the home screen placeholder.
  ///
  /// In ru, this message translates to:
  /// **'Добро пожаловать в Кампус'**
  String get homeWelcome;

  /// Body text on the home screen placeholder until the feed is implemented.
  ///
  /// In ru, this message translates to:
  /// **'Здесь появятся объявления, мероприятия и закупки вашего сообщества.'**
  String get homePlaceholder;

  /// Title of the settings screen and tooltip of the button that opens it.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// Header of the interface language section in settings.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get settingsLanguage;

  /// Language option that follows the device language.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get settingsLanguageSystem;

  /// Russian language option, always written in Russian.
  ///
  /// In ru, this message translates to:
  /// **'Русский'**
  String get settingsLanguageRussian;

  /// English language option, always written in English.
  ///
  /// In ru, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Header of the color theme section in settings.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get settingsTheme;

  /// Theme option that follows the device light or dark mode.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get settingsThemeSystem;

  /// Light theme option.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get settingsThemeLight;

  /// Dark theme option.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get settingsThemeDark;

  /// Request failed because the server could not be reached or did not answer in time.
  ///
  /// In ru, this message translates to:
  /// **'Нет связи с сервером. Проверьте подключение к интернету и попробуйте ещё раз.'**
  String get errorNetwork;

  /// Request failed because of an error on the server.
  ///
  /// In ru, this message translates to:
  /// **'На сервере что-то пошло не так. Попробуйте позже.'**
  String get errorServer;

  /// Request was rejected by the server for a reason without its own message.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить действие. Попробуйте ещё раз.'**
  String get errorRequest;

  /// The requested object does not exist on the server.
  ///
  /// In ru, this message translates to:
  /// **'Не найдено: возможно, это уже удалили.'**
  String get errorNotFound;

  /// The server rejected some fields of a form.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте введённые данные.'**
  String get errorValidation;

  /// A paged list can no longer be continued and must be reloaded.
  ///
  /// In ru, this message translates to:
  /// **'Список изменился. Обновите его.'**
  String get errorListChanged;

  /// Request failed because the app version is no longer supported.
  ///
  /// In ru, this message translates to:
  /// **'Эта версия приложения устарела. Обновите приложение.'**
  String get errorUpdateRequired;

  /// Request failed for an unexpected reason, e.g. an unreadable response.
  ///
  /// In ru, this message translates to:
  /// **'Что-то пошло не так. Попробуйте ещё раз.'**
  String get errorUnexpected;

  /// Button that repeats a failed request.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get errorRetry;

  /// Strip at the top of the screen while the app is offline.
  ///
  /// In ru, this message translates to:
  /// **'Нет подключения к сети'**
  String get offlineBanner;

  /// Title of the screen shown when the server no longer supports this app version.
  ///
  /// In ru, this message translates to:
  /// **'Требуется обновление'**
  String get updateTitle;

  /// Explanation on the update screen when the minimum version is unknown.
  ///
  /// In ru, this message translates to:
  /// **'Эта версия приложения больше не поддерживается. Чтобы продолжить, установите новую версию.'**
  String get updateBody;

  /// Explanation on the update screen with the oldest supported version.
  ///
  /// In ru, this message translates to:
  /// **'Эта версия приложения больше не поддерживается. Чтобы продолжить, установите версию {version} или новее.'**
  String updateBodyVersion(String version);

  /// Button on the update screen that opens the download page.
  ///
  /// In ru, this message translates to:
  /// **'Скачать обновление'**
  String get updateDownload;

  /// Message when the download page could not be opened.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть страницу загрузки.'**
  String get updateDownloadFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
