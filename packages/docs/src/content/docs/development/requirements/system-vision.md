---
title: System vision
sidebar:
  order: 2
---

This document comprehends the system context and vision for infra, capturing features and a high-level overview of use cases.

## System context

Infra operates within the Nix ecosystem providing declarative, reproducible infrastructure management across multiple hosts and platforms.

- **Primary platform**: macOS (nix-darwin) for daily workstations.
- **Secondary platform**: NixOS for server infrastructure (VPS).
- **User environment**: home-manager for cross-platform user configuration.

**External systems**:
- GitHub: Source code hosting, CI/CD platform
- Cachix: Binary cache service
- Hetzner Cloud: VPS hosting provider (target infrastructure)
- Bitwarden: Offline backup for encryption keys

**Development environment**:
- Nix flakes for reproducible builds
- direnv for automatic environment activation
- just task runner for common operations
- GitHub Actions for automated testing and deployment

## System vision overview

### Current state vision

**Foundation**: Dendritic flake-parts pattern + clan integration providing maximum type safety and multi-host coordination.

**Key capabilities**:
- **Type-safe configuration**: Every file is a flake-parts module, eliminating specialArgs antipattern
- **Multi-host coordination**: Clan inventory system managing 8 machines (4 darwin + 4 nixos), services, and relationships
- **Declarative secrets**: Clan vars system with automatic generation and deployment
- **Overlay networking**: Zerotier VPN providing secure communication between all 8 hosts
- **Cross-platform composition**: Single modules targeting multiple platforms (darwin + nixos + home-manager)
- **Multi-channel nixpkgs resilience**: Surgical package fixes without system rollback
- **VPS infrastructure**: Always-on NixOS servers (cinnabar, electrum, galena, scheelite)
- **Development environment**: Automatic activation via direnv + just task runner
- **CI/CD pipeline**: Automated testing with binary caching

### Achieved architecture features

**Foundation**: Dendritic flake-parts pattern + clan integration (OPERATIONAL).

**Achieved capabilities**:
- **Maximum type safety**: Every file is a flake-parts module, specialArgs antipattern eliminated ✓
- **Multi-host coordination**: Clan inventory system managing 8 machines, services, and relationships ✓
- **Declarative secrets**: Clan vars system with automatic generation and deployment ✓
- **Overlay networking**: Zerotier VPN providing secure 8-machine mesh network ✓
- **Cross-platform composition**: Single modules targeting multiple platforms (darwin + nixos + home-manager) ✓
- **Systematic service deployment**: Service instances with roles spanning multiple machines ✓
- **Multi-channel nixpkgs resilience**: Surgical package fixes without system rollback ✓
- **Development environment**: Workflow automation with direnv and just ✓
- **CI/CD integration**: Automated testing with binary caching ✓

**Infrastructure deployment**:
- **4 NixOS VPS machines**: cinnabar (Hetzner zerotier controller), electrum (Hetzner), galena (GCP CPU), scheelite (GCP GPU) ✓
- **4 Darwin workstations**: stibnite, blackphos, rosegold, argentum (all aarch64-darwin) ✓
- **8-machine overlay network**: Zerotier mesh with cinnabar as controller, all others as peers ✓
- **Migration complete**: All hosts migrated from nixos-unified to dendritic+clan architecture ✓

## Rich picture: Current architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Nix-Config System                              │
│                    (Dendritic + Clan Architecture)                     │
└──────────────────────────────────────────────────────────────────────┘

External Dependencies                System Boundary
┌─────────────────┐                  ┌────────────────────────────────┐
│ GitHub          │◄─────────────────┤  Source Repository             │
│  - Git hosting  │                  │   - flake.nix                  │
│  - CI/CD        │                  │   - modules/ (dendritic)       │
│  - Issues       │                  │   - sops/ (clan vars)          │
└─────────────────┘                  └────────────────────────────────┘
                                                    │
┌─────────────────┐                                 │
│ Cachix          │◄────────────────────────────────┤
│  - Binary cache │                                 │
│  - Build cache  │                                 │
└─────────────────┘                                 │
                                                    │
