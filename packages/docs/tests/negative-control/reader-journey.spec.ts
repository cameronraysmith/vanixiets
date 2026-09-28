import { test } from "@playwright/test";
import { readBootstrapGuide } from "../../e2e/reader-journey";

test("damaged guide is rejected by the real reader journey", async ({ page }) => {
  await page.route("**/guides/getting-started/", async (route) => {
    const response = await route.fetch();
    const body = (await response.text()).replaceAll("Getting started", "Guide unavailable");
    await route.fulfill({ response, body });
  });
  await readBootstrapGuide(page);
});
