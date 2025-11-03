---
title: Goals and objectives
---

This document captures goals issued by stakeholders, organized by category.
Goals build a hierarchy and can influence each other through conflicts, constraints, or support relationships.

## Business goals

These goals focus on the overall value and sustainability of the infrastructure.

###

 G-B01: Reliable personal infrastructure

**Description**: Maintain stable, dependable systems for daily personal and professional computing.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- System uptime >99% for daily-use hosts
- Configuration changes don't break existing workflows
- Rollback available when issues occur
- Critical workflows always functional

**Dependencies**: None (top-level goal)

**Supports**: All other goals

**Status**: Ongoing

### G-B02: Sustainable maintenance burden

**Description**: Keep configuration maintainability within reasonable time investment.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Configuration updates require <2 hours/week average
- Upstream changes can be integrated without major rewrites
- Patterns are clear and documented for future reference
- Technical debt addressed regularly

**Dependencies**: G-S01 (maintainable codebase structure)

**Supports**: G-B01 (reliable infrastructure)

**Status**: Ongoing

### G-B03: Template value for community

**Description**: Provide working, forkable configuration as reference for others.

**Stakeholder**: Template users, community

**Success criteria**:
- Repository serves as both working deployment and template
- Documentation explains patterns and decisions
- Generic naming allows easy forking
- Examples demonstrate common configuration tasks

**Dependencies**: G-S02 (clear, idiomatic patterns)

**Supports**: Community knowledge sharing

**Status**: Ongoing, formalized via ADR-0014 (template duality principle)

## Usage goals

These goals focus on how the system is intended to be used.

### G-U01: Efficient development workflows

**Description**: Provide productive development environment across all hosts.

**Stakeholder**: Developer (crs58)

**Success criteria**:
- Development tools available without manual installation
- Consistent environment across all hosts
- Fast shell startup (<500ms)
- Just recipes for common tasks work reliably

**Dependencies**: G-S05 (development environment management)

**Supports**: G-B01 (reliable infrastructure)

**Status**: Achieved in current state, must be preserved during migration

### G-U02: Multi-host coordination

**Description**: Enable coordinated management of multiple hosts with shared services and configurations.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Single source of truth for multi-host configuration
- Changes propagate to all relevant hosts
- Host-specific overrides remain clear and maintainable
- Service instances can span multiple hosts

**Dependencies**: G-S06 (clan-core integration)

**Conflicts**: Current architecture (manual per-host management)

**Supports**: G-B01 (reliable infrastructure), G-U06 (overlay networking)

**Status**: Target state (not yet achieved, migration in progress)

### G-U03: Declarative secrets management

**Description**: Manage secrets through declarative generation and deployment, not manual processes.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Secrets generated automatically where possible
- Deployment integrated with configuration activation
- Clear visibility into which secrets exist for each host
- Secret rotation simplified through regeneration

**Dependencies**: G-S07 (clan vars system)

**Conflicts**: Current manual sops-nix approach

**Supports**: G-B02 (sustainable maintenance)

**Status**: Target state (migration to clan vars planned)

### G-U04: Cross-platform module composition

**Description**: Share modules across darwin, nixos, and home-manager without duplication.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Single module can target multiple platforms
- Clear separation of platform-specific vs shared code
- No code duplication for cross-cutting concerns
- Module composition explicit and type-safe

**Dependencies**: G-S03 (dendritic flake-parts pattern)

**Supports**: G-B02 (sustainable maintenance), G-S01 (maintainable structure)

**Status**: Partially achieved (current architecture has some duplication), target state improves this

### G-U05: Surgical package fixes without system rollback

**Description**: Fix individual broken packages without rolling back entire system to older channel.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Can use stable channel for single package while rest of system on unstable
- Can apply upstream patches to individual packages
- Can use custom build overrides when necessary
- No need to hold back entire channel for one package

**Dependencies**: None (independent architectural feature)

**Supports**: G-B01 (reliable infrastructure)

**Status**: Achieved in current state (multi-channel resilience), must be preserved during migration

