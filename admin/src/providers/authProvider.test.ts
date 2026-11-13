import { authProvider } from './authProvider';

describe('stub authProvider', () => {
  it('is signed out until login and after logout', async () => {
    await expect(authProvider.checkAuth({})).rejects.toThrow();

    await authProvider.login({});
    await expect(authProvider.checkAuth({})).resolves.toBeUndefined();

    await authProvider.logout({});
    await expect(authProvider.checkAuth({})).rejects.toThrow();
  });

  it('signs out only on 401', async () => {
    await expect(authProvider.checkError({ status: 401 })).rejects.toThrow();
    await expect(authProvider.checkError({ status: 403 })).resolves.toBeUndefined();
    await expect(authProvider.checkError({ status: 500 })).resolves.toBeUndefined();
  });
});
