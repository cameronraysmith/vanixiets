---
title: Project scope
---

## Problem description

Managing personal infrastructure across multiple platforms (macOS, NixOS) with reproducible, type-safe configurations presents inherent complexity.
Current architecture uses flake-parts with nixos-unified for directory-based autowiring, which provides basic modularity but limits type safety through module system.
The system lacks systematic multi-host management capabilities, relying on manual coordination between independent host configurations.
Secret management via sops-nix works but requires manual processes without declarative generation patterns.
Cross-platform module composition (darwin + nixos + home-manager) requires specialArgs pass-through, bypassing module system type checking.

## Statement of intent

Migrate from flake-parts + nixos-unified architecture to dendritic flake-parts pattern with clan-core integration.
Maximize type safety by adopting "every file is a flake-parts module" organizational pattern, eliminating specialArgs anti-pattern.
Enable systematic multi-host management through clan's inventory system, service instances, and overlay networking (zerotier).
Adopt declarative secrets management through clan vars system with automatic generation and deployment.
Preserve existing multi-channel nixpkgs resilience patterns (surgical fixes without system-wide rollback).
Maintain all current functionality while gaining enhanced modularity, type safety, and multi-host coordination capabilities.

## Current state architecture

**Foundation**: flake-parts (modular composition) + nixos-unified (directory-based autowiring)

**Repository structure**:
- `flake.nix` uses `flake-parts.lib.mkFlake` with auto-wired imports from `./modules/flake-parts/`
- `configurations/{darwin,home,nixos}/` host-specific configurations via nixos-unified autowire
- `modules/{darwin,home,nixos}/` modular system and home-manager configurations
- `secrets/` sops-nix with age encryption for secret management
- `overlays/`, `packages/` custom package definitions and multi-channel resilience

**Current hosts** (single-user, multiple darwin workstations):
- `stibnite` (darwin, aarch64) primary daily workstation
- `blackphos` (darwin, aarch64) secondary development environment
- `rosegold` (darwin, aarch64) testing and experimental
- `argentum` (darwin, aarch64) testing and backup
- CI validation mirrors: `stibnite-nixos`, `blackphos-nixos`, `orb-nixos`

**Key capabilities**:
- Platform support: macOS (nix-darwin), NixOS, standalone home-manager
- Multi-channel resilience: surgical package fixes without holding back entire channel
- Secrets management: sops-nix with age encryption
- Development environment: direnv integration, just task runner
- CI/CD: GitHub Actions with cachix, automated testing

**Architectural decisions** (see ADRs):
- ADR-0001: Claude Code multi-profile system
- ADR-0004: Monorepo structure (single packages/ directory)
- ADR-0009: Nix flake-based development environment
- ADR-0011: SOPS secrets management (age encryption)
- ADR-0014: Design principles (framework independence, type safety, bias toward removal)

## Target state architecture

**Foundation**: dendritic flake-parts pattern + clan-core integration

**Dendritic flake-parts pattern**:
- Every Nix file is a flake-parts module contributing to `flake.modules.*` namespace
- Eliminates specialArgs pass-through in favor of `config.flake.*` access
- import-tree auto-discovery replaces manual directory scanning
- Maximum type safety through consistent module system usage
- Cross-cutting concerns: single module can target multiple configuration classes (darwin + nixos + home-manager)

**Clan-core capabilities**:
- **Inventory system**: Abstract service layer for multi-machine coordination via tags, roles, instances
- **Vars system**: Declarative secret and file generation with automatic deployment
- **Service instances**: Multiple instances of same service type with role-based configuration
- **Overlay networking**: Zerotier VPN for secure inter-host communication
- **Multi-host orchestration**: Coordinated deployment and configuration management

**Planned infrastructure**:
- `cinnabar` (nixos, x86_64) Hetzner Cloud VPS as foundation infrastructure, zerotier controller, always-on core services
- Existing darwin hosts migrated progressively: blackphos → rosegold → argentum → stibnite
- Five-machine zerotier overlay network for secure communication

**Migration approach**: Validation-first, then VPS infrastructure, then progressive darwin host migration
- **Phase 0**: Validate dendritic + clan integration in test-clan/ repository (isolated testing)
- **Phase 1**: Deploy cinnabar VPS using validated patterns (foundation infrastructure)
- **Phase 2**: Migrate blackphos (establish darwin patterns)
- **Phase 3**: Migrate rosegold (validate pattern reusability)
- **Phase 4**: Migrate argentum (final validation)
- **Phase 5**: Migrate stibnite (primary workstation, last after all others proven stable)
- **Phase 6**: Remove nixos-unified, complete migration

**Strategic rationale**:
- **Type safety**: Nix lacks native type system; module system provides type checking at evaluation time; dendritic maximizes module system usage
- **Multi-host management**: Current architecture handles each host independently; clan provides coordinated multi-machine management
- **Secrets management**: Move from manual sops-nix to declarative clan vars with generation and deployment automation
- **Modularity**: Dendritic pattern enables clearer feature isolation and cross-platform module composition
- **Proven patterns**: Both dendritic and clan have production deployments (drupol-dendritic-infra, clan-infra)

## Architectural compatibility analysis

**Why abandon nixos-unified**:
- nixos-unified uses specialArgs + directory-based autowire
- Dendritic eliminates specialArgs in favor of `config.flake.*` namespace
- These approaches are mutually exclusive (cannot coexist cleanly)
- clan-infra production infrastructure uses clan + flake-parts with manual imports, not nixos-unified

**Why dendritic + clan are compatible**:
- Both use flake-parts as foundational architecture
- Both eliminate specialArgs antipattern (clan uses minimal `{ inherit inputs; }` for framework integration)
- Dendritic's `flake.modules.*` namespace pairs naturally with clan's inventory system
- Both support SOPS secrets (clan uses sops-nix internally)
- Both emphasize modular, type-safe configurations
- import-tree auto-discovery works seamlessly with clan modules

**Priority hierarchy when conflicts arise**:
1. **Primary**: Clan functionality (non-negotiable) - all clan features must work correctly
2. **Secondary**: Dendritic flake-parts pattern (best-effort) - apply where feasible without compromising clan
3. **Tertiary**: Pattern purity (flexible) - some specialArgs acceptable if clan requires, pragmatism over orthodoxy

## Risk mitigation strategy

**Phase 0 validation purpose**: No production examples exist combining dendritic + clan patterns.
test-clan/ repository validates integration in minimal environment before infrastructure commitment.
Reduces compound debugging complexity across 8 simultaneous layers (dendritic, clan, terraform, hetzner, disko, LUKS, zerotier, NixOS).
Expected outcome: proven patterns ready for cinnabar deployment with confidence.

**Progressive migration benefits**:
- Migrate non-primary machines first (blackphos, rosegold, argentum)
- Keep stibnite on nixos-unified until others proven stable
- Each host migration can be rolled back independently
- Multi-machine testing possible with multiple test hosts
- Each phase validates patterns before proceeding to next

**Stability requirements**: Each host must remain stable for 1-2 weeks before migrating next host.

**Rollback strategy**: Preserve nixos-unified configurations/ directory until all hosts migrated, enabling per-host rollback.

## Conclusion

Current architecture (flake-parts + nixos-unified) works reliably but lacks type safety optimization and multi-host coordination.
Target architecture (dendritic + clan) maximizes type safety through deeper module system integration and enables systematic multi-host management.
Migration follows validation-first approach with progressive host-by-host deployment, minimizing risk to primary workstation.
Success depends on careful validation at each phase, stability monitoring between phases, and willingness to adjust or rollback if issues arise.
