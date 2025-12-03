# Story 9.0a: Update Stale Migration Guides for Dendritic Architecture

Status: drafted

## Story

As a documentation maintainer,
I want to update migration guides that reference old nixos-unified architecture,
so that developers have accurate documentation matching the current dendritic flake-parts + clan structure.

## Background

Epic 8 retrospective and Party Mode analysis session (2025-12-03) discovered that several documentation files still reference the pre-migration nixos-unified architecture patterns, including:

- README.md references nixos-unified as current architecture
- guides/handling-broken-packages.md references old `overlays/` directory structure
- guides/adding-custom-packages.md references old `overlays/packages/` pattern
- ADR-0003 is referenced but has been superseded by ADR-0017
- "multi-channel resilience" terminology is imprecise (should be "multi-channel fallback")

The dendritic flake-parts + clan migration completed in Epic 2 (2025-11-28), but these guides were not updated during the migration.

## Acceptance Criteria

1. **AC-1**: README.md reflects dendritic flake-parts + clan architecture
   - Remove/update nixos-unified references
   - Update architecture description
   - Ensure quick-start examples use current patterns
   - Verify any path references are accurate

2. **AC-2**: All file path references in guides match current architecture
   - `overlays/packages/` → `pkgs/by-name/`
   - `overlays/infra/hotfixes.nix` → `modules/nixpkgs/overlays/hotfixes.nix`
   - `overlays/overrides/*.nix` → `modules/nixpkgs/overlays/overrides.nix`
   - `overlays/infra/patches.nix` → `modules/nixpkgs/overlays/channels.nix` (patched attr, lines 41-46)
   - `overlays/inputs.nix` → `modules/nixpkgs/overlays/channels.nix`
   - `overlays/default.nix` → `modules/nixpkgs/` (dendritic structure)

3. **AC-3**: No references to superseded ADR-0003 (use ADR-0017)
   - Replace all `/development/architecture/adrs/0003-overlay-composition-patterns` links
   - Update to `/development/architecture/adrs/0017-dendritic-overlay-patterns`

4. **AC-4**: Terminology uses proper Nix concepts (overlays, overrides, channels, fallbacks)
   - Fix "multi-channel resilience" → "multi-channel fallback" where appropriate
   - Ensure consistent terminology throughout

5. **AC-5**: `just docs-build` succeeds
   - All documentation builds without errors
   - No broken frontmatter or Starlight configuration issues

6. **AC-6**: `just docs-linkcheck` passes
   - All internal links valid
   - No broken cross-references

7. **AC-7**: Other stale guides identified and updated (if found)
   - guides/getting-started.md structure reference
   - Any additional files discovered during audit

## Tasks / Subtasks

### Task 1: Audit Current State (AC: 1, 2, 3, 4)

- [ ] 1.1 Read README.md and identify nixos-unified references
  - [ ] 1.1.1 Line 22: "nixos-unified directory-based autowiring"
  - [ ] 1.1.2 Line 49: "nixos-unified scans filesystem structure"
  - [ ] 1.1.3 Line 51-52: "overlays/infra/hotfixes.nix" reference
  - [ ] 1.1.4 Line 69: "Understanding Autowiring" link (obsolete)
  - [ ] 1.1.5 Line 82: "nixos-unified" in credits
- [ ] 1.2 Read handling-broken-packages.md and identify stale paths
  - [ ] 1.2.1 Count and list all `overlays/infra/hotfixes.nix` references (17+ occurrences)
  - [ ] 1.2.2 Count and list all `overlays/overrides/` references
  - [ ] 1.2.3 Count and list all `overlays/infra/patches.nix` references
  - [ ] 1.2.4 Note `overlays/inputs.nix` reference (line 563)
- [ ] 1.3 Read adding-custom-packages.md and identify stale paths
  - [ ] 1.3.1 Count and list all `overlays/packages/` references (14+ occurrences)
  - [ ] 1.3.2 Count and list all `overlays/default.nix` references
  - [ ] 1.3.3 Identify ADR-0003 reference (line 248)
- [ ] 1.4 Search guides/ for other stale architecture references
  - [ ] 1.4.1 Check getting-started.md (line 186 `overlays/` reference)
  - [ ] 1.4.2 Run `rg 'overlays/' packages/docs/src/content/docs/guides/`
  - [ ] 1.4.3 Run `rg 'nixos-unified' packages/docs/src/content/docs/`
- [ ] 1.5 Document all instances requiring updates in dev notes

### Task 2: Update README.md (AC: 1, 5, 6)

