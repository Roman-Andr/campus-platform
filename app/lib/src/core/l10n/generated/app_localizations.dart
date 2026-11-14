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
  /// **'Мои объявления и брони'**
  String get listingsMine;

  /// listingsOwn
  ///
  /// In ru, this message translates to:
  /// **'Мои объявления'**
  String get listingsOwn;

  /// listingsReservations
  ///
  /// In ru, this message translates to:
  /// **'Мои брони'**
  String get listingsReservations;

  /// listingIncoming
  ///
  /// In ru, this message translates to:
  /// **'Входящие заявки'**
  String get listingIncoming;

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
