# Story 2.1: Infra-Specific Components Preservation Checklist

**Generated**: 2025-11-22
**Story**: Epic 2, Story 2.1 - Identify infra-specific components to preserve during migration
**Purpose**: Document all infra-specific components that MUST NOT be overwritten when Story 2.3 copies nix configurations from test-clan → infra

## Executive Summary

This checklist identifies components unique to the infra repository that must be preserved during the Epic 2 "rip the band-aid" migration from nixos-unified to clan+dendritic architecture.
The migration will wholesale replace nix configurations but preserve all non-nix infrastructure components.

**Zero-Regression Requirement**: All preserved components must function identically pre/post-migration.

## 1. GitHub Actions CI/CD

**Description**: Complete CI/CD pipeline for nix builds, package testing, semantic releases, and documentation deployment

**Migration Action**: PRESERVE (infra-specific, NOT in test-clan)

### Workflow Files

All files in `.github/workflows/`:

1. **ci.yaml** (41 KB)
   - Purpose: Main CI pipeline for nix builds across multiple categories
   - Features: Composite action caching, content-addressed builds, path filtering
   - Dependencies: `.github/actions/` (setup-nix, cached-ci-job, verify-no-secrets)

2. **deploy-docs.yaml** (4.6 KB)
   - Purpose: Deploy documentation website to Cloudflare Workers
   - Integration: Uses nix develop environment, sops secrets, wrangler CLI
   - Environments: preview (branch deployments) and production (infra.cameronraysmith.net)

3. **package-release.yaml** (5.7 KB)
   - Purpose: Semantic versioning releases with conventional commits
   - Features: semantic-release with monorepo support, major tag generation

4. **package-test.yaml** (4.5 KB)
   - Purpose: Test TypeScript packages (docs website)
   - Coverage: Unit tests (vitest), E2E tests (playwright)

5. **pr-check.yaml** (480 B)
   - Purpose: Trigger CI checks on pull requests
   - Integration: Calls ci.yaml workflow

6. **pr-merge.yaml** (648 B)
   - Purpose: Trigger documentation deployment on PR merge
   - Integration: Calls deploy-docs.yaml workflow

7. **test-composite-actions.yaml** (7.4 KB)
   - Purpose: Test GitHub Actions composite actions in isolation
   - Coverage: setup-nix, cached-ci-job, verify-no-secrets actions

### Composite Actions

All files in `.github/actions/`:

- `setup-nix/action.yml` - Nix installer with sops integration
- `cached-ci-job/action.yaml` - Content-addressed job caching

**Note:** verify-no-secrets functionality exists as `scripts/verify-no-secrets-in-store.sh` (script), not as a composite action.

### Story 2.3 Directive

**Exclusion Pattern**: `.github/**/*`

**Verification**:
```bash
# Post-migration: Ensure GitHub Actions unchanged
git diff main..clan-01 -- .github/
# Expected: no output (no changes)

# Verify workflows still functional
gh workflow list
gh workflow view ci.yaml
```

## 2. TypeScript Monorepo (Documentation Website)

**Description**: Next.js/Astro documentation website deployed to docs.cameronraysmith.com

**Migration Action**: PRESERVE (infra-specific, NOT in test-clan)

### Root Package Configuration

1. **package.json** (root monorepo config)
   - Workspace: `packages/*`
   - Package manager: `bun@1.1.38`
   - Scripts: `test-release`, `preview-version`
   - Dependencies: semantic-release, conventional-changelog tooling

2. **package-lock.json** (if exists)
   - Dependency lockfile for npm/bun

### Documentation Package

Location: `packages/docs/`

**Structure**:
- `package.json` - Docs package dependencies (Next.js/Astro, React, testing libraries)
- `astro.config.ts` - Astro framework configuration
- `wrangler.jsonc` - Cloudflare Workers deployment config
- `tsconfig.json` - TypeScript compiler configuration
- `vitest.config.ts` - Unit test configuration
- `playwright.config.ts` - E2E test configuration
- `src/` - Source code (components, pages, content)
- `public/` - Static assets
- `dist/` - Build output (regenerable, exclude from preservation)
- `node_modules/` - Dependencies (regenerable, exclude from preservation)
- `.astro/` - Build cache (regenerable, exclude from preservation)
- `coverage/` - Test coverage (regenerable, exclude from preservation)

