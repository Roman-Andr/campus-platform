# Инфраструктура «Кампуса»

Серверные компоненты в Docker Compose (ТЗ, п. 4.4): API, PostgreSQL 18 с
pgvector, Redis 7, Centrifugo, RustFS и обратный прокси Caddy. Воркер и
планировщик добавит задача об outbox (#29).

## Быстрый старт

Нужен Docker с Compose v2. Из корня репозитория:

```sh
cd infra && (test -f .env || cp .env.example .env) && docker compose up -d --build --wait
```

`--wait` возвращает управление, когда все сервисы готовы (healthcheck),
и завершается с ошибкой, если какой-то не поднялся, например упали
миграции.

Проверка: `curl -k https://localhost/api/v1/health` → `{"status":"ok"}`
(сертификат для `localhost` выпускает локальный центр сертификации Caddy,
отсюда `-k`). Документация API — <https://localhost/api/v1/docs>.

Rootless Docker или podman не открывают порты ниже 1024: задайте в
`.env` `CADDY_HTTP_PORT=8080` и `CADDY_HTTPS_PORT=8443` и обращайтесь к
`https://localhost:8443`. С podman Docker API включается сокетом
пользователя (`systemctl --user start podman.socket`,
`DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock`); имена сервисов
в сети compose резолвятся при сетевом бэкенде netavark или с плагином
CNI `dnsname`.

Остановка — `docker compose down` (данные остаются в томах);
`docker compose down -v` удаляет и данные.

## Сервисы

| Сервис       | Назначение                                     | Готовность                 |
|--------------|------------------------------------------------|----------------------------|
| `caddy`      | HTTPS и WSS, перенаправление с HTTP            | admin API `:2019`          |
| `api`        | API (`campus-api`), образ из `backend/`        | `GET /api/v1/health`       |
| `migrate`    | `alembic upgrade head` при каждом запуске      | завершился с кодом 0       |
| `postgres`   | PostgreSQL 18 + pgvector                       | `pg_isready`               |
| `redis`      | Кэш, лимиты, брокер задач; AOF, пароль         | `redis-cli ping`           |
| `centrifugo` | Сервер реального времени                       | `GET /health`              |
| `rustfs`     | S3-совместимое хранилище                       | `GET /health/ready`        |
| `mailpit`    | Перехват почты — только в разработке           | `mailpit readyz`           |

Порядок запуска: `postgres` готов → `migrate` применяет миграции →
`api` стартует после миграций и готовности Redis, Centrifugo и RustFS →
`caddy` — после готовности `api`. Упавшие миграции оставляют API
незапущенным.

Начальные данные (справочники вуза) загружаются вручную после первого
запуска, повторная загрузка безопасна:
`docker compose run --rm migrate campus-seed`.

Маршруты Caddy:

- `https://$CAMPUS_DOMAIN/api/*` → API;
- `https://$CAMPUS_DOMAIN/connection/*` → клиентские транспорты
  Centrifugo (серверный API Centrifugo наружу не открыт);
- `https://$CAMPUS_STORAGE_DOMAIN` → RustFS (S3 для подписанных ссылок:
  подпись включает хост, поэтому у хранилища свой домен).

Сети: `data` (PostgreSQL, Redis) доступна только процессам сервера,
`edge` — сервисам за Caddy. Тома: `postgres-data`, `redis-data`,
`rustfs-data`, `caddy-data` (сертификаты), `caddy-config`.

## Разработка и стенд

`compose.yaml` — общий для разработки и стенда. В разработке
`docker compose` в `infra/` автоматически добавляет
`compose.override.yaml`:

- Mailpit: SMTP `mailpit:1025` внутри сети, веб-интерфейс
  <http://127.0.0.1:8025>;
- порты на `127.0.0.1` для инструментов на хосте: PostgreSQL `5432`,
  Redis `6379`, Centrifugo `8001`, RustFS `9000` (консоль `9001`).
  Номера меняются переменными `DEV_*_PORT` в `.env`.

На стенде в `.env` задаются `COMPOSE_FILE=compose.yaml` (без
override), `CAMPUS_ENVIRONMENT=production`, домены и новые секреты.
Порты наружу открывает только Caddy (80, 443 TCP и UDP).

## Конфигурация и секреты

Все параметры и секреты — в `infra/.env` (в репозиторий не попадает),
шаблон с пояснениями — `.env.example`. Секреты подставляются в compose
через `${VAR:?}`: без `.env` или с пустым секретом запуск
останавливается с ошибкой. Значения в `.env.example` годятся только для
разработки; на сервере каждый секрет генерируется заново, например
`openssl rand -hex 32`.

Переменные `CAMPUS_*` передаются процессам сервера (полный список —
`backend/.env.example`); адрес БД `CAMPUS_DATABASE_URL` собирается из
`POSTGRES_*`.

## Образ сервера

`backend/Dockerfile` — многоэтапная сборка на uv: зависимости ставятся
строго по `uv.lock` без dev-группы, в итоговом образе — Python, окружение
и исходники, процесс работает от непривилегированного пользователя
`campus` (UID 10001). Один образ для API, миграций, а позже — воркера и
планировщика; процесс задаёт команда. Тег образа —
`CAMPUS_BACKEND_IMAGE` (по умолчанию `campus-backend:local`, собирается
из `backend/`).
