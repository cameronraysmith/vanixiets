import { expect, type Page } from "@playwright/test";

export async function readBootstrapGuide(page: Page) {
  await page.goto("/");
  await page
    .getByRole("link", { name: /getting started/i })
    .first()
    .click();
  await expect(page).toHaveURL(/\/guides\/getting-started\/?$/);
  await expect(page.getByRole("heading", { level: 1, name: "Getting started", exact: true })).toBeVisible();
  const toc = page.locator("starlight-toc").getByRole("navigation", { name: /on this page/i });
  await toc.getByRole("link", { name: "Prerequisites", exact: true }).click();
  await expect(page).toHaveURL(/#prerequisites$/);
  await expect(page.getByRole("heading", { name: "Prerequisites", exact: true })).toBeInViewport();
  await expect(page.getByText("Physical access or SSH access to the target machine", { exact: true })).toBeVisible();
  await page.locator("main").getByRole("link", { name: "Reading paths", exact: true }).click();
  await expect(page).toHaveURL(/\/guides\/reading-paths\/?$/);
  await expect(page.getByRole("heading", { level: 1, name: "Reading paths", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Path 1: First-time bootstrap", exact: true })).toBeVisible();
}
