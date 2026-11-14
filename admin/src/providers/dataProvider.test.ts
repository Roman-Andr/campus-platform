import type { DataProvider, GetListParams } from 'react-admin';
import { createDataProvider, type CursorPage } from './dataProvider';
import type { components } from '../api/schema';
import type { HttpClient, HttpResponse } from './httpClient';

const API = 'https://api.test/api/v1';

const response = (json: unknown): HttpResponse => ({
  status: 200,
  headers: new Headers(),
  body: JSON.stringify(json),
  json,
});

/** Five records `{ id: 1..5 }`, two per page, cursors `c2`, `c3`. */
const pages: Record<string, CursorPage> = {
  '': { items: [{ id: 1 }, { id: 2 }], next_page: 'c2' },
  c2: { items: [{ id: 3 }, { id: 4 }], next_page: 'c3' },
  c3: { items: [{ id: 5 }], next_page: null },
};

let httpClient: ReturnType<typeof vi.fn<HttpClient>>;
let provider: DataProvider;

const requested = (call: number) => {
  const [url, options] = httpClient.mock.calls[call] ?? [];
  const parsed = new URL(url ?? '');
  return { path: parsed.pathname, query: parsed.searchParams, options };
};

const listParams = (page: number, extra: Partial<GetListParams> = {}): GetListParams => ({
  pagination: { page, perPage: 2 },
  sort: { field: 'created_at', order: 'DESC' },
  filter: {},
  ...extra,
});

beforeEach(() => {
  httpClient = vi.fn<HttpClient>((url) => {
    const cursor = new URL(url).searchParams.get('cursor') ?? '';
    return Promise.resolve(response(pages[cursor] ?? { items: [] }));
  });
  provider = createDataProvider({ apiUrl: API, httpClient });
});

describe('getList', () => {
  it('requests the first page with size, sort and filters', async () => {
    const result = await provider.getList(
      'users',
      listParams(1, { filter: { role: ['admin', 'moderator'], q: 'ann' } }),
    );

    expect(result.data).toEqual([{ id: 1 }, { id: 2 }]);
    expect(result.pageInfo).toEqual({ hasNextPage: true, hasPreviousPage: false });
    expect(result.total).toBeUndefined();
    const { path, query } = requested(0);
    expect(path).toBe('/api/v1/users');
    expect(query.get('size')).toBe('2');
    expect(query.get('order_by')).toBe('-created_at');
    expect(query.getAll('role')).toEqual(['admin', 'moderator']);
    expect(query.get('q')).toBe('ann');
    expect(query.has('cursor')).toBe(false);
  });

  it('sorts ascending without a minus sign and omits an empty sort', async () => {
    await provider.getList('users', listParams(1, { sort: { field: 'name', order: 'ASC' } }));
    await provider.getList('users', listParams(1, { sort: { field: '', order: 'ASC' } }));

    expect(requested(0).query.get('order_by')).toBe('name');
    expect(requested(1).query.has('order_by')).toBe(false);
  });

  it('uses the remembered cursor for the next page', async () => {
    await provider.getList('users', listParams(1));
    const result = await provider.getList('users', listParams(2));

    expect(result.data).toEqual([{ id: 3 }, { id: 4 }]);
    expect(result.pageInfo).toEqual({ hasNextPage: true, hasPreviousPage: true });
    expect(httpClient).toHaveBeenCalledTimes(2);
    expect(requested(1).query.get('cursor')).toBe('c2');
  });

  it('walks forward to a page whose cursor is not known yet', async () => {
    const result = await provider.getList('users', listParams(3));

    expect(result.data).toEqual([{ id: 5 }]);
    expect(result.pageInfo).toEqual({ hasNextPage: false, hasPreviousPage: true });
    expect(httpClient.mock.calls.map((_, i) => requested(i).query.get('cursor'))).toEqual([
      null,
      'c2',
      'c3',
    ]);
  });

  it('returns an empty page past the end of the list', async () => {
    const result = await provider.getList('users', listParams(5));

    expect(result.data).toEqual([]);
    expect(result.pageInfo).toEqual({ hasNextPage: false, hasPreviousPage: true });
    expect(httpClient).toHaveBeenCalledTimes(3);
  });

  it('keeps separate cursors per filter', async () => {
    await provider.getList('users', listParams(1));
    await provider.getList('users', listParams(2, { filter: { role: 'admin' } }));

    expect(httpClient).toHaveBeenCalledTimes(3);
    expect(requested(1).query.has('cursor')).toBe(false);
    expect(requested(2).query.get('cursor')).toBe('c2');
  });

  it('accepts the unpaginated university response and defaults to page 1', async () => {
    const cities: components['schemas']['CityList'] = {
      items: [
        {
          id: 'f9342dee-182e-4260-bd71-70ccdf51fb33',
          code: 'moscow',
          name: 'Moscow',
          timezone: 'Europe/Moscow',
        },
      ],
    };
    httpClient.mockResolvedValueOnce(response(cities));

    const result = await provider.getList<components['schemas']['CityOut']>('university/cities', {
      filter: {},
    });

    expect(result.data[0]?.id).toBe('f9342dee-182e-4260-bd71-70ccdf51fb33');
    expect(result.pageInfo?.hasNextPage).toBe(false);
    expect(result.total).toBeUndefined();
    expect(requested(0).query.get('size')).toBe('25');
  });

  it('forwards the abort signal', async () => {
    const signal = new AbortController().signal;
    await provider.getList('users', listParams(1, { signal }));

    expect(requested(0).options).toEqual({ signal });
  });
});

