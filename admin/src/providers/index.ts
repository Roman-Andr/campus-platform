import { config } from '../config';
import { i18nProvider } from '../i18n';
import { createDataProvider } from './dataProvider';
import { createHttpClient } from './httpClient';

export { authProvider } from './authProvider';

export const httpClient = createHttpClient({ getLocale: () => i18nProvider.getLocale() });

export const dataProvider = createDataProvider({ apiUrl: config.apiUrl, httpClient });
