# Story 8.7 AMDiRE Audit Results

Audit Date: 2025-12-02
Audited By: Claude Opus 4.5 (dev-story workflow)
Story Reference: docs/notes/development/work-items/8-7-audit-amdire-development-documentation-alignment.md

## Summary

| Category | Total | Current | Stale | Obsolete | Needs Update | Superseded |
|----------|-------|---------|-------|----------|--------------|------------|
| Context Documentation | 7 | 2 | 5 | 0 | - | - |
| Requirements Documentation | 8 | 4 | 4 | 0 | - | - |
| ADRs | 17 | 14 | - | - | 1 | 1 (correct) |
| **TOTAL** | **32** | **20** | **9** | **0** | **1** | **1** |

**Overall Status:** 62.5% current (20/32), 37.5% requiring updates (12/32)

### Priority Distribution

| Priority | Count | Files |
|----------|-------|-------|
| Critical | 4 | domain-model.md, goals-and-objectives.md, project-scope.md, system-vision.md |
| High | 6 | constraints-and-rules.md, glossary.md, deployment-requirements.md, functional-hierarchy.md, usage-model.md, ADR-0003 |
| Medium | 2 | risk-list.md, system-constraints.md |
| Low | 3 | stakeholders.md, quality-requirements.md, requirements/index.md |

### Common Staleness Patterns

1. **nixos-unified as "current"**: 9 files describe nixos-unified as current architecture when dendritic + clan is actual
2. **5-machine vs 8-machine fleet**: 8 files reference only 5 machines, missing electrum, galena, scheelite
3. **Migration as pending**: 7 files describe completed migration (Epics 1-7) as future work
4. **Target/Current inversion**: 5 files describe dendritic + clan as "target" when it's current state
5. **Missing two-tier secrets**: 6 files don't document clan vars + sops-nix architecture

## Context Documentation Assessment

| File | Status | Issues | Recommended Action | Priority |
|------|--------|--------|-------------------|----------|
| constraints-and-rules.md | stale | nixos-unified refs (L95), migration rules (L200-218) describe future, lists 4 hosts not 8 | Remove migration section, update host inventory, remove nixos-unified refs | high |
| domain-model.md | stale | nixos-unified section (L28-56), configurations/ refs, target/current inverted, missing electrum/galena/scheelite | Major restructure: remove nixos-unified, rename target→current, update 8-host inventory | critical |
| glossary.md | stale | configurations/ path (L93), nixos-unified defined as current (L124-127), only 5 hosts (L214-230) | Add 3 hosts, mark nixos-unified deprecated, add Pattern A term, update migration terms | high |
| goals-and-objectives.md | stale | G-S04/G-S06/G-U02/G-U03/G-U06 marked in-progress when achieved, migration described as future (L491-527) | Move achieved goals to "Achieved" section, update statuses, remove future migration framing | critical |
| project-scope.md | stale | nixos-unified as current (L7-11, L23-53), target/current inverted, only 4 hosts (L33-38) | Swap current/target sections, add 8-machine fleet, update conclusion | critical |
| stakeholders.md | current | Minor: nixos-unified status (L88) says "being replaced" | Update nixos-unified status to "deprecated, replaced Nov 2024" | low |
| index.md | current | None - correctly reflects 8 machines, dendritic + clan current, two-tier secrets | None required | N/A |

### Context Documentation Evidence

**constraints-and-rules.md:**
- Line 95: "Must preserve nixos-unified configurations until all hosts migrated"
- Line 57-60: "Existing hosts: Four darwin hosts: stibnite, blackphos, rosegold, argentum"
- Lines 200-218: Migration-specific rules describe Phases 0-5 as future

**domain-model.md:**
- Lines 38-56: "nixos-unified autowiring" section still present
- Line 46: "configurations/{darwin,nixos,home}/" directory reference
- Lines 135-147: Host inventory missing electrum, galena, scheelite

**glossary.md:**
- Lines 124-127: "nixos-unified: Framework providing directory-based autowiring for multi-platform Nix configurations"
- Lines 214-230: Only 5 hosts defined (stibnite, blackphos, rosegold, argentum, cinnabar)

**goals-and-objectives.md:**
- Lines 464-518: "In-progress goals" includes G-S04 (dendritic), G-S06 (clan), G-U02 (multi-host) which are achieved
- Line 287: "Status: Target state (migration planned)" for achieved patterns

**project-scope.md:**
- Line 8: "Current architecture uses flake-parts with nixos-unified"
- Lines 23-53: "Current state architecture" documents deprecated nixos-unified
- Lines 54-92: "Target state architecture" describes what is now current

## Requirements Documentation Assessment

