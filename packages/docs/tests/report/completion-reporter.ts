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

function assertionErrors(steps: TestStep[]): TestError[] {
  return steps.flatMap((step) => [
    ...(step.category === "expect" && step.error ? [step.error] : []),
    ...assertionErrors(step.steps),
  ]);
}

function failureKind(result: TestResult) {
  if (result.status === "passed" && result.errors.length === 0) return null;
  const assertions = assertionErrors(result.steps);
  // Playwright serializes errors without matcherResult. Match against its
  // structured expect steps, not prose such as "Timeout" or "browser closed".
  return result.status === "failed" &&
    result.errors.length > 0 &&
    result.errors.every((error) =>
      assertions.some((assertion) => assertion.message === error.message && assertion.stack === error.stack),
    )
    ? "assertion"
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
