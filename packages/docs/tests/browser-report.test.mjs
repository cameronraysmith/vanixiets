import assert from "node:assert/strict";
import { test } from "node:test";
import { runControl } from "./report/runner-control.mjs";
import { validateReport } from "./report/validate-report.mjs";

for (const mode of ["action", "assertion"]) {
  test(`actual completed ${mode} failure retains product-failure evidence`, (t) => {
    const { root, completion, results } = runControl(t, mode);
    assert.match(JSON.stringify(results), mode === "action" ? /locator.click: Timeout/ : /toBeVisible/);
    assert.equal(completion.tests[0].attempts[0].status, "failed");
    assert.equal(completion.tests[0].attempts[0].failureKind, "product");
    assert.equal(validateReport(root).passed, false);
  });
}

for (const mode of ["hook", "hook-assertion", "deadline", "worker", "closed-page"]) {
  test(`actual ${mode} failure is not product evidence`, (t) => {
    const { root, completion, results } = runControl(t, mode);
    assert.equal(completion.tests[0].attempts[0].failureKind, "infrastructure");
    assert.match(
      JSON.stringify(results),
      {
        hook: /locator.click: Timeout/,
        "hook-assertion": /toBe/,
        deadline: /Test timeout/,
        worker: /worker process exited unexpectedly/,
        "closed-page": /has been closed/,
      }[mode],
    );
    assert.throws(() => validateReport(root));
  });
}
