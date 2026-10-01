# Verification ledger

This file distinguishes inherited evidence, current implementation checks, and planned demonstrations.
No entry below claims live deployment or evidence publication.

## Requirement traceability

| Requirements | Intended evidence | Current state |
| --- | --- | --- |
| R1 | Committed journey with independent expected outcomes and required verdict | Implemented; real browser checks pass |
| R2 | Completed negative report retains attachments and is discoverable by named check | Report and negative control pass; live API retrieval pending |
| R3 | CLI reproduction and reviewed correction followed by independent rerun | Mobile hero overflow reproduced with Playwright CLI; strengthened scenario fails the required gate on Linux with a kept report and passes after the CSS correction on Linux and Darwin; review pending |
| R4 | Relevant-input identity and cache-reuse receipt | Pending; whole-build reuse does not emit build_finished |
| R5 | Isolated browser/profile/fixture cleanup checks | CLI smoke has isolation; harness integration pending |
| R6 | Trusted publisher rehearsal, malformed metadata rejection, no PR evaluation | Loopback rehearsal passes on Darwin and Linux; live effect pending |
| R7 | Deliberate defect rejected for the expected reason | Damaged-guide and removed-link controls (Chromium) and a damaged-guide control (WebKit) rejected with retained trace and screenshot on both platforms |
| R8 | Documented lifecycle seam, later exercised by a second application | Design only |

## Prior evidence and its limits

Before the latest rebases, the Playwright CLI smoke passed on native aarch64-darwin and x86_64-linux through Magnetite.
It exercised browser launch, a real button click, rendered text, nonzero font height, snapshot output, and cleanup.
The Linux run first failed because rendered text was empty; supplying a default font configuration made it pass.
The smoke clears inherited browser-control variables so it cannot accidentally attach to a live profile.
These results do not validate the proposed report/verdict split or APM skill route.

`nix develop --accept-flake-config -c just lint` passed gitleaks and treefmt on the prior base `7b7d78d3609dadb43e5a5c6d8c5fb3083d0044f2`.
The implementation checkout was then rebased onto `af98cc44c25664c5658b36f4d8f5251aa2022188`.
New changes require new validation.

## Initial implementation history

After that rebase and addition of this design tree, `nix develop --accept-flake-config -c just lint` completed with exit status 0: gitleaks and treefmt passed.
Nix emitted a nonfatal evaluation-cache SQLite contention warning.
This run covers the parent checkout's design and existing capability changes, not the isolated workers' unfinished APM, report, or registry changes.
That was the state at this particular lint run, not the current integration status; subsequent entries record their integration.

### Registry prerequisite

The isolated registry worker reports exit status 0 for:

```sh
nixfmt --check modules/effects/vanixiets/registry.nix modules/checks/effects-interpreter.nix
nix build .#checks.aarch64-darwin.effects-interpreter \
  .#checks.aarch64-darwin.effect-run-context --no-link --builders '' -L
```

The effects interpreter rebuilt; effect-run-context was reused from cache.
The worker first observed the missing buildFinished option, then independently the missing build_finished mapping before implementing each.
Its 18 script cases and two structural comparisons exercise the actual registry mapping, literal arguments, secret isolation, defaults, and absence of the main-only guard.
Linux effect derivations were evaluated for metadata, not built or run.
The parent reviewed the two-file diff and reran both native Darwin checks after integration; both completed with exit status 0 using cached outputs.
`git diff --check` also passed.
This evidence does not cover artifact publication.

### APM skill integration

The parent reviewed the source/manifest drift guards and confirmed that root `apm.lock.yaml` has no diff.
After integration, native Darwin builds of `playwright-cli-consumers` and `omnigent-worker-capabilities` completed with exit status 0.
The worker additionally reports successful x86_64-linux versions using only Magnetite/Pyrite builders, clean frozen APM installation for both targets, recursive upstream skill/reference comparisons, and rejection of package-version and source-revision mutations.

The planning plugin's generated lock migrated from APM 0.24 to 0.32.
Its large deployment ledger also reconciles older resolutions to the already-declared Superpowers and mattpocock pins and adds the previously missing Linear dependency.
Those manifest pins were not changed by this task.
The root consumer follows published remote plugin refs, so it cannot record the unpublished local manifest honestly; its relock is deferred until publication.
This does not block local Nix composition or the plugin's frozen-install check.

