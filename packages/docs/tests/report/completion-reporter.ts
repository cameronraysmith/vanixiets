import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import type {
  FullConfig,
  FullResult,
  Reporter,
  Suite,
  TestError,
  TestResult,
  TestStep,
} from "@playwright/test/reporter";

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

function failureKind(result: TestResult) {
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
    const completion = {
      schemaVersion: 1,
      status: result.status,
      projects: this.projects,
      errors: this.errors,
      tests: this.suite?.allTests().map((test) => ({
        id: test.id,
        project: test.parent.project()?.name,
        case: `${path.relative(this.rootDir, test.location.file)}::${test.title}`,
        title: test.titlePath().join(" > "),
        outcome: test.outcome(),
        expectedStatus: test.expectedStatus,
        attempts: test.results.map((attempt) => ({
          status: attempt.status,
          retry: attempt.retry,
          failureKind: failureKind(attempt),
          attachments: attempt.attachments
            .filter((attachment) => attachment.path)
            .map((attachment) => path.relative(process.cwd(), attachment.path as string)),
        })),
      })),
    };
    mkdirSync("playwright-report", { recursive: true });
    writeFileSync("playwright-report/completion.json", JSON.stringify(completion, null, 2));
  }
}
