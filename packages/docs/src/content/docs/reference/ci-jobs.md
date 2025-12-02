---
title: CI Jobs
description: Reference for GitHub Actions CI jobs and their local equivalents
---

This reference documents the CI jobs defined in `.github/workflows/ci.yaml` and how to run equivalent checks locally.

## Overview

The CI pipeline runs on push to `main`, pull requests, and manual dispatch.
Jobs are organized in a dependency graph to optimize execution time and catch failures early.

```
secrets-scan
    └── set-variables
            ├── preview-release-version (PR only)
            ├── preview-docs-deploy (PR only)
            ├── bootstrap-verification
            ├── secrets-workflow
            ├── flake-validation
            ├── cache-overlay-packages
            │       └── nix (matrix)
            └── typescript (matrix)
                    └── production-release-packages (main only)
                            └── production-docs-deploy (main only)
```

## Job reference

### secrets-scan

Scans repository for hardcoded secrets using gitleaks.

| Attribute | Value |
|-----------|-------|
| Runner | `ubuntu-latest` |
| Triggers | All (always runs first) |
| Local equivalent | `nix run nixpkgs#gitleaks -- detect --verbose --redact` |

**Note:** CI uses `nix run nixpkgs#gitleaks` directly rather than the justfile recipe.

### set-variables

Determines deployment settings and discovers packages for matrix jobs.

| Attribute | Value |
|-----------|-------|
| Runner | `ubuntu-latest` |
| Triggers | After secrets-scan |
| Local equivalent | `just list-packages-json` |

**Outputs:**
- `debug` - Whether debug mode is enabled
- `deploy_enabled` - Whether docs deployment is enabled
- `deploy_environment` - Target environment (preview/production)
- `packages` - JSON array of packages for matrix jobs
- `force-ci` - Whether to force execution

### preview-release-version

Previews semantic-release version for each package (PR only).

| Attribute | Value |
|-----------|-------|
| Runner | `ubuntu-latest` |
| Triggers | Pull requests only |
| Matrix | Per package |
| Local equivalent | `just preview-version main packages/<name>` |

### preview-docs-deploy

Deploys documentation to preview environment.

| Attribute | Value |
|-----------|-------|
| Runner | Via `deploy-docs.yaml` |
| Triggers | Pull requests only |
| Environment | `preview` |
| Local equivalent | `just docs-deploy-preview` |

**Preview URL:** `https://b-<branch>-infra-docs.sciexp.workers.dev`

### bootstrap-verification

Validates Makefile bootstrap workflow on clean Ubuntu system.

| Attribute | Value |
|-----------|-------|
| Runner | `ubuntu-latest` |
| Triggers | All |
| Local equivalent | `make bootstrap && make verify && make setup-user` |

Verifies:
- Nix installation via DeterminateSystems installer
- direnv configuration
- Age key generation for sops

### secrets-workflow

Tests sops-nix mechanics with ephemeral test keys.

| Attribute | Value |
|-----------|-------|
| Runner | `ubuntu-latest` |
| Triggers | All |
| Local equivalent | Manual sops encrypt/decrypt test |

Creates ephemeral age keys, encrypts test secrets, and verifies decryption works correctly.

### flake-validation

Validates flake structure, justfile recipes, and runs `nix flake check`.

| Attribute | Value |
|-----------|-------|
| Runner | `ubuntu-latest` |
| Triggers | All |
| Local equivalent | `just check` |

Verifies:
- Core justfile recipes exist (`activate`, `verify`, `check`, `lint`)
- `nix flake check` passes (includes VM tests on Linux)

**For faster local iteration:** `just check-fast` excludes VM tests (~1-2 min vs ~7 min).

### cache-overlay-packages

Pre-caches resource-intensive overlay packages before main build.

| Attribute | Value |
|-----------|-------|
| Runner | `ubuntu-latest` (x86_64), `ubuntu-24.04-arm` (aarch64) |
| Triggers | All |
| Matrix | `x86_64-linux`, `aarch64-linux` |
| Local equivalent | `just cache-overlay-packages <system>` |

