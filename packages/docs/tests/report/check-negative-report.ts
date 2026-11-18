import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { classifyAttempt, judge, parseEvidence } from "./validate-report.ts";

const [root, mode = "damaged-guide"] = process.argv.slice(2);
assert(root, "usage: check-negative-report.ts REPORT [damaged-guide|removed-link|webkit|topology]");
assert(
  mode === "damaged-guide" || mode === "removed-link" || mode === "webkit" || mode === "topology",
  `unknown negative-control mode: ${mode}`,
);
const removedLink = mode === "removed-link";
const topology = mode === "topology";
// What each control breaks, and the failure the unchanged spec must report.
const intended = topology
  ? {
      title: /dropped host is rejected by the fleet topology oracle/,
      context: /topology-fleet\.svg/,
      failure: /host \S+ is not a <text> in \/diagrams\/topology-fleet\.svg/,
    }
  : removedLink
    ? { title: /removed homepage link is rejected/, context: /Getting started/, failure: /locator.click: Timeout/ }
    : { title: /damaged guide is rejected/, context: /Getting started/, failure: /toBeVisible/ };

const evidence = parseEvidence(root);
const verdict = judge(root, evidence);
assert.equal(verdict.passed, false, "negative control unexpectedly passed");
assert.equal(verdict.counts.unexpected, 1, "expected exactly one failing test");
const cliVerdict = spawnSync(process.execPath, [
  fileURLToPath(new URL("./validate-report.ts", import.meta.url)),
  "verdict",
  root,
]);
assert.equal(cliVerdict.status, 1, "completed product failure must exit verdict 1");

const [test] = evidence.completion.tests;
assert.equal(test.project, mode === "webkit" ? "webkit" : "chromium", "negative control ran on the wrong engine");
assert.match(test.title, intended.title);
// A deterministic defect must fail every attempt: the retries absorb a stalled
// navigation on a busy host, never the product failure itself.
const classes = test.attempts.map((attempt) => classifyAttempt(attempt).kind);
assert(!classes.includes("passed"), "a retry passed the deliberately broken journey");
assert.equal(classes.at(-1), "product", "terminal attempt must be a completed product failure");
// The validator only requires nonempty files. Here the screenshot must be a
// PNG with a nonzero-sized image header, so the WebKit control
// cannot pass on bytes that are not an image.
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
for (const name of (test.attempts.at(-1)?.attachments ?? []).filter((name) => name.endsWith(".png"))) {
  const image = readFileSync(join(root, name));
  assert(image.length >= 24 && image.subarray(0, 8).equals(png), `failure screenshot is not a PNG: ${name}`);
  assert.equal(image.toString("latin1", 12, 16), "IHDR", `failure screenshot has no PNG header: ${name}`);
  assert(image.readUInt32BE(16) > 0 && image.readUInt32BE(20) > 0, `failure screenshot has no pixels: ${name}`);
}
const results = readFileSync(join(root, "playwright-report/results.json"), "utf8");
assert.match(results, intended.context);
assert.match(results, intended.failure);
console.log(
  `Negative control (${mode}): intended failure on ${test.project} rejected; verdict 1, original trace, PNG screenshot and HTML preserved.`,
);
