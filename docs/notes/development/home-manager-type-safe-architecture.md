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
│   ├── app.nix                  # ENHANCE: Smart resolution app (see below)
│   ├── core/                    # NEW: Core home-manager modules
│   │   ├── default.nix          # Base config (home.stateVersion, etc)
│   │   └── imports.nix          # Auto-import core modules
│   ├── users/                   # KEEP (but restructure)
│   │   ├── crs58/
│   │   │   └── default.nix      # flake.modules.homeManager.user-crs58
│   │   └── raquel/
│   │       └── default.nix      # flake.modules.homeManager.user-raquel
│   └── generic-configs.nix      # NEW: System-generic configs for portable usage
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

### Implementation: home/generic-configs.nix

```nix
{
  # Generic/portable configs for one-liner app usage
  # These enable "nix run" on any system without machine-specific config

  homeHosts."crs58-x86_64-linux" = {
    user = "crs58";
    system = "x86_64-linux";
    # No machine reference - this is portable
  };

  homeHosts."crs58-aarch64-darwin" = {
    user = "crs58";
    system = "aarch64-darwin";
  };

  homeHosts."raquel-aarch64-darwin" = {
    user = "raquel";
    system = "aarch64-darwin";
  };
}
```

### Implementation: home/app.nix (smart resolution)

This app provides the one-liner activation UX while intelligently selecting between machine-specific and generic configs.

```nix
{ ... }:
{
  perSystem =
    {
      pkgs,
      system,
      lib,
      config,
      ...
    }:
    {
      apps = {
        home = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "home-switch";
              runtimeInputs = [
                pkgs.nh
                pkgs.jq
              ];
              text = ''
                set -euo pipefail

                # Show help if requested or no args provided
                if [ $# -eq 0 ] || [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
                  current_user="''${USER:-$(id -un)}"
                  current_host=$(hostname -s)
                  cat >&2 <<-EOF
                	Usage: nix run <flake> [-- <user-or-config> [flake] [NH_FLAGS...]]

                	Smart resolution (tries in order):
                	  1. Exact config name if provided (e.g., "crs58-blackphos")
                	  2. Machine-specific: <user>-<hostname>
                	  3. System-generic: <user>-<system>

                	Examples:
                	  # Auto-detect (tries: $current_user-$current_host, then $current_user-${system})
                	  nix run github:cameronraysmith/test-clan
                	  nix run github:cameronraysmith/test-clan -- $current_user

                	  # Explicit config name
                	  nix run . -- crs58-blackphos
                	  nix run . -- raquel-aarch64-darwin

                	  # Override flake location (for development)
                	  nix run . -- $current_user . --dry

                	  # Different user
                	  nix run . -- raquel

                	Arguments:
                	  user-or-config  - Username or full config name (default: \$USER)
                	  flake          - Flake path (default: github:cameronraysmith/test-clan)
                	  NH_FLAGS       - Flags for 'nh home switch' (--dry, --verbose, etc.)

                	Current context:
                	  User:   $current_user
                	  Host:   $current_host
                	  System: ${system}
                	EOF
                  exit 1
                fi

                # Get username or config name (default to current user)
                user_or_config="''${1:-''${USER:-$(id -un)}}"
                shift || true

                # Check if next arg is a flake path (doesn't start with -)
                if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
                  flake="$1"
                  shift
                else
                  flake="github:cameronraysmith/test-clan"
                fi

                current_system="${system}"
                current_host=$(hostname -s)

                # Smart resolution: try to find the best matching config
                # 1. If user_or_config contains a dash, treat as explicit config name
                # 2. Otherwise try: user-hostname, then user-system

                if [[ "$user_or_config" == *"-"* ]]; then
                  # Explicit config name provided (e.g., "crs58-blackphos")
                  config_name="$user_or_config"
                  echo "Using explicit config: $config_name"
                else
                  # Username provided, try smart resolution
                  username="$user_or_config"

                  # Build candidate list in priority order
                  declare -a candidates=(
                    "$username-$current_host"          # Machine-specific
                    "$username-$current_system"        # System-generic
                  )

                  echo "Resolving config for user: $username"
                  echo "  Current host: $current_host"
                  echo "  Current system: $current_system"
                  echo

                  # Query flake to see which configs exist
                  # This only evaluates flake metadata, very fast
                  echo "Checking available configurations..."
                  available_configs=$(nix flake show --json "$flake" 2>/dev/null | \
                    jq -r '.homeConfigurations | keys[]' 2>/dev/null || echo "")

                  config_name=""
                  for candidate in "''${candidates[@]}"; do
                    if echo "$available_configs" | grep -q "^$candidate\$"; then
                      config_name="$candidate"
                      echo "✓ Found: $candidate"
                      break
                    else
                      echo "  - Skipped: $candidate (not available)"
                    fi
                  done

                  if [ -z "$config_name" ]; then
                    cat >&2 <<-EOF

                	ERROR: No matching home configuration found for user '$username'

                	Tried (in order):
                	  - $username-$current_host (machine-specific)
                	  - $username-$current_system (system-generic)

                	Available configurations:
                	$(echo "$available_configs" | sed 's/^/  - /')

                	Hint: Either create a generic config for this system, or use explicit name:
                	  nix run $flake -- <exact-config-name>
                	EOF
                    exit 1
                  fi
                fi

                config_path="homeConfigurations.$config_name.activationPackage"

                cat <<-EOF
                	Activating home configuration...
                	  Config: $config_name
                	  Flake:  $flake
                	  Path:   $config_path

                	EOF

                exec nh home switch "$flake#$config_path" "$@"
              '';
            }
          );
        };

        default = config.apps.home;
      };
    };
}
```

