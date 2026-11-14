import { expect, test } from '@playwright/test';

test('login stub opens the dashboard and the language switches', async ({ page }) => {
  await page.goto('/');

  // Browser locale is ru-RU, so the panel starts in Russian.
  await expect(page.getByRole('heading', { name: 'Вход' })).toBeVisible();

  await page.getByRole('button', { name: 'Русский' }).click();
  await page.getByRole('menuitem', { name: 'English' }).click();
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible();

  await page.getByRole('button', { name: 'Continue' }).click();
  await expect(page.getByRole('heading', { name: 'Welcome' })).toBeVisible();
  await expect(page.getByRole('menuitem', { name: 'API status' })).toBeVisible();

  // The choice survives a reload.
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Welcome' })).toBeVisible();
});

test('outdated panel shows a reload notice in both languages', async ({ page }) => {
  await page.route('**/api/v1/health', async (route) => {
    const headers = route.request().headers();
    expect(headers['x-client-platform']).toBe('admin');
    expect(headers['x-client-version']).toMatch(/^\d+\.\d+\.\d+/);
    await route.fulfill({
      status: 426,
      contentType: 'application/problem+json',
      body: JSON.stringify({
        type: 'urn:problem:campus:client_update_required',
        title: 'Update required',
        status: 426,
        code: 'client_update_required',
        min_version: '1.2.0',
      }),
    });
  });
  await page.goto('/');
  await page.getByRole('button', { name: 'Продолжить' }).click();
  await page.getByRole('menuitem', { name: 'Состояние API' }).click();
  await expect(page.getByRole('button', { name: 'Перезагрузить панель' })).toBeVisible();
  await expect(page.getByText('Минимальная версия: 1.2.0.', { exact: false })).toBeVisible();
  await page.getByRole('button', { name: 'Русский' }).click();
  await page.getByRole('menuitem', { name: 'English' }).click();
  await expect(page.getByRole('button', { name: 'Reload panel' })).toBeVisible();
  await expect(page.getByText('Minimum version: 1.2.0.', { exact: false })).toBeVisible();
});
