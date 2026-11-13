import { en } from './en';
import { i18nProvider, initialLocale, locales } from '.';
import { ru } from './ru';

const keys = (messages: object, prefix = ''): string[] =>
  Object.entries(messages).flatMap(([key, value]) =>
    typeof value === 'object' && value !== null
      ? keys(value as object, `${prefix}${key}.`)
      : [`${prefix}${key}`],
  );

const setBrowserLanguage = (language: string) => {
  vi.spyOn(window.navigator, 'language', 'get').mockReturnValue(language);
  vi.spyOn(window.navigator, 'languages', 'get').mockReturnValue([language]);
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe('i18n', () => {
  it('offers Russian and English', () => {
    expect(locales.map((l) => l.locale)).toEqual(['ru', 'en']);
    expect(i18nProvider.getLocales?.()).toEqual(locales);
  });

  it('has the same keys and no empty strings in both languages', () => {
    expect(keys(ru).sort()).toEqual(keys(en).sort());
    for (const key of keys(ru)) {
      expect(i18nProvider.translate(key), key).not.toBe('');
    }
  });

  it('translates app and react-admin strings in the current locale', async () => {
    await i18nProvider.changeLocale('ru');
    expect(i18nProvider.translate('app.login.title')).toBe('Вход');
    expect(i18nProvider.translate('ra.action.save')).toBe('Сохранить');

    await i18nProvider.changeLocale('en');
    expect(i18nProvider.translate('app.login.title')).toBe('Sign in');
    expect(i18nProvider.translate('ra.action.save')).toBe('Save');
  });

  it('falls back to English for react-admin keys missing from the Russian pack', async () => {
    // ra-language-russian has no `ra.guesser.*` strings.
    const key = 'ra.guesser.empty.title';
    await i18nProvider.changeLocale('en');
    const english = i18nProvider.translate(key);
    await i18nProvider.changeLocale('ru');
    expect(english).not.toBe(key);
    expect(i18nProvider.translate(key)).toBe(english);
  });

  it.each([
    ['ru-RU', 'ru'],
    ['en-GB', 'en'],
    ['de-DE', 'ru'],
  ])('picks the initial locale from browser language %s', (browser, expected) => {
    setBrowserLanguage(browser);
    expect(initialLocale()).toBe(expected);
  });
});
