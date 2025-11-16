# Story 1.10DB: Execute Overlay Architecture Migration from infra to test-clan

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** drafted

**Dependencies:**
- Story 1.10D (done): pkgs-by-name pattern validated (Layer 3 foundation)
- Story 1.10DA (review): Documentation foundation established (theoretical overlay guidance)
- Party Mode Ultrathink Decision (2025-11-16): All 9 agents unanimous - Story 1.10DA provided theoretical documentation without actual migration

**Blocks:**
- Story 1.12 (backlog): GO/NO-GO decision requires 95% Epic 1 coverage with empirical validation
- Epic 2-6 migration: Teams need validated overlay migration patterns (not just documentation)

**Strategic Value:** Achieves 95% Epic 1 architectural coverage with EMPIRICAL validation (not just documentation), completes infra's 5-layer overlay architecture migration (Layers 1,2,4,5 + Layer 3 from Story 1.10D), proves hybrid pattern works (overlays + pkgs-by-name coexistence), provides Epic 2-6 teams with battle-tested migration guide based on real implementation (not theoretical), removes architectural uncertainty (all 5 layers validated in production environment), de-risks Epic 2-6 timeline (no overlay troubleshooting emergency fixes needed), updates Section 13.2 with empirical evidence matching Section 13.1 quality (production-ready tutorial).

**Effort:** 2-3 hours
**Risk Level:** Low (infra overlays already working, validating refactored implementation, drupol proves hybrid pattern viable)

---

## Story Description

As a system administrator,
I want to migrate infra's overlay layers (1,2,4,5) to test-clan dendritic flake-parts structure and validate empirically,
So that Epic 1 achieves 95% architectural coverage with REAL implementation evidence (not just documentation).

**Context:**

Story 1.10DA (completed 2025-11-16) documented HOW to preserve overlay architecture (Layers 1,2,4,5) when integrating with pkgs-by-name pattern, but only provided theoretical guidance without actual migration and validation.

Party Mode team ultrathink (2025-11-16, 9 agents unanimous) identified critical gap:
- **Story 1.10D**: EMPIRICAL validation (ccstatusline migrated, builds verified, Section 13.1 based on real code) ✅
- **Story 1.10DA**: THEORETICAL documentation (overlay patterns explained, NO actual migration) ❌

**Epic 1 Core Principle Violation:** "Architectural Validation via Pattern Rehearsal" requires DOING IT FOR REAL, not just documenting how to do it.

**Story 1.10DB Mission:** Execute actual overlay migration from infra to test-clan, validate all 5 layers work, prove hybrid pattern (overlays + pkgs-by-name) coexists, update Section 13.2 with empirical evidence.

**Comparison to Related Stories:**

**Story 1.10D (COMPLETE):** EMPIRICAL validation
- Migrated ccstatusline to pkgs-by-name pattern (Layer 3)
- Build validation with concrete evidence
- Section 13.1 tutorial based on real code (467 lines)
- Quality: 9.5/10 clarity, APPROVE
- Dev time: ~2h 55min (within 2-3h estimate)

**Story 1.10DA (DOCUMENTATION ONLY):** THEORETICAL guidance
- Documented HOW to preserve overlays (Layers 1,2,4,5)
- No actual migration performed
- Section 13.2 theoretical (not based on real implementation)
- Gap: Epic 1 needs empirical validation, not just theory

**Story 1.10DB (THIS STORY):** EMPIRICAL validation like 1.10D
- Migrate overlays (Layers 1,2,4,5) to dendritic structure
- Validate all 5 layers coexist with pkgs-by-name (Layer 3)
- Update Section 13.2 with empirical evidence
- Target quality: Match Story 1.10D rigor (9.5/10 clarity)
- Target time: 2-3h (similar complexity to Story 1.10D)

**infra's 5-Layer Overlay Architecture (Migration Source):**

1. **Layer 1 (inputs):** Multi-channel nixpkgs access (stable, patched, unstable)
   - Source: `infra/overlays/inputs.nix` (58 lines)
   - Target: `test-clan/modules/flake-parts/overlays/inputs.nix`
   - Pattern: Dendritic overlay export via modules/flake-parts/nixpkgs.nix
   - Validation: `pkgs.stable.*` and `pkgs.unstable.*` accessible in builds

2. **Layer 2 (hotfixes):** Platform-specific stable fallbacks
   - Source: `infra/overlays/infra/hotfixes.nix` (51 lines)
   - Target: `test-clan/modules/flake-parts/overlays/hotfixes.nix`
   - Pattern: Platform-conditional stable package selection
   - Validation: Verify specific packages use stable versions on target platforms

3. **Layer 3 (packages):** Custom derivations [COMPLETE - Story 1.10D]
   - Migration: `infra/overlays/packages/` → `test-clan/pkgs/by-name/`
   - Status: ✅ VALIDATED (ccstatusline proof-of-concept, Section 13.1 complete)
   - Evidence: Story 1.10D Dev Agent Record (all 9 ACs satisfied, 4 gates PASS)

4. **Layer 4 (overrides):** Per-package build modifications
   - Source: `infra/overlays/overrides/default.nix` (37 lines auto-import infrastructure)
   - Target: `test-clan/modules/flake-parts/overlays/overrides.nix`
   - Pattern: Package-specific overrideAttrs customizations
   - Validation: Verify overridden packages build with modifications applied

5. **Layer 5 (flakeInputs):** Overlays from flake inputs
   - Source: `infra/flake.nix` inputs (nuenv, jujutsu, etc.)
   - Target: `test-clan/modules/flake-parts/nixpkgs.nix` overlay composition
   - Pattern: flake.inputs.*.overlays.default integration
   - Validation: Packages from input overlays accessible in pkgs

**Blocks Story 1.12:** GO/NO-GO decision for Epic 2-6 migration requires 95% Epic 1 coverage with empirical validation, not just documentation.

---

## Implementation Notes

### infra's 5-Layer Overlay Architecture

**Architecture Source:** `~/projects/nix-workspace/infra/overlays/default.nix` (lines 1-77)

infra's overlay system consists of 5 orthogonal layers merged in specific order:

```nix
# overlays/default.nix merge order (lines 71-77)
lib.mergeAttrsList [
  inputs'    # Layer 1: Multi-channel nixpkgs access
  hotfixes   # Layer 2: Platform-specific stable fallbacks
  packages   # Layer 3: Custom derivations [Story 1.10D migrated to pkgs-by-name]
  overrides  # Layer 4: Per-package build modifications
  flakeInputs # Layer 5: Overlays from flake inputs (nuenv, etc.)
]
```

**Layer Dependencies:**
- **Order matters:** Later layers can reference earlier layers
- **Layer 1 (inputs)** provides `stable`, `unstable`, `patched` namespaces
- **Layer 2 (hotfixes)** uses `final.stable.*` from Layer 1
- **Layer 3 (packages)** standalone (migrated to pkgs-by-name in Story 1.10D)
- **Layer 4 (overrides)** can reference all prior layers
- **Layer 5 (flakeInputs)** external overlays (nuenv, nvim-treesitter from LazyVim)

**Why 5 Layers:**
- **Separation of concerns:** Each layer has distinct purpose
- **Merge order control:** Explicit ordering prevents conflicts
- **Selective updates:** Change one layer without affecting others
- **Platform-specific handling:** Layer 2 hotfixes platform-conditional
- **External integration:** Layer 5 integrates third-party overlays cleanly

### drupol Hybrid Pattern Implementation

**Pattern Source:** `~/projects/nix-workspace/drupol-dendritic-infra/modules/flake-parts/nixpkgs.nix` (lines 19-37)

Pattern proves overlays array + pkgsDirectory coexist in same perSystem:

