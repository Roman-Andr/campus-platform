import type { AppMessages } from './en';

export const ru: AppMessages = {
  app: {
    title: 'Кампус: администрирование',
    login: {
      title: 'Вход',
      stub: 'Вход по одноразовому коду и второй фактор пока не реализованы.',
      continue: 'Продолжить',
    },
    dashboard: {
      title: 'Добро пожаловать',
      description: 'Панель администратора «Кампуса». Разделы появятся здесь по мере разработки.',
    },
    apiStatus: {
      menu: 'Состояние API',
      title: 'Состояние API',
      checking: 'Проверка…',
      ok: 'API доступен',
      unavailable: 'API недоступен: %{error}',
      retry: 'Проверить снова',
    },
  },
};
