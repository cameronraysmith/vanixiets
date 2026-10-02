# Docs browser evidence

This directory defines the report contract for maintainers changing the docs browser checks.
A successful report build means that usable evidence exists, not that the site passed.

## Checks and consumption

The package-test registry exposes these attributes under `checks.<system>`:

- `package-vanixiets-docs-test-e2e-report`: runs the browser suite once and retains a valid report, even when product checks fail.
- `package-vanixiets-docs-test-e2e`: the existing mandatory verdict; validates the report dependency without running browsers again.
- `package-vanixiets-docs-test-e2e-negative-control`: runs the same reader journey against an intercepted guide response whose heading is damaged, then verifies the intended failure and its retained attachments.
- `package-vanixiets-docs-test-e2e-action-negative-control`: removes the homepage's Getting started links from the intercepted HTML, runs the unchanged reader journey, and verifies a completed locator timeout, verdict exit 1, and retained trace/screenshot.
- `package-vanixiets-docs-test-e2e-webkit-negative-control`: runs the damaged-guide journey on WebKit alone, on every system, and verifies the completed failure, verdict exit 1, the trace, and a PNG screenshot with a valid nonzero-sized header.
- `package-vanixiets-docs-test-e2e-runner-controls`: native-browser classification controls, separated from the browser-free unit check.
- `docs-e2e-wiring`: asserts both public identities and the verdict's Nix dependency on that producer.
  Its negative fixtures omit the verdict or supply a successfully built verdict consuming a different producer; both must fail the same predicate.

The verdict output is an empty success marker with no runtime store references.
The negative-control output retains a `report` symlink for inspection.
The independently enumerable producer gives nixbot a successful build artifact to expose even when the verdict fails.
These checks do not publish artifacts or deploy the site.

```sh
node packages/docs/tests/report/validate-report.ts validate /nix/store/...-vanixiets-docs-e2e-report-...
node packages/docs/tests/report/validate-report.ts verdict /nix/store/...-vanixiets-docs-e2e-report-...
```

`validate` exits 0 for valid passing or product-failing evidence.
`verdict` exits 0 for a passing suite and 1 for a completed product-failing suite.
Both exit 2 for invalid evidence.
Successful validation prints `{passed, counts: {expected, unexpected, skipped, flaky}, infrastructureRetries}`.

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

The validator first parses the three JSON files into types taken from the completion reporter and Playwright's published JSON report declarations, rejecting any value outside them, then reconciles the completion inventory, JSON report, exit status, per-attempt results, and counts.
Each attempt is classified by an exhaustive match on Playwright's `TestStatus`: `passed`; a `failed` product failure; an infrastructure failure (`failed`, `timedOut`, or `interrupted` with an infrastructure kind); or invalid, which includes every `skipped` attempt.
`policy.ts` specifies the required scenario/project matrix independently of test discovery, including the reader journey.
Its independently declared engine policy requires Chromium and WebKit on Darwin, and Chromium, Firefox, and WebKit on Linux.
The Chromium negative-control suites require Chromium only; the WebKit negative-control suite requires WebKit only; unknown systems/configs fail closed.
Narrowing both producer metadata and discovery cannot narrow the required matrix.
Update it deliberately when adding or removing a scenario; deleting a spec alone must fail validation.
Zero tests, partial matrices, skips, expected failures, interrupted attempts, a terminal timed-out attempt, global errors, unknown outcomes, and missing or empty referenced files fail closed.
Referenced attachment paths cannot escape the artifact, including through symlinks.
Every product-failed attempt must have a trace and screenshot; every referenced video must exist, but a video is not mandatory if Playwright emitted none.
Attachment validation checks containment, existence, and nonempty content, not archive/media decoding.

The existing CI retry policy remains two retries, for the positive suite and the negative controls alike.
A recovered retry is accepted with a nonzero `flaky` count, not reported as clean first-attempt success.
An infrastructure-class attempt is accepted only when a later attempt of the same test completed, as a pass or a product failure; `infrastructureRetries` counts them, and a terminal infrastructure attempt is invalid evidence.
The negative controls require every attempt to fail and the terminal attempt to be a product failure, so a retry can absorb a stalled navigation but never the deliberate defect.
Report builds run at most four workers: CI builders grant every concurrent build all cores, so `NIX_BUILD_CORES` overstates what one build may use.
`trace: "retain-on-failure"` captures the original failing attempt, unlike the previous `on-first-retry` policy.
HTML/JSON serve artifact readers; the line reporter serves nixbot build logs without GitHub-specific annotations.

