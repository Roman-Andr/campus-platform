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

`pre-commit install` ставит и хук pre-push: он не даёт отправить
коммиты прямо в `main` — изменения попадают туда только через PR.

Форматирование для редакторов задаёт `.editorconfig`, окончания строк —
`.gitattributes` (LF).

Веб-панель администратора — см. [`admin/README.md`](admin/README.md);
хуки pre-commit для `admin/` требуют `npm ci` в этом каталоге.

Сборка документов — `make compile` в `docs/paperwork/` (нужен
[Typst](https://typst.app)); в репозитории хранится только PDF ТЗ.

Сервер: запуск, проверки и устройство — [`backend/README.md`](backend/README.md).

Все серверные компоненты в Docker Compose (API, PostgreSQL, Redis,
Centrifugo, RustFS, Caddy) — [`infra/README.md`](infra/README.md).

Клиент студента: запуск, проверки и устройство — [`app/README.md`](app/README.md).

## CI и защита `main`

GitHub Actions (`.github/workflows/`):

- `ci.yml` — проверки по слоям; задача слоя запускается, только если
  в PR менялись его файлы (или сам `ci.yml`), на тегах `v*` — все:
  - сервер — ruff, mypy, import-linter, pytest с PostgreSQL
    (testcontainers; в наборе — `alembic check`), покрытие доменных
    модулей (`campus.modules`) не ниже 80 %, сборка образа; из `main` и
    тегов образ публикуется в GHCR (`ghcr.io/roman-andr/campus-backend`);
  - клиент — `dart format`, `flutter analyze`, актуальность
    сгенерированного кода (gen-l10n, build_runner, drift), `flutter
    test`, сборка APK (артефакт `campus-apk`);
  - веб-панель — Prettier, ESLint, типы, Vitest с покрытием, сборка,
    Playwright;
  - инфраструктура — `docker compose config`, `caddy validate`;
  - общие хуки pre-commit.

  Итог — задача `ci`: пропущенные по фильтру задачи считаются
  пройденными, упавшие — нет.
- `pr-title.yml` — проверка `pr-title`: заголовок PR по Conventional
  Commits, со строчной буквы, до 50 символов.
- `main-guard.yml` — после каждого push в `main` проверяет, что каждый
  новый коммит — squash-мерж PR с зелёными `ci` и `pr-title` и что push
  не принудительный; иначе падает и заводит issue с меткой `bug`.

Обязательные проверки — `ci` и `pr-title`. Репозиторий приватный, без
GitHub Pro rulesets и branch protection недоступны (API отвечает 403),
поэтому до их появления действует замена:

1. PR сливается только скриптом, который проверяет `ci` и `pr-title` на
   последнем коммите PR и сливает именно его:
   `.github/scripts/merge-pr.sh <номер PR>`;
2. хук pre-push отклоняет push в `main` (обходится `--no-verify` — такой
   push ловит `main-guard.yml`);
3. `main-guard.yml` сообщает о любом изменении `main` в обход п. 1.

Когда rulesets станут доступны (GitHub Pro или публичный репозиторий),
правило для `main` включается одной командой — PR обязателен, только
squash, обязательные `ci` и `pr-title`, без force push и удаления:

```sh
gh api -X POST repos/Roman-Andr/campus-platform/rulesets \
  --input .github/rulesets/main.json
```

<!-- ruleset guard test -->
