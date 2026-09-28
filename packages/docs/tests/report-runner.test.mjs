import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { validateReport } from "./report/validate-report.mjs";

const require = createRequire(import.meta.url);
const playwright = require.resolve("@playwright/test");
const cli = require.resolve("@playwright/test/cli");
const reporter = fileURLToPath(new URL("./report/completion-reporter.ts", import.meta.url));

function runControl(t, mode) {
  const root = mkdtempSync(join(tmpdir(), "docs-runner-control-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const config = {
    testDir: ".",
    testMatch: mode === "empty" ? "missing.spec.ts" : "reader-journey.spec.ts",
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
        use: { browserName: "chromium", launchOptions: { executablePath: "/nonexistent-docs-control-browser" } },
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
    `import { test } from ${JSON.stringify(playwright)};
     test("damaged guide is rejected by the real reader journey", async ({ page }) => { await page.goto("/"); });`,
  );
  const child = spawnSync(process.execPath, [cli, "test", "--config", "playwright.negative.config.ts"], {
    cwd: root,
    env: { ...process.env, CI: "true", PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: "1" },
    encoding: "utf8",
    timeout: 30000,
    maxBuffer: 8 * 1024 * 1024,
  });
  assert.ifError(child.error);
  assert.equal(child.status, 1, child.stdout + child.stderr);
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
        system: "control",
        config: "playwright.negative.config.ts",
        projects: "chromium",
        trace: "retain-on-failure",
      },
    }),
  );
  return { root, completion: JSON.parse(readFileSync(join(root, "playwright-report/completion.json"), "utf8")) };
}

test("actual Playwright browser launch failure is not accepted as assertion evidence", (t) => {
  const { root, completion } = runControl(t, "launch");
  assert.equal(completion.tests[0].attempts[0].failureKind, "infrastructure");
  assert.throws(() => validateReport(root), /infrastructure failure/);
});

test("actual Playwright global setup failure fails closed", (t) => {
  const { root, completion } = runControl(t, "global");
  assert.match(completion.errors[0].message, /controlled setup failure/);
  assert.throws(() => validateReport(root), /runner infrastructure error/);
});

test("actual Playwright zero-test selection fails closed", (t) => {
  const { root, completion } = runControl(t, "empty");
  assert.equal(completion.tests.length, 0);
  assert.throws(() => validateReport(root), /runner infrastructure error|zero-test/);
});