┌─────────────────┐                  ┌──────────────▼──────────────────┐
│ Hetzner Cloud   │◄─────────────────┤  Infrastructure Provisioning    │
│  - VPS hosting  │                  │   - Terraform/terranix          │
│  - API access   │                  │   - Disko (partitioning)        │
└─────────────────┘                  │   - Clan deployment             │
                                     └─────────────────────────────────┘
                                                    │
                                     ┌──────────────▼──────────────────┐
                                     │   Clan Inventory System          │
                                     │  ┌───────────────────────────┐  │
                                     │  │ Machines (8 total):       │  │
                                     │  │ NixOS VPS:                │  │
                                     │  │  - cinnabar (hetzner)     │  │
                                     │  │  - electrum (hetzner)     │  │
                                     │  │  - galena (gcp-cpu)       │  │
                                     │  │  - scheelite (gcp-gpu)    │  │
                                     │  │ Darwin Workstations:      │  │
                                     │  │  - stibnite (aarch64)     │  │
                                     │  │  - blackphos (aarch64)    │  │
                                     │  │  - rosegold (aarch64)     │  │
                                     │  │  - argentum (aarch64)     │  │
                                     │  └───────────────────────────┘  │
                                     │  ┌───────────────────────────┐  │
                                     │  │ Service Instances:        │  │
                                     │  │  - zerotier-local         │  │
                                     │  │  - sshd-clan              │  │
                                     │  │  - emergency-access       │  │
                                     │  │  - users-crs58            │  │
                                     │  └───────────────────────────┘  │
                                     └─────────────────────────────────┘
                                                    │
              ┌─────────────────────────────────────┴────────────────────┐
              │                                                          │
   ┌──────────▼─────────┐                              ┌────────────────▼────────┐
   │  VPS Infrastructure│                              │  Darwin Workstations    │
   │  (4 machines)      │                              │  (4 machines)           │
   │                    │                              │                         │
   │  ┌──────────────┐  │                              │  ┌──────────────────┐   │
   │  │ cinnabar     │  │                              │  │ stibnite         │   │
   │  │ (Hetzner)    │  │                              │  │ blackphos        │   │
   │  │              │  │                              │  │ rosegold         │   │
   │  │ Roles:       │  │                              │  │ argentum         │   │
   │  │ - ZT ctrl    │◄─┼──────────────────────────────┼─►│ (all aarch64)    │   │
   │  │ - SSH server │  │    Zerotier 8-Machine Mesh   │  │                  │   │
   │  │ - Core svcs  │  │    (Encrypted, Private)      │  │ Roles:           │   │
   │  └──────────────┘  │                              │  │ - ZT peer        │   │
   │  ┌──────────────┐  │                              │  │ - SSH client     │   │
   │  │ electrum     │  │                              │  │ - Development    │   │
   │  │ (Hetzner)    │  │                              │  │ - Daily use      │   │
   │  │              │  │                              │  └──────────────────┘   │
   │  │ Roles:       │  │                              └─────────────────────────┘
   │  │ - ZT peer    │  │
   │  │ - Secondary  │  │
   │  └──────────────┘  │
   │  ┌──────────────┐  │
   │  │ galena       │  │
   │  │ (GCP CPU)    │  │
   │  │              │  │
   │  │ Roles:       │  │
   │  │ - ZT peer    │  │
   │  │ - Compute    │  │
   │  └──────────────┘  │
   │  ┌──────────────┐  │
   │  │ scheelite    │  │
   │  │ (GCP GPU)    │  │
   │  │              │  │
   │  │ Roles:       │  │
   │  │ - ZT peer    │  │
   │  │ - GPU jobs   │  │
   │  └──────────────┘  │
   │                    │
   │ x86_64-linux       │
   │ Always-on          │
   └────────────────────┘

Configuration Flow:
  Developer ──► Edit modules/ ──► Git commit ──► CI checks ──► Deploy
                   │                                              │
                   └──► Dendritic pattern ◄──────────────────────┘
                        (every file is module)

Secrets Flow:
  Developer ──► Define generators ──► Clan vars generate
                                          │
                    ┌─────────────────────┴────────────────────┐
                    │                                          │
            Encrypted in sops/                        Deployed to /run/secrets/
            (version controlled)                      (runtime on each host)