| File | Status | Issues | Recommended Action | Priority |
|------|--------|--------|-------------------|----------|
| deployment-requirements.md | stale | "current (nixos-unified)" framing (L10), only 5 hosts in examples (L368), missing GCP machines | Update to 8-machine fleet, remove current/target framing | high |
| functional-hierarchy.md | stale | Migration functions (MF-001 to MF-004) describe pending work (L649-722), no terranix functions | Reframe migration as historical, add current operations functions | high |
| quality-requirements.md | current | Minor: measurement examples reference pre-migration patterns | Minor updates to reference 8 machines | low |
| risk-list.md | current | Risk statuses show "Not started" when phases complete (R-001 L68, R-007 L508) | Update risk statuses to reflect Epics 1-7 completion | medium |
| system-constraints.md | current | SC-010 (L560-597) treats migration as ongoing | Update SC-010 to reflect migration completion | medium |
| system-vision.md | stale | "Current state vision" documents nixos-unified (L29-47), only 5 machines in diagram (L74-151), migration as future (L325-362) | Complete rewrite of current/target sections, update to 8 machines | critical |
| usage-model.md | stale | nixos-unified as current (L12), Phase 0-6 as pending (L440-474), UC-007 describes future migration | Reframe UC-007 as historical, update examples to 8 machines | high |
| index.md | current | None significant | Minor updates to note migration completion | low |

### Requirements Documentation Evidence

**deployment-requirements.md:**
- Line 10: "Requirements cover both current (nixos-unified) and target (dendritic + clan) architectures."
- Line 368-382: Zerotier example uses only 5 hosts

**functional-hierarchy.md:**
- Lines 652-667: "MF-001: Convert modules to dendritic pattern" treats conversion as future work

**system-vision.md:**
- Lines 29-47: "Current state vision" describes nixos-unified as current foundation
- Line 105: Machine list: "cinnabar (nixos/vps), blackphos, rosegold, argentum, stibnite" - missing 3 machines
- Line 330: "Status: Not started (next step)" for Phase 0 when Epic 1 complete

**usage-model.md:**
- Line 12: "targeting the dendritic flake-parts + clan-core architecture while preserving critical capabilities from the current nixos-unified system"
- Lines 440-446: Migration order lists Phases 0-6 as pending work

## ADR Assessment

| ADR | Status | Issues | Action Needed | Cross-References |
|-----|--------|--------|---------------|------------------|
| 0001-claude-code-multi-profile-system | current | None | none | ADR-0011 (secrets) |
| 0002-use-generic-just-recipes | current | None | none | N/A |
| 0003-overlay-composition-patterns | needs-update | nixos-unified refs (L12-20, L30-42), configurations/ path, overlays/ at root | update or supersede | Missing: dendritic, pkgs-by-name |
| 0004-monorepo-structure | current | None | none | python-nix-template |
| 0005-semantic-versioning | current | None | none | ADR-0006 |
| 0006-monorepo-tag-strategy | current | None | none | ADR-0005 |
| 0007-bun-workspaces | current | None | none | N/A |
| 0008-typescript-configuration | current | None | none | N/A |
| 0009-nix-development-environment | current | None | none | N/A |
| 0010-testing-architecture | current | None | none | testing docs |
| 0011-sops-secrets-management | current | None | none | ADR-0001, secrets guide |
| 0012-github-actions-pipeline | current | None | none | ADR-0015/0016 |
| 0013-cloudflare-workers-deployment | current | None | none | N/A |
| 0014-design-principles | current | None | none | global CLAUDE.md |
| 0015-ci-caching-optimization | superseded | Correctly marked superseded by ADR-0016 (L7) | none | ADR-0016 |
| 0016-per-job-content-addressed-caching | current | None | none | ADR-0015 (supersedes) |
| index.md | current | None | none | All ADRs linked |

### ADR-0003 Staleness Evidence

**Deprecated Patterns:**
- Lines 12-20, 30-42, 373-424: References `nixos-unified` framework extensively
- Lines 37-56, 235-260, 431-445: Documents `overlays/default.nix`, `overlays/inputs.nix`, `overlays/infra/`
- References `configurations/` directory that doesn't exist

**Missing Current Patterns:**
- No mention of dendritic flake-parts pattern
- No mention of pkgs-by-name pattern for overlays
- Current location is `modules/nixpkgs/overlays/` not `overlays/`
- No mention of five-layer overlay architecture documented in test-clan

**Recommended Resolution:**
Either major update to ADR-0003 or create ADR-0017 (Dendritic Overlay Patterns) and supersede ADR-0003

## Traceability Gaps

### Requirements → ADR Gaps

| Requirement Area | ADR Coverage | Gap Description |
|------------------|--------------|-----------------|
| Dendritic architecture | Missing | No ADR documents dendritic flake-parts migration decision |
| Clan-core integration | Missing | No ADR documents clan inventory, vars, services integration |
| Two-tier secrets | Partial | ADR-0011 covers sops-nix but not clan vars tier |
| Multi-platform coordination | Missing | No ADR documents nix-darwin + nixos + home-manager strategy |
| 8-machine fleet operations | Missing | No ADR documents operational patterns for expanded fleet |
| terranix/terraform | Missing | No ADR documents GCP/Hetzner infrastructure provisioning |

### ADR → Code Traceability Gaps

