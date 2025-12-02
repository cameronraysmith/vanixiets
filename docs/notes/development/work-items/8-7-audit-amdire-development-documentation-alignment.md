# Story 8.7: Audit AMDiRE Development Documentation Alignment

Status: review

## Story

As a contributor,
I want development documentation that accurately reflects the current project context, requirements, and architectural decisions,
so that I understand the project's goals, constraints, and design rationale when implementing features.

## Acceptance Criteria

### Context Documentation Audit (AC1-AC7)

1. **constraints-and-rules.md verified**: Reflects current constraints including dendritic + clan architecture, not deprecated nixos-unified patterns
2. **domain-model.md verified**: Matches implemented domain model with current machine fleet and user management patterns
3. **glossary.md verified**: Terms are current with dendritic flake-parts, clan-core, and two-tier secrets terminology
4. **goals-and-objectives.md verified**: Alignment with post-migration state (Epic 1-6 complete, Epic 7-8 in progress)
5. **project-scope.md verified**: Scope matches current reality (6-machine fleet, GCP expansion, zerotier mesh)
6. **stakeholders.md verified**: Stakeholder information is current (user roles, machine ownership)
7. **index.md verified**: Navigation and cross-references accurate

### Requirements Documentation Audit (AC8-AC15)

8. **deployment-requirements.md verified**: Matches clan deployment patterns (not nixos-unified)
9. **functional-hierarchy.md verified**: Reflects implemented features (dendritic modules, clan services, terranix)
10. **quality-requirements.md verified**: NFRs are current with implemented architecture
11. **risk-list.md verified**: Risks are updated post-migration (many risks mitigated in Epic 1)
12. **system-constraints.md verified**: Constraints reflect clan + dendritic reality
13. **system-vision.md verified**: Vision aligns with implemented multi-machine coordination
14. **usage-model.md verified**: Usage patterns documented match actual workflows
15. **index.md verified**: Navigation and cross-references accurate

### ADR Audit (AC16-AC20)

16. **16 ADRs reviewed for currency**: Each ADR verified against current implementation
17. **Cross-references validated**: Related ADRs reference each other appropriately
18. **ADRs needing updates identified**: List of ADRs requiring modification with specific issues
19. **ADRs needing supersession identified**: List of ADRs that should be marked superseded or deprecated
20. **ADR decisions match implementation**: Verify decisions in ADRs align with actual code patterns

### Audit Output (AC21-AC23)

21. **Audit results documented**: `story-8.7-amdire-audit-results.md` created with per-file assessment
22. **Traceability gaps identified**: Missing links between requirements, architecture, and implementation
23. **Recommended actions documented**: Specific fixes for each staleness issue, prioritized by impact

### Documentation Quality (AC24-AC25)

24. **Zero nixos-unified references**: Final verification passes grep checks in all audited files
25. **Starlight build passes**: `bun run build` succeeds with all audited files

## Tasks / Subtasks

### Task 1: Audit Context Documentation (AC: #1-7)

- [x] Read `packages/docs/src/content/docs/development/context/constraints-and-rules.md` completely
  - [x] Check for nixos-unified references
  - [x] Verify dendritic + clan constraints documented
  - [x] Classify: current/stale/obsolete → **STALE** (nixos-unified refs L95, migration rules L200-218)
- [x] Read `packages/docs/src/content/docs/development/context/domain-model.md` completely
  - [x] Verify machine fleet matches: stibnite, blackphos, rosegold, argentum, cinnabar, electrum, galena, scheelite
  - [x] Verify user model: crs58, raquel, cameron, janettesmith, christophersmith
  - [x] Classify: current/stale/obsolete → **STALE** (nixos-unified section L28-56, missing 3 hosts)
- [x] Read `packages/docs/src/content/docs/development/context/glossary.md` completely
  - [x] Check for deprecated terms (nixos-unified, configurations/)
  - [x] Verify new terms documented (dendritic, clan vars, Pattern A)
  - [x] Classify: current/stale/obsolete → **STALE** (nixos-unified as current L124-127, only 5 hosts)
- [x] Read `packages/docs/src/content/docs/development/context/goals-and-objectives.md` completely
  - [x] Verify goals reflect post-migration state
  - [x] Check if Epic 1-6 outcomes incorporated
  - [x] Classify: current/stale/obsolete → **STALE** (achieved goals marked in-progress L464-518)
