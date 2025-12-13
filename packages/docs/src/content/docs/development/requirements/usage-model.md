---
title: Usage model
sidebar:
  order: 4
---

This document details the use cases from the system vision with complete scenarios, actors, preconditions, flows, and postconditions.

## Overview

The usage model specifies how the system is intended to be used from a black-box perspective.
Each use case describes user-visible interactions without constraining internal implementation.

Use cases describe the operational deferred module composition + clan architecture managing an 8-machine fleet (4 darwin laptops, 4 NixOS VPS) with terranix-provisioned cloud infrastructure.

## Use case catalog

### UC-001: Bootstrap new host with minimal configuration

**Actor**: System Administrator (crs58)

**Preconditions**:
- Nix installed on target host (darwin or NixOS)
- For VPS: Host provisioned via terranix (Hetzner, GCP)
- Repository cloned locally
- Age key generated for secrets
- Target host accessible (physical or via SSH)

**Main flow**:
1. Administrator creates host configuration in `modules/hosts/<hostname>/default.nix`
2. System imports deferred modules (`config.flake.modules.{darwin,nixos}.base`)
3. Administrator adds host to clan inventory with appropriate tags and machineClass
4. Administrator generates clan vars for the host: `clan vars generate <hostname>`
5. System generates required secrets (SSH keys, service credentials)
6. Administrator builds system configuration: `nix build .#darwinConfigurations.<hostname>.system` or `.#nixosConfigurations.<hostname>.config.system.build.toplevel`
7. Administrator activates configuration: `darwin-rebuild switch --flake .#<hostname>` or `nixos-rebuild switch --flake .#<hostname>`
8. System applies configuration, deploys secrets to `/run/secrets/`
9. Host successfully bootstrapped with minimal working system

**Alternate flows**:
- **A1**: If vars generation fails due to missing prompts, administrator provides required values interactively
- **A2**: If build fails due to evaluation errors, administrator debugs module imports and fixes type errors
- **A3**: If activation fails, administrator reviews logs, fixes issues, and retries activation or rolls back to previous generation

**Postconditions**:
- Host operational with base system configuration
- Secrets deployed to `/run/secrets/`
- SSH access configured
- Base development tools available
- Host ready for feature module additions

**References**:
- [Context: Domain model](../context/domain-model/) - Deferred module composition, clan inventory
- [Context: Project scope](../context/project-scope/) - Bootstrap rationale
- Migration plan: docs/notes/clan/integration-plan.md - Bootstrap patterns

**Example**:
```nix
# modules/hosts/argentum/default.nix
{ config, ... }:
{
  flake.modules.darwin."hosts/argentum" = {
    imports = [
      config.flake.modules.darwin.base
      config.flake.modules.darwin.system
      config.flake.modules.homeManager.shell
    ];

    networking.hostName = "argentum";
    system.stateVersion = 5;
  };
}
```

### UC-002: Add feature module spanning multiple platforms

**Actor**: Developer/Maintainer (crs58)

**Preconditions**:
- Deferred module composition + clan architecture operational
- Repository structure in place (`modules/{base,shell,dev,hosts}`)
- Understanding of cross-cutting concern pattern
- Target platforms identified (darwin, nixos, home-manager)

**Main flow**:
1. Developer creates feature module file in appropriate category (`modules/shell/fish.nix`)
2. System auto-discovers module via import-tree
3. Developer defines `flake.modules.darwin.<feature>` for darwin system configuration
4. Developer defines `flake.modules.homeManager.<feature>` for user environment configuration
5. Developer optionally defines `flake.modules.nixos.<feature>` for NixOS system configuration
6. Developer imports feature in host configurations via `config.flake.modules.<class>.<feature>`
7. System evaluates configuration, type-checks module options
8. Developer tests on one platform: `nix build .#darwinConfigurations.<hostname>.system`
9. Developer deploys to test host for validation
10. Developer verifies functionality across platforms
11. Feature module successfully deployed to all target platforms

**Alternate flows**:
- **A1**: If module evaluation fails, developer checks syntax and module system types
- **A2**: If platform-specific behavior needed, developer uses conditional logic (`lib.optionalAttrs stdenv.isDarwin`)
- **A3**: If circular dependency detected, developer reorganizes module imports
- **A4**: If feature conflicts with existing modules, developer resolves option collisions via priorities or merging

