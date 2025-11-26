# Story 2.11: Test harness and CI validation

Status: drafted

## Story

As a system administrator,
I want to validate and update the test harness and CI workflow for the dendritic flake-parts + clan architecture,
so that infra repository has continuous validation aligned with the 4-host fleet (stibnite, blackphos, cinnabar, electrum).

## Context

**Epic 2 Phase 4 Story 1 (Infrastructure Validation):**

This is the first story in Epic 2 Phase 4. Stories 2.1-2.10 (Phases 1-3) are complete. All 4 hosts (stibnite, blackphos, cinnabar, electrum) are now deployed from infra clan-01 branch. Story 2.11 validates the test harness and CI workflow align with the new dendritic flake-parts + clan architecture.

**Story Type: VALIDATION + FIX (CI Alignment)**

This story addresses CI/test infrastructure that drifted from actual repository state during Phase 1-3 migrations:
- Orphaned CI matrix entries for configs that don't exist
- Missing CI coverage for actual hosts (cinnabar, electrum)
- Home config testing expectations misaligned with actual users

**Execution Model: HYBRID (AI-Heavy with User CI Monitoring)**

- **[AI]** tasks: File edits, nix flake check, CI analysis, git commits
- **[USER]** tasks: Monitor GitHub Actions workflow run, report results
- **[HYBRID]** tasks: AI triggers CI, user monitors long-running jobs

**Estimated Effort:** 4-6 hours

**Risk Level:** MEDIUM (CI changes could break main branch if not careful)

## Acceptance Criteria

### AC1: Validate existing checks pass locally

Confirm 20+ implemented checks pass with `nix flake check`.

**Verification:**
```bash
# Run all checks
nix flake check

# Expected: 20+ checks pass
# - nix-unit.nix: 11 tests
# - validation.nix: 7 checks
# - integration.nix: 2 tests
# - performance.nix: stubs (acceptable to defer)
```

### AC2: Add stibnite to explicit validation

Ensure stibnite darwin config has explicit check coverage (not just via clan inventory TC-003).

**Verification:**
```bash
# Check for stibnite-specific validation
grep -r "stibnite" modules/checks/

# Expected: Explicit stibnite darwin build validation check
```

### AC3: Fix CI matrix orphans

Remove non-existent configurations from ci.yaml matrix.

**Verification:**
```bash
# Before: ci.yaml contains these invalid entries
# - blackphos-nixos (doesn't exist - blackphos is darwin)
# - stibnite-nixos (doesn't exist - stibnite is darwin)
# - orb-nixos (doesn't exist - removed)

# After: these entries removed from CI matrix
grep -E "(blackphos-nixos|stibnite-nixos|orb-nixos)" .github/workflows/ci.yaml
# Expected: No matches
```

### AC4: Add VPS builds to CI

Add cinnabar and electrum nixosConfigurations to CI build matrix.

**Verification:**
```bash
# Verify nixos build matrix includes VPS hosts
grep -E "(cinnabar|electrum)" .github/workflows/ci.yaml

# Expected: Both hosts in nixos build matrix
```

### AC5: Update home config testing

Align CI home config expectations with actual users (cameron, raquel, crs58).

**Verification:**
```bash
# Check home config matrix in CI
grep -E "home.*config" .github/workflows/ci.yaml -A 20

# Expected: cameron, raquel, crs58 (not runner@*)
```

### AC6: Preserve content-addressed job caching

Ensure new/modified jobs follow the `cached-ci-job` pattern with accurate `hash-sources` closures.

**Verification:**
```bash
# All build jobs should use cached-ci-job action
grep -A 10 "cached-ci-job" .github/workflows/ci.yaml

# Expected pattern per job:
# - uses: ./.github/actions/cached-ci-job
# - with hash-sources including relevant nix files
# - steps gated with if: steps.cache.outputs.should-run == 'true'
```

### AC7: Execute CI validation

Run `gh workflow run ci.yaml --ref clan-01` and verify all jobs pass.

**Verification:**
```bash
# Trigger CI
gh workflow run ci.yaml --ref clan-01

# Monitor status
gh run list --workflow=ci.yaml --branch=clan-01 -L 1

# Expected: All jobs pass (green checkmarks)
```

### AC8: Document test execution

Update or create testing documentation with current check inventory.

