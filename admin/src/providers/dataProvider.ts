import {
  fetchUtils,
  type DataProvider,
  type CreateParams,
  type DeleteParams,
  type GetListParams,
  type GetListResult,
  type GetManyParams,
  type Identifier,
  type RaRecord,
  type UpdateParams,
} from 'react-admin';
import type { HttpClient } from './httpClient';

/**
 * One page of a cursor-paginated list, as returned by `GET /<resource>`.
 * Request: `?size=<n>&cursor=<opaque>&order_by=<field|-field>&<filters>`.
 */
export interface CursorPage<T = unknown> {
  items: T[];
  /** Cursor of the next page; absent or `null` on the last page. */
  next_page?: string | null;
}

export interface DataProviderOptions {
  apiUrl: string;
  httpClient: HttpClient;
}

type Cursor = string | null;

/**
 * react-admin addresses list pages by number while the API uses opaque
 * cursors. For each list query (resource + sort + filter + page size) the
 * provider remembers the cursor of every page it has reached; a page whose
 * cursor is unknown yet (e.g. a deep link to page 3) is reached by walking
 * forward from the closest known page.
 */
class CursorCache {
  private readonly pages = new Map<string, Cursor[]>();

  /** Cursors of pages 1..n; page 1 needs no cursor. */
  get(key: string): Cursor[] {
    return this.pages.get(key) ?? [null];
  }

  set(key: string, cursors: Cursor[]): void {
    this.pages.set(key, cursors);
  }
}

const listKey = (resource: string, params: GetListParams, perPage: number): string =>
  JSON.stringify([resource, perPage, params.sort ?? null, params.filter ?? {}]);

const orderBy = (params: GetListParams): string | undefined => {
  const sort = params.sort;
  if (!sort?.field) {
    return undefined;
  }
  return sort.order === 'DESC' ? `-${sort.field}` : sort.field;
};

export const DEFAULT_PAGE_SIZE = 25;

export const createDataProvider = ({ apiUrl, httpClient }: DataProviderOptions): DataProvider => {
  const cursors = new CursorCache();
  const resourceUrl = (resource: string, id?: Identifier): string =>
    id === undefined
      ? `${apiUrl}/${resource}`
      : `${apiUrl}/${resource}/${encodeURIComponent(String(id))}`;

  const fetchPage = async (
    resource: string,
    params: GetListParams,
    perPage: number,
    cursor: Cursor,
  ): Promise<CursorPage> => {
    const filter = (params.filter ?? {}) as Record<string, unknown>;
    const query: Record<string, unknown> = { ...filter, size: perPage };
    const order = orderBy(params);
    if (order) {
      query.order_by = order;
    }
    if (cursor !== null) {
      query.cursor = cursor;
    }
    const { json } = await httpClient(
      `${resourceUrl(resource)}?${fetchUtils.queryParameters(query)}`,
      { signal: params.signal },
    );
    return json as CursorPage;
  };

  const getList = async <RecordType extends RaRecord>(
    resource: string,
    params: GetListParams,
  ): Promise<GetListResult<RecordType>> => {
    const page = Math.max(1, params.pagination?.page ?? 1);
    const perPage = params.pagination?.perPage ?? DEFAULT_PAGE_SIZE;
    const key = listKey(resource, params, perPage);
    const known = [...cursors.get(key)];

    let current = Math.min(page, known.length);
    for (;;) {
      const result = await fetchPage(resource, params, perPage, known[current - 1] ?? null);
      const next = result.next_page ?? null;
      known.length = current;
      if (next !== null) {
        known.push(next);
      }
      cursors.set(key, known);

      if (current === page || next === null) {
        const reached = current === page;
        return {
          data: (reached ? result.items : []) as RecordType[],
          pageInfo: { hasNextPage: reached && next !== null, hasPreviousPage: page > 1 },
        };
      }
      current += 1;
    }
  };

  const getOne = async <RecordType extends RaRecord>(
    resource: string,
    id: Identifier,
    signal?: AbortSignal,
  ): Promise<RecordType> => {
    const { json } = await httpClient(resourceUrl(resource, id), { signal });
    return json as RecordType;
  };

  const update = async <RecordType extends RaRecord>(
    resource: string,
    id: Identifier,
    data: unknown,
  ): Promise<RecordType> => {
    const { json } = await httpClient(resourceUrl(resource, id), {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
    return json as RecordType;
  };

  const remove = async (resource: string, id: Identifier): Promise<unknown> => {
    const { json } = await httpClient(resourceUrl(resource, id), { method: 'DELETE' });
    return json;
  };

  return {
    getList,

    getOne: async (resource, params) => ({
      data: await getOne(resource, params.id, params.signal),
    }),

    getMany: async <RecordType extends RaRecord>(
      resource: string,
      params: GetManyParams<RecordType>,
    ) => ({
      data: await Promise.all(
        params.ids.map((id) => getOne<RecordType>(resource, id, params.signal)),
      ),
    }),

    getManyReference: (resource, params) =>
      getList(resource, {
        pagination: params.pagination,
        sort: params.sort,
        filter: { ...(params.filter as Record<string, unknown>), [params.target]: params.id },
        signal: params.signal,
      }),

    create: async <RecordType extends RaRecord>(
      resource: string,
      params: CreateParams<RecordType>,
    ) => {
      const { json } = await httpClient(resourceUrl(resource), {
        method: 'POST',
        body: JSON.stringify(params.data),
      });
      return { data: json as RecordType };
    },

    update: async <RecordType extends RaRecord>(
      resource: string,
      params: UpdateParams<RecordType>,
    ) => ({
      data: await update<RecordType>(resource, params.id, params.data),
    }),

    updateMany: async (resource, params) => {
      await Promise.all(params.ids.map((id: Identifier) => update(resource, id, params.data)));
      return { data: params.ids };
    },

    delete: async <RecordType extends RaRecord>(
      resource: string,
      params: DeleteParams<RecordType>,
    ) => {
      const json = await remove(resource, params.id);
      // 204 No Content: fall back to the record react-admin already has.
      return { data: (json ?? params.previousData ?? { id: params.id }) as RecordType };
    },

    deleteMany: async (resource, params) => {
      await Promise.all(params.ids.map((id: Identifier) => remove(resource, id)));
      return { data: params.ids };
    },
  };
};
