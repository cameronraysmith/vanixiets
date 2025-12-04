# Story 9.0b: Clean Up Migration Artifacts and Migrate Essential Content

Status: ready-for-review

## Story

As a repository maintainer,
I want to triage content in docs/notes/development/ with a DELETE-by-default bias,
so that ephemeral migration artifacts are removed before the clan-01 to main merge.

## Background

Epic 8 retrospective (2025-12-03) identified that `docs/notes/development/` contains almost entirely ephemeral artifacts from the nixos-unified to dendritic migration. The correct approach is **DELETE by default**, not preservation.

**Key principle:** This is cleanup before merge. We're removing ephemeral artifacts, not preserving history. The migration is complete; these artifacts served their purpose.

**Critical clarification:** The `docs/` directory is NOT being deleted. Only `docs/notes/development/` content is triaged for deletion. Sprint management files are RETAINED until Story 9.3 (pre-merge cleanup) because they're needed to track Epic 9 execution.

## Acceptance Criteria

1. **AC-1**: Content triage matrix documented with DELETE-by-default decisions
   - Every file in `docs/notes/development/` has a documented decision
   - Default is DEFER-DELETE unless explicitly excepted

2. **AC-2**: NVIDIA docs (`nvidia-module-analysis.md`) marked DEFER-DELETE
   - Pre-assessed as ephemeral Epic 7 research (subagent evaluation 2025-12-03)
   - Actionable config should already be in scheelite module, not docs

3. **AC-3**: Retrospectives marked DEFER-DELETE
   - Lessons already captured in session context
   - No migration to Starlight required

4. **AC-4**: Only explicit retention exception applied
   - RETAIN: `cluster/nix-kubernetes-product-brief-references.md` (next phase planning)
   - No other content meets the migration bar

5. **AC-5**: All sprint management files listed as DEFER-DELETE for Story 9.3
   - `sprint-status.yaml`, `bmm-workflow-status.yaml`
   - `work-items/*.md`, `epics/*.md`

6. **AC-6**: Starlight build passes (no migrations expected, validation only)
   - `just docs-build` succeeds
   - `just docs-linkcheck` passes

7. **AC-7**: No content deleted in this story (deletions happen in Story 9.3)
   - All files remain in place
   - Only triage decisions documented

## Tasks / Subtasks

### Task 1: Inventory docs/notes/development/ Content (AC: 1)

- [x] 1.1 Run `fd -t f . docs/notes/development/` to get complete file list
- [x] 1.2 Run `fd -t d . docs/notes/development/` to get directory structure
- [x] 1.3 Count files per category for triage matrix

### Task 2: Confirm NVIDIA docs Assessment (AC: 2)

- [x] 2.1 Verify `nvidia-module-analysis.md` is ephemeral Epic 7 research
- [x] 2.2 Confirm actionable config (lines 234-274) should be in scheelite module
- [x] 2.3 Mark as DEFER-DELETE in triage matrix
- [x] 2.4 Document rationale: session-bound analysis, stale nixpkgs refs, Epic 7-specific

### Task 3: Create Content Triage Matrix (AC: 1, 3, 4, 5)

- [x] 3.1 Create `docs/notes/development/work-items/story-9.0b-content-triage-matrix.md`
- [x] 3.2 Apply DELETE-by-default to all categories:

| Category | Decision | Notes |
|----------|----------|-------|
| `cluster/nix-kubernetes-product-brief-references.md` | **RETAIN** | Next phase planning |
| `nvidia-module-analysis.md` | DEFER-DELETE | Ephemeral Epic 7 research |
| `retrospectives/*` (4 files) | DEFER-DELETE | Lessons captured in session |
| `research/*` | DEFER-DELETE | Served Epic 8 purpose |
| `epics/*` | DEFER-DELETE | Sprint tracking artifacts |
| `work-items/*` | DEFER-DELETE | Sprint tracking artifacts |
| `sprint-status.yaml` | DEFER-DELETE | Sprint tracking |
| `bmm-workflow-status.yaml` | DEFER-DELETE | Sprint tracking |
| `PRD/*` | DEFER-DELETE | Requirements in Starlight |
| `architecture/*` | DEFER-DELETE | Architecture in ADRs |
| All planning docs | DEFER-DELETE | Historical artifacts |
| All other files | DEFER-DELETE | Ephemeral migration artifacts |

- [x] 3.3 List every file with its decision and brief rationale

### Task 4: Document Deferred Deletions (AC: 5, 7)

- [x] 4.1 Create definitive file list for Story 9.3 deletion
- [x] 4.2 Organize by directory for efficient bulk deletion
- [x] 4.3 Note the single RETAIN exception clearly

### Task 5: Validation (AC: 6, 7)

- [x] 5.1 Run `just docs-build` and verify success (no content changes, build unaffected)
- [x] 5.2 Run `just docs-linkcheck` and verify no broken links (no content changes)
- [x] 5.3 Verify no files were deleted (`git status`)
- [x] 5.4 Verify triage matrix accounts for all files in inventory

