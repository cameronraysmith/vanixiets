# Story 8.10: Audit Test Harness and CI Documentation

Status: drafted

## Story

As a developer,
I want documentation that explains how to run tests locally and debug CI failures,
so that I can validate changes before pushing and troubleshoot failures efficiently.

## Background

Story 8.7 AMDiRE audit identified research streams R19 (Module Options-Docs Alignment) and R22 (Test Harness Documentation) as gaps requiring remediation.
Story 8.5 structural audit identified `development/traceability/` as a HIGH priority gap.

**Problem Statement:**
- User-facing test documentation (`packages/docs/src/content/docs/about/contributing/testing.md`) is stale and Vitest/Playwright-focused
- Excellent internal docs exist (`docs/notes/development/testing.md`, 194 lines) but aren't in Starlight
- No CI-to-local parity documentation exists
- Test philosophy (risk-based, depth scaling) is tribal knowledge
- Developers cannot easily reproduce CI failures locally

**Current Test Infrastructure State:**
- `docs/notes/development/testing.md`: 194 lines, current, infrastructure-focused (nix-unit, validation, CI)
- `packages/docs/src/content/docs/about/contributing/testing.md`: 379 lines, stale, web-app-focused (Vitest/Playwright)
- `modules/checks/`: 21 checks (11 nix-unit + 7 validation + 1 integration + 2 formatting)
- `.github/workflows/ci.yaml`: 13+ CI jobs with content-addressed caching
- `justfile`: test recipes including `check`, `check-fast`, category-specific builds

**Dependencies Completed:**
- Story 8.6 (done): CLI reference includes test recipes (`reference/justfile-recipes.md`)
- Story 8.5 (done): Identified `development/traceability/` as HIGH gap

## Acceptance Criteria

### Contributing Test Documentation Update (AC-1 through AC-3)

1. **AC-1**: Updated `packages/docs/src/content/docs/about/contributing/testing.md` includes:
   - Infrastructure test content (nix-unit, validation checks, integration tests) alongside web app tests
   - Test philosophy section (risk-based testing, depth scaling by change type)
   - Clear "when to use `just check` vs `just check-fast`" guidance with decision criteria
   - Module options that affect test behavior documented

2. **AC-2**: Test philosophy documentation explains:
   - Risk-based testing approach (critical path validation vs comprehensive checks)
   - Depth scaling by change type (config-only → `check-fast`, module changes → `check`)
   - When to run full CI locally vs trusting remote CI
   - What each test category validates and why

3. **AC-3**: Common failure modes and troubleshooting documented:
   - nix-unit test failures and solutions
   - Cross-platform test issues (darwin vs linux)
   - CI caching issues (cache invalidation, force refresh)
   - How to run/skip specific checks

### CI-Local Parity Documentation (AC-4 through AC-7)

4. **AC-4**: Created `packages/docs/src/content/docs/development/traceability/test-harness.md` with:
   - CI job → local recipe mapping table (all 13+ CI jobs)
   - Which recipes are CI-tested vs manual-only
   - Skip conditions and platform considerations
   - Local reproduction commands for each CI job

5. **AC-5**: Parity matrix exists showing:
   - CI job name → equivalent `just` recipe or `nix build` command
   - Required environment (linux-only, darwin-only, cross-platform)
   - Expected runtime for each check category
   - Cache key sources for understanding when jobs rerun

6. **AC-6**: Clear indication of:
   - Which justfile recipes are exercised by CI (with job mapping)
   - Which recipes are manual-only (not CI-tested)
   - Rationale for CI-excluded recipes (cost, platform, flakiness)

7. **AC-7**: Skip conditions documented:
   - Platform-specific skips (darwin integration tests on linux runners)
   - Content-addressed caching skip logic (hash-sources patterns)
   - Manual skip mechanisms (force_run parameter)

### Module Test Options Documentation (AC-8)

8. **AC-8**: Module options that affect tests are documented:
   - Enable flags in `modules/checks/*.nix`
   - Test selection patterns
   - Integration test VM configuration options
   - Environment variables affecting test behavior