Prevents disk space exhaustion during CI builds, especially for Rust packages.

### nix

Builds flake outputs via category-based matrix for disk space optimization.

| Attribute | Value |
|-----------|-------|
| Runner | `ubuntu-latest` (x86_64), `ubuntu-24.04-arm` (aarch64) |
| Triggers | All |
| Depends on | `cache-overlay-packages` |
| Local equivalent | `just ci-build-category <system> <category> [config]` |

**Matrix configurations:**

| System | Category | Config | Description |
|--------|----------|--------|-------------|
| x86_64-linux | packages | - | Overlay packages |
| x86_64-linux | checks-devshells | - | Checks and dev shells |
| x86_64-linux | home | - | Home-manager configs |
| x86_64-linux | nixos | cinnabar | NixOS server |
| x86_64-linux | nixos | electrum | NixOS server |
| aarch64-linux | packages | - | Overlay packages |
| aarch64-linux | checks-devshells | - | Checks and dev shells |
| aarch64-linux | home | - | Home-manager configs |

### typescript

Tests TypeScript packages (docs site).

| Attribute | Value |
|-----------|-------|
| Runner | Via `package-test.yaml` |
| Triggers | All |
| Matrix | Per package |
| Local equivalent | `just test-package <package>` |

Runs:
- `bun install`
- `bun run test:unit`
- `bun run test:coverage`
- `bun run build`
- `bun run test:e2e`

### production-release-packages

Releases packages via semantic-release on main branch.

| Attribute | Value |
|-----------|-------|
| Runner | Via `package-release.yaml` |
| Triggers | Push to main/beta only |
| Matrix | Per package |
| Local equivalent | `just release-package <package>` (dry run) |

### production-docs-deploy

Deploys documentation to production.

| Attribute | Value |
|-----------|-------|
| Runner | Via `deploy-docs.yaml` |
| Triggers | Push to main only |
| Environment | `production` |
| Local equivalent | `just docs-deploy-production` |

**Production URL:** `https://infra.cameronraysmith.net`

## Running CI locally

### Full validation

```bash
# Run all checks (equivalent to flake-validation job)
just check

# Fast checks only (skip VM tests)
just check-fast
```

### Package testing

```bash
# Test specific package
just test-package docs

# Preview release version
just preview-version main packages/docs
```

### Build verification

```bash
# Build specific category
just ci-build-category x86_64-linux packages
just ci-build-category x86_64-linux nixos cinnabar

# Build all outputs for current system
just ci-build-local
```

### Documentation

```bash
# Full docs test suite
just docs-test

# Preview deployment
just docs-deploy-preview

# Link validation
just docs-linkcheck
```

## Caching

CI uses per-job content-addressed caching to skip unchanged jobs.
The caching is based on:
- Content hash of relevant source files
- GitHub Actions cache API

To force re-execution:
- Add the `force-ci` label to a PR
- Use `force_run: true` in workflow dispatch

See [ADR-0016](/development/architecture/adrs/0016-per-job-content-addressed-caching/) for details.

## Troubleshooting

### Common failures

**flake-validation fails:**
```bash
# Check locally
just check

# For faster iteration
just check-fast x86_64-linux
```

**nix build fails:**
```bash
# Build specific category locally
just ci-build-category <system> <category>

# Check disk space
df -h
```

**typescript tests fail:**
```bash
# Run tests locally
just test-package docs

# Check coverage
just docs-test-coverage
```

### Viewing logs

```bash
# View latest run logs
just ci-logs

# View only failed logs
just ci-logs-failed

# Debug specific job
just ci-debug-job ci.yaml "nix (x86_64-linux, packages)"
```

## See also

- [Justfile Recipes](/reference/justfile-recipes/) - Local recipe reference
- [CI Philosophy](/development/traceability/ci-philosophy/) - Design principles
- [Troubleshooting CI Cache](/development/operations/troubleshooting-ci-cache/) - Cache issues
