---
title: "Documentation coverage analysis"
---

## Session Context

**Date:** 2025-12-02

**Purpose:** Comprehensive audit of `packages/docs/src/content/docs/` structure to identify gaps between actual documentation and the dual Diataxis (user documentation) + AMDiRE (development documentation) framework requirements.

**Methodology:** Party Mode collaborative analysis with tracer bullet research design involving multiple agent perspectives examining the documentation structure from different angles.

**Outcome:** 22 research streams identified across 5 tiers, providing a structured approach to comprehensive documentation enhancement beyond the original Epic 8 scope.

## Documentation Framework Requirements

This repository employs a dual framework approach to documentation, combining user-facing documentation with development documentation:

### Diataxis Framework (User Documentation)

The Diataxis framework organizes user-facing documentation into four quadrants based on user needs:

- **tutorials/** - Learning-oriented lessons that guide new users through initial experiences with the system
- **guides/** - Task-oriented how-to documents that help users accomplish specific goals
- **concepts/** - Understanding-oriented explanations that help users develop mental models of the system
- **reference/** - Information-oriented API/CLI documentation providing technical specifications

### AMDiRE Framework (Development Documentation)

The AMDiRE framework structures development documentation to support the entire software development lifecycle:

- **development/context/** - Problem domain, stakeholders, objectives, and project background
- **development/requirements/** - Functional and non-functional requirements with traceability
- **development/architecture/** - Design decisions, ADRs, and architectural patterns
- **development/traceability/** - Test framework, validation approach, and requirement coverage
- **development/work-items/** - Implementation tracking including epics, stories, and tasks

## Actual Structure Analysis

Current state of `packages/docs/src/content/docs/` comprises 62 files organized into 17 directories:

```
packages/docs/src/content/docs/
├── about/
│   ├── contributing/ (7 files)
│   │   ├── documentation-style.md
│   │   ├── index.md
│   │   ├── commit-conventions.md
│   │   ├── code-standards.md
│   │   ├── pull-requests.md
│   │   ├── release-process.md
│   │   └── testing.md
│   └── credits.md
├── concepts/ (4 files)
│   ├── nix-config-architecture.md
│   ├── dendritic-architecture.md
│   ├── clan-integration.md
│   └── multi-user-patterns.md
├── development/
│   ├── architecture/
│   │   ├── adrs/ (17 files including index)
│   │   │   ├── index.md
│   │   │   ├── adr-0001-flake-parts-dendritic.md
│   │   │   ├── adr-0002-nixos-unified-foundation.md
│   │   │   ├── adr-0003-nix-darwin-support.md
│   │   │   ├── adr-0004-clan-orchestration.md
│   │   │   ├── adr-0005-sops-secrets.md
│   │   │   ├── adr-0006-zerotier-vpn.md
│   │   │   ├── adr-0007-home-manager-users.md
│   │   │   ├── adr-0008-overlay-aggregation.md
│   │   │   ├── adr-0009-containerization.md
│   │   │   ├── adr-0010-astro-starlight-docs.md
│   │   │   ├── adr-0011-secrets-workflow.md
│   │   │   ├── adr-0012-ci-philosophy.md
│   │   │   ├── adr-0013-multi-user-patterns.md
│   │   │   ├── adr-0014-terranix-iac.md
│   │   │   ├── adr-0015-cache-strategy.md
│   │   │   └── adr-0016-path-filtering.md
│   │   ├── index.md
│   │   └── nixpkgs-hotfixes.md
│   ├── context/ (6 files)
│   │   ├── index.md
│   │   ├── problem-domain.md
│   │   ├── stakeholders.md
│   │   ├── objectives.md
│   │   ├── constraints.md
│   │   └── assumptions.md
│   ├── operations/ (1 file)
│   │   └── troubleshooting-ci-cache.md
│   ├── requirements/ (7 files)
│   │   ├── index.md
│   │   ├── functional-requirements.md
│   │   ├── non-functional-requirements.md
│   │   ├── darwin-requirements.md
│   │   ├── nixos-requirements.md
│   │   ├── secrets-requirements.md
│   │   └── ci-requirements.md
│   ├── traceability/ (2 files)
│   │   ├── index.md
│   │   └── ci-cd-setup.md
│   └── work-items/ (index + empty subdirs)
│       ├── index.md
│       ├── epics/
│       ├── stories/
│       └── tasks/
├── guides/ (7 files)
│   ├── getting-started.md
│   ├── host-onboarding.md
│   ├── home-manager-onboarding.md
│   ├── adding-custom-packages.md
│   ├── secrets-management.md
│   ├── handling-broken-packages.md
│   └── mcp-servers-usage.md
├── reference/ (1 file)
│   └── repository-structure.md
└── tutorials/ (EMPTY - directory exists but contains no files)
```

## Structural Gap Analysis

| Directory | Expected Purpose | Actual State | Gap Severity | Description |
|-----------|-----------------|--------------|--------------|-------------|
| tutorials/ | Learning-oriented lessons for new users | EXISTS but EMPTY | CRITICAL | No tutorial content exists. New users lack guided learning paths for bootstrap, secrets, deployment, and contribution workflows. |
| reference/ | CLI/API documentation, command references | 1 file only | HIGH | Only repository-structure.md exists. Missing: justfile recipe reference, flake app reference, module options reference, CLI command reference. |
| development/operations/ | Runbooks, troubleshooting guides, operational procedures | 1 file only | HIGH | Only CI cache troubleshooting exists. Missing: deployment runbooks, rollback procedures, incident response, monitoring setup. |
| development/traceability/ | Test/validation documentation, requirement coverage | 2 files only | HIGH | Only index and ci-cd-setup exist. Missing: test harness documentation, test case enumeration, coverage reports, validation matrices. |
| development/work-items/ | Task tracking, epic/story documentation | Index only, empty subdirs | MEDIUM | Structure exists but epics/stories/tasks subdirectories are empty. Work items tracked externally in docs/notes/development/. |

## Research Stream Catalog

### Tier 1: User Journey Streams (7 streams)

These streams trace end-to-end user experiences from entry points to successful outcomes, identifying documentation gaps that block or frustrate users.

| ID | Name | Scope | Key Files |
|----|------|-------|-----------|
| R1 | Bootstrap-to-Activation Journey | New user zero-to-working system | Makefile, justfile, guides/getting-started.md, guides/host-onboarding.md, guides/home-manager-onboarding.md |
| R2 | Secrets Lifecycle Complete | All secrets operations (create, rotate, share, revoke) | guides/secrets-management.md, development/architecture/adrs/adr-0011-secrets-workflow.md, justfile (secrets/sops groups), scripts/sops/* |
| R3 | Darwin Deployment Pipeline | macOS host full lifecycle (add, configure, update, remove) | guides/host-onboarding.md, concepts/clan-integration.md, justfile (clan/darwin groups), development/requirements/darwin-requirements.md |
| R4 | NixOS/Cloud Deployment Pipeline | Server deployment lifecycle (provision, configure, monitor, teardown) | guides/host-onboarding.md, concepts/clan-integration.md, justfile (clan/nixos groups), terranix configs, development/requirements/nixos-requirements.md |
| R5 | CI/CD Validation Flow | CI understanding, local reproduction, debugging | development/traceability/ci-cd-setup.md, development/architecture/adrs/adr-0012-ci-philosophy.md, development/operations/troubleshooting-ci-cache.md, .github/workflows/ci.yaml, development/architecture/adrs/adr-0015-cache-strategy.md, adr-0016-path-filtering.md |
| R6 | Module Architecture Patterns | Technical understanding of config patterns | concepts/nix-config-architecture.md, concepts/dendritic-architecture.md, concepts/clan-integration.md, concepts/multi-user-patterns.md |
| R7 | Developer Contribution Path | Contributor onboarding to first PR | guides/adding-custom-packages.md, guides/handling-broken-packages.md, about/contributing/* (7 files), about/contributing/commit-conventions.md |

### Tier 2: Diataxis Structure Streams (3 streams)

These streams focus on completing the Diataxis framework structure, ensuring each quadrant has appropriate coverage.

| ID | Name | Scope | Key Files |
|----|------|-------|-----------|
| R8 | Tutorials Structure Design | Define missing tutorials, create learning paths | Empty tutorials/ directory, proposed learning paths from user journeys (R1-R7) |
| R9 | Reference Documentation Gaps | Identify and document missing reference content | reference/repository-structure.md, justfile (all groups), flake.nix apps, module options |
| R10 | Guides Completeness Audit | Ensure all guides are coherent and cross-linked | All guides/*.md (7 files), cross-reference validation, task completion verification |

### Tier 3: AMDiRE Development Docs Streams (5 streams)

These streams audit AMDiRE framework completeness, ensuring development documentation supports the entire project lifecycle.

| ID | Name | Scope | Key Files |
|----|------|-------|-----------|
| R11 | Context Documentation Audit | Problem domain coherence and completeness | development/context/*.md (6 files: index, problem-domain, stakeholders, objectives, constraints, assumptions) |
| R12 | Requirements Documentation Audit | Requirements traceability and coverage | development/requirements/*.md (7 files: index, functional, non-functional, darwin, nixos, secrets, ci) |
| R13 | ADR Comprehensive Audit | All 16 ADRs current, linked, and traceable | development/architecture/adrs/*.md (17 files including index), cross-references to requirements and code |
| R14 | Operations Runbook Assessment | Operational documentation gaps | development/operations/*.md (1 file: troubleshooting-ci-cache), proposed additions (deployment, rollback, monitoring, incident response) |
| R15 | Traceability Enhancement | Testing/validation documentation | development/traceability/*.md (2 files: index, ci-cd-setup), gaps in test harness docs, test enumeration, coverage reports |

### Tier 4: Code-Documentation Alignment Streams (4 streams)

These streams ensure bidirectional coherence between code artifacts and documentation.

| ID | Name | Scope | Key Files |
|----|------|-------|-----------|
| R16 | Justfile-Docs Alignment | Recipe documentation, discoverability, examples | justfile (all recipe groups: nix, clan, docs, containers, secrets, sops, CI/CD, home-manager, darwin, nixos) ↔ guides/reference |
| R17 | Flake Apps-Docs Alignment | Flake app documentation and usage examples | flake.nix apps (CLI tools, utilities) ↔ guides/reference |
| R18 | CI Jobs-Docs Alignment | CI job documentation and troubleshooting | .github/workflows/ci.yaml jobs ↔ development/traceability/ci-cd-setup.md, development/operations/troubleshooting-ci-cache.md |
| R19 | Module Options-Docs Alignment | Configuration options documentation | modules/**/*.nix (all module options) ↔ reference documentation, module option reference |