### Browser report and verdict

After integration and jj snapshotting of the new files, the parent ran:

```sh
nix build .#checks.aarch64-darwin.docs-e2e-wiring \
  .#checks.aarch64-darwin.package-vanixiets-docs-test-e2e \
  .#checks.aarch64-darwin.package-vanixiets-docs-test-e2e-negative-control \
  .#checks.aarch64-darwin.package-vanixiets-docs-test-unit \
  --no-link --builders '' --cores 4
```

All passed using the worker's cached outputs.
The initial parent evaluation correctly rejected untracked new files; snapshotting them made the flake complete.
Integrated `just lint` and `git diff --check` passed.

The worker's final native Darwin run exercised 20 browser scenarios across Chromium and WebKit, 25 report-protocol tests, and 20 existing Vitest tests.
The protocol tests include real pinned-runner launch failure, global setup failure, and zero-test selection.
The isolated negative journey produced exactly one intended assertion failure with its original trace and screenshot retained; validating its evidence succeeded while its verdict returned 1.
Its output is `/nix/store/9n8s3icgic8gjx24w7251czhli76vdlx-vanixiets-docs-e2e-negative-report-0.0.0-development`.

Linux exercised 30 scenarios across Chromium, Firefox, and WebKit.
The positive report ran on Pyrite and the negative report on Magnetite with Rosetta excluded.
Those runs preceded final formatting, README changes, and the additional unit-runner controls; final Linux revalidation remains outstanding.

An attempted full `just check-fast auto off x86_64-linux` warm-up reached 11 successful checks and no observed failures before the 200-second terminal limit.
It did not complete and is not evidence that the full Linux check surface passed.
The draft review checkpoint must disclose that limit.

## Independent review and corrections

The independent `omp` review covers published head `d9d44f5c5c8d94412021e1f46386a9dccb211b56` in draft PR #3265.
Its eight findings are recorded in tuicr session `gh:cameronraysmith/vanixiets/pr/3265`.
Review finding identifiers R1–R8 are distinct from the requirement identifiers in the table above.

The reviewer reports successful targeted Darwin and Linux checks at that head, mostly from cached outputs, and an actual reproduction of lost evidence for a missing-element action timeout.
This supplements the initial implementation history; it is not a full check sweep or a fresh browser-suite run.

The correction work has passed this integrated native Darwin selection, with remote builders disabled:

```sh
nix build .#checks.aarch64-darwin.docs-e2e-wiring \
  .#checks.aarch64-darwin.playwright-cli-consumers \
  .#checks.aarch64-darwin.docs-evidence-cache \
  .#checks.aarch64-darwin.effects-interpreter \
  .#checks.aarch64-darwin.effect-run-context \
  .#checks.aarch64-darwin.deployment-safety \
  --no-link --builders '' --cores 4
```

- R2: the evidence-epoch check rejects invalid epochs, requires identical epochs to reuse the report, and requires a new epoch to change the report and verdict without changing the site derivation.
  Native report outputs for epochs `0` and `1` were realized and their provenance read back.
  Ordinary nixbot restart and Nix `--rebuild` semantics were inspected in pinned source; neither is documented as a replacement mechanism for an existing negative report.
- R3: credentialed `buildFinished` definitions now require write/admin permission metadata.
  Real registry evaluation covers unsafe configurations; seven direct assertions against the pinned nixbot matcher cover permission behavior.
  Those assertions ran without pytest, which was unavailable in the research Python environment.
- R5: a successfully built verdict reading another producer is rejected despite matching enumeration identities.
  Removing the dependency predicate made the negative fixture fail, demonstrating that the fixture exercises that predicate.
- R6: consumer tests evaluate the real `ai` and `agents` aggregates without named-user enrollment lists.
  Injecting the package into the lighter aggregate made its exclusion check fail.
- R7: the required verdict no longer links to the report and enforces `allowedReferences = [ ]`.
  A measured empty verdict closure was 96 bytes with no references; the separately enumerated report intentionally retains its provenance closure.