### Validation (AC-9, AC-10)

9. **AC-9**: `just docs-build` passes with all new/updated documentation
10. **AC-10**: `just docs-linkcheck` passes with all cross-references valid

## Tasks / Subtasks

### Task 1: Research and Context Gathering (AC: all)

- [x] 1.1 Audit CI workflow structure (`.github/workflows/ci.yaml`)
  - [x] 1.1.1 List all jobs with triggers and dependencies
  - [x] 1.1.2 Identify matrix configurations (systems, configs)
  - [x] 1.1.3 Document content-addressed caching patterns (hash-sources)
  - [x] 1.1.4 Note conditional execution logic
- [x] 1.2 Audit existing test documentation files
  - [x] 1.2.1 Read `docs/notes/development/testing.md` (internal, current)
  - [x] 1.2.2 Read `packages/docs/src/content/docs/about/contributing/testing.md` (stale)
  - [x] 1.2.3 Identify content to preserve vs replace vs add
- [x] 1.3 Inventory justfile test recipes
  - [x] 1.3.1 List all recipes in nix, check, validation groups
  - [x] 1.3.2 Cross-reference with CI jobs that call them
  - [x] 1.3.3 Identify manual-only recipes
- [x] 1.4 Audit module options affecting tests
  - [x] 1.4.1 Read `modules/checks/default.nix` (aggregator) - N/A: no aggregator, uses perSystem directly
  - [x] 1.4.2 Read `modules/checks/nix-unit.nix` (15 test definitions)
  - [x] 1.4.3 Read `modules/checks/validation.nix` (7 validation checks)
  - [x] 1.4.4 Read `modules/checks/integration.nix` (2 VM integration tests)
  - [x] 1.4.5 Document enable flags and configuration options

### Task 2: Update Contributing Test Documentation (AC: 1, 2, 3)

- [x] 2.1 Revise `packages/docs/src/content/docs/about/contributing/testing.md`
  - [x] 2.1.1 Preserve web app test content (Vitest/Playwright) in dedicated section
  - [x] 2.1.2 Add infrastructure test section (nix-unit, validation, integration)
  - [x] 2.1.3 Add "Running Tests" section with platform-specific instructions
- [x] 2.2 Add test philosophy section
  - [x] 2.2.1 Document risk-based testing approach
  - [x] 2.2.2 Document depth scaling by change type
  - [x] 2.2.3 Include decision tree: when to use which check level
- [x] 2.3 Add `just check` vs `just check-fast` guidance
  - [x] 2.3.1 Document what each recipe validates
  - [x] 2.3.2 Provide change-type → recipe mapping guidance
  - [x] 2.3.3 Include timing expectations (check: ~5min, check-fast: ~1min)
- [x] 2.4 Add troubleshooting section
  - [x] 2.4.1 Common nix-unit failures and solutions
  - [x] 2.4.2 Cross-platform issues (darwin vs linux evaluation)
  - [x] 2.4.3 CI caching issues and cache invalidation
  - [x] 2.4.4 How to run/skip specific checks

### Task 3: Create CI-Local Parity Documentation (AC: 4, 5, 6, 7)

- [x] 3.1 Create `packages/docs/src/content/docs/development/traceability/test-harness.md`
  - [x] 3.1.1 Add Starlight frontmatter (title, description)
  - [x] 3.1.2 Write introduction explaining CI-local parity purpose
- [x] 3.2 Build CI job → local recipe mapping table
  - [x] 3.2.1 Map each CI job to equivalent local command
  - [x] 3.2.2 Document required environment (platform, secrets)
  - [x] 3.2.3 Note expected runtime per job category
- [x] 3.3 Document CI-tested vs manual-only recipes
  - [x] 3.3.1 List recipes exercised by CI with job references
  - [x] 3.3.2 List manual-only recipes with rationale
  - [x] 3.3.3 Document exclusion reasons (cost, platform, flakiness)
- [x] 3.4 Document skip conditions
  - [x] 3.4.1 Platform-specific skips
  - [x] 3.4.2 Content-addressed caching logic (hash-sources)
  - [x] 3.4.3 Manual skip/force mechanisms

