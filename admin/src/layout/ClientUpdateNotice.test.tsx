import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AdminContext } from 'react-admin';
import englishMessages from 'ra-language-english';
import polyglotI18nProvider from 'ra-i18n-polyglot';
import { en } from '../i18n/en';
import { ru } from '../i18n/ru';
import { createHttpClient } from '../providers/httpClient';
import { ClientUpdateNotice } from './ClientUpdateNotice';

it.each([
  ['en', en],
  ['ru', ru],
] as const)('shows a reload action on a real 426 response in %s', async (locale, messages) => {
  const reload = vi.fn();
  const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
    new Response(
      JSON.stringify({
        type: 'urn:problem:campus:client_update_required',
        title: 'Update required',
        status: 426,
        code: 'client_update_required',
        min_version: '1.2.0',
      }),
      { status: 426, headers: { 'Content-Type': 'application/problem+json' } },
    ),
  );
  vi.stubGlobal('fetch', fetchMock);
  const client = createHttpClient({ getLocale: () => locale });
  try {
    render(
      <AdminContext
        i18nProvider={polyglotI18nProvider(() => ({ ...englishMessages, ...messages }), locale)}
      >
        <ClientUpdateNotice reload={reload} />
      </AdminContext>,
    );
    await act(async () => {
      await expect(client('/api/v1/university/cities')).rejects.toMatchObject({ status: 426 });
    });
    expect(
      await screen.findByText(new RegExp(messages.app.clientUpdate.message)),
    ).toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('1.2.0');
    await userEvent.click(screen.getByRole('button', { name: messages.app.clientUpdate.reload }));
    expect(reload).toHaveBeenCalledOnce();
    expect(fetchMock).toHaveBeenCalledOnce();
  } finally {
    vi.unstubAllGlobals();
  }
});
