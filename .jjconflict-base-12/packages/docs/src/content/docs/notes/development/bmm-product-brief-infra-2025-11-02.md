---
title: "Product Brief: infra"
---

**Date:** 2025-11-02
**Author:** Dev
**Context:** Level 3 Brownfield Infrastructure Migration

---

## Executive Summary

[Initial draft - will refine]

This product brief captures the vision for migrating the nix-config infrastructure from nixos-unified to a dendritic flake-parts pattern with clan-core integration.
The migration addresses the need for improved type safety, better organizational patterns, and multi-machine coordination capabilities while managing 1 VPS (cinnabar) and 4 darwin workstations (blackphos, rosegold, argentum, stibnite).

The critical challenge is that no proven examples exist combining dendritic flake-parts + clan patterns, requiring a validation-first approach with progressive rollout.

---

## Core Vision

### Problem Statement

The current nix-config infrastructure uses nixos-unified with flake-parts, which presents several architectural limitations:

**Type safety gaps**: Nix language lacks native compile-time type checking, and the current architecture relies on specialArgs pass-through which bypasses module system type checking, creating implicit dependencies and making it difficult to track value sources.

**Organizational complexity**: Directory-based autowire (`modules/{darwin,home,nixos}/`) creates unclear feature boundaries and makes cross-cutting concerns (modules targeting multiple systems) difficult to implement cleanly.

**Limited multi-machine coordination**: Current setup lacks robust mechanisms for managing secrets, service coordination, and network configuration across multiple machines (1 VPS + 4 darwin hosts).

**Migration to better patterns**: The dendritic flake-parts pattern offers maximum type safety through consistent module usage and clear interfaces via `config.flake.*` namespace, while clan-core provides declarative multi-machine coordination, vars/secrets management, and service instances with roles.

**Unproven combination**: Despite both patterns being proven individually (dendritic flake-parts in production infrastructures, clan in clan-infra), no documented examples exist combining them, creating architectural uncertainty that must be resolved through validation before production deployment.

### Problem Impact

**Development velocity**: Implicit dependencies and unclear module boundaries slow down configuration changes and increase debugging time when issues arise.

**Maintainability risk**: As infrastructure scales across 5 machines, the lack of type safety and clear interfaces compounds maintenance complexity.

**Operational overhead**: Manual secrets management and lack of coordinated service deployment across machines increases operational burden.

**Migration risk**: Without validation, deploying unproven architectural combinations directly to production VPS could create compound debugging complexity across 8+ simultaneous layers (dendritic flake-parts, clan, terraform, hetzner, disko, LUKS, zerotier, NixOS).

**Cost of delay**: Continuing with current architecture means missing benefits of improved type safety, better organization, and multi-machine coordination while technical debt accumulates.

### Proposed Solution

Implement a progressive, validation-first migration strategy that combines the dendritic flake-parts pattern with clan-core integration:

**Phase 0 - Pattern Validation** (test-clan repository): Create minimal test environment to validate dendritic + clan integration works before infrastructure commitment. Determine optimal balance between dendritic optimization and clan functionality. Document integration patterns and acceptable compromises. This de-risks the entire migration by proving the architectural combination in isolation.

**Phase 1 - VPS Infrastructure** (cinnabar): Deploy Hetzner Cloud VPS using validated patterns from Phase 0. Establish always-on infrastructure with zerotier controller and core services. Validates complete stack (dendritic + clan + terraform + infrastructure) on clan's native platform (NixOS) before touching darwin hosts. Provides stable foundation independent of workstation power state.

**Phase 2-4 - Progressive Darwin Migration**: Migrate darwin workstations incrementally (blackphos → rosegold → argentum) to establish and validate patterns. Each host connects to cinnabar's zerotier network. 1-2 weeks stability validation between migrations. Primary workstation (stibnite) migrated last only after all others proven stable.

