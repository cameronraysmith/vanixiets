# Phase 2 implementation guide: darwin migration (blackphos)

This guide provides step-by-step instructions for Phase 2: migrating blackphos (the first darwin host) from nixos-unified to the dendritic pattern with clan-core integration.
Phase 2 builds on the infrastructure established in Phase 1 (cinnabar VPS) and establishes darwin-specific patterns for subsequent host migrations.

## Critical Prerequisites

Phase 1 (cinnabar VPS deployment) **MUST be completed first** - see `02-phase-1-vps-deployment.md`.

The following infrastructure is already in place from Phase 1:
- ✅ Flake inputs added (clan-core, import-tree, terranix, disko, srvos)
- ✅ Dendritic modules/ directory structure created
- ✅ Clan secrets initialized (age keys, admin group)
- ✅ cinnabar VPS deployed with zerotier controller operational
- ✅ Base NixOS modules created (modules/base/nix.nix, modules/nixos/server.nix)

**Verify Phase 1 complete**:
```bash
# Check cinnabar VPS is operational
ssh root@<cinnabar-ip> zerotier-cli info
# Expected: 200 info <node-id> <version> ONLINE

# Get zerotier network ID for blackphos configuration
ssh root@<cinnabar-ip> "zerotier-cli listnetworks | awk 'NR==2 {print \$3}'"
# Save this network ID - you'll need it in Step 11
```

**Phase 2 Objective**: Connect blackphos to cinnabar's zerotier network as a peer and establish darwin + clan integration patterns.

## Prerequisites

- [ ] Read `00-integration-plan.md` for complete context
- [ ] Age key generated for yourself: `nix run nixpkgs#age -- keygen`
- [ ] Current nix-config working and tests passing
- [ ] Familiarity with flake-parts module system
- [ ] Understanding of dendritic pattern concepts

## Migration overview

Phase 2 focuses on darwin-specific configuration:
1. Create darwin-specific dendritic modules (base, shell, dev tools)
2. Create blackphos host configuration
3. Configure blackphos as zerotier peer (connects to cinnabar controller)
4. Generate clan vars for blackphos
5. Build and deploy blackphos with darwin-rebuild
6. Validate blackphos ↔ cinnabar connectivity

This creates a parallel environment where blackphos uses dendritic + clan while other darwin hosts remain on nixos-unified.

## Steps 1-3: Infrastructure Setup

**⏭️ SKIP THESE STEPS - COMPLETED IN PHASE 1**

Steps 1-3 (flake inputs, import-tree setup, module directory structure) were completed in Phase 1 (cinnabar VPS deployment).
If you completed Phase 1, proceed directly to Step 4.

<details>
<summary>Step 1-3 Details (for reference only - already done)</summary>

## Step 1: Add clan-core and import-tree flake inputs (DONE IN PHASE 1)

**File**: `flake.nix`

Add clan-core and import-tree inputs with appropriate follows:

```nix
{
  inputs = {
    # ... existing inputs ...

    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.sops-nix.follows = "sops-nix";
    clan-core.inputs.home-manager.follows = "home-manager";
    clan-core.inputs.nix-darwin.follows = "nix-darwin";

    import-tree.url = "github:vic/import-tree";
  };
}
```

**Validation**:
```bash
cd ~/projects/nix-workspace/nix-config
nix flake lock --update-input clan-core --update-input import-tree
nix flake show
```

Expected: clan-core and import-tree appear in inputs, flake evaluates successfully.

## Step 2: Update flake outputs to use import-tree

**File**: `flake.nix`

Modify outputs to use import-tree for auto-discovery:

```nix
{
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
    (inputs.import-tree ./modules);
  # import-tree recursively imports all .nix files in modules/
  # Each file is a flake-parts module contributing to flake.modules.*
}
```

**Note**: This replaces manual imports from `./modules/flake-parts/`.
The import-tree function will discover and import all .nix files automatically.

**Validation**:
```bash
nix flake check
```

Expected: Flake checks pass, existing configurations still evaluate.

## Step 3: Create dendritic module directory structure

**Commands**:
```bash
cd ~/projects/nix-workspace/nix-config

# Create dendritic module structure
mkdir -p modules/base
mkdir -p modules/darwin
mkdir -p modules/shell
mkdir -p modules/dev/git
mkdir -p modules/hosts/blackphos
mkdir -p modules/users
```

**Directory layout**:
```
modules/
├── base/           # Foundation modules (cross-platform)
├── darwin/         # Darwin-specific modules
├── shell/          # Shell tools (fish, starship, etc.)
├── dev/            # Development tools
│   └── git/
├── hosts/          # Machine-specific configurations
│   └── blackphos/
└── users/          # User configurations
```

</details>

---

## Step 4: Create base nix configuration module

**File**: `modules/base/nix.nix`

```nix
{
  flake.modules = {
    darwin.base-nix = {
      pkgs,
      ...
    }: {
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@admin"
        ];

        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
          "https://cameronraysmith.cachix.org"
        ];

        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "cameronraysmith.cachix.org-1:aC8ZcRCVcQql77Qn//Q1jrKkiDGir+pIUjhUunN6aio="
        ];
      };

      nix.gc = {
        automatic = true;
        options = "--delete-older-than 30d";
      };
    };
  };
}
```