### Task 4: Document Module Test Options (AC: 8)

- [x] 4.1 Document `modules/checks/` structure
  - [x] 4.1.1 Explain check aggregation pattern (perSystem direct composition, not default.nix)
  - [x] 4.1.2 Document nix-unit test definitions (15 tests, TC-001 to TC-021 IDs) - in testing.md
  - [x] 4.1.3 Document validation check purposes (7 checks) - in testing.md
  - [x] 4.1.4 Document integration test VM configuration (2 tests, Linux only) - in testing.md
- [x] 4.2 Document module enable flags
  - [x] 4.2.1 List configurable options per check module - in testing.md "Module options"
  - [x] 4.2.2 Document environment variables affecting tests - in testing.md "Environment variables"
  - [x] 4.2.3 Document test selection patterns - in testing.md "Test selection patterns"

### Task 5: Cross-Reference and Navigation (AC: 4, 9, 10)

- [x] 5.1 Add cross-references from new docs to existing docs
  - [x] 5.1.1 Link to CLI reference (`reference/justfile-recipes.md`) - in testing.md, test-harness.md
  - [x] 5.1.2 Link to CI jobs reference (`reference/ci-jobs.md`) - in testing.md, test-harness.md
  - [x] 5.1.3 Link to flake apps reference (`reference/flake-apps.md`) - via justfile-recipes.md
  - [x] 5.1.4 Link to ADR-0010 (testing architecture) - in testing.md
- [x] 5.2 Add backlinks from existing docs to new docs
  - [x] 5.2.1 Update `reference/justfile-recipes.md` to link testing.md, test-harness.md
  - [x] 5.2.2 Update `reference/ci-jobs.md` to link testing.md, test-harness.md
  - [x] 5.2.3 testing.md already includes test-harness.md link in "See also"
- [x] 5.3 Update navigation/index files
  - [x] 5.3.1 Add test-harness.md to development/traceability/index.md
  - [x] 5.3.2 Sidebar auto-discovers from Starlight content structure

### Task 6: Validation (AC: 9, 10)

- [ ] 6.1 Validate Starlight build
  - [ ] 6.1.1 Run `just docs-build`
  - [ ] 6.1.2 Verify all new pages render correctly
  - [ ] 6.1.3 Check for frontmatter warnings
- [ ] 6.2 Validate links
  - [ ] 6.2.1 Run `just docs-linkcheck`
  - [ ] 6.2.2 Fix any broken internal links
  - [ ] 6.2.3 Verify cross-references work bidirectionally
- [ ] 6.3 Manual review
  - [ ] 6.3.1 Verify contributing/testing.md reads coherently
  - [ ] 6.3.2 Verify test-harness.md parity matrix is accurate
  - [ ] 6.3.3 Confirm no placeholder content remains

## Dev Notes

### Source Material Locations

| Source | Path | Lines | Purpose |
|--------|------|-------|---------|
| Internal testing docs | `docs/notes/development/testing.md` | 194 | Current, infrastructure-focused (PRIMARY SOURCE) |
| Contributing testing | `packages/docs/src/content/docs/about/contributing/testing.md` | 379 | Stale, web-app-focused (UPDATE TARGET) |
| ADR-0010 | `packages/docs/src/content/docs/development/architecture/adrs/0010-testing-architecture.md` | ~100 | Testing strategy decisions |
| CLI reference | `packages/docs/src/content/docs/reference/justfile-recipes.md` | ~300 | Story 8.6 output (CROSS-REFERENCE) |
| CI jobs reference | `packages/docs/src/content/docs/reference/ci-jobs.md` | ~150 | Story 8.6 output (CROSS-REFERENCE) |

### Test Infrastructure Files

