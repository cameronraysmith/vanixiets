---
title: "Decision: Defer Story 1.2 (Dendritic Pattern) - Infrastructure First"
---

**Date**: 2025-11-03
**Status**: Accepted
**Context**: Story 1.1 completion and Epic 1 sequencing

## Decision

Defer Story 1.2 (Implement dendritic flake-parts pattern in test-clan) and proceed directly to Story 1.3 (Configure clan inventory), following the infrastructure-first approach.

## Rationale

### Infrastructure-first strategy is primary

**From Story 1.1 completion**:
- test-clan repository successfully migrated to flake-parts.lib.mkFlake
- clan-core.flakeModules.default integrated ✅
- terranix.flakeModule imported ✅
- All infrastructure inputs configured (terranix, disko, srvos) ✅

**From Epic 1 restructuring (2025-11-03 12:58-13:06)**:
- PRIMARY objective: Deploy infrastructure using clan-infra's proven terranix + flake-parts patterns
- SECONDARY objective: Dendritic pattern optimization (optional)
- Real infrastructure deployment (Hetzner + GCP VMs) is the validation goal

### Dependency chain

Story 1.4 (Hetzner terraform config) has **Prerequisites: Story 1.3 (inventory configured)**:
- Story 1.3 defines machine inventory (hetzner-vm, gcp-vm)
- Story 1.3 configures clan service instances
- Story 1.4 creates terraform configuration that references those machines
- Cannot skip Story 1.3

### Dendritic pattern can be refactored later

**From clan-infra analysis**:
- clan-infra uses manual imports (not import-tree) which is a proven alternative
- Dendritic pattern is an optimization, not a requirement
- Infrastructure patterns are NON-NEGOTIABLE (proven in production)
- Dendritic pattern can be added via refactoring AFTER infrastructure works

### Risk reduction

**Minimize compound complexity**:
- Implementing dendritic pattern + infrastructure simultaneously increases debugging surface
- If issues arise, harder to isolate whether problem is dendritic vs infrastructure
- Incremental approach: validate infrastructure patterns first, then optimize structure

## Consequences

### Positive

1. **Faster path to infrastructure validation** - Direct progress on primary objective
2. **Reduced risk** - Proven patterns (clan-infra) without experimental optimization
3. **Clear fallback** - If dendritic conflicts discovered later, infrastructure already working
4. **Learning opportunity** - Validate core patterns before adding complexity

### Negative

1. **Potential rework** - If dendritic pattern adopted later, may need refactoring
2. **Deferred optimization** - Won't test dendritic pattern in Phase 0
3. **Decision debt** - Need to revisit dendritic pattern decision in Story 1.11 (findings)

### Mitigation

- Story 1.11 (Document integration findings) will assess dendritic pattern viability
- Story 1.2 status: "deferred" (not "cancelled") - can revisit if time permits
- Story 1.12 (GO/NO-GO decision) will determine if dendritic pattern is valuable for production

## Implementation

### Sprint flow update

**Previous flow**:
```
1.1 → 1.2 → 1.3 → 1.4 → ...
```

**New flow**:
```
1.1 ✅ → 1.3 (next) → 1.4 → 1.5 → ... → 1.2 (if time/value)
```

### sprint-status.yaml changes

- Story 1.2: `backlog` → `deferred` with comment explaining deferral
- Story 1.3: Remains `backlog`, becomes next in sequence after 1.1 review
- Added strategic decision comment at Epic 1 level

### Story 1.1 completion notes

Recommendation captured in story file:
> **Next steps recommendation**: SKIP Story 1.2 (dendritic pattern) and proceed directly to Story 1.4 (Hetzner terraform config).
> Reasoning: Infrastructure deployment is primary objective, dendritic pattern can be refactored later if desired after infrastructure works.

**Correction**: Actually proceed to Story 1.3 (clan inventory) first, as it's a prerequisite for Story 1.4.

## Review criteria

This decision should be revisited in:
- **Story 1.11**: Document whether dendritic pattern would have added value
- **Story 1.12**: GO/NO-GO decision considers dendritic pattern for production nix-config

## References

- Story 1.1 completion: docs/notes/development/work-items/1-1-prepare-existing-test-clan-repository-for-validation.md
- Epic 1 restructuring: docs/notes/development/epic-1-infrastructure-restructure-proposal.md
- clan-infra pattern: docs/notes/implementation/clan-infra-terranix-pattern.md
- Integration plan: docs/notes/clan/integration-plan.md
