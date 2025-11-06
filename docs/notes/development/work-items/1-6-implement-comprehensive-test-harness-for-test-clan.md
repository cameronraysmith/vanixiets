# Story 1.6: Implement Comprehensive Test Harness for test-clan Infrastructure Validation

**Epic:** Epic 1 - Architectural Validation + Infrastructure Deployment (Phase 0 - test-clan)

**Status:** Ready for Dev

**Dependencies:**
- Story 1.5 (complete): Operational VMs provide test targets

**Related Documents:**
- Test strategy: docs/notes/development/dendritic-refactor-test-strategy.md
- Assessment: docs/notes/development/dendritic-flake-parts-assessment.md

**Dev Agent Record:**
- Context Reference: docs/notes/development/work-items/1-6-implement-comprehensive-test-harness-for-test-clan.context.xml

---

## Story Description

Implement a comprehensive test suite for test-clan that enables confident refactoring of the codebase to full dendritic flake-parts compliance while guaranteeing zero regression in critical infrastructure functionality validated by Story 1.5 (2 operational Hetzner VMs).

This test harness is a **general-purpose test infrastructure** for test-clan, not specific to dendritic refactoring.
It provides ongoing value for validating any changes to the infrastructure codebase.

---

## Acceptance Criteria

### AC1: Test Infrastructure Setup
- [ ] nix-unit added to flake inputs
- [ ] Test directory structure created: `tests/{regression,invariant,feature,integration,snapshots}/`
- [ ] Test outputs exposed via `flake.nix` checks
- [ ] Test runner script operational: `./tests/run-all.sh`

### AC2: Regression Tests Implemented and Passing
- [ ] RT-1: Terraform output equivalence test implemented
- [ ] RT-2: NixOS configuration closure equivalence test implemented
- [ ] RT-3: Machine configurations build test implemented
- [ ] All regression tests pass with baseline snapshots captured

### AC3: Invariant Tests Implemented and Passing
- [ ] IT-1: Clan inventory structure test implemented
- [ ] IT-2: Clan service targeting test implemented
- [ ] IT-3: specialArgs propagation test implemented
- [ ] All invariant tests pass (validates clan-core integration)