### Build Dependencies

**Integration with Nix**:
- justfile targets: `install`, `docs-build`, `docs-deploy-preview`, `docs-deploy-production`, `docs-linkcheck`
- Nix provides bun via devShell
- CI uses `nix develop -c just [target]` pattern

**External Services**:
- Cloudflare Workers (infra-docs worker)
- Custom domain: infra.cameronraysmith.net
- Preview URLs: b-{branch}-infra-docs.sciexp.workers.dev

### Story 2.3 Directive

**Exclusion Patterns**:
```
packages/**/*
package.json (root)
```

**Verification**:
```bash
# Post-migration: Ensure TypeScript monorepo unchanged
git diff main..clan-01 -- packages/ package.json
# Expected: no output (no changes)

# Verify build still works
nix develop -c just install
nix develop -c just docs-build
# Expected: successful build with no errors

# Verify deployment configuration intact
cat packages/docs/wrangler.jsonc | jq '.routes'
# Expected: infra.cameronraysmith.net route present
```

## 3. Cloudflare Deployment Configuration

**Description**: Cloudflare Workers configuration for documentation website deployment

**Migration Action**: PRESERVE (infra-specific configuration)

### Configuration Files

1. **packages/docs/wrangler.jsonc**
   - Worker name: `infra-docs`
   - Main entry: `./dist/_worker.js/index.js`
   - Custom domain: `infra.cameronraysmith.net`
   - Assets binding: Static site serving
   - Compatibility: nodejs_compat, global_fetch_strictly_public

2. **packages/docs/worker-configuration.d.ts**
   - TypeScript types for Cloudflare Workers environment

### Secrets Management

**GitHub Secrets** (used by deploy-docs.yaml):
- `SOPS_AGE_KEY` - Age private key for sops-nix decryption
- Cloudflare API credentials (managed via sops, see secrets/ directory)

**Sops Integration**:
- Age keys stored in `secrets/` directory
- Decrypted at deployment time via SOPS_AGE_KEY environment variable
- See `scripts/sops/` for key management utilities

### Story 2.3 Directive

**Exclusion Pattern**: `packages/docs/wrangler.jsonc`, `packages/docs/worker-configuration.d.ts`

**Verification**:
```bash
# Post-migration: Verify Cloudflare config unchanged
git diff main..clan-01 -- packages/docs/wrangler.jsonc packages/docs/worker-configuration.d.ts
# Expected: no output

# Test deployment (dry-run)
cd packages/docs && nix develop -c wrangler deploy --dry-run
# Expected: successful dry-run with infra.cameronraysmith.net route
```

## 4. Additional Infra-Unique Components

**Description**: Project-specific files and directories not present in test-clan

**Migration Action**: PRESERVE (infra-specific) or DOCUMENT (case-by-case)

### 4.1 Project Documentation

**Location**: `docs/notes/development/`

**Subdirectories**:
- `PRD/` - Product requirements (sharded markdown)
- `architecture/` - Architecture documentation (sharded markdown)
- `epics/` - Epic breakdown and planning
- `work-items/` - Story files and context
- `research/` - Research artifacts and exploration
- `implementation/` - Implementation notes
- [other subdirectories]

**Repository Structure Note**: The `docs/` directory at repository root contains:
- Symlinks to `packages/docs/src/content/docs/` (documentation website source)
- Actual subdirectory `docs/notes/` (project planning and development docs)

**Migration Action**: PRESERVE `docs/notes/` entirely (infra-specific project documentation). Symlinks will be recreated by build process.

**Story 2.3 Directive**: `docs/notes/**/*` (preserve all)

### 4.2 Scripts Directory

**Location**: `scripts/`