### WebKit failure screenshots

On Darwin the Nix build users (`_nixbld*`) have no LaunchServices database (their `$DARWIN_USER_DIR/0/` holds no `com.apple.LaunchServices.dv`).
WebKit's sandboxed WebContent process resolves `image/png` through LaunchServices, so ImageIO is asked for an empty type identifier (`unsupported output file format ''`).
`Page.snapshotRect` then returns `data:,`, and Playwright 1.63 writes the empty buffer as a 0-byte `test-failed-1.png` without raising.
Rendering itself works: canvas pixels and screencast frames are correct, while `canvas.toDataURL()` returns `data:,` for the same reason.
Running as the normal user, even with the build's exact environment, produces real screenshots; running as `_nixbld9` through `sudo` outside Nix reproduces the empty file.

Every browser spec therefore imports `test` from `e2e/fixtures.ts`.
For WebKit it records the latest screencast frame.
Only if Playwright's own failure screenshot is a 0-byte file does it write that frame, converted to PNG, into the same attachment.
First it waits for the frame stream to stay quiet for 500 ms, because frames trail paints.
The frame is the video's downscaled viewport (800x450 bounds), not a device-pixel capture.
If no painted frame exists, the fixture teardown throws, so the attempt fails as infrastructure rather than carrying a blank image.
The validator still rejects any empty attachment.

## Publication

`publish-evidence` (`modules/apps/docs/publish-evidence.sh` documents its interface) publishes this contract's evidence; the `browser-evidence` effect runs it from `main`'s code.
It has two modes:

- `build-finished [--out <dir>] [--upload]`: the `build_finished` sidecar, which looks the event's build up by number; nixbot sends this for pull request builds and other newly finished builds, whether the aggregate succeeded or failed.
- `main --rev <commit> [--out <dir>] [--upload]`: the onPush run for `main`, which looks up the highest-numbered build of that commit; a fast-forward landing reuses the merge-queue build and sends no `build_finished`.

Both modes look up `checks.x86_64-linux.package-vanixiets-docs-test-e2e-report` through nixbot's build API and realise the recorded output; a missing, failed, or unrealisable output is reported as unavailable evidence, never rebuilt.
They validate the report with the program's own copy of `validate-report.ts` and stage only `run.json`, `playwright-report/completion.json`, and PNG screenshots referenced by attempts, beside a deterministic `receipt.json` (schema version 3) carrying the report's identity (attribute and output path), provenance, verdict, and file digests, and nothing about the build that produced it.
Product-failing reports are published with `passed: false`; invalid evidence, unsafe attachment paths, symlinks, non-PNG screenshots, and build/report identity mismatches are rejected.
`publish-evidence-rehearsal` exercises both modes against a loopback nixbot API, a chroot store, and stub storage and comment endpoints.

### Where evidence goes

With `--upload`, the bundle goes to the R2 bucket `sciexp` under `projects/vanixiets/browser-evidence/<tier>/v1/<obs>/`.
`<obs>` is the first 32 hex digits of the SHA-256 of `[attribute, output path]`, so every build carrying the same report writes the same keys, and a repeat reports `unchanged` instead of uploading again.
The tier sets retention: `ttl-90d` for `main` and other builds without a pull request, `ttl-30d` for a pull request whose report `main` has not published.
Objects are deleted by age; nothing renews them.

A pull request build first checks whether `main` has already published this exact report, that is, whether `ttl-90d/v1/<obs>/receipt.json` exists.
If it has, the pull request does not change the docs browser evidence: nothing is uploaded, no comment is posted, and the log prints `PUBLISH-EVIDENCE: unaffected (report <obs> already published from main)`.
Otherwise the build uploads to `ttl-30d` and comments.
The report's Nix output path decides this, since it changes exactly when an input of the report changes.
A report that differs from every report published from `main` in the last 90 days counts as a change, even when `main`'s evidence for it has expired or `main`'s publish run failed.

