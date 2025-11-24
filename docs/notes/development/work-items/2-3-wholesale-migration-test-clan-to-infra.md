# Story 2.3: Execute wholesale migration from test-clan to infra

Status: backlog

## Story

As a system administrator,
I want to execute the wholesale migration from test-clan to infra using the "rip the band-aid" strategy,
So that infra repository uses the validated dendritic+clan architecture while preserving all infra-specific components.

## Context

**Migration Philosophy:**
Epic 1 was discovery/validation in test-clan.
Epic 2 is application of proven patterns to infra.
Use modular "replace" approach, not individual file reading.
Trust git branch/diff/history as safety net.
Fast and pragmatic > slow and careful.

**Story 2.1 Foundation:**
Story 2.1 created comprehensive preservation checklist (887 lines, 9.8/10 quality) with PRESERVE/REPLACE/CREATE/IGNORE/MERGE/VERIFY patterns.
Story 2.3 MUST comply with this checklist.

**Story 2.2 Preparation:**
Story 2.2 created clan-01 branch and verified clean state.
Story 2.3 executes migration on this branch.

**Scope:**
This is the LINCHPIN story of Epic 2 - the "rip the band-aid" wholesale migration where we copy ALL validated nix configurations from test-clan → infra while preserving infra-specific components (GitHub Actions, TypeScript monorepo, Cloudflare deployment).

## Acceptance Criteria

### AC1: All PRESERVE components unchanged (Zero-Regression)

**Verification:**
```bash
git diff main..clan-01 -- .github/ packages/ docs/notes/ scripts/ CLAUDE.md README.md Makefile biome.json
```

**Expected:** No output (zero changes to preserved components)

**Effort:** 5 min

### AC2: All REPLACE components copied from test-clan

**Verification:**
```bash
# Check new directories exist
ls -ld machines/ sops/ vars/ pkgs/ terraform/ inventory.json

# Check legacy directories removed
ls configurations/ overlays/ tests/ config.nix 2>&1 | grep -q "No such file"

# Count nix files in migrated structure
find lib/ modules/ -name "*.nix" | wc -l
```

**Expected:**
- machines/, sops/, vars/, pkgs/, terraform/, inventory.json all exist
- configurations/, overlays/, tests/, config.nix do NOT exist
- ~148 .nix files in lib/ and modules/

**Effort:** 10 min

### AC3: All MERGE files manually merged

**Verification:**
```bash
# Verify justfile has both test-clan and infra targets
just --summary | grep -E "(docs-build|check|show)"

# Verify .gitignore has terraform patterns
grep -q "terraform" .gitignore

# Verify .sops.yaml has proper structure
grep -q "creation_rules" .sops.yaml
```

**Expected:** Content from both repos present in merged files

**Effort:** Verified from Tasks 5-7

### AC4: GitHub Actions workflows functional

**Verification:**
```bash
# List workflows
gh workflow list

# Verify CI workflow can be triggered
gh workflow run ci.yaml --ref clan-01
```

**Expected:** Workflows list correctly, can trigger on clan-01 branch

**Effort:** 15 min

### AC5: TypeScript documentation builds successfully

**Verification:**
```bash
cd packages/docs
nix develop -c just install
nix develop -c just docs-build
ls -la dist/
```

**Expected:** dist/ directory with built site, no build errors

**Effort:** 20 min

### AC6: Nix flake checks pass

**Verification:**
```bash
# Validate flake syntax
nix flake check

# Show available configurations
nix flake show

# Dry-run build a configuration
nix build .#darwinConfigurations.blackphos.system --dry-run
```

**Expected:** Flake syntax valid, configurations evaluate without errors

**Effort:** 30 min

### AC7: Secrets structure coexistence verified

**Verification:**
```bash
# Verify both secrets structures exist
ls -ld secrets/ sops/

# Test sops decryption
sops -d secrets/shared.yaml
```

**Expected:** Both directories exist, decryption works

**Effort:** 10 min

## Tasks / Subtasks

### Task 1: Pre-Migration Preparation (15 min)

