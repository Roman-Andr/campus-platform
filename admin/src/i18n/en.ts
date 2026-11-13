/** Application-specific UI strings (react-admin's own strings come from ra-language-*). */
export const en = {
  app: {
    title: 'Campus admin',
    login: {
      title: 'Sign in',
      stub: 'Sign-in with a one-time code and a second factor is not implemented yet.',
      continue: 'Continue',
    },
    dashboard: {
      title: 'Welcome',
      description: 'Campus administration panel. Sections will appear here as they are built.',
    },
    apiStatus: {
      menu: 'API status',
      title: 'API status',
      checking: 'Checking…',
      ok: 'API is available',
      unavailable: 'API is unavailable: %{error}',
      retry: 'Check again',
    },
  },
};

type Strings<T> = { [K in keyof T]: T[K] extends string ? string : Strings<T[K]> };

/** Shape every locale must implement, so a missing key is a type error. */
export type AppMessages = Strings<typeof en>;