| File | Purpose | Key Content |
|------|---------|-------------|
| `modules/checks/default.nix` | Check aggregator | Combines all checks for `nix flake check` |
| `modules/checks/nix-unit.nix` | Unit tests | 11 tests (TC-001 to TC-021 with gaps) |
| `modules/checks/validation.nix` | Validation checks | 7 checks (exports, naming, terraform, secrets, deployment) |
| `modules/checks/integration.nix` | VM tests | NixOS VM boot tests for cinnabar, electrum |
| `.github/workflows/ci.yaml` | CI workflow | 13+ jobs with matrix builds |
| `.github/actions/cached-ci-job/` | Caching action | Content-addressed job result caching |

### CI Job → Local Parity Reference

From `docs/notes/development/testing.md`:

| CI Job | Local Equivalent | Platform |
|--------|------------------|----------|
| secrets-scan | `just gitleaks` | all |
| bootstrap-verification | `make bootstrap && make verify` | all |
| config-validation | `nix eval .#darwinConfigurations...` | all |
| autowiring-validation | `nix flake show` | all |
| secrets-workflow | `just check-secrets` | all |
| justfile-activation | `just --list` | all |
| nix (packages) | `nix build .#packages.<system>.<pkg>` | per-system |
| nix (checks-devshells) | `nix flake check` | per-system |
| nix (home) | `nix build .#homeConfigurations.<user>.activationPackage` | linux |
| nix (nixos) | `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` | linux |
| typescript | `cd packages/... && bun test` | all |

### Test Philosophy Content Outline

```markdown
## Test Philosophy

### Risk-Based Testing
- Critical path validation: Validate what matters most
- Depth scaling: Match test depth to change risk
- Trust boundaries: When to trust CI vs validate locally

### Depth Scaling by Change Type
| Change Type | Recommended Check | Rationale |
|-------------|-------------------|-----------|
| Config values only | `just check-fast` | Low risk, fast feedback |
| Module logic | `just check` | Medium risk, need validation |
| New host/user | `just check` + manual deploy | High risk, full validation |
| CI workflow | Push to trigger CI | CI is the test |
| Documentation | `just docs-build` | Starlight validation |

### When to Run Full Checks
- Before PR creation
- After rebasing
- When touching test infrastructure
- When adding new machines/users
```

### Content-Addressed Caching Pattern

From `docs/notes/development/testing.md` (lines 109-142):

```yaml
# Hash sources determine when CI jobs rerun
hash-sources: |
  flake.nix
  flake.lock
  modules/**/*.nix
  .github/actions/setup-nix/action.yml
```

Jobs skip when hash matches prior successful run.
Force rerun: `gh workflow run ci.yaml -f force_run=true`

### Diataxis Compliance

- **Contributing/testing.md**: How-to guide (task-oriented)
- **Traceability/test-harness.md**: Reference documentation (information-oriented)
- Tutorials would be "Learning to test your changes" (not in scope)

### Constraints

1. **Update existing files first** - Revise contributing/testing.md, don't replace
2. **Starlight structure** - New files must follow existing frontmatter patterns
3. **Diataxis compliance** - Reference docs for CI parity, how-to for troubleshooting
4. **Cross-reference existing docs** - Link to CLI reference (Story 8.6), ADRs
5. **No placeholders** - All content must be accurate and complete
6. **Atomic commits** - One logical change per commit

### Estimated Effort

| Task | Effort | Notes |
|------|--------|-------|
| Task 1: Research | 1-2h | Audit CI, modules, justfile |
| Task 2: Contributing docs | 2-3h | Major revision + philosophy section |
| Task 3: Test-harness.md | 2-3h | New reference document |
| Task 4: Module options | 1h | Extract from module files |
| Task 5: Cross-references | 0.5-1h | Bidirectional links |
| Task 6: Validation | 0.5h | Build, linkcheck, review |
| **Total** | **7-10h** | |

## NFR Coverage

**NFR-8.10**: Test reproducibility
- Every CI job has documented local equivalent
- Parity matrix enables failure reproduction
- Troubleshooting enables self-service debugging

## Dependencies

**Prerequisites:**
- Story 8.6 complete (CLI reference includes test recipes)
- Story 8.5 complete (identified traceability gap)

**Blocks:**
- None directly (documentation story)

**Related:**
- Story 8.9 (cross-reference validation can include these docs)

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-02 | Story drafted | SM workflow |

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
