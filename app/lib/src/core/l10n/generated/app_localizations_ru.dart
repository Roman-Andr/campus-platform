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
}
