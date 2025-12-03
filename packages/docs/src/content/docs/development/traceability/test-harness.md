---
title: Test Harness Reference
description: CI-local parity matrix and test infrastructure reference
---

This reference documents the relationship between CI jobs and local test commands, enabling developers to reproduce CI behavior locally.

## CI-local parity matrix

The following table maps each CI job to its local equivalent command.
All local commands can be run from the repository root.

| CI Job | Purpose | Local Equivalent | Platform | Runtime |
|--------|---------|------------------|----------|---------|
| secrets-scan | Gitleaks secret scanning | `nix run nixpkgs#gitleaks -- detect --verbose --redact` | All | ~30s |
| set-variables | Package discovery | `just list-packages-json` | All | ~5s |
| preview-release-version | Semantic-release preview | `just preview-version main packages/<name>` | All | ~30s |
| preview-docs-deploy | Preview docs deployment | `just docs-deploy-preview` | All | ~2-3min |
| bootstrap-verification | Makefile bootstrap test | `make bootstrap && make verify && make setup-user` | All | ~2-3min |
| secrets-workflow | SOPS mechanics test | Manual encrypt/decrypt test (see below) | All | ~30s |
| flake-validation | Flake check + justfile | `just check` | All | ~5-7min |
| cache-overlay-packages | Pre-cache packages | `just cache-overlay-packages <system>` | x86_64/aarch64-linux | ~5-10min |
| nix (packages) | Build overlay packages | `just ci-build-category <system> packages` | All | ~3-5min |
| nix (checks-devshells) | Build checks and devShells | `just ci-build-category <system> checks-devshells` | All | ~3-5min |
| nix (home) | Build homeConfigurations | `just ci-build-category <system> home` | x86_64/aarch64-linux | ~3-5min |
| nix (nixos) | Build nixosConfigurations | `just ci-build-category <system> nixos <config>` | x86_64-linux | ~5-10min |
| typescript | Package tests (unit/e2e) | `just test-package docs` | All | ~2-3min |
| production-release-packages | Semantic-release | `just release-package <pkg> true` (dry run) | All | ~1min |
| production-docs-deploy | Production docs | `just docs-deploy-production` | All | ~2-3min |

### Runtime estimates

- Fast (~30s): Secret scanning, package discovery
- Medium (~2-5min): Individual builds, documentation
- Slow (~5-10min): Full flake check, NixOS builds

### secrets-workflow local equivalent

The secrets-workflow job tests SOPS encryption/decryption with ephemeral keys.
To test locally:

```bash
# Create temporary directory
mkdir -p /tmp/sops-test && cd /tmp/sops-test

# Generate ephemeral age key
nix develop --command age-keygen -o test-key.txt
TEST_PUBLIC=$(nix develop --command age-keygen -y test-key.txt)

# Create .sops.yaml
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: .*\.yaml$
    key_groups:
      - age:
        - $TEST_PUBLIC
EOF

# Create and encrypt test secret
echo "test_secret: test-value" > test.yaml
nix develop --command sops -e -i test.yaml

# Verify decryption works
SOPS_AGE_KEY_FILE=test-key.txt nix develop --command sops -d test.yaml

# Cleanup
cd - && rm -rf /tmp/sops-test
```

## CI-tested recipes

The following justfile recipes are exercised by CI jobs:

| Recipe | CI Job | Notes |
|--------|--------|-------|
| `check` | flake-validation | Runs `nix flake check` including VM tests |
| `ci-build-category` | nix (matrix) | Category-based builds for disk space optimization |
| `cache-overlay-packages` | cache-overlay-packages | Pre-cache expensive packages |
| `list-packages-json` | set-variables | Package discovery for matrix jobs |
| `test-package` | typescript | Per-package test suite |
| `preview-version` | preview-release-version | Semantic-release dry run |
| `docs-test-*` | typescript | Docs unit and E2E tests |
| `docs-deploy-preview` | preview-docs-deploy | Cloudflare preview deployment |
| `docs-deploy-production` | production-docs-deploy | Cloudflare production deployment |

## Manual-only recipes

The following recipes are not exercised by CI:

| Recipe | Rationale |
|--------|-----------|
| `activate*` | Requires physical machine access |
| `check-fast` | CI runs full checks; fast mode is for local iteration |
| `build-machine` | CI uses ci-build-category for disk optimization |
| `build-all` | Too slow; CI builds machines individually |
| `test-quick` | CI runs full check, not subset |
| `test-integration` | Subset of full check |
| `darwin-*` | Requires darwin hardware (no CI runners) |
| `nixos-bootstrap` | Destructive disk operations |
| `cache-darwin-system` | Requires darwin hardware |
| `scan-secrets` | CI uses gitleaks directly |
| `sops-*` | Requires Bitwarden access |

