---
title: System vision
---

This document comprehends the system context and vision for the nix-config, capturing features and a high-level overview of use cases.

## System context

The nix-config system operates within the Nix ecosystem providing declarative, reproducible infrastructure management across multiple hosts and platforms.

**Primary platform**: macOS (nix-darwin) for daily workstations.
**Secondary platform**: NixOS for server infrastructure (VPS).
**User environment**: home-manager for cross-platform user configuration.

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

**Foundation**: flake-parts + nixos-unified providing modular, multi-platform configuration.

**Key capabilities**:
- Declarative system configuration for macOS and NixOS
- Directory-based autowiring for host discovery
- Multi-channel nixpkgs resilience (surgical package fixes)
- Secrets management via sops-nix with age encryption
- Development environment with automatic activation
- CI/CD pipeline with binary caching

**Limitations**:
- Manual per-host coordination (no systematic multi-host management)
- Limited type safety (specialArgs bypasses module system type checking)
- Manual secrets management (no declarative generation)
- Cross-platform module composition requires duplication
- No overlay networking between hosts

### Target state vision

**Foundation**: Dendritic flake-parts pattern + clan-core integration.

**Enhanced capabilities**:
- **Maximum type safety**: Every file is a flake-parts module, eliminating specialArgs antipattern
- **Multi-host coordination**: Clan inventory system managing machines, services, and relationships
- **Declarative secrets**: Clan vars system with automatic generation and deployment
- **Overlay networking**: Zerotier VPN providing secure communication between all hosts
- **Cross-platform composition**: Single modules targeting multiple platforms (darwin + nixos + home-manager)
- **Systematic service deployment**: Service instances with roles spanning multiple machines

**Preserved capabilities**:
- Multi-channel nixpkgs resilience (surgical package fixes without system rollback)
- Development environment and workflow automation
- CI/CD integration with binary caching
- All existing functionality maintained

**Infrastructure evolution**:
- Add VPS infrastructure (cinnabar) as foundation for always-on services
- Zerotier controller role on VPS (independent of darwin hosts)
- Progressive migration of darwin hosts to new architecture
- Five-machine overlay network (1 VPS + 4 darwin workstations)

## Rich picture: Target architecture

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
                                     │  │ Machines:                 │  │
                                     │  │  - cinnabar (nixos/vps)   │  │
                                     │  │  - blackphos (darwin)     │  │
                                     │  │  - rosegold (darwin)      │  │
                                     │  │  - argentum (darwin)      │  │
                                     │  │  - stibnite (darwin)      │  │
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
   │  ┌──────────────┐  │                              │  ┌──────────────────┐   │
   │  │ cinnabar     │  │                              │  │ blackphos        │   │
   │  │ (NixOS)      │  │                              │  │ rosegold         │   │
   │  │              │  │                              │  │ argentum         │   │
   │  │ Roles:       │  │                              │  │ stibnite         │   │
   │  │ - ZT ctrl    │◄─┼──────────────────────────────┼─►│ (all aarch64)    │   │
   │  │ - SSH server │  │    Zerotier Overlay Network  │  │                  │   │
   │  │ - Core svcs  │  │    (Encrypted, Private)      │  │ Roles:           │   │
   │  └──────────────┘  │                              │  │ - ZT peer        │   │
   │                    │                              │  │ - SSH client     │   │
   │ Hetzner Cloud CX53 │                              │  │ - Development    │   │
   │ x86_64-linux       │                              │  │ - Daily use      │   │
   │ Always-on          │                              │  └──────────────────┘   │
   └────────────────────┘                              └─────────────────────────┘

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

**Current state**: Achieved via flake-parts + nixos-unified.

**Target state**: Enhanced with dendritic pattern for better organization.

**User benefit**: Reproducible systems, easy rollback, configuration as documentation.

### F-002: Multi-channel package resilience

**Description**: Use multiple nixpkgs channels to fix individual packages without system-wide rollback.

**Current state**: Implemented via overlays and multiple nixpkgs inputs.

**Target state**: Preserved without modification.

**User benefit**: Latest packages without sacrificing stability.

**Reference**: `docs/development/architecture/nixpkgs-hotfixes.md`

### F-003: Secrets management

**Description**: Encrypted secrets in version control with secure deployment.

**Current state**: sops-nix with age encryption, manual generation.

**Target state**: Clan vars with declarative generation and automatic deployment.

**User benefit**: Secure secret storage, simplified rotation, declarative workflow.

### F-004: Development environment

**Description**: Reproducible development environment with automatic activation.

**Current state**: Nix develop + direnv + just task runner.

**Target state**: Preserved without modification.

**User benefit**: Consistent environment across hosts, no manual tool installation.

### F-005: Multi-host coordination

**Description**: Coordinated management of multiple hosts with shared services.

**Current state**: Not available (manual per-host management).

**Target state**: Clan inventory system with machines, tags, roles, service instances.

**User benefit**: Single source of truth, automated service deployment across hosts.

### F-006: Overlay networking

**Description**: Secure private network connecting all hosts regardless of physical location.

**Current state**: Not available.

