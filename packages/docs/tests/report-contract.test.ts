import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type TestContext, test } from "node:test";
import { fileURLToPath } from "node:url";
import type { TestStatus } from "@playwright/test/reporter";
import type { Completion, FailureKind, TestOutcome } from "./report/completion-reporter.ts";
import { type Engine, requiredCases } from "./report/policy.ts";
import {
  type AttemptClass,
  classifyAttempt,
  type JsonStats,
  type RunMetadata,
  validateReport,
} from "./report/validate-report.ts";

// The subset of Playwright's JSON report the validator reads.
type ResultsFixture = {
  errors: unknown[];
  stats: JsonStats;
  suites: {
    specs: {
      id: string;
      tests: {
        expectedStatus: TestStatus;
        status: TestOutcome;
        results: { status: TestStatus; retry: number; attachments: { path: string }[] }[];
      }[];
    }[];
  }[];
};
type Fixture = {
  root: string;
  completion: Completion;
  results: ResultsFixture;
  metadata: RunMetadata;
  save: () => void;
};

// Deliberately corrupts typed evidence the way an untrusted producer could.
const corrupt = <T>(value: unknown): T => value as T;

function fixture(t: TestContext, failed = false): Fixture {
  const root = mkdtempSync(join(tmpdir(), "docs-report-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, "playwright-report"));
  mkdirSync(join(root, "test-results"));
  writeFileSync(join(root, "playwright-report/index.html"), "<html>report</html>");
  writeFileSync(join(root, "test-results/trace.zip"), "trace fixture");
  writeFileSync(join(root, "test-results/failure.png"), "screenshot fixture");
  const attachments = failed ? ["test-results/trace.zip", "test-results/failure.png"] : [];
  const status: TestStatus = failed ? "failed" : "passed";
  const outcome: TestOutcome = failed ? "unexpected" : "expected";
  const completion: Completion = {
    schemaVersion: 1,
    status,
    projects: ["chromium"],
    errors: [],
    tests: [
      {
        id: "reader-chromium",
        project: "chromium",
        case: "reader-journey.spec.ts::damaged guide is rejected by the real reader journey",
        title: " > chromium > reader-journey.spec.ts > damaged guide is rejected by the real reader journey",
        outcome,
        expectedStatus: "passed",
        attempts: [
          {
            status,
            retry: 0,
            failureKind: failed ? "product" : null,
            attachments,
          },
        ],
      },
    ],
  };
  const results: ResultsFixture = {
    errors: [],
    stats: { expected: failed ? 0 : 1, unexpected: failed ? 1 : 0, skipped: 0, flaky: 0 },
    suites: [
      {
        specs: [
          {
            id: "reader-chromium",
            tests: [
              {
                expectedStatus: "passed",
                status: outcome,
                results: [{ status, retry: 0, attachments: attachments.map((path) => ({ path })) }],
              },
            ],
          },
        ],
      },
    ],
  };
  const metadata: RunMetadata = {
    schemaVersion: 1,
    exitCode: failed ? 1 : 0,
    provenance: {
      site: "/nix/store/site",
      source: "/nix/store/source",
      dependencies: "/nix/store/dependencies",
      browsers: "/nix/store/browsers",
      node: "/nix/store/node",
      system: "aarch64-darwin",
      config: "playwright.negative.config.ts",
      projects: "chromium",
      trace: "retain-on-failure",
      evidenceEpoch: "0",
    },
  };
  const save = () => {
    writeFileSync(join(root, "playwright-report/completion.json"), JSON.stringify(completion));
    writeFileSync(join(root, "playwright-report/results.json"), JSON.stringify(results));
    writeFileSync(join(root, "run.json"), JSON.stringify(metadata));
  };
  save();
  return { root, completion, results, metadata, save };
}

test("complete success is valid and passes the verdict", (t) => {
  assert.equal(validateReport(fixture(t).root).passed, true);
});

test("complete assertion failure is valid but fails the verdict", (t) => {
  assert.equal(validateReport(fixture(t, true).root).passed, false);
});

for (const missing of [false, true]) {
  test(`symlinked CLI rejects ${missing ? "missing" : "negative"} evidence`, (t) => {
    const { root } = fixture(t, true);
    const link = join(root, "linked-report-tools");
    symlinkSync(fileURLToPath(new URL("./report", import.meta.url)), link, "dir");
    const result = spawnSync(
      process.execPath,
      [join(link, "validate-report.ts"), "verdict", missing ? join(root, "missing") : root],
      { encoding: "utf8" },
    );
    assert.ifError(result.error);
    assert.equal(result.status, missing ? 2 : 1, result.stderr);
    if (missing) assert.match(result.stderr, /Invalid Playwright evidence:/);
    else assert.equal(JSON.parse(result.stdout).passed, false);
  });
}

const mutations: [string, (data: Fixture) => void][] = [
  [
    "zero tests",
    ({ completion, results }) => {
      completion.tests = [];
      results.suites = [];
    },
  ],
  [
    "missing attempt",
    ({ completion }) => {
      completion.tests[0].attempts = [];
    },
  ],
  [
    "interrupted run",
    ({ completion }) => {
      completion.status = "interrupted";
    },
  ],
  [
    "global error",
    ({ completion }) => {
      completion.errors.push({ message: "worker crashed" });
    },
  ],
  [
    "JSON reporter error",
    ({ results }) => {
      results.errors.push({ message: "server failed" });
    },
  ],
  [
    "runner exit",
    ({ metadata }) => {
      metadata.exitCode = 2;
    },
  ],
  [
    "exit disagreement",
    ({ metadata }) => {
      metadata.exitCode = 1;
    },
  ],
  [
    "missing provenance",
    ({ metadata }) => {
      Reflect.deleteProperty(metadata.provenance, "site");
    },
  ],
  [
    "missing project",
    ({ completion }) => {
      completion.projects = [];
    },
  ],
  [
    "unexecuted project",
    ({ metadata, completion }) => {
      metadata.provenance.projects = "chromium,webkit";
      completion.projects.push("webkit");
    },
  ],
  [
    "stats disagreement",
    ({ results }) => {
      results.stats.expected = 2;
    },
  ],
  [
    "unknown outcome",
    ({ completion }) => {
      completion.tests[0].outcome = corrupt<TestOutcome>("unknown");
    },
  ],
  [
    "duplicate test",
    ({ completion }) => {
      completion.tests.push(completion.tests[0]);
    },
  ],
  [
    "skipped test",
    ({ completion }) => {
      completion.tests[0].attempts[0].status = "skipped";
    },
  ],
  [
    "malformed JSON",
    ({ root }) => {
      writeFileSync(join(root, "playwright-report/results.json"), "{");
    },
  ],
  [
    "missing HTML",
    ({ root }) => {
      rmSync(join(root, "playwright-report/index.html"));
    },
  ],
];

for (const [name, mutate] of mutations) {
  test(`fails closed: ${name}`, (t) => {
    const data = fixture(t);
    if (name === "malformed JSON" || name === "missing HTML") {
      mutate(data);
    } else {
      mutate(data);
      data.save();
    }
    assert.throws(() => validateReport(data.root));
  });
}

test("terminal infrastructure failure is not a valid report", (t) => {
  const data = fixture(t, true);
  data.completion.tests[0].attempts[0].failureKind = "infrastructure";
  data.save();
  assert.throws(() => validateReport(data.root), /infrastructure failure \(failed\)/);
});

// Every TestStatus, with every failure kind the reporter can record, has one
// explicit classification; the switch in classifyAttempt makes a new status a
// type error, and this table makes a changed classification a test failure.
const classifications: [TestStatus, FailureKind | null, AttemptClass["kind"]][] = [
  ["passed", null, "passed"],
  ["passed", "product", "invalid"],
  ["passed", "infrastructure", "invalid"],
  ["failed", "product", "product"],
  ["failed", "infrastructure", "infrastructure"],
  ["failed", null, "invalid"],
  ["timedOut", "infrastructure", "infrastructure"],
  ["timedOut", "product", "invalid"],
  ["timedOut", null, "invalid"],
  ["interrupted", "infrastructure", "infrastructure"],
  ["interrupted", "product", "invalid"],
  ["interrupted", null, "invalid"],
  ["skipped", "infrastructure", "invalid"],
  ["skipped", null, "invalid"],
];

for (const [status, failureKind, kind] of classifications) {
  test(`classifies a ${status} attempt with failure kind ${failureKind} as ${kind}`, () => {
    assert.equal(classifyAttempt({ status, failureKind }).kind, kind);
  });
}

function retried(data: Fixture, first: FailureKind, final: FailureKind | null, firstStatus: TestStatus = "failed") {
  const test = data.completion.tests[0];
  const json = data.results.suites[0].specs[0].tests[0];
  test.attempts[0].failureKind = first;
  test.attempts[0].status = json.results[0].status = firstStatus;
  const passed = final === null;
  const attachments = passed ? [] : ["test-results/trace.zip", "test-results/failure.png"];
  test.attempts.push({ status: passed ? "passed" : "failed", retry: 1, failureKind: final, attachments });
  json.results.push({
    status: passed ? "passed" : "failed",
    retry: 1,
    attachments: attachments.map((path) => ({ path })),
  });
  test.outcome = json.status = passed ? "flaky" : "unexpected";
  data.completion.status = passed ? "passed" : "failed";
  data.metadata.exitCode = passed ? 0 : 1;
  data.results.stats.unexpected = passed ? 0 : 1;
  data.results.stats.flaky = passed ? 1 : 0;
  data.save();
}

test("recovered infrastructure attempt passes and is counted", (t) => {
  const data = fixture(t, true);
  retried(data, "infrastructure", null);
  assert.deepEqual(validateReport(data.root), {
    passed: true,
    counts: { expected: 0, unexpected: 0, skipped: 0, flaky: 1 },
    infrastructureRetries: 1,
  });
});

test("recovered test-deadline attempt passes and is counted", (t) => {
  const data = fixture(t, true);
  retried(data, "infrastructure", null, "timedOut");
  assert.equal(validateReport(data.root).infrastructureRetries, 1);
});

// nixbot build 956 (PR #3273): an unretried attempt hit the whole-test
// deadline under load. It is terminal infrastructure, reported as such rather
// than as malformed evidence.
test("terminal test-deadline attempt is an infrastructure failure", (t) => {
  const data = fixture(t, true);
  const test = data.completion.tests[0];
  test.attempts[0].status = data.results.suites[0].specs[0].tests[0].results[0].status = "timedOut";
  test.attempts[0].failureKind = "infrastructure";
  data.save();
  assert.throws(() => validateReport(data.root), /infrastructure failure \(test deadline\)/);
});

test("recovered interrupted attempt passes; an unrecovered one is an infrastructure failure", (t) => {
  const data = fixture(t, true);
  retried(data, "infrastructure", null, "interrupted");
  assert.equal(validateReport(data.root).infrastructureRetries, 1);
  const terminal = fixture(t, true);
  const attempt = terminal.completion.tests[0].attempts[0];
  attempt.status = terminal.results.suites[0].specs[0].tests[0].results[0].status = "interrupted";
  attempt.failureKind = "infrastructure";
  terminal.save();
  assert.throws(() => validateReport(terminal.root), /infrastructure failure \(interrupted\)/);
});

test("a skipped attempt is not evidence, even before a passing retry", (t) => {
  const data = fixture(t, true);
  retried(data, "infrastructure", null, "skipped");
  assert.throws(() => validateReport(data.root), /skipped attempt/);
});

test("a product-classified test deadline is rejected", (t) => {
  const data = fixture(t, true);
  retried(data, "product", null, "timedOut");
  assert.throws(() => validateReport(data.root), /incomplete/);
});

test("infrastructure attempt cannot hide a terminal product failure", (t) => {
  const data = fixture(t, true);
  retried(data, "infrastructure", "product");
  const verdict = validateReport(data.root);
  assert.equal(verdict.passed, false);
  assert.equal(verdict.infrastructureRetries, 1);
});

test("missing or escaping attachment fails closed", (t) => {
  const data = fixture(t, true);
  for (const attachment of ["test-results/missing.zip", "../outside.zip", "/tmp/trace.zip"]) {
    data.completion.tests[0].attempts[0].attachments = [attachment];
    data.results.suites[0].specs[0].tests[0].results[0].attachments = [{ path: attachment }];
    data.save();
    assert.throws(() => validateReport(data.root));
  }
});

test("retry-to-pass remains a passing verdict with an explicit flaky count", (t) => {
  const data = fixture(t, true);
  const test = data.completion.tests[0];
  test.outcome = "flaky";
  test.attempts.push({ status: "passed", retry: 1, failureKind: null, attachments: [] });
  data.completion.status = "passed";
  data.metadata.exitCode = 0;
  const json = data.results.suites[0].specs[0].tests[0];
  json.status = "flaky";
  json.results.push({ status: "passed", retry: 1, attachments: [] });
  data.results.stats.unexpected = 0;
  data.results.stats.flaky = 1;
  data.save();
  assert.deepEqual(validateReport(data.root), {
    passed: true,
    counts: { expected: 0, unexpected: 0, skipped: 0, flaky: 1 },
    infrastructureRetries: 0,
  });
});

test("well-formed partial scenario inventory is rejected even when counts agree", (t) => {
  const data = fixture(t);
  const names = requiredCases["playwright.config.ts"];
  data.metadata.provenance.config = "playwright.config.ts";
  data.metadata.provenance.projects = "chromium,webkit";
  data.completion.projects = ["chromium", "webkit"];
  const template = data.completion.tests[0];
  const spec = data.results.suites[0].specs[0];
  data.completion.tests = ["chromium", "webkit"].flatMap((project) =>
    names.map((name, index) => ({ ...template, project, id: `${project}-${index}`, case: name })),
  );
  data.results.suites[0].specs = data.completion.tests.map(({ id }) => ({ ...spec, id }));
  data.results.stats.expected = names.length * 2;
  data.save();
  assert.equal(validateReport(data.root).passed, true);
  data.completion.tests.pop();
  data.results.suites[0].specs.pop();
  data.results.stats.expected--;
  data.save();
  assert.throws(() => validateReport(data.root), /partial\/unexpected scenario matrix/);
});

for (const system of ["aarch64-darwin", "x86_64-linux"]) {
  test(`independent ${system} engine policy rejects self-consistent chromium-only producer`, (t) => {
    const data = fixture(t);
    const names = requiredCases["playwright.config.ts"];
    data.metadata.provenance.config = "playwright.config.ts";
    data.metadata.provenance.system = system;
    const template = data.completion.tests[0];
    const spec = data.results.suites[0].specs[0];
    data.completion.tests = names.map((name, index) => ({ ...template, id: `case-${index}`, case: name }));
    data.results.suites[0].specs = names.map((_, index) => ({ ...spec, id: `case-${index}` }));
    data.results.stats.expected = names.length;
    data.save();
    assert.throws(() => validateReport(data.root), /required browser engines/);
  });
}

const engineMatrices: [string, Engine[]][] = [
  ["aarch64-darwin", ["chromium", "webkit"]],
  ["x86_64-linux", ["chromium", "firefox", "webkit"]],
];
for (const [system, projects] of engineMatrices) {
  test(`${system} requires every declared engine even with consistent producer metadata`, (t) => {
    const data = fixture(t);
    const names = requiredCases["playwright.config.ts"];
    const template = data.completion.tests[0];
    const spec = data.results.suites[0].specs[0];
    const saveMatrix = (engines: Engine[]) => {
      data.metadata.provenance.config = "playwright.config.ts";
      data.metadata.provenance.system = system;
      data.metadata.provenance.projects = engines.join(",");
      data.completion.projects = engines;
      data.completion.tests = engines.flatMap((project) =>
        names.map((name, index) => ({ ...template, project, id: `${project}-${index}`, case: name })),
      );
      data.results.suites[0].specs = data.completion.tests.map(({ id }) => ({ ...spec, id }));
      data.results.stats.expected = data.completion.tests.length;
      data.save();
    };
    saveMatrix(projects);
    assert.equal(validateReport(data.root).passed, true);
    for (const missing of projects) {
      saveMatrix(projects.filter((engine) => engine !== missing));
      assert.throws(() => validateReport(data.root), /required browser engines/);
    }
  });
}

test("unknown platform and malformed evidence epoch fail closed", (t) => {
  const data = fixture(t);
  data.metadata.provenance.system = "unknown";
  data.save();
  assert.throws(() => validateReport(data.root), /unknown system\/suite policy/);
  data.metadata.provenance.system = "aarch64-darwin";
  for (const epoch of [undefined, 0, "-1", "1.2", "", "01"]) {
    data.metadata.provenance.evidenceEpoch = corrupt<string>(epoch);
    data.save();
    assert.throws(() => validateReport(data.root), /invalid evidence epoch/);
  }
});
