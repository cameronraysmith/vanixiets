# Story 8.12: Create Foundational Architecture Decision Records

Status: review

## Story

As a contributor or future maintainer,
I want ADRs documenting the foundational architectural decisions (dendritic flake-parts adoption, clan-core orchestration, and their integration),
so that I understand why these patterns were adopted, what alternatives were considered, and how they work together.

## Background

Story 8.7 audit identified a critical traceability gap: the two most important architectural decisions (dendritic flake-parts and clan-core) have no ADRs, while less significant decisions (TypeScript config, Bun workspaces) do.
This creates an inverted importance hierarchy in architectural documentation.

**Story 8.7 Audit Findings (lines 145-152, 214-222):**
- Missing ADR for dendritic flake-parts migration decision
- Missing ADR for clan-core integration decision
- Missing ADR for multi-platform coordination strategy
- Missing ADR for terranix infrastructure provisioning

**Epic 1 GO/NO-GO Decision:**
The migration was validated and approved on 2025-11-20 with ALL 7 decision criteria passing:
- AC1.1: Infrastructure Deployment Success
- AC1.2: Dendritic Flake-Parts Pattern Validated
- AC1.3: Nix-Darwin + Clan Integration Proven
- AC1.4: Heterogeneous Networking Validated
- AC1.5: Transformation Pattern Documented
- AC1.6: Home-Manager Integration Proven
- AC1.7: Pattern Confidence Assessment (ALL 7 patterns HIGH)

## Acceptance Criteria

### ADR-0018: Dendritic Flake-Parts Architecture (Required)

1. **AC-18.1**: ADR file created at `packages/docs/src/content/docs/development/architecture/adrs/0018-dendritic-flake-parts-architecture.md`
2. **AC-18.2**: Context section documents:
   - nixos-unified limitations (specialArgs anti-pattern, autowiring opacity)
   - Dendritic pattern benefits from flake-parts ecosystem
   - Epic 1 validation evidence with story references
3. **AC-18.3**: Decision section documents:
   - Adoption of dendritic flake-parts over nixos-unified
   - Use of import-tree for auto-discovery
   - Explicit `flake.modules` namespace exports
   - Module organization: `modules/{darwin,nixos,home}/`
4. **AC-18.4**: Alternatives section documents:
   - Stay with nixos-unified (rejected: specialArgs pollution, implicit wiring)
   - Raw flake-parts without dendritic (rejected: no organizational convention)
   - Other frameworks evaluated or not evaluated
5. **AC-18.5**: Consequences section covers positive, negative, and neutral outcomes
6. **AC-18.6**: References section includes:
   - Internal: Epic 1 stories (1.1, 1.2, 1.6, 1.7), GO/NO-GO decision
   - External: dendritic-flake-parts repo, import-tree repo, reference implementations
   - Cross-references: ADR-0017 (overlay patterns), concepts/dendritic-architecture.md

### ADR-0019: Clan-Core Orchestration (Required)

7. **AC-19.1**: ADR file created at `packages/docs/src/content/docs/development/architecture/adrs/0019-clan-core-orchestration.md`
8. **AC-19.2**: Context section documents:
   - Multi-machine coordination requirements (4 darwin + 4 nixos)
   - Secrets management needs across machines
   - Zerotier VPN mesh coordination
   - Infrastructure provisioning integration
9. **AC-19.3**: Decision section documents:
   - Adoption of clan-core for orchestration
   - Clan inventory for machine registration
   - Clan vars for generated secrets (Tier 1)
   - Clan services for cross-machine coordination
