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
