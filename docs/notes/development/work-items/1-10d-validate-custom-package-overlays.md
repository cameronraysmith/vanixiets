# Story 1.10D: Validate Custom Package Overlays with pkgs-by-name Pattern

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** backlog

**Dependencies:**
- Story 1.10C (done): sops-nix infrastructure validates secrets work with dendritic
- Dendritic Overlay Pattern Review (2025-11-16): Architectural guidance and drupol pattern identification

**Blocks:**
- Story 1.10E (backlog): ccstatusline feature enablement requires package from this story
- Epic 1 checkpoint (backlog): Overlay validation critical for Epic 2-6 GO decision

**Strategic Value:** Completes Epic 1 architectural validation (modules ✅, secrets ✅, **overlays ✅**), validates infra's 4 custom packages will migrate to dendritic + clan successfully, removes last Epic 2-6 migration blocker (overlay pattern uncertainty), provides reusable pattern template for Epic 2-6 package migration, proves dendritic pattern is comprehensive (handles all infra architectural components), de-risks Epic 2-6 timeline (no overlay emergency fixes needed), documents migration path for 4 infra packages (2.5-3h effort in Epic 2).

---

## Story Description

As a system administrator,
I want to validate that infra's custom package overlays work with dendritic flake-parts + clan architecture using the pkgs-by-name pattern,
So that Epic 2-6 migration can proceed confidently knowing all 4 infra custom packages will migrate successfully.

**Context:**

Epic 1 validation mission requires proving ALL infra architectural patterns work with dendritic + clan, not just modules and secrets.

infra has 4 production custom packages (ccstatusline, atuin-format, markdown-tree-parser, starship-jj) currently in `overlays/packages/` using `lib.packagesFromDirectoryRecursive` for auto-discovery.
These packages must migrate to dendritic flake-parts structure in Epic 2-6.

**Critical Discovery:** Dendritic Overlay Pattern Review (2025-11-16) identified pkgs-by-name-for-flake-parts (drupol) as optimal pattern:
- Uses SAME underlying function as infra (`lib.packagesFromDirectoryRecursive`)
- Follows nixpkgs RFC 140 convention (`pkgs/by-name/` directory structure)
- Zero boilerplate (just set `pkgsDirectory` option in perSystem)
- Proven in production: drupol-dendritic-infra (9 packages), compatible with gaetanlepage comprehensive dendritic usage

**Migration Assessment:** infra overlay system is ✅ COMPATIBLE with dendritic pattern.
Migration requires directory restructuring (`overlays/packages/` → `pkgs/by-name/`) but NO code changes to package derivations.
Estimated effort: 2.5-3 hours for all 4 packages.

**Story 1.10D validates:** Create pkgs-by-name infrastructure in test-clan, implement ccstatusline as proof-of-concept, prove pattern works end-to-end (package build → module consumption → activation).
Success means Epic 2-6 can migrate infra's 4 packages with confidence.

**Blocks Story 1.10E:** ccstatusline feature enablement requires ccstatusline package (created in this story).

**Test Case: ccstatusline**

ccstatusline chosen as proof-of-concept because:
- Production-ready derivation exists in infra (copy directly, no development needed)
- Settings pre-configured in test-clan: ccstatusline-settings.nix (175 lines, waiting for package)
- Full workflow validation: package build → perSystem export → pkgs.* consumption → home-manager activation
- Represents real infra need (Claude Code status line feature)

---

## Implementation Notes

### pkgs-by-name-for-flake-parts Pattern Overview

**Pattern Source:** drupol-dendritic-infra (PRIMARY reference, 9 packages in production)

**Key Architecture:**
- Directory structure: `pkgs/by-name/<first-2-chars>/<package-name>/package.nix` (nixpkgs RFC 140)
- Auto-discovery via `lib.packagesFromDirectoryRecursive` (SAME as infra)
- Zero boilerplate: Just set `pkgsDirectory` option in perSystem
- Proven dendritic compatibility (gaetanlepage evidence: 50+ packages)

**Pattern Mechanism:**
1. Add flake input: `inputs.pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts"`
2. Import flake module in modules/nixpkgs.nix: `imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];`
3. Configure perSystem: `perSystem = { ... }: { pkgsDirectory = ../../pkgs/by-name; };`
4. Create packages in `pkgs/by-name/XY/package-name/package.nix` (X=first char, Y=second char)
5. Packages auto-export to `packages.<system>.<package-name>` and available as `pkgs.<package-name>` in all modules

**Why This Pattern:**
- Uses SAME underlying function as infra (`lib.packagesFromDirectoryRecursive`)
- No custom overlay code needed (flake module handles export)
- Follows nixpkgs convention (RFC 140 compliance)
- Production-proven in multiple dendritic repos

### infra Compatibility Assessment

**Current State (infra):**
- Location: `overlays/packages/`
- Auto-discovery: `lib.packagesFromDirectoryRecursive`
- Packages: ccstatusline, atuin-format, markdown-tree-parser, starship-jj
- Export mechanism: Custom overlay configuration

**Target State (dendritic + pkgs-by-name):**
- Location: `pkgs/by-name/`
- Auto-discovery: `lib.packagesFromDirectoryRecursive` (via pkgs-by-name-for-flake-parts)
- Packages: Same 4 packages
- Export mechanism: Flake module (no custom overlay code)

**Migration Impact:**
- ✅ SAFE TO MIGRATE (uses same underlying function)
- Migration = directory restructuring only (NO code changes to package derivations)
- `overlays/packages/ccstatusline.nix` → `pkgs/by-name/cc/ccstatusline/package.nix`
- Estimated effort: 2.5-3 hours for all 4 packages (directory moves + flake input + module config)
- Risk level: LOW (proven pattern, compatible architecture)

### Three-Layer Pattern Architecture

**Critical Constraint:** Layers are orthogonal with zero overlap (prevents "where does my code go?" confusion)

**Layer 1 - Package Definition (pkgs/by-name/):**
- Purpose: Define package derivations
- Location: `pkgs/by-name/<first-2-chars>/<package-name>/package.nix`
- Content: Standard Nix derivations with callPackage signature
- Example: `{ lib, buildNpmPackage, ... }: buildNpmPackage { ... }`
- Rule: NO flake-parts imports, NO module system, just derivations

