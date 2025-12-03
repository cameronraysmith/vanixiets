# Story 8.11: Remediate AMDiRE Development Documentation Staleness

Status: drafted

## Story

As a contributor,
I want development documentation that accurately reflects the current project state,
so that I understand the actual goals, constraints, and architectural decisions when contributing.

## Acceptance Criteria

### Critical Priority (MUST complete)

1. **AC-C1**: domain-model.md updated - nixos-unified section removed, 8-machine fleet documented, current/target inversion fixed
2. **AC-C2**: goals-and-objectives.md updated - achieved goals (G-S04, G-S06, G-U02, G-U03, G-U06) moved to "Achieved" section with correct statuses
3. **AC-C3**: project-scope.md updated - current/target sections swapped, 8-machine fleet added, conclusion reflects migration completion
4. **AC-C4**: system-vision.md updated - current/target vision rewritten, machine diagram shows 8 machines, Phase 0-6 marked complete

### High Priority (SHOULD complete)

5. **AC-H1**: constraints-and-rules.md updated - migration-specific rules section removed or marked historical, host inventory shows 8 machines
6. **AC-H2**: glossary.md updated - 3 new hosts added (electrum, galena, scheelite), nixos-unified marked deprecated, Pattern A term defined
7. **AC-H3**: deployment-requirements.md updated - 8-machine fleet in all examples, current/target framing removed
8. **AC-H4**: functional-hierarchy.md updated - migration functions (MF-001 to MF-004) reframed as historical, current operations functions added or referenced
9. **AC-H5**: usage-model.md updated - UC-007 marked as historical, all examples show 8 machines
10. **AC-H6**: ADR-0003 resolved - either major update to reflect dendritic overlay patterns OR superseded by new ADR-0017

### Medium Priority (SHOULD address)

11. **AC-M1**: risk-list.md updated - risk statuses reflect Epics 1-7 completion (R-001, R-007 no longer "Not started")
12. **AC-M2**: system-constraints.md updated - SC-010 reflects migration completion, not ongoing

### Low Priority (MAY address)

13. **AC-L1**: stakeholders.md updated - nixos-unified status changed from "being replaced" to "deprecated Nov 2024"
14. **AC-L2**: quality-requirements.md updated - measurement examples reference 8 machines where applicable
15. **AC-L3**: requirements/index.md updated - overview notes migration completion

### Validation

16. **AC-V1**: Zero nixos-unified references describing it as "current" architecture in development/ docs
17. **AC-V2**: All machine lists in development/ docs show 8 machines: stibnite, blackphos, rosegold, argentum (Darwin), cinnabar, electrum, galena, scheelite (NixOS)
18. **AC-V3**: Starlight build passes (`bun run build` in packages/docs/)

## Tasks / Subtasks

### Task 1: Remediate Critical Priority Files (AC: C1-C4)

Estimated effort: 7-10 hours

- [ ] **1.1** Update domain-model.md (AC: C1)
  - [ ] Remove nixos-unified autowiring section (lines 38-56)
  - [ ] Remove configurations/ directory references (line 46)
  - [ ] Update host inventory (lines 135-147) to 8 machines
  - [ ] Fix current/target inversion throughout
  - [ ] Verify all dendritic pattern references are current
- [ ] **1.2** Update goals-and-objectives.md (AC: C2)
  - [ ] Move G-S04 (dendritic) from in-progress to achieved
  - [ ] Move G-S06 (clan) from in-progress to achieved
  - [ ] Move G-U02 (multi-host) from in-progress to achieved
  - [ ] Move G-U03 from in-progress to achieved
  - [ ] Move G-U06 from in-progress to achieved
  - [ ] Remove future migration framing (lines 491-527)
  - [ ] Update all status markers to reflect current state
- [ ] **1.3** Update project-scope.md (AC: C3)
  - [ ] Rename "Target state architecture" section to "Current architecture"
  - [ ] Rename or remove "Current state architecture" section (nixos-unified)
  - [ ] Add 8-machine fleet to scope (lines 33-38 currently show 4)
  - [ ] Update conclusion to reflect migration completion
- [ ] **1.4** Update system-vision.md (AC: C4)
  - [ ] Rewrite current state vision (lines 29-47) to reflect dendritic + clan
  - [ ] Update machine diagram (lines 74-151) to show 8 machines
  - [ ] Mark Phase 0-6 as complete (lines 325-362)
  - [ ] Update target vision to reflect future expansion goals

### Task 2: Remediate High Priority Files (AC: H1-H6)

Estimated effort: 8-10 hours

- [ ] **2.1** Update constraints-and-rules.md (AC: H1)
  - [ ] Remove or mark historical: migration-specific rules (lines 200-218)
  - [ ] Update host inventory (lines 57-60) from 4 to 8 machines
  - [ ] Remove "preserve nixos-unified" constraint (line 95)
