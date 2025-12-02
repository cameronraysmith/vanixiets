# Story 8.6: Rationalize and Document CLI Tooling

Status: done

## Story

As a user or developer,
I want a curated, well-named set of CLI tools with comprehensive reference documentation,
so that I can discover and use the correct recipes without confusion from legacy or poorly-named options.

## Acceptance Criteria

### Phase 1: Rationalization (AC1-AC6)

1. **Recipe audit complete**: Audit all ~100 justfile recipes across 10 groups (nix, clan, docs, containers, secrets, sops, CI/CD, nix-home-manager, nix-darwin, nixos) for relevance to dendritic + clan architecture
2. **Stale recipes identified**: Identify and document recipes from nixos-unified era that are no longer applicable (e.g., recipes referencing `configurations/` directory, obsolete module patterns)
3. **Naming improvements identified**: Identify important recipes with suboptimal names needing rename for clarity (e.g., cryptic abbreviations, inconsistent prefixes)
4. **CI/CD coverage verified**: Verify which recipes are tested by CI/CD workflow jobs (ci.yaml), documenting the CI-to-recipe mapping
5. **Nix check coverage verified**: Verify which recipes are covered by `nix flake check` or nix-unit tests vs manual-only
6. **Rationalization proposals documented**: Produce rename/refactor/remove proposals for team approval with rationale for each

### Phase 2: Implementation (AC7-AC10)

7. **Deprecated recipes removed**: Remove stale recipes with git history preserving rationale (commit messages document why)
8. **Recipes renamed**: Rename recipes for semantic clarity where approved
9. **Documentation references updated**: Update any documentation referencing renamed/removed recipes
10. **CI/CD workflows aligned**: Ensure CI/CD workflows reference correct recipe names post-rename

### Phase 3: Documentation (AC11-AC14)

11. **Justfile recipe reference created**: Create `packages/docs/src/content/docs/reference/justfile-recipes.md` organized by group with purpose, usage, prerequisites, and examples
12. **Flake apps reference created**: Create `packages/docs/src/content/docs/reference/flake-apps.md` documenting darwin, os, home, update, activate, activate-home
13. **CI job reference created**: Create `packages/docs/src/content/docs/reference/ci-jobs.md` with local equivalents and CI-to-local recipe mapping
14. **CI-tested indication added**: Each recipe/app documents whether it is CI-tested or manual-only

## Tasks / Subtasks

### Task Group 1: Recipe Audit and Analysis (AC: #1-5)

