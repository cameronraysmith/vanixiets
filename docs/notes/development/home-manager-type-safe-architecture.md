# Type-safe home-manager architecture for test-clan

This document outlines how to evolve test-clan's home-manager integration to achieve gaetanlepage-level type safety while maintaining mic92-style clan-core integration.

## Current state (test-clan)

**Strengths:**
- Uses dendritic flake-parts with import-tree auto-discovery
- Has clan.inventory for machines
- Separates user configs in `modules/home/users/`

**Limitations:**
- Hardcoded user list in `modules/home/configurations.nix:8-11`
- No type safety for home configurations
- No formal relationship between users, machines, and home configs
- Simple nested structure `homeConfigurations.${system}.${username}` assumes uniform cross-compilation

## Reference architectures analyzed

### gaetanlepage-dendritic-nix-config (type-safe dendritic)

**Key innovations:**
```nix
# modules/flake/hosts.nix - centralized type-safe transformer
options = {
  homeHosts = mkOption { type = types.attrsOf hostTypeHomeManager; };
};

config = {
  flake.homeConfigurations = lib.mapAttrs mkHost config.homeHosts;
};
```

**Pattern:**
1. Define options with NixOS module type system
2. Declare hosts via options throughout dendritic modules
3. Centralized flake-module transforms options → outputs
4. Type safety enforced at evaluation time

**Structure:**
```
modules/
├── flake/hosts.nix              # Options + transformer (homeHosts → homeConfigurations)
├── home/core/                   # Core home-manager modules
│   ├── default.nix              # Base config (username default)
│   └── imports.nix              # Auto-compose core modules
└── hosts/                       # Per-host definitions
    └── framework/
        ├── default.nix          # nixosHosts.framework declaration
        └── home/default.nix     # flake.modules.homeManager.host_framework
```

**Sophistication:**
- Type-checked host declarations (`hostTypeHomeManager` submodule)
- Automatic pkgs instantiation per host with system/unstable selection
- Module composition via `flake.modules.homeManager.*` namespace
- Clean separation: declaration vs output generation

### mic92-clan-dotfiles (clan integration)

**Key patterns:**
```nix
# home-manager/flake-module.nix
perSystem = { pkgs, lib, ... }: {
  legacyPackages.homeConfigurations = {
    common = homeManagerConfiguration { };
    desktop = homeManagerConfiguration { extraModules = [ ./desktop.nix ]; };
  };
};
```

**Integration with clan:**
- clan-core imported for features (sops-nix, multi-machine coordination)
- Does NOT use clan.inventory for home-manager
- homeConfigurations completely separate from clan machines
- Uses checks to validate homeConfigurations via activation-script

**Philosophy:**
home-manager is user-level, clan is machine-level - intentionally decoupled

### pinpox-clan-nixos (inventory-based clan)

**Key patterns:**
```nix
# inventory.nix
{
  machines.kiwi.tags = [ "desktop" ];
  instances.user-pinpox = {
    module.name = "users";
    roles.default.tags.all = { };
  };
}

# flake.nix (traditional, not flake-parts)
homeConfigurations = builtins.listToAttrs (
  map (name: ...)
    (builtins.attrNames (builtins.readDir ./home-manager/profiles))
);
```

**Integration:**
- Heavy clan.inventory usage for machines and services
- homeConfigurations still filesystem-based auto-discovery
- No formal link between inventory machines and home profiles

## Proposed architecture for test-clan

### Design principles

1. **Type safety** - Use NixOS module options for compile-time validation
2. **Dendritic compatibility** - Work with import-tree auto-discovery
3. **Clan integration** - Reference clan.inventory.machines, but don't duplicate
4. **Separation of concerns** - Users ≠ Machines ≠ HomeConfigs
5. **Progressive enhancement** - Build on current structure, don't rewrite

### Core insight: Three-layer model

```
Layer 1: Users (identity)
  └─ username, email, git config, SSH keys

Layer 2: Machines (from clan.inventory)
  └─ hostname, system, machineClass, tags

Layer 3: Home configurations (user @ machine)
  └─ Compose user modules + machine-specific home modules
```

**Relationship:**
- User configs are reusable across machines
- Machine-specific home configs extend user base
- homeConfigurations = cartesian product of users × systems (with opt-out)

