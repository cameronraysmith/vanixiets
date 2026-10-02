import { readFileSync, realpathSync, statSync } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { FullResult, JSONReport, JSONReportTest, JSONReportTestResult, TestStatus } from "@playwright/test/reporter";
import type {
  Completion,
  CompletionAttempt,
  CompletionTest,
  FailureKind,
  TestOutcome,
} from "./completion-reporter.ts";
import { requiredCases, requiredProjects } from "./policy.ts";

/** The evidence violates the artifact contract; the CLI exits 2. */
export class InvalidEvidence extends Error {}

type RunStatus = FullResult["status"];

// Runtime membership lists for the untrusted JSON. Each is tied to its
// Playwright or reporter type: a value added upstream and missing here fails
// the type check rather than reaching a CI run.
const testStatuses = ["passed", "failed", "timedOut", "skipped", "interrupted"] as const satisfies readonly TestStatus[];
const runStatuses = ["passed", "failed", "timedout", "interrupted"] as const satisfies readonly RunStatus[];
const outcomes = ["skipped", "expected", "unexpected", "flaky"] as const satisfies readonly TestOutcome[];
const failureKinds = ["product", "infrastructure"] as const satisfies readonly FailureKind[];
type Exhaustive<Listed, All> = [Exclude<All, Listed>] extends [never] ? true : never;
const listsAreExhaustive: [
  Exhaustive<(typeof testStatuses)[number], TestStatus>,
  Exhaustive<(typeof runStatuses)[number], RunStatus>,
  Exhaustive<(typeof outcomes)[number], TestOutcome>,
  Exhaustive<(typeof outcomes)[number], JSONReportTest["status"]>,
  Exhaustive<(typeof failureKinds)[number], FailureKind>,
] = [true, true, true, true, true];
void listsAreExhaustive;

export type Provenance = {
  site: string;
  source: string;
  dependencies: string;
  browsers: string;
  node: string;
  system: string;
  config: string;
  projects: string;
  trace: "retain-on-failure";
  evidenceEpoch: string;
};
export type RunMetadata = { schemaVersion: 1; exitCode: number; provenance: Provenance };
/** completion.json as parsed: errors are only counted, never interpreted. */
export type ParsedCompletion = Omit<Completion, "errors"> & { errors: unknown[] };
export type JsonAttempt = Pick<JSONReportTestResult, "retry"> & { status: TestStatus; attachments: string[] };
export type JsonTest = Pick<JSONReportTest, "status" | "expectedStatus"> & { id: string; results: JsonAttempt[] };
export type JsonStats = Pick<JSONReport["stats"], TestOutcome>;
export type JsonResults = { errors: unknown[]; stats: JsonStats; tests: JsonTest[] };
export type Evidence = { metadata: RunMetadata; completion: ParsedCompletion; results: JsonResults };
export type Verdict = { passed: boolean; counts: Record<TestOutcome, number>; infrastructureRetries: number };

/**
 * How one attempt counts toward the verdict. Every TestStatus has an explicit
 * case: a status Playwright adds later is a type error here.
 */
export type AttemptClass =
  | { kind: "passed" }
  | { kind: "product" }
  | { kind: "infrastructure"; cause: "failed" | "test deadline" | "interrupted" }
  | { kind: "invalid"; reason: string };

