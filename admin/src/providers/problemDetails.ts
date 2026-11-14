import type { components } from '../api/schema';

export type ProblemDetails = components['schemas']['Problem'];

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const isProblemDetails = (value: unknown): value is ProblemDetails =>
  isRecord(value) &&
  typeof value.type === 'string' &&
  typeof value.title === 'string' &&
  typeof value.status === 'number' &&
  typeof value.code === 'string';

/** Decode a server JSON pointer into a react-admin form field path. */
const fieldName = (pointer: string): string =>
  pointer
    .replace(/^#?\//, '')
    .split('/')
    .map((part) => part.replace(/~1/g, '/').replace(/~0/g, '~'))
    .join('.');

export const fieldErrors = (problem: ProblemDetails): Record<string, string> | undefined => {
  const result: Record<string, string> = {};
  for (const error of problem.errors ?? []) {
    // Query parameters and headers are not fields of a submitted form.
    if (error.pointer?.startsWith('#/')) {
      result[fieldName(error.pointer)] = error.detail;
    }
  }
  return Object.keys(result).length > 0 ? result : undefined;
};

export const problemMessage = (problem: ProblemDetails): string => problem.detail ?? problem.title;