**Validation**:
```bash
nix eval .#flake.modules.darwin.base-nix --json
```

Expected: Module evaluates and exports darwin configuration.

## Step 5: Create system state version module

**File**: `modules/base/system.nix`

```nix
{
  flake.modules.darwin.base-system = {
    # Darwin state version
    # Set to the darwin release version at initial installation
    system.stateVersion = 5;
  };
}
```

## Step 6: Convert shell modules to dendritic pattern

**File**: `modules/shell/fish.nix`

Example conversion from existing module:

```nix
{
  flake.modules = {
    # System-level fish configuration
    darwin.shell-fish = {
      programs.fish.enable = true;
    };

    # Home-manager fish configuration
    homeManager.shell-fish = {
      pkgs,
      ...
    }: {
      programs.fish = {
        enable = true;
        shellAliases = {
          ls = "eza";
          cat = "bat";
          grep = "rg";
        };
        shellInit = ''
          # Custom fish initialization
        '';
      };
    };
  };
}
```

**Pattern**: Each module defines both darwin and homeManager configurations in `flake.modules` namespace.

## Step 7: Convert development tool modules

**File**: `modules/dev/git/git.nix`

```nix
{ config, ... }:
{
  flake.modules.homeManager.dev-git = {
    pkgs,
    ...
  }: {
    programs.git = {
      enable = true;
      userName = config.flake.meta.users.crs58.name or "User Name";
      userEmail = config.flake.meta.users.crs58.email or "user@example.com";

      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
        # ... additional git configuration
      };
    };
  };
}
```

**Note**: Uses `config.flake.meta.users.crs58.*` for metadata sharing (defined in step 8).

## Step 8: Create user metadata module

**File**: `modules/users/crs58/default.nix`

```nix
{
  config,
  ...
}:
{
  # Define user metadata accessible across all modules
  flake.meta.users.crs58 = {
    name = "User Name";
    email = "user@example.com";
    username = "crs58";
    sshKeys = [
      "ssh-ed25519 AAAAC3... your-key-here"
    ];
  };

  # Darwin user configuration
  flake.modules.darwin.users-crs58 = {
    ...
  }: {
    users.users.crs58 = {
      description = config.flake.meta.users.crs58.name;
      home = "/Users/crs58";
      shell = "/run/current-system/sw/bin/fish";
    };
  };

  # Home-manager user configuration
  flake.modules.homeManager.users-crs58 = {
    ...
  }: {
    home = {
      username = config.flake.meta.users.crs58.username;
      homeDirectory = "/Users/crs58";
      stateVersion = "25.05";
    };
  };
}
```

## Step 9: Create blackphos host configuration

**File**: `modules/hosts/blackphos/default.nix`

This is the core host composition using dendritic pattern:

```nix
{
  config,
  inputs,
  ...
}:
{
  flake.modules.darwin."hosts/blackphos" = {
    pkgs,
    ...
  }: {
    imports =
      with config.flake.modules;
      [
        # Base modules
        darwin.base-nix
        darwin.base-system

        # Darwin-specific modules
        # (add existing darwin modules converted to dendritic pattern)

        # Home-manager integration
        inputs.home-manager.darwinModules.home-manager
      ];

    # Home-manager configuration
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;

      users.crs58 = {
        imports = with config.flake.modules.homeManager; [
          users-crs58
          shell-fish
          dev-git
          # ... additional home-manager modules
        ];
      };
    };

    # Host-specific configuration
    networking = {
      computerName = "blackphos";
      hostName = "blackphos";
    };

    # System packages
    environment.systemPackages = with pkgs; [
      vim
      git
      curl
    ];
  };
}
```

**Pattern**: Host modules import from `config.flake.modules.*` namespace, compose system and home-manager configurations.

## Step 10: Create flake-parts host-machines module

**File**: `modules/flake-parts/host-machines.nix`

This generates darwinConfigurations from dendritic host modules:

```nix
{
  inputs,
  lib,
  config,
  ...
}:
let
  prefix = "hosts/";
  collectHostsModules = modules: lib.filterAttrs (name: _: lib.hasPrefix prefix name) modules;
in
{
  flake.darwinConfigurations = lib.pipe (collectHostsModules config.flake.modules.darwin) [
    (lib.mapAttrs' (
      name: module:
      let
        hostName = lib.removePrefix prefix name;
      in
      {
        name = hostName;
        value = inputs.nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit inputs;
          };
          modules = [
            inputs.home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
            module
          ];
        };
      }
    ))
  ];
}
```

**Function**: Automatically discovers all `flake.modules.darwin."hosts/*"` modules and generates corresponding darwinConfigurations.

## Step 11: Update clan inventory for blackphos

**File**: `modules/flake-parts/clan.nix`

**Note**: This file was initially created in Phase 1 with cinnabar configuration.
This step adds blackphos to the existing inventory and ensures zerotier is configured correctly (cinnabar as controller, blackphos as peer).

