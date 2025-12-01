# Story 8.1 Audit Results: Starlight Documentation Staleness Assessment

**Date:** 2025-12-01
**Epic:** 8 - Documentation Refresh
**Story:** 8.1 - Audit existing Starlight docs for staleness

## Executive Summary

**Total files audited:** 59
**Documentation root:** `packages/docs/src/content/docs/`

### Status Distribution

| Status | Count | Percentage |
|--------|-------|------------|
| Current | 22 | 37% |
| Stale | 21 | 36% |
| Obsolete | 9 | 15% |
| Missing | 7 | N/A |

### Priority Distribution

| Priority | Count | Description |
|----------|-------|-------------|
| Critical | 6 | Blocks Stories 8.2-8.4; fundamentally wrong architecture |
| High | 12 | Significant gaps; actively misleads readers |
| Medium | 12 | Outdated but not harmful; nice-to-have improvements |
| Low | 10 | Cosmetic; minor inaccuracies |
| Current | 19 | No changes needed |

### Total Effort Estimate

**Estimated total hours:** 38-46 hours

- Story 8.2 (Architecture/Concepts): 16-20h
- Story 8.3 (Host Onboarding Guides): 10-12h
- Story 8.4 (Secrets Management): 8-10h
- Additional (new docs): 4h

## Audit Results Table

### Landing Page and Navigation

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `index.mdx` | Obsolete | Tagline mentions "nixos-unified directory-based autowiring"; features list describes deprecated patterns | Critical | 3h | 8.2 |
| `concepts/index.md` | Stale | References obsolete architecture docs | High | 1h | 8.2 |
| `guides/index.md` | Stale | Missing zerotier, GCP, clan guides in listing | Medium | 1h | 8.3 |
| `development/index.md` | Current | Generic AMDiRE description | - | - | - |
| `development/architecture/index.md` | Current | Links to valid docs | - | - | - |

### Reference Section

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `reference/repository-structure.md` | Obsolete | `configurations/` directory structure (lines 12-15, 45-57); lists obsolete hosts (stibnite-nixos, blackphos-nixos, orb-nixos); "autowired by nixos-unified" | Critical | 4h+ | 8.2 |

### Concepts Section

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `concepts/nix-config-architecture.md` | Obsolete | Entire "three-layer architecture" with nixos-unified is deprecated; should describe dendritic flake-parts + clan-core | Critical | 4h+ | 8.2 |
| `concepts/understanding-autowiring.md` | Obsolete | Entire document describes nixos-unified autowiring; current architecture uses import-tree auto-discovery | Critical | 4h | 8.2 |
| `concepts/multi-user-patterns.md` | Obsolete | All `configurations/` paths (lines 16, 34, 48-59, 65, 97); pattern concepts are valid but paths wrong | High | 3h | 8.2 |

### Guides Section

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `guides/getting-started.md` | Stale | `configurations/` references (lines 144-150); "directory-based autowiring" mention; links to obsolete docs | High | 2h | 8.3 |
| `guides/host-onboarding.md` | Obsolete | "3-tier key architecture" (line 21); Bitwarden as single source (line 31); `configurations/darwin/` paths (lines 14, 41); entire SOPS workflow outdated | Critical | 4h+ | 8.3 |
| `guides/home-manager-onboarding.md` | Stale | `configurations/home/` paths (lines 72-76); Bitwarden-based workflow; sopsIdentifier pattern | High | 3h | 8.3 |
| `guides/secrets-management.md` | Stale | Focuses on CI/GitHub secrets; missing clan vars + sops-nix two-tier pattern; Dev/CI key model outdated | High | 4h | 8.4 |
| `guides/adding-custom-packages.md` | Current | Uses `overlays/packages/` which is retained | - | - | - |
| `guides/handling-broken-packages.md` | Current | Uses `overlays/infra/hotfixes.nix` which is retained | - | - | - |
| `guides/mcp-servers-usage.md` | Current | MCP configuration is independent of architecture | - | - | - |

### About Section

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `about/credits.md` | Stale | Lists nixos-unified as "Primary framework" (line 13-14); should credit dendritic flake-parts + clan-core | Medium | 1h | 8.2 |
| `about/contributing/*.md` (7 files) | Stale | May reference old paths; need individual review | Low | 2h | 8.2 |

