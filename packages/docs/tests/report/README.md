# Docs browser evidence

This directory defines the report contract for maintainers changing the docs browser checks.
A successful report build means that usable evidence exists, not that the site passed.

## Checks and consumption

The package-test registry exposes these attributes under `checks.<system>`:

- `package-vanixiets-docs-test-e2e-report`: runs the browser suite once and retains a valid report, even when product checks fail.
- `package-vanixiets-docs-test-e2e`: the existing mandatory verdict; validates the report dependency without running browsers again.
- `package-vanixiets-docs-test-e2e-negative-control`: runs the same reader journey against an intercepted guide response whose heading is damaged, then verifies the intended failure and its retained attachments.
- `package-vanixiets-docs-test-e2e-action-negative-control`: removes the homepage's Getting started links from the intercepted HTML, runs the unchanged reader journey, and verifies a completed locator timeout, verdict exit 1, and retained trace/screenshot.
- `package-vanixiets-docs-test-e2e-runner-controls`: native-browser classification controls, separated from the browser-free unit check.
- `docs-e2e-wiring`: asserts both public identities and the verdict's Nix dependency on that producer.
  Its negative fixtures omit the verdict or supply a successfully built verdict consuming a different producer; both must fail the same predicate.

The verdict output is an empty success marker with no runtime store references.
The negative-control output retains a `report` symlink for inspection.
The independently enumerable producer gives nixbot a successful build artifact to expose even when the verdict fails.
This change does not publish artifacts or deploy the site.

```sh
node packages/docs/tests/report/validate-report.mjs validate /nix/store/...-vanixiets-docs-e2e-report-...
node packages/docs/tests/report/validate-report.mjs verdict /nix/store/...-vanixiets-docs-e2e-report-...
```

`validate` exits 0 for valid passing or product-failing evidence.
`verdict` exits 0 for a passing suite and 1 for a completed product-failing suite.
Both exit 2 for invalid evidence.
Successful validation prints `{passed, counts: {expected, unexpected, skipped, flaky}}`.

## Artifact contract, version 1

The producer retains:

- `run.json`: `schemaVersion`, original runner `exitCode`, and `provenance`.
  Provenance records `site`, `source`, `dependencies`, `browsers`, and `node` Nix store paths, plus `system`, `config`, comma-separated `projects`, and `trace`.
  `evidenceEpoch` is a canonical nonnegative decimal string identifying an explicitly requested observation generation.
- `playwright-report/index.html` and the HTML reporter's `data/` attachments.
- `playwright-report/results.json`: Playwright's JSON report, with attachment paths made relative to the artifact root.
- `playwright-report/completion.json`: `schemaVersion`, full-run `status`, selected `projects`, global `errors`, and `tests`.
  Each test records `id`, `project`, independent policy `case`, human-readable `title`, `outcome`, `expectedStatus`, and `attempts`.
  Each attempt records `status`, `retry`, `failureKind` (`null`, `product`, or `infrastructure`), and relative `attachments`.
- `test-results/`: original traces, screenshots, videos, and error context; `runner.log`: original runner stdout/stderr.

The validator reconciles the completion inventory, JSON report, exit status, per-attempt results, and counts.
`policy.mjs` specifies the required scenario/project matrix independently of test discovery, including the reader journey.
Its independently declared engine policy requires Chromium and WebKit on Darwin, and Chromium, Firefox, and WebKit on Linux.
Only the two named negative-control suites have a Chromium-only exception; unknown systems/configs fail closed.
Narrowing both producer metadata and discovery cannot narrow the required matrix.
Update it deliberately when adding or removing a scenario; deleting a spec alone must fail validation.
Zero tests, partial matrices, skips, expected failures, interrupted/timed-out attempts, global errors, unknown outcomes, and missing or empty referenced files fail closed.
Referenced attachment paths cannot escape the artifact, including through symlinks.
Every failed attempt must have a trace and screenshot; every referenced video must exist, but a video is not mandatory if Playwright emitted none.
Attachment validation checks containment, existence, and nonempty content, not archive/media decoding.

The existing CI retry policy remains two retries.
A recovered retry is accepted with a nonzero `flaky` count, not reported as clean first-attempt success.
The negative control disables retries.
`trace: "retain-on-failure"` captures the original failing attempt, unlike the previous `on-first-retry` policy.
HTML/JSON serve artifact readers; the line reporter serves nixbot build logs without GitHub-specific annotations.

## Failure classification boundary

The completion reporter matches every failed result error's message and stack to a failed public Playwright product step.
A product step is either a test-body `expect`, or a bounded auto-wait timeout from an allowlisted locator action.
Locator actions require all three public metadata checks: category `pw:api`, a string `params.locator`, and a known action title.
They additionally require the serialized `TimeoutError:` type prefix, not a generic "timeout" substring; closed-page errors are rejected.
Hook and fixture subtrees are excluded even when they contain assertions or locator actions.
Only completed `failed` attempts qualify: whole-test deadlines (`timedOut`), launch, navigation, arbitrary API exceptions, and worker failures fail closed.
Action and navigation budgets are 5 and 10 seconds respectively, below the 30-second test deadline.
Global reporter errors and nonstandard exit codes are always rejected.
An infrastructure fault deliberately wrapped in an assertion can still appear as an assertion failure; this is not a perfect causal classifier.
The browser-free native-runner controls exercise an absent browser executable, a throwing global setup, and an empty test selection.
The separate native-browser controls exercise assertions, locator action timeouts, hook actions/assertions, whole-test deadlines, worker exit, and a closed page.

