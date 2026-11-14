# Сервер «Кампуса»

Модульный монолит на Python 3.14 и FastAPI (ТЗ, п. 4.1 и 5.5.2): одна
кодовая база, три процесса — API, воркер и планировщик.

## Быстрый старт

Нужен [uv](https://docs.astral.sh/uv/); нужную версию Python он ставит сам.

```sh
cd backend
uv sync                      # окружение и зависимости из uv.lock
cp .env.example .env         # локальные настройки с ключом разработки
uv run campus-api            # http://127.0.0.1:8000/api/v1/docs
```

Образ сервера — `Dockerfile`; запуск вместе с базой данных и остальными
сервисами в Docker Compose — [`infra/README.md`](../infra/README.md).

Начальные данные стенда (справочники вуза: кампусы НИУ ВШЭ, общежития,
факультеты, почтовые домены) загружает команда `uv run campus-seed`
после миграций. Повторный запуск добавляет только недостающие строки и не
меняет отредактированные; свой файл справочников —
`campus-seed --university FILE.toml` (формат — `src/campus/modules/university/seed.toml`).

Воркер и планировщик — `uv run campus-worker` и `uv run campus-scheduler`;
им нужны PostgreSQL и Redis (`CAMPUS_DATABASE_URL`, `CAMPUS_REDIS_URL`),
проще всего — из Docker Compose (см. «Фоновые задачи»).

## Проверки

```sh
uv run pytest                # тесты и отчёт покрытия (терминал и coverage.xml)
uv run coverage report --include='src/campus/modules/*' --fail-under=80  # порог CI
uv run ruff check .          # линтер
uv run ruff format .         # форматтер
uv run mypy                  # типы, строгий режим
uv run lint-imports          # границы модулей
```

Те же проверки запускает pre-commit из корня репозитория.

Тесты с базой данных поднимают PostgreSQL 18 с pgvector
(`pgvector/pgvector:0.8.7-pg18-trixie`) через testcontainers, поэтому нужен Docker.
Тесты воркера, планировщика и почты так же поднимают Redis и Mailpit
(`tests/services.py`). Интеграционные тесты реального времени поднимают
Centrifugo (`tests/test_realtime_integration.py`), остальные тесты
Centrifugo подменяют.
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

## Фоновые задачи

Побочные эффекты и события по сроку (ТЗ, п. 4.3 и 5.2) хранятся в БД и
выполняются фоновыми процессами; общая часть — `campus.core.jobs`.

- **Outbox** (`campus.core.outbox`). Модуль пишет сообщение
  `add_message(session, topic, payload)` в той же транзакции, что и
  изменение: откат не оставляет сообщения. Воркер раз в
  `CAMPUS_OUTBOX_POLL_INTERVAL` секунд выбирает готовые сообщения и
  вызывает обработчик темы, зарегистрированный декоратором
  `@outbox_handlers.register("module.action")`. Тема — одно действие
  одного потребителя; событию с несколькими потребителями — несколько
  сообщений.
- **Сроки** (`campus.core.deadlines`). `schedule_deadline(session, topic,
  due_at, payload, key=...)` записывает срок; срок с тем же `key`
  переносится, `cancel_deadline(session, key)` отменяет его. Обработчики —
  `@deadline_handlers.register(...)`. Планировщик раз в минуту
  (`CAMPUS_DEADLINES_CRON`) и сразу при запуске ставит задачу обработки
  наступивших сроков, поэтому сроки, пропущенные за время простоя,
  обрабатываются после запуска.
- **Гарантии.** Строка захватывается `SELECT … FOR UPDATE SKIP LOCKED`,
  обработчик выполняется в той же транзакции, что и отметка
  `processed_at`, поэтому несколько воркеров и планировщиков не
  выполняют одно задание дважды, а изменения обработчика в БД
  применяются ровно один раз. Ошибка откатывает изменения обработчика;
  повтор — через `CAMPUS_JOB_RETRY_BASE_DELAY` с удвоением до
  `CAMPUS_JOB_RETRY_MAX_DELAY`, после `CAMPUS_JOB_MAX_ATTEMPTS` попыток
  задание помечается `failed_at`. Внешний эффект (письмо, push) может
  повториться, если он прошёл, а фиксация — нет: для защиты обработчик
  получает постоянный `job.id` (у писем он входит в `Message-ID`).
- **Очистка.** По расписанию `CAMPUS_CLEANUP_CRON` удаляются завершённые
  записи старше `CAMPUS_OUTBOX_RETENTION` и `CAMPUS_DEADLINE_RETENTION` и
  просроченные ключи идемпотентности. Модуль добавляет правила хранения
  своих таблиц декоратором `campus.core.tasks.register_cleanup(name)`:
  функция `(sessions, settings) -> {вид: удалено}` должна быть
  идемпотентной, счётчики пишутся в лог `expired_records_deleted`.
- **Очередь задач** (`campus.core.tasks`) — Taskiq с брокером Redis
  Streams (подтверждение доставки). Модули объявляют свои задачи
  декоратором `campus.core.tasks.task`.
- **Остановка воркера.** По SIGTERM воркер перестаёт брать новые задачи и
  сообщения outbox и ждёт выполняющиеся до
  `CAMPUS_WORKER_SHUTDOWN_TIMEOUT` (20 с, меньше `stop_grace_period`
  контейнера); оставшиеся отменяются — их транзакция откатывается, и
  задание повторится. Соединения с БД и Redis закрываются после этого,
  поэтому после `worker_stopped` задачи к ним не обращаются.
- **Почта** (`campus.core.mail`). `queue_email(session, to=..., subject=...,
  text=..., html=...)` ставит письмо в outbox, воркер отправляет его по
  SMTP (`CAMPUS_SMTP_*`). В разработке письма ловит Mailpit:
  `CAMPUS_SMTP_HOST=127.0.0.1`, `CAMPUS_SMTP_PORT=1025`,
  `CAMPUS_SMTP_SECURITY=none`, веб-интерфейс — <http://127.0.0.1:8025>.

Обработчики модулей регистрируются при импорте модуля; воркер
импортирует все модули при запуске.

## Реальное время (Centrifugo)

Клиент подключается к Centrifugo напрямую (WebSocket), а API выдаёт ему
подписанные токены и отдаёт пропущенные публикации. Публичные транспорты
Centrifugo наружу открывает Caddy (`infra/README.md`), серверный HTTP API
доступен только бэкенду.

- **Токены.** `POST /api/v1/realtime/connection-token` — токен соединения
  устройства (`sub` — пользователь, `sid` — сессия устройства).
  `POST /api/v1/realtime/subscription-token` с `{"channel": ...}` — токен
  подписки на один канал: тот же `sub`/`sid` и claim `channel`, поэтому
  токен нельзя применить к другому каналу (Centrifugo отключает клиента).
  Оба маршрута требуют `Idempotency-Key`; повтор возвращает
  сохранённый токен, но проверки сессии и доступа выполняются заново.
  Время жизни — `CAMPUS_CENTRIFUGO_CONNECTION_TOKEN_TTL` и
  `CAMPUS_CENTRIFUGO_SUBSCRIPTION_TOKEN_TTL` (по 5 минут): клиент
  обновляет токен через API, где доступ проверяется ещё раз.
- **Каналы.** `user#<uuid>` — личный канал пользователя
  (user-limited channel без namespace; подписка только на свой).
  `chat:<uuid>` — канал чата из namespace `chat` с историей и
  восстановлением. Имя проверяется канонически: UUID в нижнем регистре,
  без лишних символов; иначе `422 realtime_channel_invalid`.
- **Доступ к чату.** `realtime_channel_grant` — проекция прав на реальное
  время: пара `(channel, user_id)`, отзыв — `revoked_at`, а не удаление
  строки. Модуль, владеющий членством (чат), пишет её публичными
  `grant_chat_access`/`revoke_chat_access` в той же транзакции, что и
  изменение членства. Нет действующего grant — `403
  realtime_channel_forbidden`; проверка идёт и при выдаче токена, и при
  восстановлении.
- **Сессии и блокировка.** Выдача токена проверяет строку сессии
  устройства в БД, а не только отметку отзыва в Redis: отозванная сессия
  получает `401` даже при повторном запросе с тем же
  `Idempotency-Key`. Блокировка аккаунта (#93) отзывает сессии, поэтому
  заблокированный пользователь не получит и токен соединения.
- **Принудительные эффекты.** Отзыв членства пишет в outbox
  `realtime.unsubscribe`, обработчик вызывает `unsubscribe(channel,
  user)`; отзыв сессии — событие `identity.sessions_revoked`, обработчик
  вызывает `disconnect(user)`. Перед отпиской обработчик заново читает
  grant: доставка, пришедшая после повторной выдачи доступа,
  пропускается. Команды Centrifugo идемпотентны, поэтому повторы outbox
  безопасны. `disconnect` отключает все устройства пользователя: у
  Centrifugo OSS нет адресации по нашей сессии, остальные устройства
  переподключаются и подписываются снова, а отозванное — не получит
  новый токен.
- **Восстановление.** `POST /api/v1/realtime/recover` с `{"channel":
  ..., "since": {"epoch": ..., "offset": ...}}` возвращает публикации
  после позиции и текущую `{epoch, offset}`; без `since` — только
  позицию. История эфемерна: если позиции уже нет,
  `409 realtime_history_lost` — клиент перезагружает состояние канала
  через API, полнота истории не гарантируется. Лимит читаемых
  публикаций — `CAMPUS_CENTRIFUGO_HISTORY_LIMIT`.
- **Конфигурация.** `CAMPUS_CENTRIFUGO_TOKEN_HMAC_SECRET` (тот же, что
  `client.token.hmac_secret_key` Centrifugo), `CAMPUS_CENTRIFUGO_API_URL`
  (например, `http://centrifugo:8000/api`), `CAMPUS_CENTRIFUGO_API_KEY`
  (`http_api.key`), `CAMPUS_CENTRIFUGO_API_TIMEOUT`. Без секрета токены
  отвечают `503 realtime_unavailable`, без адреса или ключа API — не
  работает восстановление; в Docker Compose значения задаются из
  `infra/.env`.
  История и recovery включены для личных каналов и namespace `chat` в
  `infra/compose.yaml`.
- **Тесты.** `tests/test_realtime.py` проверяет токены, матрицу доступа и
  обработчики на подменённом серверном API; concurrency — на настоящем
  PostgreSQL. `tests/test_realtime_integration.py` поднимает настоящий
  Centrifugo (testcontainers) и проверяет подключение, подписку, запрет
  чужого канала, принудительную отписку и отключение, чтение истории.

## Устройство

| Пакет               | Назначение                                              |
|---------------------|---------------------------------------------------------|
| `campus.api`        | Процесс API: сборка приложения, health, журнал запросов |
| `campus.worker`     | Процесс воркера: outbox и очередь задач                 |
| `campus.scheduler`  | Процесс планировщика: периодические задачи              |
| `campus.migrations` | Миграции Alembic                                        |
| `campus.seed`       | Команда `campus-seed`: начальные данные стенда          |
| `campus.admin`      | Команда создания первого администратора                 |
| `campus.modules.*`  | Доменные модули (ТЗ, п. 4.1)                            |
| `campus.core`       | Ядро: конфигурация, БД, часы, журналы, задачи, почта    |
| `campus.core.web`   | Общие механизмы HTTP API (см. ниже)                     |
| `campus.locales`    | Каталоги переводов сообщений (gettext)                  |

Доменные модули: `identity` (аутентификация и пользователи), `university`
(структура вуза), `listings` (объявления и взаимодействия), `reputation`
(подтверждение встреч и репутация), `points` (баллы), `booking`
(бронирование ресурсов), `chat`, `publications` (форум, страницы, лента),
`moderation`, `notifications`, `ai`, `administration`, `realtime` (токены
Centrifugo и восстановление потока).

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
  `delete_expired_idempotency_keys` в задаче очистки планировщика
  (`CAMPUS_CLEANUP_CRON`).
- **Шифрование сохранённых ответов.** Ответ может содержать токены
  (вход, обновление refresh), поэтому код, заголовки и тело ответа
  хранятся одним столбцом `idempotency_key.response`, зашифрованным
  AES-256-GCM (`cryptography`). Ключи — `CAMPUS_IDEMPOTENCY_ENCRYPTION_KEYS`:
  base64-ключи по 32 байта через запятую (`openssl rand -base64 32`),
  нужны только процессу API: без них API не запускается
  (`MissingEncryptionKeysError` при старте), воркеру и планировщику ключи не
  нужны. В `.env.example` — ключ только для разработки, в тестах ключ задаёт
  `tests/conftest.py`; в Docker Compose переменная обязательна (`${VAR:?}`)
  и передаётся только сервису `api`. Первый ключ шифрует, любой из
  списка расшифровывает; в шифротексте — идентификатор ключа (префикс его
  SHA-256), а область и сам `Idempotency-Key` — связанные данные, так что
  ответ нельзя перенести в чужую строку. Ротация: новый ключ ставится
  первым, старый удаляется не раньше чем через
  `CAMPUS_IDEMPOTENCY_KEY_TTL` — к этому времени все ответы, зашифрованные
  им, удалены очисткой. Ключи хранятся только в окружении процесса API
  (на стенде — `infra/.env`), не в БД и не в журналах. Ответ, ключ
  которого удалён раньше срока или который не расшифровывается, не
  повторяется и операция заново не выполняется: `500 internal_error`.
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
  удаления во время прокрутки не теряют и не дублируют записи. Курсор
  подписан HMAC-SHA256 ключом `CAMPUS_CURSOR_SECRET_KEY` (не короче
  32 символов; обязателен для эндпоинтов списков), поэтому изменённый
  клиентом курсор отклоняется с `400 invalid_cursor`. Лента
  дополнительно подписывает время снимка и отклоняет снимок старше
  `CAMPUS_FEED_SNAPSHOT_TTL` (по умолчанию 15 минут): в обоих случаях
  клиент начинает прокрутку заново.

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

Пагинация настраивается `CAMPUS_PAGE_SIZE_DEFAULT`/`_MAX`, а также
`CAMPUS_CURSOR_SECRET_KEY` (ключ HMAC курсоров, не короче 32 символов;
без него эндпоинты списков не работают) и `CAMPUS_FEED_SNAPSHOT_TTL`
(срок жизни снимка ленты, по умолчанию 15 минут).

### За обратным прокси

Адрес клиента (по нему считается лимит входа по IP) и схема берутся из
`X-Forwarded-For` и `X-Forwarded-Proto` только если соединение пришло от
доверенного прокси из `CAMPUS_TRUSTED_PROXIES` — адреса и сети через
запятую (`127.0.0.1,172.16.0.0/12`) или `*`. По умолчанию — `127.0.0.1`.
От остальных клиентов заголовки игнорируются, используется адрес сокета.
Из цепочки `X-Forwarded-For` берётся последний адрес справа, не
входящий в доверенные. Обработка — в приложении
(`ProxyHeadersMiddleware` uvicorn), переменная uvicorn
`FORWARDED_ALLOW_IPS` не используется. Настройка в Docker Compose — в
`infra/README.md`.

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

## Вход по коду из письма

Для `/api/v1/auth` нужны PostgreSQL, Redis, разрешённые домены из seed,
`CAMPUS_AUTH_SECRET_KEY` (случайный секрет минимум 32 символа) и SMTP
воркера. Миграция: `uv run alembic upgrade head`. Redis подключается
лениво; сбой Redis закрывает доступ к аутентификации.

Все POST требуют `Idempotency-Key`, `X-Client-Platform` и
`X-Client-Version`; ошибки возвращаются как Problem Details.

- `POST /sign-in-codes`: `{email}`. Точное совпадение домена, регистр адреса
  нормализуется. Ответ 202 одинаков для новых и существующих адресов.
  Письмо отправляется для доменов вуза и подтверждённых резервных адресов;
  для неизвестного личного адреса письмо и аккаунт не создаются.
  Код из 6 цифр идёт через outbox на RU/EN по `Accept-Language`, хранится
  HMAC-хэшем; после отправки payload письма очищается.
- `POST /sign-in`: `{email, code, device_id, device_name?, first_name?,
  last_name?}`. Первый вход требует имя и фамилию, состоящие из букв,
  пробелов, дефисов и апострофов. Регистрация возможна только с почтой
  вуза; любой подтверждённый адрес ведёт в тот же аккаунт.
  Ответ: `access_token`, `refresh_token`, `token_type`, `expires_in`, `user`.
  Новый вход на том же устройстве отзывает прежнюю сессию.
- `POST /token/refresh`: `{refresh_token, device_id}`. Ротация refresh;
  повтор старого токена или несовпадение устройства отзывает всю сессию
  и её access-токены через Redis. Истечение refresh также отзывает сессию.
- `POST /sign-out`: `Authorization: Bearer <access_token>`, ответ 204.
  Отзывает текущую сессию; остальные устройства продолжают работу.

Потеря ответа входа или обновления: клиент повторяет запрос с тем же
`Idempotency-Key` и тем же телом в течение `CAMPUS_IDEMPOTENCY_KEY_TTL` и
получает те же токены из зашифрованного сохранённого ответа; вход и
ротация не выполняются повторно. Повтор refresh с новым ключом — это
повторное использование старого токена, он отзывает сессию. Ротация
refresh и сохранение ответа фиксируются одной транзакцией: сбой между
ними откатывает ротацию вместе с ключом, старый refresh остаётся
действительным, а повтор с тем же ключом выполняет ротацию заново.

Access — JWT HS256 на 15 минут; refresh — случайный непрозрачный токен
на 30 дней, в БД только SHA-256. В публичные маршруты входа и обновления
не следует передавать истёкший access-токен. Защищённые маршруты используют
`CurrentUser` из `campus.core.web.auth`; ключи идемпотентности имеют область
пользователя. Схема с bearer security доступна на `/api/v1/openapi.json`;
типы admin-клиента обновляются командой `npm run api:generate` в `admin/`.
Сетевой слой Flutter из OpenAPI — отдельная issue #36.

### Второй корпоративный и резервный адреса

Защищённые маршруты `/api/v1/me/emails`:

- `GET /`: подтверждённые адреса текущего пользователя с `id`, `email`,
  `kind` (`corporate` или `backup`) и `verified_at`.
- `POST /codes`: `{email, kind}`, ответ 202. Отправляет код на новый
  адрес. Корпоративный адрес должен быть из разрешённого домена;
  резервный — из личного. Занятый адрес возвращает 409.
- `POST /`: `{email, kind, code}`, ответ 201 с подтверждённым адресом.
  Код привязан к пользователю и виду адреса, не подходит для входа.
  Новый резервный заменяет прежний только после подтверждения.
- `DELETE /{id}`: ответ 204; последний корпоративный удалить нельзя
  (409), чужой или отсутствующий адрес возвращает 404.

Изменения требуют `Idempotency-Key`. Лимиты запросов совпадают с входом;
исчерпание попыток подтверждения возвращает 429 с `Retry-After`.
Не больше одного резервного адреса и уникальность адресов обеспечены БД;
изменения одного аккаунта сериализованы блокировкой строки пользователя.
Тип аккаунта — студент при наличии подтверждённого студенческого адреса,
иначе сотрудник. При переходе в сотрудники курс очищается.

После изменения адресов уведомление идёт на все подтверждённые адреса,
включая все корпоративные и текущий резервный. Общая функция
`identity.notify_account_security` принимает текст события для повторного
использования в восстановлении входа. Адреса хранятся в
`identity_user_email`; `identity_user.email` сохранён как совместимое
основное поле ответа `/me` и обновляется при удалении основного адреса.
Для входа используется только таблица подтверждённых адресов. Миграция
переносит прежние адреса с временем создания аккаунта как подтверждением.

Очистка (задача `CAMPUS_CLEANUP_CRON`, `campus.modules.identity.retention`):

- код входа удаляется через `CAMPUS_SIGN_IN_CODE_RETENTION` (1 сутки)
  после истечения;
- сессия завершена, если она отозвана или истёк её последний refresh;
  через `CAMPUS_SESSION_RETENTION` (7 дней) она удаляется вместе со всеми
  refresh-токенами;
- использованный refresh действующей сессии хранится ещё
  `CAMPUS_REFRESH_TOKEN_REUSE_WINDOW` (30 дней) после своего истечения:
  его повтор в этом окне отзывает сессию, позже токен удаляется и
  отклоняется без отзыва. Поэтому старый refresh обнаруживается в течение
  срока жизни токена и окна, а строки долгой сессии не копятся бессрочно.

Настройки срока кода (10 минут), попыток (5), частоты писем
(`3/15 minutes;10/day`) и общего лимита запросов кода/ввода по IP
(`60/minute`) перечислены в `.env.example`. Ответ 429 содержит
`Retry-After` в секундах. Ключи Redis содержат HMAC адреса/IP, без ПДн.

## Профиль

Профиль заполняется после первого входа (ТЗ п. 5.1.1, модуль 2, пункт 1):
город-кампус, факультет, курс и общежитие или «не живу в общежитии».
Поля хранятся в `identity_user`; общежитие и факультет обязаны
относиться к городу профиля — это проверяет API и гарантирует БД
(составные внешние ключи на `(city_id, id)` справочников).

- `GET /me` — свой аккаунт и профиль (`UserOutput`, тот же объект — в
  `user` ответа входа): `city_id`, `dormitory_id`, `faculty_id`, `course`
  и `profile_complete`.
- `PUT /me/profile`: `{city_id, dormitory_id?, faculty_id, course?}` —
  профиль целиком; пустое `dormitory_id` — не живёт в общежитии. Ошибки —
  `422 validation_failed` с полями: `not_found` (города нет),
  `not_of_city` (общежитие или факультет другого города или их нет),
  `missing` (студенту нужен курс), `not_allowed` (у сотрудника курса нет),
  курс — от 1 до `CAMPUS_PROFILE_MAX_COURSE` (6).

Профиль заполнен, когда выбраны город и факультет, а у студента — курс.
Публикация и отклики (бронь, запись, доля) требуют заполненного профиля:
их маршруты берут `ProfiledUser` из `campus.modules.identity` вместо
`CurrentUser` и без профиля отвечают `403 profile_incomplete`.

## «Отдам»: объявления и взаимодействия

`POST /api/v1/listings/giveaways` публикует вещь: `title`, `description`,
`visibility` (`city`, `faculty`, `dormitory`), `audience` (`students` по
умолчанию, либо `community`). Область берётся из заполненного профиля автора
и сохраняется в объявлении; сотруднику недоступно общежитие.

`GET /listings?area=city|faculty|dormitory&size=20&cursor=…` возвращает
объявления от новых к старым с курсорной пагинацией. Городская лента включает
все доступные пользователю области, переключатель сужает её до выбранной.
Проверки области и аудитории действуют также на чтение карточки и бронь.

`POST /listings/{id}/reservations` создаёт заявку первого откликнувшегося.
Автор не может бронировать свою вещь. Общая строка объявления блокируется
для брони, отмены, правки и смены статуса взаимодействия; частичный
уникальный индекс дополнительно защищает активную бронь слота. Для вещи
используется слот 1; будущие сценарии с вместимостью могут распределять
слоты или использовать взаимодействия без слота.

`POST /listings/{id}/interactions/{interaction_id}/transition` принимает
`status`. Таблица переходов в текущем срезе:

| Из | В | Кто |
| --- | --- | --- |
| `pending` | `accepted`, `rejected` | Автор |
| `pending`, `accepted` | `cancelled` | Участник |

Остальные переходы отклоняются (`409 listing_conflict`), чужое действие —
`403 listing_forbidden`. Отклонение или отказ участника освобождает вещь.
Отмена объявления (`POST /listings/{id}/cancel`) в этом срезе разрешена
только для свободного активного объявления: одновременные бронь и отмена
не могут обе завершиться успешно. Отмена занятого объявления с причиной,
очередь, срок брони и встреча относятся к эпику #10.

`PATCH /listings/{id}` принимает `title`, `description` и `version`.
Версия относится ко всему агрегату: бронь и переходы тоже её увеличивают.
Устаревшая правка получает `409 listing_version_conflict` с
`current_version`; для повторной правки нужны свежие данные и новый ключ
идемпотентности. Все изменяющие операции используют общий транзакционный
механизм `Idempotency-Key` с зашифрованными ответами.

История `GET /listings/{id}/events` доступна автору и участникам,
пагинируется хронологически. Каждая публикация, правка и смена статуса
записывается в `listing_event` в той же транзакции; триггер БД запрещает
изменение, удаление и очистку истории.

Срок жизни задаётся `CAMPUS_LISTING_LIFETIME` (30 дней). Дедлайн сохраняется
при публикации. Планировщик после простоя переводит просроченное объявление
в `expired`, отклоняет непринятую заявку и записывает события. Принятые
взаимодействия сохраняются для дальнейшего завершения. Просроченные
объявления исчезают из ленты и запрещают новые операции даже до запуска
планировщика. Пределы длины текста задаются
`CAMPUS_LISTING_TITLE_MAX_LENGTH` (100) и
`CAMPUS_LISTING_DESCRIPTION_MAX_LENGTH` (5000).

Архив — статусы `expired`, `completed` и `cancelled`. Момент входа в архив
хранится в `listing.archived_at` и сбрасывается при выходе из него
(повторная публикация); скрытые модерацией объявления в архив не входят.
Задача очистки (`CAMPUS_CLEANUP_CRON`) через
`CAMPUS_LISTING_ARCHIVE_RETENTION` (1 год, ТЗ п. 5.3.2) после более позднего
из двух моментов — входа в архив и последнего изменения взаимодействия —
удаляет описание и фото объявления, ставит `purged_at` и пишет в журнал
событие `purged`; строка объявления с заголовком, взаимодействия и журнал
остаются, поэтому история и отзывы читаются. Объявление с незавершённым
взаимодействием (`pending`, `accepted`) не очищается; дата создания не
учитывается. Каждое объявление очищается в своей транзакции под блокировкой
строки (`SKIP LOCKED`), поэтому повторная публикация и правка фото либо
выполняются раньше (публикация выводит объявление из архива), либо видят
`purged_at` и получают `409`. Содержимое других модулей удаляют
обработчики `register_archive_purger` (фото — модуль `files`). Объекты S3
удаляются до фиксации; отсутствующий объект допустим, а сбой откатывает
объявление, и оно повторяется при следующем запуске. Удаляются только
файлы, всё ещё прикреплённые к этому объявлению. За запуск обрабатывается
не больше `CAMPUS_LISTING_ARCHIVE_CLEANUP_LIMIT` объявлений пачками по
`CAMPUS_LISTING_ARCHIVE_CLEANUP_BATCH`; в отчёт (`listings_purged`,
`listings_skipped`, `listings_failed`, `listings_photos`) попадают только
числа, в журнал ошибок — идентификатор объявления и класс ошибки.

Общая таблица `listing` содержит тип, область, аудиторию, статус и версию;
`listing_item` — данные сценариев вещей. Новые типы добавляют таблицу деталей
и используют общие взаимодействия, журнал и механизм сроков.

## Первый администратор

После миграций и загрузки разрешённых почтовых доменов выполните в
окружении backend (с `CAMPUS_DATABASE_URL`):

```sh
uv run python -m campus.admin create-first-admin \
  --email admin@hse.ru --first-name Иван --last-name Иванов
```

Команда создаёт аккаунт с типом разрешённого домена либо использует
существующий, сохраняя его имя и профиль. Назначение администратора — без
области. При существующем администраторе команда завершается с кодом 1 и
ничего не меняет; одновременные запуски сериализуются транзакцией БД.

## Проверки прав

Публичный интерфейс `campus.modules.identity` предоставляет `Permissions`
(тип аккаунта и роли из БД на каждый запрос), `require_roles(...)`
и методы контекста `require_scope(dormitory_id=... / faculty_id=...)`,
`require_author`, `require_owner`, `require_participant`. Идентификаторы
объекта и его участников берутся из загруженного на сервере объекта.
Проверки выполняются в зависимостях FastAPI до вызова обработчика:
при повторе идемпотентного запроса зависимости выполняются заново, а
обработчик заменяется сохранённым ответом. Так отзыв роли или изменение
владельца действует и для повторов со старым ключом.
Отказ — `403 forbidden` в формате Problem Details. Глобальные роли не
обходят автоматически проверки области и прав на объект.

Все маршруты веб-панели подключаются через `campus.api.admin.router`:
он использует `identity.admin_router()` с одной зависимостью модератора
или администратора, наследуемой вложенными роутерами. Маршруты старосты
подключаются в обычном API приложения и проверяют точное совпадение области
(общежитие или факультет). Тип аккаунта сам по себе не даёт роль.
`GET /me` и обновление профиля возвращают массив `roles` с полями `role`,
`dormitory_id`, `faculty_id`. Роли не записываются в access-токен.

### Журнал действий модераторов и администраторов

Каждое административное действие записывается в таблицу `audit_record`
функцией `campus.core.audit.record_action(session, actor_id=...,
action="moderation.complaint.resolve", object_type=..., object_id=...,
reason=..., participant_ids=..., before=..., after=..., details=...)`
в той же сессии, что и само действие: запрос фиксирует оба или ничего,
а повтор с тем же `Idempotency-Key` возвращает сохранённый ответ без
новой записи. Request ID берётся из `X-Request-ID`.

- `participant_ids` — участники дела из загруженного на сервере объекта;
  `own_case` («участник разбирает собственный случай») вычисляется из
  них, его же проверяет ограничение БД. Флаг от клиента не принимается.
- `before`/`after`/`details` — только изменённые поля: идентификаторы,
  статусы, короткие метки. Ключи с токенами, кодами, паролями, TOTP и
  текстами (`text`, `body`, `message`…) и строки длиннее 200 символов
  отклоняются `AuditPayloadError`.
- Просмотр приложенных к жалобе сообщений и чата спора —
  `record_conversation_access(...)` с основанием и диапазоном сообщений;
  вызывается до загрузки сообщений, поэтому ошибка записи прерывает
  чтение.

Записи неизменяемы: триггеры БД отклоняют `UPDATE`, `DELETE` и
`TRUNCATE` для любой роли, включая прикладную, в том числе при
`session_replication_role = replica`. Удалять может только роль
`campus_audit_retention` (`NOLOGIN`, создаётся миграцией; для смены
владельца функции миграции выполняются суперпользователем — в Compose
это `POSTGRES_USER`), от которой работает лишь функция
`audit_purge_expired(interval)`. Она не удаляет записи моложе 1096 дней
по часам БД. Очистка запускается задачей `CAMPUS_CLEANUP_CRON` со сроком
`CAMPUS_AUDIT_RETENTION` (по умолчанию и не меньше 1096 дней).

`GET /api/v1/admin/audit` — журнал с курсорной пагинацией (новые
сначала, `order_by=occurred_at` — старые сначала) и фильтрами
`actor_id`, `action`, `object_type`, `object_id`, `participant_id`,
`own_case`, `occurred_from` (включительно), `occurred_to` (не
включительно). Читает только администратор; модератору, старосте и
остальным — `403 forbidden`. Доступ модератора к хронологии конкретного
дела выдаётся самим делом и журнал не открывает.

### Сессии устройств

`GET /api/v1/me/sessions` возвращает активные сессии владельца:
`id`, `device_name`, `platform`, `signed_in_at`, `last_active_at`, `current`.
Последняя активность — вход или последнее успешное обновление токена.
Отозванные сессии и сессии без действующего refresh не возвращаются.

`DELETE /api/v1/me/sessions/{session_id}` отзывает выбранную сессию;
чужой или неизвестный идентификатор возвращает 404. Повторный отзыв
своей сессии безопасен. `DELETE /api/v1/me/sessions` отзывает все сессии
пользователя, включая текущую. Оба запроса требуют `Idempotency-Key`
и возвращают 204. Эти маршруты доступны и при необходимости принять
новую версию обязательных документов.

Отзыв блокирует ту же строку сессии, что и ротация refresh. Идентификаторы
сразу записываются в список отозванных в Redis на срок жизни access.
В одной транзакции с отзывом создаётся outbox-событие
`identity.sessions_revoked`: `user_id` и массив `session_ids` (UUID строками).
Событие содержит только впервые отозванные сессии; тот же контракт
используют обычный выход, замена сессии при входе и обнаружение повторного
использования refresh. Потребители отключения Centrifugo (#77) и ключей
устройств (#71) реализуются отдельно; при нескольких потребителях нужны
отдельные сообщения для независимых повторов согласно правилам outbox.

### Versioned consents

`campus-seed` also adds the four initial legal documents, with RU/EN texts.
These are demonstration texts for test data. Repeating the seed never
replaces or republishes an existing version.

`GET /api/v1/documents` is public and selects text by `Accept-Language`.
Each item has an immutable version UUID, kind, version number, publication
time and `required` flag. On registration, pass the three mandatory UUIDs
in `accepted_document_ids` to `POST /api/v1/auth/sign-in`. Optional consent
is separate: `cross_border_document_id`, omitted by default. Existing
accounts can sign in without accepting documents again.

When a current mandatory version has not been accepted, authenticated API
requests return `403 consent_required`. The Problem Details `errors` list
contains the missing document kinds in `code` and version UUIDs in `detail`.
The gate runs before idempotent response replay. Reading documents,
`POST /me/consents` (`document_ids` of mandatory versions),
`PUT /me/consents/cross-border` (`document_id`, `accepted`) and sign-out
remain available. All mutating requests need an `Idempotency-Key` UUID.
Future export/deletion routes must use the names `export_my_data` and
`delete_my_account` to remain available through the gate (#79, #76).

`GET /me` and token responses include `cross_border_transfer_allowed`.
The public domain functions `identity.publish_document` and
`identity.cross_border_allowed` use the caller's database transaction.
The admin API owns authorization of publication (#101); no public endpoint
publishes documents. Publication serializes against protected requests and
acceptances; concurrent decisions for one account are serialized too.
A new optional version requires a fresh, explicit grant, without blocking
core service access.

`identity_consent_decision` records user, immutable document version,
decision, controlled timestamp and session UUID. PostgreSQL triggers reject
UPDATE, DELETE and TRUNCATE of decisions and published versions. The session
UUID is an audit snapshot; credential cleanup can delete the session.
Every cross-border permission change writes
`identity.cross_border_consent_changed` to the transactional outbox with
`user_id`, `document_id` and `allowed`. This includes invalidation of a
previous grant by publication. Consumers (#86, Telegram, AI) must recheck
`identity.cross_border_allowed` before sending: outbox retries may reorder
events. The identity worker handler fans out to independently retried jobs
for registered consumers; no connected consumers is a successful no-op.
Channel behavior is implemented with those consumers.
Withdrawal of personal-data processing consent uses account deletion (#76).

Consumers register through the public identity interface on module import:

```python
@consent_consumers.register("fcm")
async def update_fcm(session: AsyncSession, change: ConsentChange) -> None:
    # change.allowed is authoritative current state, not the event snapshot.
    # Use change.delivery_id as the provider's idempotency key.
    ...
```

The callback holds the same user/publication locks as consent decisions.
Perform any immediate external transfer inside the callback; a later queued
transfer must recheck `cross_border_allowed` in its own transaction. A
permission notification is not a stored authorization for future sends.
Callbacks must reconcile current state and make external effects idempotent
using `delivery_id` (or an equivalent provider-supported deduplication key).
A database rollback cannot undo an external request; a provider without
idempotency support cannot guarantee exactly-once irreversible effects.
Database effects and job completion commit together.

When deploying a new consumer, apply migrations, deploy its registration
on all workers, and run (with the backend environment configured):

```sh
uv run python -m campus.worker.replay_consents
```

This transaction fans out every retained source event, including processed
and failed events, only to consumers without a dispatch receipt. Legacy
`UnknownTopicError` failures are marked recovered; unrelated failures stay
visible. Repeating the command is safe. Each consumer's delivery then uses
the normal outbox retries. Exhausted consumer jobs require an explicit
operator retry after fixing the cause; replay does not silently reset them.
`identity_consent_dispatch` receipts intentionally survive outbox cleanup
and have no source-row foreign key, preventing replay from repeating a
completed delivery after retention removes its job. Do not prune receipts
while source events can still be replayed. They contain only event UUIDs
and consumer identifiers, without consent payloads or user identifiers.

Replay covers retained outbox history, not events already removed by the
configured retention policy. A consumer enabled beyond that window must
bootstrap its complete state from current users and `cross_border_allowed`;
no deployment may infer consent from an absent event. Keep transfer checks
active during bootstrap. No FCM, Telegram or AI transport is enabled here.


### Общая механика объявлений

`GET /api/v1/listings/categories` возвращает начальный справочник категорий
с `id`, стабильным `code` и именем на языке `Accept-Language` (RU/EN).
Публикация требует `category_id` из этого справочника; существующим
объявлениям миграция назначает «Другое».

`POST /listings/giveaways` по умолчанию публикует объявление. Поле
`draft: true` создаёт приватный черновик без срока истечения; категория
может быть выбрана при редактировании (`PATCH /listings/{id}`). Автор
публикует его через `POST /listings/{id}/publish`. Этот же маршрут возвращает
истёкшее объявление в ленту; при сохранившейся принятой брони оно остаётся
занятым. `POST /listings/{id}/extend` переносит срок активного или занятого
объявления от текущего момента. Все пути здесь относительно `/api/v1`.
`GET /listings/mine` — курсорный список всех объявлений автора, включая
черновики, архив и скрытые с причиной. В общей ленте остаются только
активные и занятые с неистёкшим сроком.

Сотрудник публикует и бронирует только для аудитории `community`.
Все изменяющие маршруты требуют заполненного профиля и `Idempotency-Key`.
`expires_at` теперь nullable для черновиков; статусы объявлений дополнены
`draft`, `completed`, `hidden`, взаимодействий — `completed`, `no_show`.
Завершение и неявка доступны только через сервисный интерфейс для модуля
QR; HTTP-маршрут переходов не разрешает участникам вызывать их напрямую.
Тип сценария определяет срок ответа автора и этапы внутри `accepted`
через `TYPE_POLICIES`; общий статус взаимодействия от этапа не зависит.

Заявки автоматически отклоняются при закрытии, истечении или отсутствии
ответа автора. Принятые взаимодействия продолжаются после закрытия и
истечения. Сроки хранятся в `core.deadlines`; обработка раз в минуту
подхватывает также сроки, пропущенные при простое. Журнал содержит
машинную причину автоматического отказа, этап, флаги `via_assistant` и
`offline_qr`. Приватная хронология конкретного взаимодействия доступна
по `GET /listings/{id}/interactions/{interaction_id}/events`.

Каждая запись журнала создаёт сообщение `notifications.send` в той же
транзакции через `notifications.notify()`: `recipients`, `type`, `params`
и тексты RU/EN. Доставка этих сообщений реализуется в #85; служебное
скрытие вызывается модулем модерации через `listings.hide()` после его
проверки роли и области модератора.

| Переменная `CAMPUS_…` | По умолчанию |
| --- | --- |
| `LISTING_LIFETIME` | 30 дней |
| `LISTING_RESPONSE_TIMEOUT` | 24 часа |
| `LISTING_PUBLICATION_LIMIT` / `LISTING_PUBLICATION_WINDOW` | 10 / 1 день |
| `LISTING_RESPONSE_LIMIT` / `LISTING_RESPONSE_WINDOW` | 30 / 1 час |
| `LISTING_TITLE_MAX_LENGTH` | 100 |
| `LISTING_DESCRIPTION_MAX_LENGTH` | 5000 |
| `LISTING_ARCHIVE_RETENTION` | 365 дней |
| `LISTING_ARCHIVE_CLEANUP_BATCH` / `LISTING_ARCHIVE_CLEANUP_LIMIT` | 50 / 1000 |

Периоды задаются как ISO 8601 duration (например, `P30D` или `PT24H`).
Квоты общие на пользователя и считаются по успешным действиям журнала
в скользящем окне с транзакционной блокировкой, включая параллельные
запросы. Превышение возвращает Problem Details `listing_rate_limited`
(429) с `Retry-After`; повтор с тем же ключом квоту не расходует.

## Время города

Моменты в схемах API объявляются общим типом `campus.core.web.Instant`:
на входе RFC 3339 с явным смещением (`2026-11-16T18:00:00+05:00`),
на выходе UTC (`2026-11-16T13:00:00Z`). Наивное время и числовые Unix
timestamps отклоняются с `validation_failed`. Поле `city_timezone` содержит
IANA-пояс города профиля, объявления, общежития или факультета; у профиля
без города оно `null`. Справочник городов возвращает пояс в `timezone`.

В `campus.core.timezones` находятся `local_to_utc(day, time, timezone)`,
`in_local_interval(moment, start, end, timezone)` и
`next_weekly(weekday, time, timezone, after=...)`. Интервал включает начало,
исключает конец, поддерживает переход через полночь; равные границы дают
пустой интервал. Дни недели — от 0 (понедельник) до 6 (воскресенье).
Следующее наступление строго позже `after`, по умолчанию — `clock.now()`.
При осеннем повторе местного времени выбирается первое наступление;
несуществующее время при весеннем переходе отклоняется для ввода и
пропускается для еженедельного расписания. Границы интервалов и местное
время передаются без смещения; сами моменты должны иметь смещение.

### Private photos

Provision `CAMPUS_S3_BUCKET` in RustFS without public ACLs or public bucket
policies. Set `CAMPUS_S3_ENDPOINT_URL`, region and access credentials (see
`.env.example`). The endpoint must be reachable by clients and the worker;
preserve its Host header through Caddy because SigV4 signs it. Configure
bucket CORS for the actual browser origins and POST/GET/HEAD methods. Local
Caddy certificates must be trusted by the backend as well as the browser.

`POST /api/v1/files/photo-uploads` returns metadata, a POST URL, exact form
fields and expiration. Send those fields as multipart form data, with the
file field last. The signed policy fixes the source key and limits the
actual object length to 10 MiB. `POST /api/v1/files/{id}/complete` enqueues
processing atomically; poll `GET /api/v1/files/{id}` for `ready` or `rejected`
and its machine-readable reason. Never display the unprocessed source.
All API writes require `Idempotency-Key`; a replay returns the original
credential and original expiration, not a renewed credential.

`PUT /api/v1/listings/{id}/photos` replaces the ordered `file_ids` list
(empty removes all). It locks the listing and the selected files, verifies
ownership, readiness, purpose and expiration, and permits up to ten files.
A file belongs to at most one listing. `GET .../photos` returns private,
short-lived photo and preview URLs after the normal listing access check.
A previously issued URL remains a bearer credential until its expiration.

Pillow and pillow-heif decode JPEG, PNG, WebP and HEIC by content. The worker
bounds downloaded bytes and decoded pixels, applies EXIF orientation, then
encodes fresh JPEG pixels and a thumbnail without EXIF/GPS, ICC or XMP.
No input filename or client MIME declaration is trusted.

Processing uses durable outbox jobs and the standard retry/backoff policy.
Deterministic output keys tolerate partial writes and transaction retries;
the source stays private until expiry so rollback never loses retry input.
Deadlines delete expired unbound files and their three object keys, keeping
the database row until every delete succeeds. Bound files retain outputs;
the source is deleted after the upload credential has expired. Detaching a
file starts a new unbound retention period. Expiry never precedes upload
credential expiration, preventing a valid POST from recreating a cleaned
source. Monitor failed outbox/deadline jobs under the existing job policy;
retry exhausted failures after repairing storage. Retention and URL TTLs
come from configuration; server time comes from `campus.core.clock`.
### Session revocation events

`identity.sessions_revoked` is handled even without channel consumers.
Consumers register on module import through the public identity interface:

```python
@session_consumers.register("devices")
async def revoke_devices(session: AsyncSession, event: SessionsRevoked) -> None:
    # event.user_id and event.session_ids identify the revoked devices.
    # Use event.delivery_id as the provider's idempotency key.
    ...
```

Each consumer receives its own outbox job with independent retries. Use
stable consumer names. Database effects commit with delivery completion;
external effects require provider deduplication with `delivery_id`, which
stays unchanged after a lost acknowledgement and retry.

After migrations and registration are deployed on every worker, run:

```sh
uv run python -m campus.worker.replay_sessions
```

The shared dispatcher replays retained source events to new consumers,
including legacy `UnknownTopicError` failures. Concurrent or repeated
replay is safe and does not reset failed delivery jobs or repeat existing
consumers. Other source failures remain visible. Exhausted deliveries need
an explicit operator retry after fixing their cause.

`identity_session_dispatch` receipts survive outbox retention and have no
foreign key to the source. Keep them while source events can be replayed.
They contain only event UUIDs and consumer names. Pruned source events
cannot be replayed; consumers deployed after that window need their own
state reconciliation. Realtime and device-key consumers remain in #77
and #71 respectively.

### Informational publications and feed filters

`POST /api/v1/listings/publications` creates a `kind=publication` entry in
that same listing aggregate and its shared `publication` base row, with `title`, `description`, `visibility` and
an explicit future `pinned_until` instant. It has no item, interactions or
listing lifetime. Headmen supply their assigned `dormitory_id` or
`faculty_id`; administrators publish for `city` (optional `city_id`, defaults
to their profile city) or `university`. University publications are visible
across cities; their `city_id` supplies timezone metadata. All publications
use the community audience, while dormitory access still requires a
student living in that dormitory.

Authors and administrators edit publications through the existing
`PATCH /api/v1/listings/{id}` with optimistic `version` checks. Optional
`pinned_until` changes the deadline; null removes the pin. The dedicated
`POST /api/v1/listings/{id}/unpin` also removes just the pin. The existing
`POST .../{id}/cancel` withdraws the publication. All writes use the common
idempotency and Problem Details mechanisms. Expiration of a pin needs no
worker: a new feed request ranks it chronologically without removing it.

`GET /api/v1/listings` accepts `kind`, `category_id` and `dormitory_id` in
addition to `area`. Filters intersect and never widen visibility. In city
and faculty feeds, the dormitory filter uses the author's dormitory saved
at publication time; changing the author's profile does not move entries
between filter results. Existing entries are backfilled from current
profiles by the migration. Publications without a category do not match a
category filter.

Visible university pins are included in narrower area feeds too. Pins sort
first, then all entries sort by creation time and UUID descending. The
cursor binds the user, profile scope, filters and first-page timestamp.
New entries and pin deadlines are evaluated against that timestamp while
scrolling; refresh the first page to see new entries or newly expired pins.
Reusing a cursor with other filters returns `400 invalid_cursor`. Explicit
edits, withdrawals and permission changes can alter the remaining results;
the cursor is not a historical snapshot of mutable content.