### Proposed module structure

```
modules/
├── flake/
│   └── home-hosts.nix           # NEW: Type-safe homeHosts options + transformer
├── home/
│   ├── configurations.nix       # DELETE (replaced by home-hosts.nix)
│   ├── app.nix                  # KEEP (unchanged)
│   ├── core/                    # NEW: Core home-manager modules
│   │   ├── default.nix          # Base config (home.stateVersion, etc)
│   │   └── imports.nix          # Auto-import core modules
│   └── users/                   # KEEP (but restructure)
│       ├── crs58/
│       │   └── default.nix      # flake.modules.homeManager.user-crs58
│       └── raquel/
│           └── default.nix      # flake.modules.homeManager.user-raquel
└── machines/
    └── darwin/
        └── blackphos/
            └── home/
                ├── crs58.nix    # homeHosts.crs58-blackphos (admin)
                └── raquel.nix   # homeHosts.raquel-blackphos (primary)
```

### Implementation: flake/home-hosts.nix

```nix
{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (lib) types mkOption;
in
{
  options = {
    homeHosts = mkOption {
      type = types.attrsOf (types.submodule (
        { config, name, ... }:
        {
          options = {
            user = mkOption {
              type = types.str;
              description = "Username for this home configuration";
              example = "crs58";
            };

            system = mkOption {
              type = types.str;
              default = "x86_64-linux";
              description = "System architecture";
            };

            machine = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Optional reference to clan.inventory.machines hostname.
                If set, validates machine exists and can pull system from it.
              '';
            };

            unstable = mkOption {
              type = types.bool;
              default = true;
              description = "Use nixpkgs-unstable vs nixpkgs-stable";
            };

            modules = mkOption {
              type = with types; listOf deferredModule;
              default = [ ];
              description = "Extra home-manager modules for this config";
            };

            # Computed/internal
            pkgs = mkOption {
              type = types.pkgs;
              internal = true;
            };

            _userModule = mkOption {
              type = types.deferredModule;
              internal = true;
            };
          };

          config =
            let
              # Validate machine reference if provided
              machineExists =
                config.machine != null
                -> (builtins.hasAttr config.machine config.flake.clanInternals.machines);

              machineSystem =
                if config.machine != null
                then config.flake.clanInternals.machines.${config.machine}.system
                else null;

              # Use machine's system if available, otherwise use explicit system option
              finalSystem =
                if machineSystem != null
                then machineSystem
                else config.system;
            in
            {
              assertions = [
                {
                  assertion = machineExists;
                  message = "homeHost ${name} references non-existent machine: ${config.machine}";
                }
              ];

              system = lib.mkDefault finalSystem;

              pkgs = import (if config.unstable then inputs.nixpkgs else inputs.nixpkgs-stable) {
                inherit (config) system;
                config.allowUnfree = true;
              };

              _userModule = config.flake.modules.homeManager."user-${config.user}" or (
                throw "homeHost ${name} references undefined user module: user-${config.user}"
              );
            };
        }
      ));
      default = { };
      description = "Type-safe home-manager host configurations";
    };
  };

  config = {
    flake.homeConfigurations =
      let
        mkHomeConfig = name: opts:
          inputs.home-manager.lib.homeManagerConfiguration {
            extraSpecialArgs = {
              inherit inputs name;
              inherit (opts) machine;
            };
            inherit (opts) pkgs;
            modules = [
              config.flake.modules.homeManager.core
              opts._userModule
              { home.username = opts.user; }
            ] ++ opts.modules;
          };
      in
      lib.mapAttrs mkHomeConfig config.homeHosts;
  };
}
```

### Implementation: home/core/default.nix

```nix
{
  flake.modules.homeManager.core = { config, lib, pkgs, ... }: {
    home.stateVersion = lib.mkDefault "24.11";
    home.homeDirectory = lib.mkDefault (
      if pkgs.stdenv.isDarwin
      then "/Users/${config.home.username}"
      else "/home/${config.home.username}"
    );

    programs.home-manager.enable = true;
  };
}
```

### Implementation: home/users/crs58/default.nix

