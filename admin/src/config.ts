/** Runtime settings taken from the Vite environment (see `.env.example`). */
export const config = {
  clientVersion: import.meta.env.VITE_CLIENT_VERSION ?? '0.0.0',
  /** Base URL of the REST API, without a trailing slash. */
  apiUrl: (import.meta.env.VITE_API_URL ?? '/api/v1').replace(/\/+$/, ''),
} as const;