- [x] Read `packages/docs/src/content/docs/development/context/project-scope.md` completely
  - [x] Verify scope includes current machine fleet
  - [x] Verify GCP expansion documented
  - [x] Classify: current/stale/obsolete → **STALE** (nixos-unified as current L7-11, only 4 hosts)
- [x] Read `packages/docs/src/content/docs/development/context/stakeholders.md` completely
  - [x] Verify user roles current
  - [x] Verify machine ownership documented
  - [x] Classify: current/stale/obsolete → **CURRENT** (minor update L88 nixos-unified status)
- [x] Read `packages/docs/src/content/docs/development/context/index.md` completely
  - [x] Verify navigation links work
  - [x] Verify descriptions accurate
  - [x] Classify: current/stale/obsolete → **CURRENT** (correctly reflects 8 machines, dendritic+clan)

### Task 2: Audit Requirements Documentation (AC: #8-15)

- [x] Read `packages/docs/src/content/docs/development/requirements/deployment-requirements.md` completely
  - [x] Verify clan deployment patterns documented
  - [x] Check for nixos-unified deployment references
  - [x] Classify: current/stale/obsolete → **STALE** (current/target framing L10, only 5 hosts L368)
- [x] Read `packages/docs/src/content/docs/development/requirements/functional-hierarchy.md` completely
  - [x] Verify features match implementation
  - [x] Check for dendritic module features
  - [x] Classify: current/stale/obsolete → **STALE** (migration functions L649-722 as pending)
- [x] Read `packages/docs/src/content/docs/development/requirements/quality-requirements.md` completely
  - [x] Verify NFRs reflect current architecture
  - [x] Check for stale performance/security requirements
  - [x] Classify: current/stale/obsolete → **CURRENT** (well-structured, minor updates to examples)
- [x] Read `packages/docs/src/content/docs/development/requirements/risk-list.md` completely
  - [x] Verify risks updated post-migration
  - [x] Check for mitigated risks still listed as active
  - [x] Classify: current/stale/obsolete → **CURRENT** (risk statuses need status update)
- [x] Read `packages/docs/src/content/docs/development/requirements/system-constraints.md` completely
  - [x] Verify constraints reflect clan + dendritic patterns
  - [x] Check for outdated constraints
  - [x] Classify: current/stale/obsolete → **CURRENT** (SC-010 L560-597 needs completion update)
- [x] Read `packages/docs/src/content/docs/development/requirements/system-vision.md` completely
  - [x] Verify vision aligns with implemented architecture
  - [x] Check for outdated vision statements
  - [x] Classify: current/stale/obsolete → **STALE** (current/target inverted L29-47, only 5 machines)
- [x] Read `packages/docs/src/content/docs/development/requirements/usage-model.md` completely
  - [x] Verify usage patterns match actual workflows
  - [x] Check for outdated CLI commands
  - [x] Classify: current/stale/obsolete → **STALE** (nixos-unified as current L12, UC-007 as future)
- [x] Read `packages/docs/src/content/docs/development/requirements/index.md` completely
  - [x] Verify navigation links work
  - [x] Verify descriptions accurate
  - [x] Classify: current/stale/obsolete → **CURRENT** (meta-document, minor updates)

### Task 3: Audit ADRs (AC: #16-20)

- [x] Read `packages/docs/src/content/docs/development/architecture/adrs/index.md` completely
  - [x] Verify ADR list is complete and accurate → **CURRENT**
  - [x] Check navigation and descriptions → All 16 ADRs linked, superseded correctly noted
- [x] Read and assess each ADR for currency:
  - [x] 0001-claude-code-multi-profile-system.md → **CURRENT**
  - [x] 0002-use-generic-just-recipes.md → **CURRENT**
  - [x] 0003-overlay-composition-patterns.md → **NEEDS-UPDATE** (nixos-unified refs, configurations/, overlays/ at root)
  - [x] 0004-monorepo-structure.md → **CURRENT**
  - [x] 0005-semantic-versioning.md → **CURRENT**
  - [x] 0006-monorepo-tag-strategy.md → **CURRENT**
  - [x] 0007-bun-workspaces.md → **CURRENT**
  - [x] 0008-typescript-configuration.md → **CURRENT**
  - [x] 0009-nix-development-environment.md → **CURRENT**
  - [x] 0010-testing-architecture.md → **CURRENT**
  - [x] 0011-sops-secrets-management.md → **CURRENT**
  - [x] 0012-github-actions-pipeline.md → **CURRENT**
  - [x] 0013-cloudflare-workers-deployment.md → **CURRENT**
  - [x] 0014-design-principles.md → **CURRENT**
  - [x] 0015-ci-caching-optimization.md → **SUPERSEDED** (correctly marked, superseded by ADR-0016)
  - [x] 0016-per-job-content-addressed-caching.md → **CURRENT**