**Contents**:
```
scripts/
├── bisect-nixpkgs.sh           # Nixpkgs regression debugging
├── inspect-derivation.sh       # Nix derivation analysis
├── preview-version.sh          # Semantic release version preview (used by package.json)
├── validate-mcp-servers.sh     # MCP server configuration validation
├── verify-no-secrets-in-store.sh  # Secret leak detection
├── verify-system.sh            # System configuration validation
├── ci/                         # CI-specific scripts
│   ├── ci-build-category.sh
│   ├── ci-build-local.sh
│   ├── ci-cache-category.sh
│   ├── ci-show-outputs.sh
│   ├── test-all-categories-unattended.sh
│   └── validate-run.sh
└── sops/                       # Sops key management
    ├── deploy-host-key.sh
    ├── extract-key-details.sh
    ├── sync-age-keys.sh
    ├── update-sops-yaml.sh
    └── validate-correspondences.sh
```

**Analysis**:
- `preview-version.sh`: Referenced by package.json scripts (PRESERVE)
- `ci/`: Referenced by GitHub Actions workflows (PRESERVE)
- `sops/`: Sops key management utilities (ANALYZE - may overlap with test-clan)
- `verify-*.sh`, `validate-*.sh`: Validation scripts (PRESERVE)
- `bisect-nixpkgs.sh`, `inspect-derivation.sh`: Debugging utilities (PRESERVE)

**Migration Action**: PRESERVE (scripts/ is infra-specific, NOT in test-clan)

**Story 2.3 Directive**: `scripts/**/*`

### 4.3 Repository Root Configuration

**Files**:

1. **CLAUDE.md** (project-specific AI instructions)
   - Content: Infra architecture overview, machine fleet, migration context
   - Migration Action: PRESERVE (infra-specific content)

2. **README.md** (repository documentation)
   - Content: Will need UPDATE after migration (references old architecture)
   - Migration Action: PRESERVE (edit manually post-migration)

3. **Makefile** (build automation)
   - Content: Legacy build targets (may be superseded by justfile)
   - Migration Action: PRESERVE (evaluate for removal post-migration)

4. **biome.json** (JavaScript/TypeScript linter config)
   - Purpose: TypeScript monorepo code quality
   - Migration Action: PRESERVE (docs package dependency)

5. **justfile** (modern build automation)
   - Content: Nix operations, docs deployment, testing targets
   - Migration Action: COMPARE with test-clan justfile, MERGE differences

6. **config.nix** (legacy configuration file)
   - Content: Old nixos-unified configuration
   - Migration Action: REPLACE (will be superseded by clan configuration)

**Story 2.3 Directive**:
```
PRESERVE: CLAUDE.md, README.md, Makefile, biome.json
MERGE: justfile (compare with test-clan, integrate infra-specific targets)
REPLACE: config.nix (superseded by clan vars)
```

### 4.4 Git Repository Metadata

**Files**:
- `.git/` - Git repository database (NEVER touch)
- `.gitignore` - Git ignore patterns (COMPARE with test-clan, MERGE unique patterns)
- `.gitattributes` - Git attribute configuration (COMPARE with test-clan, MERGE if needed)
- `.gitleaksignore` - Gitleaks secret detection ignore patterns (PRESERVE)

**Migration Action**: PRESERVE `.git/` and `.gitleaksignore`, MERGE `.gitignore` and `.gitattributes` unique patterns

### 4.5 Editor and IDE Configuration

**Files**:
- `.bmad/` - BMM workflow system (PRESERVE if present)
- `.claude/` - Claude Code project configuration (PRESERVE if present, typically in ~/.claude/)
- `.vscode/` - VS Code workspace settings (PRESERVE if present)
- `.direnv/` - direnv cache (regenerable, EXCLUDE)

**Migration Action**: PRESERVE if present (editor-specific, project configuration)

### 4.6 Nix Configuration Directories (REPLACE)

These directories WILL be replaced by test-clan equivalents:

**Replace with test-clan versions**:
- `configurations/` → NOT in test-clan (legacy nixos-unified, DELETE)
- `lib/` → Replace with test-clan lib/ (DRY configuration)
- `modules/` → Replace with test-clan modules/ (dendritic modules)
- `overlays/` → Replace with test-clan overlays/ (package overlays)
- `tests/` → Replace with test-clan test structure if present
- `flake.nix` → Replace with test-clan flake.nix (clan+dendritic architecture)

**Note**: The core nix configuration is the PRIMARY migration target. These are explicitly REPLACED, not preserved.

