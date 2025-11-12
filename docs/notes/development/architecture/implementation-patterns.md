# Implementation Patterns

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