**Postconditions**:
- Feature module available in `flake.modules.{darwin,nixos,homeManager}.*` namespace
- Configuration deployed to all platforms importing the feature
- No platform-specific duplication (single source of truth)
- Module composable with other features

**References**:
- [Context: Domain model](../context/domain-model/) - Cross-cutting concerns
- [Context: Goals](../context/goals-and-objectives/) - G-U04: Cross-platform module composition

**Example**:
```nix
# modules/shell/fish.nix
{
  flake.modules = {
    darwin.shell-fish = {
      programs.fish.enable = true;
    };

    homeManager.shell-fish = { pkgs, ... }: {
      programs.fish = {
        enable = true;
        shellAliases = {
          ls = "eza";
          cat = "bat";
        };
      };
    };

    nixos.shell-fish = {
      programs.fish.enable = true;
    };
  };
}
```

### UC-003: Manage secrets via declarative generators

**Actor**: System Administrator (crs58)

**Preconditions**:
- Clan-core integrated in flake
- Age keys configured for administrator and hosts
- Clan inventory defines target machines
- Generator logic understood (prompts, dependencies, script, files)

**Main flow**:
1. Administrator defines generator in `clan.core.vars.generators.<name>`
2. System captures generator metadata (prompts, dependencies, output files)
3. Administrator specifies which files are secrets (`secret = true`) vs public (`secret = false`)
4. Administrator runs `clan vars generate <hostname>` for target host
5. System prompts for required inputs (passwords, tokens, etc.)
6. System executes generator script, produces files in `$out/`
7. System encrypts secrets with host age key to `sops/machines/<hostname>/secrets/`
8. System stores public values in `sops/machines/<hostname>/facts/`
9. Administrator commits encrypted secrets to version control
10. System automatically deploys secrets during configuration activation
11. Secrets available at `/run/secrets/<generator>.<file>` on target host

**Alternate flows**:
- **A1**: If generator has dependencies, system generates dependencies first (DAG composition)
- **A2**: If `share = true`, secret accessible to other machines in same group
- **A3**: If generation fails, administrator debugs script and retries
- **A4**: If host age key missing, administrator generates key and retries

**Postconditions**:
- Generator defined declaratively in configuration
- Secrets generated and encrypted per-host
- Secrets version-controlled (encrypted)
- Secrets deployed automatically during activation
- Secret paths available via `config.clan.core.vars.generators.<name>.files.<file>.path`

**References**:
- [Context: Domain model](../context/domain-model/) - Clan vars system
- [Context: Goals](../context/goals-and-objectives/) - G-U03: Declarative secrets management
- clan-core/docs/site/guides/vars/ - Vars system documentation
- Migration plan: Appendix on secrets migration

**Example**:
```nix
# modules/flake-parts/clan.nix
clan.core.vars.generators.ssh-host-key = {
  prompts = {};
  script = ''
    ssh-keygen -t ed25519 -f $out/id_ed25519 -N ""
  '';
  files = {
    id_ed25519 = { secret = true; };
    id_ed25519_pub = { secret = false; };
  };
};

# Use in configuration
services.openssh.hostKeys = [{
  path = config.clan.core.vars.generators.ssh-host-key.files.id_ed25519.path;
  type = "ed25519";
}];
```

### UC-004: Deploy coordinated service across hosts

**Actor**: System Administrator (crs58)

**Preconditions**:
- Multiple hosts in clan inventory with appropriate tags
- Service module available (clan built-in or custom)
- Understanding of clan service instances and roles
- Network connectivity between hosts (zerotier or direct)

**Main flow**:
1. Administrator defines service instance in `inventory.instances.<name>`
2. System registers instance with specified module (name and input source)
3. Administrator assigns machines or tags to roles (controller, peer, server, client)
4. Administrator configures instance-wide settings (apply to all roles)
5. Administrator configures role-wide settings (apply to all machines in role)
6. Administrator optionally configures machine-specific settings (overrides)
7. System evaluates configuration hierarchy: instance → role → machine
8. Administrator generates vars for all participating hosts
9. Administrator deploys configuration to each host: `clan machines update <hostname>`
10. System activates service on each host with role-appropriate configuration
11. Service operational across all participating hosts with coordination

