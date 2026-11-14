// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Кампус';

  @override
  String get homeWelcome => 'Добро пожаловать в Кампус';

  @override
  String get homePlaceholder =>
      'Здесь появятся объявления, мероприятия и закупки вашего сообщества.';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsTheme => 'Тема';

  @override
  String get settingsThemeSystem => 'Как в системе';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get errorNetwork =>
      'Нет связи с сервером. Проверьте подключение к интернету и попробуйте ещё раз.';

  @override
  String get errorServer => 'На сервере что-то пошло не так. Попробуйте позже.';

  @override
  String get errorRequest =>
      'Не удалось выполнить действие. Попробуйте ещё раз.';

  @override
  String get errorNotFound => 'Не найдено: возможно, это уже удалили.';

  @override
  String get errorValidation => 'Проверьте введённые данные.';

  @override
  String get errorListChanged => 'Список изменился. Обновите его.';

  @override
  String get errorUpdateRequired =>
      'Эта версия приложения устарела. Обновите приложение.';

  @override
  String get errorUnexpected => 'Что-то пошло не так. Попробуйте ещё раз.';

  @override
  String get errorRetry => 'Повторить';

  @override
  String get offlineBanner => 'Нет подключения к сети';

  @override
  String get updateTitle => 'Требуется обновление';

  @override
  String get updateBody =>
      'Эта версия приложения больше не поддерживается. Чтобы продолжить, установите новую версию.';

  @override
  String updateBodyVersion(String version) {
    return 'Эта версия приложения больше не поддерживается. Чтобы продолжить, установите версию $version или новее.';
  }

  @override
  String get updateDownload => 'Скачать обновление';

  @override
  String get updateDownloadFailed => 'Не удалось открыть страницу загрузки.';

  @override
  String get errorRateLimited =>
      'Слишком много запросов. Подождите немного и попробуйте ещё раз.';

  @override
  String get signInTitle => 'Вход';

  @override
  String get signInEmailIntro =>
      'Войдите с почтой вуза: мы пришлём на неё код для входа.';

  @override
  String get signInEmailLabel => 'Почта вуза';

  @override
  String get signInEmailInvalid =>
      'Введите адрес почты, например ivanov@edu.hse.ru.';

  @override
  String get signInGetCode => 'Получить код';

  @override
  String get signInCodeTitle => 'Код из письма';

  @override
  String signInCodeSent(String email) {
    return 'Мы отправили код на $email. Если письма нет, проверьте папку «Спам».';
  }

  @override
  String get signInCodeLabel => 'Код из 6 цифр';

  @override
  String get signInCodeIncomplete => 'Введите все 6 цифр кода.';

  @override
  String get signInSubmit => 'Войти';

  @override
  String get signInResend => 'Отправить код ещё раз';

  @override
  String signInResendIn(String wait) {
    return 'Отправить код ещё раз можно через $wait';
  }

  @override
  String get signInResent => 'Новый код отправлен';

  @override
  String get signInChangeEmail => 'Изменить почту';

  @override
  String get signInNameTitle => 'Регистрация';

  @override
  String get signInNameIntro =>
      'Вы входите впервые. Укажите имя и фамилию — их увидят другие студенты.';

  @override
  String get signInFirstName => 'Имя';

  @override
  String get signInLastName => 'Фамилия';

  @override
  String get signInNameRequired => 'Заполните это поле.';

  @override
  String get signInNameInvalid =>
      'Можно использовать только буквы, пробелы, дефисы и апострофы.';

  @override
  String get signInFinish => 'Зарегистрироваться';

  @override
  String get authErrorDomain =>
      'Этот адрес не из почты вуза. Войдите с адресом в домене вуза.';

  @override
  String get authErrorCodeInvalid =>
      'Неверный код. Проверьте письмо и попробуйте ещё раз.';

  @override
  String get authErrorCodeExpired =>
      'Код истёк или уже использован. Запросите новый код.';

  @override
  String get authErrorAttemptsExceeded =>
      'Слишком много неверных попыток. Запросите новый код.';

  @override
  String authErrorRateLimitedFor(String wait) {
    return 'Слишком много попыток. Повторите через $wait.';
  }

  @override
  String waitSeconds(int count) {
    return '$count с';
  }

  @override
  String waitMinutes(int count) {
    return '$count мин';
  }

  @override
  String get settingsAccount => 'Аккаунт';

  @override
  String get signOut => 'Выйти из аккаунта';

  @override
  String get profileTitle => 'Профиль';

  @override
  String get profileSetupTitle => 'Ваш профиль';

  @override
  String get profileSetupIntro =>
      'Укажите, где вы учитесь и живёте: по этим данным вы увидите объявления своего общежития, факультета и города.';

  @override
  String get profileEditTitle => 'Изменить профиль';

  @override
  String get profileCity => 'Город-кампус';

  @override
  String get profileDormitory => 'Общежитие';

  @override
  String get profileNoDormitory => 'Не живу в общежитии';

  @override
  String get profileFaculty => 'Факультет';

  @override
  String get profileCourse => 'Курс';

  @override
  String get profileChoose => 'Выберите из списка.';

  @override
  String get profilePlaceUnavailable =>
      'Этого варианта больше нет, выберите другой.';

  @override
  String get profileContinue => 'Продолжить';

  @override
  String get profileSave => 'Сохранить';

  @override
  String get profileEmail => 'Почта';

  @override
  String get profileAccountStudent => 'Студент';

  @override
  String get profileAccountEmployee => 'Сотрудник';

  @override
  String profileCourseValue(int course) {
    return '$course курс';
  }

  @override
  String get listingsCity => 'Город';

  @override
  String get listingsEmpty => 'Пока ничего нет';

  @override
  String get listingsMore => 'Загрузить ещё';

  @override
  String get listingsFirst => 'В начало';

  @override
  String get listingDetails => 'Объявление';

  @override
  String listingAuthor(String name) {
    return 'Автор: $name';
  }

  @override
  String get listingReserve => 'Забронировать';

  @override
  String get listingCreate => 'Отдам вещь';

  @override
  String get listingTitle => 'Название';

  @override
  String get listingDescription => 'Описание';

  @override
  String get listingScope => 'Область видимости';

  @override
  String get listingAudience => 'Аудитория';

  @override
  String get listingStudents => 'Студенты';

  @override
  String get listingCommunity => 'Все участники';

  @override
  String get listingPublish => 'Опубликовать';

  @override
  String get listingsMine => 'Мои объявления и брони';

  @override
  String get listingsOwn => 'Мои объявления';

  @override
  String get listingsReservations => 'Мои брони';

  @override
  String get listingIncoming => 'Входящие заявки';

  @override
  String get reservationPending => 'Ожидает решения';

  @override
  String get reservationAccepted => 'Принята';

  @override
  String get reservationRejected => 'Отклонена';

  @override
  String get reservationCancelled => 'Отменена';

  @override
  String get reservationAccept => 'Принять';

  @override
  String get reservationReject => 'Отклонить';

  @override
  String get listingActive => 'Доступно';

  @override
  String get listingBusy => 'Уже забронировано';

  @override
  String get listingExpired => 'Срок истёк';

  @override
  String get listingConflict =>
      'Вещь уже забронирована или больше недоступна. Обновите объявление.';

  @override
  String get listingForbidden => 'Это действие недоступно для вашего аккаунта.';

  @override
  String get listingCategory => 'Категория';

  @override
  String get listingCategoriesEmpty =>
      'Категории пока недоступны. Попробуйте позже.';

  @override
  String get listingDraft => 'Черновик';

  @override
  String get listingCompleted => 'Завершено';

  @override
  String get listingHidden => 'Скрыто';

  @override
  String get reservationNoShow => 'Неявка';

  @override
  String get listingStatusUnknown => 'Статус недоступен';

  @override
  String cityTimeZone(String time, String city, String offset) {
    return '$time, $city, $offset';
  }

  @override
  String cityDateTimeHelp(String city) {
    return 'Дата и время: $city';
  }

  @override
  String get chooseCityDateTime => 'Выбрать дату и время';

  @override
  String get cityTimeDoesNotExist =>
      'Такого времени нет в часовом поясе города. Выберите другое время.';

  @override
  String get consentDocuments => 'Согласия и документы';

  @override
  String get consentRules => 'Правила сообщества';

  @override
  String get consentPrivacy => 'Политика обработки персональных данных';

  @override
  String get consentProcessing => 'Согласие на обработку персональных данных';

  @override
  String get consentCrossBorder => 'Трансграничная передача данных';

  @override
  String get consentAcceptRequired =>
      'Я принимаю правила сообщества, политику и согласие на обработку персональных данных (обязательно).';

  @override
  String get consentCrossBorderOptional =>
      'Я согласен на трансграничную передачу данных (необязательно).';

  @override
  String get consentCrossBorderEffects =>
      'Разрешает полный текст push-уведомлений, Telegram-бота и ИИ-функции.';

  @override
  String get consentUpdateTitle => 'Обновление документов';

  @override
  String get consentUpdateIntro =>
      'Для продолжения прочитайте и примите текущие версии документов.';

  @override
  String get consentContinue => 'Принять и продолжить';

  @override
  String get consentClose => 'Закрыть';

  @override
  String get consentCancel => 'Отмена';

  @override
  String get consentRevoke => 'Отозвать согласие';

  @override
  String get consentRevokeTitle => 'Отозвать согласие на передачу данных?';

  @override
  String get consentRevokeEffects =>
      'Push-уведомления будут без имён и текста. Telegram-бот и ИИ-функции будут отключены.';
}
