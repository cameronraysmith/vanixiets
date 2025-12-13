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

This repository provides declarative infrastructure management for a heterogeneous fleet of 4 darwin laptops and 4 nixos servers using deferred module composition with clan-core integration.
The architecture achieves maximum type safety through "every file is a flake-parts module" organizational pattern, eliminating specialArgs anti-pattern.
Systematic multi-host management operates through clan's inventory system, service instances, and overlay networking (zerotier).
Declarative secrets management functions through clan vars system with automatic generation and deployment.
Multi-channel nixpkgs stable fallback patterns enable surgical fixes without system-wide rollback.
The system provides enhanced modularity, type safety, and multi-host coordination capabilities across all platforms.

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

## Architectural compatibility

**Deferred module composition + clan technical compatibility**:
- Both use flake-parts as foundational architecture
- Both eliminate specialArgs antipattern (clan uses minimal `{ inherit inputs; }` for framework integration)
- Deferred module composition's `flake.modules.*` namespace pairs naturally with clan's inventory system
- Both support SOPS secrets (clan uses sops-nix internally)
- Both emphasize modular, type-safe configurations
- import-tree auto-discovery works seamlessly with clan modules

**Design priority hierarchy**:
1. **Primary**: Clan functionality (non-negotiable) - all clan features must work correctly
2. **Secondary**: Deferred module composition (best-effort) - apply where feasible without compromising clan
3. **Tertiary**: Pattern purity (flexible) - some specialArgs acceptable if clan requires, pragmatism over orthodoxy

**Production deployment**: 8-machine fleet operational

## Conclusion

Current architecture maximizes type safety through deeper module system integration and enables systematic multi-host management across 8-machine fleet.
Infrastructure operational with:
- 4 darwin hosts (stibnite, blackphos, rosegold, argentum) on aarch64-darwin
- 4 NixOS VPS hosts (cinnabar, electrum, galena, scheelite) on x86_64-linux
- Zerotier overlay networking connecting all machines
- Declarative secrets management via clan vars
- Coordinated service deployment via clan inventory system
- Multi-channel nixpkgs stable fallbacks for surgical package fixes