**Layer 2 - Package Export (modules/nixpkgs.nix):**
- Purpose: Export packages to flake outputs and pkgs namespace
- Location: `modules/nixpkgs.nix` flake-parts module
- Content: Import pkgs-by-name-for-flake-parts, configure pkgsDirectory
- Mechanism: `imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];`
- Rule: NO package definitions here, only export configuration

**Layer 3 - Package Consumption (dendritic modules):**
- Purpose: Use packages in home-manager/nixos configurations
- Location: Any dendritic module (e.g., `modules/home/ai/claude-code/default.nix`)
- Content: Reference packages via `pkgs.<package-name>`
- Example: `command = "${pkgs.ccstatusline}/bin/ccstatusline";`
- Rule: NO package definitions, NO exports, just consumption

**Why This Matters:**
- Prevents infinite recursion (common overlay pitfall)
- Clear separation of concerns (define vs export vs consume)
- Matches dendritic module philosophy (orthogonal concerns in separate files)
- Enables auto-discovery (no manual package lists)

---

## Acceptance Criteria

### A. Add pkgs-by-name-for-flake-parts Infrastructure

**Target:** Integrate pkgs-by-name-for-flake-parts flake module into test-clan

**Implementation:**

1. Add flake input to flake.nix:
   ```nix
   inputs.pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";
   ```

2. Import flake module in modules/nixpkgs.nix:
   ```nix
   imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];
   ```

3. Configure pkgsDirectory in perSystem:
   ```nix
   perSystem = { ... }: {
     pkgsDirectory = ../../pkgs/by-name;
   };
   ```

4. Verify flake module loads without errors:
   ```bash
   nix flake check
   ```

**Pass Criteria:**
- Flake input added correctly
- Module import successful
- pkgsDirectory configured
- `nix flake check` passes with no evaluation errors

**Estimated effort:** 15 min

---

### B. Create pkgs/by-name Directory Structure

**Target:** Establish nixpkgs RFC 140 compliant directory structure

**Implementation:**

1. Create directory following nixpkgs convention:
   ```bash
   mkdir -p pkgs/by-name/cc/ccstatusline
   ```

2. Verify structure follows RFC 140:
   - Pattern: `pkgs/by-name/<first-2-chars>/<package-name>/package.nix`
   - Example: `pkgs/by-name/cc/ccstatusline/package.nix`
   - First 2 chars: "cc" (from "ccstatusline")

3. Verify directory accessible from flake root:
   ```bash
   ls -la pkgs/by-name/cc/ccstatusline/
   ```

4. Confirm matches drupol-dendritic-infra pattern:
   - Reference: `~/projects/nix-workspace/drupol-dendritic-infra/pkgs/by-name/`
   - Verify same directory naming convention

**Pass Criteria:**
- Directory `pkgs/by-name/cc/ccstatusline/` exists
- Structure matches RFC 140 specification
- Accessible from flake root (relative path `../../pkgs/by-name` works from modules/)
- Pattern matches drupol reference implementation

**Estimated effort:** 5 min

---

### C. Implement ccstatusline Package

**Target:** Copy production-ready ccstatusline derivation from infra to test-clan

**Implementation:**

1. Copy production-ready derivation from infra:
   ```bash
   cp ~/projects/nix-workspace/infra/overlays/packages/ccstatusline.nix \
      ~/projects/nix-workspace/test-clan/pkgs/by-name/cc/ccstatusline/package.nix
   ```

2. Verify package.nix uses standard callPackage signature:
   ```nix
   { lib, buildNpmPackage, fetchzip, jq, nix-update-script }:
   buildNpmPackage (finalAttrs: {
     pname = "ccstatusline";
     version = "0.1.0";
     # ... rest of derivation
   })
   ```

3. Confirm no modifications needed:
   - Derivation is production-validated in infra
   - Uses standard nixpkgs builder (buildNpmPackage)
   - No custom overlay arguments required

4. Verify package follows npm tarball pattern:
   - Pre-built dist/ directory in source tarball
   - No compilation phase needed
   - installPhase copies dist/ to output

**Pass Criteria:**
- File `pkgs/by-name/cc/ccstatusline/package.nix` exists
- Uses standard callPackage signature (no custom arguments)
- Derivation matches infra production version (85 lines, npm tarball pattern)
- No syntax errors (will be validated in AC D build step)

**Estimated effort:** 10 min (copy + verify)

---

### D. Validate Package Auto-Discovery

**Target:** Verify pkgs-by-name-for-flake-parts auto-discovers and exports ccstatusline

**Implementation:**

1. Build ccstatusline package:
   ```bash
   nix build .#packages.aarch64-darwin.ccstatusline
   # OR short form:
   nix build .#ccstatusline
   ```

2. Verify package exports to correct output paths:
   - Full path: `packages.<system>.ccstatusline`
   - Short form: `ccstatusline` (flake output shorthand)
   - Check available with: `nix flake show | grep ccstatusline`

3. Verify package accessible via pkgs namespace:
   ```bash
   nix eval .#packages.aarch64-darwin.ccstatusline.meta.description
   # Expected output: "Highly customizable status line formatter for Claude Code CLI"
   ```

4. Confirm auto-discovery worked:
   - No manual package list in modules/nixpkgs.nix
   - Package discovered purely by directory structure
   - Matches drupol pattern (zero boilerplate)

**Pass Criteria:**
- `nix build .#ccstatusline` succeeds
- Package exports to `packages.<system>.ccstatusline`
- Package metadata accessible via `nix eval`
- No manual package registration needed (auto-discovery confirmed)

**Estimated effort:** 15 min

---

### E. Validate Package Build Quality

**Target:** Verify ccstatusline package build produces correct output structure

**Implementation:**

1. Inspect package contents:
   ```bash
   ls -la result/bin/
   ls -la result/lib/node_modules/ccstatusline/
   ```

2. Verify executable exists and is executable:
   ```bash
   file result/bin/ccstatusline
   # Expected: "...shell script..."
   test -x result/bin/ccstatusline && echo "✓ Executable"
   ```

3. Check runtime dependencies:
   ```bash
   nix-store -q --references result/
   # Expected: nodejs runtime + ccstatusline package
   ```

