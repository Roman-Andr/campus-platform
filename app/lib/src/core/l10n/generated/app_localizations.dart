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

  /// The server limited the rate of requests.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много запросов. Подождите немного и попробуйте ещё раз.'**
  String get errorRateLimited;

  /// Title of the sign-in screens.
  ///
  /// In ru, this message translates to:
  /// **'Вход'**
  String get signInTitle;

  /// Explanation on the e-mail step of sign-in.
  ///
  /// In ru, this message translates to:
  /// **'Войдите с почтой вуза: мы пришлём на неё код для входа.'**
  String get signInEmailIntro;

  /// Label of the e-mail field on the sign-in screen.
  ///
  /// In ru, this message translates to:
  /// **'Почта вуза'**
  String get signInEmailLabel;

  /// The entered e-mail address is malformed.
  ///
  /// In ru, this message translates to:
  /// **'Введите адрес почты, например ivanov@edu.hse.ru.'**
  String get signInEmailInvalid;

  /// Button that requests a sign-in code by e-mail.
  ///
  /// In ru, this message translates to:
  /// **'Получить код'**
  String get signInGetCode;

  /// Title of the code step of sign-in.
  ///
  /// In ru, this message translates to:
  /// **'Код из письма'**
  String get signInCodeTitle;

  /// Explanation on the code step of sign-in.
  ///
  /// In ru, this message translates to:
  /// **'Мы отправили код на {email}. Если письма нет, проверьте папку «Спам».'**
  String signInCodeSent(String email);

  /// Label of the sign-in code field.
  ///
  /// In ru, this message translates to:
  /// **'Код из 6 цифр'**
  String get signInCodeLabel;

  /// The entered sign-in code is shorter than 6 digits.
  ///
  /// In ru, this message translates to:
  /// **'Введите все 6 цифр кода.'**
  String get signInCodeIncomplete;

  /// Button that signs in with the entered code.
  ///
  /// In ru, this message translates to:
  /// **'Войти'**
  String get signInSubmit;

  /// Button that requests another sign-in code.
  ///
  /// In ru, this message translates to:
  /// **'Отправить код ещё раз'**
  String get signInResend;

  /// Disabled resend button with the time left.
  ///
  /// In ru, this message translates to:
  /// **'Отправить код ещё раз можно через {wait}'**
  String signInResendIn(String wait);

  /// Confirmation after another sign-in code was requested.
  ///
  /// In ru, this message translates to:
  /// **'Новый код отправлен'**
  String get signInResent;

  /// Button that returns to the e-mail step of sign-in.
  ///
  /// In ru, this message translates to:
  /// **'Изменить почту'**
  String get signInChangeEmail;

  /// Title of the step where a new user enters the names.
  ///
  /// In ru, this message translates to:
  /// **'Регистрация'**
  String get signInNameTitle;

  /// Explanation on the registration step.
  ///
  /// In ru, this message translates to:
  /// **'Вы входите впервые. Укажите имя и фамилию — их увидят другие студенты.'**
  String get signInNameIntro;

  /// Label of the first name field.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get signInFirstName;

  /// Label of the last name field.
  ///
  /// In ru, this message translates to:
  /// **'Фамилия'**
  String get signInLastName;

  /// A required name field is empty.
  ///
  /// In ru, this message translates to:
  /// **'Заполните это поле.'**
  String get signInNameRequired;

  /// A name contains characters that are not allowed.
  ///
  /// In ru, this message translates to:
  /// **'Можно использовать только буквы, пробелы, дефисы и апострофы.'**
  String get signInNameInvalid;

  /// Button that completes registration.
  ///
  /// In ru, this message translates to:
  /// **'Зарегистрироваться'**
  String get signInFinish;

  /// The e-mail domain is not allowed to sign in.
  ///
  /// In ru, this message translates to:
  /// **'Этот адрес не из почты вуза. Войдите с адресом в домене вуза.'**
  String get authErrorDomain;

  /// The entered sign-in code is wrong.
  ///
  /// In ru, this message translates to:
  /// **'Неверный код. Проверьте письмо и попробуйте ещё раз.'**
  String get authErrorCodeInvalid;

  /// The sign-in code is no longer valid.
  ///
  /// In ru, this message translates to:
  /// **'Код истёк или уже использован. Запросите новый код.'**
  String get authErrorCodeExpired;

  /// The limit of attempts to enter the code is reached.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много неверных попыток. Запросите новый код.'**
  String get authErrorAttemptsExceeded;

  /// Sign-in requests are limited; shows how long to wait.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много попыток. Повторите через {wait}.'**
  String authErrorRateLimitedFor(String wait);

  /// A wait in seconds, e.g. before another attempt.
  ///
  /// In ru, this message translates to:
  /// **'{count} с'**
  String waitSeconds(int count);

  /// A wait in minutes, e.g. before another attempt.
  ///
  /// In ru, this message translates to:
  /// **'{count} мин'**
  String waitMinutes(int count);

  /// Header of the account section in settings.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт'**
  String get settingsAccount;

  /// Settings item that signs out on this device.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из аккаунта'**
  String get signOut;
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
