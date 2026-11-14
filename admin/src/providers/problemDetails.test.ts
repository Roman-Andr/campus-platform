import type { ProblemDetails } from './problemDetails';
import { fieldErrors, isProblemDetails, problemMessage } from './problemDetails';

const problem: ProblemDetails = {
  type: 'urn:problem:campus:validation_failed',
  title: 'Invalid request',
  status: 422,
  code: 'validation_failed',
  detail: null,
};

it('recognizes the server Problem envelope', () => {
  expect(isProblemDetails(problem)).toBe(true);
  for (const value of [undefined, 'error', [], { message: 'oops' }, { code: 'bad_request' }]) {
    expect(isProblemDetails(value)).toBe(false);
  }
});

it('uses detail, then title', () => {
  expect(problemMessage({ ...problem, detail: 'Check fields' })).toBe('Check fields');
  expect(problemMessage(problem)).toBe('Invalid request');
});

it('decodes server pointers and ignores parameter and header errors for forms', () => {
  expect(
    fieldErrors({
      ...problem,
      errors: [
        { pointer: '#/address/city', code: 'missing', detail: 'Required' },
        { pointer: '#/a~1b/~0name', code: 'missing', detail: 'Required' },
        { parameter: 'size', code: 'greater_than', detail: 'Too small' },
        { header: 'Idempotency-Key', code: 'missing', detail: 'Required' },
      ],
    }),
  ).toEqual({ 'address.city': 'Required', 'a/b.~name': 'Required' });
  expect(fieldErrors(problem)).toBeUndefined();
  expect(fieldErrors({ ...problem, errors: null })).toBeUndefined();
});
