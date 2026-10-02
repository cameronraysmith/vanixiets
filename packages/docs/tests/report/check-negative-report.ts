import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { classifyAttempt, judge, parseEvidence } from "./validate-report.ts";

const [root, mode = "damaged-guide"] = process.argv.slice(2);
assert(root, "usage: check-negative-report.ts REPORT [damaged-guide|removed-link]");
assert(mode === "damaged-guide" || mode === "removed-link", `unknown negative-control mode: ${mode}`);
const removedLink = mode === "removed-link";

const evidence = parseEvidence(root);
const verdict = judge(root, evidence);
assert.equal(verdict.passed, false, "negative control unexpectedly passed");
assert.equal(verdict.counts.unexpected, 1, "expected exactly one failing reader journey");
const cliVerdict = spawnSync(process.execPath, [
  fileURLToPath(new URL("./validate-report.ts", import.meta.url)),
  "verdict",
  root,
]);
assert.equal(cliVerdict.status, 1, "completed product failure must exit verdict 1");

const [test] = evidence.completion.tests;
assert.match(test.title, removedLink ? /removed homepage link is rejected/ : /damaged guide is rejected/);
// A deterministic defect must fail every attempt: the retries absorb a stalled
// navigation on a busy host, never the product failure itself.
const classes = test.attempts.map((attempt) => classifyAttempt(attempt).kind);
assert(!classes.includes("passed"), "a retry passed the deliberately broken journey");
assert.equal(classes.at(-1), "product", "terminal attempt must be a completed product failure");
const results = readFileSync(join(root, "playwright-report/results.json"), "utf8");
assert.match(results, /Getting started/);
assert.match(results, removedLink ? /locator.click: Timeout/ : /toBeVisible/);
console.log(
  "Negative control: intended reader failure rejected; verdict 1, original trace, screenshot and HTML preserved.",
);
