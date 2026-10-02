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
  | "empty";

export type ControlRun = { root: string; results: unknown; completion: Completion };

export function runControl(t: TestContext, mode: ControlMode): ControlRun {
  const root = mkdtempSync(join(tmpdir(), "docs-runner-control-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const config = {
    testDir: ".",
    testMatch: mode === "empty" ? "missing.spec.ts" : "reader-journey.spec.ts",
    timeout: 5000,
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
        name: "chromium",
        use: {
          browserName: "chromium",
          ...(mode === "launch" ? { launchOptions: { executablePath: "/nonexistent-docs-control-browser" } } : {}),
        },
      },
    ],
    ...(mode === "global" ? { globalSetup: "./broken-setup.ts" } : {}),
  };
  writeFileSync(join(root, "playwright.negative.config.ts"), `export default ${JSON.stringify(config)};`);
  writeFileSync(
    join(root, "broken-setup.ts"),
    'export default () => { throw new Error("controlled setup failure"); };',
  );
  writeFileSync(
    join(root, "reader-journey.spec.ts"),
    `import { test, expect } from ${JSON.stringify(playwright)};
     ${mode === "hook" ? 'test.beforeEach(async ({ page }) => { await page.getByRole("link").click(); });' : ""}
     ${mode === "hook-assertion" ? "test.beforeEach(async () => { expect(1).toBe(2); });" : ""}
     test("damaged guide is rejected by the real reader journey", async ({ page }) => {
       ${mode === "deadline" ? "test.setTimeout(100); page.setDefaultTimeout(0);" : ""}
       ${mode === "worker" ? "process.exit(1);" : ""}
       ${mode === "closed-page" ? "await page.close();" : ""}
       ${mode === "assertion" ? "await expect(page.getByRole('link')).toBeVisible({ timeout: 250 });" : "await page.getByRole('link', { name: 'Getting started' }).click();"}
     });`,
  );
  const child = spawnSync(process.execPath, [cli, "test", "--config", "playwright.negative.config.ts"], {
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
        config: "playwright.negative.config.ts",
        projects: "chromium",
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