- [ ] 2.1 Update architecture description to reflect dendritic flake-parts + clan
  - [ ] 2.1.1 Replace "nixos-unified directory-based autowiring" with dendritic flake-parts description
  - [ ] 2.1.2 Update features section to reflect current patterns
- [ ] 2.2 Remove/update nixos-unified references
  - [ ] 2.2.1 Update line 49 feature description
  - [ ] 2.2.2 Update "Understanding Autowiring" link to dendritic-architecture.md
  - [ ] 2.2.3 Update credits section (line 82)
- [ ] 2.3 Update path references
  - [ ] 2.3.1 Update `overlays/infra/hotfixes.nix` reference in line 51-52
- [ ] 2.4 Verify quick-start examples use current patterns
- [ ] 2.5 Test build after changes: `nix build .#docs`

### Task 3: Update handling-broken-packages.md (AC: 2, 4, 5, 6)

- [ ] 3.1 Update quick reference table (lines 12-18)
  - [ ] 3.1.1 `overlays/infra/hotfixes.nix` → `modules/nixpkgs/overlays/hotfixes.nix`
  - [ ] 3.1.2 `overlays/overrides/*.nix` → `modules/nixpkgs/overlays/overrides.nix`
  - [ ] 3.1.3 Update patches row: `overlays/infra/patches.nix` → `modules/nixpkgs/overlays/channels.nix` (patched attr)
- [ ] 3.2 Update Strategy A (lines 78-129)
  - [ ] 3.2.1 Replace all `overlays/infra/hotfixes.nix` paths
  - [ ] 3.2.2 Update example commands
- [ ] 3.3 Rewrite Strategy B for consolidated overrides file (lines 131-188)
  - [ ] 3.3.1 Change workflow: "Create overlays/overrides/packageName.nix" → "Add to modules/nixpkgs/overlays/overrides.nix"
  - [ ] 3.3.2 Update code examples to show inline override syntax in single file
  - [ ] 3.3.3 Update git add/commit commands (single file, not per-package files)
  - [ ] 3.3.4 Update cleanup instructions (no `rm` needed, just remove from file)
- [ ] 3.4 Rewrite Strategy C for channels.nix integration (lines 190-259)
  - [ ] 3.4.1 Replace `overlays/infra/patches.nix` → `modules/nixpkgs/overlays/channels.nix`
  - [ ] 3.4.2 Update instructions: patches are now inline in `patched` attr (lines 41-46)
  - [ ] 3.4.3 Update code examples to show channels.nix patches list syntax
  - [ ] 3.4.4 Update git add/commit commands
- [ ] 3.5 Update Phase 3 verification section (lines 326-398)
  - [ ] 3.5.1 Update grep commands with correct paths
  - [ ] 3.5.2 Update ls commands with correct paths
- [ ] 3.6 Rewrite Phase 4 cleanup section for consolidated files (lines 400-427)
  - [ ] 3.6.1 Change override cleanup: `rm overlays/overrides/packageName.nix` → "remove entry from modules/nixpkgs/overlays/overrides.nix"
  - [ ] 3.6.2 Change patch cleanup: "remove from patches.nix" → "remove from channels.nix patches list"
  - [ ] 3.6.3 Update git add/commit commands
- [ ] 3.7 Update templates section (lines 488-549)
  - [ ] 3.7.1 Update hotfix template paths
  - [ ] 3.7.2 Update override template paths
  - [ ] 3.7.3 Rewrite patch template for channels.nix inline syntax
- [ ] 3.8 Update common errors section (lines 551-587)
  - [ ] 3.8.1 Replace `overlays/inputs.nix` → `modules/nixpkgs/overlays/channels.nix` (line 563)
- [ ] 3.9 Test build after changes: `nix build .#docs`

### Task 4: Update adding-custom-packages.md (AC: 2, 3, 5, 6)

- [ ] 4.1 Update quick start section (lines 12-17)
  - [ ] 4.1.1 Replace `overlays/packages/` → `pkgs/by-name/`
  - [ ] 4.1.2 Update example: `overlays/packages/hello-world.nix` → `pkgs/by-name/hello-world/package.nix`
- [ ] 4.2 Update "Understanding how this works" section (lines 18-40)
  - [ ] 4.2.1 Replace `overlays/default.nix` references
  - [ ] 4.2.2 Replace `overlays/packages/` references
  - [ ] 4.2.3 Update explanation to reflect dendritic pattern