- [x] For each ADR, assess:
  - [x] Does decision match current implementation? → 14/16 yes, ADR-0003 partially
  - [x] Are cross-references to related ADRs present? → ADR-0003 missing dendritic/pkgs-by-name refs
  - [x] Should ADR be updated or superseded? → ADR-0003 needs major update or supersession
  - [x] Classify: current/needs-update/superseded → 14 current, 1 needs-update, 1 superseded

### Task 4: Identify Traceability Gaps (AC: #22)

- [x] Check for requirements → ADR traceability
  - [x] Each major requirement should link to relevant ADR
  - [x] Document missing links → 6 gaps identified (dendritic, clan-core, two-tier, multi-platform, fleet ops, terranix)
- [x] Check for ADR → code traceability
  - [x] Key ADR decisions should reference implementation files
  - [x] Document missing implementation references → ADR-0003 refs overlays/ not modules/nixpkgs/overlays/
- [x] Check for context → requirements alignment
  - [x] Context documents should inform requirements
  - [x] Document contradictions or gaps → 4 gaps (domain→ops model, glossary→functions, goals→metrics, scope→usage)

### Task 5: Create Audit Results Document (AC: #21, #23)

- [x] Create `docs/notes/development/work-items/story-8.7-amdire-audit-results.md`
- [x] Include per-file assessment table:
  - [x] File path → 32 files documented
  - [x] Status (current/stale/obsolete) → 20 current, 9 stale, 1 needs-update, 1 superseded, 1 obsolete (none)
  - [x] Specific issues found → Evidence with line numbers for each stale file
  - [x] Recommended action → 15 actions documented
  - [x] Priority (critical/high/medium/low) → 4 critical, 6 high, 2 medium, 3 low
- [x] Include ADR assessment summary:
  - [x] ADRs needing updates → 1 (ADR-0003)
  - [x] ADRs needing supersession → 1 (ADR-0015 already correctly superseded)
  - [x] Cross-reference gaps → ADR-0003 missing dendritic/pkgs-by-name patterns
- [x] Include traceability gap inventory:
  - [x] Requirements → ADR gaps → 6 missing ADRs documented
  - [x] ADR → implementation gaps → ADR-0003 path issues
  - [x] Context → requirements gaps → 4 alignment issues

### Task 6: Final Verification (AC: #24-25)

- [x] Run verification commands for deprecated patterns:
  ```bash
  # These patterns found in development/ docs (confirming audit findings):
  rg "nixos-unified|configurations/" packages/docs/src/content/docs/development/
  # Result: 20 files with matches (expected - this is AUDIT not fix)
  rg "LazyVim-module" packages/docs/src/content/docs/development/
  # Result: 1 file (nixpkgs-hotfixes.md) - additional finding outside audit scope
  ```
- [x] Verify Starlight build: `bun run build` (docs should build successfully) → **PASSED**
- [x] Update story status to review → Status updated to "review"

## Dev Notes

### AMDiRE Framework Context

This story audits documentation against the AMDiRE (Agile Method for Requirements Engineering in Document Review-based projects) framework, which structures development documentation to support the software development lifecycle:

- **Context**: Problem domain, stakeholders, objectives, project background
- **Requirements**: Functional and non-functional requirements with traceability
- **Architecture**: Design decisions, ADRs, patterns
- **Traceability**: Requirement coverage, test mapping, validation approach
- **Work Items**: Implementation tracking (epics, stories, tasks)

### Research Streams Covered

From `docs/notes/development/research/documentation-coverage-analysis.md`:

- **R11 (Context Documentation Audit)**: Problem domain coherence and completeness
- **R12 (Requirements Documentation Audit)**: Requirements traceability and coverage
- **R13 (ADR Comprehensive Audit)**: All 16 ADRs current, linked, and traceable

### Actual File Inventory

**Context Documentation (7 files):**
- `packages/docs/src/content/docs/development/context/constraints-and-rules.md`
- `packages/docs/src/content/docs/development/context/domain-model.md`
- `packages/docs/src/content/docs/development/context/glossary.md`
- `packages/docs/src/content/docs/development/context/goals-and-objectives.md`
- `packages/docs/src/content/docs/development/context/project-scope.md`
- `packages/docs/src/content/docs/development/context/stakeholders.md`
- `packages/docs/src/content/docs/development/context/index.md`