The same six-check selection passed for x86_64-linux with `--max-jobs 0` and only the configured Magnetite/Pyrite builder entries supplied.
The effects interpreter and wrong-producer fixture emitted build logs; these results do not imply every selected derivation executed afresh.
`nix develop --accept-flake-config -c just lint` passed gitleaks and treefmt for this intermediate integrated state.

After R1/R4 integration, the following five checks passed on both platforms with the actual source-defined epoch wiring:

```text
package-vanixiets-docs-test-e2e
package-vanixiets-docs-test-e2e-negative-control
package-vanixiets-docs-test-e2e-action-negative-control
package-vanixiets-docs-test-e2e-runner-controls
package-vanixiets-docs-test-unit
```

Build logs show fresh positive browser execution: 20 passed on Darwin and 30 passed on Linux, with no flaky or skipped tests.
Both negative controls retained reports and attachments and independently checked verdict exit 1.
The removed-link control failed at the unchanged reader journey's click after its 5000ms action timeout, rather than reaching the whole-test deadline.
Separate native-browser controls cover accepted locator timeouts and rejected launch, hook, closed-page, and whole-test failures.
The unit check remains browser-free; independent policy tests reject omission of each required browser engine.
Linux again used only Magnetite/Pyrite builder entries and `--max-jobs 0`; Darwin used `--builders ''`.

Positive report outputs:

- Darwin: `/nix/store/m8w4hnmvjx0gn6ryd5hmjwvqkgrg4d2w-vanixiets-docs-e2e-report-0.0.0-development`.
- Linux: `/nix/store/vyl60h11xsq8jzw13xbn6cr55xyxja14-vanixiets-docs-e2e-report-0.0.0-development`.

No correction adds a live publisher, deployment, or current-revision receipt for whole-build reuse.

## Evidence publisher

`modules/apps/docs/publish-evidence.nix` exposes `nix run .#publish-evidence -- build-finished --out <dir>`, a `writeShellApplication` sidecar for a trusted default-branch `build_finished` event.
No effect registers it; storage destination, retention, and access remain undecided, so publication ends at the local `--out` directory.

Implemented behavior:

- The event supplies only data: `NIXBOT_EVENT_KIND` must be `build_finished`, and `.build.number`, `.build.rev`, `.build.status`, and `.build.url` are validated before any request.
- The build is fetched from nixbot's build API by number; its number and `commit_sha` must equal the event's.
  The aggregate build may have failed.
- The `checks.x86_64-linux.package-vanixiets-docs-test-e2e-report` attribute must be `succeeded` or `skipped_local`, carry a boolean `cached`, and have a realisable store output.
  Otherwise the program prints `evidence unavailable` and exits 1 without evaluating or building anything.
- Before validation, attachment paths must be relative and normalised, selected files must be regular files with no symlinked path component, and referenced `.png` attachments must start with the PNG signature.
  Report provenance must name `x86_64-linux` and `playwright.config.ts`.
- The program's own `validate-report.ts` copy then judges the report: a product-failing report is published with `verdict.passed: false` and exit 0; validator exit 2 is rejected.
- The bundle holds `run.json`, `playwright-report/completion.json`, and the referenced PNG screenshots, without HTML, traces, or other attachments.
  `receipt.json` records the build, attribute, output path, the API's `cached` value verbatim, report provenance, verdict, and per-file SHA-256 and size, with no timestamp.
- Publication is staged beside `--out` and renamed into place, so a rejected run leaves no receipt.
  A repeat for the same build, revision, attribute, and output path is a no-op when the bytes match; an existing receipt for another identity, or a non-empty directory without one, is refused.

`publish-evidence-rehearsal` runs the real program against a loopback nixbot API and a chroot store with synthetic report fixtures generated from `policy.ts`.
A control first runs the repository validator on every fixture, so the program, not the validator, makes each rejection except for the invalid and absolute-path fixtures.
Its rows cover passing, product-failing, failed-aggregate, and `skipped_local`/cached publication; byte-identical repeat and fresh republication; another identity's destination; a non-empty destination; missing `--out`; missing, failed, unfetchable, and unrealisable outputs; traversal, absolute, symlinked, and non-PNG attachments; revision, system, and config mismatches; a wrong event kind; malformed build number and revision; and invalid evidence.
Each rejection asserts its exit status, exact message, API requests, and the absence of a publication.