### Rationale for exclusions

**Platform limitations:**
- Darwin builds cannot run on Linux CI runners
- Some recipes require physical hardware (activation, bootstrap)

**Performance:**
- `build-all` would exhaust CI disk space
- CI uses matrix builds (`ci-build-category`) for parallelism

**Security:**
- `sops-*` requires Bitwarden CLI authentication
- Activation recipes would modify CI runner state

**Redundancy:**
- `check-fast` is a subset of `check`
- `scan-secrets` duplicates CI's gitleaks invocation

## Skip conditions

CI jobs use content-addressed caching to skip unchanged work.

### Content-addressed caching

Each job defines `hash-sources` patterns that determine when the job should re-run:

| Job | Hash sources |
|-----|--------------|
| bootstrap-verification | `Makefile .envrc .github/actions/setup-nix/action.yml` |
| secrets-workflow | `.sops.yaml modules/secrets/**/*.nix flake.nix flake.lock` |
| flake-validation | `justfile flake.nix flake.lock` |
| cache-overlay-packages | `pkgs/by-name/**/* modules/nixpkgs/overlays/**/*.nix flake.nix flake.lock` |
| nix | `flake.nix flake.lock pkgs/by-name/**/* modules/**/*.nix justfile` |

When these files are unchanged, the job checks for a cached successful result and skips execution.

### Platform-specific skips

| Skip condition | Affected jobs |
|----------------|---------------|
| VM tests on Darwin | `vm-*` checks automatically excluded via `lib.optionalAttrs isLinux` |
| Darwin builds on Linux | No CI runners for darwin; darwin configs not built in CI |
| aarch64 nixos configs | Not in CI matrix; built on aarch64-linux only |

### Manual skip/force mechanisms

**Force execution:**
```bash
# Via workflow dispatch
gh workflow run ci.yaml --ref $(git branch --show-current) -f force_run=true

# Via PR label
# Add "force-ci" label to PR
```

**Skip patterns:**
- `*.md` files in root are ignored by push/PR triggers
- `paths-ignore` in CI workflow skips on documentation-only changes

### Cache key structure

Cache keys combine:
- Job name (e.g., `flake-validation`)
- Matrix values (e.g., `x86_64-linux`, `packages`)
- Content hash of hash-sources files
- Repository ref

Example: `flake-validation-x86_64-linux-a1b2c3d4-refs/heads/main`

## Build matrix

The `nix` job uses a matrix to distribute builds across runners and avoid disk space exhaustion.

### x86_64-linux matrix

| Category | Config | Description | Runner |
|----------|--------|-------------|--------|
| packages | - | Overlay packages | ubuntu-latest |
| checks-devshells | - | Checks and dev shells | ubuntu-latest |
| home | - | homeConfigurations | ubuntu-latest |
| nixos | cinnabar | Zerotier controller VPS | ubuntu-latest |
| nixos | electrum | Zerotier peer VPS | ubuntu-latest |

### aarch64-linux matrix

| Category | Description | Runner |
|----------|-------------|--------|
| packages | Overlay packages | ubuntu-24.04-arm |
| checks-devshells | Checks and dev shells | ubuntu-24.04-arm |
| home | homeConfigurations | ubuntu-24.04-arm |

### Not in CI matrix

| Configuration | Reason |
|---------------|--------|
| darwinConfigurations | No darwin CI runners available |
| nixosConfigurations (galena, scheelite) | GCP VMs toggled off by default |

## Local reproduction commands

### Reproduce flake-validation failure

```bash
# Full reproduction
just check

# Fast mode (skip VM tests)
just check-fast x86_64-linux

# Specific check
nix build .#checks.x86_64-linux.nix-unit --print-build-logs
```

### Reproduce nix build failure

```bash
# Specific category
just ci-build-category x86_64-linux packages

# Specific nixos config
just ci-build-category x86_64-linux nixos cinnabar

# With verbose output
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel --print-build-logs
```

### Reproduce typescript failure

```bash
# Full package test
just test-package docs

# Individual test types
just docs-test-unit
just docs-test-e2e
just docs-test-coverage
```

### Debug CI cache issues

```bash
# View latest run status
just ci-status

# View logs
just ci-logs
just ci-logs-failed

# Debug specific job
just ci-debug-job ci.yaml "nix (x86_64-linux, packages)"

# Force rerun
gh workflow run ci.yaml --ref $(git branch --show-current) -f force_run=true
```

## See also

- [Testing Guide](/about/contributing/testing/) - How to run tests and testing philosophy
- [Justfile Recipes](/reference/justfile-recipes/) - Complete recipe reference
- [CI Jobs](/reference/ci-jobs/) - CI job details and troubleshooting
- [CI Philosophy](/development/traceability/ci-philosophy/) - CI design principles
