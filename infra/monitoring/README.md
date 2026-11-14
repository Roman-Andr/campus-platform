# Испытательные метрики

API, worker и scheduler имеют собственный `GET /metrics` на отдельном
порту. Это внутренний интерфейс эксплуатации, вне OpenAPI бизнес-API;
клиенты и Idempotency-Key не меняются. Prometheus использует pull, его
недоступность не вызывает сетевых обращений из бизнес-запросов.

По умолчанию listener выключен (`CAMPUS_METRICS_PORT` не задан).
`CAMPUS_METRICS_HOST=127.0.0.1`. В основном Compose включён порт 9001
на контейнерном интерфейсе, **без публикации на хост**. Caddy направляет
только `/api/*` на бизнес-порт 8000, поэтому `/metrics` снаружи недоступен.
Доступ имеют доверенные участники сетей Compose. Не подключайте к этим
сетям недоверенные контейнеры и не публикуйте 9001 на публичном адресе.
При запуске вне Compose используйте loopback либо закрытую сеть с firewall.

Один процесс — один registry и один target. Не запускайте несколько
uvicorn workers в одном контейнере и не используйте общий
`PROMETHEUS_MULTIPROC_DIR`: файлов состояния нет, рестарт начинает
локальные counters с нуля; Prometheus `rate` учитывает такие сбросы.
Реплики API/worker опрашиваются отдельно по их адресам, без балансировщика.

## Имена и единицы

| Имя | Тип / единица | Метки / смысл |
| --- | --- | --- |
| `campus_process_uptime_seconds` | gauge / s | `process`: api, worker, scheduler |
| `campus_http_request_duration_seconds` | histogram / s | `method`, `route` (шаблон), `status` (HTTP-код); только API |
| `campus_task_enqueued_total` | counter / сообщения | `task`: зарегистрированное имя или unknown; отправленные Taskiq сообщения |
| `campus_task_executions_total` | counter / попытки | `task`, `status`: success/error; только исполнение Taskiq |
| `campus_jobs` | gauge / строки | `queue`: outbox/deadlines; `state`: pending/processed/failed |
| `campus_job_oldest_pending_age_seconds` | gauge / s | `queue`; от created_at старейшей незавершённой строки, включая backoff |
| `campus_deadline_overdue_seconds` | gauge / s | max(0, now − min(original due_at)) для pending сроков |
| `campus_task_queue_messages` | gauge / сообщения | `state`: waiting (ещё не доставлены группе), pending (доставлены, не ACK) |
| `campus_task_queue_oldest_age_seconds` | gauge / s | от времени в старейшем необработанном Redis Stream ID |

`campus_jobs`, возраст и очередь экспортируются **только scheduler**.
Это снимки общего состояния, не суммируйте их между репликами scheduler:
при нескольких scheduler используйте `max`, либо назначьте один scrape-target.
`processed` — число сохранённых завершённых строк, а не число попыток и
не all-time counter. Retention уменьшает его. Параллельные worker и
повторная доставка Taskiq не добавляют второй успешный доменный job.
Taskiq success означает завершение запуска, а не успешную доменную операцию.

Pending исключает окончательно failed и processed; возраст и просрочка
пустой очереди равны нулю. Исходный due_at сохраняется при retry и меняется
при явном перепланировании. Для старых строк миграция использует available_at:
исходный срок уже выполненных до миграции retry восстановить нельзя.
Невыполненные сроки в будущем имеют нулевую просрочку.

Redis: размер — lag группы campus-worker + PEL, **не XLEN** (он включает ACK).
Возраст учитывает и недоставленные, и доставленные без ACK сообщения.
Повторная доставка не добавляет новую PEL-запись. Обрезание потока может
удалить ещё недоставленные данные; это ограничение существующего broker,
метрики не восстанавливают потерянные сообщения. При неизвестном lag или
ошибке БД/Redis scrape возвращает 503 Problem Details, а не старые/нулевые
значения. Сбор ограничен `CAMPUS_METRICS_SCRAPE_TIMEOUT` (3 s).

Гистограмма экспортирует `_bucket`, `_sum`, `_count`. Buckets в секундах:
`0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.15, 0.2, 0.3, 0.5, 1, 2.5, 5, +Inf`.
Настройка: `CAMPUS_METRICS_HTTP_BUCKETS` (JSON-массив строго возрастающих
положительных чисел). Границы 0.15 и 0.3 проверяют цели чтения/записи ТЗ.
Длительность включает streaming; исключения дают status=500. Неизвестные
пути сводятся в `unmatched`, произвольные методы — в `OTHER`.
Ни ID, ни query, ни payload, email, токены, тексты исключений не становятся
метками; темы outbox и deadline вообще не экспортируются.

```promql
# p95 чтения по маршруту
histogram_quantile(0.95, sum by (le, route) (
  rate(campus_http_request_duration_seconds_bucket{method="GET"}[5m])
))
# p95 записи: сравнить с 0.3 s
histogram_quantile(0.95, sum by (le, route) (
  rate(campus_http_request_duration_seconds_bucket{method=~"POST|PUT|PATCH|DELETE"}[5m])
))
# Доля HTTP 5xx
sum(rate(campus_http_request_duration_seconds_count{status=~"5.."}[5m]))
/ sum(rate(campus_http_request_duration_seconds_count[5m]))
max(campus_deadline_overdue_seconds)
sum(campus_task_queue_messages)
```

## Пробный запуск с внешней машины

На стенде включите loopback-порты (основной Compose без dev override):

```sh
cd infra
docker compose -f compose.yaml -f compose.metrics.yaml up -d
```

На Linux-машине испытателя откройте SSH-туннель:

```sh
ssh -N -L 19001:127.0.0.1:19001 -L 19002:127.0.0.1:19002 \
  -L 19003:127.0.0.1:19003 user@staging-host
```

В другом терминале этой машины, из копии репозитория:

```sh
cd infra/monitoring
export GRAFANA_ADMIN_PASSWORD='replace-with-a-trial-password'
docker compose up -d
```

Prometheus: http://127.0.0.1:9090/targets — три UP targets.
Grafana: http://127.0.0.1:3000 — admin и заданный пароль; datasource уже
настроен. В Explore используйте запросы выше. Искусственно задержите
обработку deadline/outbox: возраст и просрочка растут; после обработки
падают до нуля. После испытаний `docker compose down` в monitoring,
закройте туннель и уберите overlay с портами на стенде. Постоянного
Prometheus/Grafana в основном Compose нет.