`checks.aarch64-darwin.publish-evidence-rehearsal` passed natively, and `checks.x86_64-linux.publish-evidence-rehearsal` passed on Magnetite.
`apps-build`, which runs shellcheck over the new program, passed on both platforms.

This rehearsal does not cover live nixbot delivery, an upload backend, HTML or trace hosting, or whole-build reuse.

## Increment 7: mobile hero overflow repair

A Playwright CLI smoke against the built site found that the homepage did not fit a phone.
The existing "is responsive on mobile" scenario passed because it only required a visible `h1`.

### Reproduction and diagnosis

The site and dependency packages were built natively on aarch64-darwin, staged as the e2e derivation stages them, and served with `astro preview` on loopback.
Measurements came from `playwright-cli` `--raw eval` on `/`:

| Context | Before: scrollWidth / clientWidth / innerWidth | Before: hero img left–right (wrapper) | After: scrollWidth / clientWidth / innerWidth | After: hero img left–right (wrapper) |
| --- | --- | --- | --- | --- |
| `--mobile` (Pixel, 360 device width) | 466 / 360 / 466 | 65–465, 400 wide (65–295) | 360 / 360 / 360 | 65–295, 230 wide (65–295) |
| `--device="iPhone 15"` (393) | 471 / 393 / 471 | 70–470 (70–323) | 393 / 393 / 393 | 70–323, 253 wide (70–323) |
| Desktop context resized to 375×667 | 467 / 375 / 375 | 67–467, 400 wide (67–308) | not separately measured; covered by the scenario | |
| Desktop 1280 | not measured | | 1280 / 1280 / 1280 | 799–1180, 381 wide (799–1180) |

The meta viewport was `width=device-width, initial-scale=1` and `visualViewport.scale` was 1, so this was not an emulation or zoom artifact.
Before the repair, the visible screenshot cut off the right of the logo and pushed the header search button to 418–450 px, outside the 360 px device.
The only unclipped elements extending past the device width were the hero image and the fixed header, which spans the widened layout viewport.
The code blocks seen in the first smoke run sit inside scroll containers and were not the cause.

Root cause: the homepage uses `hero.image.html` with `<img … width="400" height="400">` (`packages/docs/src/content/docs/index.mdx:8`).
Starlight 0.42.4 `Hero.astro` sizes the `.hero-html` wrapper (`width: min(70%, 20rem)`, or `min(100%, 25rem)` from 50rem) but does not constrain the raw markup inside it.
The image kept its 400 px attribute width, overflowed the wrapper, and mobile browsers widened the layout viewport to contain it.

### Strengthened expectation

`packages/docs/e2e/homepage.spec.ts` "is responsive on mobile" keeps its 375×667 viewport and visible-`h1` assertion.
It now also requires a visible hero image, a layout viewport no wider than 375 px, `documentElement.scrollWidth <= clientWidth`, and the hero image's left and right edges within `[0, clientWidth]`.
No assertion was removed or relaxed, and the required-case inventory is unchanged because no test identity was added.

With the unmodified site, the pinned runner (`@playwright/test` from `vanixiets-docs-deps`, browsers from `vanixiets-docs.tests.e2e-report.PLAYWRIGHT_BROWSERS_PATH`) ran `e2e/homepage.spec.ts` for Chromium and WebKit against the preview: 10 passed and 2 failed.
Both failures were the strengthened scenario:

```text
Error: document must not scroll horizontally
expect(received).toBeLessThanOrEqual(expected)
Expected: <= 375
Received:    467
```

### Correction and re-verification

`packages/docs/src/styles/custom.css:10-17` gives `.hero-html img` `max-width: 100%` and `height: auto`, so the raw hero markup fits the wrapper Starlight already sizes.
After rebuilding `vanixiets-docs` and restaging its `dist`, the same spec, projects, and runner passed 12 of 12 with no retries, and the CLI measurements above showed no horizontal overflow.

These local runs used a temporary configuration without `webServer`, since the committed configuration probes port 4321 and would otherwise start a dev server.
They are developer-platform evidence only.

### Required gate