**Phase 5 - Primary Workstation**: Migrate stibnite (primary daily workstation) only after 4-6 weeks of proven stability across other hosts.

**Phase 6 - Cleanup**: Remove nixos-unified and legacy infrastructure once all migrations complete successfully.

**Core architectural principles**:

- Maximize type safety through module system (every file is a flake-parts module)
- Eliminate specialArgs pass-through in favor of `config.flake.*` access
- Clan functionality is non-negotiable (dendritic optimization applied where feasible)
- Pragmatism over orthodoxy (hybrid approaches acceptable if necessary)

### Key Differentiators

**Validation-first approach**: Unlike typical infrastructure migrations, Phase 0 validates the untested dendritic + clan combination in isolated test-clan repository before any production deployment, significantly reducing risk.

**VPS-first strategy**: Deploys always-on cloud infrastructure before darwin hosts, providing stable zerotier controller and validating patterns on clan's native platform (NixOS) before tackling darwin-specific integration challenges.

**Progressive validation gates**: Each host migration requires 1-2 weeks proven stability before proceeding, with explicit go/no-go decision frameworks and rollback procedures.

**Type safety maximization**: Leverages flake-parts module system to bring type checking to infrastructure configuration, addressing Nix's lack of native type system.

**Multi-machine declarative coordination**: clan-core inventory system, vars management, and service instances enable coordinated deployment across heterogeneous infrastructure (VPS + darwin workstations).

**Brownfield pragmatism**: Accepts hybrid approaches and compromises where pure patterns conflict with clan functionality, documented and justified rather than hidden.

---

## Target Users

### Primary Users

**Primary user**: Infrastructure administrator (Dev) managing personal/professional multi-machine development environment

**Current situation**: Managing 4 darwin workstations + 1 VPS through nix-config with nixos-unified, experiencing limitations in type safety, organizational clarity, and multi-machine coordination as infrastructure complexity grows.

**Specific frustrations**:

- Debugging configuration issues requires tracing implicit dependencies through specialArgs
- Directory-based organization makes it unclear where to place cross-cutting concerns
- Manual secrets management across machines is error-prone
- Lack of coordinated service deployment means manual coordination between hosts
- Fear of configuration changes breaking subtle dependencies

**What they'd value most**:

- Clear, type-safe interfaces between modules
- Declarative multi-machine coordination (one change deploys everywhere)
- Confidence that configurations will evaluate correctly before deployment
- Organizational patterns that scale as infrastructure grows
- Minimal operational overhead for secrets and service management

**Technical comfort level**: Expert (deep Nix knowledge, comfortable with experimental patterns, willing to validate unproven combinations)

---

## MVP Scope

### Core Features

**Phase 0 - Validation Environment** (test-clan):

- Minimal flake structure with clan-core + import-tree + flake-parts integration
- Test NixOS VM configuration using dendritic flake-parts pattern
- Clan inventory with single test machine
- Essential clan services (emergency-access, sshd, zerotier)
- Vars generation and deployment validation
- Documentation of integration findings and extracted patterns
- Go/no-go decision framework evaluation

**Phase 1 - VPS Infrastructure** (cinnabar):

- Terraform/terranix provisioning for Hetzner Cloud CX53
- NixOS configuration using validated dendritic + clan patterns
- Disko declarative partitioning with LUKS encryption
- Zerotier controller role
- SSH daemon with certificate-based authentication
- Emergency access configuration
- Clan vars deployment for VPS secrets

**Phase 2 - First Darwin Host** (blackphos):

- Convert darwin modules to dendritic flake-parts pattern (or validated hybrid)
- Clan inventory integration for darwin machine
- Zerotier peer role connecting to cinnabar controller
- Clan vars deployment for darwin secrets
- Preserve all existing functionality (no regressions)
- 1-2 week stability validation before proceeding

**Phase 3-4 - Multi-Darwin Validation** (rosegold, argentum):

