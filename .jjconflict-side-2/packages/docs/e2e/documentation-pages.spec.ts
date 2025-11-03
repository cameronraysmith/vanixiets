import { expect, test } from "@playwright/test";

test.describe("Documentation Pages", () => {
  test("has sidebar navigation on getting started guide page", async ({ page }) => {
    // Set desktop viewport to ensure sidebar is visible (hidden on mobile)
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto("/guides/getting-started/");

    // Verify sidebar navigation exists by checking for navigation items within it
    const sidebar = page.locator('nav[aria-label="Main"]');
    await expect(sidebar).toBeAttached();
    await expect(sidebar.getByText("Guides")).toBeVisible();
  });

  test("sidebar contains configured navigation items", async ({ page }) => {
    // Set desktop viewport to ensure sidebar is visible (hidden on mobile)
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto("/guides/getting-started/");

    // Verify sidebar contains the Guides section
    const sidebar = page.locator('nav[aria-label="Main"]');
    await expect(sidebar.getByText("Guides")).toBeVisible();
    await expect(sidebar.getByText("Getting started")).toBeVisible();
  });

  test("has table of contents on desktop", async ({ page }) => {
    // Set desktop viewport for right sidebar TOC
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto("/guides/getting-started/");

    // Verify right sidebar with table of contents exists
    const toc = page.getByRole("navigation", { name: /on this page/i });
    await expect(toc).toBeVisible();
  });
});
