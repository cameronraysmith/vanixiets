---
title: Functional hierarchy
sidebar:
  order: 5
---

This document organizes user-visible functions hierarchically by category.
Functions describe what the system does from a black-box perspective without specifying internal implementation.

## Overview

The functional hierarchy captures user-visible functions accessible through commands, configuration options, and flake outputs.
Functions are organized by purpose rather than technical implementation, reflecting the artefact-based requirements engineering approach.

This hierarchy documents the current dendritic flake-parts + clan architecture. Historical migration functions (MF-001 to MF-004) are preserved for reference, marked as completed.

## Configuration management functions

### CM-001: Flake evaluation

**Purpose**: Evaluate Nix expressions to produce configuration

**Inputs**:
- flake.nix with imports
- Module files (dendritic pattern via import-tree)
- Input dependencies (locked in flake.lock)

**Outputs**:
- Evaluated configuration for deployment
- Type-checked module options
- Generated outputs (darwinConfigurations, nixosConfigurations, etc.)

**Invocation**: `nix flake show`, `nix flake check`, `nix eval`

**Related use cases**: All use cases depend on evaluation

### CM-002: Module auto-discovery

**Purpose**: Automatically import modules from directory structure

**Inputs**:
- modules/ directory tree
- import-tree function (target)
- Pattern: every .nix file is a flake-parts module

**Outputs**:
- All modules discovered and imported
- flake.modules.* namespace populated

**Invocation**: Automatic during flake evaluation

**Related use cases**: UC-002 (Add feature module)

See [ADR-0018: Dendritic Flake-Parts Architecture](/development/architecture/adrs/0018-dendritic-flake-parts-architecture/) for module auto-discovery patterns.

### CM-003: Host configuration generation

**Purpose**: Generate system configurations for specific hosts

**Inputs**:
- Host definitions in modules/hosts/<hostname>/
- Dendritic base modules
- Clan inventory (target)

**Outputs**:
- darwinConfigurations.<hostname> (darwin)
- nixosConfigurations.<hostname> (NixOS)

**Invocation**: Build targets in nix commands

**Related use cases**: UC-001 (Bootstrap), UC-007 (Migration)

### CM-004: Cross-platform module composition

**Purpose**: Compose modules targeting multiple platforms

**Inputs**:
- Single feature module file
- Platform-specific blocks (darwin, nixos, homeManager)
- config.flake.modules.* namespace references

**Outputs**:
- Feature available on all target platforms
- No duplication of shared logic

**Invocation**: Via imports in host configurations

**Related use cases**: UC-002 (Add feature module)

## Secrets management functions

### SM-001: Generate clan vars

**Purpose**: Generate secrets and configuration files for hosts

**Inputs**:
- Generator definitions (clan.core.vars.generators.<name>)
- User prompts (interactive input)
- Dependencies (other generators via DAG)

**Outputs**:
- Encrypted secrets in sops/machines/<hostname>/secrets/
- Public values in sops/machines/<hostname>/facts/

**Invocation**: `clan vars generate <hostname>`

**Related use cases**: UC-003 (Manage secrets declaratively)

### SM-002: Deploy secrets to hosts

**Purpose**: Decrypt and deploy secrets during activation

**Inputs**:
- Encrypted secrets from repository
- Host age key (for decryption)
- Secret deployment configuration

**Outputs**:
- Secrets available at /run/secrets/<generator>.<file>
- Correct permissions applied

**Invocation**: Automatic during system activation

**Related use cases**: UC-001 (Bootstrap), UC-003 (Secrets)

### SM-003: Share secrets across machines

**Purpose**: Make secrets accessible to multiple machines in group

**Inputs**:
- Generator with share = true
- Group membership (clan inventory)
- Authorized host age keys

**Outputs**:
- Secret accessible to group members
- Proper encryption for each host

**Invocation**: Configuration-driven during vars generation

**Related use cases**: UC-004 (Multi-host services)

### SM-004: Encrypt secrets at rest

**Purpose**: Protect secrets in version control

**Inputs**:
- Plain text secret from generator
- Host or group age public keys
- SOPS encryption configuration

**Outputs**:
- Encrypted YAML files
- Version-controllable secrets

**Invocation**: Automatic during vars generation

**Related use cases**: UC-003 (Secrets)

## Package management functions

### PM-001: Multi-channel nixpkgs access

**Purpose**: Provide access to multiple nixpkgs channels simultaneously

