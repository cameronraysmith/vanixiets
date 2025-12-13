---
title: Project scope
---

## Problem description

Managing personal infrastructure across multiple platforms (macOS, NixOS) with reproducible, type-safe configurations presents inherent complexity.
Current architecture uses deferred module composition with clan integration, providing systematic multi-host management with maximized type safety through deep module system integration.
The system manages 8 machines across darwin and NixOS platforms with declarative secrets via clan vars, zerotier overlay networking, and coordinated service deployment.
This architecture eliminates specialArgs anti-patterns, enabling cross-platform module composition (darwin + nixos + home-manager) with full module system type checking.
Infrastructure coordination leverages clan's inventory system with tags, roles, and service instances for multi-machine orchestration.

## Statement of intent

Migration from flake-parts + nixos-unified architecture to deferred module composition with clan integration is complete.
Current infrastructure achieves maximum type safety through "every file is a flake-parts module" organizational pattern, eliminating specialArgs anti-pattern.
Systematic multi-host management operational through clan's inventory system, service instances, and overlay networking (zerotier).
Declarative secrets management deployed through clan vars system with automatic generation and deployment.
Multi-channel nixpkgs stable fallback patterns preserved (surgical fixes without system-wide rollback).
All original functionality maintained while gaining enhanced modularity, type safety, and multi-host coordination capabilities.

## Current state architecture

**Foundation**: deferred module composition + clan integration

**Deferred module composition**:
- Every Nix file is a flake-parts module contributing to `flake.modules.*` namespace
- Eliminates specialArgs pass-through in favor of `config.flake.*` access
- import-tree auto-discovery replaces manual directory scanning
- Maximum type safety through consistent module system usage
- Cross-cutting concerns: single module can target multiple configuration classes (darwin + nixos + home-manager)

**Clan capabilities**:
- **Inventory system**: Abstract service layer for multi-machine coordination via tags, roles, instances
- **Vars system**: Declarative secret and file generation with automatic deployment
- **Service instances**: Multiple instances of same service type with role-based configuration
- **Overlay networking**: Zerotier VPN for secure inter-host communication
- **Multi-host orchestration**: Coordinated deployment and configuration management

**Repository structure**:
- `flake.nix` uses `flake-parts.lib.mkFlake` with import-tree auto-discovery
- `modules/{darwin,nixos,home}/` modular configurations (deferred module composition)
- `machines/` clan inventory system with host configurations
- `secrets/` clan vars with declarative secret generation
- `overlays/`, `packages/` custom package definitions and multi-channel fallback

**Current hosts** (8-machine fleet):

Darwin hosts (aarch64-darwin):
- `stibnite` primary daily workstation (crs58)
- `blackphos` secondary workstation (raquel, admin: crs58)
- `rosegold` family workstation (janettesmith, admin: cameron)
- `argentum` family workstation (christophersmith, admin: cameron)

NixOS VPS hosts (x86_64-linux):
- `cinnabar` zerotier coordinator, foundation infrastructure (Hetzner Cloud)
- `electrum` secondary VPS (Hetzner Cloud)
- `galena` CPU compute server (Google Cloud Platform)
- `scheelite` GPU compute server (Google Cloud Platform)

**Deployed infrastructure**:
- Zerotier overlay network connecting all 8 machines
- Hetzner Cloud VPS via terranix (cinnabar, electrum)
- Google Cloud Platform VPS via terranix (galena, scheelite)
- Coordinated service deployment across machines via clan inventory

**Key capabilities**:
- Platform support: macOS (nix-darwin), NixOS, standalone home-manager
- Multi-channel stable fallbacks: surgical package fixes without holding back entire channel
- Secrets management: clan vars with declarative generation and deployment
- Development environment: direnv integration, just task runner
- CI/CD: GitHub Actions with cachix, automated testing
- Multi-host orchestration: clan inventory with tags, roles, service instances

**Architectural decisions** (see ADRs):
- ADR-0001: Claude Code multi-profile system
- ADR-0004: Monorepo structure (single packages/ directory)
- ADR-0009: Nix flake-based development environment
- ADR-0011: SOPS secrets management (age encryption, now via clan vars)
- ADR-0014: Design principles (framework independence, type safety, bias toward removal)

## Deprecated architecture (nixos-unified, historical)

**Foundation**: flake-parts (modular composition) + nixos-unified (directory-based autowiring)

**Deprecation**: nixos-unified architecture deprecated, removed during migration.

**Historical repository structure**:
- `flake.nix` used `flake-parts.lib.mkFlake` with auto-wired imports from `./modules/flake-parts/`
- `configurations/{darwin,home,nixos}/` host-specific configurations via nixos-unified autowire
- `modules/{darwin,home,nixos}/` modular system and home-manager configurations
- `secrets/` sops-nix with age encryption for secret management
- `overlays/`, `packages/` custom package definitions and multi-channel fallback