4. Verify package metadata complete:
   ```bash
   nix eval .#packages.aarch64-darwin.ccstatusline.meta --json | jq '.description, .homepage, .license, .mainProgram'
   ```
   - Description: "Highly customizable status line formatter for Claude Code CLI"
   - Homepage: GitHub URL
   - License: Valid SPDX identifier
   - mainProgram: "ccstatusline"

**Pass Criteria:**
- Executable `result/bin/ccstatusline` exists and is executable
- Package includes nodejs runtime dependency
- Package metadata fields populated correctly
- File permissions correct (executable bit set)

**Estimated effort:** 15 min

---

### F. Test Module Consumption

**Target:** Verify ccstatusline accessible from dendritic modules via pkgs.ccstatusline

**Implementation:**

1. Update claude-code module to consume ccstatusline:
   ```nix
   # modules/home/ai/claude-code/default.nix
   { pkgs, ... }:
   {
     programs.claude-code.settings.statusLine = {
       type = "command";
       command = "${pkgs.ccstatusline}/bin/ccstatusline";
       padding = 0;
     };
   }
   ```

2. Verify pkgs.ccstatusline resolves without errors:
   - No infinite recursion
   - No missing package errors
   - No evaluation failures

3. Build home-manager configuration:
   ```bash
   nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
   ```

4. Verify ccstatusline in activation closure:
   ```bash
   nix-store -q --references result/ | grep ccstatusline
   # Should output: /nix/store/...-ccstatusline-0.1.0
   ```

**Pass Criteria:**
- Module references `pkgs.ccstatusline` successfully
- home-manager build completes without errors
- ccstatusline package present in activation closure
- Package accessible from dendritic module context (no specialArgs needed)

**Estimated effort:** 30 min

---

### G. Validate Dendritic Compatibility

**Target:** Confirm pkgs-by-name pattern integrates correctly with dendritic architecture

**Compatibility Checklist:**

1. ✅ **Package definition is NOT a flake-parts module:**
   - File: `pkgs/by-name/cc/ccstatusline/package.nix`
   - Content: Standard Nix derivation (callPackage signature)
   - Verification: No `flake-parts` imports, no `perSystem` usage

2. ✅ **Package EXPORT via flake module:**
   - File: `modules/nixpkgs.nix`
   - Content: Import pkgs-by-name-for-flake-parts, configure pkgsDirectory
   - Verification: Package appears in `nix flake show` outputs

3. ✅ **Package CONSUMPTION in dendritic module:**
   - File: `modules/home/ai/claude-code/default.nix`
   - Content: References `pkgs.ccstatusline`
   - Verification: Module builds successfully with package reference

4. ✅ **NO specialArgs pass-thru needed:**
   - pkgs available in all dendritic modules automatically
   - No custom `extraSpecialArgs` configuration required
   - Verification: Standard module signature `{ pkgs, ... }:` works

5. ✅ **import-tree auto-discovery compatibility:**
   - pkgs-by-name doesn't conflict with module auto-discovery
   - Both use separate namespace (packages vs modules)
   - Verification: `nix flake check` passes with both systems active

6. ✅ **Pattern matches drupol-dendritic-infra architecture:**
   - Directory structure identical to drupol reference
   - Integration pattern identical (flake input + module import + perSystem config)
   - Verification: Side-by-side comparison with `~/projects/nix-workspace/drupol-dendritic-infra/`

**Pass Criteria:**
- All 6 compatibility checks pass
- No architectural conflicts detected
- Pattern matches proven dendritic reference implementation
- Zero workarounds or hacks needed

**Estimated effort:** 15 min

---

### H. Validate infra Migration Readiness

**Target:** Document migration path for all 4 infra packages

**infra Package Inventory:**

| Package | Current Location | Target Location | Estimated Effort |
|---------|------------------|-----------------|------------------|
| ccstatusline | `overlays/packages/ccstatusline.nix` | `pkgs/by-name/cc/ccstatusline/package.nix` | ✅ Validated (this story) |
| atuin-format | `overlays/packages/atuin-format/` | `pkgs/by-name/at/atuin-format/package.nix` | 30 min (directory package → single file) |
| markdown-tree-parser | `overlays/packages/markdown-tree-parser.nix` | `pkgs/by-name/ma/markdown-tree-parser/package.nix` | 15 min (file move) |
| starship-jj | `overlays/packages/starship-jj.nix` | `pkgs/by-name/st/starship-jj/package.nix` | 15 min (file move) |

**Total Migration Effort:** 2.5-3 hours (includes flake input setup, testing, documentation)

**Migration Verification:**

1. Verify all packages use standard callPackage signatures:
   - ccstatusline: ✅ `{ lib, buildNpmPackage, fetchzip, jq, nix-update-script }`
   - atuin-format: Review `overlays/packages/atuin-format/default.nix` for signature
   - markdown-tree-parser: Review for standard rustPlatform signature
   - starship-jj: Review for standard rustPlatform signature

2. Confirm lib.packagesFromDirectoryRecursive pattern compatibility:
   - infra current: `lib.packagesFromDirectoryRecursive { ... }`
   - pkgs-by-name-for-flake-parts: Uses SAME function under hood
   - Assessment: ✅ COMPATIBLE (no code changes needed)

3. Verify no custom overlayArgs needed:
   - All packages use standard nixpkgs builders
   - No infra-specific overlay arguments
   - Assessment: ✅ SAFE (standard callPackage only)

4. Migration risk assessment:
   - Risk level: LOW
   - Reasoning: Directory restructuring only, same underlying function, proven pattern
   - Mitigation: Story 1.10D validates pattern before Epic 2-6 migration

**Pass Criteria:**
- All 4 packages documented with migration paths
- Effort estimates provided per package
- callPackage signature compatibility verified
- Migration risk assessed as LOW
- Epic 2-6 migration confidence established

**Estimated effort:** 30 min (documentation + verification)

---

### I. Documentation - Section 13.1 (Custom Package Overlays)

**Target:** Create comprehensive tutorial in test-clan-validated-architecture.md

**Documentation Structure:**