```

## Feature overview

### F-001: Declarative system configuration

**Description**: Define entire system configuration in version-controlled Nix files.

**Status**: OPERATIONAL - Implemented via dendritic flake-parts pattern.

**User benefit**: Reproducible systems, easy rollback, configuration as documentation.

### F-002: Multi-channel package resilience

**Description**: Use multiple nixpkgs channels to fix individual packages without system-wide rollback.

**Status**: OPERATIONAL - Implemented via overlays and multiple nixpkgs inputs.

**User benefit**: Latest packages without sacrificing stability.

**Reference**: [Handling broken packages](/guides/handling-broken-packages)

### F-003: Secrets management

**Description**: Encrypted secrets in version control with secure deployment.

**Status**: OPERATIONAL - Clan vars with declarative generation and automatic deployment.

**User benefit**: Secure secret storage, simplified rotation, declarative workflow.

### F-004: Development environment

**Description**: Reproducible development environment with automatic activation.

**Status**: OPERATIONAL - Nix develop + direnv + just task runner.

**User benefit**: Consistent environment across hosts, no manual tool installation.

### F-005: Multi-host coordination

**Description**: Coordinated management of multiple hosts with shared services.

**Status**: OPERATIONAL - Clan inventory system managing 8 machines with tags, roles, and service instances.

**User benefit**: Single source of truth, automated service deployment across hosts.

### F-006: Overlay networking

**Description**: Secure private network connecting all hosts regardless of physical location.

**Status**: OPERATIONAL - Zerotier VPN 8-machine mesh via clan service instance, controller on cinnabar.

**User benefit**: Secure inter-host communication, works across networks/NAT.

### F-007: Cross-platform module composition

**Description**: Share modules across darwin, nixos, and home-manager.

**Status**: OPERATIONAL - Dendritic pattern enables single module targeting multiple platforms.

**User benefit**: Reduced duplication, clear separation of platform-specific vs shared code.

### F-008: Type-safe configuration

**Description**: Catch configuration errors at evaluation time through module system.

**Status**: OPERATIONAL - Maximized via dendritic pattern (every file is module, specialArgs eliminated).

**User benefit**: Earlier error detection, better error messages, safer refactoring.

### F-009: VPS infrastructure

**Description**: Always-on server infrastructure for services requiring high availability.

**Status**: OPERATIONAL - 4 VPS machines deployed (cinnabar/electrum on Hetzner, galena/scheelite on GCP).

**User benefit**: Zerotier controller independent of darwin hosts, compute infrastructure for CPU/GPU workloads.

### F-010: Progressive deployment

**Description**: Deploy configuration changes with validation and rollback capability.

**Status**: OPERATIONAL - Clan deployment workflow with darwin-rebuild/nixos-rebuild integration.

**User benefit**: Safe updates, easy rollback, dry-run capability.

## Use case overview

### Core workflows (operational)

- **UC-001**: Bootstrap new host with minimal configuration (see [usage-model](/development/requirements/usage-model/#uc-001-bootstrap-new-host-with-minimal-configuration)).
- **UC-002**: Add feature module spanning multiple platforms (see [usage-model](/development/requirements/usage-model/#uc-002-add-feature-module-spanning-multiple-platforms)).
- **UC-003**: Manage secrets via declarative generators (see [usage-model](/development/requirements/usage-model/#uc-003-manage-secrets-via-declarative-generators)).
- **UC-004**: Deploy coordinated service across hosts (see [usage-model](/development/requirements/usage-model/#uc-004-deploy-coordinated-service-across-hosts)).
- **UC-005**: Handle broken packages with multi-channel fallback (see [usage-model](/development/requirements/usage-model/#uc-005-handle-broken-package-with-multi-channel-fallback)).
- **UC-006**: Establish secure overlay network (see [usage-model](/development/requirements/usage-model/#uc-006-establish-secure-overlay-network)).
- **UC-007**: Update packages across all 8 hosts.
- **UC-008**: Deploy configuration changes with rollback capability.
- **UC-009**: Set up development environment on new machine.

Detailed use cases are documented in [usage-model](/development/requirements/usage-model/).

## System boundaries

### In scope

- System configuration for darwin and NixOS platforms
- User environment management (home-manager)
- Multi-host coordination and networking
- Secrets management
- Development environment
- Package management and resilience patterns
- CI/CD automation
- VPS infrastructure provisioning

### Out of scope

- Non-Nix package management (Homebrew casks as exceptions for GUI apps)
- Cloud services beyond VPS (no managed databases, object storage, etc.)
- Multi-user scenarios beyond single primary user (crs58)
- Windows or other non-Unix platforms
- Mobile device management
- Container orchestration (Kubernetes, Docker Swarm)
- Application-specific configuration (managed within applications themselves)

### Interfaces

**User interfaces**:
- Command-line: `darwin-rebuild`, `nixos-rebuild`, `home-manager`, `clan` commands
- Task runner: `just` recipes for common operations
- Editor integration: LSP for Nix, syntax highlighting

**System interfaces**:
- GitHub API: Repository access, CI/CD triggers
- Cachix API: Binary cache uploads/downloads
- Hetzner Cloud API: VPS provisioning via Terraform
- Zerotier API: Network management (controller role)

**Configuration interfaces**:
- Nix flake inputs: Dependency specification
- Module system: Configuration composition
- Clan inventory: Multi-host coordination

## Migration history

### Initial validation (COMPLETE)

**Objective**: Prove dendritic + clan integration works in test environment.

**Outcome**: Validated patterns ready for production deployment via test-clan repository.

**Status**: COMPLETE.

**Completion**: November 2024.

### Foundation infrastructure (COMPLETE)

**Objective**: Deploy VPS infrastructure as foundation with core services.

**Key features enabled**:
- F-009: VPS infrastructure (4 machines: cinnabar, electrum, galena, scheelite)
- F-006: Overlay networking (controller role on cinnabar)
- F-008: Type-safe configuration (dendritic on NixOS)

**Status**: COMPLETE.

**Completion**: November 2024.

### Darwin migration (COMPLETE)

**Objective**: Migrate darwin hosts progressively (blackphos → rosegold → argentum → stibnite).

**Key features enabled**:
- F-007: Cross-platform module composition
- F-008: Type-safe configuration (dendritic on darwin)
- F-005: Multi-host coordination (8-machine inventory)
- F-006: Overlay networking (peer role on all darwin hosts)
- F-003: Declarative secrets (clan vars)

**Status**: COMPLETE.

**Completion**: November 2024.

### Architecture cleanup (COMPLETE)

**Objective**: Remove nixos-unified, complete migration to dendritic+clan.

**Outcome**: Full dendritic + clan architecture operational across all 8 machines.

**Status**: COMPLETE.

**Completion**: November 2024.

## Success criteria (ACHIEVED)

### Current state preservation (ACHIEVED)

- ✓ All existing functionality maintained
- ✓ Multi-channel resilience preserved (F-002)
- ✓ Development environment functional (F-004)
- ✓ No regressions in daily workflows

### Architecture achievement (COMPLETE)

- ✓ Dendritic pattern adopted (every file is module) - OPERATIONAL
- ✓ Clan integration functional (inventory, vars, services) - OPERATIONAL
- ✓ Type safety maximized through module system (F-008) - OPERATIONAL
- ✓ Multi-host coordination operational (F-005) - 8 machines managed
- ✓ Overlay network established (F-006) - 8-machine zerotier mesh
- ✓ Cross-platform composition enabled (F-007) - OPERATIONAL
- ✓ VPS infrastructure deployed (F-009) - 4 VPS machines operational
- ✓ Declarative secrets working (F-003) - Clan vars operational

### Migration validation (COMPLETE)

- ✓ Each phase completed successfully (Phases 0-6)
- ✓ Stability demonstrated (all hosts stable in production)
- ✓ Rollback capability preserved throughout migration
- ✓ Primary workstation (stibnite) migrated last after all others proven
- ✓ nixos-unified removed, dendritic+clan architecture fully operational

## References

- [Usage model](/development/requirements/usage-model/) - Detailed use cases
- [Quality requirements](quality-requirements/) - Non-functional requirements
- [Context: Domain model](../context/domain-model/) - Technical architecture details
- [Context: Goals](../context/goals-and-objectives/) - Strategic objectives
- Migration planning: `docs/notes/clan/` (internal planning, not published)
