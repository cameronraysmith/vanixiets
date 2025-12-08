---
title: Testing
description: Comprehensive testing guide for infrastructure and documentation
sidebar:
  order: 5
---

This guide covers the complete testing strategy for the infra repository, including infrastructure validation (nix-unit, validation checks, VM tests) and documentation testing (Vitest, Playwright).

## Test philosophy

### Risk-based testing

Testing effort scales with change risk.
Not all changes require the same validation depth.

The testing strategy focuses on three principles:

1. **Critical path first**: Validate core functionality that, if broken, would block all development.
2. **Depth matches risk**: Configuration-only changes need less validation than module logic changes.
3. **Trust boundaries**: Local validation for high-risk changes; trust CI for well-tested patterns.

### Depth scaling by change type

Match your validation depth to what you changed:

| Change type | Recommended check | Rationale |
|-------------|-------------------|-----------|
| Config values only | `just check-fast` | Low risk, fast feedback (~1-2 min) |
| Module logic | `just check` | Medium risk, need full validation (~5-7 min) |
| New host/user | `just check` + manual deploy | High risk, full validation + real deployment |
| CI workflow changes | Push to trigger CI | CI is the test |
| Documentation only | `just docs-build` | Starlight validation, no nix checks needed |
| Test infrastructure | `just check` | Test the tests |

### When to run full checks

Run comprehensive validation (`just check` or `nix flake check`) before:

- Creating or updating a pull request
- After rebasing on main
- When touching test infrastructure (`modules/checks/`)
- When adding new machines or users
- After significant flake.lock updates

For routine development iteration, `just check-fast` provides faster feedback by skipping VM integration tests.

## Infrastructure testing

Infrastructure tests validate the nix flake structure, machine configurations, and deployment safety.

### Test categories

| Category | File | Count | Purpose |
|----------|------|-------|---------|
| nix-unit | `modules/checks/nix-unit.nix` | 12 | Unit tests for flake structure and invariants |
| validation | `modules/checks/validation.nix` | 6 | Configuration validation and naming conventions |
| integration | `modules/checks/integration.nix` | 2 | VM boot tests for NixOS machines |
| performance | `modules/checks/performance.nix` | 4 | Performance benchmarks and optimization (planned) |
| treefmt | (flake-parts) | 1 | Code formatting validation |
| pre-commit | (flake-parts) | 1 | Pre-commit hook validation |

### Running infrastructure tests

```bash
# Run all checks (includes VM tests, ~5-7 minutes)
just check

# Run fast checks only (excludes VM tests, ~1-2 minutes)
just check-fast

# Run specific check
nix build .#checks.aarch64-darwin.nix-unit

# Run with verbose output for debugging
nix flake check --show-trace
```

### nix-unit tests

nix-unit tests validate flake structure and configuration invariants without building derivations.

| TC-ID | Test Name | Type | Description |
|-------|-----------|------|-------------|
| TC-001 | testMetadataFlakeOutputsExist | smoke | Flake structure smoke test |
| TC-002 | testRegressionTerraformModulesExist | regression | Terraform module exports exist |
| TC-003 | testRegressionNixosConfigExists | regression | NixOS config structure valid |
| TC-004 | testInvariantClanInventoryMachines | invariant | Expected machines in clan inventory |
| TC-005 | testInvariantNixosConfigurationsExist | invariant | Expected NixOS configs present |
| TC-006 | testInvariantDarwinConfigurationsExist | invariant | Expected Darwin configs present |
| TC-007 | testInvariantHomeConfigurationsExist | invariant | Expected home configs present |
| TC-008 | testFeatureDendriticModuleDiscovery | feature | import-tree discovers nixos modules |
| TC-009 | testFeatureDarwinModuleDiscovery | feature | import-tree discovers darwin modules |
| TC-010 | testFeatureNamespaceExports | feature | Modules export to correct namespaces |
| TC-011 | testTypeSafetySpecialargsPropagation | type-safety | inputs available via specialArgs |
| TC-012 | testTypeSafetyNixosConfigStructure | type-safety | All configs have config attribute |