```markdown
## 13.1 Custom Package Overlays with pkgs-by-name Pattern

### Pattern Overview

**Architecture:** pkgs-by-name-for-flake-parts (drupol pattern)

**Directory Structure:**
pkgs/by-name/<first-2-chars>/<package-name>/package.nix

**Integration Steps:**
1. Add flake input: inputs.pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts"
2. Import module: modules/nixpkgs.nix adds flake module import
3. Configure perSystem: Set pkgsDirectory = ../../pkgs/by-name
4. Create packages: Standard Nix derivations with callPackage signature
5. Auto-discovery: Packages export to packages.<system>.<name> and pkgs.<name>

**Pattern Benefits:**
- Uses lib.packagesFromDirectoryRecursive (same as infra)
- Follows nixpkgs RFC 140 convention
- Zero boilerplate (no manual package lists)
- Dendritic compatible (proven in drupol, gaetanlepage repos)

### Complete Example: ccstatusline Package

**1. Package Derivation (pkgs/by-name/cc/ccstatusline/package.nix):**
[Include full 85-line derivation from infra]

**2. Build Commands:**
```bash
# Build package
nix build .#ccstatusline

# Inspect contents
ls -la result/bin/
nix-store -q --references result/

# Verify metadata
nix eval .#packages.aarch64-darwin.ccstatusline.meta.description
```

**3. Module Consumption:**
```nix
# modules/home/ai/claude-code/default.nix
{ pkgs, ... }:
{
  programs.claude-code.settings.statusLine = {
    type = "command";
    command = "${pkgs.ccstatusline}/bin/ccstatusline";
  };
}
```

**4. Integration Validation:**
```bash
# Build home-manager config
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage

# Verify package in closure
nix-store -q --references result/ | grep ccstatusline
```

### infra Migration Guide

**Current State (infra):**
- Location: overlays/packages/
- Auto-discovery: lib.packagesFromDirectoryRecursive
- Packages: 4 production packages

**Migration Path:**
[Include table from AC H with all 4 packages]

**Migration Steps:**
1. Add pkgs-by-name-for-flake-parts flake input to infra
2. Create pkgs/by-name/ directory structure
3. Move package files to RFC 140 paths (no code changes)
4. Update modules/nixpkgs.nix to import flake module
5. Configure pkgsDirectory in perSystem
6. Test builds and module consumption
7. Remove old overlays/ configuration

**Estimated Total Effort:** 2.5-3 hours

**Risk Assessment:** LOW (directory restructuring only, proven pattern)

### References

- **drupol-dendritic-infra:** ~/projects/nix-workspace/drupol-dendritic-infra/ (PRIMARY pattern reference, 9 packages)
- **gaetanlepage:** ~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/ (compatibility proof, 50+ packages)
- **pkgs-by-name-for-flake-parts:** https://github.com/drupol/pkgs-by-name-for-flake-parts
- **nixpkgs RFC 140:** https://github.com/NixOS/rfcs/pull/140
- **Dendritic Overlay Pattern Review:** [Link to research document]
```

**Pass Criteria:**
- Section 13.1 exists in test-clan-validated-architecture.md
- Contains pattern overview (architecture, integration steps, benefits)
- Includes complete ccstatusline example (derivation + build + consumption)
- Documents infra migration guide (table + steps + effort + risk)
- References drupol (PRIMARY), gaetanlepage (compatibility), external links

**Estimated effort:** 45 min

---

**Total Acceptance Criteria Effort:** 2-3 hours
- AC A: 15 min (infrastructure setup)
- AC B: 5 min (directory creation)
- AC C: 10 min (package implementation)
- AC D: 15 min (auto-discovery validation)
- AC E: 15 min (build quality validation)
- AC F: 30 min (module consumption test)
- AC G: 15 min (dendritic compatibility)
- AC H: 30 min (infra migration readiness)
- AC I: 45 min (documentation)

**Sum:** 2h 40min (aligns with story estimate of 2-3 hours)

---

## Tasks / Subtasks

### Task 1: Infrastructure Setup (AC A-B)

**Objective:** Integrate pkgs-by-name-for-flake-parts and create directory structure

**Estimated Time:** 20 minutes

**Subtasks:**

- [ ] 1.1: Add pkgs-by-name-for-flake-parts flake input to flake.nix (AC A.1)
  - Edit `~/projects/nix-workspace/test-clan/flake.nix`
  - Add to inputs section: `pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";`
  - Verify syntax with `nix flake metadata`

- [ ] 1.2: Import flake module in modules/nixpkgs.nix (AC A.2)
  - Edit `~/projects/nix-workspace/test-clan/modules/nixpkgs.nix`
  - Add to imports: `inputs.pkgs-by-name-for-flake-parts.flakeModule`
  - Ensure inputs parameter available in module signature

- [ ] 1.3: Configure pkgsDirectory in perSystem (AC A.3)
  - Edit `~/projects/nix-workspace/test-clan/modules/nixpkgs.nix`
  - Add perSystem configuration: `perSystem = { ... }: { pkgsDirectory = ../../pkgs/by-name; };`
  - Verify relative path correct from modules/ directory

- [ ] 1.4: Create pkgs/by-name/cc/ccstatusline/ directory structure (AC B.1)
  - Execute: `mkdir -p ~/projects/nix-workspace/test-clan/pkgs/by-name/cc/ccstatusline`
  - Verify structure matches RFC 140: `pkgs/by-name/<first-2-chars>/<package-name>/`
  - Confirm directory accessible from flake root

- [ ] 1.5: Verify flake module loads (AC A.4)
  - Execute: `nix flake check` from test-clan directory
  - Expected: No evaluation errors
  - Troubleshoot any import or path issues

**Acceptance Criteria Covered:** AC A (infrastructure), AC B (directory structure)

---

### Task 2: ccstatusline Package Implementation (AC C)

**Objective:** Copy production-ready ccstatusline derivation from infra

**Estimated Time:** 10 minutes

**Subtasks:**

- [ ] 2.1: Copy infra ccstatusline.nix → test-clan pkgs/by-name/cc/ccstatusline/package.nix (AC C.1)
  - Execute: `cp ~/projects/nix-workspace/infra/overlays/packages/ccstatusline.nix ~/projects/nix-workspace/test-clan/pkgs/by-name/cc/ccstatusline/package.nix`
  - Verify file copied successfully: `ls -la ~/projects/nix-workspace/test-clan/pkgs/by-name/cc/ccstatusline/package.nix`

- [ ] 2.2: Verify callPackage signature (AC C.2)
  - Open `package.nix` and confirm signature: `{ lib, buildNpmPackage, fetchzip, jq, nix-update-script }:`
  - Verify no custom overlay arguments needed
  - Confirm uses standard nixpkgs builders