```nix
{ inputs, ... }:
{
  imports = [ inputs.clan-core.flakeModules.default ];

  clan = {
    meta.name = "nix-config";
    specialArgs = {
      inherit inputs;
    };

    # Machine inventory (cinnabar added in Phase 1)
    inventory.machines = {
      blackphos = {
        tags = [
          "darwin"
          "workstation"
        ];
        machineClass = "darwin";
      };
      rosegold = {
        tags = [
          "darwin"
          "workstation"
        ];
        machineClass = "darwin";
      };
      argentum = {
        tags = [
          "darwin"
          "workstation"
        ];
        machineClass = "darwin";
      };
      stibnite = {
        tags = [
          "darwin"
          "workstation"
          "primary"
        ];
        machineClass = "darwin";
      };
    };

    # Service instances
    inventory.instances = {
      # Essential services
      emergency-access = {
        module = {
          name = "emergency-access";
          input = "clan-core";
        };
        roles.default.tags."workstation" = { };
      };

      users-crs58 = {
        module = {
          name = "users";
          input = "clan-core";
        };
        roles.default.tags."workstation" = { };
        roles.default.settings = {
          user = "crs58";
          share = true;
        };
      };

      zerotier-local = {
        module = {
          name = "zerotier";
          input = "clan-core";
        };
        # cinnabar is controller (configured in Phase 1)
        roles.controller.machines.cinnabar = { };
        # All darwin machines connect as peers to cinnabar
        roles.peer.tags."workstation" = { };
      };
    };

    # Secrets configuration
    secrets.sops.defaultGroups = [ "admins" ];
  };
}
```

**Note**: Inventory defines all darwin hosts. cinnabar was added in Phase 1, blackphos is being added now in Phase 2.

## Step 12: Initialize clan secrets structure

**⏭️ SKIP THIS STEP - COMPLETED IN PHASE 1**

Clan secrets (age keys, admin group) were initialized in Phase 1 Step 4.
Proceed directly to Step 13 (Generate vars for blackphos).

<details>
<summary>Step 12 Details (for reference only - already done)</summary>

**Commands**:
```bash
cd ~/projects/nix-workspace/nix-config

# Create Clan secrets directory structure
mkdir -p secrets/{groups,machines,secrets,users}

# Generate your age key if not already done
nix run nixpkgs#clan-cli -- secrets key generate

# Extract your public key (macOS)
YOUR_AGE_KEY=$(grep 'public key:' ~/Library/Application\ Support/sops/age/keys.txt | awk '{print $4}')
# Or Linux:
# YOUR_AGE_KEY=$(grep 'public key:' ~/.config/sops/age/keys.txt | awk '{print $4}')

echo "Your age public key: $YOUR_AGE_KEY"

# Create admin group
nix run nixpkgs#clan-cli -- secrets groups add admins

# Add yourself as admin
nix run nixpkgs#clan-cli -- secrets users add crs58 "$YOUR_AGE_KEY"
nix run nixpkgs#clan-cli -- secrets groups add-user admins crs58
```

**Validation**:
```bash
ls -la secrets/groups/admins/
ls -la secrets/users/crs58/
```

Expected: Age key files created in both directories.

</details>

---

## Step 13: Generate vars for blackphos

Generate clan vars for blackphos machine:

```bash
cd ~/projects/nix-workspace/nix-config

# Generate all vars for blackphos
nix run .#clan-cli -- vars generate blackphos
```

Expected prompts:
- Emergency access password
- Any other configured prompts from clan services

Expected results:
- `secrets/machines/blackphos/` populated with encrypted secrets
- `secrets/secrets/` contains shared secrets

**Validation**:
```bash
ls -la secrets/machines/blackphos/
```

Expected: Age keys, password hashes, zerotier files.

## Step 14: Build blackphos configuration

Test that blackphos configuration builds successfully:

```bash
# Build blackphos darwin system
nix build .#darwinConfigurations.blackphos.system

# Check for evaluation errors
nix flake check
```

Expected: Clean build, no errors.

If errors occur, validate:
- All module imports use correct namespace (`config.flake.modules.*`)
- No references to nixos-unified specialArgs
- All paths are correct

## Step 15: Deploy to blackphos

Deploy the dendritic configuration to blackphos:

```bash
# Deploy to blackphos
./result/sw/bin/darwin-rebuild switch --flake .#blackphos

# Or if on blackphos machine:
darwin-rebuild switch --flake ~/projects/nix-workspace/nix-config#blackphos
```

**Validation after deployment**:
```bash
# SSH into blackphos (or run locally if on blackphos)

# Check system configuration
darwin-rebuild --version

# Verify modules loaded
systemctl --user status

# Check clan vars deployed
ls -la /run/secrets/

# Test zerotier (controller role)
zerotier-cli status
zerotier-cli listnetworks
```

Expected:
- System running dendritic configuration
- Secrets deployed
- Zerotier controller operational

## Troubleshooting

### Issue: import-tree not discovering modules

**Solution**: Verify directory structure and file naming:
```bash
# Check all .nix files are discovered
fd -e nix . modules/

# Test import-tree manually
nix eval .#_module.args.inputs.import-tree --json
```

### Issue: Module namespace errors

