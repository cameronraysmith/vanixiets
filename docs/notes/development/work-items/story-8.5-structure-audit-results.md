---
title: "Story 8.5 structure audit results"
---

## Executive summary

This audit evaluated the `packages/docs/src/content/docs/` directory structure against dual Diataxis (user documentation) and AMDiRE (development documentation) frameworks.
The documentation contains 62 files across 17 directories, with significant structural gaps in specific areas.

**Key findings:**

| Category | Status | Gap Severity |
|----------|--------|--------------|
| tutorials/ | EMPTY (contains only .keep) | CRITICAL |
| reference/ | 1 file only | HIGH |
| development/operations/ | 1 file only | HIGH |
| development/traceability/ | 2 files only | HIGH |
| development/work-items/ | Index + empty subdirs | MEDIUM |
| guides/ | 8 files, comprehensive | LOW (verify completeness) |
| concepts/ | 5 files, comprehensive | LOW (verify coverage) |
| development/context/ | 7 files, comprehensive | LOW (verify currency) |
| development/requirements/ | 8 files, comprehensive | LOW (verify alignment) |
| development/architecture/ | 19 files, comprehensive | LOW (verify currency) |

**Recommended action sequence:** Stories 8.6 (CLI reference) → 8.8 (Tutorials) → 8.7 (AMDiRE audit) → 8.10 (Test docs) → 8.9 (Cross-references)

## Diataxis framework assessment

### tutorials/ - CRITICAL

**Current state:** Directory exists but contains only a `.keep` placeholder file.
No actual tutorial content exists.

**Gap:** New users lack guided learning paths for:
- Bootstrap-to-activation journey (R1)
- Secrets lifecycle complete (R2)
- Darwin deployment pipeline (R3)
- NixOS/cloud deployment pipeline (R4)

**Recommended action:**
1. Create `tutorials/bootstrap.md` - Complete bootstrap journey from zero to working system
2. Create `tutorials/secrets.md` - Full secrets lifecycle (create, rotate, share, revoke)
3. Create `tutorials/darwin-deployment.md` - macOS host full lifecycle
4. Create `tutorials/nixos-deployment.md` - NixOS/cloud deployment lifecycle

**Priority:** CRITICAL - Blocks new user success
**Estimated effort:** HIGH (20-30 hours for 4 tutorials)
**Stories affected:** Story 8.8 (primary)

### guides/ - LOW

**Current state:** 8 files total (7 guides + index)

| File | Purpose | Status |
|------|---------|--------|
| index.md | Navigation and categorization | Current |
| getting-started.md | Bootstrap nix and activate | Current |
| host-onboarding.md | Darwin vs NixOS host addition | Current |
| home-manager-onboarding.md | User environment setup | Current |
| adding-custom-packages.md | pkgs-by-name pattern | Current |
| secrets-management.md | Two-tier secrets (clan vars + sops-nix) | Current |
| handling-broken-packages.md | Hotfixes and overlays | Current |
| mcp-servers-usage.md | MCP integration | Current |

**Gap:** Generally complete for current use cases.
Missing guides for:
- Terraform/terranix operations (GCP/Hetzner provisioning)
- Zerotier network administration
- CI/CD workflow customization

**Recommended action:** Defer to Story 8.9 cross-reference validation.
May add guides based on operational experience post-Story 8.6.

**Priority:** LOW - Existing guides are comprehensive
**Estimated effort:** MEDIUM (if additional guides needed)
**Stories affected:** Story 8.9 (validation), Story 8.6 (may discover gaps)

### concepts/ - LOW

**Current state:** 5 files total (4 concepts + index)

| File | Purpose | Status |
|------|---------|--------|
| index.md | Navigation | Current |
| nix-config-architecture.md | Four-layer architecture overview | Current |
| dendritic-architecture.md | Aspect-based module organization | Current |
| clan-integration.md | Multi-machine coordination | Current |
| multi-user-patterns.md | Admin vs standalone user patterns | Current |

**Gap:** Generally complete for understanding current architecture.
Potential missing concepts:
- Overlay architecture (five-layer composition) - partially covered in reference/repository-structure.md
- Terranix infrastructure patterns - not documented as concept
- Zerotier networking patterns - covered in clan-integration.md but sparse

**Recommended action:** Defer unless Story 8.6 or 8.7 reveals specific conceptual gaps.

**Priority:** LOW - Existing concepts are adequate
**Estimated effort:** LOW
**Stories affected:** Story 8.7 (may identify gaps during AMDiRE audit)

### reference/ - HIGH

