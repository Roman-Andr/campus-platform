// Источники списка литературы после ГОСТов (раздел 10).
// Номер источника = 13 (число ГОСТов в 10-literature.typ) + позиция в словаре.
// В тексте: #lit("avito") -> [15]; #lit("avito", "youdo") -> [15, 16].
#let accessed = "13.11.26"
#let gost_count = 13

#let web(title, url) = [#title. Электронный ресурс. URL: #link(url) (дата обращения #accessed)]

#let refs = (
  fz152: [Федеральный закон от 27.07.2006 № 152-ФЗ «О персональных данных». Электронный ресурс. URL: #link("https://www.consultant.ru/document/cons_doc_LAW_61801/") (дата обращения #accessed)],
  // Аналоги модулей
  avito: web([Авито -- сервис объявлений], "https://www.avito.ru/"),
  youdo: web([YouDo -- сервис поиска исполнителей], "https://youdo.com/"),
  timepad: web([Timepad -- сервис регистрации на мероприятия], "https://timepad.ru/"),
  splitwise: web([Splitwise -- сервис учёта совместных расходов], "https://www.splitwise.com/"),
  nextdoor: web([Nextdoor -- соседская социальная сеть], "https://nextdoor.com/"),
  // Проекты ФКН и сервисы ВШЭ
  wisedubs: web([Мобильное приложение для организации студенческой жизни в общежитии (WiseDubs). Лучшие проекты студентов ФКН НИУ ВШЭ], "https://cs.hse.ru/cppr/best_projects/dorm_life_app"),
  droplet: web([Приложение для обмена товарами «Droplet». Лучшие проекты студентов ФКН НИУ ВШЭ], "https://cs.hse.ru/cppr/best_projects/barter_exchange"),
  events_app: web([Клиент-серверное приложение для помощи в организации мероприятий. Лучшие проекты студентов ФКН НИУ ВШЭ], "https://cs.hse.ru/cppr/best_projects/events_app"),
  cstati: web([Система регистрации и управления жизненным циклом мероприятий «CSTATI». Лучшие проекты студентов ФКН НИУ ВШЭ], "https://cs.hse.ru/cppr/best_projects/event_lifecycle_management"),
  hseapp: web([Мобильное приложение HSE App X], "https://istudents.hse.ru/mobileapp"),
  smarthostel: web([SmartHostel НИУ ВШЭ], "https://smarthostel.hse.ru/"),
  // Документация технологий (vision.md, блок 6)
  python: web([Официальная документация Python], "https://docs.python.org/3/"),
  fastapi: web([Официальная документация FastAPI], "https://fastapi.tiangolo.com/"),
  sqlalchemy: web([Официальная документация SQLAlchemy 2], "https://docs.sqlalchemy.org/en/20/"),
  alembic: web([Официальная документация Alembic], "https://alembic.sqlalchemy.org/"),
  pydantic: web([Официальная документация Pydantic], "https://docs.pydantic.dev/"),
  pydantic_ai: web([Официальная документация Pydantic AI], "https://ai.pydantic.dev/"),
  taskiq: web([Официальная документация Taskiq], "https://taskiq-python.github.io/"),
  postgresql: web([Официальная документация PostgreSQL], "https://www.postgresql.org/docs/"),
  pgvector: web([pgvector -- поиск по векторному сходству для PostgreSQL], "https://github.com/pgvector/pgvector"),
  redis: web([Официальная документация Redis], "https://redis.io/docs/"),
  centrifugo: web([Официальная документация Centrifugo], "https://centrifugal.dev/docs/"),
  flutter: web([Официальная документация Flutter], "https://docs.flutter.dev/"),
  riverpod: web([Официальная документация Riverpod], "https://riverpod.dev/"),
  drift: web([Официальная документация Drift], "https://drift.simonbinder.eu/"),
  go_router: web([Пакет go\_router], "https://pub.dev/packages/go_router"),
  react: web([Официальная документация React], "https://react.dev/"),
  refine: web([Официальная документация Refine], "https://refine.dev/docs/"),
  react_admin: web([Официальная документация react-admin], "https://marmelab.com/react-admin/"),
  docker: web([Официальная документация Docker Compose], "https://docs.docker.com/compose/"),
  caddy: web([Официальная документация Caddy], "https://caddyserver.com/docs/"),
  traefik: web([Официальная документация Traefik], "https://doc.traefik.io/traefik/"),
  minio: web([Официальная документация MinIO], "https://min.io/docs/"),
  gha: web([Документация GitHub Actions], "https://docs.github.com/actions"),
  sentry: web([Документация Sentry SDK], "https://docs.sentry.io/"),
  glitchtip: web([Документация GlitchTip], "https://glitchtip.com/documentation"),
  prometheus: web([Официальная документация Prometheus], "https://prometheus.io/docs/"),
  grafana: web([Официальная документация Grafana], "https://grafana.com/docs/"),
  pytest: web([Официальная документация pytest], "https://docs.pytest.org/"),
  testcontainers: web([Документация Testcontainers for Python], "https://testcontainers-python.readthedocs.io/"),
  schemathesis: web([Документация Schemathesis], "https://schemathesis.readthedocs.io/"),
  playwright: web([Официальная документация Playwright], "https://playwright.dev/"),
  locust: web([Официальная документация Locust], "https://docs.locust.io/"),
  import_linter: web([Документация Import Linter], "https://import-linter.readthedocs.io/"),
  fcm: web([Документация Firebase Cloud Messaging], "https://firebase.google.com/docs/cloud-messaging"),
  tg_bot: web([Telegram Bot API], "https://core.telegram.org/bots/api"),
  tg_miniapp: web([Telegram Mini Apps], "https://core.telegram.org/bots/webapps"),
  openapi: web([OpenAPI Specification], "https://spec.openapis.org/oas/latest.html"),
  wcag: web([Web Content Accessibility Guidelines (WCAG) 2.1. W3C Recommendation], "https://www.w3.org/TR/WCAG21/"),
  rfc8032: web([RFC 8032. Edwards-Curve Digital Signature Algorithm (EdDSA)], "https://www.rfc-editor.org/rfc/rfc8032"),
  rfc6238: web([RFC 6238. TOTP: Time-Based One-Time Password Algorithm], "https://www.rfc-editor.org/rfc/rfc6238"),
  rfc9562: web([RFC 9562. Universally Unique IDentifiers (UUIDs)], "https://www.rfc-editor.org/rfc/rfc9562"),
  conv_commits: web([Conventional Commits 1.0.0], "https://www.conventionalcommits.org/ru/v1.0.0/"),
)

#let lit(..keys) = {
  let names = refs.keys()
  let nums = keys.pos().map(k => {
    let i = names.position(x => x == k)
    assert(i != none, message: "Неизвестный источник: " + k)
    str(gost_count + i + 1)
  })
  "[" + nums.join(", ") + "]"
}