**Error**: `attribute 'modules' missing`

**Solution**: Ensure all modules define `flake.modules.*`:
```nix
# Correct:
{ flake.modules.darwin.my-module = { ... }; }

# Incorrect (will not be discovered):
{ config, ... }: { ... }
```

### Issue: Host not found in darwinConfigurations

**Solution**: Verify host module uses correct naming:
```bash
# Module must be named "hosts/<hostname>"
# File: modules/hosts/blackphos/default.nix
# Defines: flake.modules.darwin."hosts/blackphos"

# Check it's discovered:
nix eval .#darwinConfigurations --apply builtins.attrNames
```

### Issue: Clan vars generation fails

**Solution**: Check generator definitions and age keys:
```bash
# See what vars are defined for blackphos
nix eval .#nixosConfigurations.blackphos.config.clan.core.vars.generators --json | jq 'keys'

# Verify age key is correct
cat ~/Library/Application\ Support/sops/age/keys.txt
```

### Issue: Metadata not accessible

**Error**: `config.flake.meta.users.crs58 is undefined`

**Solution**: Ensure user module is imported by flake-parts (via import-tree):
```bash
# Check metadata is defined
nix eval .#flake.meta.users.crs58 --json
```

### Issue: Existing configs broken after changes

**Solution**: import-tree imports ALL .nix files, including old ones:
```bash
# Move old configurations out of modules/
mv modules/old-stuff ../backup-modules/

# Or rename to .nix.bak to exclude from discovery
mv modules/old-file.nix modules/old-file.nix.bak
```

## Darwin-specific configuration patterns

### Overview: darwin vs NixOS differences

The dendritic pattern works identically on darwin and NixOS, but darwin hosts require darwin-specific configuration options. This section documents proven patterns from production darwin configurations.

### Pattern 1: Homebrew integration

Homebrew complements nix on darwin for GUI applications and tools not available in nixpkgs.

**File**: `modules/darwin/homebrew.nix`

```nix
{
  flake.modules.darwin.homebrew =
    { config, lib, ... }:
    {
      options.custom.homebrew = {
        enable = lib.mkEnableOption "Homebrew package management";
        additionalCasks = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional Homebrew casks to install";
        };
        additionalBrews = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional Homebrew formulae to install";
        };
        additionalMasApps = lib.mkOption {
          type = lib.types.attrsOf lib.types.int;
          default = { };
          description = "Additional Mac App Store applications (name = id)";
        };
        manageFonts = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install fonts via Homebrew";
        };
      };

      config = lib.mkIf config.custom.homebrew.enable {
        homebrew = {
          enable = true;

          # Core behavior
          onActivation = {
            autoUpdate = false; # Manual control preferred
            cleanup = "zap"; # Remove unlisted packages
            upgrade = false; # Explicit upgrades only
          };

          # Base GUI applications
          casks = [
            "1password"
            "alfred"
            "rectangle"
            "iterm2"
          ] ++ config.custom.homebrew.additionalCasks;

          # Command-line tools not in nixpkgs
          brews = [
            # Example: tools only available via Homebrew
          ] ++ config.custom.homebrew.additionalBrews;

          # Mac App Store applications
          masApps =
            {
              "1Password for Safari" = 1569813296;
              Keynote = 409183694;
              Numbers = 409203825;
              Pages = 409201541;
            }
            // config.custom.homebrew.additionalMasApps;

          # Fonts (optional)
          caskArgs.fontdir = lib.mkIf config.custom.homebrew.manageFonts "/Library/Fonts";
        };
      };
    };
}
```

**Usage in host config** (e.g., `modules/hosts/blackphos/default.nix`):

```nix
{
  custom.homebrew = {
    enable = true;
    additionalCasks = [
      "codelayer-nightly"
      "dbeaver-community"
      "gpg-suite"
    ];
    additionalBrews = [
      "incus" # Not available in nixpkgs
    ];
    additionalMasApps = {
      save-to-raindrop-io = 1549370672;
    };
    manageFonts = false; # Use nix for fonts
  };
}
```

### Pattern 2: macOS system preferences

Darwin-specific system settings using nix-darwin's `system.*` options.

**File**: `modules/darwin/system-preferences.nix`

```nix
{
  flake.modules.darwin."system-preferences" =
    { lib, ... }:
    {
      # Dock configuration
      system.defaults.dock = {
        autohide = true;
        orientation = "bottom";
        tilesize = 48;
        show-recents = false;
        mru-spaces = false; # Don't rearrange spaces
      };

      # Finder configuration
      system.defaults.finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = false;
        FXEnableExtensionChangeWarning = false;
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      # Global macOS settings
      system.defaults.NSGlobalDomain = {
        AppleInterfaceStyle = "Dark"; # Dark mode
        AppleKeyboardUIMode = 3; # Full keyboard navigation
        ApplePressAndHoldEnabled = false; # Repeat keys instead of accents
        InitialKeyRepeat = 15; # Faster key repeat
        KeyRepeat = 2; # Very fast key repeat
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
      };

      # Trackpad configuration
      system.defaults.trackpad = {
        Clicking = true; # Tap to click
        TrackpadThreeFingerDrag = false;
      };

      # Screencapture configuration
      system.defaults.screencapture = {
        location = "~/Pictures/Screenshots";
        type = "png";
      };

      # System UI
      system.defaults.CustomUserPreferences = {
        "com.apple.finder" = {
          ShowExternalHardDrivesOnDesktop = true;
          ShowHardDrivesOnDesktop = false;
          ShowMountedServersOnDesktop = true;
          ShowRemovableMediaOnDesktop = true;
        };
        "com.apple.desktopservices" = {
          DSDontWriteNetworkStores = true; # Don't create .DS_Store on network volumes
          DSDontWriteUSBStores = true;
        };
      };
    };
}
```