### 4.7 Secrets and State Directories

**Directories**:
- `secrets/` - Age keys and sops configuration (PRESERVE, may need MERGE)
- `.sops.yaml` - Sops configuration (COMPARE with test-clan, MERGE)

**Migration Action**: PRESERVE existing secrets, MERGE .sops.yaml with test-clan patterns

## 5. Zero-Regression Requirements

**Definition**: All preserved components must function identically before and after migration.

### 5.1 GitHub Actions Workflows

**Requirements**:
- All 7 workflow files execute without errors
- CI builds complete successfully for all categories
- Documentation deployment reaches Cloudflare Workers
- Semantic release versioning operates correctly
- Composite actions function as expected

**Verification Strategy**:
```bash
# Trigger CI workflow
gh workflow run ci.yaml --ref clan-01

# Check workflow status
gh run list --workflow=ci.yaml --branch=clan-01 --limit 1

# Verify docs deployment
gh workflow run deploy-docs.yaml --ref clan-01 -f branch=clan-01 -f environment=preview

# Check deployment URL
curl -I https://b-clan-01-infra-docs.sciexp.workers.dev
```

### 5.2 TypeScript Documentation Website

**Requirements**:
- `nix develop -c just install` completes without errors
- `nix develop -c just docs-build` produces valid dist/ output
- `nix develop -c just docs-linkcheck` validates all internal links
- `nix develop -c just docs-deploy-preview` deploys to Cloudflare Workers
- Build output matches pre-migration structure

**Verification Strategy**:
```bash
# Clean build from clan-01 branch
git checkout clan-01
nix develop -c just install
nix develop -c just docs-build

# Compare build outputs
ls -la packages/docs/dist/

# Test local preview
nix develop -c just docs-preview
# Visit http://localhost:4321

# Verify Wrangler configuration
cd packages/docs && nix develop -c wrangler deploy --dry-run
```

### 5.3 Cloudflare Deployment

**Requirements**:
- wrangler.jsonc configuration valid
- Custom domain route (infra.cameronraysmith.net) preserved
- Preview URL pattern maintained (b-{branch}-infra-docs.sciexp.workers.dev)
- Sops secrets decryption functional

**Verification Strategy**:
```bash
# Validate wrangler config
cd packages/docs && nix develop -c wrangler deploy --dry-run

# Check custom domain
nix develop -c wrangler deployments list --name infra-docs

# Test preview deployment
nix develop -c just docs-deploy-preview clan-01
curl -I https://b-clan-01-infra-docs.sciexp.workers.dev
```

### 5.4 Scripts Functionality

**Requirements**:
- `scripts/preview-version.sh` executes via `npm run preview-version`
- `scripts/ci/*.sh` scripts execute via GitHub Actions
- `scripts/sops/*.sh` scripts operate with clan secrets structure
- `scripts/verify-*.sh` validation scripts pass

**Verification Strategy**:
```bash
# Test semantic release preview
npm run preview-version

# Test sops scripts
scripts/sops/validate-correspondences.sh

# Test verification scripts
scripts/verify-no-secrets-in-store.sh
scripts/verify-system.sh
```

## 6. File Exclusion List for Story 2.3

### 6.1 Preserve Patterns (Do NOT Copy from test-clan)

**GitHub Actions and CI/CD**:
```
.github/**/*
```

**TypeScript Documentation Website**:
```
packages/**/*
package.json
biome.json
```

**Project-Specific Assets**:
```
docs/notes/**/*
scripts/**/*
CLAUDE.md
README.md
Makefile
.bmad/**/*
```

**Git Repository Metadata**:
```
.git/**/*
.gitignore (merge unique patterns)
.gitattributes (merge unique patterns)
```

**Secrets and State** (manual merge required):
```
secrets/**/*
.sops.yaml (compare and merge)
```

### 6.2 Replace Patterns (COPY from test-clan → infra)

**Core Nix Configuration**:
```
flake.nix
lib/**/*
modules/**/*
overlays/**/*
```

**Clan Architecture Components** (NEW from test-clan):
```
machines/**/* (NEW - clan machine definitions)
sops/**/* (NEW - clan sops structure, may require merge with existing secrets/)
vars/**/* (NEW - clan vars)
pkgs/**/* (NEW - package definitions)
terraform/**/* (NEW - infrastructure as code)
inventory.json (NEW - clan inventory)
```