```nix
{
  flake.modules.homeManager.user-crs58 = { pkgs, ... }: {
    # User identity (reusable across all machines)
    programs.git = {
      enable = true;
      userName = "Cameron Smith";
      userEmail = "cameron.ray.smith@gmail.com";
    };

    programs.zsh.enable = true;
    programs.starship.enable = true;

    home.packages = with pkgs; [ git gh ];
  };
}
```

### Implementation: machines/darwin/blackphos/home/raquel.nix

```nix
{ config, ... }:
{
  homeHosts.raquel-blackphos = {
    user = "raquel";
    machine = "blackphos";  # References clan.inventory.machines.blackphos
    # system automatically inherited from machine (aarch64-darwin)

    modules = [
      # Machine-specific home config for raquel on blackphos
      {
        programs.vscode.enable = true;

        # Access machine metadata via specialArgs.machine
        home.sessionVariables = {
          MACHINE_HOSTNAME = "blackphos";
        };
      }

      # Could also reference shared machine-specific modules
      # config.flake.modules.homeManager.darwin-desktop
    ];
  };
}
```

### Implementation: machines/darwin/blackphos/home/crs58.nix

```nix
{
  homeHosts.crs58-blackphos = {
    user = "crs58";
    machine = "blackphos";

    modules = [
      # Admin user gets fewer GUI apps
      {
        programs.tmux.enable = true;
        home.sessionVariables.ROLE = "admin";
      }
    ];
  };
}
```

## Migration path for test-clan

### Phase 1: Add type-safe layer (non-breaking)

1. Create `modules/flake/home-hosts.nix` with options definition
2. Create `modules/home/core/` with base modules
3. Keep existing `modules/home/configurations.nix` (parallel operation)
4. Test: Declare one homeHost, verify it generates correct homeConfiguration

### Phase 2: Migrate users to typed declarations

1. Restructure `modules/home/users/*/default.nix` to use `flake.modules.homeManager.user-*`
2. Create machine-specific home configs in `modules/machines/*/home/*.nix`
3. Declare homeHosts for all user@machine combinations
4. Validate: `nix flake check` passes all type checks

### Phase 3: Remove legacy generator

1. Delete `modules/home/configurations.nix`
2. Update documentation and `README.md`
3. Update `modules/home/app.nix` if needed for new attribute structure

### Phase 4: Add advanced features

1. Shared machine-class modules (e.g., `homeManager.darwin-desktop`)
2. Conditional module application via tags (following clan pattern)
3. Cross-compilation controls (opt-out of certain system builds)
4. CI checks for homeConfiguration activation scripts

## Benefits of proposed architecture

### Type safety
- Typo in username → compile error (undefined user-* module)
- Invalid machine reference → assertion failure with clear message
- Missing required options → evaluation error before build

### Maintainability
- User configs in one place (`home/users/`)
- Machine-specific overrides colocated with machine (`machines/*/home/`)
- Clear dependency graph visible in module structure

### Scalability
- Adding new user: Create `home/users/newuser/default.nix`, reference in homeHosts
- Adding new machine: Machine-specific home config optional
- No manual updates to cartesian product generators

### Clan integration
- Validates machine references against clan.inventory
- Can inherit system architecture from clan machines
- Respects clan's machine/service separation (users are orthogonal)

### Dendritic compatibility
- All modules auto-discovered via import-tree
- No manual imports in flake.nix
- Follows dendritic namespace pattern (`flake.modules.homeManager.*`)

## Comparison to alternatives

### vs current test-clan approach
| Aspect | Current | Proposed |
|--------|---------|----------|
| User list | Hardcoded | Discovered via modules |
| Type safety | None | Full via options |
| Machine awareness | None | Optional typed references |
| User@Machine specificity | Generate all combos | Explicit per config |

### vs gaetanlepage pattern
| Aspect | gaetanlepage | Proposed |
|--------|--------------|----------|
| Options structure | homeHosts flat | homeHosts + user modules |
| Module namespace | host_NAME | user-NAME + host_NAME |
| Machine integration | nixosHosts separate | Clan inventory references |
| Discovery | Import-tree | Import-tree |