**Current state:** 1 file only

| File | Purpose | Status |
|------|---------|--------|
| repository-structure.md | Directory layout reference | Comprehensive |

**Gap:** Missing critical reference documentation:
- Justfile recipe reference (100+ recipes across 10 groups)
- Flake apps reference (activate, update, home switch workflows)
- Module options reference (darwin, nixos, home-manager options)
- Clan CLI reference (clan machines, clan vars, clan secrets)
- Terranix configuration reference

**Recommended action:**
1. Create `reference/justfile-recipes.md` - Complete recipe catalog with examples
2. Create `reference/flake-apps.md` - Flake app documentation
3. Create `reference/clan-cli.md` - Clan command reference
4. Optionally: `reference/module-options.md` (may be auto-generated)

**Priority:** HIGH - Users cannot discover available tooling
**Estimated effort:** HIGH (15-20 hours)
**Stories affected:** Story 8.6 (primary - rationalize and document CLI)

## AMDiRE framework assessment

### development/context/ - LOW

**Current state:** 7 files total (6 context docs + index)

| File | Purpose | Status |
|------|---------|--------|
| index.md | Navigation and usage guide | Current |
| project-scope.md | Infrastructure scope | Needs review |
| stakeholders.md | User/maintainer identification | Current |
| constraints-and-rules.md | Non-negotiable vs conditional | Current |
| goals-and-objectives.md | Goal hierarchy | Needs review |
| domain-model.md | Nix ecosystem domain | Current |
| glossary.md | Terms and abbreviations | Needs GCP additions |

**Gap:** Generally comprehensive.
Currency concerns:
- project-scope.md should mention GCP infrastructure (galena, scheelite)
- goals-and-objectives.md G-S09/G-S10 for GCP may be missing
- glossary.md needs GCP host names (galena, scheelite)

**Recommended action:** Story 8.7 should verify currency with post-Epic 7 state.

**Priority:** LOW - Existing content is comprehensive
**Estimated effort:** LOW (2-4 hours for currency updates)
**Stories affected:** Story 8.7 (primary)

### development/requirements/ - LOW

**Current state:** 8 files total (7 requirements docs + index)

| File | Purpose | Status |
|------|---------|--------|
| index.md | Navigation with usage guide | Current |
| system-vision.md | High-level capabilities | Current |
| usage-model.md | 7 detailed use cases | Current |
| functional-hierarchy.md | 52 functions across 9 categories | Current |
| quality-requirements.md | 8 quality attributes | Current |
| deployment-requirements.md | 10 deployment scenarios | Current |
| system-constraints.md | 10 constraint categories | Current |
| risk-list.md | 10 risks with mitigation | Current |

**Gap:** Comprehensive (~4,300 lines per index.md).
Currency concerns:
- May need GCP-specific deployment requirements
- Risk list may need Epic 7+ risks
- Usage model may need terranix/GCP use cases

**Recommended action:** Story 8.7 should validate alignment with implemented functionality.

**Priority:** LOW - Existing content is comprehensive
**Estimated effort:** LOW (3-5 hours for validation)
**Stories affected:** Story 8.7 (primary)

### development/architecture/ - LOW

**Current state:** 19 files total (16 ADRs + 3 other files)

**ADRs (16):**

| ADR | Topic | Status |
|-----|-------|--------|
| 0001 | Claude Code multi-profile system | Current |
| 0002 | Generic just recipes | Current |
| 0003 | Overlay composition patterns | Current |
| 0004 | Monorepo structure | Current |
| 0005 | Semantic versioning | Current |
| 0006 | Monorepo tag strategy | Current |
| 0007 | Bun workspaces | Current |
| 0008 | TypeScript configuration | Current |
| 0009 | Nix development environment | Current |
| 0010 | Testing architecture | Current |
| 0011 | SOPS secrets management | Needs review (two-tier update?) |
| 0012 | GitHub Actions pipeline | Current |
| 0013 | Cloudflare Workers deployment | Current |
| 0014 | Design principles | Current |
| 0015 | CI caching optimization | SUPERSEDED by 0016 |
| 0016 | Per-job content-addressed caching | Current |

**Other files:**
- index.md - ADR navigation by category
- nixpkgs-hotfixes.md - Multi-channel resilience

**Gap:** Generally comprehensive.
Currency concerns:
- ADR-0011 may need update for two-tier secrets (clan vars + sops-nix)
- No ADR for dendritic flake-parts adoption (architectural decision undocumented)
- No ADR for clan-core integration (architectural decision undocumented)
- No ADR for terranix/GCP infrastructure

