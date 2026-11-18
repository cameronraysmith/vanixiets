import { expect, test } from "./fixtures";
import { expectTopologyText, pagePath, topologyNames, viewPath, views } from "./fleet-topology";

test.describe("Fleet topology", () => {
  test("fleet topology page loads", async ({ page }) => {
    const response = await page.goto(pagePath);
    expect(response?.status()).toBe(200);
    await expect(page.getByRole("heading", { level: 1, name: "Fleet topology", exact: true })).toBeVisible();
    await expect(page.getByText("declared facts are true only as the operator last recorded them")).toBeVisible();
    // The generated table is page text, so every host is findable on the page.
    const table = page.locator("main table").first();
    for (const machine of topologyNames().machines) {
      await expect(table.getByRole("cell", { name: machine, exact: true })).toBeVisible();
    }
  });

  test("both fleet topology diagrams load", async ({ page }) => {
    await page.goto(pagePath);
    for (const view of views) {
      const image = page.locator(`main img[src="${viewPath(view)}"]`);
      await expect(image).toBeVisible();
      expect(await image.getAttribute("alt")).toMatch(/^Fleet topology .+/);
      const naturalWidth = await image.evaluate((img: HTMLImageElement) => img.naturalWidth);
      expect(naturalWidth, `${viewPath(view)} has no intrinsic width`).toBeGreaterThan(0);
      const { status, type, size } = await page.evaluate(async (path) => {
        const response = await fetch(path);
        return {
          status: response.status,
          type: response.headers.get("content-type") ?? "",
          size: (await response.arrayBuffer()).byteLength,
        };
      }, viewPath(view));
      expect(status).toBe(200);
      expect(type).toContain("image/svg+xml");
      expect(size).toBeGreaterThan(0);
    }
  });

  test("every host and network in fleet.json is text in the diagrams", async ({ page, browserName }, testInfo) => {
    await page.goto(pagePath);
    await expectTopologyText(page);
    // One engine's picture is enough for a reviewer, and WebKit screenshots
    // are empty in the Nix build (tests/report/README.md). These attachments
    // are evidence for the browser-evidence comment, not an assertion. Each
    // view is drawn alone, 1600 px wide, rather than scaled to the page's
    // content column; its own size (the placement view is 6700 px wide) makes
    // a full-page screenshot of the SVG document exceed the action timeout.
    if (browserName !== "chromium") return;
    await page.setViewportSize({ width: 1600, height: 900 });
    for (const view of views) {
      const path = testInfo.outputPath(`view-${view}.png`);
      await page.setContent(`<img id="view" src="${viewPath(view)}" style="display:block;width:1600px">`);
      const image = page.locator("#view");
      await expect.poll(() => image.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth)).toBeTruthy();
      await image.screenshot({ path });
      await testInfo.attach(`view-${view}`, { path, contentType: "image/png" });
    }
  });
});
