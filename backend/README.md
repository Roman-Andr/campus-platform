# Сервер «Кампуса»

Модульный монолит на Python 3.14 и FastAPI (ТЗ, п. 4.1 и 5.5.2): одна
кодовая база, три процесса — API, воркер и планировщик.

## Быстрый старт

Нужен [uv](https://docs.astral.sh/uv/); нужную версию Python он ставит сам.

```sh
cd backend
uv sync                      # окружение и зависимости из uv.lock
cp .env.example .env         # по желанию: локальные настройки
uv run campus-api            # http://127.0.0.1:8000/api/v1/docs
```

Образ сервера — `Dockerfile`; запуск вместе с базой данных и остальными
сервисами в Docker Compose — [`infra/README.md`](../infra/README.md).

Начальные данные стенда (справочники вуза: кампусы НИУ ВШЭ, общежития,
факультеты, почтовые домены) загружает команда `uv run campus-seed`
после миграций. Повторный запуск добавляет только недостающие строки и не
меняет отредактированные; свой файл справочников —
`campus-seed --university FILE.toml` (формат — `src/campus/modules/university/seed.toml`).

Воркер и планировщик — `uv run campus-worker` и `uv run campus-scheduler`
(пока заглушки: пишут в журнал о запуске и ждут сигнала остановки).

## Проверки

```sh
uv run pytest                # тесты и отчёт покрытия (терминал и coverage.xml)
uv run ruff check .          # линтер
uv run ruff format .         # форматтер
uv run mypy                  # типы, строгий режим
uv run lint-imports          # границы модулей
```

Те же проверки запускает pre-commit из корня репозитория.

Тесты с базой данных поднимают PostgreSQL 18 с pgvector
(`pgvector/pgvector:0.8.7-pg18-trixie`) через testcontainers, поэтому нужен Docker.
С podman вместо Docker:

```sh
systemctl --user start podman.socket       # rootless; от root — без --user
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock TESTCONTAINERS_RYUK_DISABLED=true
```

Вместо контейнера можно указать готовый сервер:
`CAMPUS_TEST_DATABASE_URL=postgresql://user:password@host:5432/postgres`
(пользователю нужно право создавать базы данных).

## База данных и миграции

PostgreSQL 18 с pgvector, асинхронный SQLAlchemy 2 (asyncpg). Адрес —
`CAMPUS_DATABASE_URL` в формате
`postgresql+asyncpg://USER:PASSWORD@HOST:PORT/DATABASE`; адрес
`postgresql://…` переводится на драйвер asyncpg автоматически.

Схема меняется только миграциями Alembic (ТЗ, п. 4.4). Команды — из
каталога `backend/` (настройки в `[tool.alembic]` файла `pyproject.toml`,
сами миграции — в пакете, `src/campus/migrations/`):

```sh
uv run alembic upgrade head                           # применить миграции
uv run alembic revision --autogenerate -m "add listings"  # новая миграция
uv run alembic check                                  # модели = миграции?
uv run alembic downgrade -1                           # откатить последнюю
```

Автогенерированную миграцию нужно прочитать и поправить. Таблицы модуль
объявляет в своих моделях и импортирует их в `__init__.py` модуля — так
их видит автогенерация.

Модели наследуют `campus.core.db.Entity`:

- `id` — UUIDv7, генерирует PostgreSQL (`uuidv7()`);
- `created_at`, `updated_at` — `timestamptz`, значения берутся из часов
  приложения;
- имена ограничений задаёт соглашение (`pk_<таблица>`, `fk_…`, `uq_…`,
  `ix_…`, `ck_…`).

Справочники с названиями на русском и английском добавляют примесь
`campus.core.db.LocalizedName` (`name_ru`, `name_en`, `name_in(locale)`);
API отдаёт название на языке запроса (`request_locale(request)`).

### Время

Текущее время код берёт только из `campus.core.clock.now()` (UTC, с
часовым поясом). Прямые вызовы `datetime.now()`, `date.today()`,
`time.time()` запрещены правилом ruff. В тестах время управляется
[time-machine](https://github.com/adamchainz/time-machine), пример —
`tests/test_entity.py`. Функцию `now()` из SQL для бизнес-правил не
используйте: время передаётся параметром запроса.

### Тесты с базой данных

Фикстуры — в `tests/database.py`. Миграции один раз применяются к
шаблонной базе, затем каждый тест получает собственную копию шаблона.
Поэтому тест может делать коммиты и параллельные транзакции, не влияя на
другие тесты.

- `session` — сессия на базе теста; через неё создают строки фабрики
  (`tests/factories.py`, polyfactory): `await NoteFactory.create_async()`;
- `engine` — движок базы теста, например для параллельных сессий;
- `database_url` — адрес базы теста.

## Устройство

| Пакет               | Назначение                                              |
|---------------------|---------------------------------------------------------|
| `campus.api`        | Процесс API: сборка приложения, health, журнал запросов |
| `campus.worker`     | Процесс воркера                                         |
| `campus.scheduler`  | Процесс планировщика                                    |
| `campus.migrations` | Миграции Alembic                                        |
| `campus.seed`       | Команда `campus-seed`: начальные данные стенда          |
| `campus.modules.*`  | Доменные модули (ТЗ, п. 4.1)                            |
| `campus.core`       | Общее ядро: конфигурация, БД, часы, журналы, Sentry     |
| `campus.core.web`   | Общие механизмы HTTP API (см. ниже)                     |
| `campus.locales`    | Каталоги переводов сообщений (gettext)                  |

Доменные модули: `identity` (аутентификация и пользователи), `university`
(структура вуза), `listings` (объявления и взаимодействия), `reputation`
(подтверждение встреч и репутация), `points` (баллы), `booking`
(бронирование ресурсов), `chat`, `publications` (форум, страницы, лента),
`moderation`, `notifications`, `ai`, `administration`.

Границы проверяет import-linter (контракты — в `pyproject.toml`):

- процессы зависят от модулей, модули — от `campus.core`, не наоборот;
- публичный интерфейс модуля — его пакет (`__init__.py`); подмодули —
  внутренние, другие модули и процессы их не импортируют.

## Соглашения API

Общие механизмы (ТЗ, п. 4.3 и 4.6) — в `campus.core.web`; пример
использования — тестовый роутер `tests/web_app.py`.

- **Роутер модуля** — `api_router(prefix=...)`. Его маршруты (`ApiRoute`)
  до проверки параметров требуют заголовки `X-Client-Platform`
  (`android|web|desktop|telegram|admin`) и `X-Client-Version`. Без них —
  `400 client_version_missing`; версия старее минимальной для платформы
  (`CAMPUS_CLIENT_MIN_VERSIONS`) — `426 client_update_required` с полем
  `min_version`. Health и документация от проверки освобождены.
- **Транзакция запроса.** Эндпоинт получает сессию зависимостью
  `DbSession` и сам не коммитит: ответ 2xx фиксируется, исключение или
  другой код — откатывают всё.
- **Идемпотентность.** POST, PUT, PATCH и DELETE требуют
  `Idempotency-Key` (UUID). Ключ занимается в транзакции запроса и
  сохраняется вместе с ответом на `CAMPUS_IDEMPOTENCY_KEY_TTL` (24 ч).
  Повтор, в том числе параллельный, получает сохранённый ответ с
  заголовком `Idempotent-Replayed: true`; тот же ключ с другим запросом —
  `422 idempotency_key_reused`. Просроченные ключи удаляет
  `delete_expired_idempotency_keys` (периодический запуск — задача
  планировщика).
- **Ошибки** — Problem Details (`application/problem+json`): `type`,
  `title`, `status`, `detail`, машинный `code`, `request_id`; у ошибок
  проверки — `errors[]` с `pointer` (`#/поле` тела), `parameter` или
  `header`. Свои ошибки модуль объявляет как
  `ProblemType("code", status, N_("Title"), N_("Detail {param}"))` и
  бросает `ProblemError(тип, param=...)`. Необработанное исключение —
  `500 internal_error` без подробностей.
- **Списки** — курсорная пагинация: зависимость `PageQuery`
  (`?size=&cursor=`; `CAMPUS_PAGE_SIZE_DEFAULT`/`_MAX`), параметр
  `order_by: Literal[...]` эндпоинта, `sort_by(...)` с уникальным `id`
  для однозначного порядка и `paginate(...)` → `{items, next_page}`.
  Курсор хранит ключ сортировки последней записи, поэтому вставки и
  удаления во время прокрутки не теряют и не дублируют записи.

### Переводы сообщений

Тексты для пользователя пишутся по-английски и помечаются `N_("...")`;
переводятся при отрисовке на язык из `Accept-Language` (по умолчанию —
`CAMPUS_DEFAULT_LOCALE`, `ru`). После изменения текстов:

```sh
uv run pybabel extract --no-location --sort-output --omit-header \
  -o src/campus/locales/messages.pot src/campus
uv run pybabel update -i src/campus/locales/messages.pot -d src/campus/locales
# перевести новые строки в src/campus/locales/ru/LC_MESSAGES/messages.po
```

Тест `tests/test_i18n.py` проверяет, что шаблон актуален, а перевод
полный. Файлы `.mo` не нужны: `.po` компилируются в память при запуске.

## Конфигурация

Все параметры читаются из переменных окружения с префиксом `CAMPUS_`;
файл `.env` в рабочем каталоге — запасной источник, он не коммитится.
Полный список с пояснениями — `.env.example`. Пустое значение означает
значение по умолчанию.

## Журналы и ошибки

Журналы — JSON в stdout, по записи на строку, с полями `process` и
`request_id`. Персональные данные в журнал не попадают:

- значения полей с именами вроде `email`, `phone`, `first_name`, `token`
  заменяются на `[redacted]`, адреса почты маскируются в любом тексте;
- журнал запросов пишет метод, путь без строки запроса, код и
  длительность — без адреса клиента и заголовков;
- трассировки исключений — без значений локальных переменных.

Имена и другие персональные данные в свободном тексте автоматически не
распознаются: передавайте их только именованными полями.

Ошибки уходят в Sentry (сервер сбора — GlitchTip), если задан
`CAMPUS_SENTRY_DSN`; без DSN отправка выключена. Сбор данных о
пользователе, заголовков, тел запросов и локальных переменных отключён.
