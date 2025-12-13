---
title: Domain model
---

This document describes the domain in which the system operates, including the Nix ecosystem and current architecture components based on deferred module composition + clan.

## Nix ecosystem overview

### Core concepts

- **Nix**: Functional package manager providing declarative, reproducible package management.
- **NixOS**: Linux distribution built on Nix package manager.
- **nix-darwin**: System configuration management for macOS using Nix.
- **home-manager**: User environment management working across NixOS, nix-darwin, and standalone installations.

- **Flakes**: Modern Nix feature providing hermetic, reproducible builds with lock files.
- **Derivations**: Build recipes describing how to produce outputs from inputs.
- **Overlays**: Mechanism to modify or extend nixpkgs package set.
- **Module system**: Type-safe configuration composition system with options, types, and validation.

### Package channels

- **nixpkgs**: Official Nix packages repository.
- **nixpkgs-unstable**: Rolling release channel with latest packages.
- **nixpkgs-stable**: Point releases (24.05, 24.11, etc.) with backported security fixes.
- **Following inputs**: Flake mechanism to ensure consistent dependency versions across composition.

## Current architecture domain model

### Deferred module composition

- **Core principle**: Every file is a flake-parts module.
- **Namespace**: Modules contribute to `flake.modules.<type>.*` where type is `nixos`, `darwin`, or `homeManager`.

**File organization**:
```
modules/
├── base/              # Foundation modules (cross-platform)
│   ├── nix.nix        # Core nix settings
│   └── system.nix     # State versions
├── shell/             # Shell tools
│   ├── fish.nix
│   └── starship.nix
├── dev/               # Development tools
│   └── git/
├── hosts/             # Machine-specific configurations
│   ├── blackphos/
│   ├── rosegold/
│   ├── argentum/
│   ├── stibnite/
│   ├── cinnabar/
│   ├── electrum/
│   ├── galena/
│   └── scheelite/
├── flake-parts/       # Flake-level configuration
│   ├── nixpkgs.nix
│   ├── clan.nix
│   └── *-machines.nix
└── users/             # User configurations
    └── crs58/
```

**import-tree**: Auto-discovery mechanism replacing manual imports.
Recursively imports all `.nix` files from `modules/`, each becomes a flake-parts module.

**Value sharing**: Via `config.flake.*` instead of specialArgs.
Example: `config.flake.meta.users.crs58.email` accessible from any module.

**Cross-cutting concerns**: Single module can define configuration for multiple platforms.

Example module structure:
```nix
# modules/shell/fish.nix
{
  flake.modules = {
    darwin.shell = {
      programs.fish.enable = true;
    };

    homeManager.shell = { pkgs, ... }: {
      programs.fish = {
        enable = true;
        shellAliases = { /* ... */ };
      };
    };
  };
}
```

**specialArgs minimization**: Only framework values (inputs, self) passed via specialArgs.
Application values use `config.flake.*` namespace.

**Reference**: `~/projects/nix-workspace/dendritic-flake-parts/README.md`

### Flake-parts integration

- **flake-parts**: Framework for modular flake composition using Nix module system.
- **perSystem**: Per-system configuration (packages, devShells, etc. for each platform).
- **flake.nix structure**: Uses `flake-parts.lib.mkFlake` with imports via import-tree from `./modules/`.
- **Module auto-loading**: import-tree automatically discovers and imports all `.nix` files from `./modules/` directory.

### Module organization

