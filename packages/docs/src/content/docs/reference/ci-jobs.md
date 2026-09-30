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
├── docs-preview          check run from the onEvent effect,     (informational)
│                         details link is the preview URL
└── PR Check (GitHub Actions)
    ├── check-fast-forward
    └── playwright-drift-check

push to main
├── nixbot/nix-eval, nixbot/nix-build
└── nixbot/effects        run the onPush effects
    ├── deploy-docs
    └── release-packages
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
| `checks.<system>.deploy-docs-rehearsal` | `deploy-docs production` and `deploy-docs preview` through their flag interface against a stub wrangler, including a superseded production run and the untrusted `--payload` hardening | `deploy-docs`, `docs-preview` |
| `checks.<system>.release-rehearsal` | `release-packages --rev` with the production semantic-release plugins against a local git fixture and a stub GitHub API, including the floating major and minor tags, a superseded rev, and a diverged rev | `release-packages` |
| `checks.<system>.docs-preview-rehearsal` | `docs-preview` against a stub nixbot API, a stub GitHub check-runs API, and a stub `deploy-docs`, including `succeeded` and `skipped_local` docs attributes and each failure path | `docs-preview` |

`checks.<system>.effects-interpreter`, built by `nixbot/nix-build`, checks the script the effects interpreter generates around each program: the main-only guard, secret export, the missing-secret failure, the forge token, and the program's exact argv, including `--rev`.

On a push to `main` the same context reports the effect runs themselves.

| Attribute | Value |
|-----------|-------|
| Runner | nixbot on magnetite |
| Triggers | Pull requests and batches (dependency build); pushes to `main` (effect run) |
| Required | Yes |
| Local equivalent | `nix build .#checks.x86_64-linux.deploy-docs-rehearsal .#checks.x86_64-linux.release-rehearsal .#checks.x86_64-linux.docs-preview-rehearsal` |

## Effects

Effects are data entries of `vanixiets.effects` in `modules/effects/vanixiets/effects.nix`.
Each entry names a program, its arguments, secrets, rehearsals, and lock; one interpreter, `modules/effects/vanixiets/registry.nix`, generates the nixbot effects from them.
The generated script for an onPush effect starts with a fail-closed guard that refuses to run unless nixbot's identity token says the event is a push to `refs/heads/main`; any other run is skipped with exit 0 before a secret is read.
It then exports the declared secrets and execs the program, appending `--rev <commit>` for onPush effects.

### deploy-docs

Runs `deploy-docs production --rev <commit>`, which deploys the nix-built docs payload to production with `wrangler deploy`.

| Attribute | Value |
|-----------|-------|
| Kind | onPush |
| Triggers | Push to `main` only |
| Program | `deploy-docs production --rev <commit>` |
| Rehearsal | `deploy-docs-rehearsal` |
| Lock | `deploy-docs` |
| Superseded run | Exits 0 without deploying when `main`'s head is no longer its commit |
| Local equivalent | `just docs-deploy-production` |

**Production URL:** `https://infra.cameronraysmith.net`

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

### docs-preview

`herculesCI.onEvent.pull_request.docs-preview` runs the `docs-preview` program, which uploads a docs preview version for a pull request.
Its code is evaluated from `main`; it fetches the pull request's already-built docs store path from nixbot's API instead of evaluating pull-request code, accepting the docs attribute when nixbot reports it `succeeded` or `skipped_local`, and runs `deploy-docs preview --rev <head> --alias pr-<number> --payload <store path>`.

| Attribute | Value |
|-----------|-------|
| Kind | onEvent (`pull_request`) |
| Triggers | Pull requests whose author or pusher has write permission |
| Program | `docs-preview` |
| Rehearsals | `docs-preview-rehearsal`, `deploy-docs-rehearsal` |
| Lock | `deploy-docs-preview-{pr}` |
| Required | No; never blocks a merge |
| Output | GitHub check run `docs-preview` on the head commit; its details link is the preview URL, and a failure carries the error in its summary |
| Local equivalent | `just docs-deploy-preview pr-<number>` |

**Preview URL:** `https://b-pr-<number>-infra-docs.sciexp.workers.dev`; a local `just docs-deploy-preview` with no argument aliases the current branch as `b-<branch>`.

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
nix build .#checks.x86_64-linux.docs-preview-rehearsal
nix build .#checks.x86_64-linux.effects-interpreter

# Test the docs package
just test-package docs
just docs-test
just docs-linkcheck

# Preview a release (semantic-release --dry-run with the production plugins)
GITHUB_TOKEN="$(gh auth token)" just release-package docs true

# Upload a docs preview version aliased at b-<branch>
just docs-deploy-preview
```

## Troubleshooting

**nixbot/nix-build fails:** rebuild the named check locally with `nix build -L .#checks.x86_64-linux.<name>`.

**nixbot/effects fails on a pull request:** one of the effect dependencies failed to build, usually a rehearsal.
Build `deploy-docs-rehearsal`, `release-rehearsal`, or `docs-preview-rehearsal` with `-L` to see the program output against the stubs.

**The docs-preview check run fails:** its summary carries the error, for example a docs attribute that did not build or a failed upload.

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