**Reference**: ADR nixpkgs-hotfixes, `docs/development/architecture/nixpkgs-hotfixes.md`

### G-U06: Secure overlay networking

**Description**: Enable secure communication between hosts via private overlay network.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Zerotier VPN connects all hosts
- Encrypted communication between hosts
- Reachable even when hosts on different networks
- Automatic reconnection on network changes

**Dependencies**: G-S06 (clan-core integration), VPS infrastructure (cinnabar as controller)

**Supports**: G-U02 (multi-host coordination)

**Status**: Target state (zerotier via clan planned in Phase 1)

### G-U07: Fast, cached builds

**Description**: Minimize build times through effective caching strategies.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Cachix integration for binary caches
- Local build caching functional
- CI builds push to cache
- Common operations complete in <2 minutes

**Dependencies**: None (independent optimization)

**Supports**: G-U01 (efficient workflows)

**Status**: Achieved (cachix integrated), ongoing optimization

## System goals

These goals focus on system architecture, design, and technical properties.

### G-S01: Maintainable codebase structure

**Description**: Organize code for clarity, searchability, and long-term maintenance.

**Stakeholder**: User/maintainer (crs58), potential contributors

**Success criteria**:
- File organization is intuitive and discoverable
- Module dependencies are explicit
- Code follows consistent patterns
- Documentation explains architectural decisions

**Dependencies**: G-S02 (clear patterns)

**Supports**: G-B02 (sustainable maintenance), G-B03 (template value)

**Status**: Current state adequate, target state (dendritic) improves organization

### G-S02: Clear, idiomatic patterns

**Description**: Follow Nix ecosystem best practices and community conventions.

**Stakeholder**: User/maintainer (crs58), template users

**Success criteria**:
- Patterns match upstream project conventions (flake-parts, clan, darwin, home-manager)
- Code readable by experienced Nix users
- No heavy patching or forking of upstream projects
- Architectural decisions documented in ADRs

**Dependencies**: None (guideline-level goal)

**Supports**: G-S01 (maintainable structure), G-B03 (template value)

**Status**: Ongoing adherence to best practices

### G-S03: Maximum type safety through module system

**Description**: Leverage Nix module system maximally to provide type checking and validation.

**Stakeholder**: User/maintainer (crs58)

**Rationale**:
- Nix language provides no native compile-time type checking
- Module system provides type checking at evaluation time
- dendritic pattern maximizes module system usage by making every file a module

**Success criteria**:
- Configuration errors caught at evaluation, not runtime
- Module options have explicit types
- Invalid configurations rejected early
- Clear error messages guide fixes

**Dependencies**: G-S04 (dendritic pattern adoption)

**Supports**: G-B01 (reliable infrastructure), G-S01 (maintainable structure)

**Status**: Partially achieved (current flake-parts usage), target state maximizes this

**Reference**: Strategic rationale in migration plan (type safety through module system maximization)

### G-S04: Dendritic flake-parts pattern adoption

**Description**: Adopt "every file is a flake-parts module" organizational pattern.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- All configuration files are flake-parts modules
- Values shared via `config.flake.*`, not specialArgs
- import-tree auto-discovery functional
- Cross-cutting concerns enabled (one module, multiple targets)

**Dependencies**: None (architectural decision)

**Conflicts**: nixos-unified (specialArgs-based autowiring)

**Supports**: G-S03 (maximum type safety), G-S01 (maintainable structure), G-U04 (cross-platform composition)

**Status**: Target state (migration planned), incompatible with current nixos-unified approach

**Reference**: dendritic-flake-parts README, pattern documentation

### G-S05: Comprehensive development environment

**Description**: Provide all development tools via Nix with direnv integration.

**Stakeholder**: Developer (crs58)

**Success criteria**:
- All development tools in nix development shell
- Automatic environment activation via direnv
- Just task runner for common operations
- Playwright browsers available for testing

**Dependencies**: None (existing capability)

**Supports**: G-U01 (efficient workflows)

**Status**: Achieved (ADR-0009: Nix flake-based development environment)

### G-S06: Clan-core integration