```nix
# drupol-dendritic-infra/modules/flake-parts/nixpkgs.nix
perSystem = { system, ... }: {
  _module.args.pkgs = import inputs.nixpkgs {
    inherit system;
    config = { allowUnfreePredicate = _pkg: true; };
    overlays = [
      # Traditional overlays array (Layers 1,2,4,5 in infra)
      (final: _prev: {
        master = import inputs.nixpkgs-master {
          inherit (final) config;
          inherit system;
        };
      })
      (final: _prev: {
        unstable = import inputs.nixpkgs-unstable {
          inherit (final) config;
          inherit system;
        };
      })
      inputs.nix-webapps.overlays.lib
    ];
  };
  # Custom packages via pkgs-by-name (Layer 3 in infra)
  pkgsDirectory = ../../pkgs/by-name;
};
```

**Key Insights:**
- **Both configured in same perSystem block**
- **overlays array** handles Layers 1,2,4,5 (traditional overlay functions)
- **pkgsDirectory** handles Layer 3 (custom packages via auto-discovery)
- **No conflicts** between overlay merging and auto-discovery
- **Clean separation** of concerns (overlays for modifications, pkgsDirectory for custom packages)

### Dendritic Flake-Parts Adaptation

**Target Architecture:** test-clan dendritic structure

**Current State (infra):**
- Overlays defined in `overlays/*.nix` files
- Applied via `nixpkgs.overlays` in flake.nix
- Single overlay composition file (`overlays/default.nix`)

**Target State (dendritic + clan):**
- Overlays defined in `modules/flake-parts/overlays/*.nix` files
- Applied via `_module.args.pkgs = import inputs.nixpkgs { overlays = [ ... ]; }` in `modules/flake-parts/nixpkgs.nix`
- Dendritic pattern: Separate files per layer, imported into overlays array

**Migration Pattern:**

1. **Layer 1 (inputs.nix):**
   ```nix
   # FROM: overlays/inputs.nix (overlay module with overlayArgs)
   { flake, ... }:
   final: prev:
   { stable = ...; unstable = ...; patched = ...; }

   # TO: modules/flake-parts/overlays/inputs.nix (direct overlay function)
   final: prev:
   { stable = ...; unstable = ...; patched = ...; }
   ```
   - Remove `{ flake, ... }:` wrapper (access inputs directly in nixpkgs.nix)
   - Keep overlay function signature `final: prev:`
   - Adapt flake.inputs references

2. **Layer 2 (hotfixes.nix):**
   ```nix
   # FROM: overlays/infra/hotfixes.nix (direct overlay)
   final: prev:
   { inherit (final.stable) micromamba; }

   # TO: modules/flake-parts/overlays/hotfixes.nix (unchanged)
   final: prev:
   { inherit (final.stable) micromamba; }
   ```
   - No changes needed (already pure overlay function)
   - Copy directly to dendritic location

3. **Layer 4 (overrides.nix):**
   ```nix
   # FROM: overlays/overrides/default.nix (auto-import infrastructure)
   { flake, ... }:
   final: prev:
   let
     # Auto-import all *.nix files
     ...
   in importedOverlays

   # TO: modules/flake-parts/overlays/overrides.nix (simplified)
   final: prev:
   {
     # Manual import of specific overrides (if any exist in infra)
     # infra has auto-import infrastructure but no actual override files yet
   }
   ```
   - Simplify auto-import infrastructure (infra has framework but no overrides)
   - Create placeholder for future overrides

4. **Layer 5 (flakeInputs):**
   ```nix
   # FROM: overlays/default.nix flakeInputs section (lines 45-65)
   flakeInputs = {
     nuenv = (inputs.nuenv.overlays.nuenv self super).nuenv;
   };

   # TO: modules/flake-parts/nixpkgs.nix overlays array
   overlays = [
     inputs.nuenv.overlays.nuenv
     # Other input overlays
   ];
   ```
   - Extract from merged overlay composition
   - Add directly to overlays array in nixpkgs.nix

**Integration in nixpkgs.nix:**

```nix
# modules/flake-parts/nixpkgs.nix
{ inputs, ... }:
{
  imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];

  perSystem = { system, ... }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config = { allowUnfree = true; };
      overlays = [
        # Layer 1: Multi-channel access
        (import ./overlays/inputs.nix inputs)
        # Layer 2: Platform hotfixes
        (import ./overlays/hotfixes.nix)
        # Layer 4: Package overrides
        (import ./overlays/overrides.nix)
        # Layer 5: Flake input overlays
        inputs.nuenv.overlays.nuenv
      ];
    };
    # Layer 3: Custom packages (Story 1.10D)
    pkgsDirectory = ../pkgs/by-name;
  };
}
```

**Critical Constraint:** Layers 1,2,4,5 must be migrated and validated TOGETHER with Layer 3 (Story 1.10D) to prove hybrid pattern works.

### Migration Steps Overview

**Phase 1: Directory Structure Setup (10 min)**
1. Create `modules/flake-parts/overlays/` directory
2. Create placeholder files (inputs.nix, hotfixes.nix, overrides.nix)

**Phase 2: Layer Migration (60 min)**
1. **Layer 1 (inputs):** Adapt overlayArgs pattern for dendritic (20 min)
2. **Layer 2 (hotfixes):** Direct copy with validation (10 min)
3. **Layer 4 (overrides):** Simplify auto-import infrastructure (10 min)
4. **Layer 5 (flakeInputs):** Extract nuenv overlay (10 min)
5. Integration in nixpkgs.nix overlays array (10 min)

**Phase 3: Validation (50 min)**
1. Build validation (all 4 builds with all 5 layers active) (20 min)
2. Package inspection (verify all layers present in merged pkgs) (15 min)
3. Regression testing (ensure Story 1.10D ccstatusline still works) (15 min)

**Phase 4: Documentation (30 min)**
1. Update Section 13.2 with empirical evidence (20 min)
2. Document lessons learned from migration (10 min)

**Total Estimated Effort:** 2.5 hours (150 min)

---

## Acceptance Criteria

### AC-A: Migrate Layer 1 (Multi-Channel Access)

**Target:** Migrate `infra/overlays/inputs.nix` to dendritic structure

**Implementation:**

1. Create `test-clan/modules/flake-parts/overlays/inputs.nix`:
   ```nix
   # Multi-channel nixpkgs access overlay
   # Adapted from infra/overlays/inputs.nix for dendritic pattern
   inputs:
   final: prev:
   let
     # Note: inputs parameter passed from nixpkgs.nix import
     lib' = inputs.self.lib;
     os = lib'.systemOs prev.stdenv.hostPlatform.system;

     nixpkgsConfig = {
       system = prev.stdenv.hostPlatform.system;
       config = { allowUnfree = true; };
     };
   in
   {
     inherit inputs;
     nixpkgs = import inputs.nixpkgs nixpkgsConfig;
     patched = import (prev.applyPatches {
       name = "nixpkgs-patched";
       src = inputs.nixpkgs.outPath;
       patches = [];  # Empty in test-clan (infra uses infra/patches.nix)
     }) nixpkgsConfig;
     stable = import (lib'.systemInput {
       inherit os;
       name = "nixpkgs";
       channel = "stable";
     }) nixpkgsConfig;
     unstable = import inputs.nixpkgs nixpkgsConfig;
   }
   ```

2. Import in `modules/flake-parts/nixpkgs.nix`:
   ```nix
   overlays = [
     (import ./overlays/inputs.nix inputs)
     # ... other layers
   ];
   ```

3. Validate multi-channel access:
   ```bash
   # Verify stable channel accessible
   nix eval .#darwinConfigurations.blackphos.pkgs.stable.ripgrep.version
   # Expected: stable version (e.g., "14.1.0")

   # Verify unstable channel accessible
   nix eval .#darwinConfigurations.blackphos.pkgs.unstable.ripgrep.version
   # Expected: unstable version (e.g., "14.1.1" or newer)

   # Verify channels are different
   nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version
   nix eval .#darwinConfigurations.blackphos.pkgs.unstable.hello.version
   ```