- [ ] 2.3: Confirm npm tarball pattern (AC C.4)
  - Review derivation structure: pre-built dist/ directory
  - Verify no compilation phase (buildPhase = "")
  - Confirm installPhase copies dist/ to output
  - No modifications needed (production-validated)

**Acceptance Criteria Covered:** AC C (package implementation)

---

### Task 3: Build and Quality Validation (AC D-E)

**Objective:** Verify ccstatusline builds correctly and exports properly

**Estimated Time:** 30 minutes

**Subtasks:**

- [ ] 3.1: Build ccstatusline package (AC D.1)
  - Execute: `nix build .#ccstatusline` from test-clan directory
  - Verify build completes without errors
  - Check result symlink created: `ls -la result/`

- [ ] 3.2: Verify auto-discovery (AC D.2-4)
  - Check flake outputs: `nix flake show | grep ccstatusline`
  - Verify package path: `nix eval .#packages.aarch64-darwin.ccstatusline.meta.description`
  - Expected output: "Highly customizable status line formatter for Claude Code CLI"
  - Confirm no manual package list needed (auto-discovery working)

- [ ] 3.3: Inspect package contents (AC E.1-2)
  - List executables: `ls -la result/bin/`
  - Verify ccstatusline executable exists
  - Check file type: `file result/bin/ccstatusline`
  - Test executable bit: `test -x result/bin/ccstatusline && echo "✓ Executable"`

- [ ] 3.4: Validate build quality (AC E.3-4)
  - Check runtime dependencies: `nix-store -q --references result/`
  - Expected: nodejs runtime + ccstatusline package
  - Verify metadata: `nix eval .#packages.aarch64-darwin.ccstatusline.meta --json | jq '.description, .homepage, .license, .mainProgram'`
  - Confirm all metadata fields populated

**Acceptance Criteria Covered:** AC D (auto-discovery), AC E (build quality)

---

### Task 4: Integration and Dendritic Compatibility (AC F-G)

**Objective:** Test module consumption and validate dendritic architecture integration

**Estimated Time:** 45 minutes

**Subtasks:**

- [ ] 4.1: Test module consumption (AC F.1-2)
  - Edit `~/projects/nix-workspace/test-clan/modules/home/ai/claude-code/default.nix`
  - Add/update settings: `programs.claude-code.settings.statusLine = { type = "command"; command = "${pkgs.ccstatusline}/bin/ccstatusline"; padding = 0; };`
  - Verify pkgs.ccstatusline resolves without errors
  - Check for infinite recursion or evaluation failures

