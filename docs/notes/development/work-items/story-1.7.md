# Story 1.7: Execute Dendritic Flake-Parts Refactoring in test-clan Using Test Harness

**Epic:** Epic 1 - Architectural Validation + Infrastructure Deployment (Phase 0 - test-clan)

**Status:** Drafted

**Dependencies:**
- Story 1.6 (complete): Test harness operational with all baseline tests passing

**Related Documents:**
- Assessment: docs/notes/development/dendritic-flake-parts-assessment.md (defines non-compliance gaps)
- Test strategy: docs/notes/development/dendritic-refactor-test-strategy.md (defines validation approach)
- Test harness: test-clan/tests/ (enables zero-regression validation)

---

## Story Description

Refactor test-clan from current pragmatic patterns to full dendritic flake-parts compliance, addressing specific non-compliance areas identified in the architectural assessment while maintaining zero regression through comprehensive test-driven validation.

**Non-Compliance Areas to Address** (from dendritic-flake-parts-assessment.md):

1. **Module Discovery:** Manual imports in clan.nix → Automatic import-tree discovery
2. **Base Module Exports:** Base modules NOT exported → Export to namespace
3. **Self-Composition:** Relative path imports → Namespace imports in host modules

**Validated Compliant Areas** (preserve unchanged):
- specialArgs pattern (`{ inherit inputs; }`) - dendritic-compatible, keep as-is
- Terraform/terranix integration - working correctly, preserve
- Clan inventory structure - operational, maintain

---

## Acceptance Criteria

### AC1: All Regression Tests Passing Throughout Refactoring
- [ ] RT-1: Terraform output byte-for-byte equivalent or semantically identical
- [ ] RT-2: NixOS configuration closures functionally equivalent
- [ ] RT-3: All 3 machine configurations build successfully
- [ ] Validated at each refactoring step (per test strategy Phase 2)

### AC2: All Invariant Tests Passing Throughout Refactoring
- [ ] IT-1: Clan inventory structure preserved (3 machines, 4 service instances, zerotier targeting)
- [ ] IT-2: Service targeting unchanged (hetzner-ccx23 controller, peers on all machines)
- [ ] IT-3: specialArgs propagation maintained (inputs accessible in host modules)
- [ ] clan-core integration contract preserved

### AC3: All Feature Tests Passing After Refactoring
- [ ] FT-1: import-tree discovery test passes (automatic module discovery works)
- [ ] FT-2: Namespace exports test passes (base + host modules exported)
- [ ] FT-3: Self-composition test passes (host modules use namespace imports)
- [ ] Dendritic compliance validated

### AC4: All Integration Tests Passing After Refactoring
- [ ] VT-1: All 3 machines boot successfully in VM tests
- [ ] Base module features validated (nix, users, sudo, SSH)
- [ ] Practical functionality confirmed

### AC5: Refactoring Steps Completed with Validation
- [ ] Step 2.1: import-tree added to flake.nix, tests passing
- [ ] Step 2.2: Base modules exported to namespace, tests passing
- [ ] Step 2.3: One host module refactored (hetzner-ccx23), tests passing
- [ ] Step 2.4: Remaining hosts refactored (hetzner-cx43, gcp-vm), tests passing
- [ ] Step 2.5: Automatic host collection assessed (implement or defer with rationale)

### AC6: Git Workflow and Rollback Safety
- [ ] Work performed on feature branch (feature/dendritic-refactoring)
- [ ] Per-step commits with descriptive messages
- [ ] Test validation documented at each step
- [ ] Merge to main only after ALL tests passing
- [ ] Rollback plan documented and available

---

## Implementation Tasks

### Task 1: Refactoring Step 2.1 - Add import-tree Discovery (1-2 hours)

**Change:**
```nix
# flake.nix: Replace manual imports with import-tree
outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
  (inputs.import-tree ./modules);
```

**Actions:**
1. Create feature branch: `git checkout -b feature/dendritic-refactoring`
2. Update flake.nix to use import-tree
3. Run tests: `nix flake check`
4. Validate: All regression and invariant tests MUST PASS
5. Check: Feature test FT-1 (import-tree-discovery) SHOULD NOW PASS
6. Commit: `git commit -m "refactor(step-2.1): add import-tree discovery"`

**Success Criteria:**
- flake-parts modules auto-discovered
- No functional changes to outputs
- Regression tests pass
- Invariant tests pass

**Rollback:** `git revert HEAD` if tests fail

---

### Task 2: Refactoring Step 2.2 - Export Base Modules to Namespace (1-2 hours)

**Change:**
Create `modules/base/default.nix`:
```nix
{
  flake.modules.nixos.base.nix-settings = ./nix-settings.nix;
  flake.modules.nixos.base.admins = ./admins.nix;
  flake.modules.nixos.base.initrd-networking = ./initrd-networking.nix;
}
```