- [ ] Verify clan-01 branch clean (AC: #1)
  - [ ] Run `git status` to confirm clean working directory
  - [ ] Verify on clan-01 branch: `git branch --show-current`
- [ ] Tag pre-migration state (AC: #2)
  - [ ] Create tag: `git tag pre-story-2.3-migration`
  - [ ] Document current HEAD commit hash
- [ ] Read Story 2.1 checklist (AC: #1, #2, #3)
  - [ ] Review PRESERVE patterns (Section 6.1)
  - [ ] Review REPLACE patterns (Section 6.2)
  - [ ] Review MERGE patterns (Section 6.4)
- [ ] Document test-clan commit hash (AC: #2)
  - [ ] Record test-clan HEAD: `cd ~/projects/nix-workspace/test-clan && git rev-parse HEAD`

### Task 2: rsync Dry-Run Validation (20 min)

- [ ] Construct rsync command with exclusions (AC: #1, #2)
  - [ ] Base exclusion list from Story 2.1 Section 6.1 (33+ patterns)
  - [ ] Add `--exclude='README.md'` (Blocker #1 handling)
  - [ ] Add `--exclude='CLAUDE.md'` (Blocker #2 handling)
  - [ ] Include all PRESERVE patterns from checklist
- [ ] Execute dry-run (AC: #1, #2)
  - [ ] Run: `rsync -avun --delete [exclusions] ~/projects/nix-workspace/test-clan/ .`
  - [ ] Review output carefully for unintended file operations
- [ ] Verify preservation patterns NOT affected (AC: #1)
  - [ ] Check .github/ NOT in rsync output
  - [ ] Check packages/ NOT in rsync output
  - [ ] Check docs/notes/ NOT in rsync output
  - [ ] Check scripts/ NOT in rsync output
- [ ] Verify replace/delete patterns correct (AC: #2)
  - [ ] Check flake.nix WILL be copied
  - [ ] Check lib/, modules/ WILL be copied
  - [ ] Check machines/, sops/, vars/ WILL be created
  - [ ] Check configurations/, overlays/, tests/ WILL be deleted

### Task 3: Execute rsync Copy (10 min)

- [ ] Remove -n flag from rsync command (AC: #2)
- [ ] Execute actual copy (AC: #2)
  - [ ] Run: `rsync -avu --delete [exclusions] ~/projects/nix-workspace/test-clan/ .`
  - [ ] Monitor output for errors
- [ ] Verify exit code 0 (AC: #2)
  - [ ] Check rsync completed successfully

### Task 4: Verify File Structure (15 min)

- [ ] Check new directories (AC: #2)
  - [ ] `ls -ld machines/` - exists
  - [ ] `ls -ld sops/` - exists
  - [ ] `ls -ld vars/` - exists
  - [ ] `ls -ld pkgs/` - exists
  - [ ] `ls -ld terraform/` - exists
  - [ ] `ls -l inventory.json` - exists
- [ ] Check legacy deleted (AC: #2)
  - [ ] `ls configurations/ 2>&1` - "No such file or directory"
  - [ ] `ls overlays/ 2>&1` - "No such file or directory"
  - [ ] `ls tests/ 2>&1` - "No such file or directory"
  - [ ] `ls config.nix 2>&1` - "No such file or directory"
- [ ] Count modules (AC: #2)
  - [ ] Run: `find lib/ modules/ -name "*.nix" | wc -l`
  - [ ] Expect: ~148 files

### Task 5: Manual Merge - justfile (30 min)

- [ ] Back up current justfile (AC: #3)
  - [ ] `cp justfile justfile.backup-pre-merge`
- [ ] Base on test-clan justfile (149 lines) (AC: #3)
  - [ ] Copy test-clan justfile as starting point
- [ ] Add infra target groups (AC: #3, #4)
  - [ ] docs targets (13): install, docs-build, docs-preview, docs-deploy-preview, docs-deploy-production, docs-linkcheck, etc.
  - [ ] containers targets (8): container-related operations
  - [ ] secrets targets (13): sops key management
  - [ ] sops targets (9): additional sops operations
  - [ ] CI/CD targets (20+): test-release, preview-version, etc.
- [ ] Resolve conflicts (AC: #3)
  - [ ] check target - merge both versions
  - [ ] show target - merge both versions
  - [ ] update target - merge both versions
- [ ] Test merged justfile (AC: #3, #4)
  - [ ] Run: `just --summary`
  - [ ] Verify all targets listed
- [ ] Final size check (AC: #3)
  - [ ] Expect: ~600-800 lines (149 base + 450-650 infra-specific)

### Task 6: Manual Merge - .gitignore (10 min)

- [ ] Back up current .gitignore (AC: #3)
  - [ ] `cp .gitignore .gitignore.backup-pre-merge`
- [ ] Base on infra .gitignore (37 lines) (AC: #3)
  - [ ] Keep infra TypeScript patterns
  - [ ] Keep infra build artifact patterns
- [ ] Add terraform patterns (6 lines) (AC: #3)
  - [ ] Add patterns from test-clan .gitignore:
    - `*.tfstate`
    - `*.tfstate.backup`
    - `.terraform/`
    - `terraform.tfvars`
    - `.terraformrc`
    - `*.auto.tfvars`
- [ ] Final size check (AC: #3)
  - [ ] Expect: ~45 lines (37 base + 6 terraform + 2 blanks/comments)

### Task 7: Manual Merge - .sops.yaml (20 min)

- [ ] Back up current .sops.yaml (AC: #3)
  - [ ] `cp .sops.yaml .sops.yaml.backup-pre-merge`
- [ ] Base on infra .sops.yaml (98 lines) (AC: #3)
  - [ ] Preserve infra age keys
  - [ ] Preserve infra creation rules
- [ ] Optionally add home-manager pattern (AC: #3)
  - [ ] Review test-clan .sops.yaml for home-manager rules
  - [ ] Add if beneficial (optional)
- [ ] Test sops configuration (AC: #3, #7)
  - [ ] Run: `sops -d secrets/shared.yaml`
  - [ ] Verify decryption works
- [ ] Final size check (AC: #3)
  - [ ] Expect: ~110 lines (98 base + optional additions)

### Task 8: Stage and Commit Changes (15 min)

- [ ] Stage all changes (AC: #2)
  - [ ] Run: `git add -A`
- [ ] Verify preservation patterns NOT staged (AC: #1)
  - [ ] Run: `git diff --cached -- .github/ packages/ docs/notes/ scripts/`
  - [ ] Expect: No output (no changes)
- [ ] Commit with detailed message (AC: #2)
  - [ ] Use commit message template (see Dev Notes below)
  - [ ] Include test-clan source commit hash
  - [ ] Document preserved components
  - [ ] Document replaced components
  - [ ] Note known issues (flake.nix input differences - Blocker #4)

### Task 9: Post-Migration Verification (45 min)

- [ ] Run all AC verification commands (AC: #1-7)
  - [ ] AC1: Verify preserved components unchanged
  - [ ] AC2: Verify replaced components present
  - [ ] AC3: Verify merged files correct
  - [ ] AC4: Verify GitHub Actions functional
  - [ ] AC5: Verify TypeScript build successful
  - [ ] AC6: Verify nix flake checks pass
  - [ ] AC7: Verify secrets coexistence
- [ ] Document failures (AC: #1-7)
  - [ ] Record any verification failures
  - [ ] Categorize: CRITICAL (blocks progress) vs ACCEPTABLE (document and proceed)
- [ ] If critical failures, revert (AC: #1-7)
  - [ ] Run: `git reset --hard pre-story-2.3-migration`
  - [ ] Analyze failures
  - [ ] Adjust approach
- [ ] If acceptable failures, document (AC: #1-7)
  - [ ] Add to story completion notes
  - [ ] Create follow-up tasks if needed

### Task 10: Update CLAUDE.md (10 min)

- [ ] Update "Current Architecture" section (AC: #2, #6)
  - [ ] Remove nixos-unified references
  - [ ] Add clan+dendritic architecture description
- [ ] Update "Migration Status" section (AC: #2)
  - [ ] Mark Story 2.3 complete
  - [ ] Update Epic 2 Phase 1 status
- [ ] Document secrets/sops coexistence (AC: #7)
  - [ ] Explain two-tier architecture
  - [ ] Note migration to Story 2.4
- [ ] Commit CLAUDE.md update (AC: #2)
  - [ ] Run: `git add CLAUDE.md`
  - [ ] Run: `git commit -m "docs(claude): update architecture to dendritic+clan"`

## Dev Notes

### Commit Message Template

```
feat(architecture): migrate to clan+dendritic from test-clan

Execute wholesale "rip the band-aid" migration from nixos-unified to
clan-core + dendritic flake-parts architecture.

PRESERVE (infra-specific, zero changes):
- .github/ (CI/CD workflows, composite actions)
- packages/ (TypeScript documentation monorepo)
- docs/notes/ (project documentation)
- scripts/ (CI, sops, validation scripts)
- CLAUDE.md, README.md, Makefile, biome.json

REPLACE (test-clan → infra):
- flake.nix (clan+dendritic entry point)
- lib/ (dendritic library modules)
- modules/ (dendritic auto-discovered modules)

CREATE (NEW from test-clan):
- machines/ (clan machine definitions)
- sops/ (clan two-tier secrets architecture)
- vars/ (clan vars)
- pkgs/ (package definitions)
- terraform/ (infrastructure as code)
- inventory.json (clan inventory)

DELETE (legacy nixos-unified):
- configurations/
- overlays/ (superseded by dendritic overlays pattern)
- tests/ (superseded by test harness migration in Story 2.13)
- config.nix

MERGE (manual integration):
- justfile (test-clan base + infra targets: docs, containers, secrets, CI/CD)
- .gitignore (infra base + terraform patterns)
- .sops.yaml (infra keys + optional home-manager patterns)

KNOWN ISSUES:
- flake.nix input differences (Blocker #4):
  Lost inputs: omnix, playwright-web-flake, lazyvim, jj, others
  May break: just docs-test-e2e
  Resolution: Story 2.4 will evaluate re-adding lost inputs

- secrets/sops coexistence (Blocker #3):
  Both secrets/ (infra legacy) and sops/ (clan two-tier) directories present
  Resolution: Story 2.4 will migrate secrets → sops/vars architecture

BREAKING CHANGE: Configuration structure completely replaced.
Existing nixos-unified configurations will not work.
Use clan CLI for machine management.

Source: test-clan@<COMMIT_HASH>
Story: 2.3 (Epic 2, Phase 1)
Checklist: docs/notes/development/work-items/story-2-1-preservation-checklist.md
```

### Critical Blockers

**Blocker #1: README.md Conflict (MEDIUM)**
- Action: Add `--exclude='README.md'` to rsync
- Rationale: Preserve infra README (4.8 KB production docs)
- Resolution: Defer README update to Story 2.4

**Blocker #2: CLAUDE.md Conflict (MEDIUM)**
- Action: Already excluded in Story 2.1 checklist
- Verification: Ensure exclusion works in rsync dry-run
- Resolution: Update CLAUDE.md in Task 10 after migration

**Blocker #3: secrets/sops Coexistence (CRITICAL)**
- Action: Allow parallel structures (no exclusion)
- Verification: AC7 verifies both exist
- Documentation: Update CLAUDE.md in Task 10
- Resolution: Defer migration to Story 2.4

**Blocker #4: flake.nix Input Differences (HIGH)**
- Issue: test-clan flake.nix lacks infra-specific inputs
  - Lost inputs: omnix, playwright-web-flake, lazyvim, jj, others
  - May break: `just docs-test-e2e` (playwright dependency)
- Action: Document in commit message
- Verification: Note in AC5 if docs-test-e2e fails
- Resolution: Story 2.4 will evaluate re-adding lost inputs

### rsync Exclusion Patterns (from Story 2.1)

**Comprehensive exclusion list for rsync:**

```bash
rsync -avu --delete \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='packages' \
  --exclude='package.json' \
  --exclude='package-lock.json' \
  --exclude='biome.json' \
  --exclude='docs/notes' \
  --exclude='scripts' \
  --exclude='CLAUDE.md' \
  --exclude='README.md' \
  --exclude='Makefile' \
  --exclude='.bmad' \
  --exclude='.vscode' \
  --exclude='.gitignore' \
  --exclude='.gitattributes' \
  --exclude='.gitleaksignore' \
  --exclude='secrets' \
  --exclude='.sops.yaml' \
  --exclude='result' \
  --exclude='result-*' \
  --exclude='dist' \
  --exclude='.astro' \
  --exclude='node_modules' \
  --exclude='.direnv' \
  --exclude='.devenv' \
  --exclude='coverage' \
  --exclude='test-results' \
  --exclude='playwright-report' \
  --exclude='.wrangler' \
  --exclude='.DS_Store' \
  --exclude='*.swp' \
  --exclude='*.swo' \
  --exclude='*~' \
  ~/projects/nix-workspace/test-clan/ .
```

### Estimated Effort

**Total: 3-4 hours**

Breakdown:
- Preparation: 15 min (Task 1)
- rsync operations: 30 min (Tasks 2-3)
- File structure verification: 15 min (Task 4)
- Manual merges: 60 min (Tasks 5-7)
- Git operations: 15 min (Task 8)
- Verification: 45 min (Task 9)
- Documentation: 10 min (Task 10)

### Prerequisites

- Story 2.1 complete (preservation checklist created) ✅
- Story 2.2 complete (clan-01 branch ready) ✅
- Epic 1 complete (patterns validated) ✅

### Project Structure Notes

**Alignment with dendritic+clan architecture:**

After Story 2.3 migration, infra repository structure will match test-clan:

```
infra/
├── flake.nix                  # Clan+dendritic entry point
├── inventory.json             # Clan inventory (machines, services, users)
├── lib/                       # Dendritic library modules
├── modules/                   # Dendritic auto-discovered modules
│   ├── home/                  # Home-manager modules (Pattern A)
│   ├── hosts/                 # Machine-specific modules
│   ├── nixpkgs/               # Nixpkgs configuration
│   └── ...
├── machines/                  # Clan machine definitions
├── sops/                      # Clan two-tier secrets (user-level)
├── vars/                      # Clan vars (system-level)
├── pkgs/                      # Custom packages (pkgs-by-name pattern)
├── terraform/                 # Infrastructure as code
├── .github/                   # PRESERVED: CI/CD workflows
├── packages/                  # PRESERVED: TypeScript monorepo
├── docs/notes/                # PRESERVED: Project documentation
├── scripts/                   # PRESERVED: Utility scripts
└── ...
```

**Dendritic auto-discovery:**
- `lib/` modules auto-discovered by import-tree
- `modules/` organized by category (home, hosts, nixpkgs, etc.)
- Pattern A home-manager modules with flake context access

**Clan integration:**
- `inventory.json` defines machines, services, users
- `machines/` contains machine-specific modules
- Two-tier secrets: `vars/` (system-level) + `sops/` (user-level)

### References

**Source Documentation:**
- [Story 2.1 Preservation Checklist](docs/notes/development/work-items/story-2-1-preservation-checklist.md)
  - Section 6.1: PRESERVE patterns
  - Section 6.2: REPLACE patterns
  - Section 6.3: IGNORE patterns
  - Section 6.4: MERGE patterns
  - Section 7: Verification commands
  - Section 8: Story 2.3 execution guidance

- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md)
  - Epic goal: Apply test-clan patterns to infra
  - 13 stories across 4 phases
  - "Rip the band-aid" migration philosophy

- [Sprint Status](docs/notes/development/sprint-status.yaml)
  - Story 2.1: done (preservation checklist)
  - Story 2.2: review (branch preparation)
  - Story 2.3: backlog (this story)

**External References:**
- test-clan Source: `~/projects/nix-workspace/test-clan/`
- Epic 1 Retrospective: `docs/notes/development/epic-1-retro-2025-11-20.md`
- Migration Patterns: `~/projects/nix-workspace/test-clan/docs/migration-patterns.md`
- Dendritic Patterns: `~/projects/nix-workspace/test-clan/docs/dendritic-patterns.md`

## Dev Agent Record

### Context Reference

<!-- Story context XML will be added here by story-context workflow -->

### Agent Model Used

<!-- Will be filled during story execution -->

### Debug Log References

<!-- Will be filled during story execution -->

### Completion Notes List

<!-- Will be filled during story execution -->

### File List

<!-- Will be filled during story execution -->
