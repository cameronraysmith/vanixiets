# Epic 9: Branch Consolidation and Release (Post-MVP Phase 8)

**Status:** Backlog
**Dependencies:** Epic 8 complete
**Strategy:** Safe merge with bookmark tags preserving full history

---

## Epic Goal

Merge the clan-01 branch to main with proper semantic versioning, preserving full git history and creating bookmark tags at key branch boundaries for future reference.

**Key Outcomes:**
- Bookmark tags at docs, clan, and clan-01 branch merge points
- All CI/CD workflows passing on clan-01
- Clean merge to main with no force-push or history rewriting
- Semantic version release tag with changelog
- Full history preserved for rollback capability

**Business Objective:** Production release of dendritic + clan architecture migration.

---

## FR Coverage Map

| Story | Functional Requirements |
|-------|-------------------------|
| Story 9.0a | Documentation alignment (post-migration) |
| Story 9.0b | Documentation alignment (content triage) |
| Story 9.1 | FR-9.1 (Bookmark tags) |
| Story 9.2 | FR-9.2 (CI/CD validation) |
| Story 9.3 | FR-9.3 (Merge and release) |

---

## Story 9.0a: Update stale migration guides for dendritic architecture

As a documentation maintainer,
I want to update migration guides that reference old nixos-unified architecture,
So that developers have accurate documentation matching the current dendritic flake-parts structure.

**Acceptance Criteria:**

**Given** guides written during nixos-unified architecture
**When** I audit and rewrite stale migration guides
**Then** the following files should be updated:
- `README.md` - update to reflect dendritic flake-parts + clan architecture, remove nixos-unified references
- `guides/handling-broken-packages.md` - all paths reference old `overlays/` structure
- `guides/adding-custom-packages.md` - references old `overlays/packages/` pattern

**And** path mappings should be corrected:

| Old Path | Current Path |
|----------|--------------|
| `overlays/packages/` | `pkgs/by-name/` |
| `overlays/infra/hotfixes.nix` | `modules/nixpkgs/overlays/hotfixes.nix` |
| `overlays/overrides/*.nix` | `modules/nixpkgs/overlays/overrides.nix` |

**And** ADR references should be updated:
- Replace references to ADR-0003 (superseded) with ADR-0017
- Fix "multi-channel resilience" terminology → "multi-channel fallback" (or similar Nix-appropriate term)

**And** documentation validation should pass:
- `just docs-build` succeeds
- `just docs-linkcheck` passes (no broken links)

**And** audit should check:
- Other guides for stale architecture references
- Examples use current patterns (pkgs/by-name/, modules/nixpkgs/overlays/)
- Terminology uses proper Nix concepts (overlays, overrides, channels, fallbacks)

**Prerequisites:** Epic 8 complete (dendritic migration finished)

**Technical Notes:**
- README.md is top-level repository documentation (first thing users see)
- Focus on guides/, not references/ (reference docs handled separately)
- Validate examples with `nix eval` where practical
- Ensure file path examples are discoverable via `fd` or `rg`
- Reference: ADR-0017 (overlays architecture)

**NFR Coverage:** Documentation accuracy

---

## Story 9.0b: Clean up migration artifacts and migrate essential content

As a repository maintainer,
I want to triage content in docs/notes/development/ and migrate essential content,
So that ephemeral migration artifacts are cleaned up while preserving valuable reference material.

**Important clarification:** The docs/ directory is NOT being deleted. This story cleans up migration artifacts and makes selective migrations.

**Acceptance Criteria:**

**Given** content in `docs/notes/development/` from architecture migration
**When** I triage content for retention, migration, or deletion
**Then** I should categorize content:

**Content triage categories:**
- NVIDIA docs (`nvidia-module-analysis.md`, 671 lines): EVALUATE placement (development reference, may not belong in public Starlight)
- Retrospectives (epic-7, epic-8 retros): EVALUATE preservation value
- Epic definitions: DELETE (superseded by PRD and Starlight dev docs)
- Research docs: EVALUATE case-by-case
- Sprint artifacts (`sprint-status.yaml`, `work-items/*.md`): DELETE (ephemeral by design)

**And** content triage decisions should be documented:
- Create content triage matrix with decisions
- Document rationale for EVALUATE items
- Identify which content migrates to Starlight vs stays in docs/notes/

**And** essential content should be:
- Migrated to appropriate Starlight sections (if applicable)
- OR explicitly retained in docs/notes/ with rationale
- Validated that Starlight build passes after migrations

**And** deletable content should be:
- Explicitly approved before removal
- Listed in triage matrix

**Prerequisites:** Story 9.0a complete (ensures guides are updated before any cleanup)

**Technical Notes:**
- docs/notes/ is NOT being deleted - this is selective cleanup
- Sprint artifacts are ephemeral by design (safe to delete post-merge)
- NVIDIA docs may be valuable development reference (decide placement)
- Retrospectives may inform future work (evaluate preservation)
- Use `fd` and `rg` to audit for stale cross-references

**NFR Coverage:** Documentation hygiene

---

## Story 9.1: Create bookmark tags at branch boundaries (docs, clan, clan-01)

As a repository maintainer,
I want to create bookmark tags at significant branch merge points,
So that I can reference specific points in history for debugging or rollback.

**Acceptance Criteria:**

**Given** the branch history: main → docs → clan → clan-01
**When** I create bookmark tags
**Then** tags should be created at:
- `bookmark/pre-docs-merge` - Last commit on main before docs merge
- `bookmark/docs-complete` - docs branch merge commit
- `bookmark/pre-clan-merge` - Last commit before clan branch work began
- `bookmark/clan-complete` - clan branch completion point
- `bookmark/clan-01-start` - First commit on clan-01 branch
- `bookmark/clan-01-complete` - Final commit before main merge