Read evidence at `https://evidence.vanixiets.net/vanixiets/browser-evidence/<tier>/v1/<obs>/<file>`, for example `.../receipt.json` or a screenshot path from it; the URL path is the object key after `projects/`.
The host serves only `.png` and `.json` files and does not list directories, so start from a link in a comment, a log line, or a receipt.
The receipt's `destination` gives the bucket, key prefix, tier, and this base URL.
The effect log prints `PUBLISH-EVIDENCE: uploaded <url>` for the base URL when the run wrote the receipt, and `PUBLISH-EVIDENCE: published` or `unchanged` with the report's `<obs>` and verdict.

### Reading the pull request comment

For a pull request whose report `main` has not published, the effect posts one comment through nixbot and edits it on later builds instead of adding another.
It shows:

- the verdict, passed or failed, with the expected, unexpected, skipped, and flaky counts;
- the build number, linked to the build, and the first 12 hex digits of its revision;
- a link to each screenshot of a failed attempt and to `receipt.json`;
- that the evidence is kept 30 days;
- that no report identical to this one has been published from `main` in the last 90 days, which is why it is shown.

If a later build of the pull request produces the same report as `main`, the effect replaces the comment with a short note, without links, saying that the evidence previously linked no longer describes a change, and naming the shared report, the build, and the revision.
When two builds of a pull request finish out of order, the comment reflects whichever finished last.

The comment describes the build named in it, which may be older than the pull request's current head when the report was reused from cache; the receipt names no build, since one report serves every build that carries it.
A passing verdict with no screenshots is expected: screenshots are taken only for failed attempts.
For traces, the HTML report, and other attachments, build the named report attribute locally; they are not published.

## Failure classification boundary

The completion reporter matches every failed result error's message and stack to a failed public Playwright product step.
A product step is either a test-body `expect`, or a bounded auto-wait timeout from an allowlisted locator action.
Locator actions require all three public metadata checks: category `pw:api`, a string `params.locator`, and a known action title.
They additionally require the serialized `TimeoutError:` type prefix, not a generic "timeout" substring; closed-page errors are rejected.
Hook and fixture subtrees are excluded even when they contain assertions or locator actions.
Only completed `failed` attempts qualify: whole-test deadlines (`timedOut`), launch, navigation, arbitrary API exceptions, and worker failures fail closed.
The action budget is 5 seconds, below the 30-second test deadline; navigations have no separate budget, since a failed navigation is never product evidence.
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

Darwin report builds are unsandboxed and share the host network, so report builds that run concurrently (the producer and every negative-control report) must not share any fixed listening port.
The e2e-report build phase asks the kernel for a free loopback port and exports it as `DOCS_PREVIEW_PORT`; `playwright.config.ts` passes it to the preview command as `--port` and uses it for `webServer.url` and `baseURL` (`BASE_URL` still overrides `baseURL`).
Unset, the port is 4321, so local runs are unchanged.
The port is released just before astro preview binds it, so another process can claim it in that window; that is unlikely within milliseconds, and the outcome is an infrastructure failure: under `CI` Playwright refuses a URL that already answers, and astro preview (Vite without `strictPort`) moves to another port, so the configured URL never comes up and the webServer start times out.
The preview's workerd also opens a debugger inspector, which `@cloudflare/vite-plugin` places on the first free port from 9229 upward; concurrent builds race between that probe and the bind (`EADDRINUSE 127.0.0.1:9231` was observed).
The e2e-report derivation therefore sets `DOCS_DISABLE_WORKER_INSPECTOR=1`, and `astro.config.ts` then passes `inspectorPort: false` to the Cloudflare adapter, so the preview opens no inspector port; nothing in a report build attaches a debugger.
Without that variable, local `bun run dev` and `astro preview` keep the default inspector.

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
Tests cover the local built site and synthetic failure controls, not a deployed site or live nixbot API retrieval; the publisher is rehearsed separately against a loopback API.

Run the protocol tests with installed dependencies using `node --test tests/report-*.test.ts` from `packages/docs`, or build `package-vanixiets-docs-test-unit`; Node strips the types at load time.
The unit check also runs the existing Vitest suite.
`package-vanixiets-docs-test-typecheck` type-checks the tooling and tests with `tsc -p packages/docs/tests`.
Run `node --test tests/browser-report.test.ts` with the pinned `PLAYWRIGHT_BROWSERS_PATH` for the separate native-browser controls, or build `package-vanixiets-docs-test-e2e-runner-controls`.
Native Darwin checks use Chromium and WebKit; Linux checks use Chromium, Firefox, and WebKit.
For Linux validation on this fleet, explicitly allow only magnetite and pyrite-builder; do not use Rosetta.
