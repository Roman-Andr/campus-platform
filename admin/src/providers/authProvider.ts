import type { AuthProvider } from 'react-admin';

const SESSION_KEY = 'campus-admin.stub-session';

/**
 * Placeholder until sign-in with a one-time code and TOTP is built
 * (issue #97): "Continue" on the login page opens a local session.
 * It grants nothing: every API call is still authorized by the server.
 */
export const authProvider: AuthProvider = {
  login: () => {
    localStorage.setItem(SESSION_KEY, '1');
    return Promise.resolve();
  },
  logout: () => {
    localStorage.removeItem(SESSION_KEY);
    return Promise.resolve();
  },
  checkAuth: () =>
    localStorage.getItem(SESSION_KEY) === '1' ? Promise.resolve() : Promise.reject(new Error()),
  // 403 means "not allowed to do this", not "signed out": stay logged in.
  checkError: (error: { status?: number }) =>
    error.status === 401 ? Promise.reject(new Error()) : Promise.resolve(),
};