**And** tag format should follow:
- Lightweight tags (not annotated) for bookmarks
- Descriptive names following `bookmark/` prefix convention
- Consistent naming pattern for future reference

**And** documentation should:
- List all bookmark tags in release notes
- Explain what each bookmark represents
- Document rollback procedure using bookmarks

**Prerequisites:** Story 9.0b complete (content cleanup done before tagging)

**Technical Notes:**
- Git tag creation: `git tag bookmark/<name> <commit-hash>`
- Find branch points: `git log --oneline --graph`
- Do not use annotated tags for bookmarks (reserve for releases)
- Reference: `~/.claude/commands/preferences/git-version-control.md`

**NFR Coverage:** NFR-9.2 (History preservation)

---

## Story 9.2: Validate CI/CD workflows on clan-01

As a release engineer,
I want all CI/CD workflows passing on clan-01 before merge authorization,
So that the main branch remains stable and deployable.

**Note:** Epic 2 Story 2.11 already validated CI on clan-01. This story is a pre-merge verification gate, not full re-validation. Scope simplified to "verify CI still green before merge."

**Acceptance Criteria:**

**Given** the clan-01 branch ready for merge
**When** I validate CI/CD workflows
**Then** all checks should pass:
- `nix flake check` succeeds (all outputs evaluate)
- GitHub Actions CI workflow green (all jobs pass)
- All host configurations build successfully
- Terraform validate passes (if applicable)

**And** validation should include:
- All darwin configurations: stibnite, blackphos, rosegold, argentum
- All nixos configurations: cinnabar, electrum, GCP nodes (if enabled)
- All home configurations: cameron, crs58, raquel, christophersmith, janettesmith
- All checks in `modules/checks/`

**And** workflow execution should:
- Trigger via: `gh workflow run ci.yaml --ref clan-01`
- Wait for completion and verify all green
- Document any fixed issues (if any)

**Prerequisites:** Story 9.1 (bookmark tags created)

**Technical Notes:**
- CI workflow: `.github/workflows/ci.yaml`
- Local validation: `nix flake check`
- Matrix jobs: Verify all matrix combinations pass
- Cached job pattern: Ensure cache hits for unchanged configs

**NFR Coverage:** NFR-9.1 (CI/CD must pass before merge)

---

## Story 9.3: Merge clan-01 to main and trigger release

As a repository maintainer,
I want to merge clan-01 to main with a semantic version release,
So that the dendritic + clan architecture is officially released.

**Acceptance Criteria:**

**Given** CI/CD validation passed (Story 9.2)
**When** I merge clan-01 to main
**Then** merge should:
- Use fast-forward merge if possible (`git merge --ff-only`)
- Fall back to merge commit if fast-forward not possible
- Preserve all commit history (no squash, no rebase)
- Never use force-push

**And** release should:
- Create semantic version tag (e.g., `v1.0.0` or `v2.0.0`)
- Generate changelog from conventional commit messages
- Include summary of major changes (architecture migration)
- Reference bookmark tags in release notes

**And** changelog should include:
- Architecture migration: nixos-unified → dendritic + clan
- Machine fleet: 4 darwin + 2 nixos Hetzner + GCP nodes
- Secrets architecture: Two-tier clan vars + sops-nix
- Notable improvements: lazyvim-nix, Pattern A home-manager

**And** post-merge validation should:
- Verify main branch builds: `nix flake check`
- Confirm release tag pushed
- Verify changelog published

**Prerequisites:** Stories 9.0a, 9.0b, 9.1, 9.2 complete (documentation updated, content cleaned, bookmarks created, CI validated)

**Technical Notes:**
- Merge preference: `git checkout main && git merge --ff-only clan-01`
- If ff not possible: `git merge clan-01` (creates merge commit)
- Release tag: `git tag -a v1.0.0 -m "Release message"`
- Never: `git push --force`
- Changelog: Generate from `git log --oneline` or use conventional-commits tool

**NFR Coverage:** NFR-9.1 (Semantic versioning), NFR-9.2 (No force-push)

---

## Dependencies

**Depends on:**
- Epic 8: Documentation accurate (docs must be correct before release)

**Enables:**
- Future development on main branch with stable dendritic + clan architecture

---

## Success Criteria

- [ ] Stale migration guides updated for dendritic architecture
- [ ] Content triage decisions documented
- [ ] Essential content preserved or migrated before any cleanup
- [ ] Bookmark tags created at all branch boundaries
- [ ] All CI/CD workflows passing on clan-01
- [ ] clan-01 merged to main successfully
- [ ] Release tag with semantic version applied
- [ ] Changelog published with release
- [ ] No force-push or history rewriting during merge
- [ ] Main branch builds successfully post-merge

---

## Risk Notes

**Merge risks:**
- Conflicts with main if parallel work occurred
- CI failures on main after merge

**Mitigation:**
- Rebase clan-01 on latest main before merge (if needed)
- Run full CI on main immediately after merge
- Bookmark tags enable quick rollback if issues discovered

**History preservation:**
- Never use `--force` or `--force-with-lease`
- Prefer fast-forward merges
- Create merge commits only when necessary

---

**References:**
- PRD: `docs/notes/development/PRD/functional-requirements.md` (FR-9)
- NFRs: `docs/notes/development/PRD/non-functional-requirements.md` (NFR-9)
- Git preferences: `~/.claude/commands/preferences/git-version-control.md`
- Branch history: main → docs → clan → clan-01