- Replicate blackphos patterns for additional darwin hosts
- Validate pattern reusability (minimal customization needed)
- Test multi-machine coordination across 3-4 hosts
- Zerotier mesh network across all machines
- Progressive stability validation (1-2 weeks each)

**Phase 5 - Primary Workstation** (stibnite):

- Apply proven patterns to primary daily workstation
- Migrate only after 4-6 weeks total stability across other hosts
- Preserve all daily workflows and productivity
- Complete 5-machine coordinated infrastructure

**Core Infrastructure Components**:

- Dendritic flake-parts module structure (`flake.modules.{nixos,darwin,homeManager}.*`)
- Clan inventory defining all 5 machines with tags and machineClass
- Clan service instances (emergency-access, users, zerotier, sshd)
- Vars generators for secrets management
- import-tree auto-discovery for module loading
- Justfile-based CI/CD workflow matching local development

### Out of Scope for MVP

**Not included in initial migration**:

- UI/frontend work (infrastructure project, no graphical interfaces)
- Additional VPS infrastructure beyond cinnabar
- Migration of all secrets to clan vars (hybrid sops-nix + clan vars acceptable initially)
- Complex distributed services beyond basic zerotier networking
- Automated rollback mechanisms (manual rollback procedures documented instead)
- CI mirror hosts (stibnite-nixos, blackphos-nixos, orb-nixos) - defer to post-migration
- Full terraform state management automation (manual terraform operations acceptable)

**Deferred to future phases**:

- Complete elimination of sops-nix (hybrid approach acceptable long-term)
- Advanced clan service instances beyond essentials
- Automated testing infrastructure for all configurations
- Documentation website or formal user guides
- Performance optimization and benchmarking
- Cost optimization for VPS infrastructure

### MVP Success Criteria

**Phase 0 success** (proceed to Phase 1 if):

- test-clan flake evaluates and builds successfully
- Dendritic + clan integration proven feasible (no fundamental conflicts)
- Integration patterns documented with confidence
- Go/no-go framework evaluation shows "GO" or "CONDITIONAL GO"

**Phase 1 success** (proceed to Phase 2 if):

- cinnabar VPS deployed and operational
- Zerotier controller functional and reachable
- SSH access working with certificate-based auth
- Clan vars deployed correctly to /run/secrets/
- Stable for 1-2 weeks minimum

**Phase 2-4 success** (proceed to next host if):

- Host configuration builds and deploys successfully
- All existing functionality preserved (no regressions)
- Zerotier peer connects to cinnabar controller
- Multi-machine network communication functional
- Stable for 1-2 weeks minimum per host

**Phase 5 success** (complete migration if):

- stibnite operational with all daily workflows functional
- Productivity maintained or improved
- 5-machine zerotier network complete and stable
- Stable for 1-2 weeks minimum

**Overall MVP success**:

- All 5 machines migrated to dendritic + clan
- No critical regressions in functionality
- Multi-machine coordination operational
- Type safety improvements measurable (fewer evaluation errors)
- Maintainability improved (clearer module organization)
- Ready for Phase 6 cleanup (remove nixos-unified)

---

## Technical Preferences

**Platform choices**:

- NixOS for VPS infrastructure (cinnabar on Hetzner Cloud)
- nix-darwin for macOS workstations (all darwin hosts)
- home-manager for user environment management across all platforms

**Core technology stack**:

- flake-parts: Module system for flake organization
- clan-core: Multi-machine coordination and vars management
- import-tree: Automatic module discovery
- dendritic flake-parts pattern: Organizational pattern maximizing type safety
- terranix: Declarative Terraform configuration via Nix
- disko: Declarative disk partitioning
- srvos: Server hardening modules
- zerotier: VPN mesh networking across all machines

**Infrastructure services**:

- Hetzner Cloud: VPS hosting (CX53 instance, ~€24/month)
- SOPS + clan vars: Hybrid secrets management during transition
- SSH with certificate-based auth: Secure access across zerotier network