**Verification:**
- [ ] Check inventory documented in docs/notes/development/testing.md or similar
- [ ] 23+ checks enumerated with categories (nix-unit, validation, integration, performance)
- [ ] CI job structure documented

## Tasks / Subtasks

**Execution Mode Legend:**
- **[AI]** - Can be executed directly by Claude Code
- **[USER]** - Should be executed by human developer, report results back to chat
- **[HYBRID]** - AI prepares/validates, user executes interactive portions

---

### Task 1: Validate Existing Checks Locally (AC: #1) [AI]

- [ ] Run `nix flake check` and capture output
- [ ] Enumerate all passing checks
  - [ ] Document nix-unit.nix tests (11 expected)
  - [ ] Document validation.nix checks (7 expected)
  - [ ] Document integration.nix tests (2 expected)
  - [ ] Note performance.nix stubs (deferred, acceptable)
- [ ] Identify any failing checks
- [ ] Fix any blocking failures before proceeding

### Task 2: Audit CI Workflow for Orphans (AC: #3) [AI]

- [ ] Read .github/workflows/ci.yaml completely
- [ ] Identify orphaned matrix entries
  - [ ] `blackphos-nixos` - doesn't exist (darwin)
  - [ ] `stibnite-nixos` - doesn't exist (darwin)
  - [ ] `orb-nixos` - removed config
- [ ] Document line numbers for removal
- [ ] Verify no other orphans exist

### Task 3: Fix CI Matrix - Remove Orphans (AC: #3) [AI]

- [ ] Remove `blackphos-nixos` from nixos build matrix
- [ ] Remove `stibnite-nixos` from nixos build matrix
- [ ] Remove `orb-nixos` from any matrix
- [ ] Verify matrix syntax valid after changes

### Task 4: Add VPS Hosts to CI Matrix (AC: #4) [AI]

- [ ] Add `cinnabar` to nixos build matrix
- [ ] Add `electrum` to nixos build matrix
- [ ] Configure hash-sources for VPS builds
  - [ ] Include: `flake.nix flake.lock modules/**/*.nix configurations/**/*.nix`
- [ ] Ensure cached-ci-job pattern followed

### Task 5: Update Home Config Testing (AC: #5) [AI]

- [ ] Audit current home config matrix expectations
- [ ] Update to actual users: cameron, raquel, crs58
- [ ] Remove any runner@* placeholder expectations
- [ ] Verify home config builds match actual homeConfigurations

### Task 6: Add Stibnite Explicit Validation (AC: #2) [AI]

- [ ] Check if stibnite already has explicit check coverage
- [ ] If missing: add stibnite darwin build validation to modules/checks/validation.nix
- [ ] Pattern: similar to existing darwin config checks
- [ ] Verify check passes with `nix flake check`

### Task 7: Verify Cached-CI-Job Pattern (AC: #6) [AI]

- [ ] Audit all modified/new jobs for cached-ci-job usage
- [ ] Verify hash-sources are accurate for each job
  - [ ] Nixos builds: include all nix files affecting builds
  - [ ] Home config builds: include home-manager modules
- [ ] Verify gating pattern: `if: steps.cache.outputs.should-run == 'true'`
- [ ] Verify result marker creation on success

### Task 8: Execute CI Validation (AC: #7) [HYBRID]

- [ ] AI: Trigger CI with `gh workflow run ci.yaml --ref clan-01`
- [ ] AI: Capture run ID
- [ ] USER: Monitor GitHub Actions UI for job progress
- [ ] USER: Report any failures back to chat
- [ ] AI/USER: Fix any CI failures iteratively
- [ ] Confirm all jobs green

### Task 9: Document Test Inventory (AC: #8) [AI]

- [ ] Create or update docs/notes/development/testing.md
- [ ] Document check categories and counts
- [ ] Document CI workflow structure
- [ ] Reference key files:
  - [ ] modules/checks/nix-unit.nix
  - [ ] modules/checks/validation.nix
  - [ ] modules/checks/integration.nix
  - [ ] .github/workflows/ci.yaml

## Dev Notes

### Learnings from Previous Story

**From Story 2.10 (Status: done)**

- **Deployment successful**: electrum switched from test-clan to infra clan-01 on 2025-11-26
- **Zerotier peer preserved**: Network db4344343b14b903 operational
- **All peers connected**: cinnabar (4ms), blackphos (224ms), stibnite (118ms)
- **Infrastructure fix**: Added `rosetta-restart` command, fixed rosetta-builder SSH config
- **Phase 3 complete**: Both VPS machines (cinnabar, electrum) now deployed from infra clan-01