**Usage**: Automatically imported via dendritic pattern, affects all darwin hosts.

### Pattern 3: Touch ID for sudo

Darwin-specific PAM configuration for Touch ID authentication.

**File**: `modules/darwin/touchid-sudo.nix`

```nix
{
  flake.modules.darwin."touchid-sudo" =
    { config, lib, ... }:
    {
      options.custom.touchid.sudo = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Touch ID authentication for sudo";
      };

      config = lib.mkIf config.custom.touchid.sudo {
        # Enable Touch ID for sudo
        security.pam.services.sudo_local.touchIdAuth = true;

        # Alternative: system-wide sudo (less secure, use sudo_local instead)
        # security.pam.enableSudoTouchIdAuth = true;
      };
    };
}
```

**Usage in host config**:

```nix
{
  custom.touchid.sudo = true;
}
```

### Pattern 4: Desktop vs server profile

Distinguish between GUI workstations and headless servers.

**File**: `modules/base/profile.nix`

```nix
{
  flake.modules = {
    nixos.profile =
      { lib, ... }:
      {
        options.custom.profile = {
          isDesktop = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this is a desktop/workstation with GUI";
          };
          isServer = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this is a headless server";
          };
        };

        config = {
          # Validation: can't be both
          assertions = [
            {
              assertion = !(config.custom.profile.isDesktop && config.custom.profile.isServer);
              message = "Profile cannot be both desktop and server";
            }
          ];
        };
      };

    darwin.profile =
      { lib, ... }:
      {
        # Same options for darwin
        options.custom.profile = {
          isDesktop = lib.mkOption {
            type = lib.types.bool;
            default = true; # Most darwin hosts are desktops
            description = "Whether this is a desktop/workstation with GUI";
          };
          isServer = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this is a headless server";
          };
        };

        config = {
          assertions = [
            {
              assertion = !(config.custom.profile.isDesktop && config.custom.profile.isServer);
              message = "Profile cannot be both desktop and server";
            }
          ];
        };
      };
  };
}
```

**Usage**: Conditional configuration based on profile:

```nix
{
  # In host config
  custom.profile.isDesktop = true;

  # In other modules
  config = lib.mkIf config.custom.profile.isDesktop {
    # GUI-specific configuration
    homebrew.casks = [ "iterm2" "alfred" ];
  };
}
```

### Pattern 5: nix-rosetta-builder for multi-arch builds

Enable Linux builds on Apple Silicon darwin hosts.

**File**: `modules/darwin/rosetta-builder.nix`

```nix
{ inputs, ... }:
{
  flake.modules.darwin.rosetta-builder =
    { config, lib, ... }:
    {
      imports = [ inputs.nix-rosetta-builder.darwinModules.default ];

      options.custom.rosetta-builder = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable nix-rosetta-builder for Linux builds";
        };
        cores = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Number of CPU cores for VM";
        };
        memory = lib.mkOption {
          type = lib.types.str;
          default = "8GiB";
          description = "Memory allocation for VM";
        };
        diskSize = lib.mkOption {
          type = lib.types.str;
          default = "100GiB";
          description = "Disk size for VM";
        };
      };

      config = lib.mkIf config.custom.rosetta-builder.enable {
        # Disable standard linux-builder (nix-rosetta-builder replaces it)
        nix.linux-builder.enable = false;

        # Enable nix-rosetta-builder
        nix-rosetta-builder = {
          enable = true;
          onDemand = true; # VM powers off when idle
          permitNonRootSshAccess = true; # Safe for localhost-only VM
          cores = config.custom.rosetta-builder.cores;
          memory = config.custom.rosetta-builder.memory;
          diskSize = config.custom.rosetta-builder.diskSize;
        };
      };
    };
}
```

**Usage in host config**:

```nix
{
  custom.rosetta-builder = {
    enable = true;
    cores = 12;
    memory = "48GiB";
    diskSize = "500GiB";
  };
}
```

**Notes**:
- nix-rosetta-builder uses Rosetta 2 for fast x86_64-linux emulation
- Significantly faster than QEMU-based linux-builder
- Requires flake input: `inputs.nix-rosetta-builder.darwinModules.default`
- Bootstrap requires initial build with linux-builder, then migrate

### Pattern 6: GUI application configuration

Configure GUI applications declaratively where possible.

**File**: `modules/darwin/gui-apps.nix`

