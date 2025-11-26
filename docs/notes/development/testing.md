# Test Infrastructure Documentation

This document describes the test harness and CI validation infrastructure for the infra repository.

## Overview

The infra repository uses a multi-layer testing approach combining nix-unit tests, validation checks, integration tests, and GitHub Actions CI.

## Local Checks (nix flake check)

Run all local checks with:

```bash
nix flake check
```

### Check Categories

| Category | File | Count | Description |
|----------|------|-------|-------------|
| nix-unit | modules/checks/nix-unit.nix | 11 tests | Unit tests for flake structure and invariants |
| validation | modules/checks/validation.nix | 7 checks | Configuration validation and naming conventions |
| integration | modules/checks/integration.nix | 1 test | VM boot tests for nixos machines |
| treefmt | - | 1 check | Code formatting validation |
| pre-commit | - | 1 check | Pre-commit hook validation |

Total: **21 checks** on aarch64-darwin (10 unique + cross-platform variants)

### nix-unit Tests (modules/checks/nix-unit.nix)

| Test ID | Name | Type | Description |
|---------|------|------|-------------|
| - | testFrameworkWorks | sanity | Verifies nix-unit framework functions |
| TC-001 | testRegressionTerraformModulesExist | regression | Terraform module exports exist |
| TC-002 | testRegressionNixosConfigExists | regression | NixOS config structure valid |
| TC-003 | testInvariantClanInventoryMachines | invariant | Clan inventory has expected machines |
| TC-004 | testInvariantNixosConfigurationsExist | invariant | Expected NixOS configs present |
| TC-005 | testInvariantDarwinConfigurationsExist | invariant | Expected Darwin configs present |
| TC-008 | testFeatureDendriticModuleDiscovery | feature | import-tree discovers nixos modules |
| TC-009 | testFeatureDarwinModuleDiscovery | feature | import-tree discovers darwin modules |
| TC-010 | testFeatureNamespaceExports | feature | Modules export to correct namespaces |
| TC-013 | testTypeSafetyModuleEvaluationIsolation | type-safety | Module structure validation |
| TC-014 | testTypeSafetySpecialargsProgpagation | type-safety | inputs available via specialArgs |
| TC-015 | testTypeSafetyNixosConfigStructure | type-safety | All configs have config attribute |
| TC-016 | testTypeSafetyTerranixModulesStructured | type-safety | Terranix modules properly structured |
| TC-021 | testMetadataFlakeOutputsExist | metadata | Core flake outputs exist |

### Validation Checks (modules/checks/validation.nix)

| Check | Description |
|-------|-------------|
| home-module-exports | Home-manager modules export correctly |
| home-configurations-exposed | Standalone homeConfigurations available |
| naming-conventions | Module naming follows conventions |
| terraform-validate | Terraform configuration valid |
| secrets-generation | sops-nix secret generation works |
| deployment-safety | Deployment safety checks pass |
| vars-user-password-validation | Clan vars user passwords validated |

### Integration Tests (modules/checks/integration.nix)

| Test | Description |
|------|-------------|
| nixos-vm-boot | NixOS VM boot test for cinnabar and electrum |

## CI Workflow (.github/workflows/ci.yaml)

### Job Overview

| Job | Purpose | Trigger |
|-----|---------|---------|
| secrets-scan | Gitleaks secret scanning | All events |
| set-variables | Compute deployment settings | All events |
| preview-release-version | Semantic-release preview | PR only |
| preview-docs-deploy | Preview docs deployment | PR only |
| bootstrap-verification | Makefile bootstrap validation | All events |
| config-validation | User config validation | All events |
| autowiring-validation | Flake output validation | All events |
| secrets-workflow | sops-nix mechanics test | All events |
| justfile-activation | Justfile recipe validation | All events |
| cache-overlay-packages | Pre-cache expensive packages | All events |
| nix | Flake output builds | All events |
| typescript | TypeScript package tests | All events |
| production-release-packages | Semantic-release | Push to main/beta |
| production-docs-deploy | Production docs deployment | Push to main |

### Build Matrix (nix job)

#### x86_64-linux

| Category | Config | Description |
|----------|--------|-------------|
| packages | - | Build all packages |
| checks-devshells | - | Build checks and devShells |
| home | - | Build homeConfigurations |
| nixos | cinnabar | VPS zerotier controller |
| nixos | electrum | VPS zerotier peer |

#### aarch64-linux

| Category | Description |
|----------|-------------|
| packages | Build all packages |
| checks-devshells | Build checks and devShells |
| home | Build homeConfigurations |

### Content-Addressed Job Caching

CI uses `.github/actions/cached-ci-job` for job-level result caching based on input file hashing.

Pattern for new jobs:

```yaml
- name: Check cache
  id: cache
  uses: ./.github/actions/cached-ci-job
  with:
    check-name: "job-name (${{ matrix.system }}, ${{ matrix.config }})"
    hash-sources: |
      flake.nix
      flake.lock
      modules/**/*.nix
      .github/actions/setup-nix/action.yml

- name: Setup Nix
  if: steps.cache.outputs.should-run == 'true'
  uses: ./.github/actions/setup-nix

# ... expensive steps gated by should-run ...

- name: Save result
  if: steps.cache.outputs.should-run == 'true'
  run: |
    mkdir -p "${{ steps.cache.outputs.cache-path }}"
    echo '{"success": true}' > "${{ steps.cache.outputs.cache-path }}/marker"

- uses: actions/cache/save@v4
  if: steps.cache.outputs.should-run == 'true'
  with:
    path: ${{ steps.cache.outputs.cache-path }}
    key: ${{ steps.cache.outputs.cache-key }}
```

## Active Fleet

| Host | Platform | Type | CI Coverage |
|------|----------|------|-------------|
| stibnite | aarch64-darwin | nix-darwin | darwinConfigurations build |
| blackphos | aarch64-darwin | nix-darwin | darwinConfigurations build |
| cinnabar | x86_64-linux | nixos | nixosConfigurations build, VM boot test |
| electrum | x86_64-linux | nixos | nixosConfigurations build, VM boot test |
| test-darwin | aarch64-darwin | nix-darwin | Darwin module discovery test |

## Running Tests

### Local

```bash
# Run all checks
nix flake check

# Run specific check
nix build .#checks.aarch64-darwin.nix-unit

# Run with verbose output
nix flake check --show-trace
```

### CI

```bash
# Trigger CI on current branch
gh workflow run ci.yaml --ref $(git branch --show-current)

# Monitor latest run
gh run list --workflow=ci.yaml -L 1
gh run watch <run-id>

# Force run (bypass cache)
gh workflow run ci.yaml --ref $(git branch --show-current) -f force_run=true
```

## Key Files

| Path | Purpose |
|------|---------|
| modules/checks/default.nix | Aggregates all checks |
| modules/checks/nix-unit.nix | nix-unit test definitions |
| modules/checks/validation.nix | Validation check definitions |
| modules/checks/integration.nix | VM integration tests |
| .github/workflows/ci.yaml | Main CI workflow |
| .github/actions/cached-ci-job/action.yaml | Content-addressed caching action |
| .github/actions/setup-nix/action.yml | Nix setup action |
