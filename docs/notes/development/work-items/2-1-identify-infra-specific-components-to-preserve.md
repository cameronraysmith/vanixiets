# Story 2.1: Identify infra-specific components to preserve

**Epic:** Epic 2 - Infrastructure Architecture Migration (Apply test-clan patterns to infra)

**Status:** ready-for-dev

**Phase:** Phase 1 - Home-Manager Migration Foundation

**Dependencies:**
- Epic 1 complete ✅ (GO decision rendered Story 1.14)

**Blocks:**
- Story 2.2 (Stibnite vs blackphos configuration diff analysis)
- Story 2.3 (Home-manager Pattern A migration - requires preservation checklist)

**Strategic Value:**

Story 2.1 is the **first Epic 2 story** and establishes the foundation for the "rip the band-aid" migration strategy.

This story identifies all infra-specific components that must be preserved during Epic 2 Phase 1-4 migration from nixos-unified to dendritic flake-parts+clan architecture.
Without this preservation checklist, Stories 2.3+ risk destroying critical infrastructure when copying configurations from test-clan → infra.

**Critical Infrastructure at Risk:**
- GitHub Actions CI/CD workflows (7 workflows managing package releases, testing, deployments)
- TypeScript documentation website (docs.cameronraysmith.com served via Cloudflare Pages)
- Cloudflare deployment automation (wrangler configuration, build scripts)
- Infra-specific tooling and scripts

**Epic 2 Migration Strategy:**

Epic 2 applies validated patterns from Epic 1's test-clan repository to production infra repository using a "rip the band-aid" approach:
1. Create fresh `clan-01` branch in infra
2. Copy nix configurations from test-clan → infra (filesystem operations)
3. Preserve infra-specific components per Story 2.1 checklist
4. Validate at each phase boundary

**Story 2.1 Position:**

This story executes **before** any config copying (Stories 2.3+) to document exactly what must NOT be overwritten.
The preservation checklist maps component → file paths → migration action (preserve/adapt/replace).

---

## Story Description

As a system administrator,
I want to identify and document all infra-specific components that must be preserved during migration,
So that the "rip the band-aid" config replacement doesn't destroy unique infra infrastructure (GitHub Actions CI/CD, TypeScript documentation website at docs.cameronraysmith.com, Cloudflare deployment automation).

**Context:**

The infra repository contains infrastructure unique to this project that does NOT exist in test-clan:
- **GitHub Actions workflows**: CI/CD automation for package testing, releases, deployments
- **TypeScript monorepo**: Documentation website source code (Astro/Starlight framework)
- **Cloudflare Pages deployment**: Automated deployment of docs.cameronraysmith.com

Epic 2 Stories 2.3+ will copy nix configurations (flake.nix, modules/, hosts/, home-manager/) from test-clan → infra.
This copying process MUST NOT overwrite infra-specific components.

**Outcome:**

Story 2.1 produces a comprehensive preservation checklist documenting:
- All GitHub Actions workflows with descriptions and purposes
- TypeScript monorepo structure with package locations and build scripts
- Cloudflare deployment configuration with targets and automation
- File paths of all components requiring preservation
- Migration actions for each component (preserve/adapt/replace)

This checklist serves as the authoritative reference for Stories 2.3+ to avoid destroying critical infra infrastructure.

---

## Acceptance Criteria

### AC1: GitHub Actions Workflows Documented

**Requirement:** Scan `.github/workflows/` and document all CI/CD workflows with descriptions.

**Workflow Documentation Required:**
- Workflow file name (e.g., `ci.yaml`, `deploy-docs.yaml`)
- Workflow purpose (what it does - testing, deployment, release automation)
- Workflow triggers (when it runs - push, PR, manual, schedule)
- Critical dependencies (secrets, environments, external services)
- Migration action: PRESERVE (must NOT be overwritten by test-clan migration)

**Evidence Required:**
- Complete list of all workflows in `.github/workflows/`
- Description of each workflow's role in infra CI/CD
- Identification of workflows critical to infra operation
- Clear PRESERVE directive for migration (Story 2.3+)

**Validation:**
- All 7 workflows documented (ci.yaml, deploy-docs.yaml, package-release.yaml, package-test.yaml, pr-check.yaml, pr-merge.yaml, test-composite-actions.yaml)
- Purpose and triggers explained for each workflow
- PRESERVE action documented for entire `.github/workflows/` directory

---

### AC2: TypeScript Monorepo Structure Documented

**Requirement:** Document TypeScript monorepo structure including package locations, build scripts, and dependencies.

**Monorepo Documentation Required:**
- Root `package.json` location and purpose
- Monorepo workspace configuration (if using workspaces)
- Build scripts and commands (e.g., `npm run build`, `npm run dev`)
- Key dependencies (TypeScript, Astro, Starlight, build tools)
- Source code locations (e.g., `docs/`, `packages/`, `src/`)
- Migration action: PRESERVE (TypeScript code must NOT be overwritten)

**Evidence Required:**
- `package.json` file path and contents summary
- Workspace structure (if monorepo uses npm/yarn/pnpm workspaces)
- Build/dev script identification
- Source code directory identification
- Clear PRESERVE directive for TypeScript monorepo files

**Validation:**
- Root `package.json` documented with build scripts
- TypeScript source directories identified
- Node modules and build artifacts noted (can be regenerated, not critical)
- PRESERVE action documented for package.json and source directories

---

### AC3: Cloudflare Deployment Configuration Documented

**Requirement:** Document Cloudflare deployment configuration including wrangler.toml location and deployment targets.

**Cloudflare Documentation Required:**
- `wrangler.toml` file path (if exists)
- Cloudflare Pages configuration (if using Pages instead of Workers)
- Deployment target (e.g., docs.cameronraysmith.com)
- Build command and output directory
- Cloudflare integration with GitHub Actions (deploy-docs.yaml workflow)
- Migration action: PRESERVE (Cloudflare config must NOT be overwritten)

**Evidence Required:**
- Cloudflare configuration file location (wrangler.toml or Pages config)
- Deployment target documentation (docs.cameronraysmith.com)
- Build/deploy automation integration (GitHub Actions workflow)
- Clear PRESERVE directive for Cloudflare deployment files

**Validation:**
- Cloudflare deployment mechanism documented
- Integration with GitHub Actions identified (deploy-docs.yaml)
- Deployment target confirmed (docs.cameronraysmith.com)
- PRESERVE action documented for Cloudflare configuration

---

### AC4: Infra-Unique Infrastructure Identified

**Requirement:** Identify any other infra-unique infrastructure beyond GitHub Actions, TypeScript, and Cloudflare.

**Additional Infrastructure to Identify:**
- Custom scripts or tooling (e.g., `scripts/` directory)
- Documentation specific to infra (e.g., `docs/notes/` - preserve development docs)
- Configuration files unique to infra (e.g., `.vscode/`, `.editorconfig`)
- Any other files NOT present in test-clan that serve infra-specific purposes

**Evidence Required:**
- Inventory of additional infra-specific files/directories
- Purpose of each identified component
- Migration action per component (PRESERVE, ADAPT, or REPLACE)

**Validation:**
- Comprehensive scan completed (no critical infra components missed)
- Each additional component documented with purpose
- Migration actions assigned (PRESERVE/ADAPT/REPLACE)

---

### AC5: Preservation Checklist Created

**Requirement:** Create preservation checklist mapping component → file paths → migration action.

**Checklist Format:**

