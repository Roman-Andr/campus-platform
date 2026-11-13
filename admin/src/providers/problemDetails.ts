/**
 * Problem Details for HTTP APIs (RFC 9457) as returned by the Campus API:
 * the standard members plus a machine-readable `code` and, for validation
 * failures, per-field messages.
 */
export interface ProblemDetails {
  type?: string;
  title?: string;
  status?: number;
  detail?: string;
  instance?: string;
  /** Machine-readable error code, stable across languages. */
  code?: string;
  /** Validation errors: RFC 9457 `invalid-params` style. */
  'invalid-params'?: { name: string; reason: string }[];
  /** Validation errors: JSON-pointer style. */
  errors?: { pointer?: string; field?: string; detail?: string; message?: string }[];
  [extension: string]: unknown;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const isProblemDetails = (value: unknown): value is ProblemDetails =>
  isRecord(value) &&
  (typeof value.title === 'string' ||
    typeof value.detail === 'string' ||
    typeof value.code === 'string' ||
    typeof value.type === 'string');

/** Turns `/data/attributes/name`, `/name` or `name` into react-admin's `name`. */
const fieldName = (pointer: string): string =>
  pointer
    .replace(/^#?\//, '')
    .replace(/^(body|data)\//, '')
    .split('/')
    .join('.');

/**
 * Field errors in the shape react-admin forms expect
 * (`{ errors: { field: message } }`), or `undefined` when there are none.
 */
export const fieldErrors = (problem: ProblemDetails): Record<string, string> | undefined => {
  const result: Record<string, string> = {};
  for (const param of problem['invalid-params'] ?? []) {
    result[fieldName(param.name)] = param.reason;
  }
  for (const error of problem.errors ?? []) {
    const name = error.pointer ?? error.field;
    const message = error.detail ?? error.message;
    if (name && message) {
      result[fieldName(name)] = message;
    }
  }
  return Object.keys(result).length > 0 ? result : undefined;
};

/** Human-readable message: `detail` (already localized by the server), then `title`. */
export const problemMessage = (problem: ProblemDetails, fallback: string): string =>
  problem.detail ?? problem.title ?? fallback;
