# Phase 1 implementation guide: migrating to dendritic + clan (blackphos)

This guide provides step-by-step instructions for implementing Phase 1 of the dendritic flake-parts + clan-core migration.
Phase 1 migrates blackphos (the first darwin host) from nixos-unified to the dendritic pattern with clan-core integration, establishing patterns for subsequent host migrations.

## Prerequisites

- [ ] Read `00-integration-plan.md` for complete context
- [ ] Age key generated for yourself: `nix run nixpkgs#age -- keygen`
- [ ] Current nix-config working and tests passing
- [ ] Familiarity with flake-parts module system
- [ ] Understanding of dendritic pattern concepts

## Migration overview

Phase 1 establishes the dendritic + clan foundation by:
1. Adding clan-core and import-tree inputs
2. Creating dendritic module structure alongside existing configurations
3. Converting key modules to flake.modules.* namespace
4. Migrating blackphos to dendritic pattern
5. Initializing clan inventory and vars
6. Validating blackphos deployment

This creates a parallel environment where blackphos uses dendritic + clan while other hosts remain on nixos-unified.

## Step 1: Add clan-core and import-tree flake inputs

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

## Step 11: Create clan inventory module

**File**: `modules/flake-parts/clan.nix`

```nix
{ inputs, ... }:
{
  imports = [ inputs.clan-core.flakeModules.default ];

  clan = {
    meta.name = "nix-config";
    specialArgs = {
      inherit inputs;
    };

    # Machine inventory
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
        # blackphos is controller
        roles.controller.machines.blackphos = { };
        # All machines are peers
        roles.peer.tags."workstation" = { };
      };
    };

    # Secrets configuration
    secrets.sops.defaultGroups = [ "admins" ];
  };
}
```

**Note**: Inventory defines all four hosts, but only blackphos will be migrated in Phase 1.

## Step 12: Initialize clan secrets structure

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
