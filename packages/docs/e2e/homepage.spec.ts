import { expect, test } from "@playwright/test";

test.describe("Homepage", () => {
  test("has correct title and heading", async ({ page }) => {
    await page.goto("/");

    // Verify page title
    await expect(page).toHaveTitle(/vanixiets/);

    // Verify main heading
    const heading = page.locator("h1").first();
    await expect(heading).toBeVisible();
  });

  test("has accessible links", async ({ page }) => {
    await page.goto("/");

    // Verify GitHub link exists and is accessible (using first to handle multiple matches)
    const githubLink = page.getByRole("link", { name: /github/i }).first();
    await expect(githubLink).toBeVisible();
    await expect(githubLink).toHaveAttribute("href", /.+/);
  });

  test("navigates to getting started guide", async ({ page }) => {
    await page.goto("/");

    // Find and click the Getting started link (using first to handle multiple matches)
    const guideLink = page.getByRole("link", { name: /getting started/i }).first();
    await guideLink.click();

    // Verify navigation occurred
    await expect(page).toHaveURL(/\/guides\/getting-started/);
  });

  test("is responsive on mobile", async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto("/");

    // Page should still be functional
    await expect(page.locator("h1").first()).toBeVisible();
  });

  test("loads without console errors", async ({ page }) => {
    const errors: string[] = [];

    page.on("console", (msg) => {
      if (msg.type() === "error") {
        errors.push(msg.text());
      }
    });

    await page.goto("/");

    // Wait for page to fully load
    await page.waitForLoadState("networkidle");

    // Check for console errors
    expect(errors).toHaveLength(0);
  });
});
