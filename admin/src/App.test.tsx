import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { App } from './App';
import { en } from './i18n/en';
import { ru } from './i18n/ru';

/**
 * The locale menu button has an empty aria-label, so find it by its text
 * (the closed menu is kept mounted and shows the same names in items).
 */
const localeButton = async (name: string): Promise<HTMLElement> => {
  const buttons = (await screen.findAllByText(name))
    .map((element) => element.closest('button'))
    .filter((button) => button !== null);
  if (buttons.length !== 1 || !buttons[0]) {
    throw new Error(
      `Expected one locale button showing "${name}", found ${String(buttons.length)}`,
    );
  }
  return buttons[0];
};

const switchLocale = async (from: string, to: string) => {
  const user = userEvent.setup();
  await user.click(await localeButton(from));
  await user.click(await screen.findByRole('menuitem', { name: to }));
};

describe('App', () => {
  beforeEach(() => {
    window.history.replaceState(null, '', '/');
  });

  it('shows the login stub and switches between English and Russian', async () => {
    render(<App />);

    // jsdom reports en-US, so the panel starts in English.
    expect(await screen.findByRole('heading', { name: en.app.login.title })).toBeInTheDocument();
    expect(screen.getByText(en.app.login.stub)).toBeInTheDocument();

    await switchLocale('English', 'Русский');
    expect(await screen.findByRole('heading', { name: ru.app.login.title })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: ru.app.login.continue })).toBeInTheDocument();

    await switchLocale('Русский', 'English');
    expect(await screen.findByRole('heading', { name: en.app.login.title })).toBeInTheDocument();
  });

  it('opens the dashboard after the stub sign-in, in the chosen language', async () => {
    const user = userEvent.setup();
    render(<App />);

    await switchLocale('English', 'Русский');
    await user.click(await screen.findByRole('button', { name: ru.app.login.continue }));

    expect(
      await screen.findByRole('heading', { name: ru.app.dashboard.title }),
    ).toBeInTheDocument();
    // react-admin's own strings are translated too.
    expect(screen.getAllByText('Главная').length).toBeGreaterThan(0);
    const menuItem = screen.getByRole('menuitem', { name: ru.app.apiStatus.menu });
    expect(menuItem).toHaveAttribute('href', '#/api-status');
  });
});
