---
title: Justfile Recipes
description: Complete reference for all justfile recipes organized by functional group
sidebar:
  order: 4
---

This reference documents all justfile recipes available in the infra repository.
Run `just --list` to see available recipes or `just help` for usage information.

## Quick reference

| Group | Count | Purpose |
|-------|-------|---------|
| [activation](#activation) | 4 | System/home configuration activation |
| [nix](#nix) | 13 | Core nix operations |
| [clan](#clan) | 7 | Machine building and testing |
| [docs](#docs) | 17 | Documentation site management |
| [containers](#containers) | 7 | Container image building |
| [secrets](#secrets) | 13 | SOPS secrets management |
| [sops](#sops) | 8 | SOPS key management |
| [CI/CD](#cicd) | 27 | CI/CD operations and caching |
| [nix-home-manager](#nix-home-manager) | 4 | Home-manager bootstrap |
| [nix-darwin](#nix-darwin) | 3 | Darwin bootstrap |
| [nixos](#nixos) | 4 | NixOS operations |

## Activation

Unified activation commands using nh via flake apps.
All recipes accept nh flags: `--dry` (preview), `--ask` (confirm), `--verbose`.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `activate` | `*FLAGS` | Auto-detect platform and activate current machine | No |
| `activate-darwin` | `hostname *FLAGS` | Activate darwin configuration | No |
| `activate-os` | `hostname *FLAGS` | Activate NixOS configuration | No |
| `activate-home` | `username *FLAGS` | Activate home-manager configuration | No |

**Examples:**

```bash
# Preview changes before applying
just activate --dry

# Apply with confirmation prompt
just activate --ask

# Activate specific darwin host
just activate-darwin stibnite

# Activate home-manager for user
just activate-home crs58 --dry
```

## Nix

Core nix operations for building, checking, and managing the flake.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `flake-info` | - | Print nix flake inputs and outputs | No |
| `lint` | - | Lint nix files with pre-commit | No |
| `dev` | - | Manually enter dev shell | No |
| `clean` | - | Remove build output link (no garbage collection) | No |
| `build` | `profile` | Build nix flake (runs lint and check first) | No |
| `debug-build` | `package` | Build experimental debug package with nom | No |
| `debug-list` | - | List all available debug packages | No |
| `check` | - | Run nix flake check (full, including VM tests) | **Yes** |
| `check-fast` | `system` | Fast checks excluding heavy VM integration tests | No |
| `verify` | - | Verify system configuration builds after updates | No |
| `bisect-nixpkgs` | - | Bisect nixpkgs commits (automatic mode) | No |
| `bisect-nixpkgs-manual` | `command` | Bisect nixpkgs commits (manual mode) | No |
| `bootstrap-shell` | - | Shell with bootstrap dependencies | No |
| `update` | - | Update all nix flake inputs | No |
| `update-package` | `package` | Update a package using its updateScript | No |

**CI-tested recipes:** `check` is called by the `flake-validation` CI job.

## Clan

Commands for clan-based machine management.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `test` | - | Run all tests (nix flake check) | No |
| `test-quick` | - | Run fast validation tests (nix-unit) | No |
| `test-integration` | - | Run VM integration tests (Linux only) | No |
| `build-all` | - | Build all machine configurations using nom | No |
| `build-machine` | `machine` | Build a specific machine configuration | No |
| `clan-show` | - | Show flake outputs | No |
| `clan-metadata` | - | Show flake metadata | No |

## Docs

Documentation site management using Starlight and Cloudflare Workers.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `install` | - | Install workspace dependencies (bun install) | No |
| `docs-dev` | - | Start documentation development server | No |
| `docs-build` | - | Build the documentation site | No |
| `docs-preview` | - | Preview the built documentation site | No |
| `docs-format` | - | Format documentation code with Biome | No |
| `docs-lint` | - | Lint documentation code with Biome | No |
| `docs-check` | - | Check and fix documentation code with Biome | No |
| `docs-linkcheck` | - | Validate internal and external links | No |
| `docs-test` | - | Run all documentation tests | **Yes** |
| `docs-test-unit` | - | Run documentation unit tests | **Yes** |
| `docs-test-e2e` | - | Run documentation E2E tests | **Yes** |
| `docs-test-coverage` | - | Generate documentation test coverage report | **Yes** |
| `docs-deploy-preview` | `branch` | Deploy to Cloudflare Workers (preview) | **Yes** |
| `docs-deploy-production` | - | Deploy to Cloudflare Workers (production) | **Yes** |
| `docs-deployments` | - | List recent Cloudflare deployments | No |
| `docs-tail` | - | Tail live logs from Cloudflare Workers | No |
| `docs-versions` | `limit` | List recent Cloudflare versions | No |

**CI-tested recipes:** `docs-test-*` recipes are called by the `typescript` CI job.
`docs-deploy-*` recipes are called by `preview-docs-deploy` and `production-docs-deploy` jobs.

## Containers

Container image building and testing.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `build-container` | `container arch?` | Build container for specified architecture | No |
| `build-multiarch` | `container` | Build container for both aarch64 and x86_64 | No |
| `load-container` | - | Load container image from result into docker | No |
| `load-native` | - | Load native architecture from multi-arch build | No |
| `test-container` | `binary` | Test container by running binary with --help | No |
| `container-all` | `container binary arch?` | Complete workflow: build, load, test | No |
| `container-all-multiarch` | `container binary` | Multi-arch workflow: build both, load native, test | No |

## Secrets

SOPS-based secrets management.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `scan-secrets` | - | Scan repository for hardcoded secrets (full history) | No |
| `scan-staged` | - | Scan staged changes for secrets (pre-commit) | No |
| `show` | - | Show existing secrets using sops | No |
| `seed-dotenv` | - | Create empty dotenv from template | No |
| `export` | - | Export unique secrets to dotenv format | No |
| `check-secrets` | - | Check secrets are available in sops environment | No |
| `get-kubeconfig` | - | Save KUBECONFIG to file from sops | No |
| `hash-encrypt` | `source_file user?` | Hash-encrypt file and store in secrets directory | No |
| `verify-hash` | `original_file secret_file` | Verify hash integrity of encrypted file | No |
| `edit-secret` | `file` | Edit a sops encrypted file | No |
| `new-secret` | `file` | Create a new sops encrypted file | No |
| `get-shared-secret` | `key` | Show specific secret value from shared secrets | No |
| `run-with-secrets` | `+command` | Run command with all shared secrets as env vars | No |
| `validate-secrets` | - | Validate all sops encrypted files can be decrypted | No |

**Note:** CI uses `nix run nixpkgs#gitleaks` directly rather than `just scan-secrets`.

## SOPS

SOPS key management and rotation.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `sops-extract-keys` | `key?` | Extract key details from Bitwarden | No |
| `sops-update-yaml` | - | Update .sops.yaml with keys from Bitwarden | No |
| `sops-deploy-host-key` | `host` | Deploy host key from Bitwarden to /etc/ssh | No |
| `sops-validate-correspondences` | - | Validate SOPS key correspondences | No |
| `sops-sync-keys` | `*FLAGS` | Regenerate ~/.config/sops/age/keys.txt | No |
| `sops-rotate` | - | Full key rotation workflow (interactive) | No |
| `update-all-keys` | - | Update keys for all encrypted files | No |
| `sops-load-agent` | - | Load SOPS launchd agent (darwin only) | No |

## CI/CD

CI/CD operations, caching, and release management.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `ci-run-watch` | `workflow?` | Trigger CI workflow and wait for result | No |
| `ci-status` | `workflow?` | View latest CI run status | No |
| `ci-logs` | `workflow?` | View latest CI run logs | No |
| `ci-logs-failed` | `workflow?` | View only failed logs from latest CI run | No |
| `ci-show-outputs` | `system?` | List categorized flake outputs | No |
| `ci-build-local` | `category? system?` | Build all flake outputs locally with nom | No |
| `ci-build-category` | `system category config?` | Build specific category for CI matrix | **Yes** |
| `ci-cache-category` | `system category config?` | Build and cache category with cachix | No |
| `ci-validate` | `workflow? run_id?` | Validate latest CI run comprehensively | No |
| `ci-debug-job` | `workflow? job_name?` | Debug specific failed job | No |
| `ghsecrets` | `repo?` | Update GitHub secrets from sops | No |
| `list-workflows` | - | List available workflows (via act) | No |
| `test-flake-workflow` | - | Execute ci.yaml workflow locally via act | No |
| `ratchet-pin` | - | Pin GitHub Actions workflow versions to hashes | No |
| `ratchet-unpin` | - | Unpin workflow versions to semantic values | No |
| `ratchet-update` | - | Update GitHub Actions to latest versions | No |
| `ratchet-upgrade` | - | Upgrade GitHub Actions across major versions | No |
| `cache-rosetta-builder` | - | Push nix-rosetta-builder VM image to cachix | No |
| `check-rosetta-cache` | - | Check if rosetta-builder image is cached | No |
| `cache-linux-package` | `package` | Build Linux package and push to cachix | No |
| `test-cachix` | - | Test cachix push/pull with simple derivation | No |
| `cache-ci-outputs` | `system?` | Build all CI outputs and push to cachix | No |
| `cache-darwin-system` | - | Build darwin system and push to cachix | No |
| `cache-overlay-packages` | `system` | Cache all overlay packages for system | **Yes** |
| `list-packages` | - | List all packages in packages/ directory | No |
| `list-packages-json` | - | List packages in JSON format for CI matrix | **Yes** |
| `validate-package` | `package` | Validate package structure | No |
| `test-package` | `package` | Test package (install, tests, build) | **Yes** |
| `preview-version` | `target? package?` | Preview semantic-release version | **Yes** |
| `release-package` | `package dry_run?` | Release package using semantic-release | No |

**CI-tested recipes:**
- `ci-build-category` is called by the `nix` CI job matrix
- `cache-overlay-packages` is called by the `cache-overlay-packages` CI job
- `list-packages-json` is called by the `set-variables` CI job
- `test-package` is called by the `typescript` CI job
- `preview-version` is called by the `preview-release-version` CI job

## Nix-home-manager

Home-manager bootstrap recipes for initial setup.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `home-manager-bootstrap-build` | `profile?` | Bootstrap build home-manager (before installed) | No |
| `home-manager-bootstrap-switch` | `profile?` | Bootstrap switch home-manager (before installed) | No |
| `home-manager-build` | `profile?` | Build home-manager with flake | No |
| `home-manager-switch` | `profile?` | Switch home-manager with flake | No |

**Note:** Use `activate-home` for normal operations.
These recipes are for bootstrap scenarios before home-manager is installed.

## Nix-darwin

Darwin bootstrap recipes for initial setup.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `darwin-bootstrap` | `profile?` | Bootstrap nix-darwin with flake | No |
| `darwin-build` | `profile?` | Build darwin from flake | No |
| `darwin-test` | `profile?` | Test darwin from flake | No |

**Note:** Use `activate-darwin` for normal operations.
These recipes are for bootstrap scenarios before nix-darwin is installed.

## NixOS

NixOS operations and bootstrap.

| Recipe | Arguments | Description | CI-tested |
|--------|-----------|-------------|-----------|
| `nixos-bootstrap` | `destination username publickey` | Bootstrap NixOS (physical partitioning) | No |
| `nixos-vm-sync` | `user destination` | Copy flake to VM via rsync | No |
| `nixos-build` | `profile?` | Build NixOS from flake | No |
| `nixos-test` | `profile?` | Test NixOS from flake | No |

**Warning:** `nixos-bootstrap` performs destructive disk operations.
Only use for initial physical machine setup.

**Note:** Use `activate-os` for normal NixOS activation.

## See also

- [Testing Guide](/about/contributing/testing/) - How to run tests and testing philosophy
- [Test Harness Reference](/development/traceability/test-harness/) - CI-local parity matrix
- [Flake Apps](/reference/flake-apps/) - Flake app reference
- [CI Jobs](/reference/ci-jobs/) - CI job to recipe mapping
- [Getting Started](/guides/getting-started/) - Initial setup guide