**Key features of smart resolution:**

1. **Auto-detection** - Tries machine-specific first (user-hostname), falls back to generic (user-system)
2. **Explicit override** - Pass full config name like `crs58-blackphos` to skip resolution
3. **Fast metadata query** - Uses `nix flake show --json` to check available configs without building
4. **Clear error messages** - Shows what was tried and what's available when resolution fails
5. **Backward compatible** - Existing usage `nix run . -- crs58` continues working

**Resolution examples:**

```bash
# On blackphos as raquel
nix run .
# Tries: raquel-blackphos ✓ (found, uses machine-specific)

# On blackphos as crs58
nix run . -- crs58
# Tries: crs58-blackphos ✓ (found, uses machine-specific)

# On unknown-host as crs58 (no machine-specific config exists)
nix run . -- crs58
# Tries: crs58-unknown-host ✗ (not found)
# Tries: crs58-aarch64-darwin ✓ (found, uses generic)

# Explicit config name (bypasses resolution)
nix run . -- raquel-blackphos
# Uses: raquel-blackphos directly
```

## Migration path for test-clan

### Phase 1: Add type-safe layer (non-breaking)

1. Create `modules/flake/home-hosts.nix` with options definition
2. Create `modules/home/core/` with base modules
3. Create `modules/home/generic-configs.nix` with system-generic homeHosts
4. Keep existing `modules/home/configurations.nix` (parallel operation)
5. Test: Declare one homeHost, verify it generates correct homeConfiguration

### Phase 2: Enhance app with smart resolution

1. Update `modules/home/app.nix` to use smart resolution logic
2. Update help text to reflect new resolution strategy
3. Test: Verify app still works with generic configs (backward compatibility)
4. Test: Add machine-specific config, verify app prefers it

### Phase 3: Migrate users to typed declarations

1. Restructure `modules/home/users/*/default.nix` to use `flake.modules.homeManager.user-*`
2. Create machine-specific home configs in `modules/machines/*/home/*.nix`
3. Declare homeHosts for all user@machine combinations
4. Validate: `nix flake check` passes all type checks
5. Test: Verify app resolution chain works correctly

### Phase 4: Remove legacy generator

