# Adding Users to Clan Inventory

This guide explains how to add new users to the clan inventory users service, generate vars, and deploy configurations.

## Quick Start

1. Create inventory user instance in `modules/clan/inventory/services/users.nix`
2. Define user overlay with shell and home-manager configuration
3. Generate vars: `nix develop -c clan vars generate <machine>`
4. Deploy: `nix develop -c clan machines update <machine>`

## Step-by-Step Guide

### 1. Create Inventory User Instance

Edit `modules/clan/inventory/services/users.nix`:

```nix
{
  config,
  inputs,
  ...
}:
{
  # Existing user-cameron instance...

  # New user instance
  clan.inventory.instances.user-raquel = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Deploy to all machines (or specify machines)
    roles.default.tags."all" = { };

    # User settings
    roles.default.settings = {
      user = "raquel";
      groups = [
        "wheel"           # sudo access
        "networkmanager"  # network configuration
      ];
      share = true;       # Same password across all machines
      prompt = false;     # Auto-generate password with xkcdpass
    };

    # User overlay (shell preference, home-manager integration)
    roles.default.extraModules = [
      inputs.home-manager.nixosModules.home-manager
      (
        { config, pkgs, ... }:
        {
          # Shell preference
          users.users.raquel.shell = pkgs.zsh;
          programs.zsh.enable = true;

          # Home-manager configuration
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.raquel = {
              imports = [
                inputs.self.modules.homeManager."users/raquel"
              ];
              home.username = "raquel";
              home.homeDirectory = "/home/raquel";
            };
          };
        }
      )
    ];
  };
}
```

### 2. Customize Role Targeting

#### Deploy to All Machines

```nix
roles.default.tags."all" = { };
```

#### Deploy to Specific Machines

```nix
roles.default.machines."cinnabar" = { };
roles.default.machines."argentum" = { };
```

#### Deploy to Machine Tags

```nix
# First, tag machines in inventory
roles.default.tags."production" = { };

# Then tag machines in their inventory definitions
# clan.inventory.machines.cinnabar.tags = ["production"];
```

### 3. Customize User Settings

#### Groups

Common groups:
- `wheel`: sudo access
- `networkmanager`: network configuration
- `video`: video device access
- `input`: input device access
- `docker`: docker socket access

```nix
groups = [ "wheel" "networkmanager" "video" ];
```

#### Password Management

**Auto-generate password (recommended):**

```nix
share = true;    # Same password across machines
prompt = false;  # Auto-generate with xkcdpass
```

**Prompt for password during deployment:**

```nix
share = false;   # Different password per machine
prompt = true;   # Prompt during deployment
```

**Share password across specific machines:**

```nix
share = true;    # Same password across machines
prompt = true;   # Prompt once, reuse across machines
```

### 4. Create Portable Home Module (Optional)

If the user needs custom home-manager configuration, create a portable module:

`modules/home/users/raquel/default.nix`:

```nix
{ lib, ... }:
{
  flake.modules.homeManager."users/raquel" =
    { config, pkgs, lib, ... }:
    {
      home.stateVersion = "23.11";
      
      # Username defaults (overridable with mkDefault)
      home.username = lib.mkDefault "raquel";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin 
        then "/Users/${config.home.username}" 
        else "/home/${config.home.username}"
      );

      # Shell configuration
      programs.zsh.enable = true;
      programs.starship.enable = true;

      # Git configuration
      programs.git = {
        enable = true;
        settings = {
          user.name = "Raquel";
          user.email = "raquel@example.com";
        };
      };

      # Development packages
      home.packages = with pkgs; [
        git
        gh
      ];
    };
}
```

### 5. Generate Vars

Generate password vars for the machine(s):

```bash
# Enter development shell
nix develop

# Generate vars for specific machine
clan vars generate cinnabar

# Generate vars for all machines (if deploying to multiple)
clan vars generate argentum
clan vars generate rosegold
```

### 6. Verify Vars

List generated vars:

```bash
clan vars list cinnabar | grep user-password-raquel
```

Expected output:
```
user-password-raquel/user-password: ********
user-password-raquel/user-password-hash: ********
```

Vars are stored in:
```
vars/shared/user-password-raquel/
├── user-password/secret       # SOPS-encrypted password
└── user-password-hash/secret  # SOPS-encrypted hash
```

### 7. Build Configuration

Verify configuration builds:

```bash
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel
```

### 8. Deploy Configuration

Deploy to machine:

```bash
# Deploy to specific machine
clan machines update cinnabar

# Deploy to all machines
clan machines update --all
```

### 9. Verify Deployment

SSH into the machine:

```bash
# Test SSH login
ssh raquel@cinnabar

# Verify shell
ssh raquel@cinnabar "echo \$SHELL"
# Expected: /run/current-system/sw/bin/zsh

# Verify sudo access
ssh raquel@cinnabar "sudo -n true"

# Check home-manager service
ssh raquel@cinnabar "systemctl --user status home-manager-raquel.service"
```

