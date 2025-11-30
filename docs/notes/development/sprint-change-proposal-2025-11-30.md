# Sprint Change Proposal: Post-MVP Expansion (Epics 7-9)

**Date:** 2025-11-30
**Change Type:** Scope Expansion (Post-MVP)
**Scope Classification:** Moderate (Backlog reorganization needed)
**Status:** Pending Approval

---

## Section 1: Issue Summary

### Problem Statement

Epics 1-6 of the infra migration project are complete, delivering the original MVP scope (dendritic + clan migration across 5 machines). New business requirements necessitate infrastructure expansion beyond the original MVP:

1. **Epic 7: GCP Multi-Node Infrastructure** - Primary business objective due to existing GCP contract obligations and GPU availability needs for ML workloads
2. **Epic 8: Documentation Alignment** - Comprehensive documentation update required before release
3. **Epic 9: Branch Consolidation and Release** - Merge clan-01 to main with proper tagging

### Discovery Context

- Epics 1-6 marked DONE in sprint-status.yaml
- Epic 7-9 story titles and notes already defined in sprint-status.yaml (lines 540-592)
- PRD lacks formal FRs/NFRs for these expansion epics
- Proven patterns: Terranix + clan integration validated on Hetzner (cinnabar, electrum)

### Evidence

- `modules/terranix/hetzner.nix` demonstrates replicable terranix pattern
- cinnabar and electrum operational, proving terranix + clan integration
- Business context: GCP contract obligations, GPU availability requirements

---

## Section 2: Impact Analysis

### Epic Impact

| Epic | Status | Impact |
|------|--------|--------|
| Epic 1-6 | DONE | No impact - MVP complete |
| Epic 7 | NEW | GCP infrastructure expansion |
| Epic 8 | NEW | Documentation alignment |
| Epic 9 | NEW | Branch consolidation/release |

### Dependency Chain

```
Epic 7 (GCP) → Epic 8 (Docs) → Epic 9 (Release)
```

- Cannot document GCP infrastructure until it exists
- Cannot merge to main until documentation is accurate

### Artifact Conflicts

| Artifact | Conflict | Resolution |
|----------|----------|------------|
| PRD/functional-requirements.md | Stops at FR-6 | Add FR-7, FR-8, FR-9 |
| PRD/non-functional-requirements.md | No post-MVP NFRs | Add NFR sections |
| PRD/product-scope.md | "Additional VPS" listed as Out of Scope | Clarify MVP vs Post-MVP |
| PRD/implementation-planning.md | Stops at Epic 6 | Add Epic 7-9 descriptions |
| PRD/index.md | No TOC entries for new sections | Add TOC entries |

### Technical Impact

- No code changes required (PRD documentation only)
- Architecture patterns already proven (hetzner.nix template)
- CI/CD unaffected (Epic 9 validates before merge)

---

## Section 3: Recommended Approach

### Selected Path: Direct Adjustment

Add new requirements to PRD without modifying existing MVP scope:

1. **Add FR-7, FR-8, FR-9** to functional-requirements.md
2. **Add Post-MVP NFRs** to non-functional-requirements.md
3. **Add Post-MVP Phases** to product-scope.md
4. **Add Epic 7-9 descriptions** to implementation-planning.md
5. **Update TOC** in PRD/index.md

### Rationale

- MVP complete - no disruption to completed work
- Clear separation between MVP (Epics 1-6) and Post-MVP (Epics 7-9)
- Maintains PRD structure consistency
- Minimal effort, low risk

### Effort Estimate

- **Implementation:** Low (documentation updates only)
- **Risk Level:** Low (additive changes, no modifications to existing scope)
- **Timeline Impact:** None (expansion, not delay)

---

## Section 4: Detailed Change Proposals

### Proposal 1: functional-requirements.md

**Location:** After FR-6 (line 259)
**Action:** Append FR-7, FR-8, FR-9 sections

**FR-7: GCP Multi-Node Infrastructure** (Epic 7)
- FR-7.1: Terranix GCP provisioning with enabled/disabled toggle
- FR-7.2: CPU-only nodes (e2-standard/n2-standard)
- FR-7.3: GPU-capable nodes (T4/A100 accelerators)
- FR-7.4: Clan inventory + zerotier mesh integration

**FR-8: Documentation Alignment** (Epic 8)
- FR-8.1: Starlight docs site update
- FR-8.2: Architecture documentation update
- FR-8.3: Host onboarding guides (darwin vs nixos)
- FR-8.4: Secrets management documentation