**Alternate flows**:
- **A1**: If service requires shared secrets, administrator uses `share = true` in vars
- **A2**: If role assignment via tags doesn't match hosts, administrator adjusts tags or uses explicit machine assignment
- **A3**: If service fails on one host, administrator troubleshoots that host without affecting others
- **A4**: If configuration conflicts exist, system reports error and administrator resolves via priorities

**Postconditions**:
- Service instance deployed across multiple hosts
- Role-based configuration applied correctly
- Inter-host communication functional (if required)
- Service coordination operational
- Each host has appropriate role configuration

**References**:
- [Context: Domain model](../context/domain-model/) - Clan service instances
- [Context: Goals](../context/goals-and-objectives/) - G-U02: Multi-host coordination
- clan-core/docs/site/guides/inventory/ - Service instance patterns
- Migration plan: Zerotier example

**Example**:
```nix
# modules/flake-parts/clan.nix
inventory.instances.zerotier-local = {
  module = { name = "zerotier"; input = "clan-core"; };
  # VPS is controller (always-on)
  roles.controller.machines.cinnabar = {};
  # All workstations are peers
  roles.peer.tags."workstation" = {};
};

# Machines tagged with "workstation" automatically become zerotier peers
inventory.machines = {
  cinnabar = {
    tags = [ "nixos" "vps" "hetzner" ];
    machineClass = "nixos";
  };
  stibnite = {
    tags = [ "darwin" "workstation" ];
    machineClass = "darwin";
  };
  blackphos = {
    tags = [ "darwin" "workstation" ];
    machineClass = "darwin";
  };
  rosegold = {
    tags = [ "darwin" "workstation" ];
    machineClass = "darwin";
  };
  argentum = {
    tags = [ "darwin" "workstation" ];
    machineClass = "darwin";
  };
};
```

### UC-005: Handle broken package with multi-channel fallback

**Actor**: Developer/Maintainer (crs58)

**Preconditions**:
- Multi-channel nixpkgs inputs configured (unstable, stable, patched)
- Overlays infrastructure operational (`modules/nixpkgs/overlays/stable-fallbacks.nix`, `modules/nixpkgs/overlays/channels.nix`)
- Package broken in nixpkgs-unstable
- Understanding of overlay composition layers

**Main flow**:
1. Developer updates flake inputs: `nix flake update`
2. System builds fail due to broken package in unstable
3. Developer investigates issue (compilation failure, test failure, etc.)
4. Developer determines appropriate fix strategy (stable fallback, upstream patch, or build modification)
5. Developer edits appropriate overlay file (`stable-fallbacks.nix`, `patches.nix`, or `overrides/<package>.nix`)
6. Developer tests fix: `nix build .#legacyPackages.<system>.<package>`
7. System builds successfully using fixed package
8. Developer commits fix with tracking comment (hydra link, TODO condition)
9. System continues using fixed package until upstream resolution
10. Developer monitors upstream for fix, removes workaround when available

**Alternate flows**:
- **A1**: If multiple packages broken, developer considers flake.lock rollback before selective fixes
- **A2**: If upstream fix in PR exists, developer applies patch via `patches.nix` and references `pkgs.patched.<package>`
- **A3**: If package works but has minor issues, developer uses build modification in `overrides/<package>.nix`
- **A4**: If stable version also broken, developer investigates older stable channels or custom build

**Postconditions**:
- System builds successfully with fixed package
- Fix documented with tracking information
- Other packages continue using unstable
- No system-wide channel rollback required
- Fix removed when upstream resolves issue

**References**:
- [Context: Goals](../context/goals-and-objectives/) - G-U05: Surgical package fixes, G-S08: Stable fallbacks
- [Handling broken packages](/guides/handling-broken-packages) - Complete implementation guide
- modules/nixpkgs/overlays/stable-fallbacks.nix - Platform-specific stable fallbacks
- modules/nixpkgs/overlays/channels.nix - Upstream patch list

**Example**:
```nix
# modules/nixpkgs/overlays/stable-fallbacks.nix
// (prev.lib.optionalAttrs prev.stdenv.isDarwin {
  inherit (final.stable)
    # https://hydra.nixos.org/job/nixpkgs/trunk/buf.aarch64-darwin
    # Compilation fails with llvm 21.x in unstable
    # Uses llvm 19.x from stable channel
    # TODO: Remove when llvm 21.x compatibility fixed
    buf
    ;
})
```