- [ ] **2.2** Update glossary.md (AC: H2)
  - [ ] Add electrum definition
  - [ ] Add galena definition
  - [ ] Add scheelite definition
  - [ ] Update nixos-unified definition (lines 124-127) to mark deprecated
  - [ ] Add Pattern A term (dendritic aggregate pattern)
  - [ ] Update migration-related terms to reflect completion
- [ ] **2.3** Update deployment-requirements.md (AC: H3)
  - [ ] Update introduction (line 10) to remove current/target framing
  - [ ] Update zerotier example (lines 368-382) to show 8 hosts
  - [ ] Update all other examples to reference 8-machine fleet
- [ ] **2.4** Update functional-hierarchy.md (AC: H4)
  - [ ] Reframe MF-001 to MF-004 (lines 649-722) as historical/completed
  - [ ] Add or reference current operations functions for 8-machine fleet
  - [ ] Add terranix/terraform functions if not present
- [ ] **2.5** Update usage-model.md (AC: H5)
  - [ ] Update introduction (line 12) to remove current/target framing
  - [ ] Mark UC-007 as historical migration use case
  - [ ] Update Phase 0-6 references (lines 440-474) to reflect completion
  - [ ] Update all machine examples to 8-machine fleet
- [ ] **2.6** Resolve ADR-0003 (AC: H6)
  - [ ] Assess delta between current ADR-0003 and dendritic overlay patterns
  - [ ] If delta < 50%: Update ADR-0003 with dendritic patterns, pkgs-by-name, correct paths
  - [ ] If delta >= 50%: Create ADR-0017 (Dendritic Overlay Patterns), mark ADR-0003 superseded
  - [ ] Remove nixos-unified references (lines 12-20, 30-42, 373-424)
  - [ ] Update overlay paths from `overlays/` to `modules/nixpkgs/overlays/`
  - [ ] Document five-layer overlay architecture

### Task 3: Remediate Medium Priority Files (AC: M1-M2)

Estimated effort: 1.5 hours

- [ ] **3.1** Update risk-list.md (AC: M1)
  - [ ] Update R-001 status (line 68) from "Not started" to reflect Epic 1 completion
  - [ ] Update R-007 status (line 508) from "Not started" to reflect completion
  - [ ] Review all risk statuses for alignment with Epics 1-7 completion
- [ ] **3.2** Update system-constraints.md (AC: M2)
  - [ ] Update SC-010 (lines 560-597) to reflect migration completion
  - [ ] Remove "ongoing migration" framing

### Task 4: Remediate Low Priority Files (AC: L1-L3)

Estimated effort: 1 hour

- [ ] **4.1** Update stakeholders.md (AC: L1)
  - [ ] Update nixos-unified status (line 88) from "being replaced" to "deprecated Nov 2024"
- [ ] **4.2** Update quality-requirements.md (AC: L2)
  - [ ] Update measurement examples to reference 8 machines where applicable
- [ ] **4.3** Update requirements/index.md (AC: L3)
  - [ ] Add note that migration is complete as of Epic 6

### Task 5: Validation (AC: V1-V3)

Estimated effort: 0.5-1 hour

- [ ] **5.1** Verify zero nixos-unified "current" references (AC: V1)
  - [ ] Run: `rg "nixos-unified" packages/docs/src/content/docs/development/`
  - [ ] For each match, verify it describes nixos-unified as deprecated/historical, not current
- [ ] **5.2** Verify 8-machine fleet references (AC: V2)
  - [ ] Run: `rg "stibnite|blackphos|rosegold|argentum|cinnabar" packages/docs/src/content/docs/development/`
  - [ ] Verify all machine lists include: electrum, galena, scheelite
- [ ] **5.3** Verify Starlight build (AC: V3)
  - [ ] Run: `cd packages/docs && bun run build`
  - [ ] Verify zero errors

## Dev Notes

### Story 8.7 Audit Reference

Primary source: `docs/notes/development/work-items/story-8.7-amdire-audit-results.md`

Every fix in this story traces to a finding in the Story 8.7 audit.
Do not invent new issues - fix what was identified.

### Common Staleness Patterns to Fix

From Story 8.7 audit lines 29-34:

1. **nixos-unified as "current"**: 9 files describe nixos-unified as current when dendritic + clan is actual
2. **5-machine vs 8-machine fleet**: 8 files reference only 5 machines, missing electrum, galena, scheelite
3. **Migration as pending**: 7 files describe completed migration (Epics 1-7) as future work
4. **Target/Current inversion**: 5 files describe dendritic + clan as "target" when it's current state
5. **Missing two-tier secrets**: 6 files don't document clan vars + sops-nix architecture

