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

  /// The server rejected the action because the user has no rights to it.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к этому действию.'**
  String get errorForbidden;

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

  /// Explanation on the e-mail step of sign-in; a backup personal address works too.
  ///
  /// In ru, this message translates to:
  /// **'Войдите с почтой вуза или резервным личным адресом: мы пришлём на него код для входа.'**
  String get signInEmailIntro;

  /// Label of the e-mail field on the sign-in screen; a backup personal address works too.
  ///
  /// In ru, this message translates to:
  /// **'Почта вуза или резервная'**
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

  /// Title of the own profile screen and tooltip of the button that opens it.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get profileTitle;

  /// Title of the screen that fills in the profile after the first sign-in.
  ///
  /// In ru, this message translates to:
  /// **'Ваш профиль'**
  String get profileSetupTitle;

  /// Introduction on the profile setup screen after the first sign-in.
  ///
  /// In ru, this message translates to:
  /// **'Укажите, где вы учитесь и живёте: по этим данным вы увидите объявления своего общежития, факультета и города.'**
  String get profileSetupIntro;

  /// Title of the profile edit screen and tooltip of the button that opens it.
  ///
  /// In ru, this message translates to:
  /// **'Изменить профиль'**
  String get profileEditTitle;

  /// Label of the campus city field and item of the profile.
  ///
  /// In ru, this message translates to:
  /// **'Город-кампус'**
  String get profileCity;

  /// Label of the dormitory field and item of the profile.
  ///
  /// In ru, this message translates to:
  /// **'Общежитие'**
  String get profileDormitory;

  /// Dormitory option and profile value for users who do not live in a dormitory.
  ///
  /// In ru, this message translates to:
  /// **'Не живу в общежитии'**
  String get profileNoDormitory;

  /// Label of the faculty field and item of the profile.
  ///
  /// In ru, this message translates to:
  /// **'Факультет'**
  String get profileFaculty;

  /// Label of the course (year of study) field and item of the profile.
  ///
  /// In ru, this message translates to:
  /// **'Курс'**
  String get profileCourse;

  /// Error under a profile field left empty or rejected.
  ///
  /// In ru, this message translates to:
  /// **'Выберите из списка.'**
  String get profileChoose;

  /// Error under a city, dormitory or faculty that the server no longer offers for the city.
  ///
  /// In ru, this message translates to:
  /// **'Этого варианта больше нет, выберите другой.'**
  String get profilePlaceUnavailable;

  /// Button that saves the profile on the setup screen after the first sign-in.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get profileContinue;

  /// Button that saves changes of the profile.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get profileSave;

  /// Item of the profile: the university e-mail address.
  ///
  /// In ru, this message translates to:
  /// **'Почта'**
  String get profileEmail;

  /// Account type label of students (including postgraduates).
  ///
  /// In ru, this message translates to:
  /// **'Студент'**
  String get profileAccountStudent;

  /// Account type label of university employees.
  ///
  /// In ru, this message translates to:
  /// **'Сотрудник'**
  String get profileAccountEmployee;

  /// Account type label of former university employees.
  ///
  /// In ru, this message translates to:
  /// **'Бывший сотрудник'**
  String get profileAccountFormerEmployee;

  /// A course (year of study) in the course field and in the profile.
  ///
  /// In ru, this message translates to:
  /// **'{course} курс'**
  String profileCourseValue(int course);

  /// Profile item and screen title listing the account's e-mail addresses.
  ///
  /// In ru, this message translates to:
  /// **'Адреса почты'**
  String get profileEmails;

  /// Explanation of what a backup personal address is for.
  ///
  /// In ru, this message translates to:
  /// **'Резервный адрес нужен только для входа и уведомлений о безопасности. Он не даёт прав и не меняет тип аккаунта.'**
  String get emailsBackupHint;

  /// Kind label of a corporate university address in the list.
  ///
  /// In ru, this message translates to:
  /// **'Корпоративный'**
  String get emailsKindCorporate;

  /// Kind label of the backup personal address in the list.
  ///
  /// In ru, this message translates to:
  /// **'Резервный'**
  String get emailsKindBackup;

  /// Button that starts adding a second corporate address.
  ///
  /// In ru, this message translates to:
  /// **'Добавить корпоративный адрес'**
  String get emailsAddCorporate;

  /// Button that starts adding a backup personal address.
  ///
  /// In ru, this message translates to:
  /// **'Добавить резервный адрес'**
  String get emailsAddBackup;

  /// Button that starts replacing the existing backup personal address.
  ///
  /// In ru, this message translates to:
  /// **'Заменить резервный адрес'**
  String get emailsReplaceBackup;

  /// Label of the address field when adding an e-mail address.
  ///
  /// In ru, this message translates to:
  /// **'Адрес почты'**
  String get emailsEmailLabel;

  /// Button that requests a confirmation code for a new address.
  ///
  /// In ru, this message translates to:
  /// **'Получить код'**
  String get emailsGetCode;

  /// Explanation on the code step of adding an e-mail address.
  ///
  /// In ru, this message translates to:
  /// **'Мы отправили код на {email}.'**
  String emailsCodeSent(String email);

  /// Button that confirms the address with the code.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить'**
  String get emailsConfirm;

  /// Tooltip and confirmation button that delete an e-mail address.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get emailsDelete;

  /// Button that closes the e-mail address dialog without changes.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get emailsCancel;

  /// Confirmation dialog before deleting an e-mail address.
  ///
  /// In ru, this message translates to:
  /// **'Удалить адрес {email}?'**
  String emailsDeleteConfirm(String email);

  /// Confirmation after an e-mail address was deleted.
  ///
  /// In ru, this message translates to:
  /// **'Адрес удалён'**
  String get emailsDeleted;

  /// Confirmation after an e-mail address was added.
  ///
  /// In ru, this message translates to:
  /// **'Адрес добавлен'**
  String get emailsSaved;

  /// Note that the last corporate address cannot be deleted.
  ///
  /// In ru, this message translates to:
  /// **'Единственный корпоративный адрес нельзя удалить.'**
  String get emailsLastCorporateNote;

  /// The address belongs to another account.
  ///
  /// In ru, this message translates to:
  /// **'Этот адрес уже занят. Укажите другой.'**
  String get emailsErrorTaken;

  /// A new corporate address must be in a university domain.
  ///
  /// In ru, this message translates to:
  /// **'Укажите адрес в домене вуза.'**
  String get emailsErrorCorporateDomain;

  /// A backup address must not be in a university domain.
  ///
  /// In ru, this message translates to:
  /// **'Резервный адрес не должен быть в домене вуза.'**
  String get emailsErrorBackupDomain;

  /// Address changes are rate limited; shows how long to wait.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много запросов. Повторите через {wait}.'**
  String emailsErrorRateLimitedFor(String wait);

  /// listingsCity
  ///
  /// In ru, this message translates to:
  /// **'Город'**
  String get listingsCity;

  /// listingsEmpty
  ///
  /// In ru, this message translates to:
  /// **'Пока ничего нет'**
  String get listingsEmpty;

  /// listingsMore
  ///
  /// In ru, this message translates to:
  /// **'Загрузить ещё'**
  String get listingsMore;

  /// listingsFirst
  ///
  /// In ru, this message translates to:
  /// **'В начало'**
  String get listingsFirst;

  /// listingDetails
  ///
  /// In ru, this message translates to:
  /// **'Объявление'**
  String get listingDetails;

  /// listingAuthor
  ///
  /// In ru, this message translates to:
  /// **'Автор: {name}'**
  String listingAuthor(String name);

  /// listingReserve
  ///
  /// In ru, this message translates to:
  /// **'Забронировать'**
  String get listingReserve;

  /// listingCreate
  ///
  /// In ru, this message translates to:
  /// **'Отдам вещь'**
  String get listingCreate;

  /// listingTitle
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get listingTitle;

  /// listingDescription
  ///
  /// In ru, this message translates to:
  /// **'Описание'**
  String get listingDescription;

  /// listingScope
  ///
  /// In ru, this message translates to:
  /// **'Область видимости'**
  String get listingScope;

  /// listingAudience
  ///
  /// In ru, this message translates to:
  /// **'Аудитория'**
  String get listingAudience;

  /// listingStudents
  ///
  /// In ru, this message translates to:
  /// **'Студенты'**
  String get listingStudents;

  /// listingCommunity
  ///
  /// In ru, this message translates to:
  /// **'Все участники'**
  String get listingCommunity;

  /// listingPublish
  ///
  /// In ru, this message translates to:
  /// **'Опубликовать'**
  String get listingPublish;

  /// listingsMine
  ///
  /// In ru, this message translates to:
  /// **'Мои объявления и участие'**
  String get listingsMine;

  /// listingsOwn
  ///
  /// In ru, this message translates to:
  /// **'Мои объявления'**
  String get listingsOwn;

  /// listingsReservations
  ///
  /// In ru, this message translates to:
  /// **'Моё участие'**
  String get listingsReservations;

  /// listingIncoming
  ///
  /// In ru, this message translates to:
  /// **'Входящие заявки'**
  String get listingIncoming;

  /// Heading of the pinned notices above the feed.
  ///
  /// In ru, this message translates to:
  /// **'Закреплённые'**
  String get feedPinned;

  /// Pin deadline shown on a notice.
  ///
  /// In ru, this message translates to:
  /// **'Закреплено до {date}'**
  String feedPinnedUntil(String date);

  /// Feed filter: every kind of entry.
  ///
  /// In ru, this message translates to:
  /// **'Все типы'**
  String get feedFilterAllKinds;

  /// Feed filter: every category.
  ///
  /// In ru, this message translates to:
  /// **'Все категории'**
  String get feedFilterAllCategories;

  /// Feed filter: every dormitory.
  ///
  /// In ru, this message translates to:
  /// **'Все общежития'**
  String get feedFilterAllDormitories;

  /// Clears all feed filters.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить фильтры'**
  String get feedFiltersReset;

  /// Headman action and screen title for a pinned notice.
  ///
  /// In ru, this message translates to:
  /// **'Разместить объявление'**
  String get feedCreatePublication;

  /// Edit action of a pinned notice.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать объявление'**
  String get feedEditPublication;

  /// Area of a pinned notice.
  ///
  /// In ru, this message translates to:
  /// **'Где опубликовать'**
  String get feedPublicationScope;

  /// Label of the pin deadline picker.
  ///
  /// In ru, this message translates to:
  /// **'Закрепить до'**
  String get feedPinUntil;

  /// Validation of a pin deadline in the past.
  ///
  /// In ru, this message translates to:
  /// **'Выберите будущие дату и время.'**
  String get feedPinInFuture;

  /// A headman without a dormitory or faculty scope.
  ///
  /// In ru, this message translates to:
  /// **'Нет области для публикации.'**
  String get feedNoScope;

  /// Removes the pin but keeps the notice in the feed.
  ///
  /// In ru, this message translates to:
  /// **'Снять закреп'**
  String get feedUnpin;

  /// Listing kind name: informational publication.
  ///
  /// In ru, this message translates to:
  /// **'Объявление'**
  String get listingKindPublication;

  /// reservationPending
  ///
  /// In ru, this message translates to:
  /// **'Ожидает решения'**
  String get reservationPending;

  /// reservationAccepted
  ///
  /// In ru, this message translates to:
  /// **'Принята'**
  String get reservationAccepted;

  /// reservationRejected
  ///
  /// In ru, this message translates to:
  /// **'Отклонена'**
  String get reservationRejected;

  /// reservationCancelled
  ///
  /// In ru, this message translates to:
  /// **'Отменена'**
  String get reservationCancelled;

  /// reservationAccept
  ///
  /// In ru, this message translates to:
  /// **'Принять'**
  String get reservationAccept;

  /// reservationReject
  ///
  /// In ru, this message translates to:
  /// **'Отклонить'**
  String get reservationReject;

  /// listingActive
  ///
  /// In ru, this message translates to:
  /// **'Доступно'**
  String get listingActive;

  /// listingBusy
  ///
  /// In ru, this message translates to:
  /// **'Уже забронировано'**
  String get listingBusy;

  /// listingExpired
  ///
  /// In ru, this message translates to:
  /// **'Срок истёк'**
  String get listingExpired;

  /// listingConflict
  ///
  /// In ru, this message translates to:
  /// **'Вещь уже забронирована или больше недоступна. Обновите объявление.'**
  String get listingConflict;

  /// listingForbidden
  ///
  /// In ru, this message translates to:
  /// **'Это действие недоступно для вашего аккаунта.'**
  String get listingForbidden;

  /// listingCategory
  ///
  /// In ru, this message translates to:
  /// **'Категория'**
  String get listingCategory;

  /// listingCategoriesEmpty
  ///
  /// In ru, this message translates to:
  /// **'Категории пока недоступны. Попробуйте позже.'**
  String get listingCategoriesEmpty;

  /// listingDraft
  ///
  /// In ru, this message translates to:
  /// **'Черновик'**
  String get listingDraft;

  /// listingCompleted
  ///
  /// In ru, this message translates to:
  /// **'Завершено'**
  String get listingCompleted;

  /// listingHidden
  ///
  /// In ru, this message translates to:
  /// **'Скрыто'**
  String get listingHidden;

  /// reservationNoShow
  ///
  /// In ru, this message translates to:
  /// **'Неявка'**
  String get reservationNoShow;

  /// listingStatusUnknown
  ///
  /// In ru, this message translates to:
  /// **'Статус недоступен'**
  String get listingStatusUnknown;

  /// No description provided for @cityTimeZone.
  ///
  /// In ru, this message translates to:
  /// **'{time}, {city}, {offset}'**
  String cityTimeZone(String time, String city, String offset);

  /// No description provided for @cityDateTimeHelp.
  ///
  /// In ru, this message translates to:
  /// **'Дата и время: {city}'**
  String cityDateTimeHelp(String city);

  /// No description provided for @chooseCityDateTime.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать дату и время'**
  String get chooseCityDateTime;

  /// No description provided for @cityTimeDoesNotExist.
  ///
  /// In ru, this message translates to:
  /// **'Такого времени нет в часовом поясе города. Выберите другое время.'**
  String get cityTimeDoesNotExist;

  /// Consents and documents
  ///
  /// In ru, this message translates to:
  /// **'Согласия и документы'**
  String get consentDocuments;

  /// Community rules
  ///
  /// In ru, this message translates to:
  /// **'Правила сообщества'**
  String get consentRules;

  /// Privacy policy
  ///
  /// In ru, this message translates to:
  /// **'Политика обработки персональных данных'**
  String get consentPrivacy;

  /// Personal data processing consent
  ///
  /// In ru, this message translates to:
  /// **'Согласие на обработку персональных данных'**
  String get consentProcessing;

  /// Cross-border data transfer
  ///
  /// In ru, this message translates to:
  /// **'Трансграничная передача данных'**
  String get consentCrossBorder;

  /// I accept the community rules, privacy policy and personal data processing consent (required).
  ///
  /// In ru, this message translates to:
  /// **'Я принимаю правила сообщества, политику и согласие на обработку персональных данных (обязательно).'**
  String get consentAcceptRequired;

  /// I consent to cross-border data transfer (optional).
  ///
  /// In ru, this message translates to:
  /// **'Я согласен на трансграничную передачу данных (необязательно).'**
  String get consentCrossBorderOptional;

  /// Enables full push notification text, the Telegram bot and AI features.
  ///
  /// In ru, this message translates to:
  /// **'Разрешает полный текст push-уведомлений, Telegram-бота и ИИ-функции.'**
  String get consentCrossBorderEffects;

  /// Updated documents
  ///
  /// In ru, this message translates to:
  /// **'Обновление документов'**
  String get consentUpdateTitle;

  /// Read and accept the current document versions to continue.
  ///
  /// In ru, this message translates to:
  /// **'Для продолжения прочитайте и примите текущие версии документов.'**
  String get consentUpdateIntro;

  /// Accept and continue
  ///
  /// In ru, this message translates to:
  /// **'Принять и продолжить'**
  String get consentContinue;

  /// Close
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get consentClose;

  /// Cancel
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get consentCancel;

  /// Revoke consent
  ///
  /// In ru, this message translates to:
  /// **'Отозвать согласие'**
  String get consentRevoke;

  /// Revoke data transfer consent?
  ///
  /// In ru, this message translates to:
  /// **'Отозвать согласие на передачу данных?'**
  String get consentRevokeTitle;

  /// Push notifications will contain no names or message text. The Telegram bot and AI features will be disabled.
  ///
  /// In ru, this message translates to:
  /// **'Push-уведомления будут без имён и текста. Telegram-бот и ИИ-функции будут отключены.'**
  String get consentRevokeEffects;

  /// devicesTitle
  ///
  /// In ru, this message translates to:
  /// **'Устройства'**
  String get devicesTitle;

  /// devicesCurrent
  ///
  /// In ru, this message translates to:
  /// **'Текущее устройство'**
  String get devicesCurrent;

  /// devicesUnknown
  ///
  /// In ru, this message translates to:
  /// **'Устройство без названия'**
  String get devicesUnknown;

  /// devicesSignOutAll
  ///
  /// In ru, this message translates to:
  /// **'Выйти со всех устройств'**
  String get devicesSignOutAll;

  /// devicesConfirmAll
  ///
  /// In ru, this message translates to:
  /// **'Выйти со всех устройств, включая текущее?'**
  String get devicesConfirmAll;

  /// No description provided for @devicesConfirmOne.
  ///
  /// In ru, this message translates to:
  /// **'Выйти с устройства «{device}»?'**
  String devicesConfirmOne(String device);

  /// devicesCancel
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get devicesCancel;

  /// No description provided for @devicesSignedIn.
  ///
  /// In ru, this message translates to:
  /// **'Вход: {time}'**
  String devicesSignedIn(String time);

  /// No description provided for @devicesLastActive.
  ///
  /// In ru, this message translates to:
  /// **'Последняя активность: {time}'**
  String devicesLastActive(String time);

  /// devicesEmpty
  ///
  /// In ru, this message translates to:
  /// **'Нет активных сессий'**
  String get devicesEmpty;

  /// No description provided for @devicesPlatform.
  ///
  /// In ru, this message translates to:
  /// **'{platform, select, android{Android} web{Браузер} desktop{Компьютер} telegram{Telegram} admin{Панель администратора} other{Другая платформа}}'**
  String devicesPlatform(String platform);

  /// photoCount
  ///
  /// In ru, this message translates to:
  /// **'Фото: {count} из {limit}'**
  String photoCount(int count, int limit);

  /// photoChoose
  ///
  /// In ru, this message translates to:
  /// **'Выбрать фото'**
  String get photoChoose;

  /// photoTake
  ///
  /// In ru, this message translates to:
  /// **'Сделать фото'**
  String get photoTake;

  /// photoUploading
  ///
  /// In ru, this message translates to:
  /// **'Загружается: {percent}%'**
  String photoUploading(int percent);

  /// photoProcessing
  ///
  /// In ru, this message translates to:
  /// **'Обрабатывается…'**
  String get photoProcessing;

  /// photoRejected
  ///
  /// In ru, this message translates to:
  /// **'Отклонено: {reason}'**
  String photoRejected(String reason);

  /// photoRejectedTooLarge
  ///
  /// In ru, this message translates to:
  /// **'файл больше {megabytes} МБ'**
  String photoRejectedTooLarge(int megabytes);

  /// photoRejectedUnsupported
  ///
  /// In ru, this message translates to:
  /// **'формат не поддерживается, нужен JPEG, PNG, WebP или HEIC'**
  String get photoRejectedUnsupported;

  /// photoRejectedTooManyPixels
  ///
  /// In ru, this message translates to:
  /// **'слишком большое разрешение'**
  String get photoRejectedTooManyPixels;

  /// photoRejectedInvalidImage
  ///
  /// In ru, this message translates to:
  /// **'файл повреждён или не является изображением'**
  String get photoRejectedInvalidImage;

  /// photoRejectedOther
  ///
  /// In ru, this message translates to:
  /// **'фото нельзя использовать'**
  String get photoRejectedOther;

  /// photoRemove
  ///
  /// In ru, this message translates to:
  /// **'Удалить фото'**
  String get photoRemove;

  /// photoMoveEarlier
  ///
  /// In ru, this message translates to:
  /// **'Переместить левее'**
  String get photoMoveEarlier;

  /// photoLimit
  ///
  /// In ru, this message translates to:
  /// **'Можно добавить не больше {limit} фото'**
  String photoLimit(int limit);

  /// photoTooLarge
  ///
  /// In ru, this message translates to:
  /// **'{name}: файл больше {megabytes} МБ'**
  String photoTooLarge(String name, int megabytes);

  /// photoWait
  ///
  /// In ru, this message translates to:
  /// **'Дождитесь окончания загрузки фото'**
  String get photoWait;

  /// photoOf
  ///
  /// In ru, this message translates to:
  /// **'Фото {index} из {count}'**
  String photoOf(int index, int count);

  /// Alt text of the photo preview in a listing row.
  ///
  /// In ru, this message translates to:
  /// **'Превью фото'**
  String get photoPreview;

  /// No description provided for @listingSaveDraft.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить черновик'**
  String get listingSaveDraft;

  /// No description provided for @listingSaveChanges.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить изменения'**
  String get listingSaveChanges;

  /// No description provided for @listingEditDraft.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать черновик'**
  String get listingEditDraft;

  /// No description provided for @listingRepublish.
  ///
  /// In ru, this message translates to:
  /// **'Опубликовать снова'**
  String get listingRepublish;

  /// No description provided for @listingExtend.
  ///
  /// In ru, this message translates to:
  /// **'Продлить объявление'**
  String get listingExtend;

  /// No description provided for @listingsArchive.
  ///
  /// In ru, this message translates to:
  /// **'Архив'**
  String get listingsArchive;

  /// No description provided for @reservationCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отменить заявку или бронь'**
  String get reservationCancel;

  /// No description provided for @reservationRejectedExpired.
  ///
  /// In ru, this message translates to:
  /// **'Срок объявления истёк.'**
  String get reservationRejectedExpired;

  /// No description provided for @reservationRejectedClosed.
  ///
  /// In ru, this message translates to:
  /// **'Автор закрыл объявление.'**
  String get reservationRejectedClosed;

  /// No description provided for @reservationRejectedTimeout.
  ///
  /// In ru, this message translates to:
  /// **'Автор не ответил вовремя.'**
  String get reservationRejectedTimeout;

  /// No description provided for @reservationRejectedAuthor.
  ///
  /// In ru, this message translates to:
  /// **'Автор отклонил заявку.'**
  String get reservationRejectedAuthor;

  /// No description provided for @reservationRejectedOther.
  ///
  /// In ru, this message translates to:
  /// **'Заявка отклонена.'**
  String get reservationRejectedOther;

  /// No description provided for @listingHiddenReason.
  ///
  /// In ru, this message translates to:
  /// **'Причина скрытия: {reason}'**
  String listingHiddenReason(String reason);

  /// No description provided for @listingRateLimitedFor.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много запросов. Повторите через {seconds} с.'**
  String listingRateLimitedFor(int seconds);

  /// No description provided for @listingVersionConflict.
  ///
  /// In ru, this message translates to:
  /// **'Объявление изменилось. Откройте его заново перед правкой.'**
  String get listingVersionConflict;

  /// No description provided for @listingUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Объявление недоступно. Возможно, оно удалено или доступ изменился.'**
  String get listingUnavailable;

  /// No description provided for @listingTransitionConflict.
  ///
  /// In ru, this message translates to:
  /// **'Действие недоступно в текущем статусе. Обновите объявление.'**
  String get listingTransitionConflict;

  /// No description provided for @listingExtended.
  ///
  /// In ru, this message translates to:
  /// **'Срок объявления продлён.'**
  String get listingExtended;

  /// Title of the meeting screen and of the meeting card.
  ///
  /// In ru, this message translates to:
  /// **'Встреча'**
  String get meetingTitle;

  /// An accepted interaction without a meeting yet.
  ///
  /// In ru, this message translates to:
  /// **'Встреча ещё не назначена'**
  String get meetingNotScheduled;

  /// Label of the effective meeting before a pending transfer.
  ///
  /// In ru, this message translates to:
  /// **'Действующая встреча'**
  String get meetingCurrent;

  /// A proposal made by the current user and awaiting the answer.
  ///
  /// In ru, this message translates to:
  /// **'Ваше предложение'**
  String get meetingYourProposal;

  /// A proposal made by the other participant.
  ///
  /// In ru, this message translates to:
  /// **'Новое предложение'**
  String get meetingNewProposal;

  /// Meeting place.
  ///
  /// In ru, this message translates to:
  /// **'Место: {place}'**
  String meetingPlace(String place);

  /// The user proposed a meeting and waits for the answer.
  ///
  /// In ru, this message translates to:
  /// **'Ждём ответа второго участника'**
  String get meetingAwaitingAnswer;

  /// The other participant proposed a meeting.
  ///
  /// In ru, this message translates to:
  /// **'Ждёт вашего ответа'**
  String get meetingAwaitingYourAnswer;

  /// Opens the meeting screen from an interaction card.
  ///
  /// In ru, this message translates to:
  /// **'Открыть встречу'**
  String get meetingOpen;

  /// Accepts the current meeting proposal.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить'**
  String get meetingAccept;

  /// Proposes a new time and place for a scheduled meeting.
  ///
  /// In ru, this message translates to:
  /// **'Перенести'**
  String get meetingReschedule;

  /// Proposes the first time and place.
  ///
  /// In ru, this message translates to:
  /// **'Предложить время и место'**
  String get meetingSuggest;

  /// Replaces the pending proposal.
  ///
  /// In ru, this message translates to:
  /// **'Изменить предложение'**
  String get meetingChangeProposal;

  /// Title of the meeting proposal form.
  ///
  /// In ru, this message translates to:
  /// **'Время и место'**
  String get meetingFormTitle;

  /// Field label of the meeting place.
  ///
  /// In ru, this message translates to:
  /// **'Место встречи'**
  String get meetingPlaceLabel;

  /// A meeting place is required.
  ///
  /// In ru, this message translates to:
  /// **'Укажите место встречи.'**
  String get meetingPlaceRequired;

  /// A meeting time is required.
  ///
  /// In ru, this message translates to:
  /// **'Выберите время встречи.'**
  String get meetingTimeRequired;

  /// A meeting cannot be proposed in the past.
  ///
  /// In ru, this message translates to:
  /// **'Нельзя выбрать время в прошлом.'**
  String get meetingTimePast;

  /// Sends the meeting proposal.
  ///
  /// In ru, this message translates to:
  /// **'Отправить предложение'**
  String get meetingSaveProposal;

  /// Closes the proposal form without sending it.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get meetingDismiss;

  /// The server rejected an outdated proposal with 409.
  ///
  /// In ru, this message translates to:
  /// **'Предложение уже изменилось. Проверьте новое время и место.'**
  String get meetingStale;

  /// The interaction is not accepted, so a meeting cannot change.
  ///
  /// In ru, this message translates to:
  /// **'Встречу можно назначить только для принятого взаимодействия.'**
  String get meetingStateConflict;

  /// The server rejected the meeting time.
  ///
  /// In ru, this message translates to:
  /// **'Выберите время в будущем.'**
  String get meetingTimeInvalid;

  /// The server rejected the meeting place.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте место встречи.'**
  String get meetingPlaceInvalid;

  /// The interaction or its meeting is not available to the user.
  ///
  /// In ru, this message translates to:
  /// **'Встреча недоступна.'**
  String get meetingUnavailable;

  /// The meeting was accepted.
  ///
  /// In ru, this message translates to:
  /// **'Встреча подтверждена.'**
  String get meetingConfirmed;

  /// A meeting proposal was sent to the other participant.
  ///
  /// In ru, this message translates to:
  /// **'Предложение отправлено.'**
  String get meetingProposalSent;

  /// Withdraws the accepted interaction and its meeting.
  ///
  /// In ru, this message translates to:
  /// **'Отменить взаимодействие'**
  String get meetingCancelInteraction;

  /// Confirmation title before withdrawing the interaction.
  ///
  /// In ru, this message translates to:
  /// **'Отменить взаимодействие?'**
  String get meetingCancelTitle;

  /// Explains that withdrawing the interaction cancels the meeting.
  ///
  /// In ru, this message translates to:
  /// **'Встреча и напоминания о ней будут отменены.'**
  String get meetingCancelBody;

  /// Keeps the interaction in the confirmation dialog.
  ///
  /// In ru, this message translates to:
  /// **'Оставить'**
  String get meetingCancelKeep;

  /// Confirms withdrawing the interaction.
  ///
  /// In ru, this message translates to:
  /// **'Отменить'**
  String get meetingCancelConfirm;

  /// Title of the no-meeting confirmation screen and card.
  ///
  /// In ru, this message translates to:
  /// **'Без встречи'**
  String get noMeetingTitle;

  /// Explains the mutual confirmation without a meeting.
  ///
  /// In ru, this message translates to:
  /// **'Оба участника подтверждают, что взаимодействие состоялось без встречи.'**
  String get noMeetingBothConfirm;

  /// Opens the no-meeting confirmation screen from an interaction card.
  ///
  /// In ru, this message translates to:
  /// **'Открыть подтверждение'**
  String get noMeetingOpen;

  /// Explains that the interaction is completed after both consents.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердите, что взаимодействие состоялось без встречи. Оно завершится после согласия обоих участников.'**
  String get noMeetingIntro;

  /// Records the current user's consent.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить без встречи'**
  String get noMeetingConfirm;

  /// Label of the current user's consent.
  ///
  /// In ru, this message translates to:
  /// **'Ваше согласие'**
  String get noMeetingYourConsent;

  /// Label of the other participant's consent.
  ///
  /// In ru, this message translates to:
  /// **'Согласие второго участника'**
  String get noMeetingOtherConsent;

  /// Time of a participant's consent in the city zone.
  ///
  /// In ru, this message translates to:
  /// **'Подтверждено {time}'**
  String noMeetingConfirmedAt(String time);

  /// A participant has not confirmed the interaction yet.
  ///
  /// In ru, this message translates to:
  /// **'Пока нет'**
  String get noMeetingNotConfirmed;

  /// The current user waits for the second consent.
  ///
  /// In ru, this message translates to:
  /// **'Ожидаем подтверждения второго участника.'**
  String get noMeetingWaiting;

  /// Reloads the server state while waiting for the second consent.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get noMeetingRefresh;

  /// Completion label of an interaction finished without a meeting.
  ///
  /// In ru, this message translates to:
  /// **'Завершено без встречи'**
  String get noMeetingCompletedStatus;

  /// The interaction became completed after the second consent.
  ///
  /// In ru, this message translates to:
  /// **'Взаимодействие завершено без встречи.'**
  String get noMeetingCompleted;

  /// The agreed server moment in the city zone.
  ///
  /// In ru, this message translates to:
  /// **'Согласованное время: {time}'**
  String noMeetingAgreedAt(String time);

  /// When the interaction was completed, in the city zone.
  ///
  /// In ru, this message translates to:
  /// **'Завершено: {time}'**
  String noMeetingCompletedAt(String time);

  /// The first consent was recorded; the second participant is awaited.
  ///
  /// In ru, this message translates to:
  /// **'Согласие отправлено.'**
  String get noMeetingSent;

  /// The interaction cannot be completed without a meeting.
  ///
  /// In ru, this message translates to:
  /// **'Это взаимодействие нельзя завершить без встречи.'**
  String get noMeetingUnavailable;

  /// The user is not a participant of the interaction.
  ///
  /// In ru, this message translates to:
  /// **'Вы не можете подтвердить это взаимодействие.'**
  String get noMeetingForbidden;

  /// Own listings filter: drafts.
  ///
  /// In ru, this message translates to:
  /// **'Черновики'**
  String get mySectionDrafts;

  /// Own listings filter: active listings.
  ///
  /// In ru, this message translates to:
  /// **'Активные'**
  String get mySectionActive;

  /// Own listings filter: reserved (busy) listings.
  ///
  /// In ru, this message translates to:
  /// **'Занятые'**
  String get mySectionBusy;

  /// Listing kind name: giveaway.
  ///
  /// In ru, this message translates to:
  /// **'Отдам даром'**
  String get listingKindGiveaway;

  /// Favorites screen title and entry point.
  ///
  /// In ru, this message translates to:
  /// **'Избранное'**
  String get favoritesTitle;

  /// Favorites screen without bookmarks.
  ///
  /// In ru, this message translates to:
  /// **'В избранном пока ничего нет'**
  String get favoritesEmpty;

  /// Bookmark toggle tooltip when not bookmarked.
  ///
  /// In ru, this message translates to:
  /// **'Добавить в избранное'**
  String get favoriteAdd;

  /// Bookmark toggle tooltip when bookmarked.
  ///
  /// In ru, this message translates to:
  /// **'Убрать из избранного'**
  String get favoriteRemove;

  /// A bookmarked listing that can no longer be shown.
  ///
  /// In ru, this message translates to:
  /// **'Объявление недоступно'**
  String get favoriteUnavailable;

  /// Private lists shown from the device cache while offline.
  ///
  /// In ru, this message translates to:
  /// **'Нет сети: показаны сохранённые данные'**
  String get savedCopy;

  /// Scenario stage of own participation.
  ///
  /// In ru, this message translates to:
  /// **'Этап: {stage}'**
  String participationStage(String stage);

  /// No description provided for @timelineTitle.
  ///
  /// In ru, this message translates to:
  /// **'История взаимодействия'**
  String get timelineTitle;

  /// No description provided for @timelineOpen.
  ///
  /// In ru, this message translates to:
  /// **'История'**
  String get timelineOpen;

  /// No description provided for @timelineEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Событий пока нет'**
  String get timelineEmpty;

  /// No description provided for @timelineForbidden.
  ///
  /// In ru, this message translates to:
  /// **'История доступна только автору объявления и участнику.'**
  String get timelineForbidden;

  /// No description provided for @timelineSystem.
  ///
  /// In ru, this message translates to:
  /// **'Система'**
  String get timelineSystem;

  /// No description provided for @timelineYou.
  ///
  /// In ru, this message translates to:
  /// **'Вы'**
  String get timelineYou;

  /// No description provided for @timelineParticipant.
  ///
  /// In ru, this message translates to:
  /// **'Участник'**
  String get timelineParticipant;

  /// No description provided for @timelineRequested.
  ///
  /// In ru, this message translates to:
  /// **'Заявка отправлена'**
  String get timelineRequested;

  /// No description provided for @timelineTransition.
  ///
  /// In ru, this message translates to:
  /// **'Статус изменён'**
  String get timelineTransition;

  /// No description provided for @timelineAutoRejected.
  ///
  /// In ru, this message translates to:
  /// **'Заявка отклонена автоматически'**
  String get timelineAutoRejected;

  /// No description provided for @timelineStageChanged.
  ///
  /// In ru, this message translates to:
  /// **'Этап изменён'**
  String get timelineStageChanged;

  /// No description provided for @timelineOther.
  ///
  /// In ru, this message translates to:
  /// **'Действие'**
  String get timelineOther;

  /// No description provided for @timelineStatusChange.
  ///
  /// In ru, this message translates to:
  /// **'{from} → {to}'**
  String timelineStatusChange(String from, String to);

  /// No description provided for @timelineReason.
  ///
  /// In ru, this message translates to:
  /// **'Причина: {reason}'**
  String timelineReason(String reason);

  /// No description provided for @timelineReasonHidden.
  ///
  /// In ru, this message translates to:
  /// **'Объявление скрыто модерацией.'**
  String get timelineReasonHidden;

  /// No description provided for @timelineViaAssistant.
  ///
  /// In ru, this message translates to:
  /// **'Через ассистента'**
  String get timelineViaAssistant;

  /// No description provided for @timelineOfflineQr.
  ///
  /// In ru, this message translates to:
  /// **'Офлайн-QR'**
  String get timelineOfflineQr;

  /// Title of the profile photo and its step.
  ///
  /// In ru, this message translates to:
  /// **'Фото профиля'**
  String get profilePhoto;

  /// Button choosing the profile photo from the gallery or files.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать фото'**
  String get profilePhotoChoose;

  /// Button replacing the profile photo.
  ///
  /// In ru, this message translates to:
  /// **'Заменить фото'**
  String get profilePhotoReplace;

  /// Button taking the profile photo with the camera.
  ///
  /// In ru, this message translates to:
  /// **'Сделать снимок'**
  String get profilePhotoCamera;

  /// Button removing the profile photo.
  ///
  /// In ru, this message translates to:
  /// **'Удалить фото'**
  String get profilePhotoRemove;

  /// While the profile photo uploads.
  ///
  /// In ru, this message translates to:
  /// **'Фото загружается…'**
  String get profilePhotoUploading;

  /// While the server checks and re-encodes the photo.
  ///
  /// In ru, this message translates to:
  /// **'Фото проверяется…'**
  String get profilePhotoProcessing;

  /// The chosen photo file is too large.
  ///
  /// In ru, this message translates to:
  /// **'Файл больше {megabytes} МБ — выберите фото поменьше.'**
  String profilePhotoTooLarge(int megabytes);

  /// The server rejected the photo.
  ///
  /// In ru, this message translates to:
  /// **'Это не похоже на фото: выберите изображение JPEG, PNG, WebP или HEIC.'**
  String get profilePhotoRejected;

  /// The server did not finish checking the photo in time.
  ///
  /// In ru, this message translates to:
  /// **'Фото проверяется слишком долго. Попробуйте ещё раз.'**
  String get profilePhotoTimeout;

  /// Title of the skills section and step.
  ///
  /// In ru, this message translates to:
  /// **'Навыки'**
  String get profileSkills;

  /// The list of skills the user has.
  ///
  /// In ru, this message translates to:
  /// **'Умею'**
  String get profileSkillsCan;

  /// The list of skills the user wants to learn.
  ///
  /// In ru, this message translates to:
  /// **'Хочу научиться'**
  String get profileSkillsWants;

  /// An empty list of skills.
  ///
  /// In ru, this message translates to:
  /// **'Не указаны'**
  String get profileSkillsNone;

  /// Button and title of changing the skills.
  ///
  /// In ru, this message translates to:
  /// **'Изменить навыки'**
  String get profileSkillsEdit;

  /// Chip adding a skill to a list.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get profileSkillsAdd;

  /// Search field of the skill tags.
  ///
  /// In ru, this message translates to:
  /// **'Найти навык'**
  String get profileSkillsSearch;

  /// No skill tag matches the search.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get profileSkillsNotFound;

  /// Tooltip of removing a skill from a list.
  ///
  /// In ru, this message translates to:
  /// **'Убрать «{name}»'**
  String profileSkillRemove(String name);

  /// The server rejected skills removed from the reference.
  ///
  /// In ru, this message translates to:
  /// **'Некоторых навыков больше нет в справочнике — уберите их и сохраните снова.'**
  String get profileSkillsUnavailable;

  /// Button and title of changing the name.
  ///
  /// In ru, this message translates to:
  /// **'Изменить имя'**
  String get profileNameChange;

  /// Explanation in the name change dialog.
  ///
  /// In ru, this message translates to:
  /// **'Смена имени записывается в журнал, а следующая будет доступна не сразу. Указывайте настоящие имя и фамилию.'**
  String get profileNameRule;

  /// When the name may change next.
  ///
  /// In ru, this message translates to:
  /// **'Следующая смена имени — не раньше {date}'**
  String profileNameNextChange(String date);

  /// The server refused a name change made too soon.
  ///
  /// In ru, this message translates to:
  /// **'Имя недавно менялось. Следующая смена — не раньше {date}.'**
  String profileNameTooSoon(String date);

  /// Intro of the optional photo step.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте фото, чтобы вас узнавали при встрече. Этот шаг можно пропустить.'**
  String get profileSetupPhotoIntro;

  /// Intro of the optional skills step.
  ///
  /// In ru, this message translates to:
  /// **'Отметьте, что вы умеете и чему хотите научиться, — так проще найти, с кем обменяться навыками. Этот шаг можно пропустить.'**
  String get profileSetupSkillsIntro;

  /// Skips an optional step of filling in the profile.
  ///
  /// In ru, this message translates to:
  /// **'Пропустить'**
  String get profileSkip;

  /// Finishes filling in the profile.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get profileDone;

  /// Listing search field label
  ///
  /// In ru, this message translates to:
  /// **'Поиск объявлений'**
  String get feedSearch;

  /// Clear the listing search
  ///
  /// In ru, this message translates to:
  /// **'Сбросить поиск'**
  String get feedSearchClear;

  /// No full-text search matches
  ///
  /// In ru, this message translates to:
  /// **'Объявления не найдены'**
  String get feedSearchEmpty;

  /// Tab of own queues and place offers.
  ///
  /// In ru, this message translates to:
  /// **'Очереди и предложения'**
  String get listingsQueue;

  /// Joins the queue of an occupied listing.
  ///
  /// In ru, this message translates to:
  /// **'Встать в очередь'**
  String get waitlistJoin;

  /// Leaves the own place in a listing queue.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из очереди'**
  String get waitlistLeave;

  /// Own one-based place in the listing queue.
  ///
  /// In ru, this message translates to:
  /// **'Ваше место в очереди: {position}'**
  String waitlistPosition(int position);

  /// Re-reads the own place in the queue.
  ///
  /// In ru, this message translates to:
  /// **'Обновить позицию'**
  String get waitlistRefresh;

  /// Queue entry without a place yet.
  ///
  /// In ru, this message translates to:
  /// **'Ожидание в очереди'**
  String get waitlistWaiting;

  /// The queues and offers tab without active entries.
  ///
  /// In ru, this message translates to:
  /// **'Вы не стоите в очередях, предложений места нет'**
  String get waitlistEmpty;

  /// Heading of active queues in the My tab.
  ///
  /// In ru, this message translates to:
  /// **'Ваши очереди'**
  String get waitlistSection;

  /// The listing has a free place, so a queue is not available.
  ///
  /// In ru, this message translates to:
  /// **'Место уже свободно: забронируйте вещь.'**
  String get waitlistFree;

  /// The user already has an active queue entry.
  ///
  /// In ru, this message translates to:
  /// **'Вы уже стоите в этой очереди.'**
  String get waitlistDuplicate;

  /// A participant cannot join the queue of their own application.
  ///
  /// In ru, this message translates to:
  /// **'Вы уже участвуете в этом объявлении.'**
  String get waitlistParticipating;

  /// The listing type has no limited places to wait for.
  ///
  /// In ru, this message translates to:
  /// **'У этого объявления нет очереди.'**
  String get waitlistUnavailable;

  /// A place offer is already active for another participant.
  ///
  /// In ru, this message translates to:
  /// **'Место предложено другому участнику.'**
  String get waitlistOfferPending;

  /// The own place offer is no longer active.
  ///
  /// In ru, this message translates to:
  /// **'Предложение места больше не действует.'**
  String get waitlistOfferMissing;

  /// The own place offer expired before confirmation.
  ///
  /// In ru, this message translates to:
  /// **'Срок предложения места истёк.'**
  String get waitlistOfferExpired;

  /// Heading of place offers in the My tab.
  ///
  /// In ru, this message translates to:
  /// **'Предложения места'**
  String get offerSection;

  /// Screen opened by the place offer notification.
  ///
  /// In ru, this message translates to:
  /// **'Предложение места'**
  String get offerTitle;

  /// Heading of the place offer card.
  ///
  /// In ru, this message translates to:
  /// **'Вам предложили место'**
  String get offerOffered;

  /// Remaining offer time counted from the server expiry.
  ///
  /// In ru, this message translates to:
  /// **'Предложение истекает через {time}'**
  String offerCountdown(String time);

  /// The countdown reached the server expiry instant.
  ///
  /// In ru, this message translates to:
  /// **'Срок предложения истёк.'**
  String get offerExpired;

  /// Confirms the place offer and creates an application.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить'**
  String get offerAccept;

  /// Declines the place offer; it goes to the next member.
  ///
  /// In ru, this message translates to:
  /// **'Отказаться'**
  String get offerDecline;

  /// The place offer was confirmed.
  ///
  /// In ru, this message translates to:
  /// **'Предложение подтверждено. Заявка ждёт ответа автора.'**
  String get offerConfirmed;

  /// The place offer was declined.
  ///
  /// In ru, this message translates to:
  /// **'Вы отказались от предложения.'**
  String get offerDeclined;

  /// The notification opens a place offer that is already gone.
  ///
  /// In ru, this message translates to:
  /// **'Это предложение больше не действует.'**
  String get offerUnavailable;

  /// Opens the listing of an unavailable place offer.
  ///
  /// In ru, this message translates to:
  /// **'Открыть объявление'**
  String get offerOpenListing;

  /// Shown while the realtime client connects.
  ///
  /// In ru, this message translates to:
  /// **'Подключение к реальному времени…'**
  String get realtimeConnecting;

  /// Shown while the realtime client reconnects after a dropped connection.
  ///
  /// In ru, this message translates to:
  /// **'Связь с реальным временем потеряна. Переподключение…'**
  String get realtimeReconnecting;

  /// Realtime connection is healthy.
  ///
  /// In ru, this message translates to:
  /// **'Реальное время подключено'**
  String get realtimeConnected;

  /// Realtime is not connected.
  ///
  /// In ru, this message translates to:
  /// **'Реальное время отключено'**
  String get realtimeOffline;

  /// The screen is reloading data through the API, e.g. after returning from the background.
  ///
  /// In ru, this message translates to:
  /// **'Обновляем данные…'**
  String get realtimeUpdating;

  /// A realtime token was rejected because the session ended.
  ///
  /// In ru, this message translates to:
  /// **'Сессия завершена. Войдите снова.'**
  String get realtimeSessionEnded;

  /// The user is not a member of the realtime channel.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к этому каналу.'**
  String get realtimeChannelForbidden;

  /// The realtime channel name was rejected by the server.
  ///
  /// In ru, this message translates to:
  /// **'Канал недоступен.'**
  String get realtimeChannelInvalid;

  /// The realtime server or its API is temporarily unavailable.
  ///
  /// In ru, this message translates to:
  /// **'Реальное время временно недоступно. Попробуем снова.'**
  String get realtimeUnavailable;

  /// Centrifugo no longer kept the stream position, so the state was reloaded through the API.
  ///
  /// In ru, this message translates to:
  /// **'Часть событий уже недоступна — данные обновлены.'**
  String get realtimeHistoryLost;

  /// The device or the realtime server cannot be reached.
  ///
  /// In ru, this message translates to:
  /// **'Нет связи. Переподключение…'**
  String get realtimeNetworkLost;

  /// An unexpected realtime failure.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обновить реальное время. Попробуйте позже.'**
  String get realtimeError;

  /// Time of the last realtime event, already formatted in the city time zone.
  ///
  /// In ru, this message translates to:
  /// **'Последнее событие: {time}'**
  String realtimeLastEvent(String time);

  /// Title of the in-app notification centre.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления'**
  String get notificationsTitle;

  /// The notification centre has no records.
  ///
  /// In ru, this message translates to:
  /// **'Пока нет уведомлений'**
  String get notificationsEmpty;

  /// Marks every notification of the inbox read.
  ///
  /// In ru, this message translates to:
  /// **'Отметить все прочитанными'**
  String get notificationsMarkAllRead;

  /// The notification type has no known destination; the app does not open a wrong screen.
  ///
  /// In ru, this message translates to:
  /// **'Для этого уведомления в приложении пока нет экрана.'**
  String get notificationsNoScreen;

  /// Listing kind name: event with seats.
  ///
  /// In ru, this message translates to:
  /// **'Мероприятие'**
  String get listingKindEvent;

  /// Tooltip and title of the event creation screen.
  ///
  /// In ru, this message translates to:
  /// **'Новое мероприятие'**
  String get eventCreate;

  /// Title of the event edit screen and its action.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать мероприятие'**
  String get eventEdit;

  /// Label of the event start field.
  ///
  /// In ru, this message translates to:
  /// **'Начало'**
  String get eventStartsAt;

  /// Label of the event end field.
  ///
  /// In ru, this message translates to:
  /// **'Окончание'**
  String get eventEndsAt;

  /// Label of the event location field.
  ///
  /// In ru, this message translates to:
  /// **'Место'**
  String get eventLocation;

  /// Event location on a card.
  ///
  /// In ru, this message translates to:
  /// **'Место: {location}'**
  String eventLocationValue(String location);

  /// Label of the event seat limit field.
  ///
  /// In ru, this message translates to:
  /// **'Лимит мест'**
  String get eventCapacity;

  /// Remaining seats of an event; zero reads as no seats left.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Мест нет} one{Осталось {count} место} few{Осталось {count} места} many{Осталось {count} мест} other{Осталось {count} места}}'**
  String eventSeatsLeft(int count);

  /// The event has no free seats.
  ///
  /// In ru, this message translates to:
  /// **'Мест нет'**
  String get eventNoSeats;

  /// Sign up for an event with a free seat.
  ///
  /// In ru, this message translates to:
  /// **'Записаться'**
  String get eventSignup;

  /// The user is registered for the event.
  ///
  /// In ru, this message translates to:
  /// **'Вы записаны'**
  String get eventRegistered;

  /// The user is waiting in the event queue.
  ///
  /// In ru, this message translates to:
  /// **'Вы в очереди'**
  String get eventQueued;

  /// Join the event queue when no seats are left.
  ///
  /// In ru, this message translates to:
  /// **'Встать в очередь'**
  String get eventJoinQueue;

  /// Cancel an event registration.
  ///
  /// In ru, this message translates to:
  /// **'Отменить запись'**
  String get eventCancelSignup;

  /// Registered participants list title.
  ///
  /// In ru, this message translates to:
  /// **'Записавшиеся'**
  String get eventParticipants;

  /// Status of a registered participant in the event list.
  ///
  /// In ru, this message translates to:
  /// **'Записан'**
  String get eventParticipantRegistered;

  /// Nobody has registered for the event yet.
  ///
  /// In ru, this message translates to:
  /// **'Пока никто не записался'**
  String get eventParticipantsEmpty;

  /// The event started, so signups are closed.
  ///
  /// In ru, this message translates to:
  /// **'Запись закрыта'**
  String get eventSignupClosed;

  /// The event schedule is invalid.
  ///
  /// In ru, this message translates to:
  /// **'Мероприятие должно начинаться в будущем и заканчиваться после начала.'**
  String get eventTimeInvalid;

  /// Event schedule range with formatted start and end.
  ///
  /// In ru, this message translates to:
  /// **'{start} — {end}'**
  String eventTimeRange(String start, String end);

  /// The seat limit is below one.
  ///
  /// In ru, this message translates to:
  /// **'Лимит мест должен быть не меньше 1.'**
  String get eventCapacityInvalid;

  /// The seat limit is below the registered participant count.
  ///
  /// In ru, this message translates to:
  /// **'Лимит не может быть меньше числа записавшихся: {registered}.'**
  String eventCapacityBelowRegistered(int registered);

  /// The server refused a seat limit below the registered count.
  ///
  /// In ru, this message translates to:
  /// **'Нельзя уменьшить лимит мест ниже числа записавшихся.'**
  String get eventCapacityConflict;

  /// Menu of secondary actions of the home screen.
  ///
  /// In ru, this message translates to:
  /// **'Ещё'**
  String get moreActions;

  /// Название вида объявления: навык.
  ///
  /// In ru, this message translates to:
  /// **'Навык'**
  String get listingKindSkill;

  /// Поле направления объявления о навыке.
  ///
  /// In ru, this message translates to:
  /// **'Направление'**
  String get skillDirection;

  /// Заголовок формы создания объявления о навыке.
  ///
  /// In ru, this message translates to:
  /// **'Новое объявление о навыке'**
  String get skillCreateTitle;

  /// Автор предлагает научить навыку.
  ///
  /// In ru, this message translates to:
  /// **'Могу научить'**
  String get skillDirectionTeach;

  /// Автор ищет того, кто научит навыку.
  ///
  /// In ru, this message translates to:
  /// **'Хочу научиться'**
  String get skillDirectionLearn;

  /// Направление навыка не выбрано.
  ///
  /// In ru, this message translates to:
  /// **'Выберите, чему вы можете научить или хотите научиться.'**
  String get skillDirectionRequired;

  /// Объявление о навыке успешно создано.
  ///
  /// In ru, this message translates to:
  /// **'Объявление о навыке опубликовано.'**
  String get skillPublished;

  /// Заголовок списка вариантов времени занятия.
  ///
  /// In ru, this message translates to:
  /// **'Варианты времени'**
  String get lessonOptionsTitle;

  /// Участник предлагает занятие с вариантами времени.
  ///
  /// In ru, this message translates to:
  /// **'Предложить занятие'**
  String get lessonPropose;

  /// Заголовок формы предложения занятия.
  ///
  /// In ru, this message translates to:
  /// **'Время занятия'**
  String get lessonProposeTitle;

  /// Создаёт следующее занятие с тем же участником.
  ///
  /// In ru, this message translates to:
  /// **'Ещё занятие'**
  String get lessonRepeat;

  /// Заголовок формы повторного занятия.
  ///
  /// In ru, this message translates to:
  /// **'Ещё занятие с {name}'**
  String lessonRepeatTitle(String name);

  /// Вторая сторона повторного занятия.
  ///
  /// In ru, this message translates to:
  /// **'С кем: {name}'**
  String lessonCounterpart(String name);

  /// Подсказка о числе вариантов времени.
  ///
  /// In ru, this message translates to:
  /// **'Выберите от {min} до {max} вариантов времени.'**
  String lessonOptionsHint(int min, int max);

  /// Номер варианта времени занятия.
  ///
  /// In ru, this message translates to:
  /// **'Вариант {number}'**
  String lessonOptionNumber(int number);

  /// Добавляет ещё один вариант времени.
  ///
  /// In ru, this message translates to:
  /// **'Добавить вариант времени'**
  String get lessonAddOption;

  /// Удаляет вариант времени из формы.
  ///
  /// In ru, this message translates to:
  /// **'Удалить вариант'**
  String get lessonRemoveOption;

  /// Вариантов времени меньше допустимого.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте хотя бы {min} варианта времени.'**
  String lessonOptionsTooFew(int min);

  /// Достигнут предел вариантов времени.
  ///
  /// In ru, this message translates to:
  /// **'Можно добавить не больше {max} вариантов времени.'**
  String lessonOptionsTooMany(int max);

  /// Сервер отклонил число или значения вариантов времени.
  ///
  /// In ru, this message translates to:
  /// **'У занятия должно быть от {min} до {max} вариантов времени в будущем.'**
  String lessonOptionsInvalid(int min, int max);

  /// Занятие уже обработано, вариант времени недоступен.
  ///
  /// In ru, this message translates to:
  /// **'На занятие уже ответили. Обновите объявление.'**
  String get lessonConflict;

  /// Нет прав на действие с занятием.
  ///
  /// In ru, this message translates to:
  /// **'Отвечать на занятие могут только автор и участник.'**
  String get lessonForbidden;

  /// Занятие проходит онлайн.
  ///
  /// In ru, this message translates to:
  /// **'Онлайн'**
  String get lessonOnline;

  /// Занятие проходит очно.
  ///
  /// In ru, this message translates to:
  /// **'Очно'**
  String get lessonOffline;

  /// Переключатель онлайн-формата занятия.
  ///
  /// In ru, this message translates to:
  /// **'Онлайн-встреча'**
  String get lessonOnlineSwitch;

  /// Поле места очного занятия.
  ///
  /// In ru, this message translates to:
  /// **'Место занятия'**
  String get lessonPlaceLabel;

  /// Вариант времени ожидает ответа.
  ///
  /// In ru, this message translates to:
  /// **'Ждёт ответа'**
  String get lessonOptionProposed;

  /// Выбранный вариант времени занятия.
  ///
  /// In ru, this message translates to:
  /// **'Выбран'**
  String get lessonOptionSelected;

  /// Отклонённый вариант времени занятия.
  ///
  /// In ru, this message translates to:
  /// **'Отклонён'**
  String get lessonOptionDeclined;

  /// Вариант времени предложен текущим пользователем.
  ///
  /// In ru, this message translates to:
  /// **'Ваш вариант'**
  String get lessonOptionByYou;

  /// Вариант времени предложен участником.
  ///
  /// In ru, this message translates to:
  /// **'Вариант участника'**
  String get lessonOptionByParticipant;

  /// Вариант времени предложен автором объявления.
  ///
  /// In ru, this message translates to:
  /// **'Вариант автора'**
  String get lessonOptionByAuthor;

  /// Выбирает вариант времени занятия.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать это время'**
  String get lessonAccept;

  /// Автор предлагает встречное время занятия.
  ///
  /// In ru, this message translates to:
  /// **'Предложить другое время'**
  String get lessonCounter;

  /// Заголовок формы встречного предложения.
  ///
  /// In ru, this message translates to:
  /// **'Другое время'**
  String get lessonCounterTitle;

  /// Отправляет варианты времени занятия.
  ///
  /// In ru, this message translates to:
  /// **'Отправить'**
  String get lessonSend;

  /// Заявка на занятие отправлена.
  ///
  /// In ru, this message translates to:
  /// **'Занятие предложено.'**
  String get lessonSent;

  /// Встречное время занятия отправлено.
  ///
  /// In ru, this message translates to:
  /// **'Предложено другое время.'**
  String get lessonCounterSent;

  /// Вариант времени выбран и встреча назначена.
  ///
  /// In ru, this message translates to:
  /// **'Занятие назначено.'**
  String get lessonAccepted;

  /// Следующее занятие создано.
  ///
  /// In ru, this message translates to:
  /// **'Ещё одно занятие предложено.'**
  String get lessonRepeated;

  /// У занятия нет вариантов времени.
  ///
  /// In ru, this message translates to:
  /// **'Вариантов времени нет.'**
  String get lessonNoOptions;

  /// Участник ждёт ответа на предложенные варианты.
  ///
  /// In ru, this message translates to:
  /// **'Ждём ответа автора'**
  String get lessonAwaitingAnswer;

  /// Автор должен ответить на варианты участника.
  ///
  /// In ru, this message translates to:
  /// **'Ждёт вашего ответа'**
  String get lessonAwaitingYourAnswer;

  /// Автор ждёт ответа участника на свои варианты.
  ///
  /// In ru, this message translates to:
  /// **'Ждём ответа участника'**
  String get lessonAwaitingParticipant;

  /// Срок ответа автора на заявку.
  ///
  /// In ru, this message translates to:
  /// **'Ответить нужно до {time}'**
  String lessonResponseDue(String time);

  /// Встреча проходит онлайн, без места.
  ///
  /// In ru, this message translates to:
  /// **'Онлайн-встреча'**
  String get meetingOnline;

  /// Listing kind name: help request.
  ///
  /// In ru, this message translates to:
  /// **'Помощь'**
  String get listingKindHelp;

  /// Entry point to a new help request.
  ///
  /// In ru, this message translates to:
  /// **'Попросить помощь'**
  String get feedCreateHelp;

  /// Title of the help request form.
  ///
  /// In ru, this message translates to:
  /// **'Новый запрос о помощи'**
  String get helpCreateTitle;

  /// The help request was created.
  ///
  /// In ru, this message translates to:
  /// **'Запрос о помощи опубликован.'**
  String get helpPublished;

  /// Field of the help request relevance deadline.
  ///
  /// In ru, this message translates to:
  /// **'Актуален до'**
  String get helpDeadline;

  /// The relevance deadline is in the past.
  ///
  /// In ru, this message translates to:
  /// **'Выберите срок в будущем.'**
  String get helpDeadlinePast;

  /// The server rejected the relevance deadline.
  ///
  /// In ru, this message translates to:
  /// **'Срок должен быть в будущем и не позже срока жизни объявления.'**
  String get helpDeadlineInvalid;

  /// Applies to a help request.
  ///
  /// In ru, this message translates to:
  /// **'Откликнуться'**
  String get helpRespond;

  /// The application to a help request was sent.
  ///
  /// In ru, this message translates to:
  /// **'Отклик отправлен.'**
  String get helpResponded;

  /// The application is pending while the request is active.
  ///
  /// In ru, this message translates to:
  /// **'Отклик ждёт решения автора.'**
  String get helpApplicationPending;

  /// An application kept in reserve behind the selected executor.
  ///
  /// In ru, this message translates to:
  /// **'Резерв'**
  String get helpReserve;

  /// The respondent is kept in reserve because an executor was chosen.
  ///
  /// In ru, this message translates to:
  /// **'Исполнитель уже выбран; вы остаётесь в резерве.'**
  String get helpReserveNotice;

  /// The selected executor of a help request.
  ///
  /// In ru, this message translates to:
  /// **'Исполнитель'**
  String get helpExecutor;

  /// The current user was selected as the executor.
  ///
  /// In ru, this message translates to:
  /// **'Вы исполнитель.'**
  String get helpYouAreExecutor;

  /// The author selects one application as the executor.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать исполнителя'**
  String get helpSelectExecutor;

  /// The author selected an executor.
  ///
  /// In ru, this message translates to:
  /// **'Исполнитель выбран.'**
  String get helpSelected;

  /// The help request changed after it was loaded.
  ///
  /// In ru, this message translates to:
  /// **'Запрос уже изменился. Обновите объявление.'**
  String get helpConflict;

  /// The user may not act on this help request.
  ///
  /// In ru, this message translates to:
  /// **'Вы не можете действовать по этому запросу.'**
  String get helpForbidden;

  /// Heading of the applications to a help request.
  ///
  /// In ru, this message translates to:
  /// **'Отклики'**
  String get helpIncoming;

  /// Hint about the earliest acceptable deadline.
  ///
  /// In ru, this message translates to:
  /// **'Не позже срока жизни объявления ({days} дн.).'**
  String helpDeadlineHint(int days);

  /// The deadline exceeds the listing lifetime.
  ///
  /// In ru, this message translates to:
  /// **'Срок не может быть больше срока жизни объявления ({days} дн.).'**
  String helpDeadlineTooLate(int days);

  /// Relevance deadline shown on a help request.
  ///
  /// In ru, this message translates to:
  /// **'Актуален до {date}'**
  String helpRelevantUntil(String date);

  /// Заголовок списка личных диалогов.
  ///
  /// In ru, this message translates to:
  /// **'Диалоги'**
  String get chatsTitle;

  /// Пустой список личных диалогов.
  ///
  /// In ru, this message translates to:
  /// **'Диалогов пока нет. Напишите автору объявления.'**
  String get chatsEmpty;

  /// В диалоге ещё нет сообщений.
  ///
  /// In ru, this message translates to:
  /// **'Сообщений пока нет'**
  String get chatsNoMessages;

  /// Имя собеседника не удалось определить.
  ///
  /// In ru, this message translates to:
  /// **'Диалог'**
  String get chatsUnnamed;

  /// Заголовок личного чата без имени собеседника.
  ///
  /// In ru, this message translates to:
  /// **'Чат'**
  String get chatTitle;

  /// Пустая история личного чата.
  ///
  /// In ru, this message translates to:
  /// **'Сообщений пока нет. Напишите первым.'**
  String get chatEmpty;

  /// Подсказка поля ввода сообщения.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение'**
  String get chatInputHint;

  /// Кнопка отправки сообщения.
  ///
  /// In ru, this message translates to:
  /// **'Отправить'**
  String get chatSend;

  /// Текст сообщения пуст.
  ///
  /// In ru, this message translates to:
  /// **'Введите сообщение.'**
  String get chatMessageEmpty;

  /// Текст сообщения превышает допустимую длину.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение длиннее {max} символов.'**
  String chatMessageTooLong(int max);

  /// Сообщение отправляется на сервер.
  ///
  /// In ru, this message translates to:
  /// **'Отправляется…'**
  String get chatMessageSending;

  /// Сообщение в очереди ждёт сети.
  ///
  /// In ru, this message translates to:
  /// **'Ждёт отправки'**
  String get chatMessageWaiting;

  /// Сообщение не отправлено из-за ошибки.
  ///
  /// In ru, this message translates to:
  /// **'Не отправлено'**
  String get chatMessageFailed;

  /// Повторить отправку сообщения.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get chatMessageRetry;

  /// Удаляет неотправленное сообщение из очереди.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get chatMessageDiscard;

  /// The next page of dialogs failed to load.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить ещё диалоги.'**
  String get chatLoadMoreFailed;

  /// The previous page of the chat history failed to load.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить более ранние сообщения.'**
  String get chatLoadOlderFailed;

  /// A realtime update failed to load the missed messages.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обновить чат.'**
  String get chatSyncFailed;

  /// Загрузить предыдущую страницу истории.
  ///
  /// In ru, this message translates to:
  /// **'Показать ранее'**
  String get chatLoadOlder;

  /// Открыть личный диалог с автором объявления.
  ///
  /// In ru, this message translates to:
  /// **'Написать сообщение'**
  String get chatStart;

  /// Диалог не существует или недоступен.
  ///
  /// In ru, this message translates to:
  /// **'Диалог недоступен'**
  String get chatNotFound;

  /// Выпускник не может создать новый диалог.
  ///
  /// In ru, this message translates to:
  /// **'Выпускники могут писать только в существующие диалоги.'**
  String get chatForbiddenAlumni;

  /// Один идентификатор сообщения использован с другим текстом.
  ///
  /// In ru, this message translates to:
  /// **'Это сообщение уже отправлено с другим текстом.'**
  String get chatFailureConflict;

  /// Сервер отклонил текст сообщения.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение не отправлено: проверьте текст.'**
  String get chatFailureInvalid;

  /// Превышен лимит отправки сообщений.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много сообщений. Попробуйте позже.'**
  String get chatFailureRateLimited;

  /// Сообщение ждёт восстановления сети.
  ///
  /// In ru, this message translates to:
  /// **'Нет сети. Сообщение отправится, когда связь вернётся.'**
  String get chatFailureNetwork;

  /// Действие в диалоге запрещено.
  ///
  /// In ru, this message translates to:
  /// **'Вы не можете писать в этот диалог.'**
  String get chatFailureForbidden;

  /// Сессия завершена, сообщение не отправлено.
  ///
  /// In ru, this message translates to:
  /// **'Сессия истекла. Войдите снова.'**
  String get chatFailureUnauthorized;

  /// Временная ошибка сервера при отправке.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение не отправлено: сервер недоступен.'**
  String get chatFailureServer;

  /// Неизвестная ошибка отправки.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение не отправлено. Попробуйте ещё раз.'**
  String get chatFailureUnexpected;

  /// Переход к личным диалогам из профиля.
  ///
  /// In ru, this message translates to:
  /// **'Мои диалоги'**
  String get profileChats;
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