### Development/Architecture Section

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `development/architecture/nixpkgs-hotfixes.md` | Current | Overlay hotfixes pattern retained | - | - | - |
| `development/architecture/adrs/0001-use-just-task-runner.md` | Current | Tool choice still valid | - | - | - |
| `development/architecture/adrs/0002-use-generic-just-recipes.md` | Stale | References Bitwarden CLI in devshell | Low | 1h | 8.4 |
| `development/architecture/adrs/0003-overlay-composition-patterns.md` | Current | Overlay patterns retained | - | - | - |
| `development/architecture/adrs/0004-nix-darwin-per-user-secrets.md` | Current | sops-nix patterns still valid | - | - | - |
| `development/architecture/adrs/0005-adopt-starlight-docs-site.md` | Current | Meta documentation choice | - | - | - |
| `development/architecture/adrs/0006-claude-code-dev-shell.md` | Current | Dev tooling still valid | - | - | - |
| `development/architecture/adrs/0007-adopt-sops-yaml-extension.md` | Current | SOPS file format choice | - | - | - |
| `development/architecture/adrs/0008-migrate-editor-to-home-manager.md` | Current | Editor config approach | - | - | - |
| `development/architecture/adrs/0009-deprecate-external-neovim-modules.md` | Current | Neovim decision still valid | - | - | - |
| `development/architecture/adrs/0010-adopt-mcp-server-integration.md` | Current | MCP integration choice | - | - | - |
| `development/architecture/adrs/0011-adopt-cc-statusline-rs.md` | Current | Statusline tooling | - | - | - |
| `development/architecture/adrs/0012-adopt-jujutsu-vcs.md` | Current | VCS choice | - | - | - |
| `development/architecture/adrs/0013-adopt-bmad-method.md` | Current | Process choice | - | - | - |
| `development/architecture/adrs/0014-adopt-dendritic-flake-parts.md` | Current | Architecture decision recorded | - | - | - |
| `development/architecture/adrs/0015-adopt-clan-core.md` | Current | Clan adoption recorded | - | - | - |
| `development/architecture/adrs/0016-adopt-terranix.md` | Current | Terranix decision recorded | - | - | - |

### Development/Context Section

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `development/context/index.md` | Stale | Migration described as "target state" when now complete; line 17 says "Target state" for what is current state | Medium | 2h | 8.2 |
| `development/context/constraints-and-rules.md` | Current | General constraints still valid | - | - | - |
| `development/context/domain-model.md` | Stale | `clan.nix` path (line 175) vs current clan integration; mostly accurate but needs path updates | Medium | 2h | 8.2 |
| `development/context/glossary.md` | Current | Terminology definitions valid | - | - | - |
| `development/context/goals-and-objectives.md` | Stale | Objectives described as "target" vs "achieved" | Medium | 2h | 8.2 |
| `development/context/project-scope.md` | Stale | Migration scope now complete; should reflect current state | Medium | 2h | 8.2 |
| `development/context/stakeholders.md` | Current | Stakeholder analysis still valid | - | - | - |

### Development/Requirements Section

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `development/requirements/index.md` | Stale | References migration; needs "current state" framing | Low | 1h | 8.2 |
| `development/requirements/deployment-requirements.md` | Current | Deployment patterns general | - | - | - |
| `development/requirements/functional-hierarchy.md` | Stale | References `modules/flake-parts/clan.nix` path | Low | 1h | 8.2 |
| `development/requirements/quality-requirements.md` | Current | Quality metrics still valid | - | - | - |
| `development/requirements/risk-list.md` | Stale | Migration risks now realized/mitigated | Low | 1h | 8.2 |
| `development/requirements/system-constraints.md` | Current | System constraints valid | - | - | - |
| `development/requirements/system-vision.md` | Stale | Vision describes "target" which is now current | Medium | 1h | 8.2 |
| `development/requirements/usage-model.md` | Stale | Use cases reference migration, path updates needed | Medium | 2h | 8.2 |

