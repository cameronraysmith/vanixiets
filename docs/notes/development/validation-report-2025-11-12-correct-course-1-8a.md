# Sprint Change Proposal: Story 1.8A - Extract Portable Home-Manager Modules

**Date:** 2025-11-12
**Workflow:** correct-course (Sprint Change Management)
**Scope:** Minor (single story insertion within Epic 1)
**Urgency:** CRITICAL PATH - Blocks Story 1.9 and all Epic 1 progression

---

## Issue Summary

During Story 1.8 implementation (migrate blackphos darwin config to test-clan), we successfully validated the dendritic + clan pattern BUT discovered a critical architectural gap that blocks Epic 1 progression:

**Gap Identified:** User home-manager configurations are inline in machine modules (not reusable across platforms).

**Why This Blocks Epic 1:**
- Story 1.8: blackphos (darwin) has crs58 config INLINE in machine module
- Story 1.9: cinnabar (NixOS) needs crs58 config → would require DUPLICATION
- Story 1.10: Network validation across blackphos + cinnabar (same user on both) → BLOCKED
- Epic 2+: 4 more machines all need crs58 → 6 duplicate configs total = maintenance nightmare
- Epic 1 goal: Architectural validation must prove cross-platform user config sharing works

**This is a Feature Regression, Not New Requirement:**

Our infra repo (nixos-unified) ALREADY supports modular home-manager configs that are reused across machines.
The test-clan prototype LOST this capability by implementing inline configs in Story 1.8.
We need to restore this proven pattern while adapting it to dendritic + clan architecture.

**Evidence:**
- blackphos inline configs: `modules/machines/darwin/blackphos/default.nix` lines 127-183
- infra proven pattern: `modules/home/` directory with modular, reusable configs
- Story 1.8 completion notes (line 841-861): Gap identified, solution proposed

---

## Impact Analysis

### Epic Impact

**Epic 1 (Phase 0 - Architectural Validation):**
- Story 1.8: Configuration builds successfully, gap identified ✅
- **Story 1.8A (NEW)**: Extract portable home modules **← INSERT HERE**
- Story 1.9: BLOCKED until 1.8A complete (needs crs58 module)
- Story 1.10: BLOCKED until 1.8A complete (needs shared config)
- Epic 1 Goal Update: Home-manager modularity IS part of architectural validation

**Epic 2-6 (Production Migration):**
- All future stories require portable user configs (DRY principle)
- Pattern validated in Story 1.8A enables Epic 2-6 progression
- No changes to epic scope, only dependency clarification

**Epic 7 (Cleanup):**
- Unaffected (occurs after all migrations complete)

### Artifact Conflicts and Updates

**epics.md Updates:**
- ✅ Story 1.8: Add status update noting gap identified
- ✅ Story 1.8A: INSERT between Stories 1.8 and 1.9
- ✅ Story 1.9: Mark as blocked by 1.8A
- ✅ Epic 1 narrative: Add cross-platform user config sharing to success criteria

**architecture.md Updates:**
- ✅ NEW Pattern: "Portable Home-Manager Modules with Dendritic Integration"
- ✅ Document three integration modes (darwin, NixOS, standalone)
- ✅ Show namespace exports and imports
- ✅ Capture Story 1.8 lesson: inline configs are anti-pattern
- ✅ Document username-only vs username@hostname naming
- ✅ Show clan compatibility (users per machine, configs modular)

**PRD.md Updates:**
- ℹ️ OPTIONAL: Cross-platform user config sharing already implicit (home-manager mentioned)
- If explicit requirement needed: Add to Phase 0 success criteria
- Recommendation: Document in completion notes rather than PRD revision

**sprint-status.yaml Updates:**
- ✅ Story 1.8: Status remains `review`, add gap identification note
- ✅ Story 1.8A: Add as `ready-for-dev` with critical path notation
- ✅ Story 1.9: Add `blocked by 1.8A` note

---

## Recommended Approach

**Selected Path: Option 1 - Direct Adjustment (Story 1.8A Insertion)**

**Rationale:**
- **Low Effort**: 2-3 hours (pattern proven in infra, well-scoped refactoring)
- **Low Risk**: Configuration already builds, just reorganizing
- **High Value**: Unblocks Epic 1-6 progression, enables DRY principle
- **Architectural Requirement**: Epic 1 must validate cross-platform user config sharing
- **Proven Pattern**: infra already does this successfully

**Alternatives Considered:**

**Option 2 - Rollback Story 1.8**: NOT VIABLE
- Would lose 9 commits of validated multi-user darwin config
- Forward path (Story 1.8A) is simpler than rollback + redo
- Story 1.8 is correctly implemented, just incomplete

**Option 3 - MVP Review**: NOT VIABLE
- MVP still achievable with Story 1.8A insertion
- This is capability restoration, not scope expansion
- No need for MVP reduction

---

## Story 1.8A Scope

**Objective:** Extract crs58 and raquel home configs from blackphos into portable modules that export to dendritic namespace and support three integration modes.

**Implementation:**
1. Extract crs58 home config from blackphos into `modules/home/users/crs58/default.nix`
2. Extract raquel home config into `modules/home/users/raquel/default.nix`
3. Export to dendritic namespace: `flake.modules.homeManager."users/crs58"`
4. Refactor blackphos to import shared modules (validate zero regression)
5. Expose `homeConfigurations.{crs58,raquel}` in flake for standalone use
6. Validate three usage patterns:
   - `nh darwin switch . -H blackphos` (integrated darwin + home)
   - `nh os switch . -H cinnabar` (integrated nixos + home, Story 1.9 prep)
   - `nh home switch . -c crs58` (standalone home on any nix machine)