- [ ] 4.2: Build home-manager activation package (AC F.3)
  - Execute: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`
  - Verify build completes successfully
  - Troubleshoot any module evaluation errors

- [ ] 4.3: Verify ccstatusline in activation closure (AC F.4)
  - Execute: `nix-store -q --references result/ | grep ccstatusline`
  - Expected output: `/nix/store/...-ccstatusline-0.1.0`
  - Confirm package properly integrated into home-manager closure

- [ ] 4.4: Validate dendritic compatibility (AC G)
  - **Check 1:** Package definition NOT a flake-parts module (just derivation)
  - **Check 2:** Package EXPORT via modules/nixpkgs.nix flake module
  - **Check 3:** Package CONSUMPTION in claude-code/default.nix dendritic module
  - **Check 4:** NO specialArgs needed (pkgs available automatically)
  - **Check 5:** import-tree and pkgs-by-name don't conflict (`nix flake check` passes)
  - **Check 6:** Pattern matches drupol-dendritic-infra (side-by-side comparison)
  - Document all 6 checks in Dev Notes

**Acceptance Criteria Covered:** AC F (module consumption), AC G (dendritic compatibility)

---

### Task 5: Documentation (AC H-I)

**Objective:** Document infra migration path and create comprehensive tutorial

**Estimated Time:** 1 hour 15 minutes

**Subtasks:**

- [ ] 5.1: Document infra migration path (AC H)
  - Create table with 4 packages: ccstatusline, atuin-format, markdown-tree-parser, starship-jj
  - List current locations (overlays/packages/) and target locations (pkgs/by-name/)
  - Provide effort estimates per package
  - Document callPackage signature verification
  - Assess migration risk (LOW - directory restructuring only)
  - Add to Dev Notes section

- [ ] 5.2: Create Section 13.1 in test-clan-validated-architecture.md (AC I.1)
  - Open `~/projects/nix-workspace/test-clan/docs/test-clan-validated-architecture.md`
  - Create new section: "## 13.1 Custom Package Overlays with pkgs-by-name Pattern"
  - Structure: Pattern Overview + Example + Migration Guide + References

- [ ] 5.3: Write pattern overview (AC I.2)
  - Document pkgs-by-name-for-flake-parts architecture
  - Explain directory structure (RFC 140 compliance)
  - Detail integration steps (flake input → module import → perSystem config)
  - List pattern benefits (auto-discovery, zero boilerplate, dendritic compatible)
  - Reference drupol as PRIMARY pattern source

- [ ] 5.4: Write ccstatusline complete example (AC I.3)
  - Include full package.nix derivation (85 lines from infra)
  - Provide build commands with expected outputs
  - Show module consumption example (claude-code integration)
  - Document integration validation commands
  - Add troubleshooting notes if needed

- [ ] 5.5: Write infra migration guide (AC I.4-5)
  - Document current state (overlays/packages/ + lib.packagesFromDirectoryRecursive)
  - Document target state (pkgs/by-name/ + pkgs-by-name-for-flake-parts)
  - Provide migration steps (7 steps from flake input to cleanup)
  - Include effort estimate (2.5-3 hours total)
  - Add risk assessment (LOW - proven pattern)
  - Reference drupol (PRIMARY), gaetanlepage (compatibility), external links

**Acceptance Criteria Covered:** AC H (infra migration), AC I (documentation)

---

**Total Task Effort:** 2-3 hours (aligns with AC estimates)

---

## Dev Notes

### Architectural Context

**Three-Layer Pattern Architecture:**

This story validates a critical architectural pattern with strict layer separation.
Understanding these layers prevents common pitfalls (infinite recursion, unclear code placement).

**Layer 1 - Package Definition (pkgs/by-name/):**
- **Purpose:** Define Nix derivations for custom packages
- **Location:** `pkgs/by-name/<first-2-chars>/<package-name>/package.nix`
- **Content:** Standard Nix expressions using callPackage signature
- **Example:**
  ```nix
  { lib, buildNpmPackage, fetchzip, jq, nix-update-script }:
  buildNpmPackage (finalAttrs: {
    pname = "ccstatusline";
    version = "0.1.0";
    # ... derivation details
  })
  ```
- **Rules:**
  - NO flake-parts imports
  - NO module system usage
  - NO self-references to other layers
  - Just pure Nix derivations
- **Why:** Isolates package logic from build system mechanics

**Layer 2 - Package Export (modules/nixpkgs.nix):**
- **Purpose:** Export packages to flake outputs and make available in pkgs namespace
- **Location:** `modules/nixpkgs.nix` (flake-parts module)
- **Content:** Import pkgs-by-name-for-flake-parts, configure pkgsDirectory
- **Example:**
  ```nix
  { inputs, ... }:
  {
    imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];

    perSystem = { ... }: {
      pkgsDirectory = ../../pkgs/by-name;
    };
  }
  ```
- **Rules:**
  - NO package definitions here
  - Only export configuration
  - Uses pkgs-by-name-for-flake-parts flake module
  - Configures auto-discovery
- **Why:** Separates package definitions from export mechanism

**Layer 3 - Package Consumption (dendritic modules):**
- **Purpose:** Use packages in home-manager/NixOS configurations
- **Location:** Any dendritic module (e.g., `modules/home/ai/claude-code/default.nix`)
- **Content:** References to `pkgs.<package-name>`
- **Example:**
  ```nix
  { pkgs, ... }:
  {
    programs.claude-code.settings.statusLine = {
      command = "${pkgs.ccstatusline}/bin/ccstatusline";
    };
  }
  ```
- **Rules:**
  - NO package definitions
  - NO export configuration
  - Just consumption via pkgs.*
  - Standard module signature
- **Why:** Keeps configuration modules focused on configuration, not packaging

**Critical Constraint:** These layers are **orthogonal** with **zero overlap**.
- Prevents infinite recursion (common overlay mistake)
- Clear separation of concerns (define vs export vs consume)
- Matches dendritic philosophy (one concern per file)
- Enables auto-discovery (no manual wiring)

### pkgs-by-name-for-flake-parts Pattern (drupol)

**Pattern Source:** drupol-dendritic-infra (PRIMARY reference)
- Repository: `~/projects/nix-workspace/drupol-dendritic-infra/`
- Production usage: 9 custom packages
- Proven stable in production environment

**Pattern Architecture:**

1. **Directory Structure (RFC 140 Compliance):**
   ```
   pkgs/
   └── by-name/
       ├── cc/
       │   └── ccstatusline/
       │       └── package.nix
       ├── at/
       │   └── atuin-format/
       │       └── package.nix
       └── ma/
           └── markdown-tree-parser/
               └── package.nix
   ```
   - First 2 characters of package name = subdirectory
   - Package name = next subdirectory
   - package.nix = derivation file (standard callPackage)

2. **Auto-Discovery Mechanism:**
   - Uses `lib.packagesFromDirectoryRecursive` under the hood
   - SAME function as infra currently uses
   - Scans pkgs/by-name/ directory recursively
   - Exports all package.nix files found
   - No manual package lists needed

3. **Integration Pattern:**
   ```nix
   # flake.nix
   inputs.pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";

   # modules/nixpkgs.nix
   { inputs, ... }:
   {
     imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];
     perSystem = { ... }: {
       pkgsDirectory = ../../pkgs/by-name;
     };
   }
   ```

4. **Export Behavior:**
   - Packages export to `packages.<system>.<package-name>`
   - Available as `pkgs.<package-name>` in all modules
   - No specialArgs configuration needed
   - Works with dendritic import-tree (orthogonal namespaces)

**Why This Pattern:**
- **Same underlying function:** infra uses `lib.packagesFromDirectoryRecursive`, pkgs-by-name-for-flake-parts uses same
- **nixpkgs convention:** RFC 140 compliance (future-proof)
- **Zero boilerplate:** Just set pkgsDirectory option
- **Production proven:** drupol (9 packages), gaetanlepage (50+ packages)
- **Dendritic compatible:** No conflicts with import-tree or module system

### infra Migration Architecture

**Current State (infra repository):**

**Location:** `~/projects/nix-workspace/infra/overlays/packages/`

**Package Inventory:**
1. `ccstatusline.nix` (85 lines, npm package, Claude Code status line)
2. `atuin-format/` (directory package, rust, Atuin history formatter)
3. `markdown-tree-parser.nix` (rust package, markdown parsing)
4. `starship-jj.nix` (rust package, Starship prompt with jujutsu)

**Current Mechanism:**
- Auto-discovery: `lib.packagesFromDirectoryRecursive`
- Export: Custom overlay configuration in flake.nix
- Consumption: Available via pkgs.* in all modules

**Target State (dendritic + pkgs-by-name):**

**Location:** `~/projects/nix-workspace/infra/pkgs/by-name/`

**Package Inventory (same 4 packages):**
1. `pkgs/by-name/cc/ccstatusline/package.nix`
2. `pkgs/by-name/at/atuin-format/package.nix`
3. `pkgs/by-name/ma/markdown-tree-parser/package.nix`
4. `pkgs/by-name/st/starship-jj/package.nix`

**Target Mechanism:**
- Auto-discovery: `lib.packagesFromDirectoryRecursive` (via pkgs-by-name-for-flake-parts)
- Export: pkgs-by-name-for-flake-parts flake module
- Consumption: Available via pkgs.* (unchanged)

**Migration Impact Analysis:**

**Code Changes Required:** ZERO
- Package derivations use standard callPackage signatures
- No custom overlay arguments needed
- Same builders (buildNpmPackage, rustPlatform)
- Same auto-discovery function

**Directory Restructuring Required:** YES
- Move files from `overlays/packages/` to `pkgs/by-name/`
- Follow RFC 140 naming (first-2-chars/package-name/package.nix)
- Convert directory packages to single package.nix files (atuin-format)

**Configuration Changes Required:** MINIMAL
- Add pkgs-by-name-for-flake-parts flake input
- Import flake module in modules/nixpkgs.nix (or equivalent)
- Set pkgsDirectory in perSystem
- Remove old overlay configuration

**Migration Effort Estimate:**
- ccstatusline: ✅ Validated in Story 1.10D (0 min in Epic 2-6)
- atuin-format: 30 min (directory → file, test build)
- markdown-tree-parser: 15 min (file move, test build)
- starship-jj: 15 min (file move, test build)
- Infrastructure setup: 20 min (flake input, module config, cleanup)
- Testing and validation: 30 min (all packages, integration tests)
- **Total: 2.5-3 hours**

**Risk Assessment: LOW**
- Reasoning:
  - Same underlying function (lib.packagesFromDirectoryRecursive)
  - No code changes to package derivations
  - Proven pattern (drupol production, gaetanlepage compatibility)
  - ccstatusline validation in Story 1.10D de-risks migration
- Mitigation:
  - Story 1.10D validates pattern before Epic 2-6 migration
  - test-clan serves as reference implementation
  - Comprehensive documentation (Section 13.1)

### Testing Standards

**Quality Gate 1: Infrastructure Setup (AC A-B)**

**Objective:** Verify pkgs-by-name-for-flake-parts integrated correctly

**Validation Command:**
```bash
nix flake check
```

**Pass Criteria:**
- ✅ No evaluation errors
- ✅ No infinite recursion
- ✅ Module loads successfully
- ✅ pkgsDirectory path resolved correctly

**Troubleshooting:**
- Evaluation error: Check flake input URL, verify inputs parameter in modules/nixpkgs.nix
- Path error: Verify pkgsDirectory relative path correct from modules/ directory
- Module import error: Ensure flakeModule attribute exists in inputs.pkgs-by-name-for-flake-parts

---

**Quality Gate 2: Build Validation (AC C-D-E)**

**Objective:** Verify ccstatusline package builds and exports correctly

**Validation Commands:**
```bash
# Build package
nix build .#ccstatusline