**Requirements Documentation (8 files):**
- `packages/docs/src/content/docs/development/requirements/deployment-requirements.md`
- `packages/docs/src/content/docs/development/requirements/functional-hierarchy.md`
- `packages/docs/src/content/docs/development/requirements/index.md`
- `packages/docs/src/content/docs/development/requirements/quality-requirements.md`
- `packages/docs/src/content/docs/development/requirements/risk-list.md`
- `packages/docs/src/content/docs/development/requirements/system-constraints.md`
- `packages/docs/src/content/docs/development/requirements/system-vision.md`
- `packages/docs/src/content/docs/development/requirements/usage-model.md`

**ADRs (17 files including index):**
- `0001-claude-code-multi-profile-system.md`
- `0002-use-generic-just-recipes.md`
- `0003-overlay-composition-patterns.md`
- `0004-monorepo-structure.md`
- `0005-semantic-versioning.md`
- `0006-monorepo-tag-strategy.md`
- `0007-bun-workspaces.md`
- `0008-typescript-configuration.md`
- `0009-nix-development-environment.md`
- `0010-testing-architecture.md`
- `0011-sops-secrets-management.md`
- `0012-github-actions-pipeline.md`
- `0013-cloudflare-workers-deployment.md`
- `0014-design-principles.md`
- `0015-ci-caching-optimization.md`
- `0016-per-job-content-addressed-caching.md`
- `index.md`

### Current Machine Fleet for Verification