10. **AC-19.4**: Alternatives section documents:
    - colmena (rejected: less integrated secrets)
    - deploy-rs (rejected: deployment only, no secrets/services)
    - morph (rejected: less active development)
    - Manual coordination (rejected: doesn't scale to 8 machines)
11. **AC-19.5**: Consequences section covers positive, negative, and neutral outcomes
12. **AC-19.6**: References section includes:
    - Internal: Epic 1 stories (1.3, 1.9, 1.10A), GO/NO-GO decision
    - External: clan-core repo, clan-infra, reference implementations
    - Cross-references: ADR-0011 (sops), concepts/clan-integration.md

### ADR-0020: Dendritic + Clan Integration (Required)

13. **AC-20.1**: ADR file created at `packages/docs/src/content/docs/development/architecture/adrs/0020-dendritic-clan-integration.md`
14. **AC-20.2**: Context section documents:
    - Dendritic provides module organization
    - Clan provides orchestration
    - Integration non-obvious (neither designed for the other)
    - Epic 1 validated the synthesis
15. **AC-20.3**: Decision section documents:
    - Clan as flake-parts module (imports dendritic modules)
    - Module namespace exports accessible to clan inventory
    - Two-tier secrets: clan vars (system) + sops-nix (home-manager)
    - Zerotier integration via clan services
16. **AC-20.4**: Synthesis patterns section documents:
    - `flake.clan` configuration within flake-parts
    - `clanModules` importing from dendritic `flake.modules`
    - Cross-platform module reuse (darwin/nixos share home-manager modules)
17. **AC-20.5**: Consequences section covers positive, negative, and neutral outcomes
18. **AC-20.6**: References section includes:
    - Internal: Epic 1 stories (1.8, 1.10, 1.12), GO/NO-GO decision
    - Cross-references: ADR-0018, ADR-0019, both concepts docs

### ADR-0021: Terranix Infrastructure Provisioning (Optional)

19. **AC-21.1**: ADR file created at `packages/docs/src/content/docs/development/architecture/adrs/0021-terranix-infrastructure-provisioning.md`
20. **AC-21.2**: Context section documents:
    - Multi-cloud requirement (Hetzner VPS, GCP compute)
    - Infrastructure-as-code preference
    - Toggle mechanism for cost control
21. **AC-21.3**: Decision section documents:
    - Terranix over raw Terraform (Nix expression benefits)
    - Provider modules (hetzner.nix, gcp.nix)
    - Toggle pattern for ephemeral resources
    - Integration with clan deployment workflow
22. **AC-21.4**: Consequences section covers positive, negative, and neutral outcomes
23. **AC-21.5**: References section includes Epic 7 stories (7.1, 7.2, 7.4)

### ADR Format and Index (Required)

24. **AC-IDX.1**: All ADRs follow existing format (frontmatter, Status, Date, Scope, Context, Decision, Consequences, References)
25. **AC-IDX.2**: ADR-0017 used as structural template (newest, well-structured)
26. **AC-IDX.3**: ADR index updated with new entries organized by section
27. **AC-IDX.4**: ADRs cross-reference each other where relevant (0018 ↔ 0019 ↔ 0020)
28. **AC-IDX.5**: Starlight build passes with all new ADRs

## Tasks / Subtasks

### Task 1: Research and Context Gathering (AC: all)

- [x] 1.1 Read Epic 1 GO/NO-GO decision document completely [Source: docs/notes/development/go-no-go-decision.md]
- [x] 1.2 Review concepts/dendritic-architecture.md for existing documentation
- [x] 1.3 Review concepts/clan-integration.md for existing documentation
- [x] 1.4 Read ADR-0017 as template reference [Source: packages/docs/src/content/docs/development/architecture/adrs/0017-dendritic-overlay-patterns.md]
- [x] 1.5 Read ADR-0011 as comprehensive example [Source: packages/docs/src/content/docs/development/architecture/adrs/0011-sops-secrets-management.md]
- [x] 1.6 Review reference repositories for pattern context (optional, as needed)

### Task 2: Create ADR-0018 Dendritic Flake-Parts Architecture (AC: 18.1-18.6)

- [x] 2.1 Create file with frontmatter (title, Status: Accepted, Date: 2024-11-XX, Scope: Nix configuration)
- [x] 2.2 Write Context section:
  - [x] 2.2.1 Document nixos-unified limitations from Epic 1 findings
  - [x] 2.2.2 Document dendritic pattern benefits identified during migration
  - [x] 2.2.3 Reference Epic 1 validation evidence (Stories 1.1, 1.2, 1.6, 1.7)
- [x] 2.3 Write Decision section:
  - [x] 2.3.1 Document import-tree adoption decision
  - [x] 2.3.2 Document flake.modules namespace pattern
  - [x] 2.3.3 Document module directory organization
- [x] 2.4 Write Alternatives section:
  - [x] 2.4.1 Stay with nixos-unified (rejected, reasons)
  - [x] 2.4.2 Raw flake-parts without dendritic (rejected, reasons)
- [x] 2.5 Write Consequences section (positive, negative, neutral)
- [x] 2.6 Write References section with internal/external links

### Task 3: Create ADR-0019 Clan-Core Orchestration (AC: 19.1-19.6)

- [x] 3.1 Create file with frontmatter
- [x] 3.2 Write Context section:
  - [x] 3.2.1 Document multi-machine coordination requirements (8 machines)
  - [x] 3.2.2 Document secrets management needs
  - [x] 3.2.3 Document zerotier VPN mesh requirements
- [x] 3.3 Write Decision section:
  - [x] 3.3.1 Document clan inventory pattern
  - [x] 3.3.2 Document clan vars for Tier 1 secrets
  - [x] 3.3.3 Document clan services for coordination
- [x] 3.4 Write Alternatives section:
  - [x] 3.4.1 colmena (rejected, reasons)
  - [x] 3.4.2 deploy-rs (rejected, reasons)
  - [x] 3.4.3 morph (rejected, reasons)
  - [x] 3.4.4 Manual coordination (rejected, reasons)
- [x] 3.5 Write Consequences section
- [x] 3.6 Write References section with cross-references to ADR-0018

### Task 4: Create ADR-0020 Dendritic + Clan Integration (AC: 20.1-20.6)

- [x] 4.1 Create file with frontmatter
- [x] 4.2 Write Context section:
  - [x] 4.2.1 Document dendritic module organization role
  - [x] 4.2.2 Document clan orchestration role
  - [x] 4.2.3 Document integration challenges (neither designed for other)
  - [x] 4.2.4 Reference Epic 1 synthesis validation
- [x] 4.3 Write Decision section:
  - [x] 4.3.1 Clan as flake-parts module pattern
  - [x] 4.3.2 Module namespace exports to clan inventory
  - [x] 4.3.3 Two-tier secrets architecture
  - [x] 4.3.4 Zerotier integration approach
- [x] 4.4 Write Synthesis patterns section:
  - [x] 4.4.1 flake.clan within flake-parts
  - [x] 4.4.2 clanModules importing from flake.modules
  - [x] 4.4.3 Cross-platform module reuse
- [x] 4.5 Write Consequences section
- [x] 4.6 Write References section with cross-references to ADR-0018 and ADR-0019

### Task 5: Create ADR-0021 Terranix Infrastructure (AC: 21.1-21.5, Optional)

- [x] 5.1 Create file with frontmatter
- [x] 5.2 Write Context section:
  - [x] 5.2.1 Multi-cloud requirement (Hetzner, GCP)
  - [x] 5.2.2 Infrastructure-as-code preference
  - [x] 5.2.3 Cost control via toggle patterns
- [x] 5.3 Write Decision section:
  - [x] 5.3.1 Terranix over raw Terraform (Nix benefits)
  - [x] 5.3.2 Provider modules pattern
  - [x] 5.3.3 Toggle mechanism for ephemeral resources
- [x] 5.4 Write Consequences section
- [x] 5.5 Write References section (Epic 7 stories)

### Task 6: Update ADR Index and Validation (AC: IDX.1-IDX.5)

- [x] 6.1 Update ADR index.md with new entries
  - [x] 6.1.1 Add section header if needed (e.g., "Architecture Patterns")
  - [x] 6.1.2 Add ADR-0018 entry
  - [x] 6.1.3 Add ADR-0019 entry
  - [x] 6.1.4 Add ADR-0020 entry
  - [x] 6.1.5 Add ADR-0021 entry (if created)
- [x] 6.2 Verify all ADRs follow consistent format
- [x] 6.3 Verify cross-references between ADRs are valid
- [x] 6.4 Run `just docs-build` to validate Starlight build
- [x] 6.5 Run `just docs-linkcheck` to validate all links

## Dev Notes

### ADR Format Template (from ADR-0017)

```markdown
---
title: "ADR-00XX: Title"
---

**Status**: Accepted
**Date**: YYYY-MM-DD
**Scope**: [Nix configuration | Infrastructure | etc.]
**Supersedes**: [link if applicable]

## Context

[Problem statement, requirements, constraints]

### Key architectural changes (if migration)

[Description of changes made]

## Decision

[What was decided and why]

### Pattern/Approach details

[Implementation specifics]

## Consequences

### Positive
[Benefits]

### Negative
[Drawbacks]

### Neutral
[Trade-offs]

## References

### Internal
[Links to internal docs, stories, decisions]

### External
[Links to external repos, documentation]
```

### Reference Repository Locations

For ADR context and evidence gathering:

| Repository | Location | Purpose |
|------------|----------|---------|
| dendritic-flake-parts | `~/projects/nix-workspace/dendritic-flake-parts/` | Pattern source |
| import-tree | `~/projects/nix-workspace/import-tree/` | Auto-discovery mechanism |
| clan-core | `~/projects/nix-workspace/clan-core/` | Clan source |
| clan-infra | `~/projects/nix-workspace/clan-infra/` | Primary clan usage reference |
| dendrix-dendritic-nix | `~/projects/nix-workspace/dendrix-dendritic-nix/` | Dendritic reference |
| drupol-dendritic-infra | `~/projects/nix-workspace/drupol-dendritic-infra/` | Dendritic reference |
| test-clan | `~/projects/nix-workspace/test-clan/` | Epic 1 validation repository |

### Epic 1 Evidence References

Key evidence sources for ADR content:

1. **GO/NO-GO Decision**: `docs/notes/development/go-no-go-decision.md`
   - AC1.1-AC1.7: All 7 decision criteria with evidence
   - Pattern confidence assessment (7/7 HIGH)
   - Blocker assessment (0 critical, 0 major)

2. **Story 8.7 Audit Results**: `docs/notes/development/work-items/story-8.7-amdire-audit-results.md`
   - Lines 145-152: Missing ADR gaps identified
   - Lines 214-222: Recommended new ADRs

3. **Concepts Documentation** (existing, can reference):
   - `packages/docs/src/content/docs/concepts/dendritic-architecture.md`
   - `packages/docs/src/content/docs/concepts/clan-integration.md`

4. **ADR-0017** (structural reference): Already documents overlay patterns, supersedes ADR-0003

### Cross-Reference Strategy

ADRs should reference each other and concept docs:

```
ADR-0018 (Dendritic) ←→ ADR-0019 (Clan) ←→ ADR-0020 (Integration)
        ↓                      ↓                     ↓
   ADR-0017 (Overlays)    ADR-0011 (Secrets)   [Both concepts docs]
```

Recommended cross-reference patterns:
- ADR-0018 → ADR-0017 (overlay patterns are part of dendritic)
- ADR-0019 → ADR-0011 (clan vars complement sops-nix)
- ADR-0020 → ADR-0018 + ADR-0019 (integration of both)
- All ADRs → concepts/dendritic-architecture.md and/or concepts/clan-integration.md

### Content Guidelines

1. **Evidence-based**: Reference Epic 1 stories, GO/NO-GO decision, actual code patterns
2. **Not speculative**: Document what was decided and why, not hypotheticals
3. **Consistent terminology**: Use terms from glossary.md
4. **Appropriate depth**: ADR-0017 is ~400 lines; aim for 200-400 lines per ADR
5. **Date accuracy**: Use actual decision dates from Epic 1 (November 2024)

### ADR-0021 Optional Status

ADR-0021 (Terranix) is marked optional because:
- Epic 7 stories provide recent evidence (2025-12-01)
- terranix pattern less foundational than dendritic/clan
- Can be deferred if time-constrained
- If implemented, should reference Epic 7 stories (7.1, 7.2, 7.4)

## Estimated Effort

| Task | Effort | Notes |
|------|--------|-------|
| Task 1: Research | 1-2h | Reading source docs, gathering evidence |
| Task 2: ADR-0018 | 2-3h | Most complex, foundational decision |
| Task 3: ADR-0019 | 2-3h | Requires alternatives analysis |
| Task 4: ADR-0020 | 2-3h | Synthesis documentation |
| Task 5: ADR-0021 | 1-2h | Optional, simpler scope |
| Task 6: Index/Validation | 0.5-1h | Mechanical updates |
| **Total (Required)** | **8-12h** | ADRs 0018-0020 + index |
| **Total (With Optional)** | **9-14h** | All 4 ADRs + index |

## NFR Coverage

**NFR-8.12**: Architectural decision traceability
- All foundational decisions documented in ADR format
- Cross-references establish decision relationships
- Evidence traceability to Epic 1 validation

## Dependencies

**Prerequisites:**
- Story 8.11 complete (development docs accurate, provides context)
- ADR-0017 exists as template reference

**Blocks:**
- Story 8.9 (cross-reference validation can include these ADRs)

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-02 | Story drafted | SM workflow |

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

**2025-12-02 Task 1 Complete:**
- Read GO/NO-GO decision (1,482 lines) - extracted all AC1.1-AC1.7 evidence, pattern confidence data
- Reviewed ADR-0017 (399 lines) as structural template - adopted five-layer pattern format
- Reviewed ADR-0011 (117 lines) for sops-nix cross-reference context
- Read concepts/dendritic-architecture.md (343 lines) - confirms dendritic pattern documentation exists
- Read concepts/clan-integration.md (293 lines) - confirms clan documentation exists
- Read ADR index to understand current organization (4 sections, 17 ADRs)
- Key dates: Epic 1 GO decision 2025-11-20, Pattern validation Stories 1.1-1.13

### Completion Notes List

**2025-12-02 Story 8.12 Implementation Complete:**

ADRs created (all 4, including optional):
- ADR-0018: Dendritic Flake-Parts Architecture (285 lines)
- ADR-0019: Clan-Core Orchestration (280 lines)
- ADR-0020: Dendritic + Clan Integration (320 lines)
- ADR-0021: Terranix Infrastructure Provisioning (265 lines)

Total: ~1,150 lines of foundational ADR documentation

Validation results:
- `just docs-build`: PASSED (76 pages indexed)
- `just docs-linkcheck`: PASSED (all internal links valid)

Cross-references established:
- ADR-0018 ↔ ADR-0017 (overlay patterns), ADR-0019, ADR-0020
- ADR-0019 ↔ ADR-0011 (sops), ADR-0018, ADR-0020
- ADR-0020 ↔ ADR-0018, ADR-0019, ADR-0011, ADR-0017
- ADR-0021 ↔ ADR-0019
- All ADRs reference concepts/dendritic-architecture.md and/or concepts/clan-integration.md

Commits (6 atomic):
1. ADR-0018 dendritic flake-parts
2. ADR-0019 clan-core orchestration
3. ADR-0020 dendritic + clan integration
4. ADR-0021 terranix infrastructure
5. ADR index update with "Nix Fleet Architecture" section
6. Story file updates (this commit)

### File List

**Created:**
- packages/docs/src/content/docs/development/architecture/adrs/0018-dendritic-flake-parts-architecture.md
- packages/docs/src/content/docs/development/architecture/adrs/0019-clan-core-orchestration.md
- packages/docs/src/content/docs/development/architecture/adrs/0020-dendritic-clan-integration.md
- packages/docs/src/content/docs/development/architecture/adrs/0021-terranix-infrastructure-provisioning.md

**Modified:**
- packages/docs/src/content/docs/development/architecture/adrs/index.md
- docs/notes/development/sprint-status.yaml
- docs/notes/development/work-items/8-12-create-foundational-architecture-decision-records.md