**Description**: Integrate clan-core for multi-host management, inventory, vars, and services.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Clan flakeModules integrated into flake
- Inventory system defines machines, tags, roles
- Vars system manages secrets declaratively
- Service instances coordinate across hosts
- CLI tools (`clan` command) functional

**Dependencies**: None (architectural decision)

**Conflicts**: nixos-unified (mutually exclusive approaches)

**Supports**: G-U02 (multi-host coordination), G-U03 (declarative secrets), G-U06 (overlay networking)

**Status**: Target state (migration planned)

### G-S07: Clan vars system adoption

**Description**: Migrate from manual sops-nix to declarative clan vars for secret management.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Generators define secret creation logic
- Automatic deployment to `/run/secrets/`
- Proper permissions and encryption
- DAG composition for complex secret dependencies

**Dependencies**: G-S06 (clan-core integration)

**Conflicts**: Current manual sops-nix workflow

**Supports**: G-U03 (declarative secrets)

**Status**: Target state (migration planned incrementally per host)

### G-S08: Multi-channel nixpkgs resilience preservation

**Description**: Maintain ability to use multiple nixpkgs channels for package-specific fixes.

**Stakeholder**: User/maintainer (crs58)

**Success criteria**:
- Can use stable channel packages when needed
- Can apply surgical fixes without system-wide rollback
- Clear patterns for overlay composition
- Documented in ADRs and guides

**Dependencies**: None (existing architectural feature)

**Supports**: G-U05 (surgical package fixes), G-B01 (reliable infrastructure)

**Status**: Achieved, must be preserved during migration

**Reference**: ADR nixpkgs-hotfixes, docs/development/architecture/nixpkgs-hotfixes.md

## Goal hierarchy and relationships

### Hierarchy visualization

```
Business Goals
├── G-B01: Reliable personal infrastructure
│   ├── Supports: All other goals
│   └── Dependencies: G-S03, G-U01, G-U05, G-S08
├── G-B02: Sustainable maintenance burden
│   ├── Supports: G-B01
│   └── Dependencies: G-S01, G-S02, G-U03
└── G-B03: Template value for community
    ├── Supports: Community
    └── Dependencies: G-S01, G-S02

Usage Goals
├── G-U01: Efficient development workflows
│   ├── Supports: G-B01
│   └── Dependencies: G-S05
├── G-U02: Multi-host coordination
│   ├── Supports: G-B01, G-U06
│   └── Dependencies: G-S06
├── G-U03: Declarative secrets management
│   ├── Supports: G-B02
│   └── Dependencies: G-S07
├── G-U04: Cross-platform module composition
│   ├── Supports: G-B02, G-S01
│   └── Dependencies: G-S03
├── G-U05: Surgical package fixes
│   ├── Supports: G-B01
│   └── Dependencies: G-S08
├── G-U06: Secure overlay networking
│   ├── Supports: G-U02
│   └── Dependencies: G-S06, VPS infrastructure
└── G-U07: Fast, cached builds
    ├── Supports: G-U01
    └── Dependencies: None

System Goals
├── G-S01: Maintainable codebase structure
│   ├── Supports: G-B02, G-B03
│   └── Dependencies: G-S02
├── G-S02: Clear, idiomatic patterns
│   ├── Supports: G-S01, G-B03
│   └── Dependencies: None
├── G-S03: Maximum type safety
│   ├── Supports: G-B01, G-S01
│   └── Dependencies: G-S04
├── G-S04: Dendritic pattern adoption
│   ├── Supports: G-S03, G-S01, G-U04
│   └── Conflicts: nixos-unified
├── G-S05: Comprehensive dev environment
│   ├── Supports: G-U01
│   └── Dependencies: None (achieved)
├── G-S06: Clan-core integration
│   ├── Supports: G-U02, G-U03, G-U06
│   └── Conflicts: nixos-unified
├── G-S07: Clan vars system
│   ├── Supports: G-U03
│   └── Dependencies: G-S06
└── G-S08: Multi-channel resilience
    ├── Supports: G-U05, G-B01
    └── Dependencies: None (achieved)
```

