import assert from "node:assert/strict";
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
