import { statSync, writeFileSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { test as base } from "@playwright/test";

export { expect } from "@playwright/test";

// Screencast frames trail the paint that produced them by roughly 150 ms in
// Playwright's WebKit. Waiting for a quiet interval lets a paint that landed
// just before the failure arrive; the deadline bounds a page that keeps
// animating.
const quietMs = 500;
const settleDeadlineMs = 5000;

/**
 * Every browser spec imports `test` from here so failed WebKit attempts keep a
 * real screenshot.
 *
 * Playwright's WebKit `page.screenshot()` encodes in the sandboxed WebContent
 * process, which resolves `image/png` through LaunchServices. The macOS Nix
 * build users (`_nixbld*`) have no LaunchServices database, so ImageIO gets an
 * empty type identifier, WebKit answers `Page.snapshotRect` with `data:,`, and
 * Playwright 1.63 writes the empty buffer as a 0-byte `test-failed-1.png`
 * without raising. Playwright also swallows an on-failure `page.screenshot()`
 * that throws, such as one that outlives its fixed 5 s timeout on a loaded
 * builder, and then attaches no screenshot at all (nixbot build 2878, x86_64-linux).
 * The screencast is encoded outside that path and still shows the page, so for
 * WebKit this fixture keeps the latest screencast frame and, only when a failed
 * attempt's screenshot is empty or missing, writes that frame as PNG into the
 * attachment Playwright wrote or would have written. When Playwright produces a
 * real screenshot, it is left untouched. If no painted frame exists, the
 * teardown throws: the attempt then fails closed as infrastructure instead of
 * carrying no, an empty, or a blank image.
 */
export const test = base.extend<{ webkitFailureScreenshot: undefined }>({
  webkitFailureScreenshot: [
    async ({ page, browserName, screenshot }, use, testInfo) => {
      if (browserName !== "webkit") {
        await use(undefined);
        return;
      }
      // The first frame after start is a placeholder emitted before the page
      // has painted; only a later frame shows page content.
      let frames = 0;
      let latest: { data: Buffer; at: number } | undefined;
      await page.screencast.start({
        onFrame: ({ data }) => {
          frames++;
          latest = { data, at: Date.now() };
        },
      });
      await use(undefined);
      const screenshots = testInfo.attachments.filter(({ name }) => name === "screenshot");
      const empty = screenshots.flatMap(({ path }) => (path && statSync(path).size === 0 ? [path] : []));
      // Playwright's own on-failure capture, which runs before fixture teardown.
      const mode = typeof screenshot === "string" ? screenshot : screenshot.mode;
      const failed = testInfo.status !== "skipped" && testInfo.status !== testInfo.expectedStatus;
      const expected =
        failed && (mode === "on" || mode === "only-on-failure" || (mode === "on-first-failure" && testInfo.retry === 0));
      // Playwright's name for the first failure screenshot of an attempt.
      const missing = expected && screenshots.length === 0 ? testInfo.outputPath("test-failed-1.png") : undefined;
      const repair = missing ? [...empty, missing] : empty;
      if (repair.length > 0) {
        const deadline = Date.now() + settleDeadlineMs;
        while (Date.now() < deadline && Date.now() - (latest?.at ?? 0) < quietMs) await sleep(50);
      }
      if (!page.isClosed()) await page.screencast.stop();
      if (repair.length === 0) return;
      if (frames < 2 || !latest) {
        throw new Error(
          `WebKit wrote an empty or no failure screenshot and no painted screencast frame exists (${frames} frames): ${repair}`,
        );
      }
      // Loaded only on this repair path: sharp is a native addon, and the
      // engines whose own screenshots work never need to load it.
      const { default: sharp } = await import("sharp");
      const png = await sharp(latest.data).png().toBuffer();
      for (const path of repair) writeFileSync(path, png);
      if (missing) testInfo.attachments.push({ name: "screenshot", path: missing, contentType: "image/png" });
    },
    { auto: true },
  ],
});