### Conflicts and resolutions

**Conflict**: G-S04 (dendritic) + G-S06 (clan) vs. current nixos-unified architecture

**Resolution**: Migrate to dendritic + clan, abandon nixos-unified
- Dendritic and clan both eliminate specialArgs antipattern
- Both use flake-parts as foundation
- nixos-unified incompatible with this direction
- Migration follows phased approach to minimize risk

**Conflict**: G-U03 (declarative secrets) vs. current manual sops-nix

**Resolution**: Migrate to clan vars incrementally
- Keep sops-nix for external secrets (API tokens)
- Use clan vars for generated secrets (SSH keys, passwords)
- Hybrid approach during transition
- Full migration optional (both systems can coexist)

**Conflict**: G-U02 (multi-host coordination) vs. current per-host management

**Resolution**: VPS infrastructure enables always-on coordination
- Deploy cinnabar as foundation (zerotier controller)
- Connect darwin hosts as peers
- Single source of truth in clan inventory
- Progressive per-host migration reduces risk

## Goals tracking and validation

### Achieved goals (current state)

- ✅ G-S05: Comprehensive development environment (ADR-0009)
- ✅ G-S08: Multi-channel resilience (nixpkgs-hotfixes pattern)
- ✅ G-U05: Surgical package fixes (via G-S08)
- ✅ G-U07: Fast, cached builds (cachix integration)
- ✅ G-U01: Efficient development workflows (current state functional)
- ✅ G-B01: Reliable infrastructure (current state stable)

### In-progress goals (migration target)

- 🔄 G-S04: Dendritic pattern adoption (Phase 0-6 planned)
- 🔄 G-S06: Clan-core integration (Phase 0-6 planned)
- 🔄 G-S07: Clan vars system (migration incremental per host)
- 🔄 G-U02: Multi-host coordination (requires clan integration)
- 🔄 G-U03: Declarative secrets (requires clan vars)
- 🔄 G-U06: Overlay networking (zerotier via clan, Phase 1+)
- 🔄 G-S03: Maximum type safety (dendritic maximizes module system)
- 🔄 G-U04: Cross-platform composition (dendritic enables)

### Ongoing goals

- ⏳ G-B02: Sustainable maintenance (continuous)
- ⏳ G-B03: Template value (continuous improvement)
- ⏳ G-S01: Maintainable structure (evolving with migration)
- ⏳ G-S02: Clear patterns (refining during migration)

## Migration impact on goals

### Goals preserved during migration

Must not regress:
- G-S08: Multi-channel resilience (preserve nixpkgs hotfixes pattern)
- G-U05: Surgical package fixes (preserve overlay composition)
- G-U01: Efficient workflows (all functionality maintained)
- G-B01: Reliable infrastructure (stability priority)

### Goals enabled by migration

Achieved through dendritic + clan:
- G-S03: Maximum type safety (dendritic maximizes module system)
- G-U02: Multi-host coordination (clan inventory and services)
- G-U03: Declarative secrets (clan vars)
- G-U04: Cross-platform composition (dendritic cross-cutting)
- G-U06: Overlay networking (clan zerotier)

### Goal validation criteria

Each migration phase validates relevant goals:
- **Phase 0**: Validate G-S04 + G-S06 compatibility (dendritic + clan integration)
- **Phase 1**: Validate G-U06 (zerotier), G-S07 (vars on NixOS)
- **Phase 2**: Validate G-U04 (darwin cross-platform), G-S03 (type safety on darwin)
- **Phase 3-4**: Validate G-U02 (multi-host coordination) with multiple darwin hosts
- **Phase 5**: Validate G-U01 (workflows preserved on primary workstation)
- **Phase 6**: Confirm all goals achieved, G-B02 (maintenance sustainable)

## References

- ADR-0009: Nix development environment
- ADR-0014: Design principles
- nixpkgs-hotfixes: Multi-channel resilience pattern
- Migration plan: Phased dendritic + clan adoption
- dendritic pattern: Type safety through module system maximization
- clan-core: Multi-host coordination capabilities