**Development workflow**:

- Justfile: Universal command interface for build/check/test operations
- Local-CI parity: CI executes `nix develop -c just <command>` matching local dev
- Git for version control on `clan` branch
- Progressive deployment: test-clan → nix-config with per-host validation

**Integration requirements**:

- Must preserve all existing nix-config functionality
- Must maintain compatibility with home-manager modules
- Must support darwin-specific features (Homebrew, system preferences)
- Must enable rollback to nixos-unified configurations if needed

**Performance requirements**:

- Build times should not significantly regress from current nixos-unified setup
- System responsiveness must be maintained (especially on primary workstation stibnite)
- Network latency across zerotier mesh acceptable for development use (non-critical)

**Type safety goals**:

- Maximize use of flake-parts module system type checking
- Minimize specialArgs pass-through (framework values only: inputs, self)
- Prefer `config.flake.*` for application/user-defined values
- Document and justify any compromises to dendritic purity

---

## Risks and Assumptions

### Key Risks

**Architectural risk - Unproven pattern combination**:

- Risk: Dendritic + clan combination has no documented production examples
- Impact: May discover fundamental incompatibilities during implementation
- Likelihood: Medium (both work with flake-parts, but interaction unknown)
- Mitigation: Phase 0 validation in test-clan before infrastructure commitment, go/no-go decision framework, fallback to vanilla clan + flake-parts pattern if needed

**Technical risk - Darwin + clan integration**:

- Risk: Clan primarily targets NixOS, darwin support may have gaps
- Impact: May need workarounds or compromises for darwin-specific features
- Likelihood: Medium (some clan examples exist, but limited darwin + dendritic precedent)
- Mitigation: VPS-first validates clan on NixOS before darwin, blackphos validates darwin patterns first, can relax dendritic purity if necessary

**Operational risk - Primary workstation migration**:

