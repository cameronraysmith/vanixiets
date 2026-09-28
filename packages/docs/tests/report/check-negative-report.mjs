import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { validateReport } from "./validate-report.mjs";

const root = process.argv[2];
const verdict = validateReport(root);
assert.equal(verdict.passed, false, "negative control unexpectedly passed");
assert.equal(verdict.counts.unexpected, 1, "expected exactly one failing reader journey");
const completion = JSON.parse(readFileSync(join(root, "playwright-report/completion.json"), "utf8"));
const [test] = completion.tests;
assert.match(test.title, /damaged guide is rejected/);
assert.equal(test.attempts.length, 1, "negative control must fail on the original attempt, without retry");
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
assert.match(JSON.stringify(results), /toBeVisible/);
console.log("Negative control: intended reader assertion rejected; original trace, screenshot and HTML preserved.");
