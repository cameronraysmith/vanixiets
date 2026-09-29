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
| nixbot/effects (pre-merge) | Build each effect's dependencies, including the rehearsals | `nix build .#checks.x86_64-linux.release-rehearsal .#checks.x86_64-linux.deploy-docs-rehearsal` | PR, batch |
| `deploy-docs` effect | Production docs deploy | `just docs-deploy-production` | Push to `main` |
| `release-packages` effect | Semantic-release per package | `just release-package <pkg> true` (dry run; needs `GITHUB_TOKEN`) | Push to `main` |
| `deploy-docs-preview` effect | Docs preview for a pull request | `just docs-deploy-preview pr-<number>` | PR (informational) |
| PR Check: `check-fast-forward` | Fast-forward merge is possible | `git merge-base --is-ancestor origin/main HEAD` | PR |
| PR Check: `playwright-drift-check` | Playwright pins match the flake input | `just bun-drift-check` | PR |
| CD: `bootstrap-verification` | Makefile bootstrap on clean Ubuntu | `make bootstrap && make verify && make setup-user` | Manual dispatch |

`checks.x86_64-linux` covers the overlay packages, the docs package tests (`package-vanixiets-docs-test-*`), dev shells, the `nixos-*` and `home-manager-*` configurations, and the structure, secrets, and treefmt checks.
From darwin, `just check-fast auto off x86_64-linux` routes the build to magnetite.

## Rehearsals

The effects hold deploy secrets and run only on pushes to `main`, so pull requests validate them through hermetic rehearsal checks that run the real programs against stubs:

| Check | Program under test | Stubs |
|-------|--------------------|-------|
| `release-rehearsal` | `release` app: a full semantic-release with the production plugins, including the floating major and minor tags | Local git fixture, stub GitHub API |
| `deploy-docs-rehearsal` | `deploy-docs production` and `deploy-docs preview` | Stub wrangler |

Both are dependencies of the effects, so the required `nixbot/effects` context fails when either fails.

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
nix build -L .#checks.x86_64-linux.release-rehearsal
nix build -L .#checks.x86_64-linux.deploy-docs-rehearsal
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
