import { test, expect } from '@playwright/test'

// Signed out, the app opens on the sign-in page.
test('shows the sign-in page when signed out', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('h1')).toHaveText('Agdayo')
  await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible()
})