export function classifyAttempt({ status, failureKind }: Pick<CompletionAttempt, "status" | "failureKind">): AttemptClass {
  switch (status) {
    case "passed":
      return failureKind === null
        ? { kind: "passed" }
        : { kind: "invalid", reason: "passed attempt carries a failure kind" };
    case "failed":
      if (failureKind === "product") return { kind: "product" };
      return failureKind === "infrastructure"
        ? { kind: "infrastructure", cause: "failed" }
        : { kind: "invalid", reason: "failed attempt has no failure kind" };
    // A whole-test deadline or an aborted run is never product evidence.
    case "timedOut":
      return failureKind === "infrastructure"
        ? { kind: "infrastructure", cause: "test deadline" }
        : { kind: "invalid", reason: "incomplete attempt: timed-out attempt not classified as infrastructure" };
    case "interrupted":
      return failureKind === "infrastructure"
        ? { kind: "infrastructure", cause: "interrupted" }
        : { kind: "invalid", reason: "incomplete attempt: interrupted attempt not classified as infrastructure" };
    // Every required scenario expects to pass; one that did not run proves nothing.
    case "skipped":
      return { kind: "invalid", reason: "skipped attempt: a required scenario did not run" };
    default:
      return status satisfies never;
  }
}

function fail(reason: string): never {
  throw new InvalidEvidence(reason);
}

function check(condition: boolean, reason: string): asserts condition {
  if (!condition) fail(reason);
}

function file(root: string, name: unknown): string {
  check(typeof name === "string" && name.length > 0 && !isAbsolute(name), "invalid artifact path");
  const resolved = realpathSync(resolve(root, name));
  const rel = relative(realpathSync(root), resolved);
  check(rel !== ".." && !rel.startsWith("../") && !isAbsolute(rel), "artifact escapes report");
  const stat = statSync(resolved);
  check(stat.isFile() && stat.size > 0, `missing/empty artifact: ${name}`);
  return resolved;
}

// Boundary decoders: the only place untrusted JSON is inspected.
function record(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) fail(`${label} must be an object`);
  return value as Record<string, unknown>;
}

function list(value: unknown, label: string): unknown[] {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
  return value;
}

function text(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) fail(`missing ${label}`);
  return value;
}

function integer(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) fail(`${label} must be an integer`);
  return value;
}

function member<T extends string>(value: unknown, allowed: readonly T[], label: string): T {
  if (!allowed.some((candidate) => candidate === value)) fail(`unknown ${label}: ${String(value)}`);
  return value as T;
}

function readJson(root: string, name: string): unknown {
  return JSON.parse(readFileSync(file(root, name), "utf8"));
}

function parseMetadata(value: unknown): RunMetadata {
  const metadata = record(value, "run.json");
  check(metadata.schemaVersion === 1, "unsupported run.json schema");
  const provenance = record(metadata.provenance, "provenance");
  const field = (key: keyof Provenance) => text(provenance[key], `provenance: ${key}`);
  const store = (key: keyof Provenance) => {
    const path = field(key);
    check(path.startsWith("/nix/store/"), `missing provenance: ${key}`);
    return path;
  };
  check(provenance.trace === "retain-on-failure", "trace policy must be retain-on-failure");
  const evidenceEpoch = provenance.evidenceEpoch;
  check(typeof evidenceEpoch === "string" && /^(0|[1-9]\d*)$/.test(evidenceEpoch), "invalid evidence epoch");
  return {
    schemaVersion: 1,
    exitCode: integer(metadata.exitCode, "runner exit code"),
    provenance: {
      site: store("site"),
      source: store("source"),
      dependencies: store("dependencies"),
      browsers: store("browsers"),
      node: store("node"),
      system: field("system"),
      config: field("config"),
      projects: field("projects"),
      trace: "retain-on-failure",
      evidenceEpoch,
    },
  };
}

function parseAttempt(value: unknown): CompletionAttempt {
  const attempt = record(value, "attempt");
  return {
    status: member(attempt.status, testStatuses, "attempt status"),
    retry: integer(attempt.retry, "attempt retry"),
    failureKind: attempt.failureKind === null ? null : member(attempt.failureKind, failureKinds, "failure kind"),
    attachments: list(attempt.attachments, "attachments").map((name) => text(name, "attachment path")),
  };
}

function parseTest(value: unknown): CompletionTest {
  const test = record(value, "test");
  return {
    id: text(test.id, "test ID"),
    project: text(test.project, "test project"),
    case: text(test.case, "test case"),
    title: text(test.title, "test title"),
    outcome: member(test.outcome, outcomes, "test outcome"),
    expectedStatus: member(test.expectedStatus, testStatuses, "expected status"),
    attempts: list(test.attempts, "attempts").map(parseAttempt),
  };
}