**Inputs**:
- nixpkgs (unstable, default)
- darwin-stable / linux-stable (OS-specific stable)
- patched (unstable with patches applied)

**Outputs**:
- pkgs.stable, pkgs.unstable, pkgs.patched namespaces
- Overlay-accessible in all expressions

**Invocation**: Via overlay composition in modules/nixpkgs/overlays/channels.nix

**Related use cases**: UC-005 (Handle broken packages)

### PM-002: Platform-specific stable fallbacks

**Purpose**: Use stable channel for specific broken packages

**Inputs**:
- Package name
- Platform conditions (isDarwin, hostPlatform.system)
- Stable channel reference

**Outputs**:
- Package from stable instead of unstable
- Platform-conditional application

**Invocation**: Via stable-fallbacks.nix overlay

**Related use cases**: UC-005 (Handle broken packages)

### PM-003: Apply upstream patches

**Purpose**: Apply unreleased fixes from upstream PRs

**Inputs**:
- Patch URL (GitHub PR)
- Hash for verification
- Base nixpkgs (unstable)

**Outputs**:
- pkgs.patched with patches applied
- Fixed packages available

**Invocation**: Via patches.nix configuration, referenced in overlays

**Related use cases**: UC-005 (Handle broken packages)

### PM-004: Override package builds

**Purpose**: Modify package build parameters without channel switch

**Inputs**:
- Base package from nixpkgs
- Build modifications (overrideAttrs, disabling tests, etc.)
- Override specification in overrides/<package>.nix

**Outputs**:
- Package with modified build
- Fix applied via overlay

**Invocation**: Via overrides/ auto-import

**Related use cases**: UC-005 (Handle broken packages)

### PM-005: Build custom packages

**Purpose**: Provide custom derivations not in nixpkgs

**Inputs**:
- Package definition in packages/
- Dependencies from nixpkgs
- Build instructions

**Outputs**:
- Custom packages in overlay
- Available as pkgs.<package>

**Invocation**: Via packages/ directory composition

**Related use cases**: Infrastructure development

### PM-006: Manage binary caching

**Purpose**: Store and retrieve pre-built derivations

**Inputs**:
- Cachix configuration
- Cache credentials (secrets)
- Build outputs

**Outputs**:
- Faster builds from cache hits
- Reduced rebuild times

**Invocation**: Automatic via nix configuration

**Related use cases**: All building and deployment workflows

## Development environment functions

### DE-001: Provide development shell

**Purpose**: Reproducible development environment with tools

**Inputs**:
- devShell configuration
- Required tools (bun, nodejs, playwright, etc.)
- Environment variables

**Outputs**:
- Shell with all development tools
- Consistent environment across hosts

**Invocation**: `nix develop`

**Related use cases**: Daily development workflows

### DE-002: Automatic environment activation

**Purpose**: Activate development shell on directory entry

**Inputs**:
- .envrc configuration
- direnv integration
- Development shell definition

**Outputs**:
- Automatic tool availability
- Environment loaded without manual command

**Invocation**: Automatic via direnv

**Related use cases**: Daily development workflows

### DE-003: Task runner integration

**Purpose**: Common operations via just recipes

**Inputs**:
- justfile with recipes
- Development shell tools
- Configuration targets

**Outputs**:
- Convenient command shortcuts
- Consistent workflow across local and CI

**Invocation**: `just <recipe>` (check, verify, lint, etc.)

**Related use cases**: All development and validation workflows

## Deployment functions

### DF-001: Build darwin system configuration

**Purpose**: Build complete darwin system derivation

**Inputs**:
- darwinConfiguration for host
- All modules and dependencies
- nixpkgs with overlays

**Outputs**:
- System derivation
- Activation script

**Invocation**: `nix build .#darwinConfigurations.<hostname>.system`

**Related use cases**: UC-001 (Bootstrap), UC-007 (Migration)

### DF-002: Activate darwin configuration

**Purpose**: Apply darwin configuration to running system

**Inputs**:
- Built system derivation
- Current system state
- Secrets for deployment

**Outputs**:
- System updated to new configuration
- Services restarted as needed
- New generation in profile

**Invocation**: `darwin-rebuild switch --flake .#<hostname>`

**Related use cases**: UC-001 (Bootstrap), UC-007 (Migration)

### DF-003: Build NixOS system configuration

**Purpose**: Build complete NixOS system derivation