**Important:** These directories do NOT currently exist in infra. Story 2.3 will CREATE them by copying from test-clan. Existing infra `secrets/` directory will be preserved initially, then migrated to clan's two-tier architecture in Story 2.5.

**Build and Development**:
```
justfile (merge with infra-specific targets)
```

**Documentation** (test-clan has minimal docs):
```
docs/ (compare structures, may need selective merge)
```

### 6.3 Ignore Patterns (Do NOT Copy - Regenerable Artifacts)

**Build Outputs**:
```
result
result-*
dist/
.astro/
```

**Dependency Caches**:
```
node_modules/
.direnv/
.devenv/
```

**Test Artifacts**:
```
coverage/
test-results/
playwright-report/
.wrangler/
```

**Editor and OS Files**:
```
.DS_Store
*.swp
*.swo
*~
.vscode/ (unless project-specific config)
.idea/
```

### 6.4 Manual Merge Required

These files exist in both repositories and need intelligent merging:

1. **justfile**
   - Action: Compare test-clan and infra versions
   - Preserve: Infra-specific targets (docs-*, install, etc.)
   - Adopt: Test-clan nix targets (may be improved)

2. **.gitignore**
   - Action: Union of both versions
   - Preserve: TypeScript-specific patterns (node_modules/, dist/, coverage/)
   - Adopt: Test-clan nix-specific patterns

3. **.sops.yaml**
   - Action: Merge sops configurations
   - Preserve: Infra-specific age keys
   - Adopt: Test-clan two-tier architecture patterns