The implementation was grounded in the locked `playwright@1.63.0` package from the docs dependency output, not a newer checkout.
In that distribution, `lib/runner/index.js` implements JSON serialization (`_serializeTestResult`) and omits `expect` steps from JSON, retaining only `test.step`.
`lib/util.js` serializes errors without `matcherResult`, which is why a narrow public reporter records completion and assertion-step evidence.
`types/testReporter.d.ts` exposes `TestStep.params`, `title`, `category`, and parent/child steps.
`lib/index.js` builds `pw:api` steps through `renderTitle` and `renderParamsForCall`; the pinned `playwright-core/lib/coreBundle.js` action metadata renders locator selectors as `params.locator` and titles such as `Click`.
The serialized error preserves its type prefix, but not a separate public error-name field.
This is intentionally a bounded classifier, not an oracle for arbitrary future APIs or causal infrastructure failures that manifest as ordinary action timeouts.
`lib/worker/workerProcessEntry.js` implements `_shouldCaptureTrace` and `_shouldAbandonTrace`: `retain-on-failure` captures each attempt and discards successful attempts.
The browser distribution comes from the separately locked `playwright-web-flake` input.
Recheck these boundaries when upgrading Playwright.

## Caching and limitations

The Nix derivation depends on the filtered docs source, built site, dependency tree, runtime, browser distribution, and platform environment.
Neither a PR SHA nor wall-clock time is an input to its cache key.
The explicit `evidenceEpoch` is a report-only input, read from `pkgs/by-name/vanixiets-docs/evidence-epoch` and recorded in `run.json`.
Reports do contain observed timings, runtime paths, and browser-generated identifiers, so report bytes are not promised to reproduce identically.
Provenance uses full store paths, retaining the referenced site, dependencies, and browser closures.
That improves replayability but increases artifact closure storage and transfer costs.
At review head `d9d44f5c`, the Darwin verdict retained about 2.3 GiB through its report symlink while the report directory itself was about 580 KiB.
Removing that symlink reduced the verdict output closure to 96 bytes with no references in the native Darwin measurement.
The report producer still deliberately retains its provenance closure; removing the verdict reference does not eliminate that separate cost.
Resolve evidence through the named producer, not the verdict output.

### Intentionally collect a fresh required observation

A valid report with failed assertions is cached like any other successful derivation.
Restarting its failed verdict reuses that observation.
Pinned nixbot's attribute restart invokes ordinary `nix build`; it does not invalidate successful report outputs.
`nix build --rebuild` is a reproducibility comparison, not a replacement operation: changed report bytes produce a nondeterminism error instead of updating the report consumed by the verdict.
Do not delete store/cache objects or upload changed evidence under an existing output identity.

To request a new required observation:

1. Inspect the prior failure and record its report/build identity.
2. Increment the decimal value in `pkgs/by-name/vanixiets-docs/evidence-epoch`; never reuse an earlier value for the same inputs.
3. Include the reason and old evidence identity in that change's review.
4. Build the normal report and required verdict, or let nixbot build the new commit.
5. Check the new report's `provenance.evidenceEpoch` and the actual build log before claiming fresh execution.

The application build and browser/dependency packages retain their identities; only the report and its consumers change.
`docs-evidence-cache` checks that boundary, stable reuse for an unchanged epoch, and rejection of invalid epochs.
Further builds of the same epoch intentionally reuse the observation.
An epoch increment is not a pass override, a fix, or permission to dismiss flakiness.
Keep the original negative evidence and compare the new result; repeated failures still require diagnosis.

For a local diagnostic without changing the committed gate, override the package's `evidenceEpoch` with a new decimal string and build its report.
Such a result does not replace the report selected by the source-controlled required check.

Invalid/incomplete runs fail the producer; they have Nix build logs, not a successful report output.
They must never be presented as a passing or product-failing completed report.
Tests cover the local built site and synthetic failure controls, not a deployed site, live nixbot API retrieval, or the report publisher.

Run the protocol tests with installed dependencies using `node --test tests/report-*.test.mjs` from `packages/docs`, or build `package-vanixiets-docs-test-unit`.
The unit check also runs the existing Vitest suite.
Run `node --test tests/browser-report.test.mjs` with the pinned `PLAYWRIGHT_BROWSERS_PATH` for the separate native-browser controls, or build `package-vanixiets-docs-test-e2e-runner-controls`.
Native Darwin checks use Chromium and WebKit; Linux checks use Chromium, Firefox, and WebKit.
For Linux validation on this fleet, explicitly allow only magnetite and pyrite-builder; do not use Rosetta.