## Dev Notes

### Decision Bias: DELETE by Default

Almost everything in `docs/notes/development/` is ephemeral artifacts from the nixos-unified to dendritic migration. The bias is toward DELETION, not preservation.

### Retention Exceptions (only one)

| File | Decision | Rationale |
|------|----------|-----------|
| `cluster/nix-kubernetes-product-brief-references.md` | **RETAIN** | Explicitly needed for next development phase (post-merge product planning) |

### NVIDIA docs Assessment (Pre-resolved)

**Decision: DEFER-DELETE**

Subagent assessment (2025-12-03) determined:

1. **Not needed by future maintainers** - One-time deep analysis of nixpkgs source code (Nov 26, 2025 commit) with recommendations specific to scheelite machine configuration
2. **Entirely Epic 7-specific** - Analyzes scheelite (GCP A100 GPU), comparison with gaetanlepage's config, specific nixpkgs commit hashes that will become stale
3. **Available elsewhere** - NVIDIA official docs, nixpkgs module source, gaetanlepage-dendritic-nix-config repository
4. **Actionable output exists elsewhere** - The recommended Nix configuration (lines 234-274) should live in the actual machine module, not docs

### Category Decisions (All DEFER-DELETE except one RETAIN)

| Category | Count | Decision | Rationale |
|----------|-------|----------|-----------|
| Retrospectives | 4 | DEFER-DELETE | Ephemeral, lessons captured in session |
| Research docs | 1 | DEFER-DELETE | Served Epic 8 purpose, now obsolete |
| Planning docs | ~15 | DEFER-DELETE | Historical artifacts, decisions executed |
| Epic definitions | 14 | DEFER-DELETE | Superseded by Starlight development docs |
| Work items | ~80+ | DEFER-DELETE | Ephemeral sprint tracking |
| Sprint status | 2 | DEFER-DELETE | Ephemeral tracking |
| PRD docs | 3+ | DEFER-DELETE | Requirements captured in Starlight |
| Architecture notes | varies | DEFER-DELETE | Architecture in Starlight ADRs |
| NVIDIA docs | 1 | DEFER-DELETE | Ephemeral Epic 7 research |
| Cluster docs | 1 | **RETAIN** | Next phase planning |

### What DEFER-DELETE Means

Files marked DEFER-DELETE will be:
1. Documented in the triage matrix (this story)
2. Listed for Story 9.3 pre-merge cleanup
3. Deleted as the final step before merge to main

### Expected Commits

1. `docs(triage): inventory docs/notes/development/ content`
2. `docs(triage): create content triage matrix with deletion bias`
3. `docs(triage): document all DEFER-DELETE items for Story 9.3`
4. `chore(story-9.0b): complete implementation, mark for review`

### Constraints

1. **NO DELETIONS in this story** - Only triage decisions documented
2. **DELETE by default** - Only explicit exceptions retained
3. **Single RETAIN exception** - `cluster/nix-kubernetes-product-brief-references.md`
4. **Triage matrix required** - Every file must have a documented decision
5. **Atomic commits** - Per logical change

### References

- Epic 9 definition: `docs/notes/development/epics/epic-9-branch-consolidation-and-release.md`
- Epic 8 retrospective: `docs/notes/development/retrospectives/epic-8-documentation-alignment.md`
- Story 9.0a (previous): `docs/notes/development/work-items/9-0a-update-stale-migration-guides.md`

### Learnings from Previous Story

**From Story 9.0a (Status: done)**

Story 9.0a addressed stale migration guides for dendritic architecture:

- Path mappings from nixos-unified to dendritic documented
- ADR-0003 superseded by ADR-0017
- Terminology updates applied repo-wide
- 8 atomic commits pattern validated

[Source: docs/notes/development/work-items/9-0a-update-stale-migration-guides.md]

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-03 | Story drafted via create-story workflow | SM workflow |
| 2025-12-03 | Revised with DELETE-by-default bias per ambiguity resolution | Party Mode |
| 2025-12-03 | NVIDIA docs assessed as DEFER-DELETE (subagent evaluation) | Explore agent |
| 2025-12-03 | Implementation complete: triage matrix created (163 files, 1 RETAIN, 162 DEFER-DELETE) | Dev agent |

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

### Completion Notes List

- 2025-12-03: Inventoried 163 files across 10 directories
- 2025-12-03: Confirmed NVIDIA module analysis is ephemeral Epic 7 research (scheelite GCP A100)
- 2025-12-03: Created triage matrix with 1 RETAIN, 162 DEFER-DELETE
- 2025-12-03: Story 9.3 deletion manifest ready with clear commands

### File List

- `docs/notes/development/work-items/story-9.0b-content-triage-matrix.md` (created, 293 lines)