1. Delete `modules/home/configurations.nix`
2. Update documentation and `README.md` with smart resolution examples
3. Verify all usage examples work

### Phase 5: Add advanced features

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

### Smart app UX
- **Auto-detection** - Automatically selects machine-specific config when available
- **Intelligent fallback** - Falls back to generic config gracefully
- **One-liner deployment** - `nix run github:user/repo` works anywhere
- **Clear feedback** - Shows resolution process and helpful error messages
- **Explicit override** - Can specify exact config name when needed
- **Fast resolution** - Uses flake metadata query (no builds)

## Comparison to alternatives

### vs current test-clan approach
| Aspect | Current | Proposed |
|--------|---------|----------|
| User list | Hardcoded | Discovered via modules |
| Type safety | None | Full via options |
| Machine awareness | None | Optional typed references |
| User@Machine specificity | Generate all combos | Explicit per config |
| App resolution | System-based nested | Smart fallback chain |
| Config naming | `${system}.${user}` | `${user}-${machine/system}` |

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

## Design decisions made

1. **Naming convention:** `${user}-${machine}` for machine-specific, `${user}-${system}` for generic
   - Decision: User is primary identity, machine/system is context
   - Enables smart resolution by prefix matching on username

2. **Output structure:** Flat `homeConfigurations.*` only (no nested structure)
   - Decision: Simpler, works naturally with smart resolution
   - App uses metadata query to find configs, not nested lookups

3. **App resolution strategy:** Smart fallback chain (machine-specific → system-generic)
   - Decision: Auto-detect hostname, try specific first, fall back gracefully
   - Provides best UX: machine-specific when available, portable when needed

4. **Backward compatibility:** Parallel operation during migration, clean removal after
   - Decision: Phase 1 adds new system, Phase 4 removes old
   - Zero risk, full validation before commitment

## Open questions for discussion

1. **Default modules:** Should all homeHosts automatically get certain modules beyond core?
   - Current proposal: Only `core` module is automatic
   - Alternative: Auto-apply profile based on machine tags (desktop tag → desktop profile)
   - Trade-off: Convenience vs explicitness

2. **Generic config generation:** Should we auto-generate generic configs from user modules?
   - Current proposal: Explicit generic-configs.nix
   - Alternative: Generate `${user}-${system}` for all users × all systems automatically
   - Trade-off: Simplicity vs build time (generating unused configs)

3. **App hostname detection:** Should we support multiple fallback hostnames?
   - Current proposal: Single hostname from `hostname -s`
   - Alternative: Try both short and FQDN, or read from config
   - Use case: Machines with inconsistent hostname conventions

4. **CI checks:** Include homeConfiguration activation-script checks like mic92?
   - Recommendation: Yes, add to `modules/checks/validation.nix`
   - Validates configs actually build and activate without runtime testing

5. **Profile modules:** Should we create shared profile modules (desktop, server, minimal)?
   - Recommendation: Yes, as `flake.modules.homeManager.profile-*`
   - Enables composition: user module + profile module + machine overrides

## References

- gaetanlepage dendritic-nix-config: `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/flake/hosts.nix`
- mic92 clan-dotfiles: `~/projects/nix-workspace/mic92-clan-dotfiles/home-manager/flake-module.nix`
- pinpox clan-nixos: `~/projects/nix-workspace/pinpox-clan-nixos/flake.nix:214-232`
- test-clan current: `~/projects/nix-workspace/test-clan/modules/home/configurations.nix`
- Clan inventory spec: `~/projects/nix-workspace/clan-core/docs/inventory.md`

## Next steps

1. Review proposed architecture with user ✓
2. Clarify remaining open questions and design decisions
3. Implement Phase 1 (parallel type-safe layer with generic configs)
4. Implement Phase 2 (enhanced app with smart resolution)
5. Validate with actual homeHost declarations for test-clan users
6. Complete migration phases 3-5
7. Document patterns for infra repo migration
8. Consider profile modules for common configurations (desktop, server, etc.)
