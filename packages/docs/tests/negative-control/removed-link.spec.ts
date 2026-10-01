import { test } from "@playwright/test";
import { readBootstrapGuide } from "../../e2e/reader-journey";

test("removed homepage link is rejected by the real reader journey", async ({ page }) => {
  await page.route("**/", async (route) => {
    const response = await route.fetch();
    const body = (await response.text()).replaceAll(
      /<a\b[^>]*href="\/guides\/getting-started\/"[^>]*>[\s\S]*?<\/a>/g,
      "",
    );
    await route.fulfill({ response, body });
  });
  await readBootstrapGuide(page);
});