# Verify executable
test -x result/bin/ccstatusline && echo "✓ Executable"

# Check runtime dependencies
nix-store -q --references result/
# Expected: nodejs + ccstatusline package paths
```

**Pass Criteria:**
- ✅ Build completes without errors
- ✅ Executable exists at result/bin/ccstatusline
- ✅ File permissions correct (executable bit set)
- ✅ Runtime dependencies correct (nodejs + package)
- ✅ Package metadata populated (description, homepage, license, mainProgram)

**Troubleshooting:**
- Build failure: Check package.nix syntax, verify callPackage signature
- Missing executable: Review installPhase in derivation
- Wrong dependencies: Verify buildInputs and propagatedBuildInputs
- Missing metadata: Add meta attribute with required fields

---

**Quality Gate 3: Integration Validation (AC F-G)**

**Objective:** Verify ccstatusline integrates with dendritic modules and home-manager

**Validation Commands:**
```bash
# Build home-manager activation
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage

# Verify package in closure
nix-store -q --references result/ | grep ccstatusline
# Expected: /nix/store/...-ccstatusline-0.1.0
```

**Pass Criteria:**
- ✅ pkgs.ccstatusline resolves in module context
- ✅ home-manager build completes successfully
- ✅ ccstatusline package in activation closure
- ✅ No specialArgs needed (pkgs available automatically)
- ✅ All 6 dendritic compatibility checks pass:
  1. Package definition NOT a flake-parts module
  2. Package EXPORT via modules/nixpkgs.nix
  3. Package CONSUMPTION in dendritic module
  4. NO specialArgs pass-thru needed
  5. import-tree + pkgs-by-name coexist
  6. Pattern matches drupol-dendritic-infra

**Troubleshooting:**
- pkgs.ccstatusline undefined: Verify pkgsDirectory configured, check auto-discovery
- Infinite recursion: Ensure package.nix doesn't reference pkgs.ccstatusline
- Module evaluation error: Check module signature, verify pkgs parameter available
- Package not in closure: Verify module actually uses package (not commented out)

---

**Quality Gate 4: Documentation Review (AC H-I)**

**Objective:** Verify comprehensive tutorial documentation created

**Validation Criteria:**
- ✅ Section 13.1 exists in test-clan-validated-architecture.md
- ✅ Contains pattern overview (architecture, integration, benefits)
- ✅ Includes complete ccstatusline example (derivation + build + integration)
- ✅ Documents infra migration guide (table + steps + effort + risk)
- ✅ References included (drupol PRIMARY, gaetanlepage compatibility, external links)

**Content Verification:**
- Pattern overview: pkgs-by-name-for-flake-parts architecture explained clearly
- Example completeness: Full derivation code + build commands + consumption example
- Migration guide: All 4 infra packages documented with paths and effort
- Tutorial quality: Comprehensive enough for Epic 2-6 developers to execute migration

**Pass Criteria:**
- ✅ Documentation comprehensive (self-contained tutorial)
- ✅ Code examples correct and tested
- ✅ Migration path clear and actionable
- ✅ References accurate (local paths + external URLs)

---

### Project Structure Notes

**test-clan Repository Layout (Story 1.10D additions):**

```
test-clan/
├── flake.nix                                    # ADD: pkgs-by-name-for-flake-parts input
├── modules/
│   └── nixpkgs.nix                              # UPDATE: Import flake module, set pkgsDirectory
├── pkgs/                                        # NEW: Custom packages directory
│   └── by-name/                                 # NEW: RFC 140 compliant structure
│       └── cc/                                  # NEW: First 2 chars ("cc" from "ccstatusline")
│           └── ccstatusline/                    # NEW: Package directory
│               └── package.nix                  # NEW: Copy from infra (85 lines, npm pattern)
├── modules/home/ai/claude-code/
│   └── default.nix                              # UPDATE: Consume via pkgs.ccstatusline
└── docs/
    └── test-clan-validated-architecture.md     # UPDATE: Add Section 13.1