### vs mic92 pattern
| Aspect | mic92 | Proposed |
|--------|-------|----------|
| Flake-parts usage | perSystem.legacyPackages | flake.homeConfigurations |
| Type safety | Helper function | Options + submodules |
| Clan integration | Features only | Inventory references |
| Extensibility | extraModules param | modules option + namespace |

### vs pinpox pattern
| Aspect | pinpox | Proposed |
|--------|--------|----------|
| Discovery | Filesystem (readDir) | Module-based (typed) |
| Clan inventory | Heavy usage | Validation references only |
| Home/Machine link | None | Optional typed reference |
| Type safety | None | Full via options |

## Example usage patterns

### Simple user (all machines)

```nix
# home/users/devuser/default.nix
{
  flake.modules.homeManager.user-devuser = { ... }: {
    programs.neovim.enable = true;
  };
}

# Declare everywhere (could be automated via allSystems helper)
# machines/nixos/server1/home/devuser.nix
{ homeHosts.devuser-server1 = { user = "devuser"; machine = "server1"; }; }

# machines/darwin/laptop1/home/devuser.nix
{ homeHosts.devuser-laptop1 = { user = "devuser"; machine = "laptop1"; }; }
```

### Complex user (machine-specific profiles)

```nix
# home/users/poweruser/default.nix - base config
{
  flake.modules.homeManager.user-poweruser = { ... }: {
    programs.git.enable = true;
  };
}

# home/profiles/desktop.nix - shared desktop profile
{
  flake.modules.homeManager.profile-desktop = { ... }: {
    programs.firefox.enable = true;
    services.dunst.enable = true;
  };
}

# machines/nixos/workstation/home/poweruser.nix
{
  homeHosts.poweruser-workstation = {
    user = "poweruser";
    machine = "workstation";
    modules = [
      config.flake.modules.homeManager.profile-desktop
      { programs.vscode.enable = true; }
    ];
  };
}

# machines/nixos/server/home/poweruser.nix
{
  homeHosts.poweruser-server = {
    user = "poweruser";
    machine = "server";
    modules = [
      # No desktop profile, server-specific tools
      { programs.tmux.enable = true; }
    ];
  };
}
```

### Cross-compilation control

```nix
# Generate for specific systems only
# machines/nixos/x86-server/home/admin.nix
{
  homeHosts.admin-x86-server = {
    user = "admin";
    system = "x86_64-linux";  # Explicit, don't cross-compile
  };
}

# Use machine's system automatically
# machines/darwin/m1-laptop/home/user.nix
{
  homeHosts.user-m1-laptop = {
    user = "user";
    machine = "m1-laptop";  # system = aarch64-darwin inherited
  };
}
```

## Open questions for discussion

1. **Naming convention:** `${user}-${machine}` vs `${machine}-${user}` for homeHosts keys?
   - Recommendation: `${user}-${machine}` (user is primary identity)

2. **Default modules:** Should all homeHosts automatically get certain modules?
   - Current proposal: Only `core` module is automatic
   - Alternative: Auto-apply profile based on machine tags (desktop tag → desktop profile)

3. **System cross-compilation:** Generate for all systems or explicit only?
   - Current proposal: Explicit per homeHost
   - Alternative: Add `generateForSystems` option to auto-create variants

4. **Backward compatibility:** Keep old structure during migration?
   - Recommendation: Yes (Phase 1), remove after validation (Phase 3)

5. **CI checks:** Include homeConfiguration activation-script checks like mic92?
   - Recommendation: Yes, add to `modules/checks/validation.nix`

## References

- gaetanlepage dendritic-nix-config: `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/flake/hosts.nix`
- mic92 clan-dotfiles: `~/projects/nix-workspace/mic92-clan-dotfiles/home-manager/flake-module.nix`
- pinpox clan-nixos: `~/projects/nix-workspace/pinpox-clan-nixos/flake.nix:214-232`
- test-clan current: `~/projects/nix-workspace/test-clan/modules/home/configurations.nix`
- Clan inventory spec: `~/projects/nix-workspace/clan-core/docs/inventory.md`

## Next steps

1. Review proposed architecture with user
2. Clarify open questions and design decisions
3. Implement Phase 1 (parallel type-safe layer)
4. Validate with actual homeHost declarations for test-clan users
5. Complete migration phases 2-4
6. Document patterns for infra repo migration