**Inputs**:
- nixosConfiguration for host
- All modules and dependencies
- nixpkgs with overlays

**Outputs**:
- System toplevel derivation
- Bootloader configuration

**Invocation**: `nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel`

**Related use cases**: UC-001 (Bootstrap), Phase 1 VPS deployment

### DF-004: Activate NixOS configuration

**Purpose**: Apply NixOS configuration to running system

**Inputs**:
- Built system derivation
- Current system state
- Secrets for deployment

**Outputs**:
- System updated to new configuration
- Systemd services restarted
- New boot entry created

**Invocation**: `nixos-rebuild switch --flake .#<hostname>`

**Related use cases**: UC-001 (Bootstrap), VPS deployment

### DF-005: Rollback to previous generation

**Purpose**: Revert system to previous working configuration

**Inputs**:
- Previous generation number or profile link
- System profile history

**Outputs**:
- System reverted to previous state
- Services restored to previous configuration

**Invocation**: `darwin-rebuild switch --rollback` or manual activation

**Related use cases**: UC-007 (Migration) alternate flows

### DF-006: Perform dry-run activation

**Purpose**: Preview changes without applying them

**Inputs**:
- New system configuration
- Current system state

**Outputs**:
- List of changes (packages, services, etc.)
- No actual system modification

**Invocation**: `darwin-rebuild switch --dry-run --flake .#<hostname>`

**Related use cases**: UC-007 (Migration) validation

### DF-007: Deploy with clan orchestration

**Purpose**: Deploy configuration via clan workflow

**Inputs**:
- Clan inventory and instance definitions
- Generated vars
- Target machine specification

**Outputs**:
- System activated via clan
- Vars deployed automatically
- Role-based configuration applied

**Invocation**: `clan machines update <hostname>`

**Related use cases**: UC-004 (Multi-host services), UC-006 (Overlay network)

## Multi-host coordination functions

### MC-001: Define machine inventory

**Purpose**: Central machine registry with tags and classes

**Inputs**:
- Machine definitions (inventory.machines.<name>)
- Tags for grouping
- machineClass (darwin or nixos)

**Outputs**:
- Central machine registry
- Tag-based selection capability

**Invocation**: Configuration in modules/flake-parts/clan.nix

**Related use cases**: UC-004 (Multi-host services)

### MC-002: Configure service instances

**Purpose**: Deploy services across multiple machines

**Inputs**:
- Instance definition (inventory.instances.<name>)
- Service module specification
- Role assignments (controller, peer, server, client, etc.)
- Role-based and machine-specific settings

**Outputs**:
- Service configured across all participating hosts
- Role-appropriate configuration per machine
- Coordination enabled

**Invocation**: Configuration-driven during deployment

**Related use cases**: UC-004 (Multi-host services), UC-006 (Overlay network)

### MC-003: Assign roles to machines

**Purpose**: Define machine function within service instance

**Inputs**:
- Role definition in instance
- Machine or tag assignment
- Role-specific configuration

**Outputs**:
- Machines configured with appropriate role
- Tag-based bulk assignment supported

**Invocation**: Via roles.<name>.machines.<hostname> or roles.<name>.tags.<tag>

**Related use cases**: UC-004 (Multi-host services)

### MC-004: Evaluate configuration hierarchy

**Purpose**: Apply layered configuration (instance → role → machine)

**Inputs**:
- Instance-wide settings
- Role-wide settings
- Machine-specific overrides

**Outputs**:
- Merged configuration for each machine
- Overrides applied correctly
- Type-checked result

**Invocation**: Automatic during configuration evaluation

**Related use cases**: UC-004 (Multi-host services)

## Overlay networking functions

### ON-001: Configure zerotier controller

**Purpose**: Establish controller node for overlay network

**Inputs**:
- Controller role assignment
- Network configuration
- Generated credentials

**Outputs**:
- Zerotier network created
- Controller operational
- Network ID and credentials

**Invocation**: Via service instance deployment

**Related use cases**: UC-006 (Overlay network)

### ON-002: Connect zerotier peers

**Purpose**: Join machines to overlay network as peers

**Inputs**:
- Peer role assignment
- Network ID from controller
- Authentication tokens

**Outputs**:
- Peer authenticated and connected
- Private IP assigned
- Encrypted tunnels established

**Invocation**: Via service instance deployment

**Related use cases**: UC-006 (Overlay network)

### ON-003: Manage overlay network membership

**Purpose**: Authorize and revoke machine access to network

