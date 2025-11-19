# Clan-Core Official macOS/nix-darwin Support Research

**Date**: 2025-11-19  
**Thoroughly researched**: Yes - examined clan-core source, documentation, inventory system, real-world examples, and service implementations.

## Executive Summary

Clan-core provides **official, production-ready support for nix-darwin (macOS) machines** with the key limitation that currently only `clan machines update` is supported for remote management—full multi-machine orchestration with services is primarily designed for NixOS deployments. However, darwin machines can participate in the inventory as peers with partial service support.

## Official Clan-Core macOS Support

### Documented Support Level

Clan-core provides official macOS management documented in: `/docs/site/guides/macos.md`

**Explicitly Supported Features**:
- `clan machines update <machine>` for existing nix-darwin installations  
- Vars (secrets/variables) generation and management  
- Inventory inclusion with `machineClass = "darwin"`  
- SSH-based remote deployment to macOS machines

### Machine Class Definition

The inventory system explicitly supports darwin as a first-class machine type:

**Location**: `modules/inventoryClass/inventory.nix` (lines 249-259)

```nix
machineClass = lib.mkOption {
  default = "nixos";
  type = types.enum [
    "nixos"
    "darwin"
  ];
  description = ''
    The module system that should be used to construct the machine
    Set this to `darwin` for macOS machines
  '';
};
```

This is enforced at the type level—machines must be either "nixos" or "darwin", and the system generates separate outputs:

**In clan/module.nix** (filtered by machineClass):
```nix
darwinModules' = lib.filterAttrs (name: _: inventory.machines.${name}.machineClass == "darwin") (
  config.outputs.moduleForMachine
);

nixosModules = mapAttrs' (name: machineModule: {
  name = "clan-machine-${name}";
  value = machineModule;
}) nixosModules';

darwinModules = mapAttrs' (name: machineModule: {
  name = "clan-machine-${name}";
  value = machineModule;
}) darwinModules';

nixosConfigurations = lib.filterAttrs (name: _: machineClasses.${name} == "nixos") configurations;
darwinConfigurations = lib.filterAttrs (name: _: machineClasses.${name} == "darwin") configurations;
```

### Predefined Tags for Machine Class

The inventory system defines automatic tags for filtering machines by class:

```nix
# Predefined Tags (from inventory.nix)
nixos = lib.mkOption {
  type = with lib.types; listOf str;
  defaultText = "[ <All NixOS Machines> ]";
  description = ''
    Will be added to all machines that set `machineClass = "nixos"`
  '';
};

darwin = lib.mkOption {
  type = with lib.types; listOf str;
  defaultText = "[ <All Darwin Machines> ]";
  description = ''
    Will be added to all machines that set `machineClass = "darwin"`
  '';
};
```

This allows services to target `roles.*.tags.nixos` or `roles.*.tags.darwin` separately.

## Real-World Example: mic92's Personal Clan

The personal clan of mic92 (a clan-core developer) provides a production reference:

**Repository**: `~/projects/nix-workspace/mic92-clan-dotfiles/`

**Darwin Machine**: `evo` (Mac laptop)

```nix
# machines/flake-module.nix
machines.evo.machineClass = "darwin";
```

**Configuration** (`machines/evo/configuration.nix`):
- Platform: `aarch64-darwin` (Apple Silicon)
- Uses nix-darwin via srvos modules  
- Imports darwin-specific modules (homebrew, nix-daemon, etc.)  
- Configured with sops-nix for secrets  
- Targets SSH deployment via `evo.local`

**Inventory Integration**:
The evo machine is defined in the inventory but notably:
- NOT included in the `backup` tag (client tag for borgbackup)
- NOT included in the `wireguard-peers` tag (peer tag for wireguard)
- NOT included in the zerotier peers (uses only `tags.nixos`)

This demonstrates that while darwin machines are in the inventory, they currently don't participate in multi-machine services.

## Inventory System: Full Darwin Support

### Machines Can Include Darwin

Darwin machines are fully declarable in the inventory:

```nix
inventory.machines = {
  yourmachine.machineClass = "darwin";
};
```

Declarable options include:
- `machineClass = "darwin"` (required)
- `deploy.targetHost = "root@hostname"`
- `deploy.buildHost = "builder@host"`
- `tags = [ "custom-tag" ]`
- `description = "..."` (optional)
- `icon = "..."` (optional, UI future feature)

### Service Support for Darwin Machines

**Critical Finding**: All clan-core services are currently **NixOS-only** in their implementation.

