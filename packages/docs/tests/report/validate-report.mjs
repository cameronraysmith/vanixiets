import assert from "node:assert/strict";
import { readFileSync, realpathSync, statSync } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { requiredCases, requiredProjects } from "./policy.mjs";

function array(value, label) {
  assert(Array.isArray(value), `${label} must be an array`);
  return value;
}

function file(root, name) {
  assert(typeof name === "string" && name.length > 0 && !isAbsolute(name), "invalid artifact path");
  const resolved = realpathSync(resolve(root, name));
  const rel = relative(realpathSync(root), resolved);
  assert(rel !== ".." && !rel.startsWith("../") && !isAbsolute(rel), "artifact escapes report");
  assert(statSync(resolved).isFile() && statSync(resolved).size > 0, `missing/empty artifact: ${name}`);
  return resolved;
}

function read(root, name) {
  return JSON.parse(readFileSync(file(root, name), "utf8"));
}

function jsonTests(suites) {
  return array(suites, "suites").flatMap((suite) => [
    ...array(suite.specs, "specs").flatMap((spec) =>
      array(spec.tests, "spec tests").map((test) => ({ ...test, id: spec.id })),
    ),
    ...jsonTests(suite.suites ?? []),
  ]);
}

export function validateReport(root) {
  file(root, "playwright-report/index.html");
  const metadata = read(root, "run.json");
  const completion = read(root, "playwright-report/completion.json");
  const results = read(root, "playwright-report/results.json");
  assert.equal(metadata.schemaVersion, 1);
  assert.equal(completion.schemaVersion, 1);
  for (const key of ["site", "source", "dependencies", "browsers", "node"]) {
    assert(metadata.provenance?.[key]?.startsWith("/nix/store/"), `missing provenance: ${key}`);
  }
  for (const key of ["system", "config", "projects", "trace"]) {
    assert(typeof metadata.provenance?.[key] === "string" && metadata.provenance[key], `missing provenance: ${key}`);
  }
  assert.equal(metadata.provenance.trace, "retain-on-failure");
  assert(
    typeof metadata.provenance.evidenceEpoch === "string" && /^(0|[1-9]\d*)$/.test(metadata.provenance.evidenceEpoch),
    "invalid evidence epoch",
  );
  assert(["passed", "failed"].includes(completion.status), "incomplete run");
  assert.equal(array(completion.errors, "completion errors").length, 0, "runner infrastructure error");
  assert.equal(array(results.errors, "JSON errors").length, 0, "JSON runner infrastructure error");
  const tests = array(completion.tests, "tests");
  assert(tests.length > 0, "zero-test report");
  const projects = metadata.provenance.projects.split(",");
  const expectedProjects = requiredProjects(metadata.provenance.system, metadata.provenance.config);
  assert(expectedProjects, "unknown system/suite policy");
  assert.deepEqual([...projects].sort(), [...expectedProjects].sort(), "required browser engines");
  assert.equal(new Set(projects).size, projects.length, "duplicate project");
  assert.deepEqual([...array(completion.projects, "projects")].sort(), [...projects].sort(), "project disagreement");
  assert.deepEqual(
    [...new Set(tests.map((test) => test.project))].sort(),
    [...projects].sort(),
    "missing project tests",
  );
  const cases = requiredCases[metadata.provenance.config];
  assert(cases, "unknown suite policy");
  assert.deepEqual(
    tests.map((test) => `${test.project}::${test.case}`).sort(),
    projects.flatMap((project) => cases.map((name) => `${project}::${name}`)).sort(),
    "partial/unexpected scenario matrix",
  );
  const serialized = jsonTests(results.suites);
  assert.equal(serialized.length, tests.length, "test inventory disagreement");
  assert.equal(new Set(tests.map((test) => test.id)).size, tests.length, "duplicate test ID");
  assert.equal(new Set(serialized.map((test) => test.id)).size, tests.length, "duplicate JSON test ID");
  const counts = { expected: 0, unexpected: 0, skipped: 0, flaky: 0 };
  let infrastructureRetries = 0;
  for (const test of tests) {
    assert(typeof test.id === "string" && test.id.length > 0, "missing test ID");
    assert(["expected", "unexpected", "flaky"].includes(test.outcome), "skipped/unknown outcome");
    assert.equal(test.expectedStatus, "passed", "expected failures/skips are not evidence of success");
    counts[test.outcome]++;
    const json = serialized.find((entry) => entry.id === test.id);
    assert(json, "missing JSON test");
    assert.equal(json.status, test.outcome, "outcome disagreement");
    assert.equal(json.expectedStatus, test.expectedStatus);
    const attempts = array(test.attempts, "attempts");
    assert(attempts.length > 0, "missing attempt");
    assert.equal(array(json.results, "JSON results").length, attempts.length, "attempt count disagreement");
    for (const [index, attempt] of attempts.entries()) {
      assert(["passed", "failed", "timedOut"].includes(attempt.status), "incomplete/skipped attempt");
      assert.equal(attempt.retry, index, "missing/out-of-order attempt");
      assert.equal(json.results[index].status, attempt.status, "attempt status disagreement");
      assert.equal(json.results[index].retry, attempt.retry);
      // An infrastructure attempt, including a whole-test deadline, is
      // tolerated only when the retry policy recovered from it: a later attempt
      // of the same test completed as a pass or a product failure. A terminal
      // one prevents a valid report.
      if (attempt.status === "passed") {
        assert.equal(attempt.failureKind, null, "passed attempt carries a failure kind");
      } else if (attempt.failureKind === "infrastructure") {
        assert(index < attempts.length - 1, `infrastructure failure${attempt.status === "timedOut" ? " (test deadline)" : ""}`);
        infrastructureRetries++;
      } else {
        assert.equal(attempt.status, "failed", "incomplete/skipped attempt");
        assert.equal(attempt.failureKind, "product", "unknown failure kind");
      }
      const attachments = array(attempt.attachments, "attachments");
      const jsonAttachments = array(json.results[index].attachments, "JSON attachments")
        .filter((attachment) => attachment.path)
        .map((attachment) => attachment.path);
      assert.deepEqual(attachments, jsonAttachments, "attachment inventory disagreement");
      for (const attachment of attachments) file(root, attachment);
      if (attempt.failureKind === "product") {
        assert(
          attachments.some((attachment) => attachment.endsWith("/trace.zip")),
          "original failure trace missing",
        );
        assert(
          attachments.some((attachment) => attachment.endsWith(".png")),
          "failure screenshot missing",
        );
      }
    }
    const failed = attempts.at(-1).status === "failed";
    assert.equal(test.outcome === "unexpected", failed, "terminal outcome disagreement");
    assert.equal(test.outcome === "flaky", !failed && attempts.some((attempt) => attempt.status !== "passed"));
  }
  for (const [key, count] of Object.entries(counts)) assert.equal(results.stats?.[key], count, `stats ${key}`);
  const passed = counts.unexpected === 0;
  assert.equal(completion.status, passed ? "passed" : "failed", "run status disagreement");
  assert.equal(metadata.exitCode, passed ? 0 : 1, "runner exit disagreement");
  return { passed, counts, infrastructureRetries };
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [mode, root] = process.argv.slice(2);
    assert(["validate", "verdict"].includes(mode) && root, "usage: validate-report.mjs validate|verdict REPORT");
    const result = validateReport(root);
    console.log(JSON.stringify(result));
    if (mode === "verdict" && !result.passed) process.exitCode = 1;
  } catch (error) {
    console.error(`Invalid Playwright evidence: ${error.message}`);
    process.exitCode = 2;
  }
}