4. Document Layer 1 in Section 13.2:
   - Pattern overview (multi-channel access architecture)
   - Code example from migrated overlay
   - Build validation commands and outputs
   - Use cases (when to use stable vs unstable)

**Pass Criteria:**
- File `modules/flake-parts/overlays/inputs.nix` exists
- Imported in nixpkgs.nix overlays array
- `pkgs.stable.*` accessible in all configurations
- `pkgs.unstable.*` accessible in all configurations
- Channels provide different package versions
- Section 13.2 Layer 1 documented with validation evidence

**Estimated effort:** 30 min

---

### AC-B: Migrate Layer 2 (Hotfixes)

**Target:** Migrate `infra/overlays/infra/hotfixes.nix` to dendritic structure

**Implementation:**

1. Copy `test-clan/modules/flake-parts/overlays/hotfixes.nix`:
   ```nix
   # Platform-specific hotfixes for broken unstable packages
   # Adapted from infra/overlays/infra/hotfixes.nix
   final: prev:
   {
     # Cross-platform hotfixes (all systems)
     inherit (final.stable)
       # micromamba: fmt library compatibility issue
       # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.aarch64-darwin
       # Breaks in unstable, stable version works
       micromamba
       ;
   }
   // (prev.lib.optionalAttrs prev.stdenv.isDarwin {
     # Darwin-wide hotfixes (both aarch64 and x86_64)
   })
   // (prev.lib.optionalAttrs prev.stdenv.isLinux {
     # Linux-wide hotfixes
   })
   ```

2. Import in `modules/flake-parts/nixpkgs.nix`:
   ```nix
   overlays = [
     (import ./overlays/inputs.nix inputs)
     (import ./overlays/hotfixes.nix)  # Uses final.stable from Layer 1
     # ... other layers
   ];
   ```

3. Validate platform-specific fallbacks:
   ```bash
   # Verify micromamba uses stable version
   nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version
   # Expected: stable version (e.g., "1.5.10")

   # Compare to unstable version (should be different)
   nix eval .#darwinConfigurations.blackphos.pkgs.unstable.micromamba.version
   # Expected: unstable version (may be broken or different)

   # Verify micromamba builds successfully
   nix build .#darwinConfigurations.blackphos.pkgs.micromamba
   ```

4. Document Layer 2 in Section 13.2:
   - Pattern overview (platform-specific hotfixes strategy)
   - Code example (micromamba hotfix)
   - Validation commands
   - When to use hotfixes vs flake.lock rollback

**Pass Criteria:**
- File `modules/flake-parts/overlays/hotfixes.nix` exists
- Imported in nixpkgs.nix overlays array (after Layer 1)
- micromamba uses stable version (verify version number)
- Hotfix successfully overrides unstable package
- Section 13.2 Layer 2 documented with validation evidence

**Estimated effort:** 30 min

---

### AC-C: Migrate Layer 4 (Overrides)

**Target:** Migrate `infra/overlays/overrides/default.nix` infrastructure to dendritic structure

**Implementation:**

1. Create `test-clan/modules/flake-parts/overlays/overrides.nix`:
   ```nix
   # Per-package build modifications
   # Adapted from infra/overlays/overrides/default.nix
   final: prev:
   {
     # Package-specific overrideAttrs customizations
     # infra has auto-import infrastructure but no actual overrides yet
     # This is a placeholder for future package build modifications

     # Example override (if needed):
     # somePackage = prev.somePackage.overrideAttrs (oldAttrs: {
     #   doCheck = false;  # Disable tests
     # });
   }
   ```

2. Import in `modules/flake-parts/nixpkgs.nix`:
   ```nix
   overlays = [
     (import ./overlays/inputs.nix inputs)
     (import ./overlays/hotfixes.nix)
     (import ./overlays/overrides.nix)  # After hotfixes
     # ... other layers
   ];
   ```

3. Validate overlay infrastructure:
   ```bash
   # Verify nixpkgs.nix evaluates with overrides overlay
   nix eval .#darwinConfigurations.blackphos.config.nixpkgs.overlays
   # Expected: Array includes overrides overlay function

   # Verify builds complete successfully
   nix build .#darwinConfigurations.blackphos.system
   ```

4. Document Layer 4 in Section 13.2:
   - Pattern overview (when to use overrides vs hotfixes)
   - Infrastructure explanation (auto-import pattern from infra)
   - Example override (hypothetical or real if added)
   - Use cases (test disabling, patch application, build flags)

**Pass Criteria:**
- File `modules/flake-parts/overlays/overrides.nix` exists
- Imported in nixpkgs.nix overlays array (after Layer 2)
- Overlay infrastructure evaluates successfully
- All builds pass with overrides overlay active
- Section 13.2 Layer 4 documented with pattern explanation

**Estimated effort:** 30 min

---

### AC-D: Configure Layer 5 (Flake Input Overlays)

**Target:** Integrate flake input overlays into dendritic nixpkgs.nix

**Implementation:**

1. Add nuenv flake input to `test-clan/flake.nix`:
   ```nix
   inputs.nuenv.url = "github:DeterminateSystems/nuenv";
   ```

2. Import nuenv overlay in `modules/flake-parts/nixpkgs.nix`:
   ```nix
   overlays = [
     (import ./overlays/inputs.nix inputs)
     (import ./overlays/hotfixes.nix)
     (import ./overlays/overrides.nix)
     inputs.nuenv.overlays.nuenv  # Layer 5: flake input overlays
   ];
   ```

3. Validate nuenv accessible:
   ```bash
   # Verify nuenv package available
   nix eval .#darwinConfigurations.blackphos.pkgs.nuenv
   # Expected: derivation object

   # Check nuenv version
   nix eval .#darwinConfigurations.blackphos.pkgs.nuenv.version
   # Expected: version string (e.g., "0.3.1")

   # Verify nuenv.mkScript available (main API)
   nix eval .#darwinConfigurations.blackphos.pkgs.nuenv.mkScript
   # Expected: function
   ```

4. Document Layer 5 in Section 13.2:
   - Pattern overview (flake input overlay integration)
   - Code example (nuenv overlay from inputs.nuenv.overlays.nuenv)
   - Validation commands
   - Use cases (when to use input overlays vs custom overlays)

**Pass Criteria:**
- nuenv flake input added to flake.nix
- nuenv overlay imported in nixpkgs.nix overlays array (after Layer 4)
- `pkgs.nuenv` accessible in all configurations
- nuenv.mkScript function available
- Section 13.2 Layer 5 documented with validation evidence

**Estimated effort:** 30 min

---

### AC-E: Validate Hybrid Pattern (All 5 Layers Coexist)

**Target:** Prove all 5 overlay layers work together with pkgs-by-name (Story 1.10D Layer 3)

**Implementation:**

1. Build all configurations with all 5 layers active:
   ```bash
   # Darwin configuration (blackphos)
   nix build .#darwinConfigurations.blackphos.system

   # NixOS configuration (cinnabar)
   nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

   # Home-manager configurations
   nix build .#homeConfigurations.crs58.activationPackage
   nix build .#homeConfigurations.raquel.activationPackage
   ```

2. Inspect merged pkgs to verify all layers present:
   ```bash
   # Layer 1: Multi-channel access
   nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version
   nix eval .#darwinConfigurations.blackphos.pkgs.unstable.hello.version
   # Expected: Different versions (stable vs unstable)

   # Layer 2: Hotfixes
   nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version
   # Expected: Stable version (hotfix applied)

   # Layer 3: Custom packages (Story 1.10D)
   nix build .#ccstatusline
   nix eval .#darwinConfigurations.blackphos.pkgs.ccstatusline.version
   # Expected: ccstatusline package from pkgs-by-name

   # Layer 4: Overrides (infrastructure present, no active overrides)
   # Verified by successful builds (no evaluation errors)

   # Layer 5: Flake input overlays
   nix eval .#darwinConfigurations.blackphos.pkgs.nuenv.version
   # Expected: nuenv package from input overlay
   ```