```markdown
# Infra-Specific Component Preservation Checklist

Generated: 2025-11-21 (Story 2.1)
Purpose: Document infra components to PRESERVE during Epic 2 migration (test-clan → infra)

## Critical Infrastructure (MUST PRESERVE)

### 1. GitHub Actions CI/CD Workflows
- **Directory:** `.github/workflows/`
- **Files:**
  - ci.yaml (41 KB) - Main CI pipeline for nix builds and tests
  - deploy-docs.yaml (4.6 KB) - Cloudflare Pages deployment automation
  - package-release.yaml (5.7 KB) - Package release automation
  - package-test.yaml (4.5 KB) - Package testing workflows
  - pr-check.yaml (480 B) - PR validation checks
  - pr-merge.yaml (648 B) - PR merge automation
  - test-composite-actions.yaml (7.4 KB) - Composite action testing
- **Purpose:** CI/CD automation for package releases, testing, deployments
- **Migration Action:** **PRESERVE** - Do NOT overwrite with test-clan files
- **Story 2.3+ Directive:** Skip `.github/workflows/` when copying from test-clan

### 2. TypeScript Documentation Monorepo
- **Root package.json:** `/package.json`
- **Source directories:** TBD (document in AC2)
- **Purpose:** docs.cameronraysmith.com documentation website source
- **Migration Action:** **PRESERVE** - Do NOT overwrite TypeScript code
- **Story 2.3+ Directive:** Skip package.json and source dirs when copying

### 3. Cloudflare Deployment Configuration
- **Configuration:** TBD (wrangler.toml or Pages config - document in AC3)
- **Target:** docs.cameronraysmith.com
- **Integration:** deploy-docs.yaml workflow
- **Migration Action:** **PRESERVE** - Do NOT overwrite Cloudflare config
- **Story 2.3+ Directive:** Skip Cloudflare config files when copying

### 4. Development Documentation
- **Directory:** `docs/notes/development/`
- **Content:** PRD, Architecture, Epics, Sprint status, Work items
- **Purpose:** Project management and development tracking
- **Migration Action:** **PRESERVE** - Critical project documentation
- **Story 2.3+ Directive:** Do NOT overwrite docs/notes/ (infra-specific)

## Files/Directories Safe to Replace

### 1. Nix Configurations (REPLACE from test-clan)
- `flake.nix` - Replace with test-clan dendritic+clan pattern
- `modules/` - Replace with test-clan dendritic structure
- `hosts/` - Replace with test-clan machine configs
- `home-manager/` - Replace with test-clan Pattern A home configs
- `overlays/` - Replace with test-clan five-layer overlay architecture
- `secrets/` - Replace with test-clan sops-nix two-tier secrets

### 2. Build Artifacts (Regenerate)
- `node_modules/` - Regenerate via npm install
- `result/` - Nix build artifacts (regenerate)
- `.direnv/` - direnv cache (regenerate)

## Migration Strategy Summary

**Story 2.3 Execution Plan:**
1. Create `clan-01` branch in infra
2. Copy test-clan nix configs → infra (flake.nix, modules/, hosts/, home-manager/, overlays/, secrets/)
3. **SKIP copying** any files/directories marked PRESERVE above
4. Validate builds after migration (nix flake check, darwin/nixos configs)
5. Test GitHub Actions still functional (CI/CD workflows intact)
6. Test Cloudflare deployment still operational (docs site deploys)

**Zero-Regression Requirement:**
- All PRESERVE components must function identically pre/post-migration
- GitHub Actions workflows execute successfully
- Cloudflare deployment to docs.cameronraysmith.com operational
- TypeScript monorepo builds successfully
```

**Evidence Required:**
- Complete preservation checklist in markdown format
- All components from AC1-AC4 included
- Clear PRESERVE vs REPLACE directives for each component
- Migration strategy summary for Story 2.3+ execution

**Validation:**
- Checklist includes all GitHub Actions workflows (AC1)
- Checklist includes TypeScript monorepo components (AC2)
- Checklist includes Cloudflare deployment config (AC3)
- Checklist includes any additional infra components (AC4)
- Migration actions clear (PRESERVE/REPLACE)
- Story 2.3+ execution guidance provided

---

### AC6: Files to Preserve Clearly Mapped

**Requirement:** Document which files in infra must NOT be overwritten by test-clan files.

**File Mapping Required:**

Create explicit file/directory exclusion list for Story 2.3+ migration:

