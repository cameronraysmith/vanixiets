import { test } from "@playwright/test";
import { readBootstrapGuide } from "./reader-journey";

test("reader finds bootstrap prerequisites and a guided reading path", async ({ page }) => {
  await readBootstrapGuide(page);
});