3. Validate zero regressions from Story 1.10D:
   ```bash
   # Verify ccstatusline still builds
   nix build .#ccstatusline

   # Verify home-module-exports check passes
   nix build .#checks.aarch64-darwin.home-module-exports

   # Verify home-configurations-exposed check passes
   nix build .#checks.aarch64-darwin.home-configurations-exposed
   ```

4. Document hybrid pattern validation in Section 13.2:
   - Architecture diagram (all 5 layers + pkgs-by-name)
   - Build validation commands for each layer
   - Package inspection outputs showing all layers
   - Zero regression confirmation (Story 1.10D still works)

**Pass Criteria:**
- All 4 builds pass (blackphos, cinnabar, crs58, raquel)
- Layer 1: `pkgs.stable.*` and `pkgs.unstable.*` accessible
- Layer 2: Hotfixes applied (micromamba uses stable)
- Layer 3: Custom packages from pkgs-by-name (ccstatusline)
- Layer 4: Overrides infrastructure active (no evaluation errors)
- Layer 5: Input overlay packages accessible (nuenv)
- Zero regressions from Story 1.10D (all checks still pass)
- Section 13.2 hybrid pattern documented with empirical evidence

**Estimated effort:** 30 min

---

### AC-F: Update Section 13.2 with Empirical Evidence

**Target:** Replace theoretical documentation with empirical implementation evidence matching Section 13.1 quality

**Implementation:**

1. Update `test-clan/docs/architecture/test-clan-validated-architecture.md` Section 13.2:
   ```markdown
   ## 13.2 Overlay Architecture Preservation with Dendritic Pattern

   ### Pattern Overview

   **Architecture:** 5-layer overlay system integrated with pkgs-by-name-for-flake-parts

   **Layer Structure:**
   1. **Layer 1 (inputs):** Multi-channel nixpkgs access (stable, patched, unstable)
   2. **Layer 2 (hotfixes):** Platform-specific stable fallbacks
   3. **Layer 3 (packages):** Custom derivations via pkgs-by-name [Story 1.10D]
   4. **Layer 4 (overrides):** Per-package build modifications
   5. **Layer 5 (flakeInputs):** Overlays from flake inputs (nuenv, etc.)

   **Hybrid Pattern:** overlays array + pkgsDirectory coexist in same perSystem

   **Integration Steps:**
   1. Create modules/flake-parts/overlays/ directory with layer files
   2. Import each layer in modules/flake-parts/nixpkgs.nix overlays array
   3. Configure pkgsDirectory for custom packages (Layer 3)
   4. Validate all 5 layers accessible in merged pkgs

   ### Complete Example: 5-Layer Architecture

   **1. Layer 1 - Multi-Channel Access (modules/flake-parts/overlays/inputs.nix):**
   [Include full code from migrated overlay with inline comments]

   **2. Layer 2 - Platform Hotfixes (modules/flake-parts/overlays/hotfixes.nix):**
   [Include full code with micromamba example]

   **3. Layer 3 - Custom Packages (pkgs-by-name/):**
   [Reference Section 13.1, Story 1.10D validation]

   **4. Layer 4 - Package Overrides (modules/flake-parts/overlays/overrides.nix):**
   [Include infrastructure code and example usage]

   **5. Layer 5 - Flake Input Overlays (modules/flake-parts/nixpkgs.nix):**
   [Include nuenv overlay integration example]

   **Integration in nixpkgs.nix:**
   [Include complete nixpkgs.nix showing all layers + pkgsDirectory]

   ### Build Validation

   **All 5 Layers Build Commands:**
   ```bash
   # Build all configurations
   nix build .#darwinConfigurations.blackphos.system
   nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel
   nix build .#homeConfigurations.crs58.activationPackage
   nix build .#homeConfigurations.raquel.activationPackage
   ```

   **Package Inspection Commands:**
   [Include validation commands from AC-E with expected outputs]

   ### infra Migration Guide

   **Current State (infra):**
   - Location: overlays/
   - Composition: overlays/default.nix merges 5 layers
   - Architecture: 5-layer overlay system

   **Migration Path:**
   [Include table with all 5 layers, source/target paths, effort estimates]

   **Migration Steps:**
   1. Create modules/flake-parts/overlays/ directory
   2. Migrate Layer 1 (inputs.nix) - adapt overlayArgs pattern
   3. Migrate Layer 2 (hotfixes.nix) - direct copy
   4. Migrate Layer 3 (packages/) - pkgs-by-name pattern [Story 1.10D]
   5. Migrate Layer 4 (overrides/) - simplify auto-import
   6. Configure Layer 5 (flakeInputs) - add to overlays array
   7. Test builds and package inspection
   8. Remove old overlays/ configuration

   **Estimated Total Effort:** 4-5 hours (Layers 1,2,4,5: 2.5h + Layer 3: 2h)

   **Risk Assessment:** LOW (layers independently testable, drupol proves hybrid pattern)

   ### Lessons Learned from Migration

   [Document real challenges encountered during Story 1.10DB implementation]
   - overlayArgs pattern adaptation
   - inputs parameter threading
   - Layer merge order dependencies
   - Platform-specific conditional issues
   - Regression testing approaches

   ### References

   - **drupol-dendritic-infra:** ~/projects/nix-workspace/drupol-dendritic-infra/modules/flake-parts/nixpkgs.nix (hybrid pattern proof)
   - **infra overlays:** ~/projects/nix-workspace/infra/overlays/ (5-layer architecture source)
   - **Story 1.10D:** Layer 3 validation (pkgs-by-name pattern)
   - **Story 1.10DA:** Theoretical foundation (documentation)
   ```

2. Ensure Section 13.2 matches Section 13.1 quality:
   - Empirical examples (real code from migration)
   - Build validation commands with outputs
   - Package inspection evidence
   - Troubleshooting guidance based on real issues
   - Comprehensive tutorial (self-contained, production-ready)

3. Cross-reference with Section 13.1:
   - Consistent structure (Pattern Overview, Examples, Migration Guide, References)
   - Complementary content (13.1 = Layer 3, 13.2 = Layers 1,2,4,5)
   - Combined completeness (100% overlay architecture coverage)

4. Provide Epic 2-6 teams with validated migration guide:
   - All 5 layers documented with real code
   - Build validation proven (4 configurations pass)
   - Package inspection verified (all layers accessible)
   - Lessons learned from actual migration (not theoretical)

**Pass Criteria:**
- Section 13.2 exists in test-clan-validated-architecture.md
- Contains all 5 layer implementations with real code
- Includes build validation commands and outputs
- Documents hybrid pattern integration (overlays + pkgsDirectory)
- Matches Section 13.1 quality (empirical, production-ready)
- Provides Epic 2-6 migration guide with effort estimates
- References infra source files and drupol hybrid pattern

**Estimated effort:** 30 min

---

**Total Acceptance Criteria Effort:** 2.5 hours
- AC-A: 30 min (Layer 1 migration + validation)
- AC-B: 30 min (Layer 2 migration + validation)
- AC-C: 30 min (Layer 4 migration + validation)
- AC-D: 30 min (Layer 5 configuration + validation)
- AC-E: 30 min (hybrid pattern validation + regression testing)
- AC-F: 30 min (Section 13.2 empirical documentation)

**Sum:** 3h 0min (aligns with story estimate of 2-3 hours with possible 30min variance)

---

## Tasks / Subtasks

### Task Group 1: Migrate Overlay Layers (AC-A, AC-B, AC-C)

**Objective:** Migrate Layers 1, 2, 4 from infra to test-clan dendritic structure

**Estimated Time:** 90 minutes

**Subtasks:**

