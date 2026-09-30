---
title: Test Harness Reference
description: CI-local parity matrix and test infrastructure reference
---

This reference documents the relationship between CI and local test commands, enabling developers to reproduce CI behavior locally.
CI is [nixbot](https://github.com/Mic92/nixbot) on magnetite plus a few GitHub Actions workflows; see [CI Jobs](/reference/ci-jobs/) for the full job reference.

## CI-local execution parity matrix

All local commands run from the repository root.

| CI context or job | Purpose | Local equivalent | Runs on |
|-------------------|---------|------------------|---------|
| nixbot/nix-eval | Evaluate `checks.x86_64-linux` | `nix eval .#checks.x86_64-linux --apply builtins.attrNames` | PR, batch, push |
| nixbot/nix-build | Build `checks.x86_64-linux` | `just check-fast auto off x86_64-linux` | PR, batch, push |
| nixbot/effects (pre-merge) | Build each effect's dependencies, including the rehearsals | `nix build .#checks.x86_64-linux.deploy-docs-rehearsal .#checks.x86_64-linux.release-rehearsal` | PR, batch |
| `docs` effect, `main` trigger | Production docs deploy (`deploy-docs production --rev <commit>`) | `just docs-deploy-production` | Push to `main` |
| `release-packages` effect, `main` trigger | Semantic-release per package (`release-packages --rev <commit>`) | `just release-package <pkg> true` (dry run; needs `GITHUB_TOKEN`) | Push to `main` |
| `release-packages` effect, `pullRequest` trigger | Per-package release forecast for a pull request (`release-packages plan`): the pull request's commits on a simulated merge, `main`'s files, configuration, and plugins, nixbot's installation token only, no push; reported as the `release-plan` check run and `RELEASE-PLAN:` log lines | None; `just release-package <pkg> true` on a `main` checkout previews without the pull request's commits | PR after a green build, forks included (informational) |
| `docs` effect, `pullRequest` trigger | Cloudflare Preview `pr-<number>` for a pull request (`deploy-docs pull-request`), reported as the `docs-preview` check run whose details link is the Preview URL | `just docs-deploy-preview pr-<number>` | PR (informational) |
| `docs` effect, `pullRequestClosed` trigger | Delete the pull request's Preview (`deploy-docs pull-request-closed`) | None | PR closed or merged |
| PR Check: `check-fast-forward` | Fast-forward merge is possible | `git merge-base --is-ancestor origin/main HEAD` | PR |
| PR Check: `playwright-drift-check` | Playwright pins match the flake input | `just bun-drift-check` | PR |
| CD: `bootstrap-verification` | Makefile bootstrap on clean Ubuntu | `make bootstrap && make verify && make setup-user` | Manual dispatch |

`checks.x86_64-linux` covers the overlay packages, the docs package tests (`package-vanixiets-docs-test-*`), dev shells, the `nixos-*` and `home-manager-*` configurations, and the structure, secrets, and treefmt checks.
From darwin, `just check-fast auto off x86_64-linux` routes the build to magnetite.

## Rehearsals

An effect contains no behaviour of its own: it is a data entry in `vanixiets.effects` that names a program and its triggers, and the effects interpreter generates the glue that runs it.
The effects run only on pushes to `main` or, for the effects' pull request triggers, on a pull request event evaluated from `main`, and the `main` triggers hold deploy secrets, so pull requests validate them through hermetic checks that run the real programs and the generated glue against stubs:

| Check | Program under test | Stubs |
|-------|--------------------|-------|
| `deploy-docs-rehearsal` | Every `deploy-docs` mode: `production` including a superseded run; `preview` including the untrusted `--payload` hardening; `pull-request` with the same-repository-or-writer trust rule, the build lookup accepting `succeeded` and `skipped_local`, each failure path, and the `docs-preview` check-run lifecycle; `pull-request-closed` for a deleted, absent, and failing Preview; `versions` and `deployments` `--limit` truncation; missing secrets | Stub wrangler that also runs each argv through the real pinned wrangler (`deploy --dry-run`, other commands against a loopback fake Cloudflare API), stub nixbot API, stub GitHub check-runs API |
| `release-rehearsal` | `release-packages --rev`: a full semantic-release with the production plugins, including the floating major and minor tags, a superseded rev, and a diverged rev. `release-packages plan` on fixture pull requests: minor, major (`feat!:`), and no-release forecasts; a release-configuration edit that is ignored in favour of `main`'s; merge conflict, head mismatch, and missing forge token failures; an unused release PAT; zero writes to the fixture remote and no release created | Local git fixture with `refs/pull/<number>/head` refs, stub GitHub API with check runs and the installation-token path |
| `effects-interpreter` | The script the interpreter generates for each trigger kind (`main`, `pullRequest`, `pullRequestClosed`): main-only guard, per-trigger secret export with no trigger receiving another trigger's secrets, missing-secret failure, per-trigger forge token, exact argv including `--rev` | Stub program, stub id-token endpoint |

The effects list their rehearsals among their inputs, so the required `nixbot/effects` context fails when either fails; `effects-interpreter` is built by `nixbot/nix-build`.
`release-rehearsal` proves the release and forecast machinery on a fixture; the `release-plan` check run is the forecast for the actual pull request.

## Manual-only recipes

The following recipes are not exercised by CI:

| Recipe | Rationale |
|--------|-----------|
| `activate*` | Requires physical machine access |
| `darwin-*` | Requires darwin hardware; nixbot builds `checks.x86_64-linux` only |
| `nixos-bootstrap` | Destructive disk operations |
| `cache-darwin-system` | Requires darwin hardware |
| `scan-secrets` | Local gitleaks scan; no CI job runs it |
| `sops-*` | Requires Bitwarden access |
| `docs-deploy-*`, `docs-deployments`, `docs-versions`, `docs-tail` | Run `deploy-docs` locally with `secrets/shared.yaml` credentials; CI deploys through the `docs` effect |
| `release-package` | Local dry run; CI releases through the `release-packages` effect |

## Reproducing failures

### nixbot/nix-build

```bash
# Specific check, with logs
nix build -L .#checks.x86_64-linux.<name>

# Every check for the current system
just check-fast

# Full nix flake check, including VM tests
just check
```

### nixbot/effects on a pull request

```bash
nix build -L .#checks.x86_64-linux.deploy-docs-rehearsal
nix build -L .#checks.x86_64-linux.release-rehearsal
```

### Docs package tests

```bash
# Full package test
just test-package docs

# Individual test types
just docs-test-unit
just docs-test-e2e
just docs-test-coverage
```

### GitHub Actions

```bash
just ci-status pr-check.yaml
just ci-logs-failed pr-check.yaml
```

## See also

- [Testing Guide](/about/contributing/testing/) - How to run tests and testing philosophy
- [Justfile Recipes](/reference/justfile-recipes/) - Complete recipe reference
- [CI Jobs](/reference/ci-jobs/) - CI job details and troubleshooting
- [CI/CD Setup](/about/contributing/ci-cd-setup/) - Gating, effects, and secrets
- [CI Philosophy](/development/traceability/ci-philosophy/) - CI design principles