**Actions:**
1. Create modules/base/default.nix with namespace exports
2. Verify import-tree discovers the new default.nix
3. Build test: `nix build .#flake.modules.nixos.base.nix-settings` (should work)
4. Run tests: All regression and invariant tests MUST PASS
5. Check: Feature test FT-2 (namespace-exports) SHOULD PARTIALLY PASS (base modules exported)
6. Commit: `git commit -m "refactor(step-2.2): export base modules to namespace"`

**Success Criteria:**
- Base modules accessible via config.flake.modules.nixos.base.*
- Existing host module imports still work (still using relative paths)
- No functional changes to configurations

**Rollback:** `git revert HEAD` if exports break module evaluation

---

### Task 3: Refactoring Step 2.3 - Refactor One Host Module (2-3 hours)

**Target:** hetzner-ccx23 (operational VM at 162.55.175.87)

**Change:**
Update `modules/hosts/hetzner-ccx23/default.nix`:
```nix
{ config, ... }:
{
  flake.modules.nixos."hosts/hetzner-ccx23" = { inputs, lib, ... }: {
    imports = with config.flake.modules.nixos.base; [
      nix-settings
      admins
      initrd-networking
      inputs.srvos.nixosModules.server
      inputs.srvos.nixosModules.hardware-hetzner-cloud
      ./disko.nix
    ];
    # ... rest of configuration unchanged ...
  };
}
```

**Actions:**
1. Refactor hetzner-ccx23 to use namespace imports
2. Build: `nix build .#nixosConfigurations.hetzner-ccx23.config.system.build.toplevel`
3. VM test: `nix build .#tests.integration.vm-boot-tests.tests.hetzner-ccx23`
4. Regression check: `nix build .#tests.regression.nixos-closure-equivalence.compare`
5. Verify: hetzner-ccx23 specific tests pass, other machines unchanged
6. Commit: `git commit -m "refactor(step-2.3): refactor hetzner-ccx23 to namespace imports"`

**Success Criteria:**
- hetzner-ccx23 builds successfully
- VM boot test passes
- NixOS closure equivalent to baseline
- Other machines (cx43, gcp-vm) unaffected

**Rollback:** `git revert HEAD` if hetzner-ccx23 doesn't build or VM test fails

**IMPORTANT:** Do NOT deploy to production VM (162.55.175.87) until ALL refactoring complete

---

### Task 4: Refactoring Step 2.4 - Refactor Remaining Hosts (2-3 hours)

**Targets:** hetzner-cx43, gcp-vm

**Change:**
Apply same namespace import pattern to remaining host modules.

**Actions:**
1. Refactor hetzner-cx43/default.nix (identical pattern to ccx23)
2. Build and test: `nix build .#nixosConfigurations.hetzner-cx43.config.system.build.toplevel`
3. VM test: `nix build .#tests.integration.vm-boot-tests.tests.hetzner-cx43`
4. Commit: `git commit -m "refactor(step-2.4a): refactor hetzner-cx43 to namespace imports"`
5. Refactor gcp-vm/default.nix
6. Build and test: `nix build .#nixosConfigurations.gcp-vm.config.system.build.toplevel`
7. VM test: `nix build .#tests.integration.vm-boot-tests.tests.gcp-vm`
8. Commit: `git commit -m "refactor(step-2.4b): refactor gcp-vm to namespace imports"`
9. Run full test suite: `./tests/run-all.sh all`

**Success Criteria:**
- All 3 machines build successfully
- All VM tests pass
- ALL regression tests pass
- ALL invariant tests pass
- Feature test FT-3 (self-composition) NOW PASSES

**Rollback:** `git revert HEAD` or `git revert HEAD~1` if specific host fails

---

### Task 5: Refactoring Step 2.5 - Assess Automatic Host Collection (1-2 hours)

**Objective:** Evaluate whether to implement automatic nixosConfigurations generation

**Assessment Criteria:**
1. Current clan.machines pattern works correctly (manual registration proven)
2. Automatic collection would replace manual imports in clan.nix:108-120
3. Risk: clan.machines integration complexity
4. Benefit: One less manual step when adding machines

**Decision Tree:**
- **IF** clan.machines can be automatically generated from namespace → Implement
- **ELSE IF** clan.machines requires manual registration → Skip, document rationale
- **REASON:** Clan inventory already provides operational-level machine management

**Actions:**
1. Research: Check if clan-core supports automatic machine collection from nixosConfigurations
2. Prototype: Create `modules/flake-parts/host-machines.nix` if feasible
3. Test: Validate clan inventory integration preserved
4. **Decision:** Implement OR defer with documented rationale
5. Commit: `git commit -m "refactor(step-2.5): [automatic host collection OR defer]"`

**Success Criteria (if implemented):**
- Automatic generation produces identical clan.machines
- Clan inventory integration preserved
- All tests pass

**Success Criteria (if deferred):**
- Rationale documented clearly
- Manual registration acknowledged as acceptable pattern
- Current approach validated as sufficient

---

### Task 6: Final Validation and Merge (1-2 hours)