- [ ] 1.1: Create overlay directory structure (AC-A.1)
  - Execute: `mkdir -p ~/projects/nix-workspace/test-clan/modules/flake-parts/overlays`
  - Verify structure matches dendritic pattern (flake-parts/overlays/)
  - Confirm directory accessible from modules/flake-parts/nixpkgs.nix

- [ ] 1.2: Migrate Layer 1 inputs overlay (AC-A.1)
  - Copy `infra/overlays/inputs.nix` to `test-clan/modules/flake-parts/overlays/inputs.nix`
  - Adapt overlayArgs pattern: Remove `{ flake, ... }:` wrapper, accept inputs parameter
  - Update flake.inputs references for dendritic context
  - Simplify patches (empty array in test-clan, no infra/patches.nix)

- [ ] 1.3: Import Layer 1 in nixpkgs.nix (AC-A.2)
  - Edit `test-clan/modules/flake-parts/nixpkgs.nix`
  - Add to overlays array: `(import ./overlays/inputs.nix inputs)`
  - Ensure inputs parameter passed to overlay function
  - Verify overlays array ordering (Layer 1 first)

- [ ] 1.4: Validate Layer 1 multi-channel access (AC-A.3)
  - Execute: `nix eval .#darwinConfigurations.blackphos.pkgs.stable.ripgrep.version`
  - Execute: `nix eval .#darwinConfigurations.blackphos.pkgs.unstable.ripgrep.version`
  - Verify stable and unstable provide different versions
  - Document validation outputs in Dev Notes

- [ ] 1.5: Migrate Layer 2 hotfixes overlay (AC-B.1)
  - Copy `infra/overlays/infra/hotfixes.nix` to `test-clan/modules/flake-parts/overlays/hotfixes.nix`
  - No modifications needed (pure overlay function)
  - Verify micromamba hotfix intact

- [ ] 1.6: Import Layer 2 in nixpkgs.nix (AC-B.2)
  - Edit `test-clan/modules/flake-parts/nixpkgs.nix`
  - Add to overlays array: `(import ./overlays/hotfixes.nix)`
  - Ensure Layer 2 after Layer 1 (depends on final.stable from Layer 1)
  - Verify overlays array ordering correct

- [ ] 1.7: Validate Layer 2 platform hotfixes (AC-B.3)
  - Execute: `nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version`
  - Verify micromamba uses stable version (hotfix applied)
  - Execute: `nix build .#darwinConfigurations.blackphos.pkgs.micromamba`
  - Confirm build succeeds (hotfix works)

- [ ] 1.8: Migrate Layer 4 overrides overlay (AC-C.1)
  - Create `test-clan/modules/flake-parts/overlays/overrides.nix`
  - Simplify auto-import infrastructure from infra (placeholder for future overrides)
  - Document pattern for future package overrideAttrs

- [ ] 1.9: Import Layer 4 in nixpkgs.nix (AC-C.2)
  - Edit `test-clan/modules/flake-parts/nixpkgs.nix`
  - Add to overlays array: `(import ./overlays/overrides.nix)`
  - Ensure Layer 4 after Layer 2 (can reference all prior layers)
  - Verify overlays array ordering correct

- [ ] 1.10: Validate Layer 4 infrastructure (AC-C.3)
  - Execute: `nix build .#darwinConfigurations.blackphos.system`
  - Verify build completes with overrides overlay active
  - Check for evaluation errors (none expected)
  - Confirm infrastructure ready for future overrides

**Acceptance Criteria Covered:** AC-A (Layer 1), AC-B (Layer 2), AC-C (Layer 4)

---

### Task Group 2: Configure Flake Input Overlays (AC-D)

**Objective:** Integrate Layer 5 flake input overlays into dendritic nixpkgs.nix

**Estimated Time:** 30 minutes

**Subtasks:**

- [ ] 2.1: Add nuenv flake input (AC-D.1)
  - Edit `test-clan/flake.nix`
  - Add to inputs section: `nuenv.url = "github:DeterminateSystems/nuenv";`
  - Execute: `nix flake lock` to update flake.lock
  - Verify nuenv input available

- [ ] 2.2: Import nuenv overlay in nixpkgs.nix (AC-D.2)
  - Edit `test-clan/modules/flake-parts/nixpkgs.nix`
  - Add to overlays array: `inputs.nuenv.overlays.nuenv`
  - Ensure Layer 5 after Layer 4 (last overlay layer)
  - Verify overlays array complete (5 layers total)

- [ ] 2.3: Validate nuenv accessible (AC-D.3)
  - Execute: `nix eval .#darwinConfigurations.blackphos.pkgs.nuenv.version`
  - Expected: nuenv version string (e.g., "0.3.1")
  - Execute: `nix eval .#darwinConfigurations.blackphos.pkgs.nuenv.mkScript`
  - Expected: function (nuenv main API)

- [ ] 2.4: Verify all 5 overlay layers configured
  - Review `test-clan/modules/flake-parts/nixpkgs.nix` overlays array
  - Confirm order: Layer 1 (inputs) → Layer 2 (hotfixes) → Layer 4 (overrides) → Layer 5 (flakeInputs)
  - Verify pkgsDirectory configured (Layer 3 from Story 1.10D)
  - Document complete nixpkgs.nix structure in Dev Notes

**Acceptance Criteria Covered:** AC-D (Layer 5)

---

### Task Group 3: Validate and Document (AC-E, AC-F)

**Objective:** Validate hybrid pattern (all 5 layers) and create empirical Section 13.2 documentation

**Estimated Time:** 60 minutes

**Subtasks:**

- [ ] 3.1: Build all configurations (AC-E.1)
  - Execute: `nix build .#darwinConfigurations.blackphos.system`
  - Execute: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
  - Execute: `nix build .#homeConfigurations.crs58.activationPackage`
  - Execute: `nix build .#homeConfigurations.raquel.activationPackage`
  - Verify all 4 builds pass (no evaluation errors)

- [ ] 3.2: Inspect merged pkgs (all 5 layers) (AC-E.2)
  - **Layer 1 validation:** `nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version` and unstable variant
  - **Layer 2 validation:** `nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version` (stable hotfix)
  - **Layer 3 validation:** `nix build .#ccstatusline` (pkgs-by-name from Story 1.10D)
  - **Layer 4 validation:** Successful builds (infrastructure active, no errors)
  - **Layer 5 validation:** `nix eval .#darwinConfigurations.blackphos.pkgs.nuenv.version` (input overlay)
  - Document all inspection outputs in Dev Notes

- [ ] 3.3: Validate zero regressions (AC-E.3)
  - Execute: `nix build .#ccstatusline` (Story 1.10D package still builds)
  - Execute: `nix build .#checks.aarch64-darwin.home-module-exports`
  - Execute: `nix build .#checks.aarch64-darwin.home-configurations-exposed`
  - Verify all checks pass (Story 1.10D quality maintained)

- [ ] 3.4: Create Section 13.2 structure (AC-F.1)
  - Open `test-clan/docs/architecture/test-clan-validated-architecture.md`
  - Create section: "## 13.2 Overlay Architecture Preservation with Dendritic Pattern"
  - Structure: Pattern Overview + 5-Layer Examples + Build Validation + Migration Guide + Lessons Learned + References

- [ ] 3.5: Document all 5 layers with empirical evidence (AC-F.2)
  - **Layer 1 section:** Include full inputs.nix code, validation commands, multi-channel use cases
  - **Layer 2 section:** Include full hotfixes.nix code, micromamba example, platform-specific strategy
  - **Layer 3 section:** Reference Section 13.1, Story 1.10D validation
  - **Layer 4 section:** Include overrides.nix infrastructure, override pattern examples
  - **Layer 5 section:** Include nuenv overlay integration, flake input overlay pattern
  - **Integration section:** Complete nixpkgs.nix showing all layers + pkgsDirectory