### Validation checks

Validation checks run shell commands to verify configuration correctness.

| TC-ID | Check Name | Description |
|-------|------------|-------------|
| TC-020 | home-module-exports | Home modules exported to dendritic namespace |
| TC-021 | home-configurations-exposed | Nested homeConfigurations exposed for nh CLI |
| TC-022 | naming-conventions | Machine names follow kebab-case |
| TC-023 | terraform-validate | Terraform configuration syntactically valid |
| TC-024 | terraform-config-structure | Terraform config has expected resources |
| TC-025 | vars-user-password-validation | Clan vars system for user passwords |

### Integration tests (Linux only)

VM integration tests require QEMU/KVM and only run on Linux systems.

| TC-ID | Check Name | Description |
|-------|------------|-------------|
| TC-040 | vm-test-framework | VM test framework smoke test |
| TC-041 | vm-boot-all-machines | VM boot validation for NixOS machines |

These tests are automatically skipped on Darwin.
Use `just check-fast` to skip them locally on Linux when iterating quickly.

### Performance tests (planned)

Performance tests validate build efficiency and closure sizes.

| TC-ID | Check Name | Description |
|-------|------------|-------------|
| TC-050 | closure-size-validation | Closure size validation (planned) |
| TC-051 | ci-build-matrix | CI build matrix optimization (planned) |
| TC-052 | build-performance-benchmarks | Build performance benchmarks (planned) |
| TC-053 | binary-cache-efficiency | Binary cache efficiency (planned) |

These tests are currently in planning phase and not yet implemented.

## Documentation testing

Documentation uses Vitest for unit testing and Playwright for E2E testing.

### Test structure

```
packages/docs/
├── src/
│   ├── components/
│   │   └── Card.test.ts         # Component tests (co-located)
│   └── utils/
│       └── formatters.test.ts   # Unit tests (co-located)
├── e2e/
│   └── homepage.spec.ts         # E2E tests
├── tests/
│   ├── fixtures/                # Shared test data
│   └── types/                   # Test type definitions
├── vitest.config.ts             # Vitest configuration
└── playwright.config.ts         # Playwright configuration
```

### Running documentation tests

```bash
# Run all documentation tests
just docs-test

# Run unit tests only
just docs-test-unit

# Run E2E tests
just docs-test-e2e

# Generate coverage report
just docs-test-coverage

# Watch mode for development
cd packages/docs && bun run test:watch
```

### Writing unit tests

Unit tests use Vitest and are co-located with source files:

```typescript
// src/utils/formatters.test.ts
import { describe, expect, it } from "vitest";
import { capitalizeFirst } from "./formatters";

describe("capitalizeFirst", () => {
  it("capitalizes the first letter", () => {
    expect(capitalizeFirst("hello")).toBe("Hello");
  });
});
```

### Writing component tests

Use the Astro Container API to test Astro components:

```typescript
// src/components/Card.test.ts
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, expect, it } from "vitest";
import Card from "./Card.astro";

describe("Card component", () => {
  it("renders with props", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Card, {
      props: { title: "Test Card" },
    });
    expect(result).toContain("Test Card");
  });
});
```

### Writing E2E tests

E2E tests use Playwright and live in the `e2e/` directory:

```typescript
// e2e/homepage.spec.ts
import { expect, test } from "@playwright/test";

test.describe("Homepage", () => {
  test("has correct title", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle(/infra/);
  });
});
```

## Choosing check depth

Use this decision tree to select the appropriate validation level:

```
Changed documentation only?
  └─ Yes → just docs-build && just docs-linkcheck
  └─ No → Continue...

Changed config values only (no module logic)?
  └─ Yes → just check-fast
  └─ No → Continue...

Changed module logic, added host/user, or touched tests?
  └─ Yes → just check
  └─ No → Continue...

Changed CI workflow?
  └─ Yes → Push to trigger CI (CI is the test)
```

### `just check` vs `just check-fast`