- **modules/flake-parts/**: Flake-level configuration modules.
- **modules/darwin/**: Darwin-specific system modules.
- **modules/nixos/**: NixOS-specific system modules.
- **modules/home/**: Home-manager modules (user environment).
- **modules/hosts/**: Per-host configuration directories.
- **modules/nixpkgs/overlays/**: Package overlays and modifications.

- **Import pattern**: Modules imported via import-tree auto-discovery, composed through module system.
- **specialArgs usage**: Minimal - only framework values (inputs, self). Application values via `config.flake.*`.

### Multi-channel stable fallback pattern

- **Problem**: Single channel can have broken packages.
- **Solution**: Multiple nixpkgs inputs with overlay-based selection.

**Implementation**:
- Multiple channel inputs: `nixpkgs` (unstable), `nixpkgs-stable` (24.11), potentially others
- Overlay composition in `modules/nixpkgs/overlays/` directory
- Per-package channel selection or custom builds
- No system-wide channel rollback required for individual package issues

**Patterns**:
- **Stable fallback**: Use stable channel version when unstable broken
- **Upstream patch**: Apply patch from upstream PR to current version
- **Build override**: Custom build parameters or dependencies

**Reference**: [Handling broken packages](/guides/handling-broken-packages), [ADR-0017: Dendritic overlay patterns](/development/architecture/adrs/0017-dendritic-overlay-patterns)

### Secrets management

**clan vars system**: Declarative secret and file generation with automatic deployment.

**Generators**: `clan.core.vars.generators.<name>` define generation logic.
Components:
- `prompts`: User input requirements
- `dependencies`: Other generators (DAG composition)
- `script`: Generation logic producing files in `$out/`
- `files.<name>`: Output file definitions with `secret` flag

**Secret vs public files**:
- `secret = true`: Encrypted, deployed to `/run/secrets/`, accessed via `.path`
- `secret = false`: Plain text, stored in nix store, accessed via `.value`

- **Sharing**: `share = true` allows cross-machine secret access.
- **Storage**: SOPS-encrypted in `sops/machines/<hostname>/secrets/` (secrets) and `sops/machines/<hostname>/facts/` (public).

**Deployment**: Automatic during `clan machines update <hostname>`.

**Manual generation**: `clan vars generate <hostname>`.

Example:
```nix
clan.core.vars.generators.ssh-key = {
  prompts = {};
  script = ''
    ssh-keygen -t ed25519 -f $out/id_ed25519 -N ""
  '';
  files = {
    id_ed25519 = { secret = true; };
    id_ed25519_pub = { secret = false; };
  };
};
```

### Development environment

- **nix develop**: Flake-based development shells.
- **direnv**: Automatic environment activation on directory entry.
- **just**: Task runner for common operations (check, build, activate, test, lint).

**Provided tools** (via devShell):
- Bun (package manager and runtime)
- Node.js (compatibility)
- Playwright browsers (E2E testing)
- Development utilities (gh, sops, git, editors)

**Reference**: ADR-0009 (Nix flake-based development environment)

### Build and deployment

**Clan-based deployment**:
- `clan machines update <hostname>`: Deploy configuration to machine
- `clan machines install <hostname>`: Install NixOS on new machine
- `clan vars generate <hostname>`: Generate secrets and vars

**Traditional rebuild tools** (still supported):
- `darwin-rebuild switch --flake .#<hostname>`: Activate nix-darwin configuration
- `nixos-rebuild switch --flake .#<hostname>`: Activate NixOS configuration

**Activation command examples**:
```bash
# Clan deployment (recommended)
clan machines update stibnite
clan machines update cinnabar

# Traditional rebuild (legacy)
darwin-rebuild switch --flake .#stibnite
nixos-rebuild switch --flake .#cinnabar
```

**CI/CD**:
- GitHub Actions workflows in `.github/workflows/`
- Automated checks: flake evaluation, builds, linting, tests
- Cachix for binary cache
- justfile integration for local/CI parity

**Reference**: `docs/development/traceability/ci-philosophy.md`, ADR-0012 (GitHub Actions pipeline)

### Host inventory

**Darwin hosts** (all aarch64-darwin):
- `stibnite`: crs58's primary workstation
- `blackphos`: raquel's primary workstation
- `rosegold`: janettesmith's primary workstation
- `argentum`: christophersmith's primary workstation

**NixOS VPS hosts** (all x86_64-linux):
- `cinnabar`: Permanent Hetzner VPS, zerotier controller, core services
- `electrum`: Secondary Hetzner VPS
- `galena`: GCP CPU compute instance
- `scheelite`: GCP GPU compute instance

**Configuration location**: `modules/hosts/<hostname>/default.nix`

**Inventory definition**: `modules/flake-parts/clan.nix` (clan inventory with tags and service instances)

### Clan-core architecture

**Foundation**: Library-centric design with NixOS modules, Python CLI, multiple frontends.

**Key components**:
1. **Flake integration**: `clan-core.flakeModules.default` provides flake-parts integration
2. **Inventory system**: Abstract service layer for multi-machine coordination
3. **Vars system**: Declarative secret and file generation
4. **Service instances**: New module class (`_class = "clan.service"`) with roles
5. **CLI tools**: `clan` command for machine management, deployment, vars

#### Inventory system

**Purpose**: Centralized definition of machines, services, and their relationships.

- **Machines**: `inventory.machines.<name>` with tags and machineClass.
- **Tags**: Labels for grouping machines (e.g., "workstation", "server", "nixos", "darwin").
- **machineClass**: Platform type ("nixos" or "darwin").

- **Instances**: `inventory.instances.<name>` define service instances.
- **Roles**: Different functions within service (server, client, peer, controller).
- **Role assignment**: Via `roles.<name>.machines.<hostname>` or `roles.<name>.tags.<tag>`.

**Configuration hierarchy**:
- Instance-wide settings apply to all roles
- Role-wide settings apply to all machines in that role
- Machine-specific settings override role-wide

Example:
```nix
inventory.instances.zerotier-local = {
  module = { name = "zerotier"; input = "clan-core"; };
  roles.controller.machines.cinnabar = {};
  roles.peer.tags."workstation" = {};
};
```

#### Vars system

See "Secrets management" section above for full details on the clan vars system.

#### Clan services

- **Service instances**: Multiple instances of same service type.
- **Role-based configuration**: Different roles per instance (client/server/peer/controller).

**Service module structure**:
- `roles.<name>.interface`: Define configuration options for role
- `roles.<name>.perInstance`: Map over instances, produce nixosModule
- `perMachine`: Map over machines, produce nixosModule

**Built-in services** (from clan):
- `emergency-access`: Root access recovery
- `sshd`: SSH daemon with certificate authority
- `zerotier`: Overlay VPN networking
- `borgbackup`: Backup management
- `users`: User account management
- Many others

**Custom services**: Users can define own service modules following clan service pattern.

#### Zerotier overlay networking

**Purpose**: Secure private network between hosts, works across NAT/firewalls.

**Roles**:
- `controller`: Manages network, authorizes peers (cinnabar in our architecture)
- `moon`: L2 relay for NAT traversal (optional)
- `peer`: Network member (all workstations)

**Configuration**: Via clan service instance, automatic setup and credential management.

**Benefits**:
- Encrypted communication
- Works across different networks
- Automatic reconnection
- Private IP space for inter-host communication

### Terraform/terranix provisioning

**Purpose**: Declarative cloud infrastructure provisioning for VPS.

- **terranix**: Nix-based Terraform configuration generator.
- **Hetzner Cloud API**: VPS provisioning via terraform provider.

**Workflow**:
1. Define infrastructure in `modules/terranix/` (Nix expressions)
2. terranix generates Terraform JSON
3. Terraform provisions actual resources
4. clan deploys NixOS to provisioned VPS

**Integration**: terranix.flakeModule provides `perSystem.terranix` configuration.

### Disko declarative partitioning

**Purpose**: Declarative disk partitioning and formatting.

**Features**:
- Partition tables (GPT, MBR)
- Filesystems (ext4, btrfs, zfs, etc.)
- LUKS encryption
- LVM configuration

**Usage**: Define disk layout in Nix, disko handles partitioning during installation.

**Integration**: NixOS module, used during `clan machines install`.

### Srvos server hardening

**Purpose**: Hardening and best practices for NixOS servers.

**Features**:
- Security-focused defaults
- Common server configurations
- Hardware-specific optimizations

**Integration**: NixOS modules imported into server configurations.

## Domain processes

### Configuration development workflow

1. **Edit configuration**: Modify Nix files in repository
2. **Test locally**: `nix flake check`, `just check`
3. **Validate**: `just verify` (dry-run builds)
4. **Commit**: Atomic commits per file with conventional messages
5. **Deploy**: `clan machines update <hostname>` or traditional rebuild tools
6. **Monitor**: Check logs, verify functionality
7. **Rollback if needed**: `clan machines update <hostname>` with previous commit, or git revert + redeploy

### Secret management workflow

**Clan vars** (current):
1. Define generator in configuration
2. Generate vars: `clan vars generate <hostname>`
3. Commit encrypted vars to `sops/machines/<hostname>/`
4. Deploy: clan deploys vars to `/run/secrets/`

### Multi-host coordination workflow

1. **Define inventory**: Machines, tags, service instances in `modules/flake-parts/clan.nix`
2. **Assign roles**: Via tags or specific machine names
3. **Configure services**: Instance-wide, role-wide, or machine-specific settings
4. **Generate vars**: For all machines requiring secrets
5. **Deploy**: `clan machines update <hostname>` for each host
6. **Verify**: Check service status, network connectivity, coordination

### Package override workflow

**Problem**: Package broken in nixpkgs-unstable.

**Solutions**:
1. **Stable fallback**: Use version from nixpkgs-stable
2. **Upstream patch**: Apply patch from upstream repository or PR
3. **Custom build**: Override build inputs, patches, or parameters

**Implementation**: Overlay in `modules/nixpkgs/overlays/` directory modifying specific package.

**Example**:
```nix
# modules/nixpkgs/overlays/fix-broken-package.nix
final: prev: {
  broken-package = prev.nixpkgs-stable.broken-package;  # Stable fallback
}
```

### Historical note: migration from nixos-unified

The infrastructure completed migration from nixos-unified to deferred module composition + clan.

**Migration was progressive host-by-host**:
1. **Initial validation**: Validated deferred module composition + clan in test-clan repository
2. **VPS foundation**: Deployed cinnabar VPS using validated patterns
3. **Darwin migrations**: Migrated darwin hosts incrementally (blackphos → rosegold → argentum → stibnite)
4. **Architecture cleanup**: Removed nixos-unified, completed cleanup

**Per-host migration steps**:
1. Created `modules/hosts/<hostname>/default.nix` using deferred module composition
2. Defined in clan inventory
3. Generated clan vars
4. Tested build: `nix build .#darwinConfigurations.<hostname>.system`
5. Deployed: `darwin-rebuild switch --flake .#<hostname>`
6. Validated functionality
7. Monitored stability for 1-2 weeks
8. Proceeded to next host

## Domain constraints

**Nix evaluation constraints**:
- Pure functional evaluation (no side effects during evaluation)
- Hermetic builds (reproducible, no network access during build)
- Type checking via module system (evaluation-time, not compile-time)

**Platform-specific constraints**:
- Darwin-specific features (system preferences, Homebrew)
- NixOS-specific features (systemd services, kernel modules)
- home-manager works across both but some features platform-specific

**Flake constraints**:
- Must have `flake.nix` in repository root
- Inputs must be lockable (git repos, tarballs, not local paths)
- Outputs follow standard schema (packages, nixosConfigurations, etc.)

**Module system constraints**:
- Options must have explicit types
- Configuration values must match option types
- Imports must resolve without cycles
- Module evaluation order matters for some features

## External systems

**Cachix**: Binary cache service for Nix.
- Stores pre-built derivations
- Speeds up builds by avoiding rebuilds
- Used in CI/CD pipeline

**GitHub**:
- Source code hosting (git repository)
- Issue tracking and discussions
- CI/CD via GitHub Actions
- Secret storage (GitHub Secrets for CI)

**Hetzner Cloud** (target):
- VPS hosting provider
- API-driven provisioning via Terraform
- Hosts cinnabar infrastructure

**Bitwarden** (current):
- Offline backup for age keys
- Manual secret storage
- Disaster recovery

## Domain-specific terminology

See `glossary.md` for comprehensive term definitions.

## References

### Architecture components

- flake-parts: <https://flake.parts/>
- Deferred module composition pattern: <https://github.com/mightyiam/dendritic>
- import-tree: <https://github.com/vic/import-tree>
- clan: <https://docs.clan.lol/>
- terranix: <https://terranix.org/>
- disko: <https://github.com/nix-community/disko>
- srvos: <https://github.com/nix-community/srvos>
- Multi-channel stable fallbacks: [Handling broken packages](/guides/handling-broken-packages)

### Nix ecosystem

- Nix: <https://nixos.org/>
- nixpkgs: <https://github.com/NixOS/nixpkgs>
- nix-darwin: <https://github.com/LnL7/nix-darwin>
- home-manager: <https://github.com/nix-community/home-manager>

### Historical/deprecated

- nixos-unified: <https://github.com/srid/nixos-unified> (deprecated, replaced by deferred module composition + clan)
- sops-nix: <https://github.com/Mic92/sops-nix> (replaced by clan vars system)