**Inputs**:
- Machine identifiers
- Network membership rules
- Authorization credentials

**Outputs**:
- Machines authorized or revoked
- Network access controlled

**Invocation**: Via controller configuration

**Related use cases**: UC-006 (Overlay network)

### ON-004: Establish encrypted communication

**Purpose**: Secure inter-host traffic via overlay network

**Inputs**:
- Zerotier peer connections
- Encryption keys
- Network topology

**Outputs**:
- End-to-end encrypted communication
- NAT traversal functional
- Stable private IPs

**Invocation**: Automatic after peer connection

**Related use cases**: UC-006 (Overlay network), UC-004 (Multi-host services)

## CI/CD functions

### CI-001: Validate flake evaluation

**Purpose**: Ensure flake evaluates without errors

**Inputs**:
- All flake files and modules
- Input dependencies

**Outputs**:
- Success or evaluation errors
- Type checking results

**Invocation**: `nix flake check`

**Related use cases**: Daily development workflows

### CI-002: Build configurations for CI

**Purpose**: Build all system configurations in CI pipeline

**Inputs**:
- All darwinConfigurations
- All nixosConfigurations
- Test configurations

**Outputs**:
- Build success or failure
- Derivation outputs

**Invocation**: GitHub Actions workflows

**Related use cases**: Continuous integration validation

### CI-003: Run static analysis

**Purpose**: Lint and check code quality

**Inputs**:
- Nix source files
- Linting tools (statix, deadnix)

**Outputs**:
- Lint errors and warnings
- Code quality metrics

**Invocation**: `just lint`, pre-commit hooks

**Related use cases**: Development quality assurance

### CI-004: Cache build outputs

**Purpose**: Store builds in cachix for reuse

**Inputs**:
- Build outputs
- Cachix credentials
- Cache push configuration

**Outputs**:
- Derivations available in cache
- Faster subsequent builds

**Invocation**: Automatic in CI workflow

**Related use cases**: Build performance optimization

## Migration functions

These functions describe the migration from nixos-unified to dendritic + clan architecture.
Migration completed across 8-machine fleet (4 darwin: stibnite, blackphos, rosegold, argentum; 4 nixos VPS: cinnabar, electrum, galena, scheelite).

### MF-001: Convert modules to dendritic pattern

**Purpose**: Transform nixos-unified modules to dendritic

**Inputs**:
- Existing module in modules/{darwin,home,nixos}/
- Dendritic pattern knowledge
- flake.modules.* namespace

**Outputs**:
- Module in dendritic structure
- Cross-platform capability
- Type-safe imports via config.flake.modules.*

**Status**: COMPLETE - All modules converted to dendritic pattern with auto-discovery via import-tree

**Related use cases**: UC-007 (Migration)

### MF-002: Migrate secrets to clan vars

**Purpose**: Convert sops-nix secrets to clan vars generators

**Inputs**:
- Existing secrets in secrets/
- Generator definitions
- Migration strategy (generated vs external secrets)

**Outputs**:
- Generated secrets via clan vars
- Legacy user secrets remain in sops-nix during migration
- Migration architecture operational

**Status**: COMPLETE - Clan vars generators operational for secrets, sops-nix retained for legacy user secrets during migration

**Related use cases**: UC-007 (Migration), UC-003 (Secrets)

### MF-003: Validate migration readiness

**Purpose**: Ensure host ready for migration

**Inputs**:
- Validation criteria checklist
- Previous migration stability data
- Rollback procedure verification

**Outputs**:
- Go/no-go decision
- Risk assessment
- Prerequisites confirmation

**Status**: COMPLETE - All 8 machines validated and migrated successfully

**Related use cases**: UC-007 (Migration)

### MF-004: Monitor post-migration stability

**Purpose**: Track system stability after migration

**Inputs**:
- System metrics and logs
- Functionality validation tests
- Stability time window (1-2 weeks)

**Status**: COMPLETE - Fleet stable on dendritic + clan architecture

**Related use cases**: UC-007 (Migration)

## Infrastructure provisioning functions

### IF-001: Provision Hetzner VPS instances

**Purpose**: Create and configure Hetzner Cloud VPS instances via terraform

**Inputs**:
- Terranix configuration in terranix/
- Instance specifications (cinnabar, electrum)
- SSH keys and initial configuration
- Hetzner API credentials (from secrets)

**Outputs**:
- Running Hetzner VPS instances
- Public IP addresses assigned
- Initial NixOS installation ready
- Terraform state tracked