### UC-006: Establish secure overlay network

**Actor**: System Administrator (crs58)

**Preconditions**:
- VPS infrastructure deployed (cinnabar as permanent controller, electrum/galena/scheelite as optional peers)
- Clan zerotier service module available
- All hosts have clan vars generated
- Network configuration understood (controller vs peer roles)

**Main flow**:
1. Administrator provisions VPS infrastructure via terranix (Hetzner for cinnabar, optional Hetzner/GCP for others)
2. Administrator defines zerotier service instance in clan inventory
3. System registers cinnabar as controller role (always-on VPS)
4. Administrator assigns darwin hosts as peer role via tags
5. System generates zerotier credentials and network configuration
6. Administrator deploys configuration to controller: `clan machines update cinnabar`
7. System activates zerotier controller on cinnabar, creates network
8. Administrator deploys configuration to peers: `clan machines update <hostname>` for each
9. System activates zerotier peer on each darwin host, joins network
10. Peers authenticate with controller, establish encrypted tunnels
11. System assigns private IP addresses to each peer in overlay network
12. Administrator tests connectivity: `ping <peer-zerotier-ip>` from any host
13. Overlay network operational with encrypted communication between all hosts

**Alternate flows**:
- **A1**: If peer fails to connect, administrator checks firewall rules and network accessibility
- **A2**: If controller unavailable, peers cache credentials and reconnect when available
- **A3**: If network ID conflicts, administrator generates new network via controller
- **A4**: If authentication fails, administrator regenerates zerotier vars and redeploys

**Postconditions**:
- Zerotier controller operational on cinnabar VPS
- All darwin hosts (stibnite, blackphos, rosegold, argentum) connected as peers
- Optional VPS peers (electrum, galena, scheelite) connected when active
- Private overlay network established (e.g., 10.147.17.0/24)
- Encrypted communication between all hosts
- Network survives host reboots and network changes
- Hosts reachable via stable zerotier IPs

**References**:
- [Context: Goals](../context/goals-and-objectives/) - G-U06: Secure overlay networking
- [Context: Domain model](../context/domain-model/) - Zerotier overlay networking
- clan-core/clanServices/zerotier/ - Zerotier service module
- Migration plan: Phase 1 VPS deployment

**Example**:
```nix
# modules/flake-parts/clan.nix
inventory.instances.zerotier-local = {
  module = { name = "zerotier"; input = "clan-core"; };
  # cinnabar is controller (VPS, always-on)
  roles.controller.machines.cinnabar = {};
  # All workstations are peers
  roles.peer.tags."workstation" = {};
};

# Automatically generates:
# - Network ID
# - Controller credentials
# - Peer authentication tokens
# - Network member authorization
```

### UC-007: Migrate host to deferred module composition + clan architecture

**Status**: COMPLETE (November 2024) - This use case describes the historical migration workflow from nixos-unified to deferred module composition + clan architecture. All machines have been migrated. Preserved as reference for understanding the migration patterns used.

**Actor**: System Administrator (crs58)

**Preconditions**:
- Target host currently on nixos-unified architecture
- Deferred module composition + clan patterns validated (Phase 0)
- VPS infrastructure operational (Phase 1) if darwin migration
- Previous host migrations successful and stable (if not first migration)
- Target host fully backed up
- Rollback procedure documented and tested

**Main flow**:
1. Administrator creates feature branch for migration: `git checkout -b migrate-<hostname>`
2. Administrator creates deferred module composition host configuration in `modules/hosts/<hostname>/default.nix`
3. Administrator converts relevant modules from `modules/{darwin,home,nixos}/` to deferred module composition pattern
4. Administrator imports converted modules in host config via `config.flake.modules.*`
5. Administrator adds host to clan inventory with appropriate tags
6. Administrator generates clan vars for host: `clan vars generate <hostname>`
7. Administrator builds new configuration: `nix build .#darwinConfigurations.<hostname>.system`
8. System evaluates dendritic + clan configuration, type-checks modules
9. Administrator reviews build output, compares with current system
10. Administrator performs dry-run: `darwin-rebuild switch --flake .#<hostname> --dry-run`
11. Administrator backs up current generation: `darwin-rebuild --list-generations`
12. Administrator deploys new configuration: `darwin-rebuild switch --flake .#<hostname>`
13. System activates deferred module composition + clan configuration, deploys secrets
14. Administrator validates functionality: development tools, services, networking
15. Administrator connects to zerotier network: verifies overlay network connectivity
16. Administrator monitors stability for 1-2 weeks before next host migration
17. Host successfully migrated to deferred module composition + clan architecture

