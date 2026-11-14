# Веб-панель администратора

React + TypeScript + [react-admin](https://marmelab.com/react-admin/),
сборка — Vite. Работает поверх того же REST API, что и клиенты
(ТЗ п. 4.6, 5.5.2).

## Запуск

Нужна Node.js из `.nvmrc` (LTS 26): `fnm use` или `nvm use`.

```sh
npm ci
cp .env.example .env.local   # при необходимости поменять адрес API
npm run dev                  # http://localhost:5173, /api проксируется на API_PROXY_TARGET
```

Вход пока заглушка: «Продолжить» открывает локальную сессию; вход по
коду и второй фактор — issue #97. Язык (RU/EN) переключается в
верхней панели и на странице входа и запоминается в браузере.

## Команды

| Команда                 | Что делает                                      |
| ----------------------- | ----------------------------------------------- |
| `npm run lint`          | ESLint (typescript-eslint, строгий режим)       |
| `npm run typecheck`     | Проверка типов TypeScript                       |
| `npm run format`        | Prettier                                        |
| `npm test`              | Тесты компонентов и провайдеров (Vitest, jsdom) |
| `npm run test:coverage` | То же с покрытием, порог — 80 %                 |
| `npm run build`         | Проверка типов и сборка в `dist/`               |
| `npm run e2e`           | Playwright по собранной панели                  |

Перед первым `npm run e2e`: `npx playwright install --with-deps chromium`.

## Типы API

Из `admin/` (нужны Node 26 и `uv`):

```sh
npm run api:generate
npm run api:check
```

Генератор запускает `uv run --frozen python` в `backend/`, получает
`openapi.json` в памяти через `create_app(...).openapi()` и генерирует
`src/api/schema.ts` с помощью `openapi-typescript`. Сервер, PostgreSQL и
локальный `.env` не нужны. Сгенерированный файл хранится в Git и вручную
не редактируется. После изменения API запустите генерацию и включите
результат в PR. Workflow `Admin API types` проверяет расхождение на
изменениях как `admin/`, так и `backend/`.

`openapi-typescript` 7 объявляет peer dependency TypeScript 5; override
использует TypeScript 6 проекта. Совместимость проверяется генерацией,
проверкой расхождений и `npm run typecheck`.

`VITE_CLIENT_VERSION` задаёт семантическую версию сборки (по умолчанию
`0.0.0`); при выпуске задавайте актуальную версию. Каждый запрос передаёт
`X-Client-Platform: admin` и `X-Client-Version`. Ответ 426 с кодом
`client_update_required` показывает в панели сообщение RU/EN с минимальной
версией и кнопкой перезагрузки.

HTTP-клиент один раз повторяет запрос после сетевого сбоя, сохраняя тело
и тот же UUID `Idempotency-Key`. HTTP-ошибки и отменённые запросы не
повторяются. Новый вызов провайдера — новая операция с новым ключом;
явно переданный ключ сохраняется.

## Устройство

- `src/providers/httpClient.ts` — общие заголовки (`Accept-Language`
  по языку интерфейса, `Idempotency-Key` у изменяющих запросов) и разбор
  ошибок Problem Details (RFC 9457) в `HttpError`: сообщение — `detail`,
  в `body` — машинный `code` и ошибки полей для форм.
- `src/providers/dataProvider.ts` — провайдер данных с курсорной
  пагинацией: `GET /<ресурс>?size=&cursor=&order_by=&<фильтры>` →
  `{ items, next_page }`. Номера страниц react-admin
  сопоставляются с курсорами, переход сразу на N-ю страницу проходит
  предыдущие. Справочники #34 возвращают целиком `{ items }` — такой
  ответ считается последней страницей. Сейчас в OpenAPI нет курсорного
  endpoint: общий адаптер `CursorPage` описывает протокол #26. Типы
  справочников и Problem Details берутся из сгенерированной схемы.
- `src/providers/authProvider.ts` — заглушка входа.
- `src/i18n/` — строки интерфейса RU/EN; строки самого react-admin — из
  `ra-language-*`, недостающие в русском пакете берутся из английского.
