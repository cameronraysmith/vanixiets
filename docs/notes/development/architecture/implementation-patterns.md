# Implementation Patterns

**Last Updated**: 2025-11-21
**Status**: Updated with Epic 1 validation evidence (Stories 1.1-1.7, dendritic pattern proven)

## Dendritic Pattern Implementation (Epic 1 Validated)

**Status**: ✅ VALIDATED (Epic 1 Stories 1.1-1.7, 1.10BA-1.10E - 83 modules, 18 tests passing, zero regressions)

### Core Principle: Import-Tree Auto-Discovery + Namespace Merging

**Single-line flake.nix pattern**:
```nix
# flake.nix (test-clan: lines 4-6, entire pattern in 3 lines)
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
```

**What this does**:
1. `import-tree ./modules` recursively discovers ALL `.nix` files in modules/
2. Each file is evaluated as a flake-parts module
3. Modules declaring same namespace auto-merge via eval-modules
4. NO manual imports in flake.nix (zero boilerplate)

**Epic 1 Validation**: test-clan discovered 83 modules automatically, zero import statements needed.

### Module Size Heuristic: >7 Lines

**Pattern**: If logical unit exceeds ~7 lines, extract to separate module.

**Example** (Story 1.7 darwin/system-defaults refactoring):
```
Before (monolithic):
modules/darwin/system-defaults.nix  # 143 lines, all settings in one file

After (dendritic):
modules/darwin/system-defaults/
├── dock.nix              # 20 lines
├── finder.nix            # 15 lines
├── input-devices.nix     # 12 lines
├── loginwindow.nix       # 8 lines
├── nsglobaldomain.nix    # 18 lines
├── window-manager.nix    # 10 lines
├── screencapture.nix     # 8 lines
├── custom-user-prefs.nix # 15 lines
└── misc-defaults.nix     # 12 lines

All 9 files auto-merge into: flake.modules.darwin.base
```

**Validation**: Story 1.7 refactoring maintained zero regressions, 18 tests passing.

### Namespace Merging Strategies

**Deep Attribute Merging** (nested attrsets):
```nix
# modules/darwin/system-defaults/dock.nix
{ ... }: {
  flake.modules.darwin.base = { ... }: {
    system.defaults.dock.autohide = true;
  };
}

# modules/darwin/system-defaults/finder.nix
{ ... }: {
  flake.modules.darwin.base = { ... }: {
    system.defaults.finder.ShowPathbar = true;
  };
}

# Result: Both merge into single base module
# flake.modules.darwin.base.system.defaults = {
#   dock.autohide = true;
#   finder.ShowPathbar = true;
# }
```

**List Concatenation** (overlays, imports):
```nix
# modules/nixpkgs/overlays/channels.nix
{ ... }: {
  flake.nixpkgsOverlays = [
    (final: prev: { stable = ...; unstable = ...; })
  ];
}

# modules/nixpkgs/overlays/hotfixes.nix
{ ... }: {
  flake.nixpkgsOverlays = [
    (final: prev: { micromamba = final.stable.micromamba; })
  ];
}

# Result: Lists concatenated in discovery order
# flake.nixpkgsOverlays = [ overlay1, overlay2 ]
# Composed via: lib.composeManyExtensions config.flake.nixpkgsOverlays
```

**Validation**: Five-layer overlay architecture (Stories 1.10D-1.10DB), all layers auto-discovered and composed.

### DRY Configuration Pattern (lib/ shared data)

**Pattern**: Extract pure data to `lib/*.nix`, import where needed.

**Example** (binary caches):
```nix
# lib/caches.nix - Single source of truth
{
  substituters = [
    "https://cache.nixos.org"
    "https://cache.clan.lol"
    "https://nix-community.cachix.org"
  ];
  publicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.clan.lol-1:3KztgSAB5R1M+Dz7vzkBGzXdodizbgLXGXKXlcQLA28="
  ];
}

# flake.nix - Literal values (nix flake check requirement)
nixConfig = {
  extra-substituters = [ "https://cache.nixos.org" /* ... */ ];
  extra-trusted-public-keys = [ "cache.nixos.org-1:..." /* ... */ ];
}

# modules/system/caches.nix - Import shared data
let cacheConfig = import ../../lib/caches.nix; in {
  flake.modules.nixos.base.nix.settings.substituters = cacheConfig.substituters;
  flake.modules.darwin.base.nix.settings.substituters = cacheConfig.substituters;
}
```

**Benefit**: Update caches once in `lib/caches.nix`, all three locations sync.

**Validation**: test-clan uses this pattern for caches, proven reliable.

### Per-Machine Module Extraction

**Pattern**: Extract machine-specific configs to subdirectory modules that auto-merge.

**Example** (disko configurations):
```
modules/machines/nixos/cinnabar/
├── default.nix  # Main machine config
└── disko.nix    # Disk layout (merges into machines/nixos/cinnabar namespace)

Both files export: flake.modules.nixos."machines/nixos/cinnabar"
Auto-merge via eval-modules.
```

**Validation**: test-clan cinnabar + electrum machines, disko configs extracted (Story 1.7).

### References

- Test-clan dendritic pattern guide: `~/projects/nix-workspace/test-clan/docs/architecture/dendritic-pattern.md` (475 lines)
- Test-clan flake.nix: Lines 4-6 (entire pattern in 3 lines)
- Epic 1 Retrospective: Lines 242-265 (dendritic validation)
- Story 1.7: Dendritic refactoring with zero regressions

## Naming Conventions

**Module Files**:
- **Kebab-case**: `nix-settings.nix`, `admins.nix`, `initrd-networking.nix`
- **Feature-based**: File name = feature name (dendritic principle)
- **Platform prefixes** (when needed): `darwin-base.nix`, `nixos-server.nix`