4. **secrets/ vs sops/**
   - Action: Migrate infra secrets/ structure to test-clan sops/ + clan vars pattern
   - Complex: Requires understanding two-tier secrets architecture from test-clan
   - Timeline: Handled in Story 2.5+ (secrets migration)

## 7. Post-Migration Verification Commands

### 7.1 Preservation Verification (Zero Changes Expected)

```bash
# Switch to clan-01 branch
git checkout clan-01

# Verify GitHub Actions unchanged
git diff main..clan-01 -- .github/
# Expected output: empty (no diff)

# Verify TypeScript monorepo unchanged
git diff main..clan-01 -- packages/ package.json biome.json
# Expected output: empty (no diff)

# Verify documentation preserved
git diff main..clan-01 -- docs/notes/
# Expected output: empty (no diff)

# Verify scripts preserved
git diff main..clan-01 -- scripts/
# Expected output: empty (no diff)

# Verify project files preserved
git diff main..clan-01 -- CLAUDE.md README.md Makefile
# Expected output: empty (no diff) OR intentional README updates
```

### 7.2 Functional Verification (Components Still Work)

**GitHub Actions**:
```bash
# List workflows (should show all 7)
gh workflow list

# Trigger CI test run
gh workflow run ci.yaml --ref clan-01

# Monitor workflow
gh run watch

# Verify success
gh run view --log
```

**TypeScript Documentation**:
```bash
# Clean build test
git clean -fdx packages/docs/node_modules packages/docs/dist
nix develop -c just install
nix develop -c just docs-build

# Verify output
ls -lh packages/docs/dist/
# Expected: _astro/, _worker.js/, index.html, etc.

# Link validation
nix develop -c just docs-linkcheck
# Expected: All links valid, no broken references

# Local preview
nix develop -c just docs-preview
# Expected: Server starts on http://localhost:4321
# Manual check: Visit site, navigate pages
```

**Cloudflare Deployment**:
```bash
# Dry-run deployment
cd packages/docs
nix develop -c wrangler deploy --dry-run
# Expected: Validation passes, shows infra.cameronraysmith.net route

# Preview deployment (non-production)
cd ../..
nix develop -c just docs-deploy-preview clan-01
# Expected: Deploys to b-clan-01-infra-docs.sciexp.workers.dev

# Verify preview URL
curl -I https://b-clan-01-infra-docs.sciexp.workers.dev
# Expected: HTTP 200 OK, content-type: text/html
```

**Scripts**:
```bash
# Semantic release preview
npm run preview-version
# Expected: Shows next version number, no errors

# Sops validation
scripts/sops/validate-correspondences.sh
# Expected: All age keys correspond correctly (may fail if secrets structure changed - acceptable)

# System verification
scripts/verify-system.sh
# Expected: System configuration valid

# Secret leak detection
scripts/verify-no-secrets-in-store.sh
# Expected: No secrets leaked to nix store
```

### 7.3 Nix Configuration Verification (New Architecture)

```bash
# Flake check (comprehensive validation)
nix flake check
# Expected: All checks pass (if any fail, debug dendritic integration)

# List available systems
nix flake show --legacy
# Expected: Shows blackphos, stibnite, cinnabar, electrum, rosegold, argentum

# Build a configuration (non-destructive)
nix build .#darwinConfigurations.blackphos.system
# Expected: Successful build, result symlink created

# Compare configurations (before/after)
nix eval .#darwinConfigurations.blackphos.config.system.build.toplevel.outPath
# Expected: Different from main branch (new architecture)
```

### 7.4 Smoke Test Summary

Run all verification commands in sequence and tally results:

```bash
# Automated smoke test script (create in Story 2.3)
#!/usr/bin/env bash
set -euo pipefail

echo "=== Story 2.3 Post-Migration Verification ==="
echo

echo "1. Checking preserved components..."
git diff main..clan-01 -- .github/ packages/ docs/notes/ scripts/ CLAUDE.md | wc -l
# Expected: 0 (or small number if intentional updates)

echo "2. Building documentation..."
nix develop -c just install && nix develop -c just docs-build
# Expected: Success

echo "3. Validating nix configuration..."
nix flake check
# Expected: Success

echo "4. Building sample configuration..."
nix build .#darwinConfigurations.blackphos.system
# Expected: Success

echo "5. Testing scripts..."
npm run preview-version
scripts/verify-system.sh
# Expected: Success

echo
echo "=== Verification Complete ==="
echo "If all steps succeeded, Story 2.3 migration is VALIDATED."
```

## 8. Story 2.3 Execution Guidance

### 8.1 Pre-Migration Checklist

Before executing Story 2.3 wholesale copy:

- [ ] Create `clan-01` branch from `main`
- [ ] Review this preservation checklist
- [ ] Confirm test-clan commit hash to copy from (latest validated)
- [ ] Backup current configuration (branch + tag)
- [ ] Verify clean working directory (`git status`)

### 8.2 Copy Strategy

**Approach**: Surgical replacement, not `rm -rf`

```bash
# Create branch
git checkout -b clan-01 main

# For each REPLACE pattern:
# 1. Remove old structure
rm -rf configurations/  # nixos-unified legacy
rm flake.nix config.nix

# 2. Copy from test-clan
cp ~/projects/nix-workspace/test-clan/flake.nix .
cp -r ~/projects/nix-workspace/test-clan/lib .
cp -r ~/projects/nix-workspace/test-clan/modules .
cp -r ~/projects/nix-workspace/test-clan/machines .
# ... (continue for all REPLACE patterns)

# 3. Stage changes
git add -A

# 4. Verify preservation patterns NOT affected
git diff --cached -- .github/ packages/ docs/notes/ scripts/
# Expected: No output (preserved components unchanged)

# 5. Commit
git commit -m "feat(architecture): migrate to clan+dendritic from test-clan

- Replace nixos-unified with clan-core architecture
- Replace manual imports with dendritic flake-parts auto-discovery
- Adopt two-tier secrets architecture (clan vars + sops-nix)
- Preserve GitHub Actions, TypeScript monorepo, Cloudflare deployment
- Preserve documentation, scripts, project configuration

BREAKING CHANGE: Configuration structure completely replaced. Existing nixos-unified configurations will not work. Use clan CLI for machine management.

Preserves: .github/, packages/, docs/notes/, scripts/, CLAUDE.md
Replaces: flake.nix, modules/, lib/, configurations/ (deleted)
Source: test-clan@<commit-hash>"
```

### 8.3 Post-Copy Merge Tasks

After wholesale copy, manually merge:

1. **justfile**: Compare versions, integrate infra-specific targets
2. **.gitignore**: Union of both versions
3. **.sops.yaml**: Merge sops configurations (may defer to Story 2.5)
4. **README.md**: Update to reflect new architecture (defer to Story 2.4)

### 8.4 Validation Gate

Before proceeding to Story 2.4, MUST pass:

- [ ] All preservation verification commands pass (Section 7.1)
- [ ] Nix flake check succeeds (Section 7.3)
- [ ] Documentation builds successfully (Section 7.2)
- [ ] GitHub Actions workflows list correctly (Section 7.2)
- [ ] No unintended diffs in preserved components

If any verification fails, debug before proceeding. This is the foundation for all subsequent stories.

## 9. Success Criteria

### Story 2.1 Acceptance Criteria Validation

- [x] **AC1**: GitHub Actions workflows documented with file paths and PRESERVE directives
  - 7 workflow files identified and documented in Section 1
  - All composite actions catalogued
  - Exclusion pattern defined: `.github/**/*`

- [x] **AC2**: TypeScript monorepo structure documented with build dependencies
  - Root package.json and packages/docs/ structure documented in Section 2
  - Build integration with Nix (justfile targets) documented
  - Cloudflare deployment workflow documented

- [x] **AC3**: Cloudflare deployment configuration documented
  - wrangler.jsonc configuration detailed in Section 3
  - Secrets management via sops documented
  - Custom domain and preview URL patterns specified

- [x] **AC4**: Additional infra-unique components identified
  - docs/notes/ project documentation identified (Section 4.1)
  - scripts/ directory analyzed and categorized (Section 4.2)
  - Repository root files evaluated (Section 4.3)
  - Git metadata and editor configs documented (Section 4.4-4.5)

- [x] **AC5**: Comprehensive preservation checklist created with zero-regression requirements
  - All sections 1-4 document components to preserve
  - Section 5 defines zero-regression requirements
  - Section 7 provides verification commands

- [x] **AC6**: File exclusion list mapped with verification commands for Story 2.3
  - Section 6.1: Preserve patterns (do NOT copy)
  - Section 6.2: Replace patterns (COPY from test-clan)
  - Section 6.3: Ignore patterns (regenerable)
  - Section 6.4: Manual merge required
  - Section 7: Comprehensive verification commands

- [x] **AC7**: Checklist reviewed and approved for Story 2.3 consumption
  - Section 8 provides Story 2.3 execution guidance
  - Pre-migration checklist, copy strategy, and validation gate defined
  - This document is ready for user approval

### Story 2.1 Task Completion

- [x] Task 1: Document GitHub Actions workflows → Section 1
- [x] Task 2: Document TypeScript monorepo structure → Section 2
- [x] Task 3: Document Cloudflare deployment config → Section 3
- [x] Task 4: Identify additional infra-unique components → Section 4
- [x] Task 5: Create comprehensive preservation checklist → Sections 1-5
- [x] Task 6: Create file exclusion list for Story 2.3 → Section 6
- [x] Task 7: Finalize and review preservation checklist → Section 8-9 (this section)

## 10. Next Steps

### Story 2.2: Prepare clan-01 Branch

After user approval of this checklist:

1. Create `clan-01` branch from `main`
2. Tag current main branch for backup: `git tag pre-clan-migration`
3. Confirm clean working directory
4. Proceed to Story 2.3

### Story 2.3: Wholesale Configuration Copy

With this checklist:

1. Copy all REPLACE patterns from test-clan to infra (Section 6.2)
2. Verify all PRESERVE patterns unchanged (Section 6.1)
3. Execute post-migration verification (Section 7)
4. If all verifications pass, commit with detailed message (Section 8.2)

### Story 2.4+: Incremental Refinement

After Story 2.3 validates:

- Story 2.4: Update documentation to reflect new architecture
- Story 2.5: Migrate secrets to two-tier architecture
- Story 2.6+: Machine-specific configuration refinements

## Document Status

**Status**: Draft - Awaiting User Approval
**Story**: 2.1 (Epic 2, Story 1/13)
**Blocks**: Stories 2.2, 2.3
**Generated**: 2025-11-22
**Author**: Claude Code (dev-story workflow)