On x86_64-linux (Magnetite), the report producer ran the strengthened scenario against the unmodified site and kept a valid report.
Its verdict exited 1 with 27 expected and 3 unexpected: the strengthened scenario failed on Chromium, Firefox, and WebKit with `Received: 467`, each attempt keeping a trace and a non-empty screenshot.
With the CSS correction, the same producer passed 30 of 30 with no flaky tests, and the verdict, both negative controls, and the unit and wiring checks passed.

On aarch64-darwin, the corrected suite passed 20 of 20 with no flaky tests, and the same checks passed.
The Darwin run against the unmodified site failed the same scenario on Chromium and WebKit, but the producer rejected the report: every failed WebKit attempt wrote a 0-byte `test-failed-1.png`.
That was a separate Darwin WebKit capture defect, fixed below.

## Harness defects found while re-verifying increment 7

Running the repair's RED and GREEN reports exposed three defects in the harness itself, all invisible to earlier single-report runs.

### Shared ports on Darwin

Darwin Nix builds are unsandboxed, so report derivations built at the same time share the host network.
Every report served `astro preview` on 4321, and one build's server broke another's tests (`page.goto: Could not connect to the server`); the producer rejected those reports as infrastructure failures.
The e2e-report build now picks a free loopback port and passes it to Playwright as `DOCS_PREVIEW_PORT`.
A second collision followed on the workerd inspector: `@cloudflare/vite-plugin` 1.62.3 probes upward from 9229, and concurrent builds raced for 9231 (`EADDRINUSE`).
Report builds now set `DOCS_DISABLE_WORKER_INSPECTOR=1`, which makes `astro.config.ts` pass `inspectorPort: false`; local development keeps 4321 and the inspector.
With both fixes, the producer and all three negative-control reports built concurrently on each platform with distinct ports and no `EADDRINUSE`.

### Empty WebKit screenshots on Darwin

Every WebKit failure screenshot taken as a Darwin Nix build user (`_nixbld*`) was a 0-byte file.
Those users have no LaunchServices database, so WebKit's image encoder resolves `image/png` to an empty type, `Page.snapshotRect` returns `data:,`, and Playwright 1.63 writes the empty buffer without raising.
Running as a normal user, even with the build's exact environment, produced real screenshots.
A shared fixture (`packages/docs/e2e/fixtures.ts`) now replaces a 0-byte WebKit failure screenshot with the latest screencast frame, or fails the attempt as infrastructure if no frame exists; the validator still rejects empty attachments.
`e2e-webkit-negative-control` fails the damaged-guide journey on WebKit and requires a decodable PNG; it passed on Darwin and Linux.

### Rehearsal teardown

One x86_64-linux `publish-evidence-rehearsal` build was reported failed after its output was already built and copied back; Nix's remote-build hook exited 1 without a message, and 22 later runs of the unmodified check passed.
The harness had two latent weaknesses, fixed while investigating: its teardown `kill` could fail the build under `set -e` if the stub server had already exited, and its readiness wait gave up after 10 s with no message.
The fixed check passed 8 runs on Linux and 3 on Darwin.

## Required negative cases

- Intended navigation outcome is broken: verdict fails for the specified assertion.
- Runner exits before producing a valid report: producer or verdict fails closed.
- Report is empty, malformed, unexpectedly skipped, or missing attachments: no passing verification claim.
- Report is valid JSON but omits a required project, journey, or discovered test: reject as incomplete.
- An assertion passes only on retry: retain and report its flaky outcome rather than label it first-attempt success.
- Required verdict export is removed or consumes a different producer: the structural gate check rejects the fixture.
- Aggregate build fails but report producer succeeds: evidence lookup remains possible.
- Report output cannot be realized: publisher reports unavailable evidence without executing PR code.
- Artifact metadata contains traversal/absolute paths, symlinks, executable upload instructions, or a wrong build identity: publisher rejects it before publication.
- Publication is retried: no duplicate or stale success receipt.
- Nix output reuse in a new build versus whole-build reuse: preserve original execution identity and do not claim a new event receipt where none was emitted.
- Correction changes assertions rather than satisfying them: review rejects the purported repair.

## Recording results

For each completed increment, record the command, platform, relevant input or derivation identity, observed outcome, and remaining limitations here.
Keep large reports, recordings, credentials, and mutable remote URLs out of this source tree.
Link durable evidence only after its storage and access policy is approved.