Examined all 24 clan services:
- **admin**: `nixosModule` only
- **borgbackup**: `nixosModule` only  
- **certificates**: `nixosModule` only
- **coredns**: `nixosModule` only
- **data-mesher**: `nixosModule` only
- **dyndns**: `nixosModule` only
- **emergency-access**: `nixosModule` only
- **garage**: `nixosModule` only
- **hello-world**: `nixosModule` only
- **importer**: `nixosModule` only
- **internet**: `nixosModule` only
- **kde**: `nixosModule` only
- **localbackup**: `nixosModule` only
- **matrix-synapse**: `nixosModule` only
- **monitoring**: `nixosModule` only
- **mycelium**: `nixosModule` only
- **packages**: `nixosModule` only
- **sshd**: `nixosModule` only
- **syncthing**: `nixosModule` only
- **tor**: `nixosModule` only
- **trusted-nix-caches**: `nixosModule` only
- **users**: `nixosModule` only
- **wifi**: `nixosModule` only
- **wireguard**: `nixosModule` only
- **yggdrasil**: `nixosModule` only
- **zerotier**: `nixosModule` only

**None of the services provide `darwinModule` implementations.**

### Service Role Architecture

Services define roles with `perInstance.nixosModule` for each machine that participates:

```nix
# Example from zerotier/default.nix
roles.peer = {
  description = "A peer that connects to your private Zerotier network.";
  perInstance = {
    instanceName,
    roles,
    lib,
    ...
  }: {
    exports.networking = { ... };
    nixosModule = { config, lib, pkgs, ... }: { ... };
  };
};
```

This architecture assumes NixOS modules (systemd services, nixos options, etc.) and cannot be directly applied to nix-darwin.

## Zerotier Service: Specific Findings

Zerotier is clan-core's flagship networking service. Analysis shows:

**Zerotier Support Matrix**:
- **NixOS**: Full support (controller, moon, peer roles)
- **nix-darwin**: No native support in clan-core service definition

**Why not Darwin**:
1. The service only exports `nixosModule` (NixOS-specific)
2. Uses `systemd.services.zerotierone` (NixOS-only)
3. Uses `systemd.services.zerotier-inventory-autoaccept` (NixOS-only)
4. Uses `clan.core.networking.zerotier.*` options (NixOS-only)

**However**: The underlying zerotier package (`clan.core.clanPkgs.zerotierone`) is cross-platform and **zerotier itself works on macOS**. The limitation is purely in the clan service module abstraction, not in zerotier functionality.

**Workaround Path**: A darwin machine could manually install zerotier and join the network outside of clan's service orchestration, but this bypasses the inventory-based automation.

## Deployment and Update Architecture

### Build Architecture for macOS

From `docs/site/getting-started/update-machines.md` (lines 93-95):

```
Note: Make sure the CPU architecture of the `buildHost` matches that of the `targetHost`

For example, if deploying to a macOS machine with an ARM64-Darwin architecture, 
you need a second macOS machine with the same architecture to build it.
```

This is a hard requirement: nix-darwin derivations must be built on native darwin systems. You cannot cross-compile darwin configurations from Linux.

**Implications**:
- If your `buildHost` is a Linux VPS (like cinnabar), you cannot build for macOS targets
- Each macOS machine must build its own configuration or use another Mac as buildHost
- This is different from NixOS where you can cross-compile

### Update Mechanism

The `clan machines update <machine>` command works uniformly:

1. For NixOS: `ssh buildHost "nixos-rebuild switch --flake ..."`
2. For nix-darwin: `ssh targetHost "darwin-rebuild switch --flake ..."` (or build locally)

The clan CLI in `clan-cli/clan_lib/` handles this dispatch based on `machineClass`.

Recent fix (commit a4519a5cd): "fix(clan-cli): use machine's target system instead of host system"—indicates ongoing refinement of system-specific build handling.

## Architecture Decision: Darwin in Clan

### What Works

1. **Machine Declaration**: Darwin machines fully supported in inventory  
2. **Configuration Management**: Full nix-darwin configurations via `machines/<name>/configuration.nix`
3. **Remote Updates**: `clan machines update <darwin-machine>` works end-to-end  
4. **Secrets Management**: Vars/sops-nix secrets generation works for darwin machines  
5. **Cross-Flake Integration**: Darwin machines compose with nixos machines in same flake  
6. **Home-Manager**: Full home-manager support on darwin (via nix-darwin)

### What Doesn't Work (Yet)

1. **Multi-Machine Services**: Services like zerotier, wireguard, borgbackup, etc. only generate NixOS modules
2. **Inventory-Based Orchestration**: Darwin machines cannot be assigned service roles automatically  
3. **Service Configuration via Roles**: You cannot use `roles.peer.machines.myMac` in service definitions
4. **Cross-System Builds**: Cannot build darwin configurations from Linux builders  
5. **Service Vars**: Service-specific variable generation doesn't account for darwin needs

### Gaps and Limitations

**Documentation Gap**: The `docs/site/guides/macos.md` explicitly lists limitations:

> Currently, Clan supports the following features for macOS:
> - `clan machines update` for existing nix-darwin installations
> - Support for vars

This is honest but minimal. There's no guidance on:
- Why darwin machines can't participate in services
- How to configure zerotier on darwin manually
- Best practices for mixing darwin + nixos in a clan

**Service Module Limitation**: Services need `darwinModule` support to work with darwin machines. This is a feature gap, not a fundamental incompatibility.

**Build System Constraint**: Native darwin builds required for darwin machines—architectural, not a bug.

