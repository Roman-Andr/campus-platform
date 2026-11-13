import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AdminContext, HttpError } from 'react-admin';
import { i18nProvider } from '../i18n';
import { en } from '../i18n/en';
import type { HttpClient } from '../providers/httpClient';
import { ApiStatusPage } from './ApiStatusPage';

const renderPage = (httpClient: HttpClient) =>
  render(
    <AdminContext i18nProvider={i18nProvider}>
      <ApiStatusPage httpClient={httpClient} />
    </AdminContext>,
  );

describe('ApiStatusPage', () => {
  it('reports an available API', async () => {
    const httpClient = vi.fn<HttpClient>().mockResolvedValue({
      status: 200,
      headers: new Headers(),
      body: '{"status":"ok"}',
      json: { status: 'ok' },
    });

    renderPage(httpClient);

    expect(await screen.findByText(en.app.apiStatus.ok)).toBeInTheDocument();
    expect(httpClient.mock.calls[0]?.[0]).toBe('/api/v1/health');
  });

  it('shows the error and checks again on request', async () => {
    const httpClient = vi
      .fn<HttpClient>()
      .mockRejectedValue(new HttpError('Service Unavailable', 503));

    renderPage(httpClient);

    expect(await screen.findByText('API is unavailable: Service Unavailable')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: en.app.apiStatus.retry }));
    expect(httpClient).toHaveBeenCalledTimes(2);
  });
});
