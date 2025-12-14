---
title: CI Testing Strategy
---

This document describes what our CI tests validate and why, organized by job.

## Testing Philosophy

Our CI validates the **user experience** described in the README, not just that code compiles. Tests are designed to:

1. **Mirror user workflows** - If a user following the README would do it, CI tests it
2. **Discover resources dynamically** - No hardcoded lists that drift out of sync
3. **Fail fast and clearly** - Errors should point to the exact problem
4. **Scale efficiently** - Tests should remain fast as the project grows

## Job: flake-validation

**Purpose**: Validates flake structure and developer tooling.

### What It Tests

#### 1. Justfile Recipe Discovery
```bash
just --summary  # Shows all available recipes
```

**Validates**:
- Core recipes exist: `activate`, `verify`, `check`, `lint`
- Justfile is accessible in devshell
- Recipe descriptions are visible

**Why**: First thing users do is `just --list` to see what's available.

#### 2. Flake Structure
```bash
just check  # Runs nix flake check
```

**Validates**:
- Flake syntax is correct
- All outputs are properly defined
- No circular dependencies
- All nix checks pass (see Nix Checks section below)

**Why**: Users run `just check` before making changes. Must pass consistently.

### Expected Runtime

- **Duration**: 5-7 minutes (includes VM tests on Linux)
- **Fast local alternative**: `just check-fast` (~1-2 min, skips VM tests)

## Job: nix

**Purpose**: Validates that all flake outputs actually build.

### What It Tests

Builds all outputs by category for each system:
- **packages**: overlay packages for x86_64-linux and aarch64-linux
- **checks-devshells**: all checks and development shells
- **home**: homeConfigurations for Linux systems
- **nixos**: individual nixosConfigurations (cinnabar, electrum)

### Build Matrix Strategy

The nix job uses a matrix strategy to distribute builds across multiple runners and avoid disk space exhaustion:
- x86_64-linux: packages, checks-devshells, home, nixos (cinnabar), nixos (electrum)
- aarch64-linux: packages, checks-devshells, home

Darwin configurations are not built in CI due to lack of macOS runners.

## Job: secrets-workflow

**Purpose**: Validates secrets management infrastructure.

### What It Tests

- Ephemeral sops-age key generation
- Encrypted file creation with sops-nix
- File decryption with generated keys
- Cleanup of test secrets

**Why**: Secrets are critical infrastructure. Test that sops-nix integration works.

## Job: typescript

**Purpose**: Validates TypeScript packages in the packages/ directory.

### What It Tests

- Dependency installation (bun)
- Build process
- Unit tests with coverage
- E2E tests where applicable

**Why**: TypeScript packages (like docs) are part of the user experience. Must build and pass tests.

## Nix Checks

The flake defines checks in `modules/checks/` that run during `nix flake check`:

**Validation checks** (all platforms):
- `home-module-exports` — validates home modules exported to flake.modules.homeManager namespace
- `home-configurations-exposed` — validates nested homeConfigurations exposed for nh CLI
- `naming-conventions` — validates consistent kebab-case naming across machines
- `terraform-validate` — validates generated terraform is syntactically correct
- `deployment-safety` — verifies terraform configuration safety patterns
- `vars-user-password-validation` — validates clan vars system for user password management
- `secrets-tier-separation` — validates secrets tier separation (vars vs secrets)
- `clan-inventory-consistency` — validates clan inventory references valid machines
- `secrets-encryption-integrity` — validates all secrets are SOPS-encrypted
- `machine-registry-completeness` — validates all machine modules are registered in clan

**Integration checks** (Linux only):
- `vm-test-framework` — VM test framework smoke test
- `vm-boot-all-machines` — VM boot validation for NixOS machines

**Other checks**:
- `nix-unit` — unit tests for flake structure and module exports
- `treefmt` — formatting validation
- `pre-commit` — pre-commit hook validation

## Adding New Tests

### When to Add a Nix Check

Add a check in `modules/checks/` when:
- Validating flake structure or module exports
- Testing infrastructure configuration (terraform, secrets)
- Verifying cross-cutting concerns (naming conventions, registry completeness)

### When to Create New CI Job

Create new job when:
- Test requires different environment (e.g., specific runner type)
- Test has very different performance characteristics
- Test validates completely separate concern (e.g., TypeScript vs Nix)

### Dynamic vs Static Tests

**Prefer dynamic** when:
- Resource list changes frequently (configs, packages, etc)
- Maintaining hardcoded lists is error-prone
- Discovery logic is itself important to validate

**Use static** when:
- Testing specific known failures
- Validating backwards compatibility
- Performance is critical (discovery is expensive)

## Test Maintenance

### Monitoring Test Performance

Track in CI:
- `flake-validation` should stay under 10min (includes VM tests)
- If individual checks become slow, consider optimization

Track locally:
- `just check-fast` should stay under 2min
- If it grows beyond 3min, investigate what's being evaluated

## Job Execution Caching

As of ADR-0016, all jobs use per-job content-addressed caching via GitHub Checks API.
Each job independently decides whether to run based on:
1. Previous successful execution for the current commit SHA
2. Relevant file changes (via path filters)
3. Manual force-run override

This means jobs automatically skip if they've already succeeded for a given commit, providing optimal retry behavior and faster feedback loops.

## References

- **Implementation**: `.github/workflows/ci.yaml` (see job definitions for caching logic)
- **Caching architecture**: [ADR-0016: Per-job content-addressed caching](/development/architecture/adrs/0016-per-job-content-addressed-caching/)
- **User workflows**: Repository README (usage section)
