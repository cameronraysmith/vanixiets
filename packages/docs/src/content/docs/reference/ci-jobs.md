---
title: CI Jobs
description: Reference for nixbot checks, effects, and the remaining GitHub Actions jobs, with their local equivalents
sidebar:
  order: 5
---

This reference lists what CI runs for vanixiets and how to run the equivalent locally.
[nixbot](https://github.com/Mic92/nixbot) on magnetite builds every pull request, merge-queue batch, and push to `main`, and runs the deploy effects.
A few GitHub Actions workflows remain for checks nixbot does not cover.
See [CI/CD Setup](/about/contributing/ci-cd-setup/) for the gating and secrets model.

## Overview

```
pull request / gitea-mq batch
├── nixbot/nix-eval       evaluate checks.x86_64-linux          (required)
├── nixbot/nix-build      build checks.x86_64-linux             (required)
├── nixbot/effects        build each effect's dependencies,     (required)
│                         including the rehearsal checks
├── docs-preview          check run from the docs effect's       (informational)
│                         pull request trigger; details link
│                         is the Cloudflare Preview URL
├── release-plan          check run from the release-packages    (informational)
│                         effect's pull request trigger; the
│                         per-package release forecast
├── browser-evidence      build_finished effect; uploads the     (no status)
│                         browser report's screenshots and
│                         comments on the pull request
└── PR Check (GitHub Actions)
    ├── check-fast-forward
    └── playwright-drift-check

push to main
├── nixbot/nix-eval, nixbot/nix-build
└── nixbot/effects        run the onPush effects
    ├── docs
    ├── release-packages
    └── browser-evidence

pull request closed or merged
└── docs effect           delete the pull request's Cloudflare Preview
```

## nixbot contexts

### nixbot/nix-eval and nixbot/nix-build

Evaluate and build `checks.x86_64-linux`, the attribute set by `nixbot.toml`.

| Attribute | Value |
|-----------|-------|
| Runner | nixbot on magnetite |
| Triggers | Pull requests, merge-queue batches, pushes |
| Required | Yes |
| Local equivalent | `just check-fast auto off x86_64-linux` or `nix build .#checks.x86_64-linux.<name>` |

### nixbot/effects

On pull requests and merge-queue batches no onPush effect runs.
nixbot instead builds each effect's dependencies as a check, and every effect lists the rehearsals of its program among them:

| Check | What it runs | Listed by |
|-------|--------------|-----------|
| `checks.<system>.deploy-docs-rehearsal` | Every `deploy-docs` mode (`production`, `preview`, `pull-request`, `pull-request-closed`, `versions`, `deployments`) against a stub wrangler that also runs each invocation's identical argv through the real pinned wrangler (`deploy --dry-run`, the other commands against a loopback fake Cloudflare API), including a superseded production run, the untrusted `--payload` hardening, the same-repository-or-writer trust rule, each build status and failure path, the `docs-preview` check-run lifecycle, a pull request found closed or superseded before the upload (skipped, with no Cloudflare or nixbot API request) or closed during it (Preview withdrawn), a failed pull request state lookup, Preview teardown when deleted, absent, or failing, `--limit` truncation, and missing secrets | `docs` |
| `checks.<system>.release-rehearsal` | `release-packages --rev` with the production semantic-release plugins against a local git fixture and a stub GitHub API, including the floating major and minor tags, a superseded rev, and a diverged rev; `release-packages plan` on fixture pull requests through the installation-token path, covering a minor, a major, and no bump, a release-configuration edit that is ignored in favour of `main`'s, a closed or superseded pull request (skipped without cloning), a failed pull request state lookup, a merge conflict, a head mismatch, a missing forge token, and an unused release PAT, with no write to the fixture remote and no release created | `release-packages` |
| `checks.<system>.publish-evidence-rehearsal` | `publish-evidence build-finished` and `publish-evidence main` against a loopback nixbot API, a chroot store, a stub comment endpoint, and a stub S3 endpoint that verifies the temporary credential's JWT claims and SigV4 signature and refuses keys outside its prefix: report selection and validation, upload with the receipt last and create-only, tier selection, an identical retry, a conflicting receipt, a failed upload and its retry, a refused comment, the pull request comment, `main` mode's lookup of the newest build of exactly its commit, a commit with no build, a missing `NIXBOT_API_URL`, a missing or non-`main` `--rev`, missing R2 secrets, and the parent secret's absence from every request | `browser-evidence` |

`checks.<system>.effects-interpreter`, built by `nixbot/nix-build`, checks the script the effects interpreter generates for each trigger kind (`main`, `pullRequest`, `pullRequestClosed`): the main-only guard, secret export, that a trigger never receives another trigger's secrets, the missing-secret failure, the per-trigger forge token, and the program's exact argv, including `--rev`.

On a push to `main` the same context reports the effect runs themselves.

| Attribute | Value |
|-----------|-------|
| Runner | nixbot on magnetite |
| Triggers | Pull requests and batches (dependency build); pushes to `main` (effect run) |
| Required | Yes |
| Local equivalent | `nix build .#checks.x86_64-linux.deploy-docs-rehearsal .#checks.x86_64-linux.release-rehearsal .#checks.x86_64-linux.publish-evidence-rehearsal` |

## Effects

Effects are data entries of `vanixiets.effects` in `modules/effects/vanixiets/effects.nix`.
Each entry names a program, its rehearsals, and one or more triggers (`main`, `pullRequest`, `pullRequestClosed`, `buildFinished`), each with its own arguments, secrets, lock, and forge-token setting; one interpreter, `modules/effects/vanixiets/registry.nix`, generates a nixbot effect per trigger.
A `buildFinished` trigger becomes an onEvent `build_finished` effect, evaluated from `main` and delivered for builds matching its `when` conditions; one that reads a secret must require `write` or `admin` permission.
The generated script for a `main` trigger starts with a fail-closed guard that refuses to run unless nixbot's identity token says the event is a push to `refs/heads/main`; any other run is skipped with exit 0 before a secret is read.
It then exports the trigger's declared secrets, and only those, and execs the program, appending `--rev <commit>` for `main` triggers.

Programs that report a GitHub check run (`deploy-docs pull-request` for `docs-preview`, `release-packages plan` for `release-plan`) share the `github-check-run` program (`modules/apps/ci/github-check-run.{nix,sh}`): `create --repo <owner/name> --name <check> --head-sha <sha>` prints the new `in_progress` check run's id, and `complete --repo <owner/name> --id <id> --conclusion <success|neutral|failure> --title <title> --summary <summary> [--details-url <url>]` completes it, both authenticated with nixbot's forge token (`GITHUB_FORGE_TOKEN`).

nixbot does not guarantee the order in which it delivers pull request events, and a fast merge can deliver `pull_request_closed` before the `pull_request` event for the last green head.
Both pull request modes therefore check, after creating their check run and before acting, that the pull request is still open at the event's head commit with the shared `github-pull-request` program (`modules/apps/ci/github-pull-request.{nix,sh}`): `state --repo <owner/name> --number <n> --head-sha <sha>` prints `current` (open at that head), `closed` (closed or merged), or `superseded` (open at a different head), and exits 1 on an API or argument failure.
A mode whose pull request is not `current` completes its check run as `neutral` and exits 0 without acting; a failed lookup fails the run.

### docs

Runs the `deploy-docs` program on each of its three triggers: production deploys on `main`, and a Cloudflare Preview per pull request, deleted when the pull request closes.

| Attribute | Value |
|-----------|-------|
| Program | `deploy-docs` |
| Rehearsal | `deploy-docs-rehearsal` |
| Secrets | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` on each trigger |

| Trigger | nixbot effect | Program | Lock | Forge token |
|---------|---------------|---------|------|-------------|
| `main` | `onPush.default.outputs.effects.docs` | `deploy-docs production --rev <commit>` | `deploy-docs` | No |
| `pullRequest` | `onEvent.pull_request.docs` | `deploy-docs pull-request` | `docs-preview-{pr}` | Yes |
| `pullRequestClosed` | `onEvent.pull_request_closed.docs` | `deploy-docs pull-request-closed` | `docs-preview-{pr}` | No |

**`main`:** deploys the nix-built docs payload to production with `wrangler deploy`, and exits 0 without deploying when `main`'s head is no longer its commit.
Local equivalent: `just docs-deploy-production`.

**Production URL:** `https://infra.cameronraysmith.net`

**`pullRequest`:** evaluated from `main`, it first confirms the pull request is open at the event's head commit, and otherwise completes `neutral` ("Docs preview skipped") and logs `DEPLOY-DOCS-PREVIEW: skipped (<closed|superseded>)` without fetching or deploying anything.
It then fetches the pull request's already-built docs store path from nixbot's API instead of evaluating pull-request code, accepting the docs attribute when nixbot reports it `succeeded` or `skipped_local`, and deploys it with `wrangler preview --ignore-base-config` as the Cloudflare Preview `pr-<number>` of the `infra-docs` Worker.
It previews pull requests whose head branch is in this repository and forks whose actor or author has `write` or `admin` permission (a maintainer adding any label); other forks complete `neutral` without deploying.
After the upload it checks the pull request's state again: if the pull request closed in the meantime, it deletes `pr-<number>` as teardown would, logs `DEPLOY-DOCS-PREVIEW: withdrawn (closed during upload)`, and completes `neutral`, failing if the delete fails; a head superseded during the upload keeps the Preview, which the newer head's run updates.
It reports as the GitHub check run `docs-preview` on the head commit, which is not required and never blocks a merge: its details link is the Preview URL, a skipped or withdrawn run completes `neutral` with the reason in its summary, and a failure carries the error in its summary.
Local equivalent: `just docs-deploy-preview pr-<number>`.

**Preview URL:** `https://pr-<number>-infra-docs.sciexp.workers.dev`; a local `just docs-deploy-preview` with no argument names the Preview after the current branch.

**`pullRequestClosed`:** when the pull request is closed or merged, runs `wrangler preview delete --name pr-<number> --skip-confirmation` and logs `DEPLOY-DOCS-PREVIEW: deleted (pr-<number>)`; a pull request that never got a Preview logs `DEPLOY-DOCS-PREVIEW: absent (pr-<number>)` and exits 0.
The shared `docs-preview-{pr}` lock makes teardown wait for an upload still in flight; it does not order the two triggers, so a `pullRequest` run that follows teardown finds the pull request `closed` and skips.

Cloudflare Previews are public, with `X-Robots-Tag: noindex` on `workers.dev`; a Worker holds at most 100 (Free) or 500 (paid) Previews of at most 100 deployments each, and Cloudflare deletes the least recently deployed Preview or oldest deployment at the limit.
A deleted Preview's URL can keep serving for hours after `wrangler preview delete` succeeds ([cloudflare/developer-platform#73](https://github.com/cloudflare/developer-platform/issues/73)).

### release-packages

Runs the `release-packages` program: semantic-release for each package discovered by `list-packages-json` on `main`, and a per-package release forecast on each pull request.

| Attribute | Value |
|-----------|-------|
| Program | `release-packages` |
| Rehearsal | `release-rehearsal` |

| Trigger | nixbot effect | Program | Secrets | Lock | Forge token |
|---------|---------------|---------|---------|------|-------------|
| `main` | `onPush.default.outputs.effects.release-packages` | `release-packages --rev <commit>` | `GITHUB_TOKEN` (release PAT) | `release-packages` | No |
| `pullRequest` | `onEvent.pull_request.release-packages` | `release-packages plan` | None | `release-plan-{pr}` | Yes |

**`main`:** runs semantic-release with the production plugins for each package and publishes the releases.
It exits 0 without releasing when `main` has moved past its commit, and fails for a commit outside `main`'s history.
Local equivalent: `just release-package <package> true` (semantic-release `--dry-run`; needs `GITHUB_TOKEN`).

**`pullRequest`:** runs on every pull request once its head has built green, forks included once CI is approved for them, and reports the GitHub check run `release-plan` on the head commit, which is not required and never blocks a merge.
It first confirms the pull request is open at the event's head commit, and otherwise completes `neutral` ("Release plan skipped") and logs `RELEASE-PLAN: skipped (<closed|superseded>)` without cloning.
On success it is titled "Release plan" and its summary is a table with columns package, last, next, and bump; the nixbot log carries one `RELEASE-PLAN: <package> <last|none> -> <next|no release>` line per package.
It completes as `failure`, with the reason in its summary, on a failed pull request state lookup, a conflict with `main`, a fetched `refs/pull/<number>/head` that differs from the event's head commit, or a package whose semantic-release run fails.
The log also shows semantic-release's `Published release <version> on <channel> channel`, which it prints even under `--dry-run` (semantic-release 25.0.9 `index.js`, line 221); the forecast publishes nothing, and the `RELEASE-PLAN` lines and the check run are its authoritative output.

The forecast analyses the pull request's commits on a simulated merge into `main` while the working tree, and so semantic-release's configuration and plugins, are `main`'s files; a pull request cannot change what the forecast runs.
It authenticates only with nixbot's installation token (contents read, checks write), never receives or reads the release PAT, and never pushes: it runs semantic-release with `--dry-run` and redirects every git network operation to a local bare clone.
`release-rehearsal` proves this machinery on a fixture; the `release-plan` check run forecasts the actual pull request.
See [Semantic Release Preview](/about/contributing/semantic-release-preview/).

### browser-evidence

Runs the `publish-evidence` program, which publishes the docs browser report nixbot already built (`checks.x86_64-linux.package-vanixiets-docs-test-e2e-report`): `run.json`, `completion.json`, the referenced PNG screenshots, and a `receipt.json`.

| Attribute | Value |
|-----------|-------|
| Program | `publish-evidence` |
| Rehearsal | `publish-evidence-rehearsal` |
| Secrets | `R2_EVIDENCE_ACCESS_KEY_ID`, `R2_EVIDENCE_SECRET_ACCESS_KEY`, `CLOUDFLARE_ACCOUNT_ID` on each trigger |

| Trigger | nixbot effect | Program | Lock | Forge token |
|---------|---------------|---------|------|-------------|
| `main` | `onPush.default.outputs.effects.browser-evidence` | `publish-evidence main --upload --rev <commit>` | `browser-evidence` | No |
| `buildFinished` | `onEvent.build_finished.browser-evidence` | `publish-evidence build-finished --upload` | `browser-evidence` | No |

**`buildFinished`:** delivered for succeeded and failed builds whose actor or pull request author has `write` permission or above; a failed aggregate build still publishes its report.
It fetches the event's build from nixbot's API.
For a build without a pull request it uploads to the `ttl-90d` tier without a comment.
For a pull request it first checks, with a read-only credential, whether `main` has already published this exact report (its receipt exists under `ttl-90d`); if so the pull request is unaffected, and the run uploads nothing, posts no comment, and logs `PUBLISH-EVIDENCE: unaffected (report <obs> already published from main)`.
Otherwise it uploads to `ttl-30d` and posts or edits one comment through nixbot's `pr-comment` API with the verdict and counts, the build number and revision, links to the screenshots and receipt, the retention, and a note that no identical report has been published from `main` in the last 90 days.
If an earlier build of the same pull request commented and a later one is unaffected, the run replaces the comment with a superseded note and logs `PUBLISH-EVIDENCE: superseded #<number>`; it tracks this in a marker object under `ttl-30d/pr/`, because `pr-comment` can only upsert.
When two builds of one pull request finish out of order, the one that finishes last decides the comment.

**`main`:** a landing fast-forwards `main` to an already-built commit, and nixbot sends no `build_finished` for a reused build, so this trigger looks up the highest-numbered build of `<commit>` through nixbot's builds API and publishes its report to `ttl-90d`, without a comment.

Objects go to the R2 bucket `sciexp` under `projects/vanixiets/browser-evidence/<tier>/v1/<obs>/`, where `<obs>` is derived from the report's attribute and Nix output path only, so every build with the same report writes the same keys and each tier receives a report at most once.
An identical existing receipt (schema version 3) logs `PUBLISH-EVIDENCE: unchanged`, and a different one fails as a conflict.
Each run signs 15-minute temporary credentials with the R2 token, read-write on its own tier's prefix and, for a pull request, read-only on `ttl-90d/`, so a pull request run cannot write into `main`'s tier; it reads `NIXBOT_API_URL` and `NIXBOT_API_TOKEN` from nixbot rather than the secrets schema.
The run log prints `PUBLISH-EVIDENCE: published|unchanged (report <obs>, passed=<bool>)`, `PUBLISH-EVIDENCE: uploaded <url>` when the run wrote the receipt, `PUBLISH-EVIDENCE: unaffected (report <obs> already published from main)`, and, for a pull request, `PUBLISH-EVIDENCE: commented #<number>` or `PUBLISH-EVIDENCE: superseded #<number>`.

**Evidence URL:** `https://evidence.vanixiets.net/vanixiets/browser-evidence/<tier>/v1/<obs>/<file>` (the object key after `projects/`), served read-only by the Worker `sciexp-evidence` (`packages/evidence-worker/`, deployed with wrangler): GET and HEAD, `.png` and `.json` only, no listing.
Bucket lifecycle rules delete `ttl-30d` objects after 30 days and `ttl-90d` objects after 90 days.
nixbot runs event effects from the default branch, so a pull request that changes this effect or `publish-evidence` is first exercised after it lands.
nixbot posts no forge status for event effects, so a failed `buildFinished` run shows only in nixbot's effect log and never blocks a merge; a failed `main` run fails `nixbot/effects` on the `main` push.
Local equivalent: `nix run .#publish-evidence -- build-finished --out <dir>` with nixbot's event variables set, which stages the bundle without uploading.

## GitHub Actions workflows

### PR Check (`pr-check.yaml`)

Runs on pull request open, reopen, and synchronize.

| Job | Purpose | Local equivalent |
|-----|---------|------------------|
| `check-fast-forward` | Verifies the pull request can be fast-forward merged | `git merge-base --is-ancestor origin/main HEAD` |
| `playwright-drift-check` | Asserts the npm playwright pins match the `playwright-web-flake` input | `just bun-drift-check` |

### PR Fast-forward Merge (`pr-merge.yaml`)

A `/fast-forward` comment on a pull request fast-forwards `main` to the pull request head.

### CD (`cd.yaml`)

Manual dispatch only.
Runs `bootstrap-verification` (the Makefile bootstrap on a clean Ubuntu runner; locally `make bootstrap && make verify && make setup-user`) and the informational `test-cluster` integration workflow.
Its jobs use per-job content-addressed caching; see [ADR-0016](/development/architecture/adrs/0016-per-job-content-addressed-caching/).
To force re-execution, dispatch with `force_run: true`.

## Running CI locally

```bash
# Build the checks nixbot builds (x86_64-linux routes to magnetite from darwin)
just check-fast auto off x86_64-linux

# Checks for the current system
just check-fast

# Full nix flake check, including VM tests
just check

# Rehearse the effect programs and the interpreter's generated scripts against stubs
nix build .#checks.x86_64-linux.deploy-docs-rehearsal
nix build .#checks.x86_64-linux.release-rehearsal
nix build .#checks.x86_64-linux.effects-interpreter
nix build .#checks.x86_64-linux.publish-evidence-rehearsal

# Test the docs package
just test-package docs
just docs-test
just docs-linkcheck

# Preview a release (semantic-release --dry-run with the production plugins)
GITHUB_TOKEN="$(gh auth token)" just release-package docs true

# Deploy HEAD as the Cloudflare Preview named after the current branch
just docs-deploy-preview

# Inspect Cloudflare state (newest first, default limit 10)
just docs-deployments
just docs-versions
just docs-tail
```

## Troubleshooting

**nixbot/nix-build fails:** rebuild the named check locally with `nix build -L .#checks.x86_64-linux.<name>`.

**nixbot/effects fails on a pull request:** one of the effect dependencies failed to build, usually a rehearsal.
Build `deploy-docs-rehearsal`, `release-rehearsal`, or `publish-evidence-rehearsal` with `-L` to see the program output against the stubs.

**The browser-evidence run fails:** its log names the step; `evidence unavailable` means the build has no realisable report, `conflict` means another receipt already holds that key, and an upload or comment failure names the key or HTTP status.
A rerun is idempotent: it finds the same receipt and logs `unchanged`.

**The docs-preview check run fails:** its summary carries the error, for example a docs attribute that did not build or a failed Preview deploy.

**The release-plan check run fails:** its summary names the reason; for a conflict with `main`, rebase the pull request; for a failed package, the summary carries the tail of that package's semantic-release output.

**A closed pull request's Preview still serves:** Cloudflare can keep serving a deleted Preview's URL for hours ([cloudflare/developer-platform#73](https://github.com/cloudflare/developer-platform/issues/73)); the `docs` effect's `pull_request_closed` run log shows whether `deploy-docs` logged `DEPLOY-DOCS-PREVIEW: deleted`.

**An effect on `main` reports superseded:** a newer commit landed on `main` before the run started; the run for that commit does the work.

**GitHub Actions logs:**

```bash
just ci-logs pr-check.yaml
just ci-logs-failed pr-check.yaml
```

## See also

- [CI/CD Setup](/about/contributing/ci-cd-setup/) - Gating, effects, and secrets
- [Testing Guide](/about/contributing/testing/) - How to run tests and testing philosophy
- [Test Harness Reference](/development/traceability/test-harness/) - CI-local parity matrix
- [Justfile Recipes](/reference/justfile-recipes/) - Local recipe reference
- [CI Philosophy](/development/traceability/ci-philosophy/) - Design principles
- [Troubleshooting CI Cache](/development/operations/troubleshooting-ci-cache/) - Cache issues