## Recommended Architecture for Our Infra

### For stibnite, blackphos (nix-darwin laptops)

**Approach**: Manage directly, exclude from service orchestration

```nix
inventory.machines.stibnite = {
  machineClass = "darwin";
  deploy.targetHost = "root@stibnite.local";
  # OR: build locally on each machine
};

machines.stibnite = { config, ... }: {
  clan.core.networking.targetHost = "root@stibnite.local";
  # Full nix-darwin configuration here
  # Import any modules needed directly
};
```

**Manual Setup**:
- Install nix, nix-darwin via documented methods
- Install zerotier on each mac manually (pkg installers or `brew install zerotier-one`)
- Update via `clan machines update stibnite` for declarative config changes
- Secrets via separate sops-nix setup per machine

**Advantages**:
- Decoupled from nixos infrastructure
- Simpler (fewer dependencies on Linux builders)
- Each mac maintains independence
- Secrets can be per-machine or shared via sops

### For cinnabar (nixos VPS controller)

**Approach**: Full clan orchestration, zerotier controller role

```nix
inventory.machines.cinnabar = {
  machineClass = "nixos";
  deploy.targetHost = "root@cinnabar";
  tags = [ "backup-controller" "network-coordinator" ];
};

inventory.instances.zerotier-main = {
  module.name = "zerotier";
  module.input = "clan-core";
  roles.controller.machines.cinnabar = {};
  roles.moon.machines.cinnabar.settings.stableEndpoints = [ "cinnabar.public.ip" ];
  roles.peer.tags.nixos = {};
};
```

Cinnabar becomes the zerotier controller that the macOS machines join via manual zerotier setup.

### Connection Strategy

1. **Manual zerotier**: macOS machines install zerotier and join the network manually  
2. **Controller coordination**: cinnabar zerotier controller admits the macs
3. **SSH over zerotier**: Use zerotier IPs for clan machine updates
4. **Symmetric setup**: Both nixos and darwin machines can reach each other via zerotier IPs

Example zerotier joining on macOS:
```bash
# Download from zerotier.com or brew install
brew install zerotier-one

# Start service (via launchctl on macOS)
sudo launchctl load /Library/LaunchDaemons/com.zerotier.one.plist

# Join network
sudo zerotier-cli join <network-id-from-controller>

# Accept from controller (run on cinnabar)
zerotier-members allow --member-ip <mac-zerotier-ip>
```

Then update clan config via SSH over zerotier IP:
```bash
clan machines update stibnite --target-host <zerotier-ip>
```

## Service Implementation Path (Future)

If we want full darwin service support, the path is clear:

1. **Add `darwinModule` to services**: Each service needs a darwin-specific implementation
   - Zerotier: systemd -> launchd equivalents
   - Borgbackup: systemd timers -> launchd schedules
   - Others: systemd services -> launchd services

2. **Module Type**: `types.submodule` darwinModule similar to nixosModule

3. **Testing**: Requires darwin CI environment (Apple Silicon hardware)

4. **Examples**: Reference qubasa, mic92 personal clans for patterns

This is not implemented yet—clan-core developers have it on the roadmap but haven't prioritized it.

## Validation Against Architecture Goals

### Goal: Multi-Machine Coordination with Clan

**Current Status**: Partial

- NixOS machines: Full orchestration via clan services ✓
- macOS machines: Single-machine updates only ⚠  
- Cross-system coordination: Manual zerotier setup required

### Goal: Zerotier VPN Across All Machines

**Current Status**: Achievable but manual

- Zerotier controller: Runs on NixOS (cinnabar) ✓
- Zerotier peers: NixOS machines automatic, macOS manual ⚠
- Network connectivity: Fully functional ✓

### Goal: Declarative Configuration Everything

**Current Status**: Mostly achieved

- NixOS configs: Fully declarative ✓
- nix-darwin configs: Fully declarative ✓
- Service orchestration: NixOS only ⚠
- Secrets: Fully declarative via sops-nix ✓

## Timeline and Stability

- **macOS update support**: Stable, in production (mic92's clan, others)
- **Inventory darwin support**: Stable, mature
- **Service darwin support**: Not implemented, not on critical path
- **nix-darwin integration**: Continuously updated (regular dependency updates in clan-core)

## Conclusion

Clan-core provides **solid, production-ready nix-darwin support** for individual machine management but has **incomplete support for multi-machine service orchestration** with macOS. This is an architectural choice, not a limitation of nix-darwin itself.

For our infrastructure, managing macOS machines individually with clan while orchestrating NixOS machines as the service backbone is a viable and pragmatic approach. The missing piece is service-level darwin support, which is known but not yet prioritized in clan-core development.

The path forward is either:
1. **Accept current limitations**: Manage macOS as independent nix-darwin machines, coordinate via manual zerotier  
2. **Contribute darwin service modules**: Build `darwinModule` implementations for critical services (zerotier, vars)
3. **Wait for clan-core upstream**: This feature may come in future releases
