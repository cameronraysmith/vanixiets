import assert from "node:assert/strict";
import { test } from "node:test";
import { runControl } from "./report/runner-control.ts";
import { validateReport } from "./report/validate-report.ts";

test("actual Playwright browser launch failure is not accepted as product evidence", (t) => {
  const { root, completion } = runControl(t, "launch");
  assert.equal(completion.tests[0].attempts[0].failureKind, "infrastructure");
  assert.throws(() => validateReport(root), /infrastructure failure/);
});

test("actual Playwright global setup failure fails closed", (t) => {
  const { root, completion } = runControl(t, "global");
  assert.match(completion.errors[0]?.message ?? "", /controlled setup failure/);
  assert.throws(() => validateReport(root), /runner infrastructure error/);
});

test("actual Playwright zero-test selection fails closed", (t) => {
  const { root, completion } = runControl(t, "empty");
  assert.equal(completion.tests.length, 0);
  assert.throws(() => validateReport(root), /runner infrastructure error|zero-test/);
});