function parseCompletion(value: unknown): ParsedCompletion {
  const completion = record(value, "completion.json");
  check(completion.schemaVersion === 1, "unsupported completion.json schema");
  return {
    schemaVersion: 1,
    status: member(completion.status, runStatuses, "run status"),
    projects: list(completion.projects, "projects").map((project) => text(project, "project")),
    errors: list(completion.errors, "completion errors"),
    tests: list(completion.tests, "tests").map(parseTest),
  };
}

function parseJsonTest(id: string, value: unknown): JsonTest {
  const test = record(value, "JSON test");
  return {
    id,
    status: member(test.status, outcomes, "JSON test status"),
    expectedStatus: member(test.expectedStatus, testStatuses, "JSON expected status"),
    results: list(test.results, "JSON results").map((entry) => {
      const result = record(entry, "JSON result");
      return {
        status: member(result.status, testStatuses, "JSON attempt status"),
        retry: integer(result.retry, "JSON attempt retry"),
        attachments: list(result.attachments, "JSON attachments").flatMap((attachment) => {
          const path = record(attachment, "JSON attachment").path;
          return path === undefined || path === "" ? [] : [text(path, "JSON attachment path")];
        }),
      };
    }),
  };
}

function parseSuites(value: unknown): JsonTest[] {
  return list(value, "suites").flatMap((entry) => {
    const suite = record(entry, "suite");
    return [
      ...list(suite.specs, "specs").flatMap((specEntry) => {
        const spec = record(specEntry, "spec");
        const id = text(spec.id, "spec ID");
        return list(spec.tests, "spec tests").map((test) => parseJsonTest(id, test));
      }),
      ...(suite.suites === undefined ? [] : parseSuites(suite.suites)),
    ];
  });
}

function parseResults(value: unknown): JsonResults {
  const results = record(value, "results.json");
  const stats = record(results.stats, "stats");
  return {
    errors: list(results.errors, "JSON errors"),
    stats: {
      expected: integer(stats.expected, "stats expected"),
      unexpected: integer(stats.unexpected, "stats unexpected"),
      skipped: integer(stats.skipped, "stats skipped"),
      flaky: integer(stats.flaky, "stats flaky"),
    },
    tests: parseSuites(results.suites),
  };
}

/** Narrows a report directory's untrusted JSON into the typed evidence model. */
export function parseEvidence(root: string): Evidence {
  file(root, "playwright-report/index.html");
  return {
    metadata: parseMetadata(readJson(root, "run.json")),
    completion: parseCompletion(readJson(root, "playwright-report/completion.json")),
    results: parseResults(readJson(root, "playwright-report/results.json")),
  };
}

const sorted = (values: readonly string[]) => JSON.stringify([...values].sort());