**FR-9: Branch Consolidation and Release** (Epic 9)
- FR-9.1: Bookmark tags at branch boundaries
- FR-9.2: CI/CD validation on clan-01
- FR-9.3: Merge to main with history preservation

### Proposal 2: non-functional-requirements.md

**Location:** After SOPS integration (line 96)
**Action:** Append Post-MVP NFR sections

- GCP Infrastructure NFRs (pattern consistency, cost management, deployment consistency)
- Documentation NFRs (accuracy, testability)
- Release NFRs (semantic versioning, history preservation)

### Proposal 3: product-scope.md

**Location:** After "Overall success" (line 136)
**Action:** Add "Post-MVP Expansion Phases" section

- Phase 6: GCP Multi-Cloud Infrastructure
- Phase 7: Documentation Alignment
- Phase 8: Branch Consolidation and Release
- Post-MVP success criteria

### Proposal 4: implementation-planning.md

**Location:** After Epic 6 description (line 38)
**Action:** Add Epic 7-9 descriptions

- Epic 7: GCP Multi-Node Infrastructure (stories, dependencies, pattern)
- Epic 8: Documentation Alignment (stories, scope)
- Epic 9: Branch Consolidation and Release (stories, constraints)

### Proposal 5: PRD/index.md

**Location:** Table of Contents
**Action:** Add TOC entries for FR-7, FR-8, FR-9 and Post-MVP NFRs

---

## Section 5: Implementation Handoff

### Scope Classification: Moderate

Requires backlog reorganization (new epics) but no architectural changes.

### Handoff Recipients

| Role | Responsibility |
|------|---------------|
| PM/Architect | Review and approve PRD changes |
| Development Team | Implement PRD edits after approval |
| Product Owner | Update sprint-status.yaml story details |

### Implementation Tasks

1. [ ] Apply edits to functional-requirements.md (FR-7, FR-8, FR-9)
2. [ ] Apply edits to non-functional-requirements.md (Post-MVP NFRs)
3. [ ] Apply edits to product-scope.md (Post-MVP Phases)
4. [ ] Apply edits to implementation-planning.md (Epic 7-9 descriptions)
5. [ ] Apply edits to PRD/index.md (TOC updates)
6. [ ] Commit changes with message: "docs(prd): add FR-7, FR-8, FR-9 for post-MVP expansion"

### Success Criteria

- [ ] All PRD files updated with new sections
- [ ] TOC references correct
- [ ] FRs/NFRs match sprint-status.yaml story scope
- [ ] Clear separation between MVP (Epics 1-6) and Post-MVP (Epics 7-9)

---

## Appendix: New Requirements Summary

### Functional Requirements Added

| ID | Requirement | Epic |
|----|-------------|------|
| FR-7.1 | GCP provisioning via terranix with toggle | 7 |
| FR-7.2 | CPU-only nodes (e2-standard/n2-standard) | 7 |
| FR-7.3 | GPU-capable nodes (T4/A100) | 7 |
| FR-7.4 | Clan + zerotier integration | 7 |
| FR-8.1 | Starlight docs update | 8 |
| FR-8.2 | Architecture docs update | 8 |
| FR-8.3 | Host onboarding guides | 8 |
| FR-8.4 | Secrets management docs | 8 |
| FR-9.1 | Bookmark tags at branch boundaries | 9 |
| FR-9.2 | CI/CD validation | 9 |
| FR-9.3 | Merge to main | 9 |

### Non-Functional Requirements Added

| ID | Requirement | Epic |
|----|-------------|------|
| NFR-7.1 | Pattern consistency with hetzner.nix | 7 |
| NFR-7.2 | Zero cost for disabled nodes | 7 |
| NFR-7.3 | `clan machines install` deployment | 7 |
| NFR-8.1 | Zero nixos-unified references | 8 |
| NFR-8.2 | Testable documentation | 8 |
| NFR-9.1 | Semantic versioning with changelog | 9 |
| NFR-9.2 | No force-push or history rewriting | 9 |

---

## Approval

- [x] **Approved** - Proceed with PRD updates
- [ ] **Revise** - Return to Step 3 for refinement
- [ ] **Reject** - Scope expansion not approved

**Approver:** User (via correct-course workflow)
**Date:** 2025-11-30

## Implementation Status

All PRD edits applied successfully:
- [x] functional-requirements.md - FR-7, FR-8, FR-9 added
- [x] non-functional-requirements.md - Post-MVP NFRs added
- [x] product-scope.md - Post-MVP Expansion Phases added
- [x] implementation-planning.md - Epic 7-9 descriptions added
- [x] PRD/index.md - TOC entries updated

---