**Actions:**
1. Run complete test suite: `./tests/run-all.sh all`
2. Manual validation:
   - `nix flake check`
   - Build all configurations
   - Compare terraform output to baseline
3. Git workflow:
   - Review all commits on feature branch
   - Ensure atomic commit messages
   - Merge to main: `git checkout main && git merge --no-ff feature/dendritic-refactoring`
4. Document refactoring results in story completion notes
5. Update sprint-status.yaml: Story 1.7 status → done

**Success Criteria:**
- ✅ ALL regression tests pass (existing functionality preserved)
- ✅ ALL invariant tests pass (clan-core integration intact)
- ✅ ALL feature tests pass (dendritic capabilities enabled)
- ✅ ALL integration tests pass (VMs boot and work)
- ✅ Terraform output equivalent
- ✅ No new errors in `nix flake check`
- ✅ Feature branch merged to main
- ✅ Story marked done

---

## Risk Mitigation

### Operational Safety for Deployed VMs

**CRITICAL:** test-clan repository refactoring does NOT affect deployed VMs until explicitly updated.

**Deployed VM Protection:**
- hetzner-ccx23 (162.55.175.87): Operational, do NOT deploy refactored config until validation complete
- hetzner-cx43 (49.13.140.183): Operational, do NOT deploy refactored config until validation complete

**Deployment Validation (After refactoring complete):**
1. All tests passing on feature branch
2. Terraform output validated as equivalent
3. VM tests confirm boot behavior identical
4. Manual review of configuration changes
5. User approval REQUIRED before deployment
6. Deployment plan: `clan machines update hetzner-ccx23` (optional, not required)

### Git Safety Protocol

```bash
# Before starting
git checkout main
git pull
git checkout -b feature/dendritic-refactoring

# After each step
git add .
git commit -m "refactor(step-X.Y): [description]"
./tests/run-all.sh all  # Validate

# If step fails
git revert HEAD       # Undo last commit
# OR
git reset --hard HEAD~1  # Discard last commit

# When complete
git checkout main
git merge --no-ff feature/dendritic-refactoring
```

### Rollback Plan

**Single Step Failure:**
- Identify failing test category (regression/invariant/feature/integration)
- Rollback: `git revert HEAD`
- Debug: Review test output, check configuration changes
- Fix: Address issue, commit fix, re-run tests

**Critical Failure (Invariant Tests):**
- Invariant test failure = clan-core integration broken
- **IMMEDIATE ROLLBACK:** `git reset --hard main`
- Review: Analyze what broke clan integration
- Consult: Check dendritic-flake-parts-assessment.md for guidance

**Full Refactor Rollback:**
- If refactoring fundamentally incompatible: `git reset --hard main`
- Alternative: Defer Story 1.7 to post-Epic 1
- Current architecture validated as sufficient by Story 1.2 assessment

---

## Technical Notes

### Non-Compliance Areas from Assessment

**Assessment Finding (dendritic-flake-parts-assessment.md):**

1. **Module Discovery (Line 30-46):** Manual imports in clan.nix:108-120
   - Current: O(N) scaling, manual registration
   - Target: Automatic import-tree discovery, O(1) complexity

2. **Base Module Exports (Line 92-114):** Base modules NOT exported to namespace
   - Current: Only terranix modules exported (clan.nix:7-9)
   - Target: All base modules accessible via config.flake.modules.nixos.base.*

3. **Self-Composition (Line 104-113):** Relative path imports in host modules
   - Current: `imports = [ ../../base/nix-settings.nix ]`
   - Target: `imports = with config.flake.modules.nixos.base; [ nix-settings ]`

### Validated Compliant Areas (Preserve)

**From Assessment (Line 186-296):**
- specialArgs pattern (`{ inherit inputs; }`) - Dendritic-compatible, validated by drupol-dendritic-infra
- Clan inventory structure - Operational, preserve unchanged
- Terraform integration - Working correctly, maintain

### Test Strategy Alignment

This story executes **Phase 2** of dendritic-refactor-test-strategy.md (Lines 1540-1679):
- Step 2.1: Add import-tree (Lines 1546-1569)
- Step 2.2: Export base modules (Lines 1574-1597)
- Step 2.3: Refactor one host (Lines 1602-1639)
- Step 2.4: Refactor remaining hosts (Lines 1644-1663)
- Step 2.5: Automatic host collection (Lines 1668-1679)

Each step validated with comprehensive test harness from Story 1.6.

---

## Definition of Done

- [ ] All refactoring steps (2.1-2.5) completed with test validation
- [ ] All regression tests passing (terraform, closures, builds)
- [ ] All invariant tests passing (inventory, targeting, specialArgs)
- [ ] All feature tests passing (import-tree, namespace, self-composition)
- [ ] All integration tests passing (VM boots, SSH, base modules)
- [ ] Terraform output validated as equivalent to baseline
- [ ] Git workflow complete (feature branch merged to main)
- [ ] Story completion notes document results and decisions
- [ ] Operational VMs protected (no accidental deployment)
- [ ] Zero regressions confirmed via comprehensive test suite