**Acceptance Criteria:**
- AC1: crs58 module exported to `flake.modules.homeManager."users/crs58"`
- AC2: raquel module exported to `flake.modules.homeManager."users/raquel"`
- AC3: blackphos refactored to import shared modules (builds with zero regression)
- AC4: `homeConfigurations.crs58` exposed in flake
- AC5: `homeConfigurations.raquel` exposed in flake
- AC6: `nh darwin switch . -H blackphos` works (integrated darwin validation)
- AC7: `nh home switch . -c crs58` works (standalone validation)
- AC8: Pattern documented for cinnabar reuse in Story 1.9 and Epic 2+ production

**Key Architectural Requirements:**
- Must preserve dendritic flake-parts pattern (namespace exports, import-tree auto-discovery)
- Must maintain clan-core compatibility (users defined per machine, no clan-specific user management)
- Must support all three home-manager integration modes (darwin module, nixos module, standalone)
- Single source of truth: same user module file works in all three contexts
- Username-only naming for standalone configs (crs58, not crs58@hostname) for portability

---

## MVP Impact Assessment

**MVP Scope:** No change

**Why:** This is restoration of existing infra capability, not new feature.
The infra repo already supports modular home-manager configs.
Story 1.8A adapts this proven pattern to dendritic + clan architecture.

**Timeline Impact:** +2-3 hours (minimal delay, well within Epic 1 timeline)

---

## Implementation Handoff

**Change Scope:** Minor (single story insertion within epic)

**Handoff To:** Development team

**Deliverables:**
1. ✅ Story 1.8A file: `1-8a-extract-portable-home-manager-modules.md` (ready-for-dev)
2. ✅ epics.md updates: Story 1.8A inserted with blocking relationships
3. ✅ architecture.md updates: Portable home-manager pattern documented
4. ✅ sprint-status.yaml updates: Story 1.8A added, Story 1.9 blocked status
5. ⏭️ PRD.md updates: Optional (cross-platform already implicit)

**Next Steps:**
1. Developer reviews Story 1.8A file
2. Developer implements in test-clan repository (2-3 hours)
3. Developer validates zero regression (package diff)
4. Developer commits with atomic message
5. Story 1.8A marked `done`, Story 1.9 unblocked

**Success Criteria:**
- Story 1.8A complete (all ACs satisfied)
- Test harness passes (validation coverage added)
- Pattern documented for Story 1.9 reuse
- Story 1.9 progression unblocked

---

## Decision Record

**Checklist Completion:** All 6 sections of correct-course workflow executed (2025-11-12)

**Decision:** **APPROVED** - Proceed with Story 1.8A insertion

**Justification:**
- ✅ Low effort, low risk, high value
- ✅ Restores proven capability (not experimental)
- ✅ Unblocks Epic 1-6 critical path
- ✅ Aligns with Epic 1 architectural validation goal
- ✅ Pattern documented for future reuse

**Risk Assessment:**
- **Technical Risk**: Low (refactoring only, builds validated)
- **Timeline Risk**: Low (+2-3 hours, minimal delay)
- **Architectural Risk**: Low (proven pattern from infra)
- **Operational Risk**: None (test-clan validation, no production impact)

**Alternatives Rejected:**
- Rollback Story 1.8: Too costly, forward path simpler
- Skip 1.8A: Would create 6 duplicate configs (maintenance nightmare)
- MVP reduction: Not needed, capability restoration not scope expansion

---

## Validation Results

**Package List Comparison Strategy:**
```bash
# Before Story 1.8A (blackphos inline configs)
nix-store -qR $(nix build .#darwinConfigurations.blackphos.system --no-link --print-out-paths) | sort > pre-1.8a.txt

# After Story 1.8A (imported from namespace)
nix-store -qR $(nix build .#darwinConfigurations.blackphos.system --no-link --print-out-paths) | sort > post-1.8a.txt

# Diff analysis
diff pre-1.8a.txt post-1.8a.txt
# Expected: Only derivation paths change, zero functional regressions
```

**Test Harness Coverage:**
- Validation test: Home module exports exist in namespace
- Validation test: homeConfigurations exposed in flake
- Integration test: blackphos builds successfully
- Regression test: Package list comparison (AC4)

---

## References

**Story Files:**
- Story 1.8: `1-8-migrate-blackphos-from-infra-to-test-clan.md` (lines 771-884 completion notes)
- Story 1.8A: `1-8a-extract-portable-home-manager-modules.md` (NEW, comprehensive context)

**Architecture:**
- Pattern documented: `architecture.md` Pattern 2 (Portable Home-Manager Modules)
- infra reference: `~/projects/nix-workspace/infra/modules/home/`
- test-clan validated: Stories 1.1-1.7 (dendritic pattern proven)

**Repositories:**
- test-clan: `~/projects/nix-workspace/test-clan/` (validation environment)
- infra: `~/projects/nix-workspace/infra/` (production, nixos-unified)

**nh CLI Usage:**
- Darwin integrated: `nh darwin switch . -H blackphos`
- NixOS integrated: `nh os switch . -H cinnabar` (Story 1.9)
- Standalone home: `nh home switch . -c crs58`

---

## Workflow Metadata

**Workflow:** correct-course (Sprint Change Management)
**Executed:** 2025-11-12
**Agent:** claude-sonnet-4-5-20250929
**User:** Dev (expert skill level)
**Mode:** Incremental (collaborative refinement)

**Checklist Results:**
- Section 1: Trigger and Context ✅
- Section 2: Epic Impact ✅
- Section 3: Artifact Conflicts ✅
- Section 4: Path Forward ✅
- Section 5: Proposal Components ✅
- Section 6: Final Review ✅

**Approval:** Awaiting user confirmation to proceed with implementation

---

_Generated by correct-course workflow v1.0_
_Date: 2025-11-12_
_For: infra project (Epic 1 - Phase 0)_