**Historical hosts** (pre-migration, 4 darwin machines only):
- `stibnite` (darwin, aarch64) primary daily workstation
- `blackphos` (darwin, aarch64) secondary development environment
- `rosegold` (darwin, aarch64) testing and experimental
- `argentum` (darwin, aarch64) testing and backup
- CI validation mirrors: `stibnite-nixos`, `blackphos-nixos`, `orb-nixos`

**Why nixos-unified was abandoned**:
- nixos-unified uses specialArgs + directory-based autowire
- Deferred module composition eliminates specialArgs in favor of `config.flake.*` namespace
- These approaches are mutually exclusive (cannot coexist cleanly)
- clan-infra production infrastructure uses clan + flake-parts with manual imports, not nixos-unified

**Migration completed**: Validation-first, then VPS infrastructure, then progressive darwin host migration
- **Initial validation**: COMPLETE - validated deferred module composition + clan integration in test-clan/ repository (isolated testing)
- **VPS foundation**: COMPLETE - deployed cinnabar VPS using validated patterns (foundation infrastructure)
- **Darwin migrations**: COMPLETE - migrated darwin hosts progressively (blackphos → rosegold → argentum → stibnite, primary workstation last after all others proven stable)
- **Architecture cleanup**: COMPLETE - removed nixos-unified, completed migration

**Migration rationale**:
- **Type safety**: Nix lacks native type system; module system provides type checking at evaluation time; deferred module composition maximizes module system usage
- **Multi-host management**: nixos-unified architecture handled each host independently; clan provides coordinated multi-machine management
- **Secrets management**: Moved from manual sops-nix to declarative clan vars with generation and deployment automation
- **Modularity**: Deferred module composition enables clearer feature isolation and cross-platform module composition
- **Proven patterns**: Both deferred module composition and clan have production deployments (drupol-dendritic-infra, clan-infra)

## Architectural compatibility analysis

**Deferred module composition + clan compatibility validated**:
- Both use flake-parts as foundational architecture
- Both eliminate specialArgs antipattern (clan uses minimal `{ inherit inputs; }` for framework integration)
- Deferred module composition's `flake.modules.*` namespace pairs naturally with clan's inventory system
- Both support SOPS secrets (clan uses sops-nix internally)
- Both emphasize modular, type-safe configurations
- import-tree auto-discovery works seamlessly with clan modules

**Priority hierarchy applied during migration**:
1. **Primary**: Clan functionality (non-negotiable) - all clan features must work correctly
2. **Secondary**: Deferred module composition (best-effort) - apply where feasible without compromising clan
3. **Tertiary**: Pattern purity (flexible) - some specialArgs acceptable if clan requires, pragmatism over orthodoxy

**Validated in production**: 8-machine fleet operational

## Risk mitigation strategy (historical)

**Validation completed**: No production examples existed combining deferred module composition + clan patterns.
test-clan/ repository validated integration in minimal environment before infrastructure commitment.
Reduced compound debugging complexity across 8 simultaneous layers (deferred module composition, clan, terraform, hetzner, disko, LUKS, zerotier, NixOS).
Outcome: proven patterns successfully deployed to cinnabar and all 8 machines.

**Progressive migration completed**:
- Migrated non-primary machines first (blackphos, rosegold, argentum)
- Kept stibnite on nixos-unified until others proven stable
- Each host migration verified independently
- Multi-machine testing validated with multiple test hosts
- Each host validated patterns before proceeding to next

**Stability validation**: Each host remained stable for 1-2 weeks before migrating next host.

**Rollback capability**: nixos-unified configurations/ directory preserved during migration, enabled per-host rollback (now deprecated, can be removed).

## Conclusion

Migration from flake-parts + nixos-unified to deferred module composition + clan architecture completed successfully.
Current architecture maximizes type safety through deeper module system integration and enables systematic multi-host management across 8-machine fleet.
Validation-first approach with progressive host-by-host deployment minimized risk to primary workstation.
Success achieved through careful validation at each host, stability monitoring between hosts (1-2 weeks per host), and proven rollback capabilities.

Infrastructure now operational with:
- 4 darwin hosts (stibnite, blackphos, rosegold, argentum) on aarch64-darwin
- 4 NixOS VPS hosts (cinnabar, electrum, galena, scheelite) on x86_64-linux
- Zerotier overlay networking connecting all machines
- Declarative secrets management via clan vars
- Coordinated service deployment via clan inventory system
- Multi-channel nixpkgs stable fallbacks preserved from nixos-unified architecture