**Alternate flows**:
- **A1**: If build fails, administrator debugs errors, fixes module issues, retries build
- **A2**: If activation fails, administrator reviews activation logs, fixes configuration, retries or rolls back
- **A3**: If functionality regresses, administrator rolls back immediately: `sudo /nix/var/nix/profiles/system-<previous>-link/activate`
- **A4**: If critical workflow broken, administrator reverts via git: `git checkout main && darwin-rebuild switch`
- **A5**: If zerotier connection fails, administrator troubleshoots network, regenerates vars, redeploys
- **A6**: If home-manager configuration conflicts with clan, administrator resolves via module system priorities
- **A7**: If stability issues emerge, administrator keeps host on nixos-unified, investigates root cause before retrying

**Postconditions**:
- Host operational on deferred module composition + clan architecture
- All functionality from nixos-unified preserved
- Clan vars deployed and functional
- Zerotier network connectivity established
- Host stable and ready for daily use
- nixos-unified configuration preserved for rollback
- Migration documented with any issues encountered

**References**:
- [Context: Project scope](../context/project-scope/) - Migration strategy
- [Context: Goals](../context/goals-and-objectives/) - All system goals achieved
- Migration plan: Phase-specific guides (phase-2-blackphos-guide.md, etc.)
- Migration assessment: docs/notes/clan/migration-assessment.md - Per-host considerations

**Migration order** (completed November 2024):
- Phase 0: test-clan (validation environment) - COMPLETE - validated integration
- Phase 1: VPS infrastructure (cinnabar, electrum, galena, scheelite) - COMPLETE - foundation deployed via terranix
- Phase 2: blackphos (darwin) - COMPLETE - first darwin, established patterns
- Phase 3: rosegold (darwin) - COMPLETE - validated pattern reusability
- Phase 4: argentum (darwin) - COMPLETE - final validation
- Phase 5: stibnite (darwin) - COMPLETE - primary workstation migrated
- Phase 6: Cleanup - COMPLETE - nixos-unified removed

**Example deferred module composition conversion**:
```nix
# Current (nixos-unified): configurations/darwin/blackphos.nix
{ inputs, config, pkgs, ... }:
{
  imports = [
    ../modules/darwin/homebrew.nix
    ../modules/home/shell.nix
  ];
  networking.hostName = "blackphos";
}

# Target (deferred module composition): modules/hosts/blackphos/default.nix
{ config, ... }:
{
  flake.modules.darwin."hosts/blackphos" = {
    imports = [
      config.flake.modules.darwin.base
      config.flake.modules.darwin.homebrew
      config.flake.modules.homeManager.shell
    ];

    networking.hostName = "blackphos";
    system.stateVersion = 5;
  };
}
```

## Use case dependencies

```
UC-001 (Bootstrap)
    ├─→ UC-002 (Add features) - After bootstrap, add features
    └─→ UC-003 (Secrets) - Bootstrap requires vars generation

UC-002 (Add features)
    └─→ UC-005 (Handle broken packages) - May be needed for feature dependencies

UC-003 (Secrets)
    └─→ UC-004 (Multi-host services) - Services require secrets

UC-004 (Multi-host services)
    ├─→ UC-003 (Secrets) - Services need generated secrets
    └─→ UC-006 (Overlay network) - Network enables coordination

UC-005 (Handle broken packages)
    └─→ [Independent] - Operational concern, applies throughout

UC-006 (Overlay network)
    ├─→ UC-001 (Bootstrap) - VPS must be bootstrapped first
    └─→ UC-004 (Multi-host services) - Zerotier is a multi-host service

UC-007 (Migration)
    ├─→ UC-001 (Bootstrap) - Uses bootstrap patterns
    ├─→ UC-003 (Secrets) - Migrates to clan vars
    └─→ UC-006 (Overlay network) - Connects to zerotier after migration
```