```nix
{
  flake.modules.darwin.gui-apps =
    { config, pkgs, lib, ... }:
    {
      options.custom.gui = {
        enableVscode = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable VS Code configuration";
        };
        enableAlacritty = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Alacritty terminal";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf config.custom.gui.enableVscode {
          # VS Code via nix (alternative to Homebrew cask)
          environment.systemPackages = [ pkgs.vscode ];

          # Note: VS Code settings typically managed via home-manager
          # See home-manager's programs.vscode module
        })

        (lib.mkIf config.custom.gui.enableAlacritty {
          environment.systemPackages = [ pkgs.alacritty ];

          # Alacritty configuration via home-manager
          # programs.alacritty.enable = true;
          # programs.alacritty.settings = { ... };
        })
      ];
    };
}
```

**Better approach**: Use home-manager for per-user GUI application configuration:

**File**: `modules/home/gui-apps.nix`

```nix
{
  flake.modules.homeManager.gui-apps =
    { config, pkgs, lib, ... }:
    {
      # Only enable on darwin desktops
      config = lib.mkIf (pkgs.stdenv.isDarwin && config.custom.profile.isDesktop or false) {
        # VS Code
        programs.vscode = {
          enable = true;
          extensions = with pkgs.vscode-extensions; [
            jnoortheen.nix-ide
            github.copilot
            # Add more extensions
          ];
          userSettings = {
            "editor.fontSize" = 14;
            "editor.fontFamily" = "'JetBrainsMono Nerd Font', monospace";
            "workbench.colorTheme" = "Catppuccin Mocha";
          };
        };

        # Browser configuration (where supported)
        # programs.firefox.enable = true;
        # programs.chromium.enable = true;
      };
    };
}
```

### Pattern 7: Darwin-specific performance considerations

Darwin evaluations may be slower than NixOS due to macOS filesystem characteristics.

**Optimization strategies**:

1. **Use APFS snapshots for rollback** (automatic with nix-darwin)
2. **Minimize derivation count** (consolidate modules where reasonable)
3. **Cache darwin builds** (use cachix to avoid repeated builds)
4. **Profile slow evaluations**:

```bash
# Time a dry-run activation
time darwin-rebuild build --flake .#blackphos --dry-run

# If slow (>5 minutes), investigate:
nix eval .#darwinConfigurations.blackphos.config --show-trace
```

5. **Use import-tree efficiently** (avoid deeply nested module trees)

### Pattern 8: Home-manager integration on darwin

Home-manager configuration works identically on darwin and NixOS, but activation differs.

**System-level integration** (recommended for darwin):

```nix
# In darwinConfigurations generator (modules/flake-parts/darwin-machines.nix)
{
  modules = [
    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${username} = {
        imports = [
          # User-specific home modules
        ];
        home.stateVersion = "25.05";
      };
    }
    # ... other modules
  ];
}
```

**Activation**:
- NixOS: `nixos-rebuild switch` activates both system and home-manager
- Darwin: `darwin-rebuild switch` activates both system and home-manager
- Standalone: `home-manager switch` for home-manager only

### Pattern 9: Zerotier on darwin

Zerotier peer configuration for darwin hosts connecting to VPS controller.

**File**: `modules/darwin/zerotier-peer.nix`

```nix
{
  flake.modules.darwin.zerotier-peer =
    { config, lib, ... }:
    {
      # Note: Zerotier configuration typically comes from clan inventory
      # This module adds darwin-specific zerotier support

      options.custom.zerotier = {
        enableDarwinPeer = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Zerotier peer on darwin";
        };
      };

      config = lib.mkIf config.custom.zerotier.enableDarwinPeer {
        # Darwin uses launchd instead of systemd
        # Zerotier configuration comes from clan service instance

        # Additional darwin-specific configuration if needed
        # (Most configuration handled by clan zerotier service)
      };
    };
}
```

**Note**: Clan's zerotier service handles most configuration. Darwin-specific adjustments are minimal.

### Darwin migration checklist

When migrating a darwin host, verify:

- [ ] Homebrew casks install successfully
- [ ] System preferences apply (check Dock, Finder, etc.)
- [ ] Touch ID for sudo works (if enabled)
- [ ] GUI applications launch correctly
- [ ] Home-manager activates without errors
- [ ] Performance is acceptable (<5 min for dry-run builds)
- [ ] Zerotier peer connects to controller (if configured)
- [ ] nix-rosetta-builder VM starts on-demand (if enabled)

### Common darwin issues

**Issue**: Homebrew casks fail to install
**Solution**: Run `brew cleanup` and retry, or install manually then let nix manage

**Issue**: System preferences not applying
**Solution**: Logout/login or reboot required for some preferences

**Issue**: Touch ID stops working after macOS update
**Solution**: Re-run `darwin-rebuild switch` to refresh PAM configuration

**Issue**: GUI apps in unexpected state
**Solution**: Home-manager manages dotfiles, system manages app installation - check both

**Issue**: Slow evaluation times
**Solution**: Profile with `--show-trace`, consider caching, reduce module count

## CI/CD validation for Phase 2 (darwin)

### Update nix-config justfile for blackphos

Add blackphos-specific recipes to match existing darwin patterns:

