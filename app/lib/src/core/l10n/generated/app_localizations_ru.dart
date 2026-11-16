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
  String get errorForbidden => 'Нет доступа к этому действию.';

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
      'Войдите с почтой вуза или резервным личным адресом: мы пришлём на него код для входа.';

  @override
  String get signInEmailLabel => 'Почта вуза или резервная';

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
  String get profileAccountFormerEmployee => 'Бывший сотрудник';

  @override
  String profileCourseValue(int course) {
    return '$course курс';
  }

  @override
  String get profileEmails => 'Адреса почты';

  @override
  String get emailsBackupHint =>
      'Резервный адрес нужен только для входа и уведомлений о безопасности. Он не даёт прав и не меняет тип аккаунта.';

  @override
  String get emailsKindCorporate => 'Корпоративный';

  @override
  String get emailsKindBackup => 'Резервный';

  @override
  String get emailsAddCorporate => 'Добавить корпоративный адрес';

  @override
  String get emailsAddBackup => 'Добавить резервный адрес';

  @override
  String get emailsReplaceBackup => 'Заменить резервный адрес';

  @override
  String get emailsEmailLabel => 'Адрес почты';

  @override
  String get emailsGetCode => 'Получить код';

  @override
  String emailsCodeSent(String email) {
    return 'Мы отправили код на $email.';
  }

  @override
  String get emailsConfirm => 'Подтвердить';

  @override
  String get emailsDelete => 'Удалить';

  @override
  String get emailsCancel => 'Отмена';

  @override
  String emailsDeleteConfirm(String email) {
    return 'Удалить адрес $email?';
  }

  @override
  String get emailsDeleted => 'Адрес удалён';

  @override
  String get emailsSaved => 'Адрес добавлен';

  @override
  String get emailsLastCorporateNote =>
      'Единственный корпоративный адрес нельзя удалить.';

  @override
  String get emailsErrorTaken => 'Этот адрес уже занят. Укажите другой.';

  @override
  String get emailsErrorCorporateDomain => 'Укажите адрес в домене вуза.';

  @override
  String get emailsErrorBackupDomain =>
      'Резервный адрес не должен быть в домене вуза.';

  @override
  String emailsErrorRateLimitedFor(String wait) {
    return 'Слишком много запросов. Повторите через $wait.';
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
  String get listingsMine => 'Мои объявления и участие';

  @override
  String get listingsOwn => 'Мои объявления';

  @override
  String get listingsReservations => 'Моё участие';

  @override
  String get listingIncoming => 'Входящие заявки';

  @override
  String get feedPinned => 'Закреплённые';

  @override
  String feedPinnedUntil(String date) {
    return 'Закреплено до $date';
  }

  @override
  String get feedFilterAllKinds => 'Все типы';

  @override
  String get feedFilterAllCategories => 'Все категории';

  @override
  String get feedFilterAllDormitories => 'Все общежития';

  @override
  String get feedFiltersReset => 'Сбросить фильтры';

  @override
  String get feedCreatePublication => 'Разместить объявление';

  @override
  String get feedEditPublication => 'Редактировать объявление';

  @override
  String get feedPublicationScope => 'Где опубликовать';

  @override
  String get feedPinUntil => 'Закрепить до';

  @override
  String get feedPinInFuture => 'Выберите будущие дату и время.';

  @override
  String get feedNoScope => 'Нет области для публикации.';

  @override
  String get feedUnpin => 'Снять закреп';

  @override
  String get listingKindPublication => 'Объявление';

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

  @override
  String get devicesTitle => 'Устройства';

  @override
  String get devicesCurrent => 'Текущее устройство';

  @override
  String get devicesUnknown => 'Устройство без названия';

  @override
  String get devicesSignOutAll => 'Выйти со всех устройств';

  @override
  String get devicesConfirmAll => 'Выйти со всех устройств, включая текущее?';

  @override
  String devicesConfirmOne(String device) {
    return 'Выйти с устройства «$device»?';
  }

  @override
  String get devicesCancel => 'Отмена';

  @override
  String devicesSignedIn(String time) {
    return 'Вход: $time';
  }

  @override
  String devicesLastActive(String time) {
    return 'Последняя активность: $time';
  }

  @override
  String get devicesEmpty => 'Нет активных сессий';

  @override
  String devicesPlatform(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'android': 'Android',
      'web': 'Браузер',
      'desktop': 'Компьютер',
      'telegram': 'Telegram',
      'admin': 'Панель администратора',
      'other': 'Другая платформа',
    });
    return '$_temp0';
  }

  @override
  String photoCount(int count, int limit) {
    return 'Фото: $count из $limit';
  }

  @override
  String get photoChoose => 'Выбрать фото';

  @override
  String get photoTake => 'Сделать фото';

  @override
  String photoUploading(int percent) {
    return 'Загружается: $percent%';
  }

  @override
  String get photoProcessing => 'Обрабатывается…';

  @override
  String photoRejected(String reason) {
    return 'Отклонено: $reason';
  }

  @override
  String photoRejectedTooLarge(int megabytes) {
    return 'файл больше $megabytes МБ';
  }

  @override
  String get photoRejectedUnsupported =>
      'формат не поддерживается, нужен JPEG, PNG, WebP или HEIC';

  @override
  String get photoRejectedTooManyPixels => 'слишком большое разрешение';

  @override
  String get photoRejectedInvalidImage =>
      'файл повреждён или не является изображением';

  @override
  String get photoRejectedOther => 'фото нельзя использовать';

  @override
  String get photoRemove => 'Удалить фото';

  @override
  String get photoMoveEarlier => 'Переместить левее';

  @override
  String photoLimit(int limit) {
    return 'Можно добавить не больше $limit фото';
  }

  @override
  String photoTooLarge(String name, int megabytes) {
    return '$name: файл больше $megabytes МБ';
  }

  @override
  String get photoWait => 'Дождитесь окончания загрузки фото';

  @override
  String photoOf(int index, int count) {
    return 'Фото $index из $count';
  }

  @override
  String get photoPreview => 'Превью фото';

  @override
  String get listingSaveDraft => 'Сохранить черновик';

  @override
  String get listingSaveChanges => 'Сохранить изменения';

  @override
  String get listingEditDraft => 'Редактировать черновик';

  @override
  String get listingRepublish => 'Опубликовать снова';

  @override
  String get listingExtend => 'Продлить объявление';

  @override
  String get listingsArchive => 'Архив';

  @override
  String get reservationCancel => 'Отменить заявку или бронь';

  @override
  String get reservationRejectedExpired => 'Срок объявления истёк.';

  @override
  String get reservationRejectedClosed => 'Автор закрыл объявление.';

  @override
  String get reservationRejectedTimeout => 'Автор не ответил вовремя.';

  @override
  String get reservationRejectedAuthor => 'Автор отклонил заявку.';

  @override
  String get reservationRejectedOther => 'Заявка отклонена.';

  @override
  String listingHiddenReason(String reason) {
    return 'Причина скрытия: $reason';
  }

  @override
  String listingRateLimitedFor(int seconds) {
    return 'Слишком много запросов. Повторите через $seconds с.';
  }

  @override
  String get listingVersionConflict =>
      'Объявление изменилось. Откройте его заново перед правкой.';

  @override
  String get listingUnavailable =>
      'Объявление недоступно. Возможно, оно удалено или доступ изменился.';

  @override
  String get listingTransitionConflict =>
      'Действие недоступно в текущем статусе. Обновите объявление.';

  @override
  String get listingExtended => 'Срок объявления продлён.';

  @override
  String get listingCancel => 'Отменить объявление';

  @override
  String get listingCancelTitle => 'Отменить объявление?';

  @override
  String get listingCancelBody =>
      'Объявление закроется, а принятые заявки и брони будут отменены.';

  @override
  String listingCancelAcceptedWarning(int count) {
    return 'Принятых взаимодействий: $count. Участники получат уведомление с причиной.';
  }

  @override
  String get listingCancelReason => 'Причина отмены';

  @override
  String get listingCancelReasonRequired =>
      'Укажите причину: объявление уже принято.';

  @override
  String get listingCancelReasonMissing => 'Укажите причину отмены.';

  @override
  String listingCancelReasonTooLong(int max) {
    return 'Причина длиннее $max символов.';
  }

  @override
  String get listingCancelReasonInvalid => 'Проверьте причину отмены.';

  @override
  String get listingCancelConfirm => 'Отменить объявление';

  @override
  String get listingCancelKeep => 'Оставить';

  @override
  String get listingCancelled => 'Объявление отменено.';

  @override
  String listingCancelledByAuthor(String reason) {
    return 'Автор отменил: $reason';
  }

  @override
  String get interactionCancelTitle => 'Отменить взаимодействие?';

  @override
  String get interactionCancelBody => 'Заявка или бронь будут отменены.';

  @override
  String get interactionLateCancellation =>
      'Это поздняя отмена: она будет учтена как поздняя.';

  @override
  String get interactionCancellationApproval =>
      'Организатор должен подтвердить выход.';

  @override
  String get interactionCancelKeep => 'Оставить';

  @override
  String get interactionCancelConfirm => 'Всё равно отменить';

  @override
  String get meetingTitle => 'Встреча';

  @override
  String get meetingNotScheduled => 'Встреча ещё не назначена';

  @override
  String get meetingCurrent => 'Действующая встреча';

  @override
  String get meetingYourProposal => 'Ваше предложение';

  @override
  String get meetingNewProposal => 'Новое предложение';

  @override
  String meetingPlace(String place) {
    return 'Место: $place';
  }

  @override
  String get meetingAwaitingAnswer => 'Ждём ответа второго участника';

  @override
  String get meetingAwaitingYourAnswer => 'Ждёт вашего ответа';

  @override
  String get meetingOpen => 'Открыть встречу';

  @override
  String get meetingAccept => 'Подтвердить';

  @override
  String get meetingReschedule => 'Перенести';

  @override
  String get meetingSuggest => 'Предложить время и место';

  @override
  String get meetingChangeProposal => 'Изменить предложение';

  @override
  String get meetingFormTitle => 'Время и место';

  @override
  String get meetingPlaceLabel => 'Место встречи';

  @override
  String get meetingPlaceRequired => 'Укажите место встречи.';

  @override
  String get meetingTimeRequired => 'Выберите время встречи.';

  @override
  String get meetingTimePast => 'Нельзя выбрать время в прошлом.';

  @override
  String get meetingSaveProposal => 'Отправить предложение';

  @override
  String get meetingDismiss => 'Отмена';

  @override
  String get meetingStale =>
      'Предложение уже изменилось. Проверьте новое время и место.';

  @override
  String get meetingStateConflict =>
      'Встречу можно назначить только для принятого взаимодействия.';

  @override
  String get meetingTimeInvalid => 'Выберите время в будущем.';

  @override
  String get meetingPlaceInvalid => 'Проверьте место встречи.';

  @override
  String get meetingUnavailable => 'Встреча недоступна.';

  @override
  String get meetingConfirmed => 'Встреча подтверждена.';

  @override
  String get meetingProposalSent => 'Предложение отправлено.';

  @override
  String get meetingCancelInteraction => 'Отменить взаимодействие';

  @override
  String get meetingCancelTitle => 'Отменить взаимодействие?';

  @override
  String get meetingCancelBody => 'Встреча и напоминания о ней будут отменены.';

  @override
  String get meetingCancelKeep => 'Оставить';

  @override
  String get meetingCancelConfirm => 'Отменить';

  @override
  String get noMeetingTitle => 'Без встречи';

  @override
  String get noMeetingBothConfirm =>
      'Оба участника подтверждают, что взаимодействие состоялось без встречи.';

  @override
  String get noMeetingOpen => 'Открыть подтверждение';

  @override
  String get noMeetingIntro =>
      'Подтвердите, что взаимодействие состоялось без встречи. Оно завершится после согласия обоих участников.';

  @override
  String get noMeetingConfirm => 'Подтвердить без встречи';

  @override
  String get noMeetingYourConsent => 'Ваше согласие';

  @override
  String get noMeetingOtherConsent => 'Согласие второго участника';

  @override
  String noMeetingConfirmedAt(String time) {
    return 'Подтверждено $time';
  }

  @override
  String get noMeetingNotConfirmed => 'Пока нет';

  @override
  String get noMeetingWaiting => 'Ожидаем подтверждения второго участника.';

  @override
  String get noMeetingRefresh => 'Обновить';

  @override
  String get noMeetingCompletedStatus => 'Завершено без встречи';

  @override
  String get noMeetingCompleted => 'Взаимодействие завершено без встречи.';

  @override
  String noMeetingAgreedAt(String time) {
    return 'Согласованное время: $time';
  }

  @override
  String noMeetingCompletedAt(String time) {
    return 'Завершено: $time';
  }

  @override
  String get noMeetingSent => 'Согласие отправлено.';

  @override
  String get noMeetingUnavailable =>
      'Это взаимодействие нельзя завершить без встречи.';

  @override
  String get noMeetingForbidden =>
      'Вы не можете подтвердить это взаимодействие.';

  @override
  String get mySectionDrafts => 'Черновики';

  @override
  String get mySectionActive => 'Активные';

  @override
  String get mySectionBusy => 'Занятые';

  @override
  String get listingKindGiveaway => 'Отдам даром';

  @override
  String get favoritesTitle => 'Избранное';

  @override
  String get favoritesEmpty => 'В избранном пока ничего нет';

  @override
  String get favoriteAdd => 'Добавить в избранное';

  @override
  String get favoriteRemove => 'Убрать из избранного';

  @override
  String get favoriteUnavailable => 'Объявление недоступно';

  @override
  String get savedCopy => 'Нет сети: показаны сохранённые данные';

  @override
  String participationStage(String stage) {
    return 'Этап: $stage';
  }

  @override
  String get timelineTitle => 'История взаимодействия';

  @override
  String get timelineOpen => 'История';

  @override
  String get timelineEmpty => 'Событий пока нет';

  @override
  String get timelineForbidden =>
      'История доступна только автору объявления и участнику.';

  @override
  String get timelineSystem => 'Система';

  @override
  String get timelineYou => 'Вы';

  @override
  String get timelineParticipant => 'Участник';

  @override
  String get timelineRequested => 'Заявка отправлена';

  @override
  String get timelineTransition => 'Статус изменён';

  @override
  String get timelineAutoRejected => 'Заявка отклонена автоматически';

  @override
  String get timelineStageChanged => 'Этап изменён';

  @override
  String get timelineOther => 'Действие';

  @override
  String timelineStatusChange(String from, String to) {
    return '$from → $to';
  }

  @override
  String timelineReason(String reason) {
    return 'Причина: $reason';
  }

  @override
  String get timelineReasonHidden => 'Объявление скрыто модерацией.';

  @override
  String get timelineViaAssistant => 'Через ассистента';

  @override
  String get timelineOfflineQr => 'Офлайн-QR';

  @override
  String get profilePhoto => 'Фото профиля';

  @override
  String get profilePhotoChoose => 'Выбрать фото';

  @override
  String get profilePhotoReplace => 'Заменить фото';

  @override
  String get profilePhotoCamera => 'Сделать снимок';

  @override
  String get profilePhotoRemove => 'Удалить фото';

  @override
  String get profilePhotoUploading => 'Фото загружается…';

  @override
  String get profilePhotoProcessing => 'Фото проверяется…';

  @override
  String profilePhotoTooLarge(int megabytes) {
    return 'Файл больше $megabytes МБ — выберите фото поменьше.';
  }

  @override
  String get profilePhotoRejected =>
      'Это не похоже на фото: выберите изображение JPEG, PNG, WebP или HEIC.';

  @override
  String get profilePhotoTimeout =>
      'Фото проверяется слишком долго. Попробуйте ещё раз.';

  @override
  String get profileSkills => 'Навыки';

  @override
  String get profileSkillsCan => 'Умею';

  @override
  String get profileSkillsWants => 'Хочу научиться';

  @override
  String get profileSkillsNone => 'Не указаны';

  @override
  String get profileSkillsEdit => 'Изменить навыки';

  @override
  String get profileSkillsAdd => 'Добавить';

  @override
  String get profileSkillsSearch => 'Найти навык';

  @override
  String get profileSkillsNotFound => 'Ничего не найдено';

  @override
  String profileSkillRemove(String name) {
    return 'Убрать «$name»';
  }

  @override
  String get profileSkillsUnavailable =>
      'Некоторых навыков больше нет в справочнике — уберите их и сохраните снова.';

  @override
  String get profileNameChange => 'Изменить имя';

  @override
  String get profileNameRule =>
      'Смена имени записывается в журнал, а следующая будет доступна не сразу. Указывайте настоящие имя и фамилию.';

  @override
  String profileNameNextChange(String date) {
    return 'Следующая смена имени — не раньше $date';
  }

  @override
  String profileNameTooSoon(String date) {
    return 'Имя недавно менялось. Следующая смена — не раньше $date.';
  }

  @override
  String get profileSetupPhotoIntro =>
      'Добавьте фото, чтобы вас узнавали при встрече. Этот шаг можно пропустить.';

  @override
  String get profileSetupSkillsIntro =>
      'Отметьте, что вы умеете и чему хотите научиться, — так проще найти, с кем обменяться навыками. Этот шаг можно пропустить.';

  @override
  String get profileSkip => 'Пропустить';

  @override
  String get profileDone => 'Готово';

  @override
  String get feedSearch => 'Поиск объявлений';

  @override
  String get feedSearchClear => 'Сбросить поиск';

  @override
  String get feedSearchEmpty => 'Объявления не найдены';

  @override
  String get listingsQueue => 'Очереди и предложения';

  @override
  String get waitlistJoin => 'Встать в очередь';

  @override
  String get waitlistLeave => 'Выйти из очереди';

  @override
  String waitlistPosition(int position) {
    return 'Ваше место в очереди: $position';
  }

  @override
  String get waitlistRefresh => 'Обновить позицию';

  @override
  String get waitlistWaiting => 'Ожидание в очереди';

  @override
  String get waitlistEmpty => 'Вы не стоите в очередях, предложений места нет';

  @override
  String get waitlistSection => 'Ваши очереди';

  @override
  String get waitlistFree => 'Место уже свободно: забронируйте вещь.';

  @override
  String get waitlistDuplicate => 'Вы уже стоите в этой очереди.';

  @override
  String get waitlistParticipating => 'Вы уже участвуете в этом объявлении.';

  @override
  String get waitlistUnavailable => 'У этого объявления нет очереди.';

  @override
  String get waitlistOfferPending => 'Место предложено другому участнику.';

  @override
  String get waitlistOfferMissing => 'Предложение места больше не действует.';

  @override
  String get waitlistOfferExpired => 'Срок предложения места истёк.';

  @override
  String get offerSection => 'Предложения места';

  @override
  String get offerTitle => 'Предложение места';

  @override
  String get offerOffered => 'Вам предложили место';

  @override
  String offerCountdown(String time) {
    return 'Предложение истекает через $time';
  }

  @override
  String get offerExpired => 'Срок предложения истёк.';

  @override
  String get offerAccept => 'Подтвердить';

  @override
  String get offerDecline => 'Отказаться';

  @override
  String get offerConfirmed =>
      'Предложение подтверждено. Заявка ждёт ответа автора.';

  @override
  String get offerDeclined => 'Вы отказались от предложения.';

  @override
  String get offerUnavailable => 'Это предложение больше не действует.';

  @override
  String get offerOpenListing => 'Открыть объявление';

  @override
  String get realtimeConnecting => 'Подключение к реальному времени…';

  @override
  String get realtimeReconnecting =>
      'Связь с реальным временем потеряна. Переподключение…';

  @override
  String get realtimeConnected => 'Реальное время подключено';

  @override
  String get realtimeOffline => 'Реальное время отключено';

  @override
  String get realtimeUpdating => 'Обновляем данные…';

  @override
  String get realtimeSessionEnded => 'Сессия завершена. Войдите снова.';

  @override
  String get realtimeChannelForbidden => 'Нет доступа к этому каналу.';

  @override
  String get realtimeChannelInvalid => 'Канал недоступен.';

  @override
  String get realtimeUnavailable =>
      'Реальное время временно недоступно. Попробуем снова.';

  @override
  String get realtimeHistoryLost =>
      'Часть событий уже недоступна — данные обновлены.';

  @override
  String get realtimeNetworkLost => 'Нет связи. Переподключение…';

  @override
  String get realtimeError =>
      'Не удалось обновить реальное время. Попробуйте позже.';

  @override
  String realtimeLastEvent(String time) {
    return 'Последнее событие: $time';
  }

  @override
  String get notificationsTitle => 'Уведомления';

  @override
  String get notificationsEmpty => 'Пока нет уведомлений';

  @override
  String get notificationsMarkAllRead => 'Отметить все прочитанными';

  @override
  String get notificationsNoScreen =>
      'Для этого уведомления в приложении пока нет экрана.';

  @override
  String get listingKindEvent => 'Мероприятие';

  @override
  String get eventCreate => 'Новое мероприятие';

  @override
  String get eventEdit => 'Редактировать мероприятие';

  @override
  String get eventStartsAt => 'Начало';

  @override
  String get eventEndsAt => 'Окончание';

  @override
  String get eventLocation => 'Место';

  @override
  String eventLocationValue(String location) {
    return 'Место: $location';
  }

  @override
  String get eventCapacity => 'Лимит мест';

  @override
  String eventSeatsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Осталось $count места',
      many: 'Осталось $count мест',
      few: 'Осталось $count места',
      one: 'Осталось $count место',
      zero: 'Мест нет',
    );
    return '$_temp0';
  }

  @override
  String get eventNoSeats => 'Мест нет';

  @override
  String get eventSignup => 'Записаться';

  @override
  String get eventRegistered => 'Вы записаны';

  @override
  String get eventQueued => 'Вы в очереди';

  @override
  String get eventJoinQueue => 'Встать в очередь';

  @override
  String get eventCancelSignup => 'Отменить запись';

  @override
  String get eventParticipants => 'Записавшиеся';

  @override
  String get eventParticipantRegistered => 'Записан';

  @override
  String get eventParticipantsEmpty => 'Пока никто не записался';

  @override
  String get eventSignupClosed => 'Запись закрыта';

  @override
  String get eventTimeInvalid =>
      'Мероприятие должно начинаться в будущем и заканчиваться после начала.';

  @override
  String eventTimeRange(String start, String end) {
    return '$start — $end';
  }

  @override
  String get eventCapacityInvalid => 'Лимит мест должен быть не меньше 1.';

  @override
  String eventCapacityBelowRegistered(int registered) {
    return 'Лимит не может быть меньше числа записавшихся: $registered.';
  }

  @override
  String get eventCapacityConflict =>
      'Нельзя уменьшить лимит мест ниже числа записавшихся.';

  @override
  String get moreActions => 'Ещё';

  @override
  String get listingKindExchange => 'Обменяю';

  @override
  String get feedCreateExchange => 'Создать «Обменяю»';

  @override
  String get exchangeCreateTitle => 'Новое объявление «Обменяю»';

  @override
  String get exchangeOfferTitle => 'Предложения';

  @override
  String get exchangeOfferFormTitle => 'Предложите свою вещь';

  @override
  String get exchangeOfferDescriptionLabel => 'Что вы предлагаете';

  @override
  String get exchangeOfferRequired => 'Опишите, что вы предлагаете.';

  @override
  String get exchangeOfferSend => 'Отправить предложение';

  @override
  String get exchangeOfferSent => 'Предложение отправлено.';

  @override
  String exchangeOfferMine(String description) {
    return 'Ваше предложение: $description';
  }

  @override
  String get exchangeOfferListEmpty => 'Предложений пока нет.';

  @override
  String get exchangeOfferAccept => 'Выбрать';

  @override
  String get exchangeOfferAccepted => 'Предложение выбрано.';

  @override
  String get exchangeOfferRejectedAnother => 'Автор выбрал другое предложение.';

  @override
  String get exchangeOfferDuplicate =>
      'Вы уже предложили вещь: дождитесь ответа автора.';

  @override
  String get exchangeOfferInvalid => 'Проверьте описание предложения.';

  @override
  String reservationTimeLeft(int hours, int minutes) {
    return 'До снятия брони: $hours ч $minutes мин';
  }

  @override
  String reservationTimeLeftMinutes(int minutes) {
    return 'До снятия брони: $minutes мин';
  }

  @override
  String get reservationTimeLeftSoon =>
      'Бронь снимается меньше чем через минуту.';

  @override
  String get reservationTimeLeftEnded => 'Срок брони истёк.';

  @override
  String get reservationMeetingHint =>
      'Назначьте встречу, чтобы сохранить бронь.';

  @override
  String reservationUntilMeeting(String time) {
    return 'Бронь продлена до встречи: $time';
  }

  @override
  String get reservationExpiredByDeadline =>
      'Бронь снята: встреча не назначена вовремя.';

  @override
  String exchangeOfferItem(String description) {
    return 'Предлагает: $description';
  }

  @override
  String get listingKindSkill => 'Навык';

  @override
  String get skillDirection => 'Направление';

  @override
  String get skillCreateTitle => 'Новое объявление о навыке';

  @override
  String get skillDirectionTeach => 'Могу научить';

  @override
  String get skillDirectionLearn => 'Хочу научиться';

  @override
  String get skillDirectionRequired =>
      'Выберите, чему вы можете научить или хотите научиться.';

  @override
  String get skillPublished => 'Объявление о навыке опубликовано.';

  @override
  String get lessonOptionsTitle => 'Варианты времени';

  @override
  String get lessonPropose => 'Предложить занятие';

  @override
  String get lessonProposeTitle => 'Время занятия';

  @override
  String get lessonRepeat => 'Ещё занятие';

  @override
  String lessonRepeatTitle(String name) {
    return 'Ещё занятие с $name';
  }

  @override
  String lessonCounterpart(String name) {
    return 'С кем: $name';
  }

  @override
  String lessonOptionsHint(int min, int max) {
    return 'Выберите от $min до $max вариантов времени.';
  }

  @override
  String lessonOptionNumber(int number) {
    return 'Вариант $number';
  }

  @override
  String get lessonAddOption => 'Добавить вариант времени';

  @override
  String get lessonRemoveOption => 'Удалить вариант';

  @override
  String lessonOptionsTooFew(int min) {
    return 'Добавьте хотя бы $min варианта времени.';
  }

  @override
  String lessonOptionsTooMany(int max) {
    return 'Можно добавить не больше $max вариантов времени.';
  }

  @override
  String lessonOptionsInvalid(int min, int max) {
    return 'У занятия должно быть от $min до $max вариантов времени в будущем.';
  }

  @override
  String get lessonConflict => 'На занятие уже ответили. Обновите объявление.';

  @override
  String get lessonForbidden =>
      'Отвечать на занятие могут только автор и участник.';

  @override
  String get lessonOnline => 'Онлайн';

  @override
  String get lessonOffline => 'Очно';

  @override
  String get lessonOnlineSwitch => 'Онлайн-встреча';

  @override
  String get lessonPlaceLabel => 'Место занятия';

  @override
  String get lessonOptionProposed => 'Ждёт ответа';

  @override
  String get lessonOptionSelected => 'Выбран';

  @override
  String get lessonOptionDeclined => 'Отклонён';

  @override
  String get lessonOptionByYou => 'Ваш вариант';

  @override
  String get lessonOptionByParticipant => 'Вариант участника';

  @override
  String get lessonOptionByAuthor => 'Вариант автора';

  @override
  String get lessonAccept => 'Выбрать это время';

  @override
  String get lessonCounter => 'Предложить другое время';

  @override
  String get lessonCounterTitle => 'Другое время';

  @override
  String get lessonSend => 'Отправить';

  @override
  String get lessonSent => 'Занятие предложено.';

  @override
  String get lessonCounterSent => 'Предложено другое время.';

  @override
  String get lessonAccepted => 'Занятие назначено.';

  @override
  String get lessonRepeated => 'Ещё одно занятие предложено.';

  @override
  String get lessonNoOptions => 'Вариантов времени нет.';

  @override
  String get lessonAwaitingAnswer => 'Ждём ответа автора';

  @override
  String get lessonAwaitingYourAnswer => 'Ждёт вашего ответа';

  @override
  String get lessonAwaitingParticipant => 'Ждём ответа участника';

  @override
  String lessonResponseDue(String time) {
    return 'Ответить нужно до $time';
  }

  @override
  String get meetingOnline => 'Онлайн-встреча';

  @override
  String get listingKindHelp => 'Помощь';

  @override
  String get feedCreateHelp => 'Попросить помощь';

  @override
  String get helpCreateTitle => 'Новый запрос о помощи';

  @override
  String get helpPublished => 'Запрос о помощи опубликован.';

  @override
  String get helpDeadline => 'Актуален до';

  @override
  String get helpDeadlinePast => 'Выберите срок в будущем.';

  @override
  String get helpDeadlineInvalid =>
      'Срок должен быть в будущем и не позже срока жизни объявления.';

  @override
  String get helpRespond => 'Откликнуться';

  @override
  String get helpResponded => 'Отклик отправлен.';

  @override
  String get helpApplicationPending => 'Отклик ждёт решения автора.';

  @override
  String get helpReserve => 'Резерв';

  @override
  String get helpReserveNotice =>
      'Исполнитель уже выбран; вы остаётесь в резерве.';

  @override
  String get helpExecutor => 'Исполнитель';

  @override
  String get helpYouAreExecutor => 'Вы исполнитель.';

  @override
  String get helpSelectExecutor => 'Выбрать исполнителя';

  @override
  String get helpSelected => 'Исполнитель выбран.';

  @override
  String get helpConflict => 'Запрос уже изменился. Обновите объявление.';

  @override
  String get helpForbidden => 'Вы не можете действовать по этому запросу.';

  @override
  String get helpIncoming => 'Отклики';

  @override
  String helpDeadlineHint(int days) {
    return 'Не позже срока жизни объявления ($days дн.).';
  }

  @override
  String helpDeadlineTooLate(int days) {
    return 'Срок не может быть больше срока жизни объявления ($days дн.).';
  }

  @override
  String helpRelevantUntil(String date) {
    return 'Актуален до $date';
  }

  @override
  String get chatsTitle => 'Диалоги';

  @override
  String get chatsEmpty => 'Диалогов пока нет. Напишите автору объявления.';

  @override
  String get chatsNoMessages => 'Сообщений пока нет';

  @override
  String get chatsUnnamed => 'Диалог';

  @override
  String get chatTitle => 'Чат';

  @override
  String get chatEmpty => 'Сообщений пока нет. Напишите первым.';

  @override
  String get chatInputHint => 'Сообщение';

  @override
  String get chatSend => 'Отправить';

  @override
  String get chatMessageEmpty => 'Введите сообщение.';

  @override
  String chatMessageTooLong(int max) {
    return 'Сообщение длиннее $max символов.';
  }

  @override
  String get chatMessageSending => 'Отправляется…';

  @override
  String get chatMessageWaiting => 'Ждёт отправки';

  @override
  String get chatMessageFailed => 'Не отправлено';

  @override
  String get chatMessageRetry => 'Повторить';

  @override
  String get chatMessageDiscard => 'Удалить';

  @override
  String get chatLoadMoreFailed => 'Не удалось загрузить ещё диалоги.';

  @override
  String get chatLoadOlderFailed =>
      'Не удалось загрузить более ранние сообщения.';

  @override
  String get chatSyncFailed => 'Не удалось обновить чат.';

  @override
  String get chatLoadOlder => 'Показать ранее';

  @override
  String get chatStart => 'Написать сообщение';

  @override
  String get chatNotFound => 'Диалог недоступен';

  @override
  String get chatForbiddenAlumni =>
      'Выпускники могут писать только в существующие диалоги.';

  @override
  String get chatFailureConflict =>
      'Это сообщение уже отправлено с другим текстом.';

  @override
  String get chatFailureInvalid => 'Сообщение не отправлено: проверьте текст.';

  @override
  String get chatFailureRateLimited =>
      'Слишком много сообщений. Попробуйте позже.';

  @override
  String get chatFailureNetwork =>
      'Нет сети. Сообщение отправится, когда связь вернётся.';

  @override
  String get chatFailureForbidden => 'Вы не можете писать в этот диалог.';

  @override
  String get chatFailureUnauthorized => 'Сессия истекла. Войдите снова.';

  @override
  String get chatFailureServer => 'Сообщение не отправлено: сервер недоступен.';

  @override
  String get chatFailureUnexpected =>
      'Сообщение не отправлено. Попробуйте ещё раз.';

  @override
  String get chatSearchTitle => 'Поиск по диалогам';

  @override
  String get chatSearchHint => 'Слово или фраза';

  @override
  String get chatSearchClear => 'Очистить поиск';

  @override
  String get chatSearchPrompt =>
      'Введите слово или фразу, чтобы найти сообщения в своих диалогах.';

  @override
  String chatSearchEmpty(String query) {
    return 'По запросу «$query» ничего не найдено.';
  }

  @override
  String get chatSearchFailed =>
      'Не удалось выполнить поиск. Попробуйте ещё раз.';

  @override
  String get chatSearchNetwork =>
      'Нет сети. Проверьте подключение и повторите поиск.';

  @override
  String get chatSearchTooLong => 'Запрос слишком длинный. Сократите его.';

  @override
  String get chatSearchLoadMore => 'Загрузить ещё';

  @override
  String get chatSearchLoadMoreFailed => 'Не удалось загрузить ещё результаты.';

  @override
  String get chatSearchMessageUnavailable =>
      'Найденное сообщение больше недоступно.';

  @override
  String get profileChats => 'Мои диалоги';

  @override
  String get listingKindPurchase => 'Совместная закупка';

  @override
  String get purchaseCreateTitle => 'Новая закупка';

  @override
  String get purchasePublished => 'Закупка опубликована.';

  @override
  String get purchasePrice => 'Цена за единицу';

  @override
  String get purchasePriceInvalid =>
      'Укажите положительную цену не более чем с двумя знаками после запятой.';

  @override
  String get purchaseMinUnits => 'Минимальный объём';

  @override
  String get purchaseMaxUnits => 'Максимальный объём';

  @override
  String get purchaseMinInvalid => 'Объём должен быть не меньше 1.';

  @override
  String purchaseMaxBelowMin(int min) {
    return 'Максимум не может быть меньше минимума ($min).';
  }

  @override
  String get purchaseCollectionDeadline => 'Сбор до';

  @override
  String get purchaseDeadlinePast => 'Выберите срок сбора в будущем.';

  @override
  String purchaseDeadlineTooLate(int days) {
    return 'Срок сбора не может быть позже $days дн.';
  }

  @override
  String get purchaseStageCollecting => 'Идёт сбор';

  @override
  String get purchaseStageFixed => 'Состав зафиксирован';

  @override
  String get purchaseStageCancelled => 'Закупка отменена';

  @override
  String purchaseUnitPriceValue(String price) {
    return 'Цена за единицу: $price';
  }

  @override
  String purchaseCollected(int taken, int limit) {
    return 'Набрано $taken из $limit ед.';
  }

  @override
  String purchaseMinimumValue(int min) {
    return 'Минимум для закупки: $min ед.';
  }

  @override
  String purchaseFixedUnitsValue(int units) {
    return 'Зафиксировано: $units ед.';
  }

  @override
  String purchaseCollectionDeadlineValue(String date) {
    return 'Сбор до $date';
  }

  @override
  String get purchaseShareTitle => 'Ваша доля';

  @override
  String purchaseShareAvailable(int available) {
    return 'Свободно: $available ед.';
  }

  @override
  String get purchaseShareInput => 'Сколько единиц';

  @override
  String purchaseShareAmount(String amount) {
    return 'Сумма: $amount';
  }

  @override
  String purchaseNewAmount(String amount) {
    return 'Новая сумма: $amount';
  }

  @override
  String get purchaseShareJoin => 'Записаться';

  @override
  String get purchaseShareJoined => 'Вы записались в закупку.';

  @override
  String get purchaseShareChange => 'Изменить долю';

  @override
  String get purchaseShareChanged => 'Доля изменена.';

  @override
  String get purchaseShareLeave => 'Выйти из закупки';

  @override
  String get purchaseShareLeft => 'Вы вышли из закупки.';

  @override
  String purchaseShareUnits(int units) {
    return 'Доля: $units ед.';
  }

  @override
  String get purchaseShareNoUnits => 'Свободных единиц не осталось.';

  @override
  String get purchaseUnitsPositive => 'Укажите хотя бы одну единицу.';

  @override
  String purchaseUnitsUnavailable(int available) {
    return 'Доступно только $available ед.';
  }

  @override
  String get purchaseLeaveApprovalRequired =>
      'После фиксации состава выход только с согласия организатора.';

  @override
  String get purchaseLeaveRequest => 'Запросить выход';

  @override
  String get purchaseLeaveRequestSent =>
      'Запрос на выход отправлен организатору.';

  @override
  String get purchaseLeaveRequestPending =>
      'Запрос на выход ждёт решения организатора.';

  @override
  String get purchaseLeaveCancel => 'Отменить запрос';

  @override
  String get purchaseLeaveRequestCancelled => 'Запрос на выход отменён.';

  @override
  String get purchaseCompositionTitle => 'Состав закупки';

  @override
  String get purchaseCompositionEmpty => 'Пока никто не записался.';

  @override
  String purchaseCompositionTotal(int units, String amount) {
    return 'Итого: $units ед. на $amount';
  }

  @override
  String get purchaseLeaveRequestedBy => 'Просит выйти';

  @override
  String get purchaseLeaveApprove => 'Разрешить выход';

  @override
  String get purchaseLeaveReject => 'Отклонить';

  @override
  String get purchaseLeaveApproved => 'Выход разрешён.';

  @override
  String get purchaseLeaveRejected => 'Запрос на выход отклонён.';

  @override
  String get purchaseShareExists => 'Вы уже участвуете в этой закупке.';

  @override
  String get purchaseVolumeInvalid => 'Проверьте цену и объёмы закупки.';

  @override
  String get purchaseDeadlineInvalid =>
      'Срок сбора должен быть в будущем и не позже срока жизни объявления.';

  @override
  String get purchaseLeaveRequestMissing => 'Запроса на выход нет.';

  @override
  String get purchaseNotFixed => 'Состав закупки ещё не зафиксирован.';

  @override
  String get purchaseCapacityConflict =>
      'Объём закупки уже изменился. Обновите карточку.';

  @override
  String get purchaseCollectionClosed => 'Сбор завершён.';

  @override
  String get purchaseManageShare => 'Доля меняется в карточке закупки.';

  @override
  String get profilePrivacy => 'Приватность';

  @override
  String get messagePolicyTitle => 'Кто может мне писать';

  @override
  String get messagePolicyIntro =>
      'Настройка действует на всех ваших устройствах.';

  @override
  String get messagePolicyAll => 'Все пользователи';

  @override
  String get messagePolicyAllHint =>
      'Любой студент или сотрудник может начать с вами личный диалог.';

  @override
  String get messagePolicyRelated => 'Только по объявлениям и взаимодействиям';

  @override
  String get messagePolicyRelatedHint =>
      'Писать могут только те, с кем у вас есть общее объявление или начатое взаимодействие.';

  @override
  String get blockedUsersTitle => 'Чёрный список';

  @override
  String get blockedUsersEmpty => 'В чёрном списке пока никого нет.';

  @override
  String blockedUsersBlockedAt(String date) {
    return 'В чёрном списке с $date';
  }

  @override
  String get blockedUsersMore => 'Загрузить ещё';

  @override
  String get blockedUsersUnblock => 'Разблокировать';

  @override
  String get chatBlock => 'Заблокировать';

  @override
  String get chatUnblock => 'Разблокировать';

  @override
  String get chatBlockTitle => 'Заблокировать пользователя?';

  @override
  String get chatBlockExplanation =>
      'Новые личные сообщения и отклики в обе стороны станут недоступны. Начатые взаимодействия и история диалога сохранятся.';

  @override
  String get chatBlockCancel => 'Отмена';

  @override
  String get chatBlocked => 'Пользователь заблокирован.';

  @override
  String get chatUnblocked => 'Пользователь разблокирован.';

  @override
  String get chatBlockedNotice =>
      'Вы заблокировали этого пользователя. Новые сообщения недоступны.';

  @override
  String get chatUnavailable =>
      'Личные сообщения с этим пользователем недоступны.';

  @override
  String get chatMessageEdited => 'изменено';

  @override
  String get chatReply => 'Ответить';

  @override
  String get chatReplyCancel => 'Отменить ответ';

  @override
  String get chatQuoteDeleted => 'Сообщение удалено';

  @override
  String get chatEdit => 'Редактировать';

  @override
  String get chatDelete => 'Удалить сообщение';

  @override
  String get chatEditTitle => 'Редактировать сообщение';

  @override
  String get chatDeleteTitle => 'Удалить сообщение?';

  @override
  String get chatDeleteExplanation =>
      'Текст исчезнет у собеседника. Скрытая копия хранится 30 дней только для жалоб.';

  @override
  String get chatCancel => 'Отмена';

  @override
  String get chatSave => 'Сохранить';

  @override
  String get chatEditFailed =>
      'Не удалось изменить сообщение. Попробуйте ещё раз.';

  @override
  String get chatDeleteFailed =>
      'Не удалось удалить сообщение. Попробуйте ещё раз.';

  @override
  String get chatMessageDeleted => 'Сообщение уже удалено.';

  @override
  String get chatMessageUnavailable => 'Сообщение больше недоступно.';

  @override
  String get chatActionForbidden => 'Действие недоступно: изменились права.';

  @override
  String get chatPhotoInvalid =>
      'Фото не обработано или устарело. Добавьте его заново.';

  @override
  String get chatPhotoExpired =>
      'Срок загрузки фото истёк. Добавьте его заново.';

  @override
  String get chatPhotoAdd => 'Прикрепить фото';

  @override
  String get chatPhotoFailed => 'Не удалось загрузить фото';

  @override
  String get chatPhotoWait => 'Дождитесь обработки фото.';

  @override
  String get chatPhotoFix => 'Уберите или повторите неудачные фото.';

  @override
  String get chatPhotosUnavailable => 'Фото недоступны.';

  @override
  String get chatYou => 'Вы';

  @override
  String get attendanceTitle => 'Отметка на мероприятии';

  @override
  String get attendanceManageAction => 'Отметка участников';

  @override
  String get attendanceOpenAction => 'Отметка на мероприятии';

  @override
  String get attendanceUnavailable => 'У этого мероприятия нет отметки.';

  @override
  String get attendanceModeTitle => 'Режим отметки';

  @override
  String get attendanceModeSelf => 'Участники отмечаются сами';

  @override
  String get attendanceModeScan => 'Организатор отмечает участников';

  @override
  String get attendanceModeSelfHint =>
      'Покажите код участникам: они введут его в приложении.';

  @override
  String get attendanceModeScanHint =>
      'Участник показывает личный код, вы отмечаете его.';

  @override
  String get attendanceModeMissing =>
      'Организатор ещё не выбрал режим отметки.';

  @override
  String attendanceWindowBefore(String time) {
    return 'Отметка откроется $time.';
  }

  @override
  String attendanceWindowOpen(String time) {
    return 'Отметка открыта до $time.';
  }

  @override
  String get attendanceWindowAfter =>
      'Отметка закрыта: мероприятие закончилось.';

  @override
  String get attendanceCodeTitle => 'Код организатора';

  @override
  String get attendanceCodeHint =>
      'Покажите этот код участникам: он обновляется автоматически.';

  @override
  String get attendanceParticipantCodeTitle => 'Ваш код';

  @override
  String get attendanceParticipantCodeHint =>
      'Покажите этот код организатору. Он обновляется автоматически.';

  @override
  String attendanceCodeExpires(int seconds) {
    return 'Код обновится через $seconds с.';
  }

  @override
  String get attendanceCodeCopy => 'Скопировать код';

  @override
  String get attendanceCodeRefresh => 'Показать новый код';

  @override
  String get attendanceCodeCopied => 'Код скопирован.';

  @override
  String get attendanceCodeRequired => 'Введите код.';

  @override
  String get attendanceOrganizerCodeLabel => 'Код организатора';

  @override
  String get attendanceParticipantCodeLabel => 'Личный код участника';

  @override
  String get attendanceSelfHint =>
      'Введите код, который показывает организатор.';

  @override
  String get attendanceScanHint => 'Введите личный код участника.';

  @override
  String get attendanceSubmitSelf => 'Отметить меня';

  @override
  String get attendanceSubmitScan => 'Отметить участника';

  @override
  String get attendanceSelfMarked => 'Вы отмечены на мероприятии.';

  @override
  String get attendanceSelfAlreadyMarked => 'Вы уже отмечены на мероприятии.';

  @override
  String attendanceScanMarked(String name) {
    return '$name: отметка поставлена.';
  }

  @override
  String attendanceScanAlreadyMarked(String name) {
    return '$name: уже отмечен.';
  }

  @override
  String get attendanceListTitle => 'Отметившиеся';

  @override
  String attendanceListCount(int count) {
    return 'Отмечено: $count';
  }

  @override
  String get attendanceListEmpty => 'Пока никто не отмечен.';

  @override
  String get attendanceRefreshList => 'Обновить список';

  @override
  String get attendanceRemoved => 'отметка снята';

  @override
  String get attendanceRemovedDone => 'Отметка снята.';

  @override
  String get attendanceRemove => 'Снять отметку';

  @override
  String get attendanceNoLongerRegistered => 'запись отменена';

  @override
  String get attendanceMethodSelf => 'Самоотметка';

  @override
  String get attendanceMethodScan => 'Сканирование';

  @override
  String get attendanceForbidden => 'Это может только организатор мероприятия.';

  @override
  String get attendanceNotRegistered =>
      'Отметиться может только записавшийся участник.';

  @override
  String get attendanceModeConflict =>
      'Мероприятие переключилось на другой режим отметки.';

  @override
  String get attendanceCodeInvalid => 'Код не подходит для этого мероприятия.';

  @override
  String get attendanceCodeExpired => 'Код устарел. Попросите показать новый.';

  @override
  String get attendanceNotFound => 'У этого участника нет отметки.';

  @override
  String get qrConfirmationTitle => 'Подтверждение встречи по QR';

  @override
  String get qrConfirmationHint =>
      'Один участник показывает код, второй сканирует его.';

  @override
  String get qrShowOpen => 'Показать QR-код';

  @override
  String get qrScanOpen => 'Сканировать QR-код';

  @override
  String get qrPresenterTitle => 'QR-код встречи';

  @override
  String get qrPresenterIntro =>
      'Покажите этот код второму участнику: он подтвердит встречу сканированием. Код обновляется автоматически.';

  @override
  String qrPresenterValidUntil(String time) {
    return 'Код действует до $time';
  }

  @override
  String get qrPresenterRefresh => 'Обновить код';

  @override
  String get qrPresenterCompleted => 'Встреча подтверждена по QR-коду.';

  @override
  String get qrPresenterAlreadyCompleted =>
      'Взаимодействие уже завершено другим способом.';

  @override
  String get qrPresenterNotAccepted =>
      'Подтвердить можно только принятое взаимодействие.';

  @override
  String get qrPresenterUnavailable =>
      'Это взаимодействие нельзя завершить по QR-коду.';

  @override
  String get qrScannerTitle => 'Сканирование QR-кода';

  @override
  String get qrScannerIntro =>
      'Наведите камеру на QR-код, который показывает второй участник.';

  @override
  String get qrScannerSending => 'Подтверждаем встречу…';

  @override
  String get qrScannerSuccess => 'Встреча подтверждена';

  @override
  String get qrScannerAlreadyConfirmed =>
      'Встреча уже подтверждена по QR-коду.';

  @override
  String get qrScannerAlreadyCompleted =>
      'Взаимодействие уже завершено другим способом.';

  @override
  String get qrScannerNotAccepted =>
      'Взаимодействие не принято и не может быть подтверждено.';

  @override
  String get qrScannerUnavailable =>
      'Это взаимодействие нельзя подтвердить по QR-коду.';

  @override
  String get qrScannerScanAgain => 'Сканировать другой код';

  @override
  String get qrScannerCameraDenied =>
      'Нет доступа к камере. Разрешите камеру в настройках приложения.';

  @override
  String get qrScannerCameraError => 'Не удалось включить камеру.';

  @override
  String get qrScannerCameraUnsupported =>
      'Сканирование камерой недоступно на этом устройстве.';

  @override
  String get qrScannerMalformed => 'Это не код подтверждения встречи.';

  @override
  String get qrScannerWrongInteraction =>
      'Код относится к другому взаимодействию.';

  @override
  String get qrScannerOwnCode =>
      'Это ваш код: покажите его второму участнику, а сканировать должен он.';

  @override
  String get qrScannerExpired =>
      'Срок действия кода истёк. Попросите показать новый.';

  @override
  String get qrScannerNotYetValid =>
      'Время кода опережает сервер. Попросите обновить код.';

  @override
  String get qrScannerBeforeAcceptance =>
      'Код сформирован до принятия взаимодействия. Попросите показать новый.';

  @override
  String get qrScannerUnknownKey =>
      'Ключ устройства не подходит. Попросите обновить код на устройстве показывающего.';

  @override
  String get qrScannerUsed =>
      'Этот код уже использован. Попросите показать новый.';

  @override
  String get qrScannerNotParticipant =>
      'Вы не участник этого взаимодействия и не можете его подтвердить.';

  @override
  String get qrScannerSameParticipant =>
      'Показывающий не может подтвердить собственный код.';

  @override
  String get qrScannerStageUnavailable =>
      'Сейчас подтверждается другой этап взаимодействия.';

  @override
  String get qrScannerAfterNoShow =>
      'Взаимодействие отмечено как несостоявшееся, этот код не подходит.';

  @override
  String get qrKeyConflict =>
      'Ключ устройства уже занят другой сессией. Попробуйте ещё раз.';

  @override
  String get qrDone => 'Готово';

  @override
  String qrCompletedAt(String time) {
    return 'Завершено $time';
  }

  @override
  String get noShowSummaryTitle => 'Встреча не состоялась';

  @override
  String get noShowSummaryHint =>
      'Отметьте, что встреча не состоялась: причина обязательна.';

  @override
  String get noShowSummaryWaiting => 'Отметка станет доступна позже.';

  @override
  String noShowOpensAt(String time) {
    return 'Отметить неявку можно с $time.';
  }

  @override
  String get noShowAction => 'Встреча не состоялась';

  @override
  String get noShowOpenResult => 'Посмотреть отметку';

  @override
  String get noShowScreenTitle => 'Встреча не состоялась';

  @override
  String get noShowIntro =>
      'Отметьте, что встреча не состоялась, если другой участник не пришёл. Причина обязательна и будет видна ему.';

  @override
  String get noShowBasisUnmarked => 'Отметок нет';

  @override
  String get noShowBasisMarked => 'Отметка участника';

  @override
  String get noShowBasisAutomatic => '«Не состоялось» по сроку';

  @override
  String get noShowBasisMutualDispute => 'Взаимные отметки: идёт спор';

  @override
  String get noShowBasisCompleted => 'Встреча состоялась';

  @override
  String noShowAt(String time) {
    return 'Отмечено: $time';
  }

  @override
  String noShowWindowOpen(String time) {
    return 'Отметить неявку можно до $time.';
  }

  @override
  String get noShowClosedMessage =>
      'Отметка неявки закрыта: взаимодействие уже перешло в «не состоялось».';

  @override
  String get noShowUnavailable =>
      'Для этого взаимодействия неявку отметить нельзя.';

  @override
  String get noShowReasonHint => 'Почему встреча не состоялась?';

  @override
  String get noShowReasonLabel => 'Причина';

  @override
  String get noShowAnswerLabel => 'Почему встреча всё-таки состоялась';

  @override
  String get noShowReasonRequired => 'Опишите причину неявки.';

  @override
  String get noShowMarkAction => 'Отметить неявку';

  @override
  String get noShowAnswerAction => 'Оспорить: встреча состоялась';

  @override
  String get noShowMarkedDone => 'Неявка отмечена.';

  @override
  String get noShowAnswerDone =>
      'Возражение записано: спор рассмотрит модератор.';

  @override
  String get noShowAlreadyMarked => 'Вы уже отметили эту встречу.';

  @override
  String get noShowNoAction => 'Сейчас вам нечего здесь сделать.';

  @override
  String get noShowDisputeOpenNotice =>
      'Оба участника отметили, что встреча не состоялась. Пока модератор не решит спор, неявки не учитываются.';

  @override
  String get noShowDisputeClosedNotice => 'Спор закрыт.';

  @override
  String get noShowLiftedAfterQr =>
      'Неявка снята: встреча подтверждена поздним QR-кодом.';

  @override
  String get noShowMarksTitle => 'Отметки';

  @override
  String get noShowMarksEmpty => 'Отметок пока нет.';

  @override
  String noShowMarkChargedTo(String name) {
    return 'Записано на: $name';
  }

  @override
  String noShowMarkBy(String name) {
    return 'Отметил: $name';
  }

  @override
  String get noShowMarkAutomatic => 'автоматическое правило';

  @override
  String get noShowMarkCounted => 'учитывается';

  @override
  String get noShowMarkDisputed => 'приостановлена спором';

  @override
  String get noShowMarkRemoved => 'снята';

  @override
  String noShowMarkReason(String reason) {
    return 'Причина: $reason';
  }

  @override
  String noShowRemovedAt(String time) {
    return 'снята $time';
  }

  @override
  String get noShowRefresh => 'Обновить';

  @override
  String get noShowChargedYou => 'вы';

  @override
  String get noShowForbidden =>
      'Неявку могут отметить только двое участников взаимодействия.';

  @override
  String get noShowTooEarly =>
      'Время встречи ещё слишком свежее: отметить неявку пока нельзя.';

  @override
  String get noShowStateConflict => 'Взаимодействие уже нельзя отметить.';

  @override
  String get noShowReasonInvalid => 'Причина пустая или слишком длинная.';

  @override
  String get eventNoShowTitle => 'Мероприятие не состоялось';

  @override
  String get eventNoShowAction => 'Мероприятие не состоялось';

  @override
  String get eventNoShowResultAction => 'Итог мероприятия';

  @override
  String get eventNoShowIntro =>
      'Записавшиеся участники решают, состоялось ли мероприятие. Если за несостоявшееся выскажется треть записей (с округлением вверх), неявку получает организатор.';

  @override
  String eventNoShowVotes(int votes, int threshold, int registered) {
    return 'Голоса: $votes из $threshold нужных · записей: $registered';
  }

  @override
  String eventNoShowVoteOpensAt(String time) {
    return 'Голосование откроется в $time.';
  }

  @override
  String eventNoShowVoteClosesAt(String time) {
    return 'Голосование идёт до $time.';
  }

  @override
  String get eventNoShowVoteWindowClosed =>
      'Голосование закрыто: прошло больше недели после мероприятия.';

  @override
  String get eventNoShowVoteAction => 'Голосовать: не состоялось';

  @override
  String get eventNoShowVoted =>
      'Вы проголосовали, что мероприятие не состоялось.';

  @override
  String get eventNoShowVotedDone => 'Голос учтён.';

  @override
  String get eventNoShowNoVote => 'Голосовать сейчас нельзя.';

  @override
  String eventNoShowOrganizerCharged(String time) {
    return 'Вам начислена неявка: $time';
  }

  @override
  String get eventNoShowOrganizerClear => 'Неявка вам не начислена.';

  @override
  String get eventNoShowDisputeAction => 'Оспорить неявку';

  @override
  String eventNoShowDisputeUntil(String time) {
    return 'Оспорить можно до $time.';
  }

  @override
  String get eventNoShowDisputeOpen =>
      'Спор у модератора: пока решение не принято, неявка не учитывается.';

  @override
  String get eventNoShowDisputeResolved => 'Спор закрыт.';

  @override
  String get eventNoShowDisputeDone => 'Спор открыт.';

  @override
  String get eventNoShowParticipantMarksTitle => 'Неявки участников';

  @override
  String get eventNoShowParticipantMarksEmpty =>
      'Никому из участников неявка не начислена.';

  @override
  String get eventNoShowParticipant => 'участник';

  @override
  String get eventNoShowModerationNote =>
      'Спор решает модератор в панели модерации; решение в приложении пока не показывается.';

  @override
  String get eventNoShowNotRegistered =>
      'Голосовать может только записавшийся участник.';

  @override
  String get eventNoShowForbidden =>
      'Итог мероприятия видят организатор и записавшиеся участники.';

  @override
  String get eventNoShowUnavailable => 'Для этого мероприятия итог недоступен.';

  @override
  String get eventNoShowVoteClosed => 'Голосование закрыто.';

  @override
  String get eventNoShowDisputeClosed => 'Спор уже закрыт.';

  @override
  String get eventNoShowDisputeForbidden =>
      'Оспорить неявку может только организатор мероприятия.';

  @override
  String get eventNoShowDisputeUnavailable =>
      'Начисленной неявки, которую можно оспорить, нет.';

  @override
  String get noShowOtherParticipant => 'другой участник';

  @override
  String get noShowAnswerHint =>
      'Если встреча всё-таки состоялась, ответьте: это взаимное возражение, спор рассмотрит модератор.';

  @override
  String get noShowLoanUnavailable =>
      'Неявку в займе нельзя отметить: вещь уже передана. После срока возврата владелец отмечает «не вернули».';

  @override
  String get listingKindLoan => 'Одолжу';

  @override
  String get loanCreateTitle => 'Создать «Одолжу»';

  @override
  String get loanPeriodLabel => 'Срок возврата, дней';

  @override
  String loanPeriodHint(int max) {
    return 'От 1 до $max дней';
  }

  @override
  String loanPeriodInvalid(int max) {
    return 'Срок возврата — от 1 до $max дней';
  }

  @override
  String loanPeriodShort(int days) {
    return '$days дн.';
  }

  @override
  String loanPeriodValue(int days) {
    return 'Срок возврата: $days дн. после выдачи';
  }

  @override
  String loanPeriodFixed(int days) {
    return 'Срок возврата задан при публикации: $days дн.';
  }

  @override
  String get loanCardTitle => '«Одолжу»';

  @override
  String get loanStepAccepted => 'Принято';

  @override
  String get loanStepIssued => 'Выдано';

  @override
  String get loanStepReturned => 'Возвращено';

  @override
  String loanReturnDue(String time) {
    return 'Вернуть до $time';
  }

  @override
  String get loanOverdueChip => 'Просрочено';

  @override
  String get loanShowHandover => 'Показать QR выдачи';

  @override
  String get loanScanHandover => 'Сканировать QR выдачи';

  @override
  String get loanShowReturn => 'Показать QR возврата';

  @override
  String get loanScanReturn => 'Сканировать QR возврата';

  @override
  String get loanHandoverHint =>
      'Владелец показывает код выдачи, заёмщик сканирует.';

  @override
  String get loanReturnHint =>
      'Заёмщик показывает код возврата, владелец сканирует.';

  @override
  String get loanNotReturned => 'Вещь не возвращена';

  @override
  String loanNotReturnedUntil(String time) {
    return 'Доступно с $time';
  }

  @override
  String get loanNotReturnedConfirmTitle => 'Отметить «не возвращено»?';

  @override
  String get loanNotReturnedConfirmBody =>
      'Заёмщику будет засчитана неявка, и он сможет её оспорить. Вещь остаётся занятой, пока спор не решится.';

  @override
  String get loanNotReturnedConfirm => 'Отметить';

  @override
  String get loanNotReturnedKeep => 'Отмена';

  @override
  String get loanNotReturnedMarked =>
      'Владелец отметил, что вещь не возвращена.';

  @override
  String get loanBorrowerNoShow =>
      'Заёмщик не вернул вещь в срок: засчитана неявка.';

  @override
  String get loanDisputeOpen => 'Неявка оспорена: решение примет модератор.';

  @override
  String get loanDisputeWaiting =>
      'Заёмщик может оспорить неявку в течение окна спора.';

  @override
  String get loanDispute => 'Оспорить неявку';

  @override
  String get loanDisputeTitle => 'Оспаривание неявки';

  @override
  String get loanDisputeReason => 'Причина';

  @override
  String get loanDisputeReasonRequired => 'Опишите причину';

  @override
  String loanDisputeReasonInvalid(int max) {
    return 'Причина — не длиннее $max символов';
  }

  @override
  String get loanDisputeSend => 'Отправить';

  @override
  String get loanDisputeKeep => 'Отмена';

  @override
  String get loanDisputeClosed => 'Окно оспаривания уже закрыто.';

  @override
  String get loanDisputeForbidden =>
      'Оспорить неявку может только её участник.';

  @override
  String get loanNoShowUnavailable => 'Оспорить эту неявку нельзя.';

  @override
  String get loanQrAlreadyReturned => 'Вещь уже возвращена.';

  @override
  String get loanQrHandoverUnavailable =>
      'Выдача уже подтверждена или заём закрыт.';

  @override
  String get loanQrReturnUnavailable => 'Возврат возможен только после выдачи.';

  @override
  String loanNotReturnedTooEarly(String time) {
    return 'Отметить «не возвращено» можно с $time.';
  }

  @override
  String get loanNotReturnedLater => 'Отметить «не возвращено» пока нельзя.';

  @override
  String get loanNotReturnedForbidden =>
      'Отметить «не возвращено» может только владелец.';

  @override
  String get loanNotReturnedUnavailable =>
      'Отметить «не возвращено» можно только для выданной вещи.';

  @override
  String loanReturnedAt(String time) {
    return 'Возвращено $time';
  }

  @override
  String get loanQrHandoverPresenterTitle => 'QR-код выдачи';

  @override
  String get loanQrHandoverPresenterIntro =>
      'Покажите этот код заёмщику: он подтвердит получение вещи.';

  @override
  String get loanQrReturnPresenterTitle => 'QR-код возврата';

  @override
  String get loanQrReturnPresenterIntro =>
      'Покажите этот код владельцу: он подтвердит возврат вещи.';

  @override
  String get loanQrHandoverScanTitle => 'Сканирование выдачи';

  @override
  String get loanQrHandoverScanIntro =>
      'Наведите камеру на QR-код, который показывает владелец.';

  @override
  String get loanQrReturnScanTitle => 'Сканирование возврата';

  @override
  String get loanQrReturnScanIntro =>
      'Наведите камеру на QR-код, который показывает заёмщик.';

  @override
  String get loanQrHandoverDone => 'Выдача подтверждена.';

  @override
  String get loanQrReturnDone => 'Возврат подтверждён, заём завершён.';

  @override
  String get qrScannerLoanNotHandedOver => 'Сначала подтвердите выдачу вещи.';

  @override
  String get qrScannerLoanAlreadyIssued =>
      'Выдача уже подтверждена. Для возврата покажите или отсканируйте код возврата.';

  @override
  String get qrScannerLoanReturnMarked =>
      'Владелец отметил вещь не возвращённой; исход решит спор.';

  @override
  String get qrScannerLoanActionRequired =>
      'Займ подтверждается отдельно выдачей и возвратом.';

  @override
  String get timelineLoanHandedOver => 'Выдача вещи подтверждена';

  @override
  String get timelineLoanReturned => 'Возврат вещи подтверждён';

  @override
  String get timelineLoanNotReturned => 'Вещь отмечена не возвращённой';

  @override
  String get settingsPalette => 'Палитра';

  @override
  String get paletteLavender => 'Лаванда';

  @override
  String get paletteSage => 'Шалфей';

  @override
  String get paletteSky => 'Небо';

  @override
  String get palettePeach => 'Персик';
}