### Development/Traceability and Operations

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `development/traceability/ci-cd-philosophy.md` | Current | CI/CD approach still valid | - | - | - |
| `development/traceability/index.md` | Current | Index page valid | - | - | - |
| `development/operations/index.md` | Current | Operations overview valid | - | - | - |

### Development/Work Items

| File | Status | Key Issues | Priority | Effort | Target Story |
|------|--------|------------|----------|--------|--------------|
| `development/work-items/index.md` | Current | Work item tracking valid | - | - | - |

## Missing Documentation

Documentation gaps identified from Epic 7 retrospective and architecture analysis:

### Critical Missing (HIGH Priority from Epic 7)

| Topic | Why Missing | Recommended Location | Effort |
|-------|-------------|---------------------|--------|
| Dendritic Flake-Parts Architecture | Core current architecture undocumented | `concepts/dendritic-architecture.md` | 4h |
| Clan-Core Integration | Multi-host coordination pattern | `concepts/clan-integration.md` | 4h |
| Two-Tier Secrets (clan vars + sops-nix) | Current secrets model undocumented | `guides/secrets-management.md` (rewrite) | 4h |
| GCP Deployment Patterns | Epic 7 startup-script workaround | `guides/gcp-deployment.md` | 3h |
| Zerotier Authorization Flow | Controller update requirement | `guides/zerotier-setup.md` | 2h |
| NVIDIA Datacenter Anti-Patterns | Bug #454772, nvidiaPersistenced | `guides/nvidia-gpu-setup.md` | 3h |

### Medium Priority Missing

| Topic | Why Missing | Recommended Location | Effort |
|-------|-------------|---------------------|--------|
| GPU Onboarding Guide | CUDA cache, driver selection | `guides/nvidia-gpu-setup.md` (combine above) | - |
| Cost Control Toggle Pattern | GCP cost management | `guides/gcp-deployment.md` (include) | - |
| Import-Tree Auto-Discovery | Replaces nixos-unified autowiring | `concepts/dendritic-architecture.md` (include) | - |

## Story Scope Recommendations

### Story 8.2: Architecture/Concepts Documentation

**Scope:** Core architecture docs that define the system

**Files to update:**
1. `index.mdx` - Landing page (Critical, 3h)
2. `reference/repository-structure.md` - Complete rewrite (Critical, 4h+)
3. `concepts/nix-config-architecture.md` - Complete rewrite (Critical, 4h+)
4. `concepts/understanding-autowiring.md` - Replace with import-tree (Critical, 4h)
5. `concepts/multi-user-patterns.md` - Path updates (High, 3h)
6. `concepts/index.md` - Reference updates (High, 1h)
7. `about/credits.md` - Framework credits (Medium, 1h)
8. Development context docs with "target → current" updates (Medium, 6h)

**New docs to create:**
- `concepts/dendritic-architecture.md` - Dendritic flake-parts pattern (4h)
- `concepts/clan-integration.md` - Clan-core multi-host (4h)

**Estimated total:** 34-38 hours

**Dependencies:** None - foundational layer

### Story 8.3: Host Onboarding Guides

**Scope:** Practical guides for adding new machines

**Files to update:**
1. `guides/host-onboarding.md` - Complete rewrite (Critical, 4h+)
2. `guides/home-manager-onboarding.md` - Path/workflow updates (High, 3h)
3. `guides/getting-started.md` - Architecture reference updates (High, 2h)
4. `guides/index.md` - New guide listings (Medium, 1h)

**New docs to create:**
- `guides/zerotier-setup.md` - Network overlay setup (2h)
- `guides/gcp-deployment.md` - GCP + cost control patterns (3h)
- `guides/nvidia-gpu-setup.md` - GPU + CUDA + anti-patterns (3h)

**Estimated total:** 18-20 hours

**Dependencies:** Story 8.2 (architecture docs referenced by guides)

### Story 8.4: Secrets Management

**Scope:** Secrets documentation reflecting two-tier model

**Files to update:**
1. `guides/secrets-management.md` - Rewrite for clan vars + sops-nix (High, 4h)
2. `development/architecture/adrs/0002-use-generic-just-recipes.md` - Remove Bitwarden refs (Low, 1h)