## Actor catalog

### System Administrator (crs58)

**Primary responsibilities**:
- Manage host configurations and deployments
- Configure and maintain clan inventory
- Generate and deploy secrets via clan vars
- Monitor system stability and troubleshoot issues
- Perform migrations and rollbacks
- Establish and maintain overlay network

**Skills required**:
- Nix language and module system proficiency
- Understanding of deferred module composition
- Familiarity with clan architecture
- System administration (darwin and NixOS)
- Network configuration (zerotier, SSH)
- Git version control

**Tools used**:
- `nix` command (build, flake, eval)
- `darwin-rebuild` or `nixos-rebuild`
- `clan` CLI (vars, machines)
- `git` for version control
- `just` task runner for common operations
- Editor with Nix language support

### Developer/Maintainer (crs58)

**Primary responsibilities**:
- Create and maintain feature modules
- Handle broken packages via overlay fixes
- Write cross-platform modules
- Test configurations before deployment
- Document architectural decisions
- Contribute to codebase improvements

**Skills required**:
- Nix language proficiency
- Module system and overlay composition
- Multi-channel nixpkgs stable fallback patterns
- Cross-platform development (darwin, NixOS)
- Testing and validation workflows

**Tools used**:
- Same as System Administrator
- Additionally: `rg`, `fd` for code search
- `nix flake check` for validation
- CI/CD tools (GitHub Actions)

**Note**: In this project, System Administrator and Developer/Maintainer are the same person (crs58) with different role contexts.

## Common workflows

### Daily development workflow

1. Edit configuration files
2. Test locally: `nix flake check`
3. Build system: `just verify`
4. Commit atomically: `git add <file> && git commit -m "..."`
5. Deploy when ready: `darwin-rebuild switch --flake .#<hostname>`

### Package update workflow

1. Update inputs: `nix flake update`
2. Test builds: `just verify`
3. Fix broken packages if needed (UC-005)
4. Commit: `git add flake.lock && git commit -m "chore(deps): update flake inputs"`
5. Deploy to non-primary hosts first
6. Monitor stability before primary workstation

### Multi-host deployment workflow

1. Define or update service instance in clan inventory
2. Generate vars for all hosts: `clan vars generate <hostname>` for each
3. Build configurations: `just verify`
4. Deploy to controller first: `clan machines update cinnabar`
5. Deploy to peers: `clan machines update <hostname>` for each
6. Verify service coordination: test inter-host communication
7. Monitor stability across all hosts

## Quality attributes

The usage model supports the following quality attributes from [quality requirements](/development/requirements/quality-requirements/):

- **Reproducibility**: Use cases produce deterministic outcomes via Nix evaluation and locked inputs
- **Type safety**: Module system type checking validates configurations at evaluation time
- **Maintainability**: Clear workflows and patterns reduce cognitive load and time investment
- **Modularity**: Cross-platform modules enable feature reuse across hosts
- **Security**: Encrypted secrets management via clan vars with age encryption
- **Reliability**: Rollback capability in all deployment workflows

## References

**Context layer**:
- [Project scope](../context/project-scope/) - Migration strategy and architectural rationale
- [Domain model](../context/domain-model/) - Technical architecture details
- [Goals and objectives](../context/goals-and-objectives/) - Strategic goals driving use cases

**Architecture**:
- [Handling broken packages](/guides/handling-broken-packages) - Multi-channel stable fallback implementation
- ADR-0014: Design principles - Framework independence, type safety

**Migration planning** (internal, not published):
- docs/notes/clan/integration-plan.md - Complete migration strategy
- docs/notes/clan/phase-0-validation.md - Pattern validation approach
- docs/notes/clan/phase-1-vps.md - VPS deployment guide
- docs/notes/clan/phase-2-blackphos.md - First darwin migration guide
- docs/notes/clan/migration-assessment.md - Per-host validation criteria

**External**:
- Dendritic pattern: https://github.com/mightyiam/dendritic
- Clan docs: https://docs.clan.lol/
- Clan inventory guide: clan-core/docs/site/guides/inventory/
- Clan vars guide: clan-core/docs/site/guides/vars/