| Command | Runtime | VM tests | Use when |
|---------|---------|----------|----------|
| `just check` | ~5-7 min | Included | Before PR, after rebase, full validation |
| `just check-fast` | ~1-2 min | Excluded | Development iteration, config-only changes |

The difference is VM integration tests, which:
- Require QEMU/KVM (Linux only)
- Boot NixOS VMs to validate machine configurations
- Are automatically skipped on Darwin

## Troubleshooting

### nix-unit test failures

**Symptom:** nix-unit tests fail with attribute errors

```
error: attribute 'cinnabar' missing
```

**Solution:** Check that expected machine names match your configuration.
Update test expectations in `modules/checks/nix-unit.nix` if you've renamed machines.

**Symptom:** Warnings about unknown settings

```
warning: unknown setting 'allowed-users'
```

**Context:** These warnings are expected and harmless.
nix-unit runs in pure evaluation mode where daemon settings don't apply.

### Cross-platform issues

**Symptom:** VM tests fail on Darwin

**Context:** VM integration tests require QEMU/KVM and only work on Linux.
They're automatically skipped on Darwin via `lib.optionalAttrs isLinux`.

**Solution:** Use `just check-fast` on Darwin.
CI runs VM tests on Linux runners.

**Symptom:** Different derivation hashes between systems

**Context:** Some packages have platform-specific closures.
This is expected for darwin-specific and linux-specific configurations.

### CI cache issues

**Symptom:** CI job runs when it should skip (or vice versa)

**Context:** CI uses content-addressed caching based on file hashes.

**Solutions:**
- Force rerun: `gh workflow run ci.yaml --ref $(git branch --show-current) -f force_run=true`
- Or add `force-ci` label to PR
- Check hash-sources patterns in CI job definitions

**Symptom:** Cache hit but build still fails

**Context:** Cache key may match but cached result may be stale.

**Solution:** Force rerun with `force_run=true` to bypass cache.

### Running/skipping specific checks

```bash
# Run single check by name
nix build .#checks.aarch64-darwin.nix-unit

# List all available checks
nix flake show --json | jq '.checks'

# Skip VM tests (fast mode)
just check-fast x86_64-linux
```

### Documentation test issues

**Symptom:** Playwright browsers not found

```bash
# Install Playwright browsers
just playwright-install
# or
cd packages/docs && bunx playwright install --with-deps
```

**Symptom:** Port 4321 already in use

**Solution:** Stop other development servers on port 4321.

**Symptom:** Nix environment issues with Playwright

```bash
# Rebuild nix shell
nix develop --rebuild

# Verify environment variables
echo $PLAYWRIGHT_BROWSERS_PATH
```

## Module options affecting tests

Test behavior can be configured via module options in `modules/checks/`:

### Enable flags

Tests are enabled by default.
To disable specific test categories during development:

```nix
# In a flake module (not recommended for production)
perSystem = { ... }: {
  checks = lib.optionalAttrs false { /* disabled checks */ };
};
```

### Environment variables

| Variable | Purpose |
|----------|---------|
| `PLAYWRIGHT_BROWSERS_PATH` | Path to Playwright browser binaries |
| `PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS` | Skip host validation for Nix |
| `SOPS_AGE_KEY_FILE` | Path to age key for secrets tests |

### Test selection patterns

Run specific test categories:

```bash
# nix-unit tests only
nix build .#checks.aarch64-darwin.nix-unit

# Validation checks only
nix build .#checks.aarch64-darwin.naming-conventions
nix build .#checks.aarch64-darwin.terraform-validate

# Integration tests (Linux only)
nix build .#checks.x86_64-linux.vm-boot-all-machines
```

## See also

- [Justfile Recipes](/reference/justfile-recipes/) - All available test recipes
- [CI Jobs](/reference/ci-jobs/) - CI job to local command mapping
- [Test Harness Reference](/development/traceability/test-harness/) - CI-local parity matrix
- [ADR-0010: Testing Architecture](/development/architecture/adrs/0010-testing-architecture/) - Testing strategy decisions