- Risk: stibnite migration could disrupt daily productivity
- Impact: High (primary work environment, can't afford extended downtime)
- Likelihood: Low if validation gates respected (only if previous 4 hosts stable)
- Mitigation: Migrate stibnite last, require 4-6 weeks stability across other hosts, maintain rollback path, time migration for low-stakes period

**Complexity risk - Compound debugging**:

- Risk: Issues could span multiple layers (dendritic, clan, terraform, zerotier, etc.)
- Impact: Medium (increased debugging time, may need to isolate layers)
- Likelihood: Medium (complex system with many integration points)
- Mitigation: Progressive validation isolates layers (Phase 0 validates dendritic+clan, Phase 1 adds infrastructure, etc.), comprehensive logging and monitoring

**Cost risk - VPS infrastructure**:

- Risk: Hetzner Cloud costs (~€24/month) add ongoing operational expense
- Impact: Low (acceptable for always-on infrastructure benefits)
- Likelihood: Certain (ongoing cost inherent to VPS deployment)
- Mitigation: Cost is accepted trade-off for de-risked migration and operational benefits, can downgrade or terminate if architecture proves unsuitable

**Timeline risk - Migration takes longer than expected**:

- Risk: Validation gates or stability issues extend timeline beyond 8-12 weeks
- Impact: Medium (delayed benefits, extended dual-maintenance period)
- Likelihood: Medium (complex migration, unforeseen issues possible)
- Mitigation: Conservative timeline estimates, willingness to pause or slow down if needed, no hard deadlines forcing compromises

### Critical Assumptions

**Assumption: Dendritic + clan are fundamentally compatible**:

- Validation: Phase 0 explicitly tests this assumption
- Fallback: Use vanilla clan + flake-parts (proven in clan-infra) if incompatible

**Assumption: Clan vars can replace most sops-nix usage**:

- Validation: Test vars generation and deployment in Phase 0-1
- Fallback: Hybrid sops-nix + clan vars approach acceptable long-term

**Assumption: Zerotier mesh networking scales to 5 machines**:

- Validation: Progressive testing as each host joins (3-machine, 4-machine, 5-machine)
- Fallback: Alternative VPN solutions (tailscale, wireguard) if zerotier inadequate

**Assumption: Darwin-specific features work with clan**:

- Validation: blackphos (Phase 2) tests all darwin features (Homebrew, system prefs, etc.)
- Fallback: Can exclude incompatible features or use workarounds

**Assumption: Terraform/terranix provide adequate VPS provisioning**:

- Validation: Phase 1 VPS deployment tests complete provisioning workflow
- Fallback: Manual Hetzner Cloud provisioning if terranix inadequate

**Assumption: Type safety benefits justify migration complexity**:

- Validation: Ongoing evaluation throughout migration (clearer errors, better maintainability)
- Fallback: Can rollback if benefits don't materialize

**Assumption: 1-2 week stability gates are sufficient**:

- Validation: Monitor for issues during stability windows
- Fallback: Extend stability periods if issues discovered

**Assumption: Rollback to nixos-unified remains viable during migration**:

- Validation: Preserve nixos-unified configurations until Phase 6
- Fallback: Full migration rollback procedure documented if needed

### Open Questions Requiring Research

1. **Dendritic + clan specialArgs usage**: What's the minimal acceptable specialArgs for clan integration?
   - Research: Review clan-infra patterns, test in Phase 0
   - Decision gate: Phase 0 validation

2. **Home-manager integration with dendritic**: How to structure home-manager modules in dendritic pattern?
   - Research: Review dendritic examples, test with blackphos
   - Decision gate: Phase 2 (blackphos migration)

3. **Secrets migration strategy**: Full migration to clan vars or hybrid sops-nix + clan vars?
   - Research: Inventory current secrets, categorize by type (generated vs. external)
   - Decision gate: Phase 1 (determine strategy before progressive migration)

4. **Zerotier network topology**: What roles should each machine have?
   - Research: Zerotier clan service documentation
   - Decision: cinnabar=controller (always-on), darwin hosts=peers (validated in Phase 0-1)

5. **CI/CD strategy**: How to test darwin configurations in CI without darwin runners?
   - Research: Current CI setup, nix build vs. nix eval strategies
   - Decision gate: Phase 2 (establish CI patterns with blackphos)

6. **Module conversion**: Convert all modules at once or incrementally per host?
   - Research: Evaluate dendritic pattern migration strategies
   - Decision: Incrementally per host (enables per-host rollback)

7. **Performance benchmarks**: What metrics define acceptable performance?
   - Research: Baseline current build times and responsiveness
   - Decision gate: Throughout migration (measure at each phase)

---

## Timeline

### Phase 0: Pattern Validation (Week 0)

- Duration: 1 week
- Deliverable: test-clan repository with validated dendritic + clan integration
- Milestone: Go/no-go decision for Phase 1
- Dependencies: None (can start immediately)

### Phase 1: VPS Infrastructure (Weeks 1-3)

- Duration: 1 week deployment + 1-2 weeks stability monitoring
- Deliverable: Operational cinnabar VPS with zerotier controller
- Milestone: Stable VPS infrastructure ready for darwin connections
- Dependencies: Phase 0 GO decision

### Phase 2: First Darwin Host (Weeks 4-5)

- Duration: 1 week migration + 1-2 weeks stability monitoring
- Deliverable: blackphos migrated to dendritic + clan, connected to cinnabar
- Milestone: Darwin patterns established and validated
- Dependencies: Phase 1 stable for 1-2 weeks

### Phase 3: Second Darwin Host (Weeks 6-7)

- Duration: 1 week migration + 1-2 weeks stability monitoring
- Deliverable: rosegold migrated, 3-machine network operational
- Milestone: Pattern reusability validated
- Dependencies: Phase 2 stable for 1-2 weeks

### Phase 4: Third Darwin Host (Weeks 8-9)

- Duration: 1 week migration + 1-2 weeks stability monitoring
- Deliverable: argentum migrated, 4-machine network operational
- Milestone: Ready for primary workstation migration
- Dependencies: Phase 3 stable for 1-2 weeks

### Phase 5: Primary Workstation (Weeks 10-12)

- Duration: 1 week migration + 1-2 weeks stability monitoring
- Deliverable: stibnite migrated, 5-machine infrastructure complete
- Milestone: Migration complete, all hosts on dendritic + clan
- Dependencies: Phases 2-4 stable for 4-6 weeks total

### Phase 6: Cleanup (Week 13+)

- Duration: 1-2 weeks
- Deliverable: nixos-unified removed, legacy infrastructure cleaned up
- Milestone: Clean dendritic + clan architecture
- Dependencies: Phase 5 stable for 1-2 weeks

**Total estimated duration**: 13-15 weeks (conservative)
**Aggressive timeline**: 4-6 weeks (higher risk, requires all phases to proceed smoothly)

**Critical path dependencies**:

- Each phase blocks the next until stability validated
- Primary workstation (stibnite) cannot proceed until 4-6 weeks cumulative stability
- Cleanup cannot proceed until all hosts migrated and stable

**Timeline flexibility**:

- Can pause between phases if issues discovered
- Can extend stability monitoring if needed
- Can slow down or accelerate based on confidence and stability
- No hard deadlines forcing compromises

---

## Supporting Materials

### Existing Planning Documentation

**Comprehensive planning completed**:

- `docs/notes/clan/integration-plan.md`: Strategic planning, architectural rationale, detailed migration phases
- `docs/notes/clan/migration-assessment.md`: Host-by-host validation criteria, risk analysis
- `docs/notes/clan/phase-*.md`: Phase-specific implementation guides (to be created during execution)
- `docs/notes/prompts/clan-migration.md`: Technical context and interactive guide

**Reference repositories analyzed**:

- `~/projects/nix-workspace/clan-core/`: Clan monorepo (modules, CLI, documentation)
- `~/projects/nix-workspace/clan-infra/`: Production clan + flake-parts infrastructure (manual imports)
- `~/projects/nix-workspace/dendritic-flake-parts/`: Canonical dendritic pattern implementation
- `~/projects/nix-workspace/drupol-dendritic-infra/`: Production dendritic example
- `~/projects/nix-workspace/jfly-clan-snow/`: Darwin + clan example
- `~/projects/nix-workspace/mic92-clan-dotfiles/`: Comprehensive clan usage

**Technology documentation reviewed**:

- Clan architecture decisions, vars system, inventory documentation
- Dendritic flake-parts pattern README and examples
- flake-parts documentation
- Terraform/terranix patterns from clan-infra

### Current Infrastructure State

**Hosts managed**:

- `stibnite`: Primary darwin workstation (aarch64, migrate last)
- `blackphos`: Secondary darwin workstation (aarch64, migrate first)
- `rosegold`: Tertiary darwin workstation (aarch64, not in daily use)
- `argentum`: Quaternary darwin workstation (aarch64, not in daily use)
- `cinnabar`: VPS infrastructure (x86_64, to be deployed)

**Current tooling**:

- nixos-unified for flake-parts + directory autowire
- sops-nix for secrets management
- Manual terraform for any cloud provisioning (minimal current usage)
- Git on `clan` branch for migration work

**Deployment workflow**:

- `darwin-rebuild switch --flake .#<hostname>` for darwin hosts
- `nix build` and `nix flake check` for validation
- Justfile recipes for common operations

---

_This Product Brief captures the vision and requirements for the nix-config infrastructure migration to dendritic + clan._

_It was created by transforming comprehensive technical planning documentation into BMAD product brief format._

_Next: Architecture workflow will design the technical implementation based on this brief, followed by epic/story breakdown for phased execution._
