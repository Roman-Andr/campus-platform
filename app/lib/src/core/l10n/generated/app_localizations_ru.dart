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
}