### Key Terminology Changes

| Old Term | New Term | Notes |
|----------|----------|-------|
| nixos-unified (current) | nixos-unified (deprecated Nov 2024) | Was replaced by dendritic + clan |
| target architecture | current architecture | Migration complete as of Epic 6 |
| configurations/ | modules/{darwin,nixos,home}/ | Dendritic module organization |
| overlays/ | modules/nixpkgs/overlays/ | Five-layer overlay architecture |
| 5 machines | 8 machines | Added electrum, galena, scheelite |

### 8-Machine Fleet Reference

| Hostname | Type | Primary User | Role |
|----------|------|--------------|------|
| stibnite | nix-darwin | crs58 | Primary workstation |
| blackphos | nix-darwin | raquel | Secondary workstation |
| rosegold | nix-darwin | janettesmith | Family workstation |
| argentum | nix-darwin | christophersmith | Family workstation |
| cinnabar | NixOS VPS | cameron | Zerotier coordinator (Hetzner) |
| electrum | NixOS VPS | cameron | Secondary VPS (Hetzner) |
| galena | NixOS VPS | cameron | CPU compute (GCP) |
| scheelite | NixOS VPS | cameron | GPU compute (GCP) |

### ADR-0003 Decision Criteria

**Option A - Update ADR-0003:** If the existing ADR structure can accommodate dendritic overlay patterns with < 50% content change:
- Update title to reflect dendritic patterns
- Update context section for flake-parts + clan
- Update decision section with five-layer architecture
- Update consequences for current implementation
- Update paths from `overlays/` to `modules/nixpkgs/overlays/`

**Option B - Supersede with ADR-0017:** If changes require > 50% rewrite:
- Create ADR-0017: Dendritic Overlay Patterns
- Mark ADR-0003 as superseded by ADR-0017 (line 7)
- Document migration rationale in ADR-0017

**Decision criteria for dev agent:**
1. Count lines in ADR-0003 requiring change
2. If changed lines / total lines < 0.5: Option A
3. If changed lines / total lines >= 0.5: Option B

### Learnings from Previous Story

**From Story 8.8 (Status: done)**

Story 8.8 created 5 tutorials (2,073 lines total) addressing the empty tutorials/ directory.
Key patterns established:

- Diataxis compliance: learning-oriented (not task-oriented like guides)
- Cross-reference pattern: 31 cross-references to guides added
- Build validation: `bun run build` + linkcheck passes
- Commit pattern: 6 atomic commits

No technical debt or pending items from Story 8.8 affect Story 8.11.

[Source: docs/notes/development/work-items/8-8-create-tutorials-for-common-user-workflows.md]

### Project Structure Notes

All files to update are in: `packages/docs/src/content/docs/development/`

Subdirectories:
- `context/` - 5 files affected (domain-model, goals-and-objectives, project-scope, glossary, constraints-and-rules, stakeholders)
- `requirements/` - 6 files affected (system-vision, deployment-requirements, functional-hierarchy, usage-model, risk-list, system-constraints, quality-requirements, index)
- `architecture/adrs/` - 1 file affected (0003-overlay-composition-patterns.md)

### References

- [Source: docs/notes/development/work-items/story-8.7-amdire-audit-results.md] - Primary audit artifact
- [Source: docs/notes/development/epics/epic-8-documentation-alignment.md#Story-8.11] - Epic definition
- [Source: docs/notes/development/research/documentation-coverage-analysis.md] - AMDiRE framework structure
- [Source: CLAUDE.md#Machines-and-Users] - 8-machine fleet definition

### Estimated Effort Summary

| Priority | Files | Effort |
|----------|-------|--------|
| Critical | 4 | 7-10h |
| High | 6 | 8-10h |
| Medium | 2 | 1.5h |
| Low | 3 | 1h |
| Validation | - | 0.5-1h |
| **Total** | **15** | **18-24h** |

### NFR Coverage

- **NFR-8.7**: Development documentation accuracy

### Chunking Strategy for Dev Agent

Recommended execution order for session management:

**Session 1 (Critical):** Tasks 1.1-1.4 - complete all critical files first
**Session 2 (High):** Tasks 2.1-2.5 - complete non-ADR high priority files
**Session 3 (ADR + Rest):** Task 2.6 + Tasks 3-5 - ADR decision, medium/low, validation

This chunking ensures:
- Each session produces independently valuable output
- Critical files are fixed first (highest user impact)
- ADR decision is made with full context from other updates
- Validation runs after all changes complete

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Will be filled by implementing agent -->

### Debug Log References

<!-- Will be filled by implementing agent -->

### Completion Notes List

<!-- Will be filled by implementing agent -->

### File List

<!-- Will be filled by implementing agent -->

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-02 | Story drafted | create-story workflow |
