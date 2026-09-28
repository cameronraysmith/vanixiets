# Docs browser evidence

This directory defines the report contract for maintainers changing the docs browser checks.
A successful report build means that usable evidence exists, not that the site passed.

## Checks and consumption

The package-test registry exposes these attributes under `checks.<system>`:

- `package-vanixiets-docs-test-e2e-report`: runs the browser suite once and retains a valid report, even when assertions fail.
- `package-vanixiets-docs-test-e2e`: the existing mandatory verdict; validates the report dependency without running browsers again.
- `package-vanixiets-docs-test-e2e-negative-control`: runs the same reader journey against an intercepted guide response whose heading is damaged, then verifies the intended failure and its retained attachments.
- `docs-e2e-wiring`: asserts both public identities and the verdict's Nix dependency on that producer.
  Its negative fixture removes the verdict from the registry and must fail the same predicate.

The verdict and negative-control outputs contain a `report` symlink.
The independently enumerable producer gives nixbot a successful build artifact to expose even when the verdict fails.
This change does not publish artifacts or deploy the site.

```sh
node packages/docs/tests/report/validate-report.mjs validate /nix/store/...-vanixiets-docs-e2e-report-...
node packages/docs/tests/report/validate-report.mjs verdict /nix/store/...-vanixiets-docs-e2e-report-...
```

`validate` exits 0 for valid passing or assertion-failing evidence.
`verdict` exits 0 for a passing suite and 1 for a completed assertion-failing suite.
Both exit 2 for invalid evidence.
Successful validation prints `{passed, counts: {expected, unexpected, skipped, flaky}}`.

## Artifact contract, version 1

The producer retains:

- `run.json`: `schemaVersion`, original runner `exitCode`, and `provenance`.
  Provenance records `site`, `source`, `dependencies`, `browsers`, and `node` Nix store paths, plus `system`, `config`, comma-separated `projects`, and `trace`.
- `playwright-report/index.html` and the HTML reporter's `data/` attachments.
- `playwright-report/results.json`: Playwright's JSON report, with attachment paths made relative to the artifact root.
- `playwright-report/completion.json`: `schemaVersion`, full-run `status`, selected `projects`, global `errors`, and `tests`.
  Each test records `id`, `project`, independent policy `case`, human-readable `title`, `outcome`, `expectedStatus`, and `attempts`.
  Each attempt records `status`, `retry`, `failureKind` (`null`, `assertion`, or `infrastructure`), and relative `attachments`.
- `test-results/`: original traces, screenshots, videos, and error context; `runner.log`: original runner stdout/stderr.

The validator reconciles the completion inventory, JSON report, exit status, per-attempt results, and counts.
`policy.mjs` specifies the required scenario/project matrix independently of test discovery, including the reader journey.
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

The completion reporter matches each failed result error's message and stack to a failed public Playwright step with category `expect`.
It does not infer infrastructure status from error-message keywords.
Launch, hook, navigation, or worker failures without matching assertion steps are rejected conservatively.
Global reporter errors and nonstandard exit codes are always rejected.
An infrastructure fault deliberately wrapped in an assertion can still appear as an assertion failure; this is not a perfect causal classifier.
The native-runner controls exercise an absent browser executable, a throwing global setup, and an empty test selection.

The implementation was grounded in the locked `playwright@1.63.0` package from the docs dependency output, not a newer checkout.
In that distribution, `lib/runner/index.js` implements JSON serialization (`_serializeTestResult`) and omits `expect` steps from JSON, retaining only `test.step`.
`lib/util.js` serializes errors without `matcherResult`, which is why a narrow public reporter records completion and assertion-step evidence.
`lib/worker/workerProcessEntry.js` implements `_shouldCaptureTrace` and `_shouldAbandonTrace`: `retain-on-failure` captures each attempt and discards successful attempts.
The browser distribution comes from the separately locked `playwright-web-flake` input.
Recheck these boundaries when upgrading Playwright.

## Caching and limitations

The Nix derivation depends on the filtered docs source, built site, dependency tree, runtime, browser distribution, and platform environment.
Neither a PR SHA nor wall-clock time is an input to its cache key.
Reports do contain observed timings, runtime paths, and browser-generated identifiers, so report bytes are not promised to reproduce identically.
Provenance uses full store paths, retaining the referenced site, dependencies, and browser closures.
That improves replayability but increases artifact closure storage and transfer costs.

Invalid/incomplete runs fail the producer; they have Nix build logs, not a successful report output.
They must never be presented as a passing or assertion-failing completed report.
Tests cover the local built site and synthetic failure controls, not a deployed site, live nixbot API retrieval, or the report publisher.

Run the protocol tests with installed dependencies using `node --test tests/report-*.test.mjs` from `packages/docs`, or build `package-vanixiets-docs-test-unit`.
The unit check also runs the existing Vitest suite.
Native Darwin checks use Chromium and WebKit; Linux checks use Chromium, Firefox, and WebKit.
For Linux validation on this fleet, explicitly allow only magnetite and pyrite-builder; do not use Rosetta.
