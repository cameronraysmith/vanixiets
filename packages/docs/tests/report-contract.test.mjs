import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { requiredCases } from "./report/policy.mjs";
import { validateReport } from "./report/validate-report.mjs";

function fixture(t, failed = false) {
  const root = mkdtempSync(join(tmpdir(), "docs-report-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, "playwright-report"));
  mkdirSync(join(root, "test-results"));
  writeFileSync(join(root, "playwright-report/index.html"), "<html>report</html>");
  writeFileSync(join(root, "test-results/trace.zip"), "trace fixture");
  writeFileSync(join(root, "test-results/failure.png"), "screenshot fixture");
  const attachments = failed ? ["test-results/trace.zip", "test-results/failure.png"] : [];
  const status = failed ? "failed" : "passed";
  const outcome = failed ? "unexpected" : "expected";
  const completion = {
    schemaVersion: 1,
    status,
    projects: ["chromium"],
    errors: [],
    tests: [
      {
        id: "reader-chromium",
        project: "chromium",
        case: "reader-journey.spec.ts::damaged guide is rejected by the real reader journey",
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
  const results = {
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
  const metadata = {
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
      [join(link, "validate-report.mjs"), "verdict", missing ? join(root, "missing") : root],
      { encoding: "utf8" },
    );
    assert.ifError(result.error);
    assert.equal(result.status, missing ? 2 : 1, result.stderr);
    if (missing) assert.match(result.stderr, /Invalid Playwright evidence:/);
    else assert.equal(JSON.parse(result.stdout).passed, false);
  });
}

for (const [name, mutate] of [
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
      delete metadata.provenance.site;
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
      completion.tests[0].outcome = "unknown";
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
]) {
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

test("non-assertion runner failure is not a valid report", (t) => {
  const data = fixture(t, true);
  data.completion.tests[0].attempts[0].failureKind = "infrastructure";
  data.save();
  assert.throws(() => validateReport(data.root), /infrastructure/);
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

for (const [system, projects] of [
  ["aarch64-darwin", ["chromium", "webkit"]],
  ["x86_64-linux", ["chromium", "firefox", "webkit"]],
]) {
  test(`${system} requires every declared engine even with consistent producer metadata`, (t) => {
    const data = fixture(t);
    const names = requiredCases["playwright.config.ts"];
    const template = data.completion.tests[0];
    const spec = data.results.suites[0].specs[0];
    const saveMatrix = (engines) => {
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
    data.metadata.provenance.evidenceEpoch = epoch;
    data.save();
    assert.throws(() => validateReport(data.root), /invalid evidence epoch/);
  }
});
