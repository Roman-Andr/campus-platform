# Кампус

Сервис взаимодействия студентов вуза — закрытое сообщество для обмена
вещами и навыками, мероприятий, совместных закупок и взаимопомощи.
Курсовой проект.

## Документы

- Техническое задание — [`docs/paperwork/ТЗ/`](docs/paperwork/ТЗ/),
  собранный PDF — [`docs/paperwork/pdf/`](docs/paperwork/pdf/).
  Функции — п. 5.1.1, стек — п. 5.5.2, этапы — §8, приёмка — §9.
- Видение и принятые решения — [`docs/vision.md`](docs/vision.md).
- План работ — [Roadmap (#1)](https://github.com/Roman-Andr/campus-platform/issues/1):
  срезы — milestones, задачи — issues.
- Правила работы над задачами — [`CLAUDE.md`](CLAUDE.md).

## Структура

| Каталог    | Содержимое                                                   |
|------------|--------------------------------------------------------------|
| `backend/` | API, воркер и планировщик (Python, FastAPI, Taskiq)          |
| `app/`     | Клиент студента на Flutter (Android, веб, десктоп, Mini App) |
| `admin/`   | Веб-панель администратора (React, react-admin)               |
| `infra/`   | Docker Compose, Caddy, резервное копирование, мониторинг     |
| `docs/`    | Документы проекта и ЕСПД (Typst, `docs/paperwork/`)          |

Каталоги приложений появляются по мере выполнения задач среза 0.

## Подготовка рабочей копии

Общие проверки (пробелы, концы файлов, крупные файлы, конфликты
слияния, синтаксис YAML/TOML/JSON) выполняет
[pre-commit](https://pre-commit.com):

```sh
uv tool install pre-commit   # или pipx install pre-commit
pre-commit install
pre-commit run --all-files
```

Форматирование для редакторов задаёт `.editorconfig`, окончания строк —
`.gitattributes` (LF).

Веб-панель администратора — см. [`admin/README.md`](admin/README.md);
хуки pre-commit для `admin/` требуют `npm ci` в этом каталоге.

Сборка документов — `make compile` в `docs/paperwork/` (нужен
[Typst](https://typst.app)); в репозитории хранится только PDF ТЗ.

Сервер: запуск, проверки и устройство — [`backend/README.md`](backend/README.md).

Все серверные компоненты в Docker Compose (API, PostgreSQL, Redis,
Centrifugo, RustFS, Caddy) — [`infra/README.md`](infra/README.md).