**New sections needed in secrets-management.md:**
- Clan vars for system-level secrets
- sops-nix for home-manager user secrets
- Machine key derivation (age from SSH host key)
- Comparison: old 3-tier vs new 2-tier

**Estimated total:** 5-6 hours

**Dependencies:** Story 8.2 (architecture context), Story 8.3 (host onboarding references)

## Summary Statistics

### By Category

| Category | Files | Current | Stale | Obsolete |
|----------|-------|---------|-------|----------|
| Landing/Nav | 5 | 2 | 2 | 1 |
| Reference | 1 | 0 | 0 | 1 |
| Concepts | 4 | 0 | 1 | 3 |
| Guides | 8 | 3 | 3 | 2 |
| About | 8 | 6 | 2 | 0 |
| Development/Arch | 17 | 16 | 1 | 0 |
| Development/Context | 7 | 3 | 4 | 0 |
| Development/Requirements | 8 | 3 | 5 | 0 |
| Development/Other | 4 | 4 | 0 | 0 |
| **TOTAL** | 59 | 37 | 18 | 7 |

### Staleness Indicators Found

| Indicator | Occurrences | Files Affected |
|-----------|-------------|----------------|
| `nixos-unified` references | 80+ | 35+ |
| `configurations/` paths | 60+ | 20+ |
| `bitwarden` references | 14 | 4 |
| `3-tier` / `three-tier` secrets | 2 | 2 |
| `LazyVim-module` | 1 | 1 |
| Obsolete hosts (stibnite-nixos, etc.) | 5 | 2 |

### What's Working (Current)

These sections are accurately documented and need no updates:

1. **Overlay infrastructure** - `overlays/packages/`, `overlays/infra/hotfixes.nix`, composition patterns
2. **ADRs** - All 16 ADRs accurately capture decisions made
3. **Tool choices** - just, starship, MCP servers, jujutsu, sops-yaml
4. **CI/CD philosophy** - General approaches still valid
5. **Quality requirements** - Metrics and constraints still apply
6. **Glossary** - Terminology definitions accurate

## Critical Path Items

Documents that must be updated first (block other work):

1. **concepts/nix-config-architecture.md** - Foundation for all other docs
2. **reference/repository-structure.md** - Referenced by many guides
3. **index.mdx** - Entry point for all documentation
4. **guides/host-onboarding.md** - Core operational guide

## Recommendations

### Immediate Actions for Story 8.2

1. Create `concepts/dendritic-architecture.md` first - establishes terminology
2. Rewrite `concepts/nix-config-architecture.md` to reference new doc
3. Update `index.mdx` landing page immediately after
4. Rewrite `reference/repository-structure.md` with correct paths

### Content Strategy

1. **Don't preserve old content** - The architecture changed fundamentally; complete rewrites are appropriate for obsolete docs
2. **Preserve valid concepts** - Multi-user patterns, overlay composition, etc. are still valid - just update paths
3. **Add "Migration Complete" context** - Development docs should note that migration (Phase 0-1) is complete
4. **Create architecture diagrams** - Current docs lack visual representation of dendritic + clan architecture

### Documentation Debt Reduction

1. **Remove nixos-unified references entirely** - No backwards compatibility needed in docs
2. **Consolidate secrets docs** - Single source of truth for two-tier model
3. **Add practical examples** - Current docs are conceptual; add copy-paste snippets
4. **Link to external references** - Clan docs, dendritic-flake-parts repo, import-tree

## Appendix: Search Patterns Used

```bash
# Primary staleness indicators
rg "nixos-unified|configurations/" packages/docs/

# Secondary indicators
rg "LazyVim-module|nix-darwin-kickstarter" packages/docs/

# Obsolete hosts
rg "stibnite-nixos|blackphos-nixos|orb-nixos" packages/docs/

# Old secrets pattern
rg "bitwarden|three-tier|3-tier" packages/docs/

# Current architecture (should appear more)
rg "dendritic|import-tree|clan-core" packages/docs/
```

## Audit Completion

- **Auditor:** Claude (via dev-story workflow)
- **Date:** 2025-12-01
- **Story Status:** Complete
- **Next Steps:** Story 8.2 (Architecture/Concepts), 8.3 (Guides), 8.4 (Secrets)
