import { expect, test } from "./fixtures";

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

    // A visible h1 does not show that the page fits: an oversized hero once
    // widened the document past the device, cutting off the logo and header.
    const heroImg = page.locator(".hero img");
    await expect(heroImg).toBeVisible();
    const layout = await heroImg.evaluate((img) => {
      const rect = img.getBoundingClientRect();
      return {
        scrollWidth: document.documentElement.scrollWidth,
        clientWidth: document.documentElement.clientWidth,
        heroLeft: rect.left,
        heroRight: rect.right,
      };
    });
    expect(layout.clientWidth, "layout viewport width").toBeLessThanOrEqual(375);
    expect(layout.scrollWidth, "document must not scroll horizontally").toBeLessThanOrEqual(layout.clientWidth);
    expect(layout.heroLeft, "hero image left edge").toBeGreaterThanOrEqual(0);
    expect(layout.heroRight, "hero image right edge").toBeLessThanOrEqual(layout.clientWidth);
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

  test("hero image loads successfully", async ({ page }) => {
    await page.goto("/");
    const heroImg = page.locator(".hero img");
    await expect(heroImg).toBeVisible();
    const naturalWidth = await heroImg.evaluate((img: HTMLImageElement) => img.naturalWidth);
    expect(naturalWidth).toBeGreaterThan(0);
  });
});
