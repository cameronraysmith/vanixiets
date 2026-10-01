# Architecture

## Ownership

The test suite owns expected behavior.
Playwright CLI helps explore and reproduce behavior; it is not the merge gate.
APM owns the upstream skill dependency and its composition.
Nix owns tool sources, browser/runtime dependencies, and hermetic build inputs.
Home Manager installs the shared capability for selected humans and dedicated workers.
nixbot schedules checks and effects.
A trusted effect sidecar publishes already-built evidence.

No additional browser daemon, Browserbase dependency, or agent-browser integration is required for the first slice.
OMP's native browser is an alternative exploration interface, not a replacement for project-owned assertions.

## Build and runtime boundaries

The proposed pure dependency graph is:

```text
filtered application and test inputs
  -> built application and isolated browser runner
  -> named completed-report derivation
     -> required verdict check
     -> recorded output available through nixbot build API
```

A successful report derivation means that a complete execution record exists, not that its assertions passed.
The required verdict check must remain independently enumerated in the CI gate.
The [report policy](requirements.md#initial-report-and-verdict-policy) names the exports and requires an executable wiring check, including a missing-verdict negative fixture.
Infrastructure failures that prevent a valid report remain producer failures.

Publication is a separate runtime graph:

```text
trusted default-branch build_finished effect
  -> query completed build by number
  -> select successful named report attribute
  -> validate and realize recorded store output
  -> validate publishable evidence
  -> publish and report a receipt
```

Ordinary onPush effects run after successful builds and are unsuitable as the only failed-test diagnostic path.
An effect ordered after a failing prerequisite is skipped, so the publisher must not depend on the failed verdict.

## Existing implementation anchors

- `pkgs/by-name/vanixiets-docs/package.nix`: current browser runner and application build.
- `packages/docs/playwright.config.ts`: browser projects, fixtures, reporters, and capture policy.
- `modules/effects/vanixiets/registry.nix`: declarative effect registration, rehearsal inputs, and trigger mapping.
- `modules/apps/docs/deploy.nix` and `deploy.sh`: writeShellApplication sidecar and recorded build-output lookup.
- `modules/apps/ci/github-check-run.nix`: reporting companion; GitHub API use does not imply Actions execution.
- `modules/checks/deploy-docs-rehearsal.nix`: loopback rehearsal of artifact lookup and publication.
- `modules/nixos/nixbot.nix`: best-effort cache-upload behavior.

The registry now exposes the optional buildFinished trigger as build_finished; no live consumer is registered.
The docs publisher currently requires aggregate build success.
The browser publisher remains integration work, not a capability supplied by that trigger alone.

## Cache and provenance

Relevant application sources, fixtures, test configuration, browsers, fonts, and runner versions determine report inputs.
Changing publication text or a PR number should not re-execute browser tests.
The producer records input identity; a runtime receipt relates that identity to the current CI revision and build.
Reusing an output is reported as cached verification, not a newly executed test.

There are two different reuse paths.
A newly completed nixbot build may realize the report from the Nix cache and still deliver build_finished.
Whole-build reuse instead suppresses build_finished in pinned nixbot's `nixbot/nixbot/after_build.py:74-79`.
The proposed event publisher therefore covers newly completed builds only.
It does not yet establish a new receipt for every revision that reuses an entire build.
Until a separate trusted association path is implemented and rehearsed, expose the original build/report identity and leave current-revision receipt coverage unverified.
Do not disable caching merely to manufacture publication events.
Attribute-level availability accepts the API's succeeded and skipped_local states, and execution-versus-cache claims must inspect its cached field rather than infer freshness from succeeded.

Browser traces can contain timestamps and other nondeterministic diagnostic bytes.
Nix input pinning supports reuse of a realization; it does not establish bit-identical traces across repeated executions or universal absence of flakes.
Negative results are reusable observations of those inputs.
A source-controlled report-only evidence epoch requests a fresh required observation without changing the application or browser build.
Ordinary CI restarts may reuse the old report; `--rebuild` checks reproducibility rather than replacing it.
The operational procedure is in `packages/docs/tests/report/README.md`.

A binary cache is not a browsable report archive or an indefinite retention guarantee.
Artifact realization failure must remain visible.

## Trust boundaries

Pure checks use synthetic, credential-free content.
The publisher receives credentials only at runtime and never evaluates or executes PR code.
It validates artifact paths, report shape, and output identity.
HTML reports are active untrusted content and need an appropriate isolated serving origin and content policy.
Links, captions, archive contents, symlinks, and manifest paths require validation before publication.
The initial publisher rehearsal selects only validated metadata and raster screenshots; HTML serving and archive extraction are outside that boundary.
Adversarial acceptance cases are defined in the [publisher contract](requirements.md#publisher-acceptance-boundary).

A storage destination and retention/access policy are unresolved.
Until those are approved, implement and rehearse publication contracts without enabling a live effect.

## Reusable application seam

A consumer supplies a build artifact, start/readiness contract, isolated fixtures, scenarios, output contract, and cleanup.
The first implementation remains specific enough to be understandable.
Extract a general interface only after a second consumer tests that boundary.
For future streaming applications, readiness and waits must target semantic conditions rather than network idleness.