- [ ] Task 1.1: Inventory all justfile recipes by group (AC: #1)
  - [ ] Extract recipes from each group using `just --list` and justfile parsing
  - [ ] Create audit spreadsheet/table with columns: Recipe, Group, Description, Status
  - [ ] Count: ~100 recipes across 10 groups

- [ ] Task 1.2: Audit nix group recipes for relevance (AC: #1, #2)
  - [ ] Recipes to audit: activate, io, lint, dev, clean, build, debug-build, debug-list, check, check-fast, verify, bisect-nixpkgs, bisect-nixpkgs-manual, switch, switch-home, switch-wrapper, bootstrap-shell, update, update-primary-inputs, update-package
  - [ ] Mark each as: KEEP, RENAME, REMOVE, DEPRECATE
  - [ ] Note: `switch` and `switch-home` may duplicate clan recipes

- [ ] Task 1.3: Audit nix-home-manager group recipes (AC: #1, #2)
  - [ ] Recipes: home-manager-bootstrap-build, home-manager-bootstrap-switch, home-manager-build, home-manager-switch
  - [ ] Assess overlap with clan-home-* recipes
  - [ ] Note: Bootstrap recipes use different workflow (nix run home-manager)

- [ ] Task 1.4: Audit nix-darwin group recipes (AC: #1, #2)
  - [ ] Recipes: darwin-bootstrap, darwin-build, darwin-switch, darwin-test
  - [ ] Assess overlap with clan-darwin-* recipes
  - [ ] Note: Clan recipes use flake app pattern

- [ ] Task 1.5: Audit nixos group recipes (AC: #1, #2)
  - [ ] Recipes: nixos-bootstrap, nixos-vm-sync, nixos-build, nixos-test, nixos-switch
  - [ ] Assess overlap with clan-os-* recipes
  - [ ] Note: nixos-bootstrap is legacy physical partitioning script

- [ ] Task 1.6: Audit clan group recipes (AC: #1)
  - [ ] Recipes: test, test-quick, test-integration, build-all, build-machine, clan-show, clan-metadata, clan-darwin-*, clan-os-*, clan-home-*
  - [ ] These are PRIMARY recipes for dendritic+clan architecture
  - [ ] Verify all are current and well-named

- [ ] Task 1.7: Audit docs group recipes (AC: #1)
  - [ ] Recipes: install, docs-dev, docs-build, docs-preview, docs-format, docs-lint, docs-check, docs-linkcheck, docs-test, docs-test-unit, docs-test-e2e, docs-test-coverage, docs-deploy-*, docs-deployments, docs-tail, docs-versions
  - [ ] All should be current (TypeScript/Starlight tooling)

- [ ] Task 1.8: Audit containers group recipes (AC: #1)
  - [ ] Recipes: build-container, build-multiarch, load-container, load-native, test-container, container-all, container-all-multiarch
  - [ ] Assess current usage and relevance

- [ ] Task 1.9: Audit secrets group recipes (AC: #1)
  - [ ] Recipes: scan-secrets, scan-staged, show, create-secret, populate-*, get-secret, seed-dotenv, export, check-secrets, get-kubeconfig, hash-encrypt, verify-hash, edit-secret, new-secret, get-shared-secret, run-with-secrets, validate-secrets
  - [ ] Note: GCP secrets recipes may be legacy (populate-*, create-secret, get-secret)
  - [ ] SOPS recipes are current

- [ ] Task 1.10: Audit CI/CD group recipes (AC: #1, #4, #5)
  - [ ] Recipes: ci-run-watch, ci-status, ci-logs, ci-logs-failed, ci-show-outputs, ci-build-local, ci-build-category, ci-cache-category, ci-validate, ci-debug-job, ghsecrets, list-workflows, test-flake-workflow, ratchet-*, cache-*, list-packages, list-packages-json, validate-package, test-package, preview-version, release-package
  - [ ] Map to CI jobs that invoke them:
    - `just check` → flake-validation job
    - `just cache-overlay-packages` → cache-overlay-packages job
    - `just ci-build-category` → nix job matrix
    - `just preview-version` → preview-release-version job
  - [ ] Document which are CI-tested vs manual-only

- [ ] Task 1.11: Audit sops group recipes (AC: #1)
  - [ ] Recipes: sops-extract-keys, sops-update-yaml, sops-deploy-host-key, sops-validate-correspondences, sops-sync-keys, sops-rotate, update-all-keys, sops-load-agent
  - [ ] All should be current (sops-nix workflow)

- [ ] Task 1.12: Identify naming improvements (AC: #3)
  - [ ] Look for: inconsistent prefixes, cryptic abbreviations, misleading names
  - [ ] Example candidates: `io` (unclear), `switch` vs `clan-darwin-switch` (redundancy)
  - [ ] Document proposed new names with rationale

- [ ] Task 1.13: Cross-reference with flake apps (AC: #1)
  - [ ] List flake apps: darwin, os, home, update, activate, activate-home, terraform
  - [ ] Understand relationship between flake apps and justfile recipes
  - [ ] Document: apps wrap nix-darwin/nixos-rebuild/home-manager commands

### Task Group 2: Rationalization Proposals (AC: #6)

- [ ] Task 2.1: Compile rationalization proposal document
  - [ ] Format: Table with columns: Recipe, Current State, Proposed Action, Rationale, CI Impact
  - [ ] Actions: KEEP, RENAME(new_name), REMOVE, DEPRECATE(date)
  - [ ] Flag any with CI dependencies for careful review

- [ ] Task 2.2: Present proposals for approval (**PAUSE POINT**)
  - [ ] Output proposal to user for review
  - [ ] **DEV AGENT DIRECTIVE**: Wait for explicit approval before implementing changes
  - [ ] Document any rejected proposals with rationale

### Task Group 3: Implementation of Approved Changes (AC: #7-10)

- [ ] Task 3.1: Remove deprecated recipes (AC: #7)
  - [ ] For each approved removal:
    - [ ] Verify recipe is not referenced by CI
    - [ ] Verify recipe is not referenced by documentation
    - [ ] Remove recipe from justfile
    - [ ] Commit with message: `chore(justfile): remove deprecated {recipe} - {rationale}`
  - [ ] **DEV AGENT DIRECTIVE**: Confirm CI/CD non-use before each removal

- [ ] Task 3.2: Rename recipes for clarity (AC: #8)
  - [ ] For each approved rename:
    - [ ] Update recipe name in justfile
    - [ ] Update any justfile internal references (dependencies)
    - [ ] Commit with message: `refactor(justfile): rename {old} to {new} for clarity`

- [ ] Task 3.3: Update documentation references (AC: #9)
  - [ ] Search for renamed/removed recipes in docs: `rg "{recipe}" packages/docs/`
  - [ ] Update references to new names
  - [ ] Add deprecation notices if soft-deprecating

- [ ] Task 3.4: Verify CI workflow alignment (AC: #10)
  - [ ] Review `.github/workflows/ci.yaml` for recipe references
  - [ ] Update any renamed recipe calls
  - [ ] Run `just ci-run-watch` to validate CI passes

### Task Group 4: Documentation Creation (AC: #11-14)

- [ ] Task 4.1: Create justfile-recipes.md (AC: #11)
  - [ ] Location: `packages/docs/src/content/docs/reference/justfile-recipes.md`
  - [ ] Structure by group with:
    - Group description
    - Recipe table: Name, Purpose, Prerequisites, Example, CI-tested?
    - Cross-references to related recipes
  - [ ] Use justfile comments as source for descriptions

- [ ] Task 4.2: Create flake-apps.md (AC: #12)
  - [ ] Location: `packages/docs/src/content/docs/reference/flake-apps.md`
  - [ ] Document each flake app:
    - `darwin`: darwin-rebuild switch wrapper
    - `os`: nixos-rebuild switch wrapper (clan machines update)
    - `home`: home-manager switch wrapper
    - `update`: nix flake update for primary inputs
    - `activate`: Auto-detect and switch system configuration
    - `activate-home`: Switch home-manager configuration
    - `terraform`: Run terranix-generated terraform
  - [ ] Include usage examples and prerequisites

- [ ] Task 4.3: Create ci-jobs.md (AC: #13)
  - [ ] Location: `packages/docs/src/content/docs/reference/ci-jobs.md`
  - [ ] Document each CI job with:
    - Job name and purpose
    - Local equivalent (justfile recipe)
    - When it runs (triggers)
    - Common failures and troubleshooting
  - [ ] CI jobs to document:
    1. secrets-scan → `just scan-secrets`
    2. set-variables → N/A (CI only)
    3. preview-release-version → `just preview-version`
    4. preview-docs-deploy → `just docs-deploy-preview`
    5. bootstrap-verification → `make bootstrap && make verify`
    6. secrets-workflow → N/A (ephemeral test)
    7. flake-validation → `just check` or `just check-fast`
    8. cache-overlay-packages → `just cache-overlay-packages {system}`
    9. nix → `just ci-build-category {system} {category}`
    10. typescript → `just test-package {package}`
    11. production-release-packages → `just release-package {package}`
    12. production-docs-deploy → `just docs-deploy-production`

- [ ] Task 4.4: Add CI-tested indicators (AC: #14)
  - [ ] Add badge or column to recipe documentation
  - [ ] Categories: CI-tested, Manual-only, CI-adjacent (uses cached outputs)

- [ ] Task 4.5: Create reference/index.md
  - [ ] Add navigation to new reference documents
  - [ ] Cross-link to guides and concepts

### Task Group 5: Validation and Completion

- [ ] Task 5.1: Validate Starlight build
  - [ ] Run `nix build .#docs` or `bun run build` in packages/docs
  - [ ] Verify no broken links with `just docs-linkcheck`

- [ ] Task 5.2: Update sprint-status.yaml
  - [ ] Mark story-8-6 as "done" (or "review" if code review needed)

- [ ] Task 5.3: Commit and summarize changes
  - [ ] Final commit: `docs(story-8.6): complete CLI tooling rationalization and documentation`
  - [ ] Summary of changes made

## Dev Notes

### CLI Tooling Scope

**Justfile Groups (10 total, ~100 recipes):**

| Group | Count | Purpose | Relevance |
|-------|-------|---------|-----------|
| nix | ~20 | Core nix operations | HIGH - foundational |
| clan | ~16 | Clan-based machine management | HIGH - primary workflow |
| docs | ~17 | Documentation site | MEDIUM - TypeScript tooling |
| containers | ~7 | Container builds | LOW - occasional use |
| secrets | ~18 | Secrets management | HIGH - operational |
| sops | ~8 | SOPS key management | HIGH - operational |
| CI/CD | ~25 | CI/CD operations | HIGH - development workflow |
| nix-home-manager | ~4 | Home-manager bootstrap | MEDIUM - legacy bootstrap |
| nix-darwin | ~4 | Darwin bootstrap | MEDIUM - legacy bootstrap |
| nixos | ~5 | NixOS operations | MEDIUM - VPS operations |

**Flake Apps (7 total):**
- darwin, os, home: Configuration switchers
- update, activate, activate-home: Convenience wrappers
- terraform: Infrastructure provisioning

**CI Jobs (13 total in ci.yaml):**
- See Task 4.3 for complete mapping

### Previous Story Learnings

**From Story 8.5 (Status: review)**

- **Audit methodology**: File discovery via fd, content analysis, cross-reference to research document
- **Framework alignment**: Diataxis + AMDiRE categorization
- **GAP-004 (HIGH)**: reference/ has only 1 file (repository-structure.md)
- **Recommended action**: Create justfile recipe reference, flake apps reference, CI jobs reference
- **Story sequence**: Story 8.6 recommended FIRST in Phase 2 to address reference/ gap
- **Key artifact**: story-8.5-structure-audit-results.md documents all gaps

[Source: docs/notes/development/work-items/8-5-audit-documentation-structure-against-diataxis-amdire-frameworks.md#Completion-Notes-List]

### Project Structure Notes

**Reference documentation location:** `packages/docs/src/content/docs/reference/`

**Current state (from Story 8.5):**
- Only `repository-structure.md` exists
- Gap severity: HIGH

**Target state after Story 8.6:**
- `repository-structure.md` (existing)
- `justfile-recipes.md` (new)
- `flake-apps.md` (new)
- `ci-jobs.md` (new)
- `index.md` (new, navigation)

### CI Workflow Integration

**Recipes called by CI (must preserve):**

| CI Job | Recipe | Line in ci.yaml |
|--------|--------|-----------------|
| flake-validation | `just check` | 559 |
| cache-overlay-packages | `just cache-overlay-packages` | 630 |
| nix | `just ci-build-category` | 731 |
| preview-release-version | `just preview-version` | 244 |
| preview-docs-deploy | via deploy-docs.yaml | N/A |

**Recipes tested by CI (indirectly):**
- All recipes that run as part of `just check` (includes nix flake check, nix-unit)
- `just cache-overlay-packages` validates overlay builds
- `just ci-build-category` validates all configuration builds

### Dev Agent Directive

When executing this story, the implementing agent MUST:

1. **Pause and discuss** with user if uncertain which recipes should be preferred over alternatives
2. **Confirm CI/CD coverage** before proposing removals - verify recipes are/aren't tested by CI
3. **Present rename/remove proposals** for approval before executing changes
4. **Document rationale** for any recipes retained despite appearing stale

This pause-and-discuss pattern prevents accidental removal of recipes that appear unused but serve important edge cases.

### Research Streams Covered

From `docs/notes/development/research/documentation-coverage-analysis.md`:

| Stream | Name | Scope |
|--------|------|-------|
| R16 | Justfile-Docs Alignment | Recipe documentation, discoverability, examples |
| R17 | Flake Apps-Docs Alignment | Flake app documentation and usage examples |
| R18 | CI Jobs-Docs Alignment | CI job documentation and troubleshooting |

### References

- [Epic 8: docs/notes/development/epics/epic-8-documentation-alignment.md#Story-8.6]
- [Story 8.5 Artifact: docs/notes/development/work-items/story-8.5-structure-audit-results.md]
- [Research Document: docs/notes/development/research/documentation-coverage-analysis.md]
- [Justfile: justfile]
- [CI Workflow: .github/workflows/ci.yaml]
- [Starlight Docs Reference: packages/docs/src/content/docs/reference/]

### Constraints

1. **CI-first verification**: Never remove recipes called by CI without updating CI first
2. **Atomic commits**: One commit per logical change (removal, rename, documentation)
3. **Rationalization before documentation**: Clean up recipes before documenting them
4. **Approval-gated changes**: Pause for user approval before implementing removals/renames
5. **Starlight build validation**: Verify docs build after all changes

### Estimated Effort

**Phase 1 (Rationalization):** 4-6 hours
- Task Group 1 (audit): 3-4 hours
- Task Group 2 (proposals): 1-2 hours

**Phase 2 (Implementation):** 2-4 hours
- Task Group 3 (changes): 2-4 hours (depends on approval scope)

**Phase 3 (Documentation):** 6-8 hours
- Task Group 4 (docs): 5-7 hours
- Task Group 5 (validation): 1 hour

**Total:** 12-18 hours

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

## Change Log

**2025-12-02 (Story Completed)**:
- All 14 acceptance criteria satisfied
- Phase 1: Audited ~100 justfile recipes, cross-referenced CI workflows and flake apps
- Phase 2: Removed 6 GCP legacy secrets recipes + `gcp_project_id` variable, renamed `io` → `flake-info`
- Phase 3: Created 4 reference docs (justfile-recipes.md 261 lines, flake-apps.md 203 lines, ci-jobs.md 312 lines, index.md 51 lines)
- Activation recipe rationalization completed by Party Mode team (4 unified recipes, 15 legacy recipes removed)
- Build validation: Starlight build PASS, linkcheck PASS
- Commits: 8cd1e810, d09fd4e0, c5915617, a1a52a67
- Status: done

**2025-12-02 (Story Drafted)**:
- Story file created from Epic 8 Story 8.6 specification
- Incorporated Story 8.5 findings (GAP-004: reference/ sparse)
- Incorporated research document analysis (R16, R17, R18)
- Three-phase structure: Rationalization → Implementation → Documentation
- 5 task groups with detailed subtasks
- Dev Agent Directive included for pause-and-discuss pattern
- CI workflow integration documented
- Justfile recipe groups inventoried (~100 recipes across 10 groups)
- Estimated effort: 12-18 hours
- Status: drafted
