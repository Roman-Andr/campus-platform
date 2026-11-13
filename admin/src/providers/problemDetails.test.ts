import { fieldErrors, isProblemDetails, problemMessage } from './problemDetails';

describe('isProblemDetails', () => {
  it('accepts objects with standard or code members', () => {
    expect(isProblemDetails({ title: 'Not Found', status: 404 })).toBe(true);
    expect(isProblemDetails({ code: 'item_reserved' })).toBe(true);
    expect(isProblemDetails({ type: 'about:blank' })).toBe(true);
  });

  it('rejects anything else', () => {
    expect(isProblemDetails(undefined)).toBe(false);
    expect(isProblemDetails('error')).toBe(false);
    expect(isProblemDetails([])).toBe(false);
    expect(isProblemDetails({ message: 'oops' })).toBe(false);
  });
});

describe('problemMessage', () => {
  it('prefers detail, then title, then the fallback', () => {
    expect(problemMessage({ title: 'Conflict', detail: 'Item already booked' }, 'x')).toBe(
      'Item already booked',
    );
    expect(problemMessage({ title: 'Conflict' }, 'x')).toBe('Conflict');
    expect(problemMessage({ code: 'conflict' }, 'x')).toBe('x');
  });
});

describe('fieldErrors', () => {
  it('maps invalid-params and JSON pointers to react-admin field names', () => {
    expect(
      fieldErrors({
        'invalid-params': [{ name: 'email', reason: 'Invalid address' }],
        errors: [
          { pointer: '#/name', detail: 'Required' },
          { pointer: '/body/address/city', detail: 'Too long' },
          { field: 'age', message: 'Must be positive' },
        ],
      }),
    ).toEqual({
      email: 'Invalid address',
      name: 'Required',
      'address.city': 'Too long',
      age: 'Must be positive',
    });
  });

  it('returns undefined when there are no usable field errors', () => {
    expect(fieldErrors({ title: 'Bad Request' })).toBeUndefined();
    expect(fieldErrors({ errors: [{ pointer: '/name' }] })).toBeUndefined();
  });
});