## Examples for Epic 2-6

### argentum (nix-darwin laptop, christophersmith user)

```nix
clan.inventory.instances.user-christophersmith = {
  module = {
    name = "users";
    input = "clan-core";
  };

  roles.default.tags."all" = { };

  roles.default.settings = {
    user = "christophersmith";
    groups = [ "wheel" ];
    share = true;
    prompt = false;
  };

  roles.default.extraModules = [
    inputs.home-manager.darwinModules.home-manager
    ({ config, pkgs, ... }: {
      users.users.christophersmith.shell = pkgs.zsh;
      programs.zsh.enable = true;
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.christophersmith = {
          imports = [ inputs.self.modules.homeManager."users/christophersmith" ];
          home.username = "christophersmith";
          home.homeDirectory = "/Users/christophersmith";
        };
      };
    })
  ];
};
```

### rosegold (nix-darwin laptop, janettesmith user)

```nix
clan.inventory.instances.user-janettesmith = {
  module = {
    name = "users";
    input = "clan-core";
  };

  roles.default.tags."all" = { };

  roles.default.settings = {
    user = "janettesmith";
    groups = [ "wheel" ];
    share = true;
    prompt = false;
  };

  roles.default.extraModules = [
    inputs.home-manager.darwinModules.home-manager
    ({ config, pkgs, ... }: {
      users.users.janettesmith.shell = pkgs.zsh;
      programs.zsh.enable = true;
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.janettesmith = {
          imports = [ inputs.self.modules.homeManager."users/janettesmith" ];
          home.username = "janettesmith";
          home.homeDirectory = "/Users/janettesmith";
        };
      };
    })
  ];
};
```

### stibnite (nix-darwin laptop, crs58 primary workstation)

```nix
clan.inventory.instances.user-crs58-stibnite = {
  module = {
    name = "users";
    input = "clan-core";
  };

  # Deploy only to stibnite (primary workstation)
  roles.default.machines."stibnite" = { };

  roles.default.settings = {
    user = "crs58";
    groups = [ "wheel" ];
    share = true;    # Share with other crs58 instances
    prompt = false;
  };

  roles.default.extraModules = [
    inputs.home-manager.darwinModules.home-manager
    ({ config, pkgs, ... }: {
      users.users.crs58.shell = pkgs.zsh;
      programs.zsh.enable = true;
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.crs58 = {
          imports = [ inputs.self.modules.homeManager."users/crs58" ];
          home.username = "crs58";
          home.homeDirectory = "/Users/crs58";
        };
      };
    })
  ];
};
```

## Troubleshooting

### User already exists error

If you get "user already exists" during deployment, check for:

1. Direct NixOS user definitions in machine modules
2. Duplicate inventory instances
3. Multiple role assignments

Remove direct definitions and use inventory instances exclusively.

### Home-manager conflicts

If home-manager fails to activate:

1. Check that home-manager module is imported in extraModules
2. Verify portable home module exists and is exported to flake namespace
3. Check for conflicting home-manager configurations

### Vars not generating

If vars generation fails:

1. Ensure clan CLI is available: `nix develop`
2. Check machine exists in clan metadata
3. Verify inventory instance defines the user correctly
4. Check SOPS age keys are configured

### Password not working

If password login fails:

1. Verify vars were generated: `clan vars list <machine>`
2. Check vars deployed to runtime: `ls /run/secrets/vars/user-password-<user>/`
3. Retrieve password: `clan vars get <machine> user-password-<user>/user-password`
4. Try SSH with retrieved password

## Best Practices

1. **Use portable home modules:** Define home configurations in `modules/home/users/<username>/` and export to flake namespace
2. **Share passwords:** Set `share = true` for consistency across machines
3. **Auto-generate passwords:** Set `prompt = false` for automated deployment
4. **Tag machines appropriately:** Use role targeting for flexible deployment
5. **Test locally first:** Build configuration before deploying
6. **Document users:** Add comments explaining user purpose and access level
7. **Version control vars:** Commit encrypted vars to git for backup
8. **Regular backups:** Keep SOPS age keys backed up securely

## Security Considerations

1. **Vars are encrypted:** All password vars are SOPS-encrypted with age keys
2. **Runtime secrets:** Vars deployed to `/run/secrets/` (tmpfs, cleared on reboot)
3. **Immutable users:** users.mutableUsers = false ensures inventory has exclusive control
4. **Sudo access:** Only grant wheel group to trusted users
5. **SOPS keys:** Protect age keys (usually in `sops/users/<user>/key.txt`)

## References

- User management architecture: `docs/notes/architecture/user-management.md`
- Clan-core users service: [clan-core repository](https://git.clan.lol/clan/clan-core)
- Story 1.10A context: `infra/docs/notes/development/work-items/1-10A-migrate-user-management-inventory.context.xml`
