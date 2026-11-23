import { expect, test } from "./fixtures";

test.describe("Agent affordances", () => {
  test("robots.txt, llms.txt and a page's Markdown twin are served and linked", async ({ page, request }) => {
    const robots = await request.get("/robots.txt");
    expect(robots.status()).toBe(200);
    const robotsBody = await robots.text();
    expect(robotsBody).toMatch(/^Sitemap: https:\/\/\S+\/sitemap-index\.xml$/m);
    expect(robotsBody).not.toMatch(/^Disallow:/im);

    const llms = await request.get("/llms.txt");
    expect(llms.status()).toBe(200);
    expect(await llms.text()).toMatch(/^# \S/);

    await page.goto("/guides/getting-started/");
    const alternate = page.locator('head link[rel="alternate"][type="text/markdown"]');
    await expect(alternate).toHaveAttribute("href", "/guides/getting-started.md");

    const twin = await request.get("/guides/getting-started.md");
    expect(twin.status()).toBe(200);
    expect(twin.headers()["content-type"]).toMatch(/^text\/markdown/);
    expect(await twin.text()).toMatch(/^---\ntitle: /);
  });
});