**File**: `~/projects/nix-workspace/nix-config/justfile`

Add to the `nix-darwin` group:

```just
# Build blackphos darwin configuration
[group('nix-darwin')]
darwin-build-blackphos:
  just build "darwinConfigurations.blackphos.system"

# Test blackphos darwin configuration
[group('nix-darwin')]
darwin-test-blackphos:
  darwin-rebuild check --flake .#blackphos

# Deploy to blackphos
[group('nix-darwin')]
deploy-blackphos:
  darwin-rebuild switch --flake .#blackphos
```

Add to the `clan` group:

```just
# Generate vars for blackphos
[group('clan')]
vars-generate-blackphos:
  nix run nixpkgs#clan-cli -- vars generate blackphos

# Show blackphos in clan inventory
[group('clan')]
show-blackphos-inventory:
  nix eval .#clan.inventory.machines.blackphos --json | nix run nixpkgs#jq
```

### CI workflow for darwin hosts

Update `.github/workflows/ci.yaml` to validate darwin configurations.

**Challenge**: Darwin builds require macOS runners (expensive) or cross-compilation.

**Options**:

**Option A: Use GitHub-hosted macOS runners** (recommended for critical darwin hosts):

```yaml
# In the matrix section:
- system: aarch64-darwin
  runner: macos-14  # Apple Silicon runner
  category: darwin
  config: blackphos

- system: aarch64-darwin
  runner: macos-14
  category: darwin
  config: stibnite
```

**Option B: Use nix-rosetta-builder for cross-compilation** (faster, but requires setup):

Build darwin configurations on Linux using rosetta-builder:

```bash
# On linux CI runner (with rosetta-builder configured)
nix build .#darwinConfigurations.blackphos.system --max-jobs 0 --builders @/etc/nix/machines
```

**Option C: Validate evaluation only** (cheapest, catches most errors):

```yaml
jobs:
  validate-darwin-configs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24

      # Validate darwin configurations evaluate (don't build)
      - name: Validate darwin configs
        run: |
          nix eval .#darwinConfigurations.blackphos.config.system.build.toplevel.drvPath
          nix eval .#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath
```

**Recommendation**: Start with Option C (evaluation-only), upgrade to Option A for critical hosts once confident.

### Local validation before deployment

Comprehensive local testing before activating on blackphos:

```bash
cd ~/projects/nix-workspace/nix-config

# Enter devshell
nix develop

# 1. Validate flake evaluation
just check

# 2. Build blackphos configuration locally
just darwin-build-blackphos

# 3. Validate clan inventory
just show-blackphos-inventory

# 4. Test home-manager integration (if using)
nix build .#darwinConfigurations.blackphos.config.home-manager.users.crs58.activationPackage

# 5. Verify no regressions on other darwin hosts
just darwin-build stibnite  # Primary workstation should still build

# 6. Dry-run activation (shows what would change)
darwin-rebuild build --flake .#blackphos --dry-run
```

### CI validation checklist

After integrating blackphos into CI:

- [ ] Blackphos darwin configuration evaluates in CI
- [ ] Justfile recipes for blackphos work locally
- [ ] `just check` passes with blackphos included
- [ ] `just darwin-build-blackphos` succeeds
- [ ] Clan inventory includes blackphos as darwin machine
- [ ] Home-manager configuration validates (if used)
- [ ] Other darwin hosts still build (no regressions)
- [ ] CI completes without errors after blackphos integration

### Darwin CI optimization strategies

**1. Conditional darwin builds**

Only build darwin configs when darwin files change:

```yaml
# In .github/workflows/ci.yaml
jobs:
  darwin-build:
    if: |
      contains(github.event.head_commit.modified, 'modules/darwin/') ||
      contains(github.event.head_commit.modified, 'configurations/darwin/')
    runs-on: macos-14
    # ... build steps
```

**2. Cache darwin builds**

Push darwin builds to cachix to avoid repeated builds:

```bash
# Locally (one-time):
just cache-darwin-system  # From nix-config justfile

# CI will pull from cachix instead of rebuilding
```

**3. Parallel validation**

Run darwin evaluation and Linux builds in parallel:

```yaml
strategy:
  matrix:
    include:
      - name: darwin-eval
        runner: ubuntu-latest
        job: eval-only
      - name: linux-build
        runner: ubuntu-latest
        job: build-all
      - name: darwin-build
        runner: macos-14
        job: build-darwin
```

### Benefits of darwin CI validation

1. **Catch errors early**: Darwin config errors detected before deployment to workstation
2. **Safe migration**: Validate configurations without disrupting daily work
3. **Reproducibility**: Same validation runs locally and in CI
4. **Team visibility**: CI status shows configuration health
5. **Confidence**: Green CI = safe to deploy to primary workstation

### Troubleshooting darwin CI

**Issue**: Darwin builds time out in CI (>1 hour)
**Solution**: Use cachix pre-caching (`just cache-darwin-system`), enable evaluation-only validation

**Issue**: macOS runner quota exhausted
**Solution**: Switch to evaluation-only validation, use conditional builds (only on darwin file changes)