```

**File Change Summary:**

**New Files:**
- `pkgs/by-name/cc/ccstatusline/package.nix` (85 lines, copied from infra)

**Modified Files:**
- `flake.nix` (add pkgs-by-name-for-flake-parts input)
- `modules/nixpkgs.nix` (import flake module, configure pkgsDirectory)
- `modules/home/ai/claude-code/default.nix` (consume pkgs.ccstatusline)
- `docs/test-clan-validated-architecture.md` (add Section 13.1)

**Integration Points:**

1. **flake.nix → modules/nixpkgs.nix:**
   - flake.nix provides pkgs-by-name-for-flake-parts input
   - modules/nixpkgs.nix imports flake module
   - Connection: inputs parameter threading

2. **modules/nixpkgs.nix → pkgs/by-name/:**
   - modules/nixpkgs.nix configures pkgsDirectory
   - Points to ../../pkgs/by-name (relative path)
   - Connection: perSystem configuration

3. **pkgs/by-name/ → packages.<system>.*:**
   - Auto-discovery scans pkgs/by-name/
   - Exports package.nix files to flake outputs
   - Connection: lib.packagesFromDirectoryRecursive

4. **packages.<system>.* → pkgs.*:**
   - Flake outputs available as pkgs attributes
   - Accessible in all dendritic modules
   - Connection: nixpkgs overlay mechanism

5. **pkgs.* → modules/home/ai/claude-code/:**
   - Dendritic module references pkgs.ccstatusline
   - home-manager includes package in activation
   - Connection: standard module signature { pkgs, ... }

### Quick Reference

**Target Repository:**
```bash
~/projects/nix-workspace/test-clan/
```

**Key Commands:**

```bash
# Build ccstatusline package
cd ~/projects/nix-workspace/test-clan
nix build .#ccstatusline

# Verify package exports
nix flake show | grep ccstatusline
nix eval .#packages.aarch64-darwin.ccstatusline.meta.description

# Test module consumption
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage

# Verify in closure
nix-store -q --references result/ | grep ccstatusline

# Eval package metadata
nix eval .#packages.aarch64-darwin.ccstatusline.meta --json | jq
```

**Source Files:**

```bash
# infra ccstatusline derivation (source)
~/projects/nix-workspace/infra/overlays/packages/ccstatusline.nix

# test-clan target location
~/projects/nix-workspace/test-clan/pkgs/by-name/cc/ccstatusline/package.nix

# Module consumption
~/projects/nix-workspace/test-clan/modules/home/ai/claude-code/default.nix

# Documentation
~/projects/nix-workspace/test-clan/docs/test-clan-validated-architecture.md
```

**Reference Repositories:**

```bash
# drupol-dendritic-infra (PRIMARY pattern reference)
~/projects/nix-workspace/drupol-dendritic-infra/
# Key files:
# - flake.nix (pkgs-by-name-for-flake-parts input)
# - modules/nixpkgs.nix (module import + perSystem config)
# - pkgs/by-name/ (9 packages in production)

# gaetanlepage-dendritic-nix-config (compatibility proof)
~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/
# Key evidence:
# - pkgs/by-name/ (50+ packages)
# - Comprehensive dendritic usage
# - Proves pattern scales

# infra overlays (migration source)
~/projects/nix-workspace/infra/overlays/
# Key files:
# - packages/ccstatusline.nix (production derivation)
# - packages/atuin-format/ (directory package example)
# - packages/markdown-tree-parser.nix
# - packages/starship-jj.nix
```

**External References:**

- **pkgs-by-name-for-flake-parts:** https://github.com/drupol/pkgs-by-name-for-flake-parts
  - Flake module source
  - Usage documentation
  - Pattern explanation

- **nixpkgs RFC 140:** https://github.com/NixOS/rfcs/pull/140
  - pkgs/by-name convention specification
  - Directory structure rationale
  - Migration guide

- **Dendritic Overlay Pattern Review:** (internal research document)
  - Comprehensive review of 8 repositories
  - Pattern comparison and recommendation
  - infra compatibility analysis

**Estimated Effort:** 2-3 hours

**Risk Level:** Low
- Proven pattern (drupol production, gaetanlepage compatibility)
- infra compatible (same underlying function)
- Production-ready derivation (no development needed)
- Clear three-layer architecture (prevents confusion)

---

## Dev Agent Record

### Context Reference

- Story Context XML: `docs/notes/development/work-items/1-10d-validate-custom-package-overlays.context.xml` (To be created via story-context workflow)

### Agent Model Used

- **Model**: [To be recorded during implementation]
- **Sessions**: [To be recorded during implementation]

### Debug Log References

[To be recorded during implementation]

### Completion Notes List

[To be recorded during implementation]

### File List

[To be recorded during implementation]

---

## Learnings

<!-- Post-implementation insights, architectural discoveries, pattern validations -->
<!-- This section will be populated during implementation or Party Mode checkpoint -->

---

## Change Log

### 2025-11-16 - Story Created

- Story 1.10D work item created via create-story workflow
- Epic reordering decision (2025-11-16): NEW Story 1.10D (overlay validation) blocks RENAMED Story 1.10E (feature enablement)
- Comprehensive story definition based on Epic 1 lines 1127-1362 (236 lines)
- 9 acceptance criteria across infrastructure, implementation, validation, documentation
- 5 task groups with detailed subtasks mapped to ACs
- pkgs-by-name-for-flake-parts pattern from Dendritic Overlay Pattern Review
- drupol-dendritic-infra as PRIMARY reference (9 packages proven in production)
- gaetanlepage-dendritic-nix-config as compatibility proof (50+ packages)
- infra compatibility assessment: ✅ SAFE TO MIGRATE (directory restructuring only, no code changes)
- ccstatusline test case: Production-ready derivation (85 lines), settings pre-configured (175 lines)
- Strategic value: Completes Epic 1 architectural coverage (95%), removes Epic 2-6 blocker (overlay uncertainty)
- Work item structure: 10 sections following Story 1.10C template
- Documentation scope: Comprehensive tutorial (Section 13.1: pattern + example + migration guide)
- Quality gates: 4 gates with explicit validation commands
- Three-layer architecture documented: Definition (pkgs/by-name/) → Export (modules/nixpkgs.nix) → Consumption (dendritic modules)
- Implementation guidance: Detailed (exact flake.nix snippets, directory structure, command sequences)
- Total estimated effort: 2-3 hours (matches epic estimate)

---

## Senior Developer Review (AI)

**Reviewer:** [To be assigned]
**Date:** [To be recorded]
**Review Outcome:** [To be determined]
**Justification:** [To be provided]

[Review content to be generated after implementation via code-review workflow]