- [ ] 4.3 Update "Single-file packages" section (lines 41-117)
  - [ ] 4.3.1 Replace `overlays/packages/` paths
- [ ] 4.4 Update "Multi-file packages" section (lines 118-152)
  - [ ] 4.4.1 Replace `overlays/packages/` paths
  - [ ] 4.4.2 Update example structure: `pkgs/by-name/atuin-format/`
- [ ] 4.5 Update "How packages are discovered" section (lines 204-225)
  - [ ] 4.5.1 Replace `overlays/default.nix` reference
  - [ ] 4.5.2 Update code example to reflect dendritic pattern
  - [ ] 4.5.3 Update layer description (line 224)
- [ ] 4.6 Update "Next steps" section (lines 240-249)
  - [ ] 4.6.1 Replace `overlays/overrides/` path
  - [ ] 4.6.2 Replace `overlays/infra/hotfixes.nix` path
  - [ ] 4.6.3 Update ADR reference: 0003 → 0017
- [ ] 4.7 Verify `lib.packagesFromDirectoryRecursive` usage is still accurate
- [ ] 4.8 Test build after changes: `nix build .#docs`

### Task 5: Update getting-started.md Structure Reference (AC: 2, 7)

- [ ] 5.1 Update line 186 directory structure
  - [ ] 5.1.1 Replace `overlays/` with current structure

### Task 6: Repo-Wide Terminology and ADR Updates (AC: 3, 4)

**Scope:** REPO-WIDE (not guides-only) per ambiguity resolution

- [ ] 6.1 Search ENTIRE repository for "multi-channel resilience"
  - [ ] 6.1.1 Run `rg 'multi-channel resilience' packages/docs/`
  - [ ] 6.1.2 Fix in guides/ (commit 5)
  - [ ] 6.1.3 Fix in development/ docs (commit 6)
  - [ ] 6.1.4 Fix in ADRs if applicable (commit 7)
  - [ ] 6.1.5 Replace with "multi-channel fallback" (or similar Nix-appropriate term)
- [ ] 6.2 Search entire repository for ADR-0003 references
  - [ ] 6.2.1 Run `rg 'ADR-0003|0003-overlay' packages/docs/`
  - [ ] 6.2.2 Update all to ADR-0017
- [ ] 6.3 Ensure Nix terminology is correct throughout
  - [ ] 6.3.1 Overlays, overrides, channels, fallbacks used correctly

**Known occurrences from audit:**
- `concepts/nix-config-architecture.md` line 48
- `development/context/glossary.md` (3 occurrences including definition)
- `development/context/index.md` line 90
- `development/requirements/index.md` line 58
- `development/requirements/system-vision.md` line 271
- `development/requirements/usage-model.md` line 282 (UC-005)
- `development/context/goals-and-objectives.md` line 164
- `development/context/project-scope.md` lines 45, 93

### Task 7: Validation (AC: 5, 6)

- [ ] 7.1 Run `just docs-build` and verify success
- [ ] 7.2 Run `just docs-linkcheck` and verify no broken links
- [ ] 7.3 Verify examples with `nix eval` where practical
  - [ ] 7.3.1 Test pkgs/by-name path references
  - [ ] 7.3.2 Test modules/nixpkgs/overlays path references
- [ ] 7.4 Visual spot-check of rendered documentation
  - [ ] 7.4.1 README.md renders correctly
  - [ ] 7.4.2 handling-broken-packages.md renders correctly
  - [ ] 7.4.3 adding-custom-packages.md renders correctly

## Dev Notes

### Path Mapping Reference

| Old Path | Current Path | Verified |
|----------|--------------|----------|
| `overlays/packages/` | `pkgs/by-name/` | Yes (4 packages: atuin-format, ccstatusline, markdown-tree-parser, starship-jj) |
| `overlays/infra/hotfixes.nix` | `modules/nixpkgs/overlays/hotfixes.nix` | Yes |
| `overlays/overrides/*.nix` | `modules/nixpkgs/overlays/overrides.nix` | Yes |
| `overlays/infra/patches.nix` | Integrated into `modules/nixpkgs/overlays/channels.nix` (lines 41-46, `patched` attr with inline patches list) | Yes - no standalone file |
| `overlays/default.nix` | `modules/nixpkgs/` (dendritic structure) | Yes |
| `overlays/inputs.nix` | `modules/nixpkgs/overlays/channels.nix` (line 5: "Adapted from _overlays/inputs.nix") | Yes - replaced by channels.nix |

### Architecture Terminology Updates

