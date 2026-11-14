import { HttpError } from 'react-admin';
import { config } from '../config';
import { createHttpClient } from './httpClient';

const fetchMock = vi.fn<typeof fetch>();

const jsonResponse = (body: unknown, status = 200, contentType = 'application/json') =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': contentType } });

const sentHeaders = (): Headers => {
  const init = fetchMock.mock.calls[0]?.[1];
  return new Headers(init?.headers);
};

const client = createHttpClient({ getLocale: () => 'en', newIdempotencyKey: () => 'key-1' });

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('createHttpClient', () => {
  it('sends Accept-Language and no Idempotency-Key on reads', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ ok: true }));

    const { json } = await client('/api/v1/health');

    expect(json).toEqual({ ok: true });
    expect(sentHeaders().get('Accept-Language')).toBe('en');
    expect(sentHeaders().get('X-Client-Platform')).toBe('admin');
    expect(sentHeaders().get('X-Client-Version')).toBe(config.clientVersion);
    expect(sentHeaders().get('Accept')).toContain('application/problem+json');
    expect(sentHeaders().has('Idempotency-Key')).toBe(false);
  });

  it.each(['POST', 'PUT', 'PATCH', 'DELETE'])('adds Idempotency-Key to %s', async (method) => {
    fetchMock.mockResolvedValue(jsonResponse({}));

    await client('/api/v1/items', { method, body: '{}' });

    expect(sentHeaders().get('Idempotency-Key')).toBe('key-1');
  });

  it('keeps an Idempotency-Key set by the caller', async () => {
    fetchMock.mockResolvedValue(jsonResponse({}));

    await client('/api/v1/items', { method: 'POST', headers: { 'Idempotency-Key': 'retry-7' } });

    expect(sentHeaders().get('Idempotency-Key')).toBe('retry-7');
  });

  it('defaults to a random UUID key', async () => {
    fetchMock.mockResolvedValue(jsonResponse({}));

    await createHttpClient({ getLocale: () => 'ru' })('/api/v1/items', { method: 'POST' });

    expect(sentHeaders().get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('turns Problem Details into an HttpError with message, code and field errors', async () => {
    fetchMock.mockResolvedValue(
      jsonResponse(
        {
          type: 'https://campus.example/problems/validation',
          title: 'Validation failed',
          status: 422,
          detail: 'Check the highlighted fields',
          code: 'validation_failed',
          errors: [{ pointer: '#/title', detail: 'Required', code: 'missing' }],
        },
        422,
        'application/problem+json',
      ),
    );

    const error = await client('/api/v1/items', { method: 'POST' }).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(HttpError);
    const httpError = error as HttpError;
    expect(httpError.message).toBe('Check the highlighted fields');
    expect(httpError.status).toBe(422);
    expect(httpError.body).toMatchObject({
      code: 'validation_failed',
      errors: { title: 'Required' },
    });
  });

  it('passes non-Problem errors through unchanged', async () => {
    fetchMock.mockResolvedValue(new Response('Bad gateway', { status: 502, statusText: 'Bad' }));

    const error = await client('/api/v1/health').catch((e: unknown) => e);

    expect(error).toBeInstanceOf(HttpError);
    expect((error as HttpError).status).toBe(502);
    expect((error as HttpError).message).toBe('Bad');
  });
});

it.each(['POST', 'PUT', 'PATCH', 'DELETE'])(
  'retries %s with the same UUID after connection loss',
  async (method) => {
    const newKey = vi.fn(() => crypto.randomUUID());
    fetchMock
      .mockRejectedValueOnce(new TypeError('Failed to fetch'))
      .mockResolvedValueOnce(jsonResponse({ id: 1 }));
    await createHttpClient({ getLocale: () => 'ru', newIdempotencyKey: newKey })('/api/v1/items', {
      method,
      body: '{}',
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(newKey).toHaveBeenCalledTimes(1);
    const keys = fetchMock.mock.calls.map(([, init]) =>
      new Headers(init?.headers).get('Idempotency-Key'),
    );
    expect(keys[0]).toMatch(/^[0-9a-f-]{36}$/);
    expect(keys[1]).toBe(keys[0]);
    expect(fetchMock.mock.calls[1]?.[1]?.body).toBe('{}');
  },
);

it('stops after one network retry', async () => {
  fetchMock.mockRejectedValue(new TypeError('Failed to fetch'));
  await expect(client('/api/v1/items', { method: 'POST' })).rejects.toThrow('Failed to fetch');
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

it('does not retry an aborted request', async () => {
  const controller = new AbortController();
  controller.abort();
  fetchMock.mockRejectedValue(new DOMException('Aborted', 'AbortError'));
  await expect(
    client('/api/v1/items', { method: 'POST', signal: controller.signal }),
  ).rejects.toThrow('Aborted');
  expect(fetchMock).toHaveBeenCalledTimes(1);
});
