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

Publication is a separate runtime graph with two entry points, both evaluated from `main` ([D10](decisions.md#d10-publish-main-from-onpush-and-pull-requests-from-build_finished)):

```text
build_finished effect (pull request         onPush effect on main
and other newly finished builds)              (publish-evidence main --rev)
  -> query completed build by number            -> query builds by commit,
                                                   take the highest number
                    \                          /
                     -> select successful named report attribute
                     -> validate and realize recorded store output
                     -> validate publishable evidence
                     -> stage bundle and content-keyed receipt
                     -> pull request only: probe ttl-90d for main's receipt
                          (read-only credential); if present, upload
                          nothing, supersede an earlier comment, stop
                     -> mint temporary credential for the run's own tier
                     -> upload files, receipt last and create-only
                     -> pull request only: upsert one PR comment through
                          nixbot and record the PR marker
```

Ordinary onPush effects run after successful builds and are unsuitable as the only failed-test diagnostic path.
An effect ordered after a failing prerequisite is skipped, so the publisher must not depend on the failed verdict.
A fast-forward landing reuses the batch build and sends no build_finished, so `main` needs the onPush entry point.

## Existing implementation anchors

- `pkgs/by-name/vanixiets-docs/package.nix`: current browser runner and application build.
- `packages/docs/playwright.config.ts`: browser projects, fixtures, reporters, and capture policy.
- `modules/effects/vanixiets/registry.nix`: declarative effect registration, rehearsal inputs, and trigger mapping.
- `modules/apps/docs/deploy.nix` and `deploy.sh`: writeShellApplication sidecar and recorded build-output lookup.
- `modules/apps/ci/github-check-run.nix`: reporting companion; GitHub API use does not imply Actions execution.
- `modules/checks/deploy-docs-rehearsal.nix`: loopback rehearsal of artifact lookup and publication.
- `modules/nixos/nixbot.nix`: best-effort cache-upload behavior.
- `modules/apps/docs/publish-evidence.nix` and `publish-evidence.sh`: the publisher's `build-finished` and `main` modes.
- `modules/effects/vanixiets/effects.nix`: the `browser-evidence` entry with `main` and `buildFinished` triggers.
- `modules/terranix/cloudflare.nix`: the adopted bucket and its lifecycle rules.
- `packages/evidence-worker/` (`@vanixiets/evidence-worker`): the serving Worker, deployed with wrangler.

The registry exposes the buildFinished trigger as build_finished; `browser-evidence` is its only consumer.
The docs publisher currently requires aggregate build success; the browser publisher does not.

## Cache and provenance

Relevant application sources, fixtures, test configuration, browsers, fonts, and runner versions determine report inputs.
Changing publication text or a PR number should not re-execute browser tests.
The producer records input identity; the publisher's receipt identifies the report by attribute and output path, and the pull request comment names the build it describes.
Reusing an output is not a newly executed test, and the receipt claims no execution: one report published once serves every build that carries it.

There are two different reuse paths.
A newly completed nixbot build may realize the report from the Nix cache and still deliver build_finished.
Whole-build reuse instead suppresses build_finished in pinned nixbot's `nixbot/nixbot/after_build.py:74-79`.
The build_finished entry point therefore covers newly completed builds only.
For `main`, the onPush entry point looks the landed commit up in nixbot's builds API and publishes the reused build's report.
The receipt is keyed by the report's attribute and output path, so it claims no execution, fresh or reused, for any build or push.
Whole-build reuse on branches other than `main` still has no publication path.
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

## Storage

Published evidence lives in the adopted R2 bucket `sciexp` under `projects/vanixiets/browser-evidence/<tier>/v1/<obs>/` ([D9](decisions.md#d9-publish-to-the-adopted-sciexp-bucket-under-a-confined-prefix)).
`<obs>` derives from the report's attribute and output path, so every build carrying the same report writes the same keys and a tier receives each report at most once.
The schema-version-3 receipt is uploaded last with `If-None-Match: *`; an existing identical receipt is reported unchanged, and a different one is a conflict.
The tier selects retention: 90 days for `main` and other builds without a pull request, 30 days for a pull request whose report `main` has not published, and a reserved 365-day tier for later curation.
A pull request whose report `main` already published uploads nothing and posts no comment ([D10](decisions.md#d10-publish-main-from-onpush-and-pull-requests-from-build_finished)).
Terraform owns every lifecycle rule on the bucket, because R2 lifecycle configuration is bucket-wide.
Evidence is read through `https://evidence.vanixiets.net/vanixiets/browser-evidence/<tier>/v1/<obs>/`, never through the S3 endpoint; the URL path is the key suffix after `projects/`.

## Trust boundaries

Pure checks use synthetic, credential-free content.
The publisher receives credentials only at runtime and never evaluates or executes PR code.
It validates artifact paths, report shape, and output identity.
HTML reports are active untrusted content and need an appropriate isolated serving origin and content policy.
Links, captions, archive contents, symlinks, and manifest paths require validation before publication.
The publisher selects only validated metadata and raster screenshots; HTML serving and archive extraction are outside that boundary.
Adversarial acceptance cases are defined in the [publisher contract](requirements.md#publisher-acceptance-boundary).

The effect receives an R2 token scoped to Object Read & Write on `sciexp`, the account id, and nixbot's per-run API URL and token.
It never uploads with the R2 token: it signs 15-minute temporary credentials, a read-write one confined to the run's own tier prefix and, for a pull request, a read-only one confined to `ttl-90d/`, then unsets the parent secret.
A pull request run therefore never writes into `main`'s `ttl-90d/` tier, and no run reaches the rest of `sciexp`.
The pull request comment goes through nixbot's comment API, so the effect holds no GitHub token.

Readers reach evidence only through the serving Worker on `evidence.vanixiets.net`, a registrable domain dedicated to untrusted CI content that hosts no authentication, sessions, or cookies.
It answers GET and HEAD for `.png` and `.json` keys under allowlisted (project, kind) prefixes, takes content type from the extension rather than object metadata, and sends `nosniff`, a sandboxing `default-src 'none'` content security policy, `Content-Disposition: inline`, and `Referrer-Policy: no-referrer`.
It does not list objects, so a URL is needed to read evidence; anyone holding one can read it.

## Reusable application seam

A consumer supplies a build artifact, start/readiness contract, isolated fixtures, scenarios, output contract, and cleanup.
The first implementation remains specific enough to be understandable.
Extract a general interface only after a second consumer tests that boundary.
For future streaming applications, readiness and waits must target semantic conditions rather than network idleness.
