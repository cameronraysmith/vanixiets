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
| nixbot/effects (pre-merge) | Build each effect's dependencies, including the rehearsals | `nix build .#checks.x86_64-linux.deploy-docs-rehearsal .#checks.x86_64-linux.release-rehearsal .#checks.x86_64-linux.docs-preview-rehearsal` | PR, batch |
| `deploy-docs` effect | Production docs deploy (`deploy-docs production --rev <commit>`) | `just docs-deploy-production` | Push to `main` |
| `release-packages` effect | Semantic-release per package (`release-packages --rev <commit>`) | `just release-package <pkg> true` (dry run; needs `GITHUB_TOKEN`) | Push to `main` |
| `docs-preview` effect | Docs preview for a pull request, reported as the `docs-preview` check run | `just docs-deploy-preview pr-<number>` | PR (informational) |
| PR Check: `check-fast-forward` | Fast-forward merge is possible | `git merge-base --is-ancestor origin/main HEAD` | PR |
| PR Check: `playwright-drift-check` | Playwright pins match the flake input | `just bun-drift-check` | PR |
| CD: `bootstrap-verification` | Makefile bootstrap on clean Ubuntu | `make bootstrap && make verify && make setup-user` | Manual dispatch |

`checks.x86_64-linux` covers the overlay packages, the docs package tests (`package-vanixiets-docs-test-*`), dev shells, the `nixos-*` and `home-manager-*` configurations, and the structure, secrets, and treefmt checks.
From darwin, `just check-fast auto off x86_64-linux` routes the build to magnetite.

## Rehearsals

An effect contains no behaviour of its own: it is a data entry in `vanixiets.effects` that names a program, and the effects interpreter generates the glue that runs it.
The effects hold deploy secrets and run only on pushes to `main` or, for `docs-preview`, on a pull request event evaluated from `main`, so pull requests validate them through hermetic checks that run the real programs and the generated glue against stubs:

| Check | Program under test | Stubs |
|-------|--------------------|-------|
| `deploy-docs-rehearsal` | `deploy-docs production` and `deploy-docs preview` through their flags, including a superseded production run and the untrusted `--payload` hardening | Stub wrangler |
| `release-rehearsal` | `release-packages --rev`: a full semantic-release with the production plugins, including the floating major and minor tags, a superseded rev, and a diverged rev | Local git fixture, stub GitHub API |
| `docs-preview-rehearsal` | `docs-preview`: the build lookup accepting `succeeded` and `skipped_local`, each failure path, and the `docs-preview` check-run lifecycle | Stub nixbot API, stub GitHub check-runs API, stub `deploy-docs` |
| `effects-interpreter` | The script the interpreter generates for each effect: main-only guard, secret export, missing-secret failure, forge token, exact argv including `--rev` | Stub program, stub id-token endpoint |

The effects list the three rehearsals among their inputs, so the required `nixbot/effects` context fails when any of them fails; `effects-interpreter` is built by `nixbot/nix-build`.

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
| `docs-deploy-*` | Local deploys with `secrets/shared.yaml` credentials; CI deploys through effects |
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
nix build -L .#checks.x86_64-linux.docs-preview-rehearsal
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
