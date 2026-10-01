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
 * without raising. The screencast is encoded outside that path and still
 * shows the page, so for WebKit this fixture keeps the latest screencast frame
 * and, only when Playwright's own failure screenshot is empty, writes that
 * frame into the same attachment as PNG. When Playwright produces a real
 * screenshot, it is left untouched. If no painted frame exists, the teardown
 * throws: the attempt then fails closed as infrastructure instead of carrying
 * an empty or blank image.
 */
export const test = base.extend<{ webkitFailureScreenshot: undefined }>({
  webkitFailureScreenshot: [
    async ({ page, browserName }, use, testInfo) => {
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
      const empty = testInfo.attachments.flatMap(({ name, path }) =>
        name === "screenshot" && path && statSync(path).size === 0 ? [path] : [],
      );
      if (empty.length > 0) {
        const deadline = Date.now() + settleDeadlineMs;
        while (Date.now() < deadline && Date.now() - (latest?.at ?? 0) < quietMs) await sleep(50);
      }
      if (!page.isClosed()) await page.screencast.stop();
      if (empty.length === 0) return;
      if (frames < 2 || !latest) {
        throw new Error(`WebKit wrote an empty failure screenshot and no painted screencast frame exists: ${empty}`);
      }
      // Loaded only on this repair path: sharp is a native addon, and the
      // engines whose own screenshots work never need to load it.
      const { default: sharp } = await import("sharp");
      const png = await sharp(latest.data).png().toBuffer();
      for (const path of empty) writeFileSync(path, png);
    },
    { auto: true },
  ],
});
