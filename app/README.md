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
`test/drift/*/generated/`) хранится в репозитории и руками не правится.
После изменения провайдеров или таблиц:

```sh
dart run build_runner build
```

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