describe('single-record methods', () => {
  it('getOne fetches by encoded id', async () => {
    httpClient.mockResolvedValueOnce(response({ id: 'a/b', name: 'Ann' }));

    const result = await provider.getOne('users', { id: 'a/b' });

    expect(result.data).toEqual({ id: 'a/b', name: 'Ann' });
    expect(requested(0).path).toBe('/api/v1/users/a%2Fb');
  });

  it('getMany fetches each id', async () => {
    httpClient.mockImplementation((url) =>
      Promise.resolve(response({ id: Number(url.split('/').pop()) })),
    );

    const result = await provider.getMany('users', { ids: [1, 2] });

    expect(result.data).toEqual([{ id: 1 }, { id: 2 }]);
  });

  it('getManyReference filters the list by the target field', async () => {
    await provider.getManyReference('bookings', {
      target: 'user_id',
      id: 7,
      pagination: { page: 1, perPage: 2 },
      sort: { field: 'id', order: 'ASC' },
      filter: { status: 'active' },
    });

    const { path, query } = requested(0);
    expect(path).toBe('/api/v1/bookings');
    expect(query.get('user_id')).toBe('7');
    expect(query.get('status')).toBe('active');
  });

  it('create POSTs the data', async () => {
    httpClient.mockResolvedValueOnce(response({ id: 9, name: 'Ann' }));

    const result = await provider.create('users', { data: { name: 'Ann' } });

    expect(result.data).toEqual({ id: 9, name: 'Ann' });
    expect(requested(0).options).toEqual({ method: 'POST', body: '{"name":"Ann"}' });
  });

  it('update PATCHes the record', async () => {
    httpClient.mockResolvedValueOnce(response({ id: 9, name: 'Bob' }));

    const result = await provider.update('users', {
      id: 9,
      data: { name: 'Bob' },
      previousData: { id: 9, name: 'Ann' },
    });

    expect(result.data).toEqual({ id: 9, name: 'Bob' });
    expect(requested(0).path).toBe('/api/v1/users/9');
    expect(requested(0).options).toEqual({ method: 'PATCH', body: '{"name":"Bob"}' });
  });

  it('updateMany PATCHes every id', async () => {
    const result = await provider.updateMany('users', { ids: [1, 2], data: { active: false } });

    expect(result.data).toEqual([1, 2]);
    expect(httpClient.mock.calls.map(([url, options]) => [url, options?.method])).toEqual([
      [`${API}/users/1`, 'PATCH'],
      [`${API}/users/2`, 'PATCH'],
    ]);
  });

  it('delete returns the deleted record, or previousData on 204', async () => {
    httpClient.mockResolvedValueOnce(response({ id: 1, name: 'Ann' }));
    const withBody = await provider.delete('users', { id: 1 });
    expect(withBody.data).toEqual({ id: 1, name: 'Ann' });

    httpClient.mockResolvedValueOnce(response(undefined));
    const noContent = await provider.delete('users', { id: 2, previousData: { id: 2, x: 1 } });
    expect(noContent.data).toEqual({ id: 2, x: 1 });

    httpClient.mockResolvedValueOnce(response(undefined));
    const bare = await provider.delete('users', { id: 3 });
    expect(bare.data).toEqual({ id: 3 });
    expect(requested(2).options).toEqual({ method: 'DELETE' });
  });

  it('deleteMany DELETEs every id', async () => {
    const result = await provider.deleteMany('users', { ids: [1, 2] });

    expect(result.data).toEqual([1, 2]);
    expect(httpClient).toHaveBeenCalledTimes(2);
  });
});