**Recommended action:** Story 8.7 should validate ADR currency and identify missing ADRs.

**Priority:** LOW - Existing ADRs are comprehensive
**Estimated effort:** MEDIUM (if new ADRs needed: 6-10 hours)
**Stories affected:** Story 8.7 (primary)

### development/traceability/ - HIGH

**Current state:** 2 files total (1 content file + index)

| File | Purpose | Status |
|------|---------|--------|
| index.md | Navigation (minimal) | Sparse |
| ci-philosophy.md | CI philosophy documentation | Current |

**Gap:** Significant missing content:
- Test harness documentation (nix-unit, modules/checks/)
- Test case enumeration and coverage
- Validation matrices (requirements → tests)
- Test troubleshooting guides
- Local test reproduction procedures

**Recommended action:**
1. Create `traceability/test-harness.md` - nix-unit and modules/checks/ documentation
2. Create `traceability/test-catalog.md` - Enumeration of all tests by category
3. Expand index.md to properly navigate available content

**Priority:** HIGH - Testing approach undocumented
**Estimated effort:** MEDIUM (8-12 hours)
**Stories affected:** Story 8.10 (primary)

### development/operations/ - HIGH

**Current state:** 1 file only (no index)

| File | Purpose | Status |
|------|---------|--------|
| troubleshooting-ci-cache.md | CI cache troubleshooting | Comprehensive (296 lines) |

**Gap:** Missing critical operational documentation:
- Deployment runbooks (darwin-rebuild, clan machines update)
- Rollback procedures (previous generation, git revert)
- Incident response (network outage, failed deployment)
- Monitoring setup (system health, zerotier status)
- Maintenance procedures (flake update, nixpkgs channel switch)
- GCP/Hetzner infrastructure operations (terraform apply, node toggle)

**Recommended action:**
1. Create `operations/index.md` - Navigation and overview
2. Create `operations/deployment-runbooks.md` - Standard deployment procedures
3. Create `operations/rollback-procedures.md` - Recovery from failed deployments
4. Create `operations/infrastructure-operations.md` - Terranix/cloud operations
5. Consider: `operations/monitoring.md`, `operations/maintenance.md`

**Priority:** HIGH - Operational procedures undocumented
**Estimated effort:** HIGH (12-18 hours)
**Stories affected:** Story 8.7 (may identify scope), Story 8.10 (operations testing)

### development/work-items/ - MEDIUM

**Current state:** 1 file + 2 empty subdirectories

| Item | Purpose | Status |
|------|---------|--------|
| index.md | Placeholder navigation | Sparse (no content) |
| backlog/ | Backlog items | EMPTY directory |
| completed/ | Completed items | EMPTY directory |

**Gap:** Structure exists but no content.
Work items tracked externally in `docs/notes/development/work-items/` (outside Starlight site).

**Recommended action:**
1. Decision: Include work items in Starlight OR link to external location
2. If included: Populate from sprint-status.yaml or generate during builds
3. If external: Update index.md with clear link to `docs/notes/development/`

**Priority:** MEDIUM - Structure exists, content external
**Estimated effort:** LOW (2-4 hours)
**Stories affected:** Story 8.9 (navigation/cross-reference)

## Cross-reference assessment

### Navigation quality

**Homepage (index.mdx):**
- Clear hero with primary action (Getting Started)
- Feature cards provide good orientation
- Quick start section with bootstrap commands
- Architecture overview links to concepts
- Documentation structure section mentions all categories
- Next steps cards link to key destinations

**Gaps:**
- No link to tutorials/ (currently empty)
- No prominent link to reference/ content
- Development docs not surfaced in next steps

### Index file quality

| Index | Quality | Notes |
|-------|---------|-------|
| guides/index.md | GOOD | Categorized by purpose, cross-refs to concepts |
| concepts/index.md | GOOD | Clear categories, complete coverage |
| reference/ (no index) | MISSING | Only repository-structure.md exists |
| development/index.md | SPARSE | Only lists 3 sections, missing context/requirements |
| development/context/index.md | EXCELLENT | Comprehensive with usage guidance |
| development/requirements/index.md | EXCELLENT | Detailed with document statistics |
| development/architecture/index.md | SPARSE | Only lists ADRs link and nixpkgs-hotfixes |
| development/traceability/index.md | SPARSE | Only lists ci-philosophy |
| development/operations/ (no index) | MISSING | Single file, no index |
| development/work-items/index.md | SPARSE | Placeholder, no content |

### Cross-link coverage

