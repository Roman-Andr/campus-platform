# Кампус — клиент студента

Flutter-приложение для Android, веба, Windows, macOS и Linux (ТЗ
п. 5.1.5, 5.5.2). Основная цель среза 0 — Android 8.0 (API 26) и новее.

## Требования

- Flutter stable 3.50+ (Dart 3.14+), для Android — Android SDK
  (platform 36, build-tools, NDK из `flutter doctor`) и JDK 17+.
- Для десктопа — инструменты сборки платформы, см. `flutter doctor`.

## Запуск

```sh
cd app
flutter pub get
flutter run                     # выбрать устройство: Android, Linux, Chrome…
flutter build apk --debug       # APK: build/app/outputs/flutter-apk/
```

Адрес сервера и другие параметры клиента API задаются при сборке через
`--dart-define` (`lib/src/core/api/api_config.dart`):

| Параметр                     | По умолчанию                       |
|------------------------------|------------------------------------|
| `CAMPUS_API_URL`             | `http://localhost:8000`            |
| `CAMPUS_DOWNLOAD_URL`        | страница последнего релиза GitHub  |
| `CAMPUS_API_CONNECT_TIMEOUT` | 10 (секунд)                        |
| `CAMPUS_API_RECEIVE_TIMEOUT` | 30 (секунд)                        |
| `CAMPUS_API_RETRIES`         | 3 (паузы 1, 2, 4 с…)               |

Эмулятор Android видит компьютер по адресу `10.0.2.2`:

```sh
flutter run --dart-define=CAMPUS_API_URL=http://10.0.2.2:8000
```

## Проверки

```sh
dart format .                   # форматирование
flutter analyze                 # flutter_lints + строгие проверки типов
flutter test                    # unit- и widget-тесты, тест миграций БД
```

Хуки pre-commit (`dart format`, `flutter analyze`) подключаются из
корня репозитория: `pre-commit install`.

## Устройство

```
lib/
  main.dart                     загрузка настроек и запуск
  l10n/app_{ru,en}.arb          все тексты интерфейса
  src/
    app.dart                    MaterialApp: маршруты, локализация, тема
    core/                       общее: database/, router/, theme/, l10n/
    features/<фича>/            domain/, data/, application/, presentation/
```

- Состояние и зависимости — Riverpod (провайдеры через
  `riverpod_generator`), навигация — `go_router` (`AppRoutes`).
- Тема — Material 3, светлая и тёмная из одного цвета (`AppTheme`).
- Язык и тема выбираются в настройках («Как в системе», RU, EN) и
  хранятся в локальной БД. Для языка устройства, отличного от RU и EN,
  интерфейс показывается на английском.

## Локализация

Тексты интерфейса — только в `lib/l10n/app_ru.arb` (шаблон, с
описаниями) и `app_en.arb`; в коде — `context.l10n.<ключ>`. После
правки ARB:

```sh
flutter gen-l10n
```

Тест `test/l10n/localization_test.dart` не пропускает строки
интерфейса в коде (аргументы `Text`, `tooltip:`, `label:` и т. п., любая
кириллица) и проверяет, что в RU и EN одинаковый набор ключей.

## Генерация кода

Сгенерированный код (`*.g.dart`, `lib/src/core/l10n/generated/`,
`lib/src/core/api/generated/`, `test/drift/*/generated/`) хранится в репозитории и руками не правится.
После изменения провайдеров или таблиц:

```sh
dart run build_runner build
```

## Клиент API

Клиент генерируется из схемы OpenAPI сервера
([swagger_parser](https://pub.dev/packages/swagger_parser): клиент на
Dio, модели без сторонних сериализаторов) одной командой из `app/`:

```sh
tool/generate_api.sh            # после изменения API сервера
tool/generate_api.sh --check    # схема и клиент актуальны?
```

Команда берёт схему из приложения FastAPI (`backend/`, нужен
[uv](https://docs.astral.sh/uv/)), а не с запущенного сервера, сохраняет
её в `openapi/openapi.json` (`tool/export_openapi.py` переписывает
`anyOf: [T, null]` FastAPI в `T | null`, который понимает генератор) и
генерирует `lib/src/core/api/generated/` (настройки —
`swagger_parser.yaml`). Сгенерированный код руками не правится.
CI запускает `tool/generate_api.sh --check` при изменениях клиента или
сервера, чтобы схема и клиент оставались согласованы.

Запросы идут через общий `Dio` (`apiDioProvider`, клиент —
`campusApiProvider`), его перехватчики (`lib/src/core/api/`):

- добавляют `X-Client-Platform`, `X-Client-Version` (из `pubspec.yaml`)
  и `Accept-Language` к каждому запросу — в генерированных методах этих
  параметров нет;
- дают каждому изменяющему запросу (POST, PUT, PATCH, DELETE)
  `Idempotency-Key` — UUIDv7. Ключ хранится в параметрах запроса, поэтому
  повтор после обрыва связи или тайм-аута
  ([dio_smart_retry](https://pub.dev/packages/dio_smart_retry)) идёт с
  тем же ключом и сервер выполняет операцию один раз. Ключ, переданный
  вызывающим кодом, сохраняется;
- отмечают офлайн-состояние (полоса «Нет подключения к сети» над
  экраном; источник — также
  [connectivity_plus](https://pub.dev/packages/connectivity_plus)) и
  ответ `426 client_update_required` — после него доступен только экран
  «Требуется обновление» со ссылкой на загрузку.

Ошибки запросов разбираются в `ApiFailure.from(error)`: `NetworkFailure`,
`ProblemFailure` (Problem Details с `code` и `fieldErrors`),
`UpdateRequiredFailure`, `UnexpectedFailure`. Пользователю показывается
текст из ARB (`apiFailureMessage`, виджет `ApiErrorView`) — не `title` и
`detail` сервера и без технических подробностей; новые коды ошибок
сервера не ломают старый клиент.

## Локальная БД (Drift)

SQLite через Drift (`lib/src/core/database/`); в вебе — WebAssembly
(`web/sqlite3.wasm`, `web/drift_worker.js`; после обновления `drift` или
`sqlite3` — `tool/update_drift_web_assets.sh`).

Изменение схемы:

1. Изменить таблицы и увеличить `AppDatabase.schemaVersion`.
2. `dart run build_runner build`
3. `dart run drift_dev make-migrations` — сохраняет схему новой версии в
   `drift_schemas/`, генерирует `app_database.steps.dart` и тестовые
   схемы.
4. Описать шаг в `AppDatabase.migration` (`onUpgrade: stepByStep(...)`).
5. `flutter test test/drift` — проверяет, что новая установка создаёт
   выгруженную схему и что каждая версия обновляется до каждой
   следующей.

## Иконка

Заглушка — `assets/icon/`. Иконки платформ генерируются командой
`dart run flutter_launcher_icons` (настройки — в `pubspec.yaml`).