| Old Term | Current Term | Scope |
|----------|--------------|-------|
| nixos-unified | dendritic flake-parts + clan | Architecture description |
| directory-based autowiring | import-tree auto-discovery | Feature description |
| multi-channel resilience | multi-channel fallback | Nix terminology |
| Understanding Autowiring | Dendritic Architecture | Concept link |

### Files Requiring Updates (Audit Results)

**Primary scope - Guide updates (commits 1-4):**

1. **README.md** (92 lines) - 5 nixos-unified references
2. **guides/handling-broken-packages.md** (643 lines) - 17+ stale path references
3. **guides/adding-custom-packages.md** (249 lines) - 14+ stale path references, ADR-0003 reference
4. **guides/getting-started.md** - 1 structure reference (line 186)

**Expanded scope - Repo-wide terminology (commits 5-7):**

5. **concepts/nix-config-architecture.md** - "multi-channel resilience" (line 48)
6. **development/context/glossary.md** - "multi-channel resilience" definition (3 occurrences)
7. **development/context/index.md** - "multi-channel resilience" (line 90)
8. **development/requirements/index.md** - "multi-channel resilience" (line 58)
9. **development/requirements/system-vision.md** - "multi-channel resilience" (line 271)
10. **development/requirements/usage-model.md** - UC-005 reference (line 282)
11. **development/context/goals-and-objectives.md** - "multi-channel resilience" (line 164)
12. **development/context/project-scope.md** - "multi-channel resilience" (lines 45, 93)

### Constraints

1. **Preserve functionality** - Update paths, not behavior descriptions (unless incorrect)
2. **Commit granularity** - Per-file for primary guides, per-directory for terminology fixes (8 commits total)
3. **Starlight structure** - Maintain existing frontmatter and sidebar configuration
4. **No placeholders** - All paths must be verified accurate before committing
5. **README.md priority** - First thing users see, highest impact

### Expected Commits

Per ambiguity resolution, this story should produce 8 atomic commits:

1. `docs: update README.md for dendritic architecture`
2. `docs(guides): update handling-broken-packages.md for dendritic architecture`
3. `docs(guides): update adding-custom-packages.md for dendritic architecture`
4. `docs(guides): update getting-started.md structure reference`
5. `docs(guides): fix multi-channel terminology in guides/`
6. `docs(development): fix multi-channel terminology in development docs`
7. `docs(adrs): fix multi-channel terminology in ADRs` (if applicable)
8. `chore(story-9.0a): complete implementation, mark for review`

### ADR References

- **ADR-0003** (SUPERSEDED): `/development/architecture/adrs/0003-overlay-composition-patterns`
- **ADR-0017** (CURRENT): `/development/architecture/adrs/0017-dendritic-overlay-patterns`

[Source: packages/docs/src/content/docs/development/architecture/adrs/0017-dendritic-overlay-patterns.md]

### Testing Commands

```bash
# Verify current paths exist
ls modules/nixpkgs/overlays/
# Expected: channels.nix, fish-stable-darwin.nix, hotfixes.nix, nvim-treesitter-main.nix, overrides.nix

ls pkgs/by-name/
# Expected: atuin-format, ccstatusline, markdown-tree-parser, starship-jj

# Documentation validation
just docs-build
just docs-linkcheck

# Path verification
nix eval .#overlays --apply builtins.attrNames
```

### References

- Epic 9 definition: `docs/notes/development/epics/epic-9-branch-consolidation-and-release.md`
- Epic 8 retrospective: `docs/notes/development/retrospectives/epic-8-documentation-alignment.md`
- ADR-0017: `packages/docs/src/content/docs/development/architecture/adrs/0017-dendritic-overlay-patterns.md`
- Dendritic architecture concepts: `packages/docs/src/content/docs/concepts/dendritic-architecture.md`
- Clan integration concepts: `packages/docs/src/content/docs/concepts/clan-integration.md`

### Learnings from Previous Story

**From Story 8.12 (Status: review)**

Story 8.12 created ADR-0017 (dendritic overlay patterns) which supersedes ADR-0003.
This story should update references to point to ADR-0017.

[Source: docs/notes/development/work-items/8-12-create-foundational-architecture-decision-records.md#Completion-Notes-List]

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-03 | Story drafted via create-story workflow | SM workflow |
| 2025-12-03 | Ambiguity resolutions applied: patches.nix/inputs.nix paths confirmed, terminology scope expanded to repo-wide, commit granularity specified (8 commits) | Party Mode |

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

### Completion Notes List

### File List