| ADR | Code Reference Gap |
|-----|-------------------|
| ADR-0003 | References `overlays/` but current location is `modules/nixpkgs/overlays/` |
| ADR-0011 | Could reference `modules/home/all/sops-secrets/` for implementation |
| All ADRs | Missing references to dendritic module organization (`modules/{darwin,nixos,home}/`) |

### Context → Requirements Alignment Gaps

| Context Document | Requirements Gap |
|------------------|-----------------|
| domain-model.md | Requirements don't reflect 8-machine operational model |
| glossary.md | Functional-hierarchy doesn't define functions for new terms (clan vars, Pattern A) |
| goals-and-objectives.md | Quality-requirements don't have metrics for achieved goals (G-S04, G-S06, G-U02) |
| project-scope.md | Usage-model examples don't reflect 8-machine scope |

### Missing Traceability Links

1. **PRD → ADR**: No explicit links from PRD requirements to ADR decisions
2. **Epic outcomes → Documentation**: Epic 1-7 completion not reflected in context/requirements docs
3. **Test evidence → ADR validation**: ADR decisions lack references to test coverage proving implementation

## Recommended Actions (Prioritized)

### Critical Priority (Block Story 8.8+)

| # | Action | Files Affected | Estimated Effort |
|---|--------|----------------|------------------|
| 1 | Rewrite current/target state sections, update to 8 machines, reflect Epic 1-7 completion | domain-model.md | 2-3h |
| 2 | Move achieved goals to "Achieved" section, update all goal statuses | goals-and-objectives.md | 1-2h |
| 3 | Swap current/target architecture sections, add 8-machine fleet | project-scope.md | 1-2h |
| 4 | Rewrite current/target vision, update machine diagram to 8 | system-vision.md | 2-3h |

### High Priority (Should complete in Epic 8)

| # | Action | Files Affected | Estimated Effort |
|---|--------|----------------|------------------|
| 5 | Remove migration-specific rules section, update host inventory | constraints-and-rules.md | 1h |
| 6 | Add 3 hosts, mark nixos-unified deprecated, add Pattern A term | glossary.md | 1h |
| 7 | Update 8-machine fleet, remove current/target framing | deployment-requirements.md | 1-2h |
| 8 | Reframe migration functions as historical, add current operations | functional-hierarchy.md | 2h |
| 9 | Update UC-007 as historical, update examples to 8 machines | usage-model.md | 1-2h |
| 10 | Update ADR-0003 or create ADR-0017 for dendritic overlay patterns | ADR-0003 | 2-3h |

### Medium Priority (Should address)

| # | Action | Files Affected | Estimated Effort |
|---|--------|----------------|------------------|
| 11 | Update risk statuses to reflect Epics 1-7 completion | risk-list.md | 1h |
| 12 | Update SC-010 to reflect migration completion | system-constraints.md | 0.5h |

### Low Priority (Nice to have)

| # | Action | Files Affected | Estimated Effort |
|---|--------|----------------|------------------|
| 13 | Update nixos-unified status to "deprecated Nov 2024" | stakeholders.md | 0.25h |
| 14 | Update measurement examples to reference 8 machines | quality-requirements.md | 0.5h |
| 15 | Note migration completion in overview | requirements/index.md | 0.25h |

### New ADRs Recommended

| ADR Number | Title | Justification |
|------------|-------|---------------|
| ADR-0017 | Dendritic Flake-Parts Architecture | Document migration from nixos-unified to dendritic pattern |
| ADR-0018 | Clan-Core Integration Patterns | Document clan inventory, vars, services integration |
| ADR-0019 | Multi-Platform Configuration Strategy | Document nix-darwin + nixos + home-manager coordination |
| ADR-0020 | terranix Infrastructure Provisioning | Document GCP/Hetzner provisioning decisions |

## Verification Evidence

### Deprecated Pattern Search Results

Commands executed during audit to verify findings:

```bash
# Verify nixos-unified references exist in development docs
rg "nixos-unified" packages/docs/src/content/docs/development/
# Result: Found in multiple context, requirements, and ADR files

# Verify configurations/ references
rg "configurations/" packages/docs/src/content/docs/development/
# Result: Found in domain-model.md, ADR-0003

# Verify current overlay location
ls modules/nixpkgs/overlays/
# Result: Confirmed current location is modules/nixpkgs/overlays/, not overlays/
```

### Audit Methodology

1. Each file read completely (no offset/limit)
2. Every staleness claim backed by specific line numbers or quoted text
3. Status classification: current (accurate), stale (outdated but salvageable), obsolete (should delete)
4. Priority based on impact: critical (blocks work), high (affects understanding), medium (inaccurate), low (minor)

## Conclusion

The AMDiRE development documentation is 62.5% current following Epics 1-7 completion.
The primary staleness pattern is **current/target state inversion** where documentation describes the completed dendritic + clan architecture as "target" and deprecated nixos-unified as "current."

Addressing the 4 critical-priority files and 6 high-priority files would bring currency to ~90%.
Creating the 4 recommended new ADRs would close the identified traceability gaps.

Total estimated effort for all recommended actions: **18-24 hours** (aligns with original Phase 2 scope).
