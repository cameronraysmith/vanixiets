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
├── deploy-docs-preview   onEvent effect, docs preview + comment (informational)
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
nixbot instead builds each onPush effect's dependencies as a check, which includes two hermetic rehearsals of the effect programs:

| Check | What it runs |
|-------|--------------|
| `checks.<system>.release-rehearsal` | A full semantic-release with the production plugins against a local git fixture and a stub GitHub API, including the floating major and minor tags |
| `checks.<system>.deploy-docs-rehearsal` | `deploy-docs production` and `deploy-docs preview` against a stub wrangler |

On a push to `main` the same context reports the effect runs themselves.

| Attribute | Value |
|-----------|-------|
| Runner | nixbot on magnetite |
| Triggers | Pull requests and batches (dependency build); pushes to `main` (effect run) |
| Required | Yes |
| Local equivalent | `nix build .#checks.x86_64-linux.release-rehearsal .#checks.x86_64-linux.deploy-docs-rehearsal` |

## Effects

Effects live in `modules/effects/vanixiets/herculesCI/`.
The onPush effects start with a fail-closed guard that refuses to run unless nixbot's identity token says the event is a push to `refs/heads/main`; any other run is skipped with exit 0 before a secret is read.

### deploy-docs

Deploys the nix-built docs payload to production with `wrangler deploy`.

| Attribute | Value |
|-----------|-------|
| Kind | onPush |
| Triggers | Push to `main` only |
| Lock | `deploy-docs` |
| Superseded run | Exits 0 without deploying when `main` has moved past its commit |
| Local equivalent | `just docs-deploy-production` |

**Production URL:** `https://infra.cameronraysmith.net`

### release-packages

Runs semantic-release for each package discovered by `nix run .#list-packages-json`.

| Attribute | Value |
|-----------|-------|
| Kind | onPush |
| Triggers | Push to `main` only |
| Lock | `release-packages` |
| Superseded run | Exits 0 without releasing when `main` has moved past its commit |
| Local equivalent | `just release-package <package> true` (semantic-release `--dry-run`; needs `GITHUB_TOKEN`) |

### deploy-docs-preview

`herculesCI.onEvent.pull_request.deploy-docs-preview` uploads a docs preview version for a pull request.
Its code is evaluated from `main`; it fetches the pull request's already-built docs store path from nixbot's API instead of evaluating pull-request code.

| Attribute | Value |
|-----------|-------|
| Kind | onEvent (`pull_request`) |
| Triggers | Pull requests whose author or pusher has write permission |
| Lock | `deploy-docs-preview-<pr-number>` |
| Required | No; never blocks a merge |
| Output | Preview URL posted as a pull request comment |
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

# Rehearse the effect programs against stubs
nix build .#checks.x86_64-linux.release-rehearsal
nix build .#checks.x86_64-linux.deploy-docs-rehearsal

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
Build `release-rehearsal` or `deploy-docs-rehearsal` with `-L` to see the program output against the stubs.

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