**All 4 hosts now on infra clan-01:**
| Host | Platform | Role | Status |
|------|----------|------|--------|
| stibnite | nix-darwin | crs58's workstation | Deployed Story 2.7 |
| blackphos | nix-darwin | raquel's workstation | Deployed Story 2.7 |
| cinnabar | nixos | Zerotier controller VPS | Deployed Story 2.9 |
| electrum | nixos | Zerotier peer VPS | Deployed Story 2.10 |

[Source: docs/notes/development/work-items/2-10-electrum-config-migration.md#Dev-Agent-Record]

### Reconnaissance Findings

**modules/checks/ Status (23 checks exist):**

| File | Count | Description |
|------|-------|-------------|
| nix-unit.nix | 11 tests | TC-001 to TC-021, regression/invariant/feature/type-safety |
| validation.nix | 7 checks | Home exports, naming conventions, terraform, secrets |
| integration.nix | 2 tests | VM boot tests for nixos machines |
| performance.nix | 3+ stubs | Not implemented, acceptable to defer |

**Gaps Identified:**
- stibnite missing from explicit validation (only via clan inventory TC-003)
- No darwin machine boot tests (only nixos VMs tested - acceptable limitation)

**ci.yaml Status (13 jobs, 1105 lines):**

| Issue | Description | Action |
|-------|-------------|--------|
| Orphaned: blackphos-nixos | Doesn't exist (darwin) | REMOVE from matrix |
| Orphaned: stibnite-nixos | Doesn't exist (darwin) | REMOVE from matrix |
| Orphaned: orb-nixos | Config removed | REMOVE from matrix |
| Missing: cinnabar | Not in CI build matrix | ADD to nixos matrix |
| Missing: electrum | Not in CI build matrix | ADD to nixos matrix |
| Home configs | Uses runner@* not actual users | UPDATE to cameron, raquel, crs58 |

**Working Correctly:**
- Cachix binary caching (cameronraysmith cache)
- Content-addressed job caching via `.github/actions/cached-ci-job`

### Content-Addressed Job Caching Pattern

**Critical for new jobs** - the CI uses `.github/actions/cached-ci-job` for job-level result caching based on input file closure hashing.

New/modified jobs MUST:
1. Call `cached-ci-job` action early (before expensive setup like setup-nix)
2. Specify accurate `hash-sources` globs (only files that affect job outcome)
3. For matrix jobs: include matrix values in `check-name` parameter
4. Gate expensive steps with `if: steps.cache.outputs.should-run == 'true'`
5. Create JSON result marker and save to Actions cache on success

**Example hash-sources for nix builds:**
```yaml
hash-sources: 'flake.nix flake.lock modules/**/*.nix configurations/**/*.nix justfile .github/actions/setup-nix/action.yml'
```

### Project Structure Notes

**Check Infrastructure:**
```
modules/checks/
├── default.nix       # Aggregates all checks
├── nix-unit.nix      # 11 nix-unit tests
├── validation.nix    # 7 validation checks
├── integration.nix   # 2 VM integration tests
└── performance.nix   # Stubs (deferred)
```

**CI Infrastructure:**
```
.github/
├── workflows/
│   └── ci.yaml       # Main CI workflow (13 jobs)
└── actions/
    ├── cached-ci-job/action.yaml  # Content-addressed caching
    └── setup-nix/action.yml       # Nix setup action
```

### References

**Source Documentation:**
- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md) - Story 2.11 definition (lines 266-301)
- [Architecture - Deployment](docs/notes/development/architecture/deployment-architecture.md) - CI/CD integration

**Key Files:**
- modules/checks/nix-unit.nix (11 tests)
- modules/checks/validation.nix (7 checks)
- modules/checks/integration.nix (2 tests)
- .github/workflows/ci.yaml (13 jobs, 1105 lines)
- .github/actions/cached-ci-job/action.yaml

**Predecessor Stories:**
- [Story 2.10](docs/notes/development/work-items/2-10-electrum-config-migration.md) - Electrum migration (Phase 3 complete)

**Successor Stories:**
- Story 2.12 - Consolidate agents-md module duplication (Phase 4)

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

### Completion Notes List

### File List

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-26 | 1.0 | Story drafted from Epic 2 definition and reconnaissance findings |