**Target state**: Zerotier VPN via clan service instance, controller on VPS.

**User benefit**: Secure inter-host communication, works across networks/NAT.

### F-007: Cross-platform module composition

**Description**: Share modules across darwin, nixos, and home-manager.

**Current state**: Partial (some duplication required).

**Target state**: Dendritic pattern enables single module targeting multiple platforms.

**User benefit**: Reduced duplication, clear separation of platform-specific vs shared code.

### F-008: Type-safe configuration

**Description**: Catch configuration errors at evaluation time through module system.

**Current state**: Partial (specialArgs bypasses type checking).

**Target state**: Maximized via dendritic pattern (every file is module).

**User benefit**: Earlier error detection, better error messages, safer refactoring.

### F-009: VPS infrastructure

**Description**: Always-on server infrastructure for services requiring high availability.

**Current state**: Not available.

**Target state**: Hetzner Cloud VPS (cinnabar) with core services.

**User benefit**: Zerotier controller independent of darwin hosts, foundation for future services.

### F-010: Progressive deployment

**Description**: Deploy configuration changes with validation and rollback capability.

**Current state**: darwin-rebuild/nixos-rebuild with rollback.

**Target state**: Enhanced with clan deployment workflow.

**User benefit**: Safe updates, easy rollback, dry-run capability.

## Use case overview

### Core workflows (current state)

**UC-Current-001**: Configure new darwin host.
**UC-Current-002**: Update packages across all hosts.
**UC-Current-003**: Fix broken package without system rollback.
**UC-Current-004**: Deploy configuration changes.
**UC-Current-005**: Manage secrets.
**UC-Current-006**: Set up development environment.

### Enhanced workflows (target state)

**UC-Target-001**: Bootstrap new host with minimal configuration (see [usage-model](usage-model/#uc-001-bootstrap-new-host)).
**UC-Target-002**: Add feature module spanning multiple platforms (see [usage-model](usage-model/#uc-002-add-cross-platform-feature-module)).
**UC-Target-003**: Manage secrets via declarative generators (see [usage-model](usage-model/#uc-003-manage-secrets-declaratively)).
**UC-Target-004**: Deploy coordinated service across hosts (see [usage-model](usage-model/#uc-004-deploy-coordinated-multi-host-service)).
**UC-Target-005**: Handle broken packages with multi-channel resilience (see [usage-model](usage-model/#uc-005-handle-broken-package)).
**UC-Target-006**: Establish secure overlay network (see [usage-model](usage-model/#uc-006-establish-overlay-network)).
**UC-Target-007**: Migrate host to new architecture (see [usage-model](usage-model/#uc-007-migrate-host-to-dendritic-clan)).

Detailed use cases are documented in [usage-model](usage-model/).

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

## Migration vision

### Phase 0: Validation

**Objective**: Prove dendritic + clan integration works in test environment.

**Outcome**: Validated patterns ready for production deployment.

**Status**: Not started (next step).

### Phase 1: Foundation infrastructure

**Objective**: Deploy cinnabar VPS as foundation with core services.

**Key features enabled**:
- F-009: VPS infrastructure
- F-006: Overlay networking (controller role)
- F-008: Type-safe configuration (dendritic on NixOS)

**Status**: Planned after Phase 0 validation.

### Phases 2-5: Darwin migration

**Objective**: Migrate darwin hosts progressively (blackphos → rosegold → argentum → stibnite).

**Key features enabled**:
- F-007: Cross-platform module composition
- F-008: Type-safe configuration (dendritic on darwin)
- F-005: Multi-host coordination
- F-006: Overlay networking (peer role)
- F-003: Declarative secrets (clan vars)

**Status**: Planned after Phase 1 stable.

### Phase 6: Cleanup

**Objective**: Remove nixos-unified, complete migration.

**Outcome**: Full dendritic + clan architecture operational.

**Status**: Planned after all hosts migrated and stable.

## Success criteria

### Current state preservation

- ✓ All existing functionality maintained
- ✓ Multi-channel resilience preserved (F-002)
- ✓ Development environment functional (F-004)
- ✓ No regressions in daily workflows

### Target state achievement

- ✓ Dendritic pattern adopted (every file is module)
- ✓ Clan integration functional (inventory, vars, services)
- ✓ Type safety maximized through module system (F-008)
- ✓ Multi-host coordination operational (F-005)
- ✓ Overlay network established (F-006)
- ✓ Cross-platform composition enabled (F-007)
- ✓ VPS infrastructure deployed (F-009)
- ✓ Declarative secrets working (F-003 enhanced)

### Migration validation

- ✓ Each phase completes successfully
- ✓ Stability demonstrated (1-2 weeks per host minimum)
- ✓ Rollback capability preserved throughout migration
- ✓ Primary workstation (stibnite) migrated last after all others proven

## References

- [Usage model](usage-model/) - Detailed use cases
- [Quality requirements](quality-requirements/) - Non-functional requirements
- [Context: Domain model](../context/domain-model/) - Technical architecture details
- [Context: Goals](../context/goals-and-objectives/) - Strategic objectives
- Migration planning: `docs/notes/clan/` (internal planning, not published)
