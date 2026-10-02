import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import type {
  FullConfig,
  FullResult,
  Reporter,
  Suite,
  TestError,
  TestResult,
  TestStatus,
  TestStep,
} from "@playwright/test/reporter";

// completion.json, schema version 1: the only producer of this shape, and the
// type validate-report.ts parses untrusted JSON into.
export type FailureKind = "product" | "infrastructure";
// TestCase.outcome()'s values; the reporter assigns outcome() to this type,
// so a new Playwright outcome fails the type check.
export type TestOutcome = "skipped" | "expected" | "unexpected" | "flaky";
export type CompletionAttempt = {
  status: TestStatus;
  retry: number;
  failureKind: FailureKind | null;
  attachments: string[];
};
export type CompletionTest = {
  id: string;
  project: string;
  case: string;
  title: string;
  outcome: TestOutcome;
  expectedStatus: TestStatus;
  attempts: CompletionAttempt[];
};
export type Completion = {
  schemaVersion: 1;
  status: FullResult["status"];
  projects: string[];
  errors: TestError[];
  tests: CompletionTest[];
};

function productErrors(steps: TestStep[]): TestError[] {
  return steps.flatMap((step) => {
    // Setup/teardown assertions and actions are infrastructure, not reader work.
    if (step.category === "hook" || step.category === "fixture") return [];
    // Public 1.63 metadata identifies locator operations without trusting a
    // pw:api category alone (browserType.launch also uses that category).
    // Only bounded auto-wait timeouts qualify; crashes/closed pages and other
    // API exceptions remain infrastructure. Test-level deadlines never qualify.
    const locatorTimeout =
      step.category === "pw:api" &&
      typeof step.params?.locator === "string" &&
      /^(Click|Double click|Check|Uncheck|Hover|Tap|Select option|Set input files|Fill ".*"|Press ".*")$/.test(
        step.title,
      ) &&
      step.error?.message?.startsWith("TimeoutError:");
    return [
      ...((step.category === "expect" || locatorTimeout) && step.error ? [step.error] : []),
      ...productErrors(step.steps),
    ];
  });
}

function failureKind(result: TestResult): FailureKind | null {
  if (result.status === "passed" && result.errors.length === 0) return null;
  const failures = productErrors(result.steps);
  // Every reported error must have matching completed product-step evidence.
  // A second hook/worker error must not be hidden by a legitimate product error.
  return result.status === "failed" &&
    result.errors.length > 0 &&
    result.errors.every((error) =>
      failures.some((failure) => failure.message === error.message && failure.stack === error.stack),
    )
    ? "product"
    : "infrastructure";
}

export default class CompletionReporter implements Reporter {
  private suite?: Suite;
  private errors: TestError[] = [];
  private projects: string[] = [];
  private rootDir = "";

  onBegin(config: FullConfig, suite: Suite) {
    this.suite = suite;
    this.projects = config.projects.map((project) => project.name);
    this.rootDir = config.rootDir;
  }

  onError(error: TestError) {
    this.errors.push(error);
  }

  onEnd(result: FullResult) {
    const completion: Completion = {
      schemaVersion: 1,
      status: result.status,
      projects: this.projects,
      errors: this.errors,
      tests: (this.suite?.allTests() ?? []).map((test) => ({
        id: test.id,
        // A test always belongs to a project; an empty name fails validation.
        project: test.parent.project()?.name ?? "",
        case: `${path.relative(this.rootDir, test.location.file)}::${test.title}`,
        title: test.titlePath().join(" > "),
        outcome: test.outcome(),
        expectedStatus: test.expectedStatus,
        attempts: test.results.map((attempt) => ({
          status: attempt.status,
          retry: attempt.retry,
          failureKind: failureKind(attempt),
          attachments: attempt.attachments.flatMap((attachment) =>
            attachment.path ? [path.relative(process.cwd(), attachment.path)] : [],
          ),
        })),
      })),
    };
    mkdirSync("playwright-report", { recursive: true });
    writeFileSync("playwright-report/completion.json", JSON.stringify(completion, null, 2));
  }
}