- [ ] 3.6: Document build validation and package inspection (AC-F.2)
  - Include all build commands from Task 3.1
  - Include all package inspection commands from Task 3.2
  - Document expected outputs with actual validation results
  - Add troubleshooting guidance based on implementation experience

- [ ] 3.7: Create infra migration guide (AC-F.2)
  - Table: 5 layers with source/target paths, effort estimates
  - Migration steps: 8-step procedure (directory setup → Layer 1-5 migration → testing → cleanup)
  - Effort estimate: 4-5 hours total (Layers 1,2,4,5: 2.5h + Layer 3: 2h)
  - Risk assessment: LOW (independently testable, drupol proves hybrid pattern)

- [ ] 3.8: Document lessons learned (AC-F.2)
  - overlayArgs pattern adaptation (flake parameter threading)
  - inputs parameter passing in nixpkgs.nix
  - Layer merge order dependencies (Layer 2 needs Layer 1)
  - Platform-specific conditional patterns
  - Regression testing approach (preserve Story 1.10D quality)

- [ ] 3.9: Add references and cross-references (AC-F.2)
  - Reference drupol-dendritic-infra (hybrid pattern proof)
  - Reference infra overlays (5-layer source)
  - Reference Story 1.10D (Layer 3 validation)
  - Reference Story 1.10DA (theoretical foundation)
  - Cross-reference Section 13.1 (complementary content)

- [ ] 3.10: Verify Section 13.2 matches Section 13.1 quality (AC-F.2)
  - Empirical examples (real code from migration, not hypothetical)
  - Build validation commands with actual outputs
  - Package inspection evidence from real environment
  - Comprehensive tutorial (Epic 2-6 developers can execute migration)
  - Production-ready documentation (9.5/10 clarity target like Story 1.10D)

**Acceptance Criteria Covered:** AC-E (hybrid pattern validation), AC-F (Section 13.2 empirical documentation)

---

**Total Task Group Effort:** 3 hours (180 min)

---

## Dev Notes

### Architectural Context

**5-Layer Overlay Architecture:**

This story validates infra's complete overlay architecture (5 layers) integrated with pkgs-by-name pattern (Story 1.10D Layer 3).
Understanding layer dependencies and merge order is critical for preventing evaluation failures and infinite recursion.

**Layer 1 - Multi-Channel Access (inputs.nix):**
- **Purpose:** Provide access to multiple nixpkgs channels (stable, unstable, patched)
- **Location:** `modules/flake-parts/overlays/inputs.nix`
- **Content:** Overlay function exposing `pkgs.stable.*`, `pkgs.unstable.*`, `pkgs.patched.*` namespaces
- **Dependencies:** None (first layer in merge order)
- **Use Case:** Mix stable packages for reliability with unstable for latest features
- **Example:**
  ```nix
  # Use stable version for production reliability
  packages = [ pkgs.stable.postgresql ];

  # Use unstable version for latest features
  packages = [ pkgs.unstable.neovim ];
  ```

**Layer 2 - Platform Hotfixes (hotfixes.nix):**
- **Purpose:** Selectively override broken unstable packages with stable versions
- **Location:** `modules/flake-parts/overlays/hotfixes.nix`
- **Content:** Platform-conditional package overrides using `final.stable.*`
- **Dependencies:** Layer 1 (requires `final.stable` namespace)
- **Use Case:** Avoid flake.lock rollbacks affecting all packages when one package breaks
- **Example:**
  ```nix
  # micromamba broken in unstable, use stable version
  inherit (final.stable) micromamba;
  ```

**Layer 3 - Custom Packages (pkgs-by-name/):**
- **Purpose:** Define custom derivations for packages not in nixpkgs
- **Location:** `pkgs/by-name/<package-name>/package.nix`
- **Content:** Standard Nix derivations with callPackage signature
- **Dependencies:** None (auto-discovered via pkgsDirectory)
- **Use Case:** Add custom tools (ccstatusline, atuin-format, etc.)
- **Status:** ✅ VALIDATED in Story 1.10D

**Layer 4 - Package Overrides (overrides.nix):**
- **Purpose:** Modify existing package builds (disable tests, add patches, change flags)
- **Location:** `modules/flake-parts/overlays/overrides.nix`
- **Content:** Package-specific `overrideAttrs` customizations
- **Dependencies:** All prior layers (can reference stable, unstable, custom packages)
- **Use Case:** Fix broken package tests, apply custom patches, modify build configuration
- **Example:**
  ```nix
  # Disable tests for broken package
  somePackage = prev.somePackage.overrideAttrs (oldAttrs: {
    doCheck = false;
  });
  ```

**Layer 5 - Flake Input Overlays (flakeInputs):**
- **Purpose:** Integrate third-party overlays from flake inputs
- **Location:** Configured in `modules/flake-parts/nixpkgs.nix` overlays array
- **Content:** Direct imports of `inputs.*.overlays.*`
- **Dependencies:** All prior layers (external overlays can reference everything)
- **Use Case:** Add overlays from external flakes (nuenv, LazyVim, etc.)
- **Example:**
  ```nix
  overlays = [
    # ... Layers 1-4
    inputs.nuenv.overlays.nuenv  # Layer 5: nuenv for nushell script packaging
  ];
  ```

**Critical Constraint:** Layer merge order MUST be preserved:
1. Layer 1 (inputs) - provides stable/unstable namespaces
2. Layer 2 (hotfixes) - uses stable from Layer 1
3. Layer 3 (packages) - standalone via pkgsDirectory
4. Layer 4 (overrides) - can reference all prior layers
5. Layer 5 (flakeInputs) - external overlays reference everything

**Why Order Matters:**
- Layer 2 needs `final.stable` from Layer 1 → Layer 1 must come first
- Layer 4 overrides can reference Layer 1-3 packages → Layer 4 must come after
- Layer 5 external overlays may reference anything → Layer 5 must be last
- Incorrect order causes evaluation failures or infinite recursion

### Hybrid Pattern Architecture (drupol proof)

**Pattern Source:** `~/projects/nix-workspace/drupol-dendritic-infra/modules/flake-parts/nixpkgs.nix`

**Key Architectural Insight:** overlays array + pkgsDirectory coexist in SAME perSystem block

```nix
# drupol hybrid pattern (lines 11-38)
perSystem = { system, ... }: {
  _module.args.pkgs = import inputs.nixpkgs {
    inherit system;
    config = { ... };
    overlays = [
      # Traditional overlays (Layers 1,2,4,5)
      (final: _prev: { master = ...; })
      (final: _prev: { unstable = ...; })
      inputs.nix-webapps.overlays.lib
    ];
  };
  # Custom packages auto-discovery (Layer 3)
  pkgsDirectory = ../../pkgs/by-name;
};
```

**Pattern Benefits:**
- **Clean separation:** overlays modify packages, pkgsDirectory defines new packages
- **No conflicts:** Orthogonal namespaces (overlay attributes vs discovered packages)
- **Flexible composition:** Mix traditional overlays with modern pkgs-by-name pattern
- **Production proven:** drupol uses 9 custom packages + multiple overlays successfully

**infra Adaptation:**

```nix
# test-clan modules/flake-parts/nixpkgs.nix (target)
{ inputs, ... }:
{
  imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];

  perSystem = { system, ... }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config = { allowUnfree = true; };
      overlays = [
        # Layer 1: Multi-channel access
        (import ./overlays/inputs.nix inputs)
        # Layer 2: Platform hotfixes
        (import ./overlays/hotfixes.nix)
        # Layer 4: Package overrides
        (import ./overlays/overrides.nix)
        # Layer 5: Flake input overlays
        inputs.nuenv.overlays.nuenv
      ];
    };
    # Layer 3: Custom packages (Story 1.10D)
    pkgsDirectory = ../pkgs/by-name;
  };
}
```

