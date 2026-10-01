import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { validateReport } from "./validate-report.mjs";

const root = process.argv[2];
const verdict = validateReport(root);
assert.equal(verdict.passed, false, "negative control unexpectedly passed");
assert.equal(verdict.counts.unexpected, 1, "expected exactly one failing reader journey");
const cliVerdict = spawnSync(process.execPath, [
  new URL("./validate-report.mjs", import.meta.url).pathname,
  "verdict",
  root,
]);
assert.equal(cliVerdict.status, 1, "completed product failure must exit verdict 1");
const completion = JSON.parse(readFileSync(join(root, "playwright-report/completion.json"), "utf8"));
const [test] = completion.tests;
const removedLink = process.argv[3] === "removed-link";
assert.match(test.title, removedLink ? /removed homepage link is rejected/ : /damaged guide is rejected/);
assert.equal(test.attempts.length, 1, "negative control must fail on the original attempt, without retry");
assert.equal(test.attempts[0].status, "failed");
assert.equal(test.attempts[0].failureKind, "product");
assert(
  test.attempts[0].attachments.some((name) => name.endsWith("/trace.zip")),
  "original failure trace missing",
);
assert(
  test.attempts[0].attachments.some((name) => name.endsWith(".png")),
  "failure screenshot missing",
);
const results = JSON.parse(readFileSync(join(root, "playwright-report/results.json"), "utf8"));
assert.match(JSON.stringify(results), /Getting started/);
assert.match(JSON.stringify(results), removedLink ? /locator.click: Timeout/ : /toBeVisible/);
console.log(
  "Negative control: intended reader failure rejected; verdict 1, original trace, screenshot and HTML preserved.",
);