**Invocation**: `terraform apply` after terranix generation

**Related use cases**: Infrastructure deployment and expansion

### IF-002: Provision GCP instances

**Purpose**: Create and configure Google Cloud Platform instances via terraform

**Inputs**:
- Terranix configuration in terranix/
- Instance specifications (galena, scheelite)
- GCP project and credentials
- Network configuration

**Outputs**:
- Running GCP instances
- Network configuration applied
- Initial NixOS installation ready
- Terraform state tracked

**Invocation**: `terraform apply` after terranix generation

**Related use cases**: Infrastructure deployment and expansion

### IF-003: Manage infrastructure toggle state

**Purpose**: Enable/disable ephemeral infrastructure declaratively

**Inputs**:
- Infrastructure desired state (enabled/disabled flags)
- Terranix configuration
- Terraform state

**Outputs**:
- Infrastructure created or destroyed based on toggle
- Cost optimization via disabled ephemeral resources
- Permanent infrastructure (cinnabar) always maintained

**Invocation**: Configuration-driven via terranix toggle flags

**Related use cases**: Cost management, testing infrastructure

### IF-004: Generate terraform configuration from terranix

**Purpose**: Convert declarative Nix terranix to terraform JSON

**Inputs**:
- Terranix Nix expressions
- Provider configurations (Hetzner, GCP)
- Variable definitions

**Outputs**:
- terraform.tf.json with all resources
- Provider configurations
- Variable files

**Invocation**: `nix eval` or terranix build commands

**Related use cases**: All infrastructure provisioning workflows

## Operational functions

### OF-001: Deploy configuration to 8-machine fleet

**Purpose**: Update system configurations across darwin and NixOS machines

**Inputs**:
- Target machine(s) specification
- Updated flake configuration
- Generated secrets and vars
- Deployment method (darwin-rebuild or clan machines)

**Outputs**:
- Darwin machines (stibnite, blackphos, rosegold, argentum) updated via darwin-rebuild
- NixOS VPS (cinnabar, electrum, galena, scheelite) updated via clan machines
- Services restarted as needed
- New generation activated

**Invocation**:
- Darwin: `darwin-rebuild switch --flake .#<hostname>`
- NixOS: `clan machines update <hostname>` or batch operations

**Related use cases**: Daily operations, configuration updates

### OF-002: Manage zerotier mesh network

**Purpose**: Maintain overlay network connecting entire 8-machine fleet

**Inputs**:
- Zerotier controller (cinnabar)
- Peer configurations (7 other machines)
- Network membership rules
- Authorization credentials

**Outputs**:
- All 8 machines connected via zerotier mesh
- Private IPs assigned and stable
- Encrypted communication established
- NAT traversal operational

**Invocation**: Automated via service instance deployment (DF-007, MC-002)

**Related use cases**: UC-006 (Overlay network), UC-004 (Multi-host services)

### OF-003: Rotate secrets across fleet

**Purpose**: Update secrets and credentials for all machines

**Inputs**:
- New secret values
- Clan vars generators for rotated secrets
- Sops-nix configuration for external secrets
- Machine age keys

**Outputs**:
- Secrets regenerated via clan vars
- External secrets re-encrypted via sops-nix
- Updated secrets deployed to all affected machines
- Services restarted with new credentials

**Invocation**:
- Clan vars: `clan vars generate <hostname>` per machine
- Sops-nix: Manual re-encryption and deployment

**Related use cases**: UC-003 (Secrets), security operations

### OF-004: Propagate configuration updates across fleet

**Purpose**: Coordinate updates across multiple machines with dependencies

**Inputs**:
- Configuration changes affecting multiple machines
- Service instance definitions
- Role dependencies (e.g., controller must update before peers)
- Update orchestration plan

**Outputs**:
- Updates applied in correct order
- Service instances remain coordinated
- Zerotier mesh stability maintained
- Multi-host services continue operating

**Invocation**: Manual orchestration or clan machines batch commands

**Related use cases**: UC-004 (Multi-host services), fleet maintenance

## Function cross-reference

### By use case