**Integration Points:**
1. **overlays array** applies Layers 1,2,4,5 to nixpkgs import
2. **pkgsDirectory** configures pkgs-by-name-for-flake-parts (Layer 3)
3. **Both merge into final pkgs** accessible in all dendritic modules
4. **No specialArgs needed** - standard `{ pkgs, ... }:` signature works

### Testing Standards

**Quality Gate 1: Infrastructure Setup (Task Group 1)**

**Objective:** Verify all overlay layers migrated and imported correctly

**Validation Commands:**
```bash
# Verify nixpkgs.nix evaluates with all overlays
nix eval .#darwinConfigurations.blackphos.config.nixpkgs.overlays
# Expected: Array with 4 overlay functions (Layers 1,2,4,5)

# Verify no evaluation errors
nix flake check
# Expected: All checks pass
```

**Pass Criteria:**
- ✅ overlays/inputs.nix created and imported
- ✅ overlays/hotfixes.nix created and imported
- ✅ overlays/overrides.nix created and imported
- ✅ Overlay array ordering correct (Layer 1 → 2 → 4)
- ✅ No evaluation errors (nix flake check passes)

**Troubleshooting:**
- Evaluation error: Check overlay function signatures (final: prev: ...)
- Import error: Verify relative paths from nixpkgs.nix location
- Ordering error: Review layer dependencies (Layer 2 needs Layer 1)

---

**Quality Gate 2: Multi-Channel Validation (AC-A, AC-B)**

**Objective:** Verify Layers 1-2 provide multi-channel access and hotfixes

**Validation Commands:**
```bash
# Layer 1: Multi-channel access
nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version
nix eval .#darwinConfigurations.blackphos.pkgs.unstable.hello.version
# Expected: Different versions (stable older, unstable newer)

# Layer 2: Hotfixes
nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version
# Expected: Stable version (hotfix applied)
```

**Pass Criteria:**
- ✅ `pkgs.stable.*` accessible with stable channel packages
- ✅ `pkgs.unstable.*` accessible with unstable channel packages
- ✅ Channels provide different versions (validation working)
- ✅ micromamba uses stable version (hotfix applied)

**Troubleshooting:**
- stable/unstable undefined: Check inputs.nix overlay function, verify systemInput
- Hotfix not applied: Verify overlays array ordering (Layer 2 after Layer 1)
- Same versions: Check flake inputs (stable vs unstable inputs configured?)

---

**Quality Gate 3: Hybrid Pattern Integration (AC-D, AC-E)**

**Objective:** Verify all 5 layers coexist with pkgs-by-name (Story 1.10D Layer 3)

**Validation Commands:**
```bash
# All 4 configurations build
nix build .#darwinConfigurations.blackphos.system
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel
nix build .#homeConfigurations.crs58.activationPackage
nix build .#homeConfigurations.raquel.activationPackage

# All 5 layers accessible
nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello       # Layer 1
nix eval .#darwinConfigurations.blackphos.pkgs.micromamba         # Layer 2
nix build .#ccstatusline                                          # Layer 3
# Layer 4 validated by successful builds (no active overrides yet)
nix eval .#darwinConfigurations.blackphos.pkgs.nuenv.version      # Layer 5
```

**Pass Criteria:**
- ✅ All 4 builds pass (blackphos, cinnabar, crs58, raquel)
- ✅ Layer 1: Multi-channel access works
- ✅ Layer 2: Hotfixes applied
- ✅ Layer 3: Custom packages from pkgs-by-name (Story 1.10D)
- ✅ Layer 4: Overrides infrastructure active (no errors)
- ✅ Layer 5: Input overlay packages accessible
- ✅ Zero regressions (Story 1.10D checks still pass)

**Troubleshooting:**
- Build failure: Check overlay function syntax, verify layer ordering
- Layer missing: Verify overlay imported in nixpkgs.nix overlays array
- Regression: Review nixpkgs.nix changes, ensure pkgsDirectory still configured
- Package undefined: Check layer dependencies (Layer 2 needs Layer 1)

---

**Quality Gate 4: Documentation Review (AC-F)**

**Objective:** Verify Section 13.2 comprehensive and empirical (matches Section 13.1 quality)

**Validation Criteria:**
- ✅ Section 13.2 exists in test-clan-validated-architecture.md
- ✅ Contains all 5 layer implementations with real code
- ✅ Includes build validation commands with actual outputs
- ✅ Documents hybrid pattern integration (overlays + pkgsDirectory)
- ✅ Provides Epic 2-6 migration guide with effort estimates
- ✅ References infra source files and drupol hybrid pattern
- ✅ Matches Section 13.1 quality (empirical, production-ready)

**Content Verification:**
- Pattern overview: All 5 layers explained with purpose and dependencies
- Example completeness: Full overlay code + build commands + inspection outputs
- Migration guide: All 5 layers documented with source/target paths and effort
- Tutorial quality: Comprehensive enough for Epic 2-6 developers to execute migration
- Empirical evidence: Based on real implementation, not hypothetical

**Pass Criteria:**
- ✅ Documentation comprehensive (self-contained tutorial)
- ✅ Code examples correct and tested (from actual migration)
- ✅ Migration path clear and actionable (8-step procedure)
- ✅ References accurate (local paths + external links)
- ✅ Quality matches Section 13.1 (9.5/10 clarity)

---

### Project Structure Notes

**test-clan Repository Layout (Story 1.10DB additions):**

```
test-clan/
├── flake.nix                                    # UPDATE: Add nuenv input (Layer 5)
├── modules/
│   └── flake-parts/
│       ├── nixpkgs.nix                          # UPDATE: Import all overlays, configure pkgsDirectory
│       └── overlays/                            # NEW: Overlay layers directory
│           ├── inputs.nix                       # NEW: Layer 1 (multi-channel access)
│           ├── hotfixes.nix                     # NEW: Layer 2 (platform hotfixes)
│           └── overrides.nix                    # NEW: Layer 4 (package overrides)
├── pkgs/
│   └── by-name/
│       └── ccstatusline/                        # EXISTING: Layer 3 (Story 1.10D)
│           └── package.nix
└── docs/
    └── architecture/
        └── test-clan-validated-architecture.md # UPDATE: Add Section 13.2
```

**File Change Summary:**

**New Files:**
- `modules/flake-parts/overlays/inputs.nix` (Layer 1, ~60 lines)
- `modules/flake-parts/overlays/hotfixes.nix` (Layer 2, ~30 lines)
- `modules/flake-parts/overlays/overrides.nix` (Layer 4, ~10 lines placeholder)

**Modified Files:**
- `flake.nix` (add nuenv flake input for Layer 5)
- `flake.lock` (update with nuenv dependency)
- `modules/flake-parts/nixpkgs.nix` (import overlays, add nuenv to overlays array)
- `docs/architecture/test-clan-validated-architecture.md` (add Section 13.2)

**Integration Points:**

1. **flake.nix → modules/flake-parts/nixpkgs.nix:**
   - flake.nix provides inputs (nixpkgs, nuenv, etc.)
   - nixpkgs.nix imports inputs parameter
   - Connection: inputs threading via module signature

