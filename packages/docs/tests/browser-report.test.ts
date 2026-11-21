import assert from "node:assert/strict";
import { statSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { runControl } from "./report/runner-control.ts";
import { validateReport } from "./report/validate-report.ts";

for (const mode of ["action", "assertion"] as const) {
  test(`actual completed ${mode} failure retains product-failure evidence`, (t) => {
    const { root, completion, results } = runControl(t, mode);
    assert.match(JSON.stringify(results), mode === "action" ? /locator.click: Timeout/ : /toBeVisible/);
    assert.equal(completion.tests[0].attempts[0].status, "failed");
    assert.equal(completion.tests[0].attempts[0].failureKind, "product");
    assert.equal(validateReport(root).passed, false);
  });
}

const infrastructureControls = {
  hook: /locator.click: Timeout/,
  "hook-assertion": /toBe/,
  deadline: /Test timeout/,
  worker: /worker process exited unexpectedly/,
  "closed-page": /has been closed/,
} as const;

for (const [mode, message] of Object.entries(infrastructureControls) as [
  keyof typeof infrastructureControls,
  RegExp,
][]) {
  test(`actual ${mode} failure is not product evidence`, (t) => {
    const { root, completion, results } = runControl(t, mode);
    assert.equal(completion.tests[0].attempts[0].failureKind, "infrastructure");
    assert.match(JSON.stringify(results), message);
    // Unretried, so the infrastructure attempt is terminal.
    assert.throws(() => validateReport(root), /infrastructure failure/);
  });
}

test("WebKit product failure without Playwright's screenshot keeps a non-empty PNG", (t) => {
  const { root, completion } = runControl(t, "webkit-missing-screenshot");
  const [attempt] = completion.tests[0].attempts;
  assert.equal(attempt.failureKind, "product");
  const screenshots = attempt.attachments.filter((name) => name.endsWith(".png"));
  assert.equal(screenshots.length, 1, JSON.stringify(attempt.attachments));
  assert.ok(statSync(join(root, screenshots[0])).size > 0);
  assert.equal(validateReport(root).passed, false);
});