**Well-linked:**
- guides/ ↔ concepts/ (bidirectional references)
- development/context/ ↔ development/requirements/ (navigation sections)
- ADRs cross-reference each other where relevant

**Missing links:**
- development/index.md → development/context/ (not listed)
- development/index.md → development/requirements/ (not listed)
- reference/ → concepts/ (no cross-references in repository-structure.md footer)
- tutorials/ → guides/ (cannot link, tutorials empty)

### Discoverability assessment

**2-click reachability from homepage:**
- Getting Started guide: YES (hero action)
- Host onboarding: YES (via guides)
- Secrets management: YES (via guides)
- Dendritic architecture: YES (via concepts or next steps)
- ADRs: NO (requires navigation through development → architecture → adrs)
- CI troubleshooting: NO (requires development → operations)
- Requirements docs: NO (development/index.md doesn't list them)

**Recommendations:**
- Add "Development docs" card to homepage next steps
- Improve development/index.md to list all subsections
- Consider adding popular ADRs to homepage or guides sidebar

## Priority matrix

| Gap ID | Gap | Severity | Effort | Stories Affected |
|--------|-----|----------|--------|------------------|
| G-01 | tutorials/ empty | CRITICAL | HIGH | 8.8 |
| G-02 | reference/ sparse (1 file) | HIGH | HIGH | 8.6 |
| G-03 | operations/ sparse (1 file, no index) | HIGH | HIGH | 8.7, 8.10 |
| G-04 | traceability/ sparse (2 files) | HIGH | MEDIUM | 8.10 |
| G-05 | development/index.md incomplete navigation | MEDIUM | LOW | 8.9 |
| G-06 | work-items/ empty content | MEDIUM | LOW | 8.9 |
| G-07 | Missing ADRs (dendritic, clan, terranix) | MEDIUM | MEDIUM | 8.7 |
| G-08 | Context docs currency (GCP) | LOW | LOW | 8.7 |
| G-09 | Requirements docs currency (GCP) | LOW | LOW | 8.7 |
| G-10 | ADR-0011 currency (two-tier secrets) | LOW | LOW | 8.7 |

## Recommendations for subsequent stories

### Story 8.6 (CLI Reference) inputs

**Primary deliverable:** Create comprehensive CLI reference documentation

**Scope from this audit:**
1. Create `reference/justfile-recipes.md` with complete recipe catalog
2. Create `reference/flake-apps.md` documenting activation workflows
3. Create `reference/clan-cli.md` for clan command reference
4. Rationalize justfile: Rename stale recipes, remove deprecated commands, improve discoverability
5. Verify all documented recipes exist and work correctly

**Key decisions for 8.6:**
- Recipe naming convention (consistent prefixes)
- Deprecated recipe removal vs documentation of removed items
- Auto-generation vs manual documentation approach

**Dependencies:** None (can proceed immediately)

### Story 8.7 (AMDiRE Audit) inputs

**Primary deliverable:** Validate AMDiRE docs reflect post-Epic 7 state

**Scope from this audit:**
1. Verify context docs include GCP infrastructure (galena, scheelite)
2. Verify requirements docs include GCP deployment scenarios
3. Assess need for new ADRs (dendritic adoption, clan integration, terranix)
4. Update ADR-0011 for two-tier secrets if needed
5. Assess operations/ expansion scope

**Key decisions for 8.7:**
- New ADR creation: dendritic (ADR-0017?), clan (ADR-0018?), terranix (ADR-0019?)
- Operations expansion: Full runbooks vs focused troubleshooting
- Currency update approach: In-place edits vs comprehensive rewrites

**Dependencies:** Story 8.6 may reveal additional CLI documentation needs

### Story 8.8 (Tutorials) inputs

**Primary deliverable:** Populate empty tutorials/ directory

**Scope from this audit:**
1. Bootstrap tutorial: Zero to working system (from guides/getting-started.md expansion)
2. Secrets tutorial: Complete lifecycle (from guides/secrets-management.md expansion)
3. Darwin deployment tutorial: Full lifecycle for macOS hosts
4. NixOS deployment tutorial: Cloud/VPS deployment lifecycle

**Key decisions for 8.8:**
- Tutorial length and depth (quick start vs comprehensive)
- Overlap management with guides/ (tutorials teach, guides reference)
- Ordering and prerequisites between tutorials

**Dependencies:** Story 8.6 (CLI reference enables tutorial commands), Story 8.7 (operations docs inform deployment tutorials)

### Story 8.9 (Cross-References) inputs

**Primary deliverable:** Validate navigation and fix cross-reference gaps

**Scope from this audit:**
1. Improve development/index.md to list all subsections
2. Add missing cross-references between sections
3. Verify all internal links valid
4. Improve 2-click reachability from homepage
5. Update homepage to include development docs in next steps

**Key decisions for 8.9:**
- Link validation tooling (manual vs automated)
- Homepage structure changes (additional cards vs sidebar updates)
- Navigation consistency patterns

**Dependencies:** Stories 8.6, 8.7, 8.8 (must validate links to new content)

### Story 8.10 (Test Docs) inputs

**Primary deliverable:** Document test harness and CI-local parity

**Scope from this audit:**
1. Create traceability/test-harness.md documenting nix-unit and modules/checks/
2. Create traceability/test-catalog.md enumerating all tests
3. Expand operations/ with test-related runbooks
4. Document CI-to-local reproduction procedures
5. Improve traceability/index.md navigation

**Key decisions for 8.10:**
- Test catalog granularity (individual tests vs categories)
- Integration with operations/ (combined vs separate)
- Auto-generation from test files vs manual documentation

**Dependencies:** Story 8.7 (operations scope affects test documentation)

## Appendix: complete file inventory

### Root level (1 file)
- index.mdx

### about/ (8 files)
- credits.md
- contributing/index.md
- contributing/ci-cd-setup.md
- contributing/commit-conventions.md
- contributing/container-runtime-setup.md
- contributing/multi-arch-containers.md
- contributing/semantic-release-preview.md
- contributing/testing.md

### concepts/ (5 files)
- index.md
- nix-config-architecture.md
- dendritic-architecture.md
- clan-integration.md
- multi-user-patterns.md

### guides/ (8 files)
- index.md
- getting-started.md
- host-onboarding.md
- home-manager-onboarding.md
- adding-custom-packages.md
- secrets-management.md
- handling-broken-packages.md
- mcp-servers-usage.md

### reference/ (1 file)
- repository-structure.md

### tutorials/ (0 files)
- .keep (placeholder only)

### development/ (40 files)

**development/ root (1 file):**
- index.md

**development/context/ (7 files):**
- index.md
- project-scope.md
- stakeholders.md
- constraints-and-rules.md
- goals-and-objectives.md
- domain-model.md
- glossary.md

**development/requirements/ (8 files):**
- index.md
- system-vision.md
- usage-model.md
- functional-hierarchy.md
- quality-requirements.md
- deployment-requirements.md
- system-constraints.md
- risk-list.md

**development/architecture/ (19 files):**
- index.md
- nixpkgs-hotfixes.md
- adrs/index.md
- adrs/0001-claude-code-multi-profile-system.md
- adrs/0002-use-generic-just-recipes.md
- adrs/0003-overlay-composition-patterns.md
- adrs/0004-monorepo-structure.md
- adrs/0005-semantic-versioning.md
- adrs/0006-monorepo-tag-strategy.md
- adrs/0007-bun-workspaces.md
- adrs/0008-typescript-configuration.md
- adrs/0009-nix-development-environment.md
- adrs/0010-testing-architecture.md
- adrs/0011-sops-secrets-management.md
- adrs/0012-github-actions-pipeline.md
- adrs/0013-cloudflare-workers-deployment.md
- adrs/0014-design-principles.md
- adrs/0015-ci-caching-optimization.md
- adrs/0016-per-job-content-addressed-caching.md

**development/traceability/ (2 files):**
- index.md
- ci-philosophy.md

**development/operations/ (1 file):**
- troubleshooting-ci-cache.md

**development/work-items/ (1 file + 2 empty dirs):**
- index.md
- backlog/ (empty)
- completed/ (empty)

### Total: 62 files in 17 directories

## Audit methodology

**Audit date:** 2025-12-02

**Audit scope:** `packages/docs/src/content/docs/` directory

**Framework references:**
- Diataxis: https://diataxis.fr/
- AMDiRE: https://arxiv.org/abs/1611.10024

**Research streams covered:**
- R8: Tutorials Structure Design
- R9: Reference Documentation Gaps
- R10: Guides Completeness Audit
- R14: Operations Runbook Assessment
- R15: Traceability Enhancement

**Tools used:**
- fd (file discovery)
- File reading and analysis
- Cross-reference to docs/notes/development/research/documentation-coverage-analysis.md

**Severity classification:**
- CRITICAL: Blocks user success
- HIGH: Significant friction
- MEDIUM: Minor friction
- LOW: Nice-to-have improvements
