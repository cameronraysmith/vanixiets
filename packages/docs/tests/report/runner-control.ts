import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { isAbsolute, join, relative } from "node:path";
import type { TestContext } from "node:test";
import { fileURLToPath } from "node:url";
import type { Completion } from "./completion-reporter.ts";

const require = createRequire(import.meta.url);
const playwright = require.resolve("@playwright/test");
const cli = require.resolve("@playwright/test/cli");
const reporter = fileURLToPath(new URL("./completion-reporter.ts", import.meta.url));
const fixtures = fileURLToPath(new URL("../../e2e/fixtures.ts", import.meta.url));

export type ControlMode =
  | "action"
  | "assertion"
  | "hook"
  | "hook-assertion"
  | "deadline"
  | "worker"
  | "closed-page"
  | "launch"
  | "global"
  | "empty"
  // A WebKit product failure, through e2e/fixtures.ts, whose on-failure
  // `page.screenshot()` fails, so Playwright attaches no screenshot at all.
  | "webkit-missing-screenshot";

export type ControlRun = { root: string; results: unknown; completion: Completion };

export function runControl(t: TestContext, mode: ControlMode): ControlRun {
  const root = mkdtempSync(join(tmpdir(), "docs-runner-control-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const webkit = mode === "webkit-missing-screenshot";
  const engine = webkit ? "webkit" : "chromium";
  const configName = webkit ? "playwright.webkit-negative.config.ts" : "playwright.negative.config.ts";
  const config = {
    testDir: ".",
    testMatch: mode === "empty" ? "missing.spec.ts" : "reader-journey.spec.ts",
    // Playwright's test deadline also covers context and page setup, and a
    // setup that outlives it is a test-level deadline, classified as
    // infrastructure; on a loaded builder 5 s did not cover setup (nixbot
    // builds 1000 and 1001), turning every control into a deadline failure.
    // Each control's own failure is bounded separately: actionTimeout,
    // the deadline control's test.setTimeout(100), or process.exit.
    timeout: 60000,
    use: { actionTimeout: 250, trace: "retain-on-failure", screenshot: "only-on-failure" },
    workers: 1,
    retries: 0,
    reporter: [
      ["html", { outputFolder: "playwright-report", open: "never" }],
      ["json", { outputFile: "playwright-report/results.json" }],
      [reporter],
    ],
    projects: [
      {
        name: engine,
        use: {
          browserName: engine,
          ...(mode === "launch" ? { launchOptions: { executablePath: "/nonexistent-docs-control-browser" } } : {}),
          // As in playwright.config.ts, where the video shares the screencast.
          ...(webkit ? { video: "retain-on-failure" } : {}),
        },
      },
    ],
    ...(mode === "global" ? { globalSetup: "./broken-setup.ts" } : {}),
  };
  writeFileSync(join(root, configName), `export default ${JSON.stringify(config)};`);
  writeFileSync(
    join(root, "broken-setup.ts"),
    'export default () => { throw new Error("controlled setup failure"); };',
  );
  writeFileSync(
    join(root, "reader-journey.spec.ts"),
    `import { test, expect } from ${JSON.stringify(webkit ? fixtures : playwright)};
     ${mode === "hook" ? 'test.beforeEach(async ({ page }) => { await page.getByRole("link").click(); });' : ""}
     ${mode === "hook-assertion" ? "test.beforeEach(async () => { expect(1).toBe(2); });" : ""}
     test("damaged guide is rejected by the real reader journey", async ({ page }) => {
       ${mode === "deadline" ? "test.setTimeout(100); page.setDefaultTimeout(0);" : ""}
       ${mode === "worker" ? "process.exit(1);" : ""}
       ${mode === "closed-page" ? "await page.close();" : ""}
       ${webkit ? 'page.screenshot = () => Promise.reject(new Error("controlled screenshot failure"));' : ""}
       ${
         // The fixture takes the first screencast frame for a pre-paint
         // placeholder, so paint several times, as a navigated reader page does.
         webkit
           ? 'await page.setContent("<h1>Damaged guide</h1>"); for (let i = 0; i < 5; i++) { await page.evaluate((n) => document.body.append(String(n)), i); await page.waitForTimeout(200); }'
           : ""
       }
       ${mode === "assertion" || webkit ? "await expect(page.getByRole('link')).toBeVisible({ timeout: 250 });" : "await page.getByRole('link', { name: 'Getting started' }).click();"}
     });`,
  );
  const child = spawnSync(process.execPath, [cli, "test", "--config", configName], {
    cwd: root,
    env: { ...process.env, CI: "true", PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: "1" },
    encoding: "utf8",
    // A hang guard only: each control is bounded by its own 5 s test deadline,
    // but browser launch and worker restart share the builder with concurrent
    // report builds, and a worker-exit control took 42 s in nixbot build 956.
    timeout: 180000,
    maxBuffer: 8 * 1024 * 1024,
  });
  assert.ifError(child.error);
  assert.equal(child.status, 1, child.stdout + child.stderr);
  const resultsPath = join(root, "playwright-report/results.json");
  const results: unknown = JSON.parse(readFileSync(resultsPath, "utf8"), (key, value) =>
    key === "path" && typeof value === "string" && isAbsolute(value)
      ? relative(realpathSync(root), realpathSync(value))
      : value,
  );
  writeFileSync(resultsPath, JSON.stringify(results));
  writeFileSync(
    join(root, "run.json"),
    JSON.stringify({
      schemaVersion: 1,
      exitCode: child.status,
      provenance: {
        site: "/nix/store/control-site",
        source: "/nix/store/control-source",
        dependencies: "/nix/store/control-dependencies",
        browsers: "/nix/store/control-browsers",
        node: "/nix/store/control-node",
        system: "aarch64-darwin",
        config: configName,
        projects: engine,
        trace: "retain-on-failure",
        evidenceEpoch: "0",
      },
    }),
  );
  return {
    root,
    results,
    // The control's own reporter output; the tests inspect it directly.
    completion: JSON.parse(readFileSync(join(root, "playwright-report/completion.json"), "utf8")) as Completion,
  };
}
