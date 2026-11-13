import polyglotI18nProvider from 'ra-i18n-polyglot';
import englishMessages from 'ra-language-english';
import russianMessages from 'ra-language-russian';
import { mergeTranslations, resolveBrowserLocale, type TranslationMessages } from 'react-admin';
import { en } from './en';
import { ru } from './ru';

export const locales = [
  { locale: 'ru', name: 'Русский' },
  { locale: 'en', name: 'English' },
] as const;

export type AppLocale = (typeof locales)[number]['locale'];

export const defaultLocale: AppLocale = 'ru';

const isAppLocale = (locale: string): locale is AppLocale =>
  locales.some((item) => item.locale === locale);

// ra-language-russian lags behind react-admin, so English fills in missing keys.
const messages: Record<AppLocale, TranslationMessages> = {
  en: mergeTranslations(englishMessages, en) as TranslationMessages,
  ru: mergeTranslations(englishMessages, russianMessages, ru) as TranslationMessages,
};

/** Browser language if supported, otherwise Russian. */
export const initialLocale = (): AppLocale => {
  const browser = resolveBrowserLocale(defaultLocale);
  return isAppLocale(browser) ? browser : defaultLocale;
};

export const i18nProvider = polyglotI18nProvider(
  (locale) => messages[isAppLocale(locale) ? locale : defaultLocale],
  initialLocale(),
  locales,
);
