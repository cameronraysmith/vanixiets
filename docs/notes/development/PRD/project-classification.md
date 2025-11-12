# Project Classification

**Technical Type:** Infrastructure / DevOps / Configuration Management
**Domain:** System Administration / Multi-Machine Orchestration
**Complexity:** High (Level 3 brownfield migration with unproven pattern combination)

This is a Level 3 brownfield infrastructure migration project targeting a 5-machine heterogeneous environment (1 x86_64 NixOS VPS + 4 aarch64 darwin workstations).

The project combines three proven technologies in an unproven configuration:

- Dendritic flake-parts pattern (proven in production: drupol-dendritic-infra)
- Clan-core multi-machine coordination (proven in production: clan-infra)
- Integration of both patterns (unproven, requires Phase 0 validation)

**Brownfield characteristics:**

- Existing nix-config infrastructure actively manages 4 darwin workstations
- Migration must preserve all functionality (zero-regression requirement)
- Cannot disrupt daily productivity on primary workstation (stibnite)
- Must support rollback at any phase if issues discovered
- Progressive per-host migration with stability validation gates

**Complexity drivers:**

- No documented examples combining dendritic + clan patterns
- Darwin + clan integration has limited precedent (some examples exist but not with dendritic)
- VPS deployment involves 8+ simultaneous layers (dendritic, clan, terraform, hetzner, disko, LUKS, zerotier, NixOS)
- Multi-machine coordination across heterogeneous platforms (NixOS + darwin)
- Type safety goals require deep understanding of flake-parts module system
- Secrets migration from sops-nix to clan vars system

## Domain Context

**System administration domain with multi-machine orchestration complexity:**

**Infrastructure management**: Declarative configuration management via Nix for system-level (NixOS/nix-darwin), user-level (home-manager), and multi-machine coordination (clan-core inventory system)

**Secrets management**: Transition from manual sops-nix encryption to declarative clan vars generators with automatic deployment and generation orchestration

**Network topology**: Establish zerotier mesh VPN with always-on VPS controller (cinnabar) and darwin peer nodes for secure inter-machine communication and service coordination

**Cloud provisioning**: Declarative infrastructure-as-code via terraform/terranix for Hetzner Cloud VPS deployment with disko declarative disk partitioning and LUKS encryption

**Type system engineering**: Apply module system type safety to infrastructure configuration, leveraging flake-parts option types to compensate for Nix language's lack of native compile-time type checking

**Migration strategy**: Validation-first approach with progressive rollout, explicit go/no-go decision gates, stability validation windows, and per-host rollback procedures to manage risk of unproven architectural combination

---
