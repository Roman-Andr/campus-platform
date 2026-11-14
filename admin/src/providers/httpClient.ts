import { config } from '../config';
import { reportClientUpdate } from './clientUpdate';
import { fetchUtils, HttpError } from 'react-admin';
import { fieldErrors, isProblemDetails, problemMessage } from './problemDetails';

export interface HttpResponse {
  status: number;
  headers: Headers;
  body: string;
  /** Parsed body; validate or cast at the call site. */
  json: unknown;
}

export type HttpClient = (url: string, options?: fetchUtils.Options) => Promise<HttpResponse>;

export interface HttpClientOptions {
  /** Current UI language, sent as `Accept-Language` so server messages match it. */
  getLocale: () => string;
  /** Generates `Idempotency-Key` values; defaults to `crypto.randomUUID`. */
  newIdempotencyKey?: () => string;
}

const MUTATING_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

/**
 * `fetchJson` with the headers every Campus API call needs and with
 * Problem Details errors turned into react-admin `HttpError`s:
 * `message` is the server's localized detail, `body.errors` holds field
 * errors for forms, `body.code` the machine-readable error code.
 */
export const createHttpClient =
  ({ getLocale, newIdempotencyKey = () => crypto.randomUUID() }: HttpClientOptions): HttpClient =>
  async (url, options = {}) => {
    const headers = new Headers(options.headers);
    headers.set('Accept', 'application/json, application/problem+json');
    headers.set('Accept-Language', getLocale());
    headers.set('X-Client-Platform', 'admin');
    headers.set('X-Client-Version', config.clientVersion);
    const method = (options.method ?? 'GET').toUpperCase();
    if (MUTATING_METHODS.has(method) && !headers.has('Idempotency-Key')) {
      headers.set('Idempotency-Key', newIdempotencyKey());
    }
    try {
      try {
        return await fetchUtils.fetchJson(url, { ...options, headers });
      } catch (error) {
        // A fetch network failure has no HTTP response. Retry once, keeping
        // the prepared headers and body, including the operation's UUID.
        if (!(error instanceof TypeError) || options.signal?.aborted) throw error;
        return await fetchUtils.fetchJson(url, { ...options, headers });
      }
    } catch (error) {
      if (error instanceof HttpError && isProblemDetails(error.body)) {
        const problem = error.body;
        if (error.status === 426 && problem.code === 'client_update_required') {
          reportClientUpdate(problem.min_version ?? null);
        }
        throw new HttpError(problemMessage(problem), error.status, {
          ...problem,
          errors: fieldErrors(problem),
        });
      }
      throw error;
    }
  };