export function judge(root: string, { metadata, completion, results }: Evidence): Verdict {
  const { provenance } = metadata;
  // An aborted or globally timed-out run never produced a complete matrix.
  check(completion.status === "passed" || completion.status === "failed", `incomplete run: ${completion.status}`);
  check(completion.errors.length === 0, "runner infrastructure error");
  check(results.errors.length === 0, "JSON runner infrastructure error");
  const tests = completion.tests;
  check(tests.length > 0, "zero-test report");
  const projects = provenance.projects.split(",");
  const expectedProjects = requiredProjects(provenance.system, provenance.config);
  check(expectedProjects !== undefined, "unknown system/suite policy");
  check(sorted(projects) === sorted(expectedProjects), "required browser engines");
  check(new Set(projects).size === projects.length, "duplicate project");
  check(sorted(completion.projects) === sorted(projects), "project disagreement");
  check(sorted([...new Set(tests.map((test) => test.project))]) === sorted(projects), "missing project tests");
  const cases = requiredCases[provenance.config];
  check(cases !== undefined, "unknown suite policy");
  check(
    sorted(tests.map((test) => `${test.project}::${test.case}`)) ===
      sorted(projects.flatMap((project) => cases.map((name) => `${project}::${name}`))),
    "partial/unexpected scenario matrix",
  );
  check(results.tests.length === tests.length, "test inventory disagreement");
  check(new Set(tests.map((test) => test.id)).size === tests.length, "duplicate test ID");
  check(new Set(results.tests.map((test) => test.id)).size === tests.length, "duplicate JSON test ID");

  const counts: Record<TestOutcome, number> = { expected: 0, unexpected: 0, skipped: 0, flaky: 0 };
  let infrastructureRetries = 0;
  for (const test of tests) {
    check(test.outcome !== "skipped", "skipped/unknown outcome");
    check(test.expectedStatus === "passed", "expected failures/skips are not evidence of success");
    counts[test.outcome]++;
    const json = results.tests.find((entry) => entry.id === test.id);
    check(json !== undefined, "missing JSON test");
    check(json.status === test.outcome, "outcome disagreement");
    check(json.expectedStatus === test.expectedStatus, "expected status disagreement");
    const attempts = test.attempts;
    check(attempts.length > 0, "missing attempt");
    check(json.results.length === attempts.length, "attempt count disagreement");
    const classes = attempts.map((attempt, index) => {
      const jsonAttempt = json.results[index];
      check(attempt.retry === index, "missing/out-of-order attempt");
      check(jsonAttempt.status === attempt.status, "attempt status disagreement");
      check(jsonAttempt.retry === attempt.retry, "attempt retry disagreement");
      check(sorted(attempt.attachments) === sorted(jsonAttempt.attachments), "attachment inventory disagreement");
      for (const attachment of attempt.attachments) file(root, attachment);
      const attemptClass = classifyAttempt(attempt);
      switch (attemptClass.kind) {
        case "invalid":
          return fail(attemptClass.reason);
        // Tolerated only when the retry policy recovered: a later attempt of
        // the same test completed as a pass or a product failure.
        case "infrastructure":
          check(index < attempts.length - 1, `infrastructure failure (${attemptClass.cause})`);
          infrastructureRetries++;
          break;
        case "product":
          check(attempt.attachments.some((name) => name.endsWith("/trace.zip")), "original failure trace missing");
          check(attempt.attachments.some((name) => name.endsWith(".png")), "failure screenshot missing");
          break;
        case "passed":
          break;
        default:
          attemptClass satisfies never;
      }
      return attemptClass.kind;
    });
    const failed = classes.at(-1) === "product";
    check((test.outcome === "unexpected") === failed, "terminal outcome disagreement");
    check(
      (test.outcome === "flaky") === (!failed && classes.some((kind) => kind !== "passed")),
      "flaky outcome disagreement",
    );
  }
  for (const outcome of outcomes) check(results.stats[outcome] === counts[outcome], `stats ${outcome}`);
  const passed = counts.unexpected === 0;
  check(completion.status === (passed ? "passed" : "failed"), "run status disagreement");
  check(metadata.exitCode === (passed ? 0 : 1), "runner exit disagreement");
  return { passed, counts, infrastructureRetries };
}

export function validateReport(root: string): Verdict {
  return judge(root, parseEvidence(root));
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, root] = process.argv.slice(2);
  try {
    if ((mode !== "validate" && mode !== "verdict") || !root) {
      throw new InvalidEvidence("usage: validate-report.ts validate|verdict REPORT");
    }
    const verdict = validateReport(root);
    console.log(JSON.stringify(verdict));
    if (mode === "verdict" && !verdict.passed) process.exitCode = 1;
  } catch (error) {
    // Unreadable or missing files are invalid evidence too, not a crash.
    console.error(`Invalid Playwright evidence: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 2;
  }
}