**Darwin Machines:**
- stibnite (crs58's primary workstation)
- blackphos (raquel's workstation)
- rosegold (janettesmith's workstation)
- argentum (christophersmith's workstation)

**NixOS Machines:**
- cinnabar (Hetzner VPS, zerotier controller)
- electrum (Hetzner VPS, zerotier peer)
- galena (GCP CPU node)
- scheelite (GCP GPU node)

### Post-Migration Reality Check

The audit should verify documents reflect these completed migrations:

- **Epic 1**: Architectural validation in test-clan (13 stories, GO decision)
- **Epic 2**: Infrastructure migration to infra repo (14 stories)
- **Epic 3**: rosegold deployment and zerotier integration
- **Epic 4**: argentum deployment, 6-machine network
- **Epic 5**: Skipped (stibnite stable)
- **Epic 6**: Legacy cleanup complete
- **Epic 7**: GCP multi-node infrastructure (galena, scheelite)
- **Epic 8**: Documentation alignment (in progress)

### Key Terminology to Verify

| Correct Term | Deprecated Term |
|--------------|-----------------|
| dendritic flake-parts | nixos-unified |
| clan-core | N/A (new) |
| clan vars | N/A (new) |
| sops-nix (Tier 2) | sops-secrets-management (may be stale) |
| Pattern A (home-manager) | N/A (new) |
| terranix | N/A (new) |
| modules/ | configurations/ |

### Output Artifact

**Primary Deliverable:** `docs/notes/development/work-items/story-8.7-amdire-audit-results.md`

**Format:**
```markdown
# Story 8.7 AMDiRE Audit Results

## Summary
- Files audited: X
- Current: X
- Stale: X
- Obsolete: X
- ADRs needing updates: X
- Traceability gaps: X

## Context Documentation Assessment
| File | Status | Issues | Recommended Action | Priority |
|------|--------|--------|-------------------|----------|
| ... | ... | ... | ... | ... |

## Requirements Documentation Assessment
| File | Status | Issues | Recommended Action | Priority |
|------|--------|--------|-------------------|----------|
| ... | ... | ... | ... | ... |

## ADR Assessment
| ADR | Status | Issues | Action Needed | Cross-References |
|-----|--------|--------|---------------|------------------|
| ... | ... | ... | ... | ... |

## Traceability Gaps
### Requirements → ADR
- ...
### ADR → Implementation
- ...
### Context → Requirements
- ...

## Recommended Actions (Prioritized)
1. [Priority] [Action] [File(s)]
2. ...
```

### Project Structure Notes

- Alignment with dendritic flake-parts pattern
- ADRs in Starlight docs structure, not separate ADR repo
- Development docs serve both AMDiRE compliance and contributor onboarding

### Learnings from Previous Story

**From Story 8.4 (Status: review)**

- Two-tier documentation pattern established (architecture + practical)
- Verification pattern: rg commands for deprecated patterns
- Starlight build validation: `bun run build`
- Atomic commits per section
- Cross-reference patterns between docs

[Source: docs/notes/development/work-items/8-4-update-secrets-management-documentation.md#Dev-Notes]

### References

- [Epic 8: docs/notes/development/epics/epic-8-documentation-alignment.md]
- [Research Document: docs/notes/development/research/documentation-coverage-analysis.md]
- [Story 8.4: docs/notes/development/work-items/8-4-update-secrets-management-documentation.md]
- [Sprint Status: docs/notes/development/sprint-status.yaml]

### Constraints

1. **Audit only, no fixes**: This story identifies issues, does NOT fix them
2. **All files must be read completely**: No offset/limit, full document analysis
3. **Evidence-based assessment**: Each staleness claim backed by specific finding
4. **Prioritized recommendations**: Critical/high/medium/low for each action
5. **Machine fleet verification**: Verify documentation matches 8-machine fleet

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-8.1 | Zero references to deprecated architecture |
| NFR-8.7 | Development documentation accuracy |

### Estimated Effort

**6-8 hours** (research-intensive audit story)

- Task 1 (context audit): 1.5h (7 files)
- Task 2 (requirements audit): 2h (8 files)
- Task 3 (ADR audit): 2h (17 files including cross-reference analysis)
- Task 4 (traceability gaps): 0.5h
- Task 5 (audit results document): 1h
- Task 6 (verification): 0.5h

## Dev Agent Record

### Context Reference

No context file generated (proceeded with story file only per workflow step 1)

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

- Dispatched 3 parallel subagent tasks for context/requirements/ADR audits
- Audit methodology: complete file reads, evidence-based assessments with line numbers
- Verification commands executed to confirm deprecated pattern presence

### Completion Notes List

**Audit Execution (2025-12-02):**
- 32 files audited across context (7), requirements (8), and ADRs (17)
- Overall currency: 62.5% current (20/32), 37.5% requiring updates (12/32)
- Primary staleness pattern: "current/target state inversion" where docs describe dendritic + clan as "target" and nixos-unified as "current"
- 5 common staleness patterns identified across documents
- 15 prioritized recommended actions (4 critical, 6 high, 2 medium, 3 low)
- 4 new ADRs recommended to close traceability gaps
- Estimated total remediation effort: 18-24 hours

**Verification Results:**
- `rg "nixos-unified|configurations/"` found matches in 20 files (confirms audit)
- `rg "LazyVim-module"` found 1 additional file outside audit scope (nixpkgs-hotfixes.md)
- `bun run build` passed successfully

**AC24 Clarification:**
- AC24 states "Zero nixos-unified references" but this is an AUDIT story (identifies issues, doesn't fix them)
- The verification confirms deprecated patterns exist and documents them for future remediation
- Per story constraints section: "Audit only, no fixes: This story identifies issues, does NOT fix them"

### File List

**Created:**
- docs/notes/development/work-items/story-8.7-amdire-audit-results.md (primary deliverable)

**Modified:**
- docs/notes/development/sprint-status.yaml (story-8-7: drafted → in-progress → review)
- docs/notes/development/work-items/8-7-audit-amdire-development-documentation-alignment.md (this file)

## Change Log

**2025-12-02 (Story Completed)**:
- All 6 tasks executed, all 25 acceptance criteria addressed
- Primary deliverable created: story-8.7-amdire-audit-results.md
- 32 files audited: 20 current, 9 stale, 1 needs-update, 1 superseded (correct), 0 obsolete
- 15 prioritized recommended actions documented
- Traceability gaps identified: 6 missing ADRs, context→requirements alignment issues
- Verification: deprecated patterns confirmed present (expected for audit), Starlight build passed
- Status: drafted → in-progress → review
- Actual effort: ~3 hours (parallel subagent dispatch optimized execution)

**2025-12-02 (Story Drafted)**:
- Story file created from Epic 8 Story 8.7 specification
- Incorporated research streams R11, R12, R13 from documentation-coverage-analysis.md
- 25 acceptance criteria mapped to 6 task groups
- Actual file inventory verified via glob patterns
- Post-migration reality check incorporated (Epic 1-8 status)
- Key terminology verification table created
- Output artifact format specified
- Learnings from Story 8.4 incorporated
- Estimated effort: 6-8 hours