2. **modules/flake-parts/nixpkgs.nix → overlays/*.nix:**
   - nixpkgs.nix imports each overlay file
   - Overlays applied to nixpkgs import
   - Connection: overlays array in perSystem

3. **overlays/inputs.nix → overlays/hotfixes.nix:**
   - inputs.nix provides `final.stable` namespace
   - hotfixes.nix uses `final.stable.*` for fallbacks
   - Connection: Layer merge order dependency

4. **overlays array + pkgsDirectory → merged pkgs:**
   - Overlays modify nixpkgs (Layers 1,2,4,5)
   - pkgsDirectory adds custom packages (Layer 3)
   - Connection: Hybrid pattern (drupol architecture)

5. **merged pkgs → all dendritic modules:**
   - All 5 layers accessible via `pkgs.*` in modules
   - No specialArgs needed (standard signature)
   - Connection: nixpkgs import with overlays + pkgsDirectory

### Quick Reference

**Target Repository:**
```bash
~/projects/nix-workspace/test-clan/
```

**Key Commands:**

```bash
# Build all configurations
cd ~/projects/nix-workspace/test-clan
nix build .#darwinConfigurations.blackphos.system
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel
nix build .#homeConfigurations.crs58.activationPackage
nix build .#homeConfigurations.raquel.activationPackage

# Validate all 5 layers
nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version       # Layer 1
nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version        # Layer 2
nix build .#ccstatusline                                                 # Layer 3
nix eval .#darwinConfigurations.blackphos.pkgs.nuenv.version             # Layer 5

# Verify zero regressions (Story 1.10D)
nix build .#ccstatusline
nix build .#checks.aarch64-darwin.home-module-exports
nix build .#checks.aarch64-darwin.home-configurations-exposed
```

**Source Files:**

```bash
# infra overlay layers (source)
~/projects/nix-workspace/infra/overlays/default.nix               # 5-layer architecture
~/projects/nix-workspace/infra/overlays/inputs.nix                # Layer 1 source
~/projects/nix-workspace/infra/overlays/infra/hotfixes.nix        # Layer 2 source
~/projects/nix-workspace/infra/overlays/overrides/default.nix     # Layer 4 source

# test-clan overlay layers (target)
~/projects/nix-workspace/test-clan/modules/flake-parts/nixpkgs.nix
~/projects/nix-workspace/test-clan/modules/flake-parts/overlays/inputs.nix
~/projects/nix-workspace/test-clan/modules/flake-parts/overlays/hotfixes.nix
~/projects/nix-workspace/test-clan/modules/flake-parts/overlays/overrides.nix

# Documentation
~/projects/nix-workspace/test-clan/docs/architecture/test-clan-validated-architecture.md
```

**Reference Repositories:**

```bash
# drupol-dendritic-infra (PRIMARY hybrid pattern reference)
~/projects/nix-workspace/drupol-dendritic-infra/
# Key file:
# - modules/flake-parts/nixpkgs.nix (lines 19-37: overlays array + pkgsDirectory)

# infra (5-layer overlay source)
~/projects/nix-workspace/infra/
# Key files:
# - overlays/default.nix (5-layer merge composition)
# - overlays/inputs.nix (Layer 1 implementation)
# - overlays/infra/hotfixes.nix (Layer 2 implementation)
# - overlays/overrides/default.nix (Layer 4 infrastructure)
```

**External References:**

- **Nixpkgs overlays documentation:** https://nixos.org/manual/nixpkgs/stable/#chap-overlays
  - Overlay function signature
  - Merge order semantics
  - Final vs prev distinction

- **pkgs-by-name-for-flake-parts:** https://github.com/drupol/pkgs-by-name-for-flake-parts
  - Flake module source
  - Usage documentation
  - Pattern explanation

- **Story 1.10D work item:** `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10d-validate-custom-package-overlays.md`
  - Layer 3 validation (pkgs-by-name pattern)
  - Section 13.1 reference

- **Story 1.10DA work item:** `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10da-validate-overlay-preservation.md`
  - Theoretical foundation (documentation)
  - Overlay architecture concepts

**Estimated Effort:** 2-3 hours

**Risk Level:** Low
- infra overlays already working (proven in production)
- drupol proves hybrid pattern viable (9 packages + multiple overlays)
- Layers independently testable (incremental validation)
- Clear separation of concerns (each layer orthogonal)

### Constraints

1. **Layer Merge Order Preservation:**
   - Layer 1 (inputs) MUST come first (provides stable/unstable namespaces)
   - Layer 2 (hotfixes) MUST come after Layer 1 (depends on final.stable)
   - Layer 4 (overrides) MUST come after Layers 1-2 (can reference all prior layers)
   - Layer 5 (flakeInputs) MUST come last (external overlays reference everything)
   - Incorrect order causes evaluation failures or infinite recursion

2. **Hybrid Pattern Integrity:**
   - overlays array handles Layers 1,2,4,5 (traditional overlay functions)
   - pkgsDirectory handles Layer 3 (custom packages via auto-discovery)
   - Both configured in SAME perSystem block (drupol pattern)
   - Do NOT mix overlay layers into pkgsDirectory or vice versa

3. **Story 1.10D Regression Prevention:**
   - All Story 1.10D validations MUST still pass after overlay migration
   - ccstatusline package MUST still build (Layer 3 integrity)
   - home-module-exports check MUST still pass
   - home-configurations-exposed check MUST still pass
   - Zero tolerance for regressions (overlay changes cannot break pkgs-by-name)

4. **Empirical Documentation Requirement:**
   - Section 13.2 MUST be based on real implementation (not hypothetical)
   - All code examples MUST be from actual migrated overlays
   - Build validation MUST include actual command outputs
   - Lessons learned MUST document real challenges encountered
   - Quality MUST match Section 13.1 (9.5/10 clarity, production-ready)

5. **Epic 1 Coverage Target:**
   - Story 1.10DB completion achieves 95% Epic 1 architectural coverage
   - All 5 overlay layers empirically validated (not just documented)
   - Hybrid pattern proven (overlays + pkgs-by-name coexistence)
   - Epic 2-6 teams receive battle-tested migration guide

---

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Model name and version will be recorded during implementation -->

### Debug Log References

<!-- Commit hashes and links will be recorded during implementation -->

### Completion Notes List

<!-- Implementation notes, challenges, solutions will be recorded during implementation -->

### File List

<!-- Files created, modified, deleted will be recorded during implementation -->

---

## Learnings

<!-- Post-implementation insights, architectural discoveries, pattern validations -->
<!-- This section will be populated during implementation or Party Mode checkpoint -->

---

## Change Log

### 2025-11-16 - Story Created

- Story 1.10DB work item created following Story 1.10D template structure
- Comprehensive story definition based on Epic 1 lines 1481-1639 (159 lines)
- Party Mode Ultrathink Decision (2025-11-16): All 9 agents unanimous - Story 1.10DA provided theoretical documentation without actual migration, violating Epic 1 "Architectural Validation via Pattern Rehearsal" principle
- Story 1.10DB mission: Execute ACTUAL overlay migration from infra to test-clan (Layers 1,2,4,5), validate empirically, prove hybrid pattern works
- 6 acceptance criteria across 5-layer overlay migration and validation (AC-A through AC-F)
- 3 task groups with detailed subtasks mapped to ACs (90min + 30min + 60min = 3h)
- 4 quality gates with explicit validation commands (Infrastructure, Multi-Channel, Hybrid Pattern, Documentation)
- drupol-dendritic-infra as PRIMARY hybrid pattern reference (overlays array + pkgsDirectory coexistence proof)
- infra's 5-layer overlay architecture source (default.nix, inputs.nix, hotfixes.nix, overrides/default.nix)
- Strategic value: Achieves 95% Epic 1 coverage with empirical validation, removes Epic 2-6 migration blocker (architectural uncertainty), provides battle-tested migration guide based on real implementation
- Work item structure: 10 sections following Story 1.10D template (9.5/10 clarity target)
- Documentation scope: Comprehensive Section 13.2 tutorial matching Section 13.1 quality (empirical evidence, production-ready)
- Implementation guidance: Detailed (exact overlay code patterns, build validation commands, package inspection sequences)
- Total estimated effort: 2-3 hours (matches Story 1.10D complexity, similar scope)
- Template source: Story 1.10D (2138 lines, 9.5/10 clarity, all 9 ACs satisfied, 4 gates PASS)
- Work item length: 1,563 lines (within target 1,400-1,600 range, proportional to 6 ACs vs Story 1.10D's 9 ACs)

---

## Senior Developer Review (AI)

<!-- Placeholder for post-implementation review -->
<!-- Will be populated after Story 1.10DB implementation complete -->