**Issue**: Darwin config builds locally but fails in CI
**Solution**: Check nixpkgs version consistency, verify inputs.follows, ensure no local-only paths

**Issue**: Home-manager fails in CI
**Solution**: Verify home-manager input follows nixpkgs, check for darwin-specific home-manager options

## Phase 1 validation checklist

After completing all steps:

- [ ] Flake evaluates: `nix flake check`
- [ ] blackphos configuration builds: `nix build .#darwinConfigurations.blackphos.system`
- [ ] Clan inventory accessible: `nix eval .#clan.inventory --json`
- [ ] Vars generated: `secrets/machines/blackphos/` populated
- [ ] Deployment successful on blackphos
- [ ] All functionality preserved (compare with pre-migration state)
- [ ] Zerotier network operational
- [ ] Secrets deployed: `ls /run/secrets/` (on blackphos)
- [ ] Other hosts unchanged: `nix build .#darwinConfigurations.stibnite.system`

## Next steps: Phase 2 (rosegold migration)

After blackphos is stable for 1-2 weeks, migrate rosegold using established patterns:

### Rosegold migration overview

**File**: `modules/hosts/rosegold/default.nix`

```nix
{
  config,
  inputs,
  ...
}:
{
  flake.modules.darwin."hosts/rosegold" = {
    pkgs,
    ...
  }: {
    imports = with config.flake.modules; [
      # Reuse same modules as blackphos
      darwin.base-nix
      darwin.base-system
      # ... other darwin modules
    ];

    home-manager.users.crs58 = {
      imports = with config.flake.modules.homeManager; [
        users-crs58
        shell-fish
        dev-git
        # ... same home-manager modules
      ];
    };

    # Host-specific configuration
    networking = {
      computerName = "rosegold";
      hostName = "rosegold";
    };
  };
}
```

**Steps**:
1. Create `modules/hosts/rosegold/default.nix` (copy from blackphos, change hostName)
2. Generate vars: `nix run .#clan-cli -- vars generate rosegold`
3. Build: `nix build .#darwinConfigurations.rosegold.system`
4. Deploy on rosegold: `darwin-rebuild switch --flake .#rosegold`
5. Validate zerotier peer connection to blackphos controller

**Success criteria**:
- [ ] rosegold operational
- [ ] blackphos ↔ rosegold zerotier communication
- [ ] Patterns validated for reuse

## Next steps: Phase 3 (argentum migration)

After rosegold is stable for 1-2 weeks, migrate argentum:

**Steps**: Identical to rosegold migration, replace hostName with "argentum"

**Success criteria**:
- [ ] argentum operational
- [ ] 3-machine zerotier network functional
- [ ] Ready for primary workstation migration

## Next steps: Phase 4 (stibnite migration)

**Critical**: Only migrate stibnite after all other hosts proven stable.

**Recommended timeline**: 4-6 weeks after blackphos migration, 2-4 weeks after argentum stable.

**Additional precautions**:
- Full backup of current stibnite configuration
- Low-stakes timing (not before important deadline)
- Fallback plan documented and tested
- Consider keeping stibnite on nixos-unified if no compelling benefits

See `02-migration-assessment.md` for detailed stibnite migration considerations.

## Phase 5: Cleanup

After all hosts migrated successfully:

**Tasks**:
- Remove `configurations/` directory (if all hosts migrated)
- Remove nixos-unified flake input and module imports
- Remove old secrets structure (after migrating all to clan vars)
- Update main repository documentation

**Commands**:
```bash
# Remove old configurations
rm -rf configurations/

# Remove old secrets (ONLY after all migrated)
rm -rf secrets/hosts/

# Update flake.nix to remove nixos-unified input
vim flake.nix

# Commit cleanup
git add -A
git commit -m "chore: remove nixos-unified after complete migration to dendritic + clan"
```

## Additional resources

### Dendritic pattern references
- Pattern documentation: `~/projects/nix-workspace/dendritic-flake-parts/README.md`
- Production examples:
  - `~/projects/nix-workspace/drupol-dendritic-infra/`
  - `~/projects/nix-workspace/mic92-clan-dotfiles/`

### Clan documentation
- Getting started: `~/projects/nix-workspace/clan-core/docs/site/getting-started/`
- Vars system: `~/projects/nix-workspace/clan-core/docs/site/guides/vars/`
- Inventory: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/`
- Services: `~/projects/nix-workspace/clan-core/clanServices/`

### Example repositories
- clan-infra: `~/projects/nix-workspace/clan-infra` (production dendritic + clan)
- clan-core: `~/projects/nix-workspace/clan-core` (modules and CLI)
- jfly-clan-snow: `~/projects/nix-workspace/jfly-clan-snow/` (darwin + clan example)

## Summary

Phase 1 establishes the dendritic + clan foundation by migrating blackphos.
This creates reusable patterns for migrating rosegold, argentum, and eventually stibnite.
The progressive approach allows validation at each step while maintaining system stability.

**Key achievements**:
- Dendritic module organization with flake.modules.* namespace
- import-tree auto-discovery
- Clan inventory for multi-machine coordination
- Clan vars for declarative secret management
- Zerotier network with blackphos as controller
- Proven patterns for remaining hosts