### AC4: Feature Tests Implemented (Expected to Fail)
- [ ] FT-1: import-tree discovery test implemented
- [ ] FT-2: Namespace exports test implemented
- [ ] FT-3: Self-composition test implemented
- [ ] Feature tests fail as expected (confirms test correctness - dendritic features don't exist yet)

### AC5: Integration Tests Implemented and Passing
- [ ] VT-1: VM boot tests implemented for all 3 machines
- [ ] All VMs boot successfully with base module features validated
- [ ] SSH access confirmed on all test VMs

### AC6: Baseline Snapshots Captured
- [ ] Terraform baseline: `tests/snapshots/terraform.json`
- [ ] NixOS configs baseline: `tests/snapshots/nixos-configs.json`
- [ ] Clan inventory baseline: `tests/snapshots/clan-inventory.json`

---

## Implementation Tasks

### Task 1: Setup Test Infrastructure (1-2 hours)
1. Add nix-unit to flake.nix inputs
2. Create test directory structure
3. Create test runner script template
4. Add checks section to flake.nix perSystem

### Task 2: Implement Regression Tests (2-3 hours)
1. Implement RT-1: Terraform output equivalence
   - Normalize and compare terraform JSON outputs
   - Capture baseline snapshot
2. Implement RT-2: NixOS closure equivalence
   - Extract configuration properties (hostname, services, bootloader, users)
   - Compare before/after snapshots
3. Implement RT-3: Machine builds
   - Verify all 3 machines build successfully
   - Test toplevel derivation accessibility

### Task 3: Implement Invariant Tests (1-2 hours)
1. Implement IT-1: Clan inventory structure
   - Validate 3 machines present with correct tags
   - Validate service instances (emergency-access, users-root, zerotier, tor)
   - Verify zerotier controller/peer targeting
2. Implement IT-2: Service targeting preservation
   - Validate role assignments unchanged
   - Confirm hetzner-ccx23 is zerotier controller
3. Implement IT-3: specialArgs propagation
   - Verify inputs accessible in host modules
   - Confirm srvos importable

### Task 4: Implement Feature Tests (1 hour)
1. Implement FT-1: import-tree discovery
   - Check for automatic module discovery
   - Expected to fail before dendritic refactoring
2. Implement FT-2: Namespace exports
   - Verify modules exported to config.flake.modules
   - Expected to fail (only terranix currently exported)
3. Implement FT-3: Self-composition
   - Check host modules for namespace imports vs relative paths
   - Expected to fail (currently using relative imports)

### Task 5: Implement Integration Tests (1-2 hours)
1. Implement VT-1: VM boot tests
   - Create nixosTest for each machine
   - Validate boot to multi-user.target
   - Test base module features (nix, users, sudo, SSH)
   - Verify hostname and service enablement

### Task 6: Validation and Documentation (1 hour)
1. Run complete test suite baseline
2. Capture all snapshots
3. Verify test categories behave as expected:
   - Regression: PASS
   - Invariant: PASS
   - Feature: FAIL (expected)
   - Integration: PASS
4. Document test execution in story completion notes

---

## Technical Notes

### Critical Architecture Constraint: Flake-Parts Evaluation Model

**IMPORTANT:** This story's implementation was revised based on comprehensive technical research that identified why the phase-0-tests branch failed.

**Root Cause of Failure:** The phase-0-tests branch (commits f0aa5e9..f405a6a) attempted to import test modules in perSystem with access to complete flake outputs (`inputs.self`, `config.flake`).
This created circular dependencies because perSystem evaluation happens BEFORE flake outputs exist.

**Technical Research Reference:**
`docs/notes/development/research/flake-parts-nix-unit-test-integration.md`

This research document provides:
- Deep analysis of flake-parts perSystem evaluation model
- Root cause analysis of circular dependency failures
- THREE correct implementation patterns with working code examples
- Recommended hybrid approach for test-clan
- Specific implementation guidance

### Correct Implementation Patterns

**Pattern 1: nix-unit expr/expected (for simple property tests)**
```nix
perSystem = {
  nix-unit.tests."test-name" = {
    expr = "flake.terranix.x86_64-linux.google_compute_instance";  # String expression
    expected = "{ /* ... */ }";
  };
};
```
- Test DATA defined in perSystem as strings
- Test EXECUTION happens in check derivation with complete flake access
- No circular dependency because expressions are not evaluated until nix-unit binary runs

**Pattern 2: withSystem at flake level (for complex derivation tests)**
```nix
top@{ withSystem, config, lib, ... }:
{
  perSystem = { /* normal perSystem */ };

  flake.checks = lib.genAttrs config.systems (system:
    withSystem system ({ pkgs, ... }: {
      vm-boot = pkgs.testers.runNixOSTest {
        nodes.machine = { imports = [ top.config.flake.nixosModules.default ]; };
        testScript = ''machine.wait_for_unit("multi-user.target")'';
      };
    })
  );
}
```
- Tests defined at flake level, NOT in perSystem
- Access both perSystem context (pkgs) AND complete flake outputs (via top.config.flake)
- No circular dependency because tests run after flake outputs assembled

**Hybrid Approach (RECOMMENDED for test-clan):**
- Simple property tests (RT-1, IT-1, IT-2, IT-3, FT-1, FT-2) → nix-unit
- Build validation tests (RT-2, RT-3) → withSystem + runCommand
- VM integration tests (VT-1) → withSystem + runNixOSTest

### Test File Organization

```
tests/
├── nix-unit/                # Simple property tests (nix-unit expr/expected)
│   ├── regression.nix       # RT-1: Terraform output equivalence
│   ├── invariant.nix        # IT-1, IT-2, IT-3: Clan structure tests
│   └── feature.nix          # FT-1, FT-2: Dendritic features
└── integration/             # Complex derivation-based tests (withSystem)
    ├── machine-builds.nix   # RT-2, RT-3: Build validation
    └── vm-boot.nix          # VT-1: VM boot tests
```

### Test Categories

**Category 1: Regression Tests (MUST REMAIN PASSING)**
- Validate existing functionality that cannot break during refactoring
- Should pass before AND after any code changes
- If regression test fails → refactoring broke required functionality

**Category 2: Feature Tests (EXPECTED TO FAIL → PASS)**
- Validate new capabilities that don't exist yet
- Will fail before refactoring, must pass after refactoring
- Define what "successful implementation" means

**Category 3: Invariant Tests (ARCHITECTURAL CONSTRAINTS)**
- Validate requirements that must never change
- Enforce contracts (e.g., clan-core integration)
- Must always pass regardless of internal changes

**Category 4: Integration Tests (END-TO-END VALIDATION)**
- Prove configurations work in practice, not just evaluation
- VM tests validate actual runtime behavior

### Reusability

This test harness is **not specific to dendritic refactoring**.
It provides ongoing value for:
- Validating infrastructure changes
- Preventing regressions in future stories
- Documenting expected behavior
- Enabling confident experimentation

### References

[Research: Flake-Parts Nix-Unit Test Integration](../research/flake-parts-nix-unit-test-integration.md) - Comprehensive technical analysis of correct test implementation patterns for flake-parts repositories

---

## Definition of Done

- [ ] All test infrastructure implemented and functional
- [ ] All regression tests passing with baselines captured
- [ ] All invariant tests passing (clan-core integration preserved)
- [ ] All feature tests implemented and failing as expected
- [ ] All integration tests passing (VMs boot and work)
- [ ] Test runner script operational
- [ ] Test execution documented in story notes
- [ ] Committed to test-clan repository on feature branch