- **UC-001 (Bootstrap)**: CM-003, SM-001, SM-002, DF-001, DF-002, DF-003, DF-004, IF-001, IF-002
- **UC-002 (Add feature module)**: CM-002, CM-004
- **UC-003 (Manage secrets declaratively)**: SM-001, SM-002, SM-003, SM-004, OF-003
- **UC-004 (Multi-host services)**: MC-001, MC-002, MC-003, MC-004, DF-007, OF-001, OF-002, OF-004
- **UC-005 (Handle broken packages)**: PM-001, PM-002, PM-003, PM-004
- **UC-006 (Overlay network)**: ON-001, ON-002, ON-003, ON-004, MC-002, DF-007, OF-002
- **UC-007 (Migration)**: MF-001, MF-002, MF-003, MF-004, DF-001, DF-002, DF-005, DF-006

### By operational category

- **Daily operations**: OF-001, OF-004, DF-001, DF-002, DF-003, DF-004, DF-007
- **Infrastructure provisioning**: IF-001, IF-002, IF-003, IF-004
- **Fleet management**: OF-001, OF-002, OF-004
- **Security operations**: OF-003, SM-001, SM-002, SM-003, SM-004

### By quality attribute

- **Reproducibility**: CM-001, CM-002, PM-001, CI-001, IF-004
- **Type safety**: CM-001, CM-004, MC-004
- **Security**: SM-001, SM-002, SM-003, SM-004, ON-004, OF-003
- **Maintainability**: CM-002, CM-004, PM-004, MF-001 (historical)
- **Modularity**: CM-004, MC-002, MC-003
- **Performance**: PM-006, CI-004
- **Scalability**: OF-001, OF-004, MC-001, MC-002

## Function hierarchy visualization

```
Configuration Management (CM)
├── CM-001: Flake evaluation
├── CM-002: Module auto-discovery
├── CM-003: Host configuration generation
└── CM-004: Cross-platform module composition

Secrets Management (SM)
├── SM-001: Generate clan vars
├── SM-002: Deploy secrets to hosts
├── SM-003: Share secrets across machines
└── SM-004: Encrypt secrets at rest

Package Management (PM)
├── PM-001: Multi-channel nixpkgs access
├── PM-002: Platform-specific stable fallbacks
├── PM-003: Apply upstream patches
├── PM-004: Override package builds
├── PM-005: Build custom packages
└── PM-006: Manage binary caching

Development Environment (DE)
├── DE-001: Provide development shell
├── DE-002: Automatic environment activation
└── DE-003: Task runner integration

Deployment (DF)
├── DF-001: Build darwin system configuration
├── DF-002: Activate darwin configuration
├── DF-003: Build NixOS system configuration
├── DF-004: Activate NixOS configuration
├── DF-005: Rollback to previous generation
├── DF-006: Perform dry-run activation
└── DF-007: Deploy with clan orchestration

Multi-host Coordination (MC)
├── MC-001: Define machine inventory
├── MC-002: Configure service instances
├── MC-003: Assign roles to machines
└── MC-004: Evaluate configuration hierarchy

Overlay Networking (ON)
├── ON-001: Configure zerotier controller
├── ON-002: Connect zerotier peers
├── ON-003: Manage overlay network membership
└── ON-004: Establish encrypted communication

CI/CD (CI)
├── CI-001: Validate flake evaluation
├── CI-002: Build configurations for CI
├── CI-003: Run static analysis
└── CI-004: Cache build outputs

Migration (MF)
├── MF-001: Convert modules to dendritic pattern
├── MF-002: Migrate secrets to clan vars
├── MF-003: Validate migration readiness
└── MF-004: Monitor post-migration stability

Infrastructure Provisioning (IF)
├── IF-001: Provision Hetzner VPS instances
├── IF-002: Provision GCP instances
├── IF-003: Manage infrastructure toggle state
└── IF-004: Generate terraform configuration from terranix

Operational Functions (OF) [8-machine fleet operations]
├── OF-001: Deploy configuration to 8-machine fleet
├── OF-002: Manage zerotier mesh network
├── OF-003: Rotate secrets across fleet
└── OF-004: Propagate configuration updates across fleet
```

## References

**Context layer**:
- [Domain model](../context/domain-model/) - Technical architecture details
- [Goals and objectives](../context/goals-and-objectives/) - System goals

**Requirements**:
- [Usage model](/development/requirements/usage-model/) - Use cases invoking these functions
- [Quality requirements](/development/requirements/quality-requirements/) - Non-functional requirements
- [System vision](/development/requirements/system-vision/) - Feature overview

**Architecture**:
- [Handling broken packages](/guides/handling-broken-packages) - Package management implementation
- ADRs - Architectural decision records