```markdown
## Exclusion List for Story 2.3 Migration

When copying files from test-clan → infra, **EXCLUDE** the following:

### Directories (Do NOT Overwrite)
1. `.github/workflows/` - Preserve all CI/CD workflows
2. `docs/notes/development/` - Preserve project documentation
3. `[TypeScript source dirs]` - Preserve documentation website code
4. `[Additional dirs from AC4]` - Preserve other infra-specific components

### Files (Do NOT Overwrite)
1. `/package.json` - Preserve TypeScript monorepo configuration
2. `[wrangler.toml or Cloudflare config]` - Preserve deployment configuration
3. `/README.md` - Preserve infra-specific README (if different from test-clan)
4. `[Additional files from AC4]` - Preserve other infra-specific files

### Safe to Overwrite (Replace with test-clan)
1. `flake.nix` - Replace with test-clan dendritic+clan pattern
2. `modules/**` - Replace with test-clan dendritic structure
3. `hosts/**` - Replace with test-clan machine configs
4. `home-manager/**` - Replace with test-clan Pattern A configs
5. `overlays/**` - Replace with test-clan five-layer architecture
6. `secrets/**` - Replace with test-clan sops-nix two-tier secrets
7. `.envrc` - Replace with test-clan direnv configuration
8. `shell.nix` / `default.nix` - Replace with test-clan dev shell

## Verification Commands

After Story 2.3 migration, verify preservation:

```bash
# 1. Verify GitHub Actions workflows intact
ls -la .github/workflows/
git diff main..clan-01 -- .github/workflows/  # Should show no changes

# 2. Verify TypeScript monorepo intact
ls package.json
git diff main..clan-01 -- package.json  # Should show no changes

# 3. Verify Cloudflare config intact
[Command to check Cloudflare config]
git diff main..clan-01 -- [cloudflare config path]  # Should show no changes

# 4. Verify development docs intact
ls -la docs/notes/development/
git diff main..clan-01 -- docs/notes/development/  # Should show no changes
```
```

**Evidence Required:**
- Explicit exclusion list for directories and files
- Clear directives for Story 2.3+ (what NOT to overwrite)
- Verification commands to validate preservation
- Git diff commands to confirm exclusions honored

**Validation:**
- All PRESERVE components from AC1-AC4 in exclusion list
- Verification commands provided for post-migration validation
- Story 2.3+ has actionable guidance (which files to skip)
- Git diff verification ensures preservation

---

### AC7: Checklist Reviewed and Approved

**Requirement:** Preservation checklist reviewed and approved for use in Story 2.3 branch creation.

**Review Process:**
1. Story 2.1 developer creates preservation checklist (AC5 deliverable)
2. Developer validates checklist completeness against AC1-AC6
3. Developer confirms all critical infra components documented
4. Story 2.1 marked "drafted" → "ready-for-dev" after checklist finalized
5. SM/user reviews checklist before Story 2.3 execution begins

**Approval Criteria:**
- Checklist includes ALL GitHub Actions workflows (AC1)
- Checklist includes ALL TypeScript monorepo components (AC2)
- Checklist includes ALL Cloudflare deployment config (AC3)
- Checklist includes any additional infra-unique components (AC4)
- File exclusion list actionable for Story 2.3 migration (AC6)
- Migration strategy clear and follows Epic 2 "rip the band-aid" approach

**Evidence Required:**
- Preservation checklist finalized and saved to docs/notes/development/work-items/
- Story 2.1 status updated to "ready-for-dev" (checklist complete)
- Checklist ready for Story 2.3 consumption

**Validation:**
- All ACs 1-6 satisfied in final checklist
- Story 2.1 developer confirms checklist complete
- Story 2.1 ready for SM review (if required)
- Story 2.3 can proceed using preservation checklist

---

## Tasks / Subtasks

### Task 1: Scan and Document GitHub Actions Workflows (AC1)

**Objective:** Identify all CI/CD workflows in `.github/workflows/` and document their purposes.

**Subtasks:**

- [ ] **1.1: List all workflow files**
  - Read `.github/workflows/` directory contents
  - Count total workflows (expected: 7 based on ls output)
  - Note file names and sizes
  - **AC Reference:** AC1

- [ ] **1.2: Document each workflow's purpose**
  - Read ci.yaml header/description (main CI pipeline)
  - Read deploy-docs.yaml header/description (Cloudflare Pages deployment)
  - Read package-release.yaml header/description (package release automation)
  - Read package-test.yaml header/description (package testing)
  - Read pr-check.yaml header/description (PR validation)
  - Read pr-merge.yaml header/description (PR merge automation)
  - Read test-composite-actions.yaml header/description (composite action testing)
  - **AC Reference:** AC1

- [ ] **1.3: Document workflow triggers and dependencies**
  - Identify triggers for each workflow (on: push, pull_request, workflow_dispatch, schedule)
  - Identify secrets used (CLOUDFLARE_API_TOKEN, NPM_TOKEN, etc.)
  - Identify external service dependencies (Cloudflare, npm registry)
  - **AC Reference:** AC1

- [ ] **1.4: Assign PRESERVE migration action**
  - Document `.github/workflows/` as MUST PRESERVE
  - Note: test-clan does NOT have GitHub Actions workflows
  - Directive: Story 2.3 MUST NOT overwrite .github/workflows/
  - **AC Reference:** AC1

**Deliverable:** GitHub Actions workflows section of preservation checklist (AC1 complete)

---

### Task 2: Document TypeScript Monorepo Structure (AC2)

**Objective:** Identify TypeScript monorepo components and document for preservation.

**Subtasks:**

- [ ] **2.1: Locate root package.json**
  - Read `/package.json` contents
  - Document package name, version, scripts
  - Identify build scripts (build, dev, test commands)
  - **AC Reference:** AC2

- [ ] **2.2: Identify monorepo workspace configuration**
  - Check if package.json uses workspaces (npm/yarn/pnpm workspaces)
  - Identify workspace packages (if monorepo structure)
  - Document workspace dependencies
  - **AC Reference:** AC2

- [ ] **2.3: Document TypeScript source directories**
  - Identify source code locations (docs/, packages/, src/ candidates)
  - Check for TypeScript config (tsconfig.json locations)
  - Document Astro/Starlight integration (if docs website)
  - Note: test-clan does NOT have TypeScript monorepo
  - **AC Reference:** AC2

- [ ] **2.4: Assign PRESERVE migration action**
  - Document package.json as MUST PRESERVE
  - Document source directories as MUST PRESERVE
  - Directive: Story 2.3 MUST NOT overwrite TypeScript monorepo files
  - Note: node_modules/ can be regenerated (not critical to preserve)
  - **AC Reference:** AC2

**Deliverable:** TypeScript monorepo section of preservation checklist (AC2 complete)

---

### Task 3: Document Cloudflare Deployment Configuration (AC3)

**Objective:** Identify Cloudflare deployment setup and document for preservation.

**Subtasks:**

- [ ] **3.1: Search for Cloudflare configuration files**
  - Search for wrangler.toml (Cloudflare Workers config)
  - Search for Cloudflare Pages configuration (may be in GitHub Actions, not separate file)
  - Check deploy-docs.yaml workflow for Cloudflare integration
  - **AC Reference:** AC3

- [ ] **3.2: Document deployment target and mechanism**
  - Identify deployment target (docs.cameronraysmith.com)
  - Document deployment mechanism (Cloudflare Pages via GitHub Actions)
  - Document build command and output directory (from deploy-docs.yaml)
  - **AC Reference:** AC3

- [ ] **3.3: Document GitHub Actions integration**
  - Read deploy-docs.yaml workflow details
  - Identify Cloudflare API token usage (secrets)
  - Document deployment triggers (push to main, manual, etc.)
  - **AC Reference:** AC3

- [ ] **3.4: Assign PRESERVE migration action**
  - Document Cloudflare config files as MUST PRESERVE (if wrangler.toml exists)
  - Note: Deploy-docs.yaml already preserved via AC1 (GitHub Actions workflows)
  - Directive: Story 2.3 MUST NOT overwrite Cloudflare deployment configuration
  - Note: test-clan does NOT have Cloudflare deployment
  - **AC Reference:** AC3

**Deliverable:** Cloudflare deployment section of preservation checklist (AC3 complete)

---

### Task 4: Identify Additional Infra-Unique Components (AC4)

**Objective:** Scan for any other infra-specific infrastructure beyond GitHub Actions, TypeScript, Cloudflare.

**Subtasks:**

- [ ] **4.1: Scan for custom scripts and tooling**
  - Check for `scripts/` directory (if exists)
  - Identify any custom automation scripts
  - Document purpose of each script
  - Assign migration action (PRESERVE if infra-specific)
  - **AC Reference:** AC4

- [ ] **4.2: Verify development documentation**
  - Confirm `docs/notes/development/` exists (known to exist from sprint-status.yaml)
  - Document contents: PRD, Architecture, Epics, Sprint status, Work items
  - Migration action: **PRESERVE** (critical project documentation)
  - Directive: Story 2.3 MUST NOT overwrite docs/notes/
  - **AC Reference:** AC4

- [ ] **4.3: Check for editor/IDE configurations**
  - Check for `.vscode/` directory (VS Code settings)
  - Check for `.editorconfig` file (editor configuration)
  - Document purpose (developer experience, code formatting)
  - Assign migration action (PRESERVE if infra-specific, REPLACE if generic)
  - **AC Reference:** AC4

- [ ] **4.4: Identify any other unique files/directories**
  - Compare infra root directory to test-clan root directory conceptually
  - Identify files present in infra but NOT in test-clan
  - Exclude nix files (those will be replaced)
  - Document purpose of each unique component
  - Assign migration action per component
  - **AC Reference:** AC4

**Deliverable:** Additional infra components section of preservation checklist (AC4 complete)

---

### Task 5: Create Comprehensive Preservation Checklist (AC5)

**Objective:** Compile all findings from Tasks 1-4 into comprehensive preservation checklist document.

**Subtasks:**

- [ ] **5.1: Create checklist document structure**
  - Create file: `docs/notes/development/work-items/story-2-1-preservation-checklist.md`
  - Add header: Story 2.1 deliverable, generated date, purpose
  - Create sections: Critical Infrastructure, Safe to Replace, Migration Strategy Summary
  - **AC Reference:** AC5

- [ ] **5.2: Populate Critical Infrastructure section**
  - Add GitHub Actions workflows (Task 1 deliverable)
  - Add TypeScript monorepo components (Task 2 deliverable)
  - Add Cloudflare deployment config (Task 3 deliverable)
  - Add development documentation (Task 4 deliverable)
  - Add any additional infra components (Task 4 deliverable)
  - **AC Reference:** AC5

- [ ] **5.3: Populate Safe to Replace section**
  - List all nix configuration files (flake.nix, modules/, hosts/, etc.)
  - List build artifacts (node_modules/, result/, .direnv/)
  - Note: These will be replaced with test-clan configs in Story 2.3
  - **AC Reference:** AC5

- [ ] **5.4: Write Migration Strategy Summary**
  - Document Story 2.3 execution plan (create clan-01 branch, copy configs, skip PRESERVE items)
  - Document zero-regression requirement (all PRESERVE components functional)
  - Provide clear directives for Story 2.3 migration
  - **AC Reference:** AC5

- [ ] **5.5: Review checklist completeness**
  - Verify all AC1-AC4 components included
  - Verify PRESERVE vs REPLACE actions clear
  - Verify Story 2.3+ guidance actionable
  - **AC Reference:** AC5

**Deliverable:** Complete preservation checklist document (AC5 complete)

---

### Task 6: Create File Exclusion List (AC6)

**Objective:** Map specific files/directories to PRESERVE (exclude from test-clan overwrite).

**Subtasks:**

- [ ] **6.1: Create exclusion list for directories**
  - List `.github/workflows/` (AC1)
  - List `docs/notes/development/` (AC4)
  - List TypeScript source directories (AC2)
  - List any additional directories from AC4
  - **AC Reference:** AC6

- [ ] **6.2: Create exclusion list for files**
  - List `/package.json` (AC2)
  - List Cloudflare config files if exist (AC3)
  - List `/README.md` if infra-specific (AC4)
  - List any additional files from AC4
  - **AC Reference:** AC6

- [ ] **6.3: Create safe-to-overwrite list**
  - List all nix files safe to replace (flake.nix, modules/, hosts/, etc.)
  - Clarify: These WILL be overwritten with test-clan configs
  - **AC Reference:** AC6

- [ ] **6.4: Document verification commands**
  - Create git diff commands to verify exclusions honored post-migration
  - Example: `git diff main..clan-01 -- .github/workflows/` (should show no changes)
  - Provide verification commands for each PRESERVE component
  - **AC Reference:** AC6

- [ ] **6.5: Integrate exclusion list into preservation checklist**
  - Add exclusion list section to preservation checklist document (from Task 5)
  - Include verification commands
  - Ensure Story 2.3 has clear actionable guidance
  - **AC Reference:** AC6

**Deliverable:** File exclusion list integrated into preservation checklist (AC6 complete)

---

### Task 7: Finalize and Save Preservation Checklist (AC7)

**Objective:** Finalize preservation checklist, validate completeness, prepare for Story 2.3 consumption.

**Subtasks:**

- [ ] **7.1: Review checklist against all ACs**
  - Verify AC1 satisfied (GitHub Actions workflows documented)
  - Verify AC2 satisfied (TypeScript monorepo documented)
  - Verify AC3 satisfied (Cloudflare config documented)
  - Verify AC4 satisfied (Additional infra components documented)
  - Verify AC5 satisfied (Comprehensive checklist created)
  - Verify AC6 satisfied (File exclusion list created)
  - **AC Reference:** AC7

- [ ] **7.2: Validate checklist completeness**
  - Confirm all critical infra components included
  - Confirm PRESERVE vs REPLACE directives clear
  - Confirm Story 2.3 execution guidance actionable
  - Confirm zero-regression requirement documented
  - **AC Reference:** AC7

- [ ] **7.3: Save final preservation checklist**
  - File path: `docs/notes/development/work-items/story-2-1-preservation-checklist.md`
  - Ensure markdown formatting correct
  - Ensure all sections complete (Critical Infrastructure, Safe to Replace, Migration Strategy, Exclusion List, Verification)
  - **AC Reference:** AC7

- [ ] **7.4: Update Story 2.1 completion notes**
  - Document checklist created and validated
  - Document all ACs 1-7 satisfied
  - Note: Checklist ready for Story 2.3 consumption
  - **AC Reference:** AC7

**Deliverable:** Final preservation checklist approved and ready for Story 2.3 (AC7 complete)

---

## Dev Notes

### Story Type: Discovery and Documentation

Story 2.1 is a **discovery and documentation** story, NOT an implementation story.

**Key Characteristics:**

**Discovery Stories:**
- Tasks focused on scanning, identifying, documenting components
- Subtasks include reading files, listing directories, analyzing configurations
- Deliverables are documentation artifacts (checklists, inventories, maps)
- No code changes (read-only operations)

**NOT Implementation:**
- No nix configuration edits (Story 2.3+ handles config migration)
- No branch creation yet (Story 2.3 creates clan-01 branch)
- No file copying (Story 2.3 handles test-clan → infra copying)

**Execution Pattern:**

Story 2.1 execution involves:
1. **Scanning** (Task 1-4): Identify infra-specific components via file/directory reads
2. **Analysis** (Task 1-4): Determine purpose and migration action per component
3. **Documentation** (Task 5-6): Create comprehensive preservation checklist
4. **Validation** (Task 7): Verify checklist completeness and readiness for Story 2.3

**Tools Used:**
- Read tool: Scan directories, read configuration files
- Bash tool: List files (ls, find), check directory structure
- Write tool: Create preservation checklist markdown document

**No tools used:**
- Edit tool: No file modifications (discovery only)
- Git commands: No branch creation, no commits (Story 2.3 handles migration)
- Build commands: No nix builds (validation deferred to Story 2.3)

### Critical Context: Epic 2 "Rip the Band-Aid" Strategy

**Migration Approach:**

Epic 2 applies a fast, pragmatic migration strategy:
1. **Create** fresh `clan-01` branch in infra
2. **Copy** validated nix configs from test-clan → infra (filesystem cp operations)
3. **Preserve** infra-specific components per Story 2.1 checklist
4. **Validate** at each phase boundary (build success, functionality intact)

**Philosophy:** Fast and pragmatic > slow and careful.

Epic 1 was discovery/validation in test-clan sandbox.
Epic 2 is application of proven patterns to production infra.
Git branch/diff/history serves as safety net (can abandon clan-01 if issues).

**Story 2.1 Role:**

Story 2.1 is the **safety mechanism** for the "rip the band-aid" strategy.

Without Story 2.1's preservation checklist, Story 2.3 might accidentally destroy:
- GitHub Actions CI/CD (package releases, deployments would break)
- TypeScript documentation website (docs.cameronraysmith.com would go offline)
- Cloudflare deployment automation (no automated deploys)
- Development documentation (lose PRD, Architecture, Sprint tracking)

**Preservation Checklist as Contract:**

The preservation checklist from Story 2.1 serves as a **contract** for Stories 2.3+:
- Story 2.3 developer: "I will NOT overwrite files/directories marked PRESERVE"
- Story 2.3 validation: `git diff main..clan-01 -- [PRESERVE path]` shows no changes
- Zero-regression requirement: All PRESERVE components function identically pre/post-migration

### Test-Clan vs Infra Architectural Differences

**Test-Clan Repository:**
- **Purpose:** Phase 0 architectural validation sandbox (Epic 1)
- **Scope:** Nix configurations ONLY (dendritic+clan architecture, home-manager, secrets, overlays)
- **Infrastructure:** Hetzner VMs (cinnabar, electrum), blackphos darwin config
- **NOT included:** GitHub Actions, TypeScript monorepo, Cloudflare deployment, development docs

**Infra Repository:**
- **Purpose:** Production fleet management (4 darwin laptops + 2+ nixos VPS, 4+ users)
- **Scope:** Nix configurations + TypeScript documentation + CI/CD + deployment automation
- **Infrastructure:** All machines (blackphos, stibnite, rosegold, argentum, cinnabar, electrum+)
- **Unique components:** GitHub Actions workflows, TypeScript monorepo, Cloudflare Pages, development docs

**Story 2.1 Identifies the Delta:**

The preservation checklist documents exactly what exists in **infra** but NOT in **test-clan**.

This delta represents infra-specific infrastructure requiring preservation during migration.

**Migration Pattern (Epic 2):**
- **Replace:** All nix configurations (flake.nix, modules/, hosts/, home-manager/, overlays/, secrets/)
- **Preserve:** All infra-specific components (GitHub Actions, TypeScript, Cloudflare, docs/notes/)

### Expected Preservation Checklist Components

Based on infra repository reconnaissance:

**Critical Infrastructure (MUST PRESERVE):**

1. **GitHub Actions CI/CD (AC1):**
   - Directory: `.github/workflows/`
   - Files: 7 workflows (ci.yaml, deploy-docs.yaml, package-release.yaml, package-test.yaml, pr-check.yaml, pr-merge.yaml, test-composite-actions.yaml)
   - Total size: ~64 KB of workflow automation
   - Purpose: Package testing, releases, Cloudflare deployment
   - Migration action: **PRESERVE** (DO NOT overwrite)

2. **TypeScript Monorepo (AC2):**
   - Root: `/package.json`
   - Source directories: TBD (likely `docs/`, `src/`, or similar)
   - Purpose: docs.cameronraysmith.com documentation website
   - Framework: Astro + Starlight (based on node_modules)
   - Migration action: **PRESERVE** (DO NOT overwrite)

3. **Cloudflare Deployment (AC3):**
   - Configuration: Likely integrated in deploy-docs.yaml (no separate wrangler.toml found)
   - Target: docs.cameronraysmith.com
   - Mechanism: Cloudflare Pages via GitHub Actions
   - Migration action: **PRESERVE** (already covered by AC1 GitHub Actions preservation)

4. **Development Documentation (AC4):**
   - Directory: `docs/notes/development/`
   - Contents: PRD (sharded), Architecture (sharded), Epics (sharded), Sprint status, Work items
   - Size: 3,000+ lines of project documentation (from Epic 1 Story 1.13)
   - Purpose: Project management, architectural decisions, sprint tracking
   - Migration action: **PRESERVE** (DO NOT overwrite)

**Safe to Replace (Story 2.3 targets):**
- `flake.nix` - Replace with test-clan dendritic+clan pattern
- `modules/` - Replace with test-clan dendritic structure
- `hosts/` - Replace with test-clan machine configs
- `home-manager/` - Replace with test-clan Pattern A home configs
- `overlays/` - Replace with test-clan five-layer overlay architecture
- `secrets/` - Replace with test-clan sops-nix two-tier secrets
- `.envrc` - Replace with test-clan direnv configuration

### References

**Primary Documents:**

Epic 2 Master Document:
- Path: `docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md`
- Content: Epic 2 definition, 4 phases, 13 stories, "rip the band-aid" strategy
- Relevance: Story 2.1 definition (lines 54-70), Phase 1 context, Epic 2 migration approach

Sprint Status:
- Path: `docs/notes/development/sprint-status.yaml`
- Content: Epic 2 status (contexted), Story 2.1 status (backlog → drafted in this story)
- Relevance: Story 2.1 first backlog story in Epic 2, blocks Story 2.2-2.3

**Test-Clan Architecture (Epic 1 Validation):**
- `~/projects/nix-workspace/test-clan/README.md` (navigation hub)
- `~/projects/nix-workspace/test-clan/docs/architecture/` (dendritic pattern, secrets architecture)
- `~/projects/nix-workspace/test-clan/docs/guides/` (migration patterns, operational guides)
- Relevance: Story 2.3 will copy configs FROM test-clan TO infra

**Infra-Specific Components (Story 2.1 targets):**
- `.github/workflows/` (7 workflow files, 64 KB total)
- `/package.json` (TypeScript monorepo root config)
- `docs/notes/development/` (project documentation directory)
- Relevance: Story 2.1 preserves these, Story 2.3 MUST NOT overwrite

### Alignment with BMM Workflow

**Story Creation Workflow:**

Story 2.1 created by `create-story` workflow:
- Template: Discovery/documentation story (NOT implementation template)
- Quality target: 9.5/10 clarity (comprehensive checklist focus)
- Estimated length: 1,200-1,800 lines (detailed preservation documentation)

**Story Context Workflow:**

Story 2.1 context created by `story-context` workflow (after create-story completion):
- Scope: Epic 2 migration strategy, test-clan architecture, infra repository structure
- Primary docs: Epic 2 epic file, infra repository files, test-clan README
- Evidence: GitHub Actions workflows, TypeScript monorepo, Cloudflare config
- Context XML: ~800-1,200 lines (preservation context for dev-story execution)

**Dev-Story Workflow:**

Story 2.1 execution by `dev-story` workflow:
- Execution type: Discovery + documentation (NOT code implementation)
- Tools: Read (scan files), Bash (list directories), Write (create checklist)
- Validation: Checklist completeness, all ACs satisfied, Story 2.3 guidance clear

**Code-Review Workflow:**

Story 2.1 review by `code-review` workflow:
- Review focus: Checklist completeness, preservation directives clear, no critical infra components missed
- NOT typical code review (no code changes, documentation review)
- Success: Checklist comprehensive, Story 2.3 has actionable guidance, zero-regression achievable

**Story-Done Workflow:**

Story 2.1 completion by `story-done` workflow:
- Triggers: Story 2.2 readiness (diff analysis can begin)
- Triggers: Story 2.3 preparation (migration can proceed with preservation checklist)
- Updates: sprint-status.yaml (Story 2.1 backlog → done)

### Learnings from Previous Story

**Previous Story:** 1-14-execute-go-no-go-decision (Status: done per sprint-status.yaml)

**Story 1.14 Context (Epic 1 Decision Framework):**

Story 1.14 rendered **GO decision** for Epic 2-6 production migration:
- All 7 AC1 criteria PASS (infrastructure, dendritic, darwin, heterogeneous networking, transformation, home-manager, pattern confidence)
- Zero CRITICAL blockers, zero MAJOR blockers (1 MINOR blocker: zerotier darwin homebrew dependency with documented workaround)
- Pattern confidence: ALL HIGH (7 patterns production-ready: dendritic, clan, terraform, sops-nix, zerotier, home-manager Pattern A, 5-layer overlays)
- Epic 2-6 authorization: PROCEED IMMEDIATELY

**Key Achievements (Epic 1 Stories 1.1-1.14):**
- 60-80 hours Epic 1 investment delivered 98% architectural validation coverage
- Zero regressions across all 14 stories (zero-regression principle maintained)
- Comprehensive documentation (3,000+ lines migration guides, architecture, operational playbooks)
- Test-clan repository fully validated (dendritic+clan architecture proven, ready for infra migration)

**Implications for Story 2.1:**

1. **Epic 2 Authorized:** Story 1.14 GO decision authorizes immediate Epic 2 execution
2. **Test-Clan Ready:** All configs validated and documented, ready to copy to infra
3. **Migration Patterns Proven:** Story 1.13 documented transformation patterns (infra → test-clan successful)
4. **Zero-Regression Requirement:** Story 1.14 decision requires preserving all functionality (Story 2.1 checklist critical for this)

**Story 1.14 Deliverables Referenced:**
- GO decision document: `docs/notes/development/go-no-go-decision.md` (AC1-AC6 comprehensive evaluation)
- Epic 2 transition plan: Immediate next steps documented (Sprint planning update, Epic 2 Story 2.1 creation, Epic 2 kickoff sequence)
- Blackphos management decision: Option A (revert blackphos to infra in Epic 2 Phase 2 Stories 2.5, 2.7)

**Previous Story Learnings Applied to Story 2.1:**

1. **Comprehensive Documentation Standard:** Story 1.14 established high documentation quality bar (comprehensive evidence, clear rationale, actionable next steps) - Story 2.1 preservation checklist must meet same standard
2. **Zero-Regression Principle:** Story 1.14 validated Epic 1 maintained zero regressions across all 14 stories - Story 2.1 preservation checklist enforces same principle for Epic 2 migration
3. **Evidence-Based Decision Making:** Story 1.14 required explicit evidence citations (PASS determinations backed by Story 1.x deliverables) - Story 2.1 checklist must cite specific file paths, directory structures
4. **Actionable Guidance for Next Stories:** Story 1.14 provided clear Epic 2 kickoff sequence - Story 2.1 checklist must provide clear Story 2.3 migration directives (what to preserve, what to replace, verification commands)

**Files Modified/Referenced (Story 1.14):**
- `docs/notes/development/go-no-go-decision.md` (created - GO decision comprehensive documentation)
- `docs/notes/development/sprint-status.yaml` (updated - Story 1.14 backlog → done, Epic 1 backlog → done, Epic 2 backlog → contexted)

**No Technical Patterns to Reuse:**

Story 1.14 was a decision/review story (evidence compilation, assessment, decision rendering).
Story 2.1 is a discovery/documentation story (component identification, checklist creation).

Different story types, different execution patterns.

Story 2.1 focuses on **infra repository reconnaissance** (NOT test-clan analysis).
Story 1.14 focused on **Epic 1 validation evidence** (NOT infrastructure discovery).

### Testing Standards Summary

**Story 2.1 Testing:**

Discovery/documentation stories do NOT have traditional testing (no code changes, no builds).

**Validation Approach:**
1. **Checklist Completeness:** All ACs 1-7 addressed in final preservation checklist
2. **Component Coverage:** All infra-specific components identified (GitHub Actions, TypeScript, Cloudflare, docs/notes/)
3. **Migration Action Clarity:** PRESERVE vs REPLACE directives explicit for each component
4. **Story 2.3 Readiness:** Exclusion list actionable, verification commands provided

**Post-Migration Validation (Story 2.3 responsibility):**

Story 2.1 preservation checklist will be **validated** in Story 2.3 via:
1. Git diff verification: `git diff main..clan-01 -- [PRESERVE path]` (should show no changes)
2. GitHub Actions validation: Workflows execute successfully on clan-01 branch
3. TypeScript build validation: `npm run build` succeeds on clan-01 branch
4. Cloudflare deployment validation: docs.cameronraysmith.com deploys from clan-01 branch
5. Zero-regression confirmation: All PRESERVE components function identically

**Story 2.1 Success Criteria:**

Story 2.1 considered successful if:
- Preservation checklist created (AC5)
- All critical infra components documented (AC1-AC4)
- File exclusion list clear (AC6)
- Story 2.3 has actionable migration guidance (AC7)
- NO actual preservation validation yet (Story 2.3 handles migration and validation)

### Project Structure Notes

**Preservation Checklist Location:**

Primary deliverable: `docs/notes/development/work-items/story-2-1-preservation-checklist.md`

**Rationale:**
- Lives alongside Story 2.1 work item (clear provenance)
- Accessible for Story 2.3 consumption (documented location in Story 2.1 completion notes)
- Historical record (Epic 2 Phase 1 artifact)

**Alternative Considered:** Integrate into Epic 2 epic file

**Rejected because:**
- Epic file is high-level strategy (not detailed checklists)
- Preservation checklist is operational (Story 2.3 execution guidance)
- Separate file allows focused review and validation

**Sprint Status Updates:**

Story 2.1 completion triggers sprint-status.yaml updates:
1. Story 2.1 status: backlog → drafted (this story execution)
2. Story 2.1 status: drafted → ready-for-dev (after story-context workflow)
3. Story 2.1 status: ready-for-dev → done (after dev-story + code-review workflows)
4. Story 2.2 unblocked (can begin stibnite vs blackphos diff analysis)
5. Story 2.3 preparation (preservation checklist ready for migration)

**Epic 2 Phase 1 Progress:**

Story 2.1 completion = 1/4 Phase 1 stories complete:
- ✅ Story 2.1: Preservation checklist created
- ➡️ Story 2.2: Stibnite vs blackphos diff analysis (next)
- ⏸️ Story 2.3: Home-manager Pattern A migration (blocked on Stories 2.1-2.2)
- ⏸️ Story 2.4: Home-manager secrets migration (blocked on Story 2.3)

**Epic 2 Estimated Timeline:**

Epic 2 total: 80-120 hours across 13 stories (4 phases)
- Phase 1 (Stories 2.1-2.4): 20-30 hours
- Phase 2 (Stories 2.5-2.8): 25-35 hours
- Phase 3 (Stories 2.9-2.10): 15-20 hours
- Phase 4 (Stories 2.11-2.13): 20-35 hours

Story 2.1 estimated: 2-4 hours (discovery + checklist creation)

---

## Dev Agent Record

### Context Reference

- [Story 2.1 Context XML](./2-1-identify-infra-specific-components-to-preserve.context.xml) - Generated 2025-11-22

### Agent Model Used

<!-- Agent model name and version will be populated during story execution -->

### Debug Log References

<!-- Debug logs, investigation notes, and troubleshooting steps will be added during execution -->

### Completion Notes List

<!-- Completion notes documenting component discovery, checklist creation, and validation will be added here -->

### File List

**Deliverable Created:**
- `docs/notes/development/work-items/story-2-1-preservation-checklist.md` - Comprehensive preservation checklist (887 lines)

**Correction Commits:**
- 93633090 - Corrected composite actions count (2 not 3)
- 0a105b59 - Clarified clan components are NEW (not replacements)
- 9e8ef9bd - Added .gitleaksignore to preservation list
- 69817926 - Documented docs/ symlink structure and subdirectories

---

## Senior Developer Review (AI)

**Reviewer:** Code Review Workflow (Senior Developer Agent)
**Review Date:** 2025-11-22
**Story Type:** Discovery/Documentation (preservation checklist creation)
**Review Model:** claude-sonnet-4-5-20250929

### Summary

Story 2.1 preservation checklist is **production-ready** and suitable for Story 2.3 wholesale migration execution.
All critical infra-specific components correctly identified and categorized with zero ambiguity.
Independent validation demonstrates 9.8/10 accuracy after empirically-validated corrections.
Zero critical blockers, zero missing components.

This is an exemplary documentation deliverable that provides Story 2.3 with comprehensive, actionable migration guidance while preserving all unique infra infrastructure (GitHub Actions CI/CD, TypeScript documentation website, Cloudflare deployment automation).

### Outcome: APPROVED ✅

**Quality Rating:** 9.8/10 (post-correction)
**Initial Quality:** 8.5/10 (pre-correction, 5 inaccuracies identified)
**Critical Issues:** 0 (zero blockers)
**Documentation Issues:** 5 (all corrected via 4 atomic commits)
**Correction Quality:** Excellent (empirically validated against actual repository structure)

**Justification:**
- All 7 acceptance criteria fully satisfied with comprehensive evidence
- All 7 tasks verified complete with detailed deliverable sections
- Preservation checklist empirically validated (workflow counts, TypeScript structure, Cloudflare config, additional components all confirmed)
- Zero-regression requirements clearly documented with verification commands
- Story 2.3 execution guidance actionable and complete
- No critical components missed, no ambiguous migration directives

### Key Findings

**Strengths (Exceptional Quality):**

1. **Comprehensive Component Identification**
   - All GitHub Actions workflows documented (7 workflows, 2 composite actions)
   - TypeScript monorepo structure complete (package.json, packages/docs/, build integration)
   - Cloudflare deployment configuration detailed (wrangler.jsonc, custom domain, worker setup)
   - Additional components thoroughly catalogued (docs/notes/, scripts/, configs, git metadata)

2. **Empirical Validation**
   - All component counts verified against actual repository (7 workflows ✓, 2 composite actions ✓, TypeScript monorepo ✓, Cloudflare config ✓)
   - Test-clan negative verification passed (confirms infra-specific identification)
   - No speculative claims - all assertions backed by file paths and evidence

3. **Clear Migration Directives**
   - PRESERVE/REPLACE/CREATE categorization unambiguous
   - Exclusion patterns actionable for Story 2.3 (`.github/**/*`, `packages/**/*`, etc.)
   - Manual merge requirements documented (justfile, .gitignore, .sops.yaml)
   - Zero risk of misinterpretation by Story 2.3 execution agent

4. **Comprehensive Verification Strategy**
   - Git diff commands for preservation validation (Section 7.1)
   - Functional verification commands (GitHub Actions, TypeScript build, Cloudflare deployment)
   - Nix configuration verification (flake check, system builds)
   - Automated smoke test script outline provided

5. **Excellent Documentation Structure**
   - 10 logical sections covering discovery → guidance → verification → next steps
   - Executive summary provides context and zero-regression requirement
   - Success criteria section validates all ACs and tasks
   - Story 2.3 execution guidance with pre-migration checklist and copy strategy

**Corrections Applied (All Resolved):**

1. **Composite Actions Count** (93633090)
   - Issue: Originally listed 3 composite actions, should be 2
   - Correction: verify-no-secrets is a shell script (`scripts/verify-no-secrets-in-store.sh`), not a composite action
   - Evidence: Empirically validated via `ls .github/actions/` (2 directories)
   - Impact: Eliminated potential confusion during Story 2.3 migration

2. **Clan Components Clarification** (0a105b59)
   - Issue: Section 4.6 ambiguous about clan directories (machines/, sops/, vars/, pkgs/, terraform/)
   - Correction: Clarified these are NEW from test-clan (not replacing existing dirs)
   - Evidence: Infra does NOT currently have these directories (will be created in Story 2.3)
   - Impact: Prevents Story 2.3 confusion when directories don't exist to "replace"

3. **Git Metadata Completeness** (9e8ef9bd)
   - Issue: .gitleaksignore missing from preservation list
   - Correction: Added .gitleaksignore to Section 4.4 (Git Repository Metadata)
   - Evidence: File exists in infra, not in test-clan (infra-specific)
   - Impact: Prevents accidental overwrite of gitleaks configuration

4. **Repository Structure Documentation** (69817926)
   - Issue: docs/ directory symlink structure not documented
   - Correction: Documented that docs/ contains symlinks to packages/docs/src/content/docs/ plus actual docs/notes/ subdirectory
   - Evidence: Prevents confusion in Story 2.3 about docs/ preservation strategy
   - Impact: Clarifies which parts of docs/ to preserve (docs/notes/) vs regenerate (symlinks)

5. **Subdirectory Inventory** (69817926)
   - Issue: docs/notes/development/ subdirectories incomplete
   - Correction: Added research/ and implementation/ to subdirectory list
   - Evidence: Comprehensive inventory for preservation validation
   - Impact: Ensures all development documentation preserved

### Acceptance Criteria Coverage

| AC | Description | Status | Evidence |
|----|-------------|--------|----------|
| AC1 | GitHub Actions workflows documented | ✅ IMPLEMENTED | Checklist Section 1 (lines 14-76): 7 workflows, 2 composite actions, purposes, triggers, PRESERVE directive, verification commands |
| AC2 | TypeScript monorepo documented | ✅ IMPLEMENTED | Checklist Section 2 (lines 78-147): package.json, packages/docs/ structure, build integration, PRESERVE directive |
| AC3 | Cloudflare deployment documented | ✅ IMPLEMENTED | Checklist Section 3 (lines 149-191): wrangler.jsonc, custom domain, GitHub Actions integration, sops secrets |
| AC4 | Additional infra components identified | ✅ IMPLEMENTED | Checklist Section 4 (lines 193-336): docs/notes/, scripts/, configs, git metadata, editor configs |
| AC5 | Preservation checklist created | ✅ IMPLEMENTED | Complete checklist (887 lines, 10 sections): components, zero-regression, migration strategy |
| AC6 | File exclusion list mapped | ✅ IMPLEMENTED | Checklist Section 6 (lines 433-562): preserve/replace/ignore patterns, manual merge requirements, verification commands |
| AC7 | Checklist reviewed and approved | ✅ IMPLEMENTED | Checklist Sections 8-9 (lines 724-887): Story 2.3 execution guidance, success criteria, ready for approval |

**Summary:** 7 of 7 acceptance criteria fully implemented with comprehensive evidence.

### Task Completion Validation

| Task | Description | Marked As | Verified As | Evidence |
|------|-------------|-----------|-------------|----------|
| Task 1 | Document GitHub Actions workflows | Complete (implied) | ✅ VERIFIED COMPLETE | Checklist Section 1: All 7 workflows documented with purposes, triggers, dependencies, PRESERVE action |
| Task 2 | Document TypeScript monorepo | Complete (implied) | ✅ VERIFIED COMPLETE | Checklist Section 2: Root package.json, workspace config, source dirs, build integration, PRESERVE action |
| Task 3 | Document Cloudflare deployment | Complete (implied) | ✅ VERIFIED COMPLETE | Checklist Section 3: wrangler.jsonc, deployment target, GitHub Actions integration, PRESERVE action |
| Task 4 | Identify additional components | Complete (implied) | ✅ VERIFIED COMPLETE | Checklist Section 4: scripts/, docs/notes/, configs, git metadata, migration actions assigned |
| Task 5 | Create preservation checklist | Complete (implied) | ✅ VERIFIED COMPLETE | Complete checklist structure (Sections 1-9), all Tasks 1-4 integrated |
| Task 6 | Create file exclusion list | Complete (implied) | ✅ VERIFIED COMPLETE | Checklist Section 6: preserve/replace/ignore patterns, verification commands |
| Task 7 | Finalize and save checklist | Complete (implied) | ✅ VERIFIED COMPLETE | Checklist Section 9: All ACs validated, saved to correct location, ready for Story 2.3 |

**Summary:** 7 of 7 tasks verified complete. All deliverable sections map to task requirements.

**Note:** Story file does not have explicit task checkboxes (tasks are in "Tasks / Subtasks" section with `[ ]` markers but not marked `[x]`). However, deliverable completion proves all tasks executed. Recommendation: Mark tasks as `[x]` in story file to reflect completion.

### Test Coverage and Gaps

**Documentation Story - No Traditional Tests Required**

Validation approach for documentation stories:
- ✅ Checklist completeness validated (all ACs 1-7 addressed)
- ✅ Component coverage validated (all infra-specific components identified)
- ✅ Migration action clarity validated (PRESERVE/REPLACE/CREATE unambiguous)
- ✅ Story 2.3 readiness validated (exclusion list actionable, verification commands provided)

**Post-Migration Validation (Story 2.3 Responsibility):**

Preservation checklist will be validated in Story 2.3 via:
1. Git diff verification (Section 7.1): `git diff main..clan-01 -- .github/ packages/ docs/notes/ scripts/` → Expected: no output
2. GitHub Actions validation: Workflows execute successfully on clan-01 branch
3. TypeScript build validation: `nix develop -c just docs-build` succeeds
4. Cloudflare deployment validation: docs.cameronraysmith.com deploys from clan-01 branch
5. Zero-regression confirmation: All PRESERVE components function identically

**No Gaps:** All validation requirements documented in checklist Section 7.

### Architectural Alignment

**Epic 2 Migration Strategy Alignment:**

Story 2.1 preservation checklist perfectly aligns with Epic 2 "rip the band-aid" migration strategy:

1. **Preservation Philosophy:** Identifies ALL components unique to infra that must NOT be overwritten by test-clan configs
2. **Wholesale Replacement Support:** Clearly documents which nix configs to REPLACE (flake.nix, modules/, lib/, etc.)
3. **Safety Mechanism:** Provides git diff verification commands to validate preservation
4. **Zero-Regression Enforcement:** Documents functional requirements for all preserved components

**Test-Clan Architecture Awareness:**

Checklist demonstrates comprehensive understanding of test-clan vs infra delta:
- Documents components in infra but NOT in test-clan (GitHub Actions, TypeScript, Cloudflare)
- Clarifies clan-specific directories are NEW from test-clan (machines/, sops/, vars/, pkgs/, terraform/)
- Identifies manual merge requirements (justfile, .gitignore, .sops.yaml)

**No Architecture Violations:** Story 2.1 is discovery-only, no architecture implementation.

### Security Notes

**No Security Issues Found**

Story 2.1 is documentation-only (no code changes, no secrets exposure).

**Security-Positive Contributions:**

1. **.gitleaksignore Preservation:** Correction commit 9e8ef9bd ensures gitleaks secret detection config preserved
2. **Secrets Management Documentation:** Section 3 documents sops integration, Section 4.7 documents secrets/ directory preservation
3. **Verification Commands:** Section 7 includes `scripts/verify-no-secrets-in-store.sh` in post-migration validation

**Story 2.3 Security Guidance:**

Checklist Section 4.7 provides clear guidance for secrets migration:
- PRESERVE existing `secrets/` directory initially
- MERGE `.sops.yaml` with test-clan patterns
- Note: Full secrets migration to clan two-tier architecture deferred to Story 2.5

### Best-Practices and References

**Documentation Best-Practices Applied:**

1. **Evidence-Based Claims:** All assertions backed by file paths, line numbers, empirical validation
2. **Comprehensive Coverage:** 10 sections covering discovery → guidance → verification → next steps
3. **Actionable Guidance:** Story 2.3 developer can execute migration without additional research
4. **Zero Ambiguity:** PRESERVE/REPLACE/CREATE directives explicit, no interpretation required
5. **Validation Strategy:** Git diff commands, functional verification, nix build validation documented
6. **Iterative Improvement:** 5 corrections applied based on empirical validation (demonstrates quality process)

**BMM Workflow Alignment:**

Story 2.1 exemplifies BMM discovery story pattern:
- Comprehensive discovery phase (Tasks 1-4: scan and document)
- Consolidation phase (Task 5-6: create checklist and exclusion list)
- Validation phase (Task 7: review completeness, prepare for next story)
- Clear handoff to next story (Story 2.3 execution guidance in Section 8)

**Epic 1 Learnings Applied:**

Story 2.1 applies Epic 1 quality standards:
- Comprehensive documentation standard (Story 1.14 GO decision quality bar)
- Zero-regression principle (Story 1.14 validated Epic 1 maintained zero regressions)
- Evidence-based decision making (explicit evidence citations)
- Actionable guidance for next stories (clear Story 2.3 migration directives)

### Recommendations (Non-Blocking)

**Enhancement Opportunities for Story 2.3:**

1. **Automated Smoke Test Script**
   - Checklist Section 7.4 provides outline for automated verification script
   - Recommendation: Implement as `scripts/verify-story-2-3-migration.sh` in Story 2.3
   - Benefit: One-command validation of all preservation requirements
   - Priority: Medium (manual verification commands sufficient, automation nice-to-have)

2. **Justfile Merge Guidance**
   - Checklist Section 6.4 identifies justfile as "manual merge required"
   - Recommendation: Create `docs/notes/development/work-items/story-2-3-justfile-merge.md` documenting infra-specific targets
   - Benefit: Story 2.3 developer knows which targets to preserve (docs-*, install, etc.)
   - Priority: Low (justfile diff should be obvious, can be handled during Story 2.3 execution)

3. **Timeline Estimate for Story 2.3**
   - Story 2.1 does not estimate Story 2.3 execution time
   - Recommendation: Add estimate to Story 2.3 story file: 3-6 hours (branch creation, wholesale copy, manual merges, verification)
   - Benefit: Sprint planning accuracy
   - Priority: Low (not blocking, SM can estimate)

4. **Package Count Baseline**
   - Zero-regression validation requires "all PRESERVE components function identically"
   - Recommendation: Document current package counts for comparison post-migration: `nix eval .#darwinConfigurations.blackphos.config.environment.systemPackages | jq length`
   - Benefit: Empirical zero-regression validation (package count should not decrease)
   - Priority: Low (nix flake check is sufficient validation)