**Module Namespace**:
- **Platform separation**: `flake.modules.{nixos,darwin,homeManager}.*`
- **Dot notation**: `flake.modules.nixos.base`, `flake.modules.darwin.users`
- **Machine prefix**: `flake.modules.nixos."machines/nixos/cinnabar"`

**Clan Inventory**:
- **Machine names**: Lowercase, single word (cinnabar, blackphos, rosegold, argentum, stibnite)
- **Service instances**: Kebab-case with purpose (zerotier-local, sshd-clan, emergency-access, users-crs58)
- **Tags**: Lowercase, categorical (nixos, darwin, cloud, workstation, primary)

**Vars Generators**:
- **Per-user naming**: `ssh-key-{username}`, `user-password-{username}`
- **Per-service naming**: `openssh`, `zerotier`, `tor-identity`
- **Shared naming**: `openssh-ca` (with `share = true`)

## Code Organization

**Module Structure** (dendritic pattern):
```nix
# modules/system/nix-settings.nix
{
  flake.modules.nixos.base = { config, pkgs, lib, ... }: {
    # Module content auto-merges to base
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "@wheel" ];
    };
  };
}
```

**Machine Configuration**:
```nix
# modules/machines/nixos/cinnabar/default.nix
{ config, ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = { pkgs, lib, ... }: {
    imports = [
      config.flake.modules.nixos.base  # Auto-merged system-wide config
      ./disko.nix                       # Machine-specific disk layout
      ./hardware-configuration.nix      # Generated hardware config
    ];

    # Machine-specific configuration
    networking.hostName = "cinnabar";
    networking.hostId = "8425e349";  # Required for ZFS
    system.stateVersion = "24.11";

    # Clan integration
    nixpkgs.hostPlatform = "x86_64-linux";
  };
}
```

**Home-Manager Configuration**:
```nix
# modules/home/users/crs58/default.nix
{ config, ... }:
{
  flake.modules.homeManager.users-crs58 = { config, pkgs, lib, ... }: {
    # User-specific home configuration
    programs.git = {
      userName = "crs58";
      userEmail = "crs58@example.com";
    };

    # Development tools for admin user
    home.packages = with pkgs; [
      ripgrep
      fd
      jq
      kubectl
    ];
  };
}
```

**Clan Inventory Structure**:
```nix
# modules/clan/inventory/machines.nix
{
  clan.inventory = {
    machines = {
      cinnabar = {
        tags = [ "nixos" "cloud" "vps" "controller" ];
        machineClass = "nixos";
      };
      blackphos = {
        tags = [ "darwin" "workstation" "multi-user" ];
        machineClass = "darwin";
      };
      # ... other machines
    };

    instances = {
      zerotier-local = {
        module = { name = "zerotier"; input = "clan-core"; };
        roles.controller.machines.cinnabar = {};
        roles.peer.tags."all" = {};  # All machines join network
      };
      sshd-clan = {
        module = { name = "sshd"; input = "clan-core"; };
        roles.server.tags."all" = {};
        roles.client.tags."all" = {};
      };
      emergency-access = {
        module = { name = "emergency-access"; input = "clan-core"; };
        roles.default.tags."workstation" = {};  # Workstations only
      };
    };
  };
}
```

## Error Handling

**Flake Evaluation Errors**:
- **Strategy**: Validate with `nix flake check` before deployment
- **Test coverage**: 17 test cases catch structural errors early
- **Error pattern**: Explicit error messages via `assert` or `lib.mkIf` guards

**Example**:
```nix
# modules/machines/nixos/cinnabar/disko.nix
{ lib, ... }:
{
  assertions = [
    {
      assertion = config.networking.hostId != null;
      message = "ZFS requires networking.hostId to be set";
    }
  ];
}
```

**Deployment Errors**:
- **Clan vars generation**: Pre-generate vars before deployment (`clan vars generate <machine>`)
- **Terraform failures**: Use `--dry-run` before `apply`, validate with `terraform plan`
- **SSH access**: Ensure SSH keys in clan vars before remote deployment

**Rollback Strategy**:
```bash
# Per-machine rollback (if deployment fails)
darwin-rebuild switch --flake .#blackphos --rollback

# Terraform rollback
nix run .#terraform.terraform -- destroy  # VPS is disposable, redeploy from config

# Git rollback
git revert <commit>  # Revert to previous working configuration
```

**Error Logging**:
- **System logs**: `journalctl -u clan-vars.service` (vars deployment)
- **Build logs**: `nix log /nix/store/<drv>` (build failures)
- **Terraform logs**: `TF_LOG=DEBUG nix run .#terraform.terraform -- apply` (infrastructure debugging)

## Logging Strategy

**Clan Vars Deployment**:
```nix
# Automatic logging via systemd (NixOS) or launchd (darwin)
systemd.services.clan-vars = {
  serviceConfig.StandardOutput = "journal";
  serviceConfig.StandardError = "journal";
};

# View logs
journalctl -u clan-vars.service --since today
```

**Terraform Operations**:
```bash
# Enable debug logging
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform/debug.log
nix run .#terraform.terraform -- apply
```

**Nix Build Logs**:
```bash
# Verbose build output
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel --print-build-logs

# Store path logs
nix log /nix/store/<drv>
```

**Test Execution Logs**:
```bash
# nix-unit with verbose output
nix-unit --flake ".#checks.x86_64-linux.nix-unit-tests" --verbose

# Integration test logs
nix build .#checks.x86_64-linux.test-vm-boot-hetzner-ccx23 --print-build-logs
```
