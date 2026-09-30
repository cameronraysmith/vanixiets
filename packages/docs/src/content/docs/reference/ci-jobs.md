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
└── PR Check (GitHub Actions)
    ├── check-fast-forward
    └── playwright-drift-check

push to main
├── nixbot/nix-eval, nixbot/nix-build
└── nixbot/effects        run the onPush effects
    ├── docs
    └── release-packages

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

On pull requests and merge-queue batches no effect runs.
nixbot instead builds each effect's dependencies as a check, and every effect lists the rehearsals of its program among them:

| Check | What it runs | Listed by |
|-------|--------------|-----------|
| `checks.<system>.deploy-docs-rehearsal` | Every `deploy-docs` mode (`production`, `preview`, `pull-request`, `pull-request-closed`, `versions`, `deployments`) against a stub wrangler that also runs each invocation's identical argv through the real pinned wrangler (`deploy --dry-run`, the other commands against a loopback fake Cloudflare API), including a superseded production run, the untrusted `--payload` hardening, the same-repository-or-writer trust rule, each build status and failure path, the `docs-preview` check-run lifecycle, Preview teardown when deleted, absent, or failing, `--limit` truncation, and missing secrets | `docs` |
| `checks.<system>.release-rehearsal` | `release-packages --rev` with the production semantic-release plugins against a local git fixture and a stub GitHub API, including the floating major and minor tags, a superseded rev, and a diverged rev | `release-packages` |

`checks.<system>.effects-interpreter`, built by `nixbot/nix-build`, checks the script the effects interpreter generates for each trigger kind (`main`, `pullRequest`, `pullRequestClosed`): the main-only guard, secret export, the missing-secret failure, the per-trigger forge token, and the program's exact argv, including `--rev`.

On a push to `main` the same context reports the effect runs themselves.

| Attribute | Value |
|-----------|-------|
| Runner | nixbot on magnetite |
| Triggers | Pull requests and batches (dependency build); pushes to `main` (effect run) |
| Required | Yes |
| Local equivalent | `nix build .#checks.x86_64-linux.deploy-docs-rehearsal .#checks.x86_64-linux.release-rehearsal` |

## Effects

Effects are data entries of `vanixiets.effects` in `modules/effects/vanixiets/effects.nix`.
Each entry names a program, its secrets, its rehearsals, and one or more triggers (`main`, `pullRequest`, `pullRequestClosed`), each with its own arguments, lock, and forge-token setting; one interpreter, `modules/effects/vanixiets/registry.nix`, generates a nixbot effect per trigger.
The generated script for a `main` trigger starts with a fail-closed guard that refuses to run unless nixbot's identity token says the event is a push to `refs/heads/main`; any other run is skipped with exit 0 before a secret is read.
It then exports the declared secrets and execs the program, appending `--rev <commit>` for `main` triggers.

### docs

Runs the `deploy-docs` program on each of its three triggers: production deploys on `main`, and a Cloudflare Preview per pull request, deleted when the pull request closes.

| Attribute | Value |
|-----------|-------|
| Program | `deploy-docs` |
| Rehearsal | `deploy-docs-rehearsal` |
| Secrets | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` |

| Trigger | nixbot effect | Program | Lock | Forge token |
|---------|---------------|---------|------|-------------|
| `main` | `onPush.default.outputs.effects.docs` | `deploy-docs production --rev <commit>` | `deploy-docs` | No |
| `pullRequest` | `onEvent.pull_request.docs` | `deploy-docs pull-request` | `docs-preview-{pr}` | Yes |
| `pullRequestClosed` | `onEvent.pull_request_closed.docs` | `deploy-docs pull-request-closed` | `docs-preview-{pr}` | No |

**`main`:** deploys the nix-built docs payload to production with `wrangler deploy`, and exits 0 without deploying when `main`'s head is no longer its commit.
Local equivalent: `just docs-deploy-production`.

**Production URL:** `https://infra.cameronraysmith.net`

**`pullRequest`:** evaluated from `main`, it fetches the pull request's already-built docs store path from nixbot's API instead of evaluating pull-request code, accepting the docs attribute when nixbot reports it `succeeded` or `skipped_local`, and deploys it with `wrangler preview --ignore-base-config` as the Cloudflare Preview `pr-<number>` of the `infra-docs` Worker.
It previews pull requests whose head branch is in this repository and forks whose actor or author has `write` or `admin` permission (a maintainer adding any label); other forks complete `neutral` without deploying.
It reports as the GitHub check run `docs-preview` on the head commit, which is not required and never blocks a merge: its details link is the Preview URL, a skipped fork completes `neutral` with the reason and remedy in its summary, and a failure carries the error in its summary.
Local equivalent: `just docs-deploy-preview pr-<number>`.

**Preview URL:** `https://pr-<number>-infra-docs.sciexp.workers.dev`; a local `just docs-deploy-preview` with no argument names the Preview after the current branch.

**`pullRequestClosed`:** when the pull request is closed or merged, runs `wrangler preview delete --name pr-<number> --skip-confirmation` and logs `DEPLOY-DOCS-PREVIEW: deleted (pr-<number>)`; a pull request that never got a Preview logs `DEPLOY-DOCS-PREVIEW: absent (pr-<number>)` and exits 0.
The shared `docs-preview-{pr}` lock makes teardown wait for an upload still in flight.

Cloudflare Previews are public, with `X-Robots-Tag: noindex` on `workers.dev`; a Worker holds at most 100 (Free) or 500 (paid) Previews of at most 100 deployments each, and Cloudflare deletes the least recently deployed Preview or oldest deployment at the limit.
A deleted Preview's URL can keep serving for hours after `wrangler preview delete` succeeds ([cloudflare/developer-platform#73](https://github.com/cloudflare/developer-platform/issues/73)).

### release-packages

Runs `release-packages --rev <commit>`, which runs semantic-release for each package discovered by `list-packages-json`.

| Attribute | Value |
|-----------|-------|
| Kind | onPush |
| Triggers | Push to `main` only |
| Program | `release-packages --rev <commit>` |
| Rehearsal | `release-rehearsal` |
| Lock | `release-packages` |
| Superseded run | Exits 0 without releasing when `main` has moved past its commit; a commit outside `main`'s history fails |
| Local equivalent | `just release-package <package> true` (semantic-release `--dry-run`; needs `GITHUB_TOKEN`) |

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
Build `deploy-docs-rehearsal` or `release-rehearsal` with `-L` to see the program output against the stubs.

**The docs-preview check run fails:** its summary carries the error, for example a docs attribute that did not build or a failed Preview deploy.

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