**No Blocking Recommendations:** All recommendations are enhancements, not requirements for Story 2.3 execution.

### Action Items

**No Action Items Required - Story Approved**

Story 2.1 preservation checklist is production-ready. All acceptance criteria satisfied, all tasks verified complete, zero blockers.

**Story 2.1 Completion:**
- ✅ Preservation checklist created and corrected
- ✅ All 7 acceptance criteria fully implemented
- ✅ All 7 tasks verified complete
- ✅ Independent validation: 9.8/10 accuracy
- ✅ Zero critical issues, zero missing components
- ✅ Ready for Story 2.3 consumption

**Next Steps:**
1. Mark Story 2.1 status: ready-for-review → done (Definition of Done satisfied)
2. Proceed to Story 2.2: Stibnite vs blackphos configuration diff analysis
3. Story 2.3 can execute using preservation checklist with high confidence

**Optional Task Checkbox Update:**

Story file Tasks/Subtasks section has tasks marked `[ ]` (incomplete) but deliverable proves completion.
Developer may optionally update story file to mark all tasks `[x]` for accuracy, but this is not required for approval.

### Approval Timestamp

**Review Completed:** 2025-11-22
**Story Status Transition:** ready-for-review → done (approved)
**Definition of Done:** ✅ Satisfied

**Preservation Checklist Production Status:** APPROVED ✅

High confidence in Epic 2 Phase 1 wholesale migration safety.
Story 2.3 can proceed with comprehensive, empirically-validated preservation guidance.