### Tier 5: Cross-Cutting Concerns (3 streams)

These streams address system-wide documentation quality concerns.

| ID | Name | Scope | Key Files |
|----|------|-------|-----------|
| R20 | Cross-Reference Integrity | All links valid and bidirectional | All index.md files, all internal links, backlink analysis |
| R21 | Discoverability and Navigation | Findability assessment across entry points | Homepage (packages/docs/src/content/docs/index.mdx), sidebar configuration, error messages, justfile --list output |
| R22 | Test Harness Documentation | CI to local parity for testing | CI jobs (.github/workflows/ci.yaml), justfile test recipes, about/contributing/testing.md, local test reproduction |

## File Coverage Matrix

This matrix shows which research stream(s) provide coverage for each existing documentation file:

| File/Directory | Stream Coverage | Notes |
|----------------|-----------------|-------|
| tutorials/ (empty) | R8 | CRITICAL gap - entire directory empty |
| guides/getting-started.md | R1, R10 | Entry point for bootstrap journey |
| guides/host-onboarding.md | R1, R3, R4, R10 | Covers both darwin and nixos onboarding |
| guides/home-manager-onboarding.md | R1, R10 | User configuration onboarding |
| guides/adding-custom-packages.md | R7, R10 | Contributor workflow |
| guides/secrets-management.md | R2, R10 | Secrets lifecycle documentation |
| guides/handling-broken-packages.md | R7, R10 | Nixpkgs hotfixes and overlays |
| guides/mcp-servers-usage.md | R10 | MCP integration guide |
| concepts/nix-config-architecture.md | R6 | Core architecture patterns |
| concepts/dendritic-architecture.md | R6 | Dendritic flake-parts pattern |
| concepts/clan-integration.md | R3, R4, R6 | Clan orchestration concepts |
| concepts/multi-user-patterns.md | R6 | Multi-user configuration patterns |
| reference/repository-structure.md | R9 | Only reference doc - needs expansion |
| about/contributing/*.md (7 files) | R7, R22 | Contribution workflow and standards |
| about/credits.md | R20 | Cross-reference to contributors |
| development/context/*.md (6 files) | R11 | AMDiRE context documentation |
| development/requirements/*.md (7 files) | R12 | AMDiRE requirements documentation |
| development/architecture/adrs/*.md (17 files) | R13 | Architecture decision records |
| development/architecture/nixpkgs-hotfixes.md | R7, R13 | Overlay architecture |
| development/operations/*.md (1 file) | R5, R14 | Operations and troubleshooting |
| development/traceability/*.md (2 files) | R5, R15, R22 | Testing and validation docs |
| development/work-items/*.md | R20 | Work item tracking structure |

## Justfile Group Mapping

Analysis of justfile recipe groups and their documentation coverage:

| Justfile Group | Recipe Count (approx) | Research Stream | Documentation Status | Gaps |
|----------------|----------------------|-----------------|---------------------|------|
| nix | ~15 | R1, R16 | Partial | No reference docs for build/eval/update recipes |
| clan | ~12 | R3, R4, R16 | Partial | Deployment runbooks missing |
| docs | ~15 | R7, R16 | Partial | Local development setup incomplete |
| containers | ~7 | R7, R16 | Minimal | Container workflow undocumented |
| secrets | ~10 | R2, R16 | Good | Well-documented in guides/secrets-management.md |
| sops | ~10 | R2, R16 | Good | Covered by secrets documentation |
| CI/CD | ~20 | R5, R18, R22 | Partial | Local test reproduction needs docs |
| nix-home-manager | ~4 | R1, R16 | Minimal | User onboarding needs expansion |
| nix-darwin | ~4 | R3, R16 | Minimal | Darwin deployment needs runbooks |
| nixos | ~5 | R4, R16 | Minimal | NixOS deployment needs runbooks |

## Research Stream Output Schema

Each research stream investigation should produce the following artifacts:

### 1. Coverage Assessment

**Diataxis Quadrants:**
- Tutorial coverage: What learning-oriented content exists or is needed?
- Guide coverage: What task-oriented how-to content exists or is needed?
- Concept coverage: What understanding-oriented explanations exist or are needed?
- Reference coverage: What information-oriented specifications exist or are needed?

**AMDiRE Framework:**
- Context coverage: Problem domain, stakeholders, objectives documented?
- Requirements coverage: Functional/non-functional requirements traceable?
- Architecture coverage: Design decisions and ADRs current?
- Traceability coverage: Tests, validation, and requirement mapping complete?

### 2. Prerequisite Chain Analysis

Ordered dependency analysis:
- Identify prerequisite knowledge/setup required for this stream's topic
- Document which prerequisites have documentation (and where)
- Document which prerequisites lack documentation (gap severity)
- Create ordered learning path showing documentation dependencies

### 3. Gap Inventory

Structured gap documentation:

| Gap ID | Type | Severity | Description | Proposed Fix | Estimated Effort |
|--------|------|----------|-------------|--------------|------------------|
| R1-G1 | Tutorial | Critical | No bootstrap tutorial | Create tutorials/bootstrap.md | High |
| R2-G1 | Reference | High | Missing sops CLI reference | Add reference/sops-cli.md | Medium |

**Gap Types:** Tutorial, Guide, Concept, Reference, Context, Requirements, Architecture, Traceability, Operations

**Severity Levels:** Critical (blocks users), High (significant friction), Medium (minor friction), Low (nice-to-have)

### 4. Tool Documentation Alignment

For each tool/recipe/app in scope:

| Tool/Recipe | Documented | Discoverable | Examples | Ergonomic | Gaps |
|-------------|-----------|--------------|----------|-----------|------|
| just secrets-init | Yes (guides/secrets-management.md) | Yes (justfile --list) | Yes | Yes | None |
| just clan-darwin-build | Partial | Yes | No | No | Needs deployment runbook with examples |

### 5. Cross-Reference Audit

Document missing bidirectional links:

| Source Document | Missing Link To | Impact | Priority |
|-----------------|-----------------|--------|----------|
| guides/getting-started.md | tutorials/bootstrap.md | New users lack guided path | High |
| concepts/clan-integration.md | development/architecture/adrs/adr-0004-clan-orchestration.md | Missing architecture decision context | Medium |

### 6. Discoverability Assessment

Evaluate how users find this content:

- **Homepage path:** Is there a clear path from homepage to this content?
- **Contextual links:** Are there links from related content?
- **Error guidance:** Do error messages point to relevant docs?
- **Justfile hints:** Do recipe descriptions guide users to docs?
- **Search keywords:** Will users find this via search?

## Recommended Next Steps

### 1. Complete Epic 8 Retrospective

Epic 8 "Documentation Alignment" has stories 8.1-8.4 marked DONE but lacks final retrospective.
Complete retrospective before deciding on Epic 8 extension vs Epic 9 creation.

### 2. Scope Decision: Epic 8 Extension vs Epic 9

**Option A: Extend Epic 8 with Stories 8.5+**
- Pros: Maintains continuity, acknowledges documentation work is ongoing
- Cons: Extends already-large epic, may dilute original scope focus
- Recommendation: Use if research streams are incremental improvements to existing docs

**Option B: Create Epic 9 for Documentation Completeness**
- Pros: Clear scope boundary between "alignment" (Epic 8) and "completeness" (Epic 9)
- Cons: Requires new epic planning overhead
- Recommendation: Use if research streams reveal significant new work (tutorials, reference, operations)

**Suggested Decision Criteria:**
- If gaps are primarily in existing document categories → Epic 8 extension
- If gaps require new document categories (tutorials, reference) → Epic 9

### 3. Prioritize Research Streams by Impact

**Critical Priority (blocks users):**
- R1: Bootstrap-to-Activation Journey - new users cannot get started effectively
- R2: Secrets Lifecycle Complete - secrets workflow has gaps causing friction
- R3: Darwin Deployment Pipeline - macOS deployment lacks complete runbooks
- R8: Tutorials Structure Design - entire tutorials/ directory empty

**High Priority (significant friction):**
- R4: NixOS/Cloud Deployment Pipeline - server deployment needs runbooks
- R9: Reference Documentation Gaps - missing CLI/API reference content
- R11: Context Documentation Audit - validate AMDiRE context completeness
- R12: Requirements Documentation Audit - ensure requirements traceability

**Medium Priority (minor friction):**
- R5: CI/CD Validation Flow - CI docs exist but need enhancement
- R6: Module Architecture Patterns - concepts exist but cross-linking needed
- R13: ADR Comprehensive Audit - ADRs exist, validate currency
- R14: Operations Runbook Assessment - expand beyond CI troubleshooting
- R15: Traceability Enhancement - test harness documentation needed

**Low Priority (quality improvements):**
- R7: Developer Contribution Path - contribution docs exist, validate completeness
- R10: Guides Completeness Audit - guides exist, ensure coherence
- R16-R19: Code-Documentation Alignment - validate bidirectional coherence
- R20-R22: Cross-Cutting Concerns - system-wide quality improvements

### 4. Dispatch Parallel Research Subagents

For high-impact streams, construct detailed research prompts:

**Example Prompt Template:**

```
# Research Stream: [Stream ID and Name]

## Objective
[One-sentence objective from stream scope]

## Scope
Files: [List of key files from stream catalog]
Code: [List of justfile groups, flake apps, or modules relevant to stream]

## Required Outputs
1. Coverage Assessment (Diataxis + AMDiRE)
2. Prerequisite Chain Analysis
3. Gap Inventory (table format)
4. Tool Documentation Alignment (table format)
5. Cross-Reference Audit (table format)
6. Discoverability Assessment

## Success Criteria
- All gaps identified with severity and proposed fix
- Clear prerequisite learning path documented
- Bidirectional cross-references validated
- Actionable recommendations with effort estimates

## Constraints
- Focus on user impact, not theoretical completeness
- Prioritize critical gaps blocking user success
- Provide specific file paths and line numbers where relevant
```

### 5. Integrate Findings into Documentation Improvement Plan

After research streams complete:
1. Consolidate gap inventories across all streams
2. Identify overlapping gaps addressed by multiple streams
3. Deduplicate and prioritize consolidated gap list
4. Create epic/story breakdown for documentation improvement work
5. Estimate effort and sequence work based on dependencies

## Relationship to Epic 8

**Original Epic 8 Scope:** "Documentation Alignment" - aligning existing documentation to actual code implementation, ensuring docs accurately reflect system behavior.

**Stories 8.1-8.4 Status:** DONE
- 8.1: Documentation audit and gap analysis
- 8.2: Architecture documentation updates
- 8.3: User onboarding guide improvements
- 8.4: Secrets management documentation

**This Analysis Reveals:** Documentation **COMPLETENESS** gaps beyond alignment scope.
Epic 8 focused on making existing docs accurate; this analysis reveals entire missing documentation categories (tutorials/, reference/, operations runbooks).

**Decision Needed:**
- **Extend Epic 8** with Stories 8.5+ for incremental improvements?
- **Create Epic 9** for documentation completeness as new scope?

**Recommendation:** Complete Epic 8 retrospective first, then decide based on:
- If gaps are refinements of Epic 8 topics → extend Epic 8
- If gaps are new categories requiring tutorials/reference/operations → create Epic 9

The 22 research streams identified represent comprehensive documentation enhancement beyond original Epic 8 scope, suggesting Epic 9 may be more appropriate to maintain clear scope boundaries between "alignment" (Epic 8) and "completeness" (Epic 9).
