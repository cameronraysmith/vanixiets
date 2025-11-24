# Dendritic Flake-Parts Architecture Pattern

**Last Updated**: 2025-11-17 (Post-refactoring, Stories 1.7 and 1.10C complete)

This document explains the dendritic flake-parts architectural pattern implemented in test-clan, refined through 9 major architectural improvements in November 2025.

## What is the Dendritic Pattern?

The dendritic pattern is an architectural approach that uses flake-parts' module system combined with import-tree auto-discovery to eliminate boilerplate and enable automatic module composition.
The name "dendritic" refers to the tree-like structure of modules that branch and merge naturally, like dendrites in neural networks.

### Core Principle

**Multiple files → Same namespace → Auto-merge**

Instead of manually importing and combining modules, the dendritic pattern uses flake-parts' eval-modules system to automatically merge all modules that declare the same namespace.

## How It Works

### 1. Import-Tree Auto-Discovery

The flake.nix uses import-tree to automatically discover all .nix files in `modules/`:

```nix
# flake.nix
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
```

This single line:
- Discovers all .nix files in modules/ recursively
- Evaluates them as flake-parts modules
- No manual imports needed in flake.nix

### 2. Namespace Merging via eval-modules

Flake-parts' eval-modules system provides two merging strategies:

#### Deep Attribute Merging (for nested attrsets)

Multiple files declaring the same namespace have their attributes recursively merged:

```nix
# modules/darwin/system-defaults/dock.nix
{ ... }: {
  flake.modules.darwin.base = { ... }: {
    system.defaults.dock = {
      autohide = true;
      tilesize = 48;
    };
  };
}

# modules/darwin/system-defaults/finder.nix
{ ... }: {
  flake.modules.darwin.base = { ... }: {
    system.defaults.finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
    };
  };
}
```

Result: Both modules merge into a single `flake.modules.darwin.base` with both `system.defaults.dock` and `system.defaults.finder` attributes.

#### List Concatenation (for overlay composition)

Multiple modules declaring list attributes have their lists automatically concatenated:

```nix
# modules/nixpkgs/overlays/channels.nix
{ ... }: {
  flake.nixpkgsOverlays = [
    (final: prev: {
      stable = import inputs.nixpkgs-stable { ... };
      unstable = import inputs.nixpkgs { ... };
    })
  ];
}

# modules/nixpkgs/overlays/hotfixes.nix
{ ... }: {
  flake.nixpkgsOverlays = [
    (final: prev: {
      # Package fixes
    })
  ];
}
```

Result: `flake.nixpkgsOverlays` contains both overlays in discovery order, composed via `lib.composeManyExtensions` in `modules/nixpkgs/compose.nix`.

### 3. No Manual Imports Required

Traditional NixOS/nix-darwin configuration:

```nix
# Traditional approach - manual imports
imports = [
  ./hardware-configuration.nix
  ./networking.nix
  ./users.nix
  ./packages.nix
  # ... dozens more
];
```

Dendritic approach:

```nix
# Dendritic approach - zero imports
# All modules in modules/ directory auto-discovered and merged
```

## Why Use the Dendritic Pattern?

### Benefits

1. **Zero boilerplate**: No manual imports, no list management, no merge conflicts
2. **Automatic composition**: Modules in same namespace merge automatically
3. **Optimal granularity**: Each file can be as focused as needed (>7 line heuristic)
4. **Discoverability**: File tree structure mirrors logical organization
5. **Safe refactoring**: Split/merge modules without updating import lists
6. **DRY by default**: Shared configs via simple imports (e.g., `lib/caches.nix`)

### Comparison: Dendritic vs. Traditional

| Aspect | Traditional | Dendritic |
|--------|-------------|-----------|
| Module discovery | Manual imports | Auto-discovery via import-tree |
| Module merging | Explicit merge | Automatic via eval-modules |
| Overlay composition | `_overlays` escape hatch | List concatenation |
| File organization | Arbitrary (imports determine structure) | File tree IS the structure |
| Refactoring cost | Update all imports | Move files, done |
| Configuration sharing | Copy-paste or complex imports | Simple `import ../../lib/file.nix` |

## Module Organization Philosophy

### Size Heuristic: >7 Lines

If a logical unit of configuration exceeds ~7 lines, consider extracting it to a separate module.

**Example: darwin/system-defaults decomposition**

Before (monolithic, 143 lines):
```
modules/darwin/system-defaults.nix  # Everything in one file
```

After (9 focused modules, ~15-20 lines each):
```
modules/darwin/system-defaults/
├── dock.nix              # Dock configuration (20 lines)
├── finder.nix            # Finder settings (15 lines)
├── input-devices.nix     # Mouse/trackpad (12 lines)
├── loginwindow.nix       # Login window (8 lines)
├── nsglobaldomain.nix    # Global defaults (18 lines)
├── window-manager.nix    # Window management (10 lines)
├── screencapture.nix     # Screenshot settings (8 lines)
├── custom-user-prefs.nix # Custom preferences (15 lines)
└── misc-defaults.nix     # Misc settings (12 lines)
```

All modules merge into `flake.modules.darwin.base` automatically.

### Namespace Design

Choose namespaces that reflect **logical grouping**, not file paths:

```nix
# Good: Logical namespace (multiple files merge into same base)
flake.modules.darwin.base        # Base darwin config (many files)
flake.modules.nixos.base         # Base nixos config (many files)
flake.modules.nixos."machines/nixos/cinnabar"  # Specific machine

# Avoid: File-path-based namespaces (defeats auto-merge benefits)
flake.modules.darwin.system-defaults.dock      # Too granular
flake.modules.darwin.system-defaults.finder    # Too granular
```

## Key Patterns in test-clan

### Pattern 1: DRY Cache Configuration

Single source of truth for binary caches:

```nix
# lib/caches.nix - Shared data
{
  substituters = [ "https://cache.nixos.org" /* ... */ ];
  publicKeys = [ "cache.nixos.org-1:..." /* ... */ ];
}

# flake.nix - CLI usage (literal required)
nixConfig = {
  extra-substituters = [ "https://cache.nixos.org" /* ... */ ];
  extra-trusted-public-keys = [ "cache.nixos.org-1:..." /* ... */ ];
}

# modules/system/caches.nix - Machine configs
let cacheConfig = import ../../lib/caches.nix; in {
  flake.modules.darwin.base = {
    nix.settings.substituters = cacheConfig.substituters;
    nix.settings.trusted-public-keys = cacheConfig.publicKeys;
  };
  flake.modules.nixos.base = {
    nix.settings.substituters = cacheConfig.substituters;
    nix.settings.trusted-public-keys = cacheConfig.publicKeys;
  };
}
```

Result: Update caches in one place (`lib/caches.nix`), all three locations sync automatically.

### Pattern 2: Per-User Inventory Modules

User service instances decomposed into focused per-user modules:

Before (monolithic):
```
modules/clan/inventory/services/users.nix  # All users in one file
```

After (per-user modules):
```
modules/clan/inventory/services/users/
├── cameron.nix  # Admin user (modern machines)
└── crs58.nix    # Admin user (legacy machines)
```

Both modules declare `clan.inventory.instances.user-*` and auto-merge into the inventory.

### Pattern 3: Extracted Disko Configurations

Machine-specific disk layouts extracted from main machine module:

```
modules/machines/nixos/cinnabar/
├── default.nix      # Machine configuration
└── disko.nix        # Disk layout (merges into machines/nixos/cinnabar namespace)
```

Both files merge into `flake.modules.nixos."machines/nixos/cinnabar"`.

### Pattern 4: Overlay Composition via List Concatenation

Eliminated `_overlays` escape hatch using dendritic list composition:

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
    (final: prev: { /* package fixes */ })
  ];
}

# modules/nixpkgs/overlays/overrides.nix
{ ... }: {
  flake.nixpkgsOverlays = [
    (final: prev: { /* version overrides */ })
  ];
}

# modules/nixpkgs/compose.nix - Compose all overlays
{ config, lib, ... }: {
  flake.overlays.default = final: prev:
    let
      internalOverlays = lib.composeManyExtensions config.flake.nixpkgsOverlays;
    in
    (internalOverlays final prev) // customPackages // externalOverlays;
}
```

Result: Add new overlay by creating file in `overlays/`, no manual registration needed.

## How to Add New Modules

### Adding a Darwin System Default

1. Create file in appropriate directory:
   ```
   modules/darwin/system-defaults/new-setting.nix
   ```

2. Declare the namespace (merges automatically):
   ```nix
   { ... }: {
     flake.modules.darwin.base = { ... }: {
       system.defaults.newSetting = {
         # configuration here
       };
     };
   }
   ```

3. Done. No imports, no registration, auto-discovered and merged.

### Adding a New Overlay

1. Create file in overlays directory:
   ```
   modules/nixpkgs/overlays/my-overlay.nix
   ```

2. Append to the list:
   ```nix
   { ... }: {
     flake.nixpkgsOverlays = [
       (final: prev: {
         myPackage = prev.myPackage.overrideAttrs { ... };
       })
     ];
   }
   ```

3. Done. Auto-concatenated with other overlays, composed in `compose.nix`.

### Adding a Machine-Specific Module

1. Create file in machine directory:
   ```
   modules/machines/nixos/my-machine/custom-config.nix
   ```

2. Use machine-specific namespace:
   ```nix
   { ... }: {
     flake.modules.nixos."machines/nixos/my-machine" = {
       # machine-specific configuration
     };
   }
   ```

3. Done. Merges with other modules for that machine.

### Adding Shared Configuration

1. Create file in lib/ for pure data:
   ```
   lib/my-config.nix
   ```

2. Import where needed:
   ```nix
   let myConfig = import ../../lib/my-config.nix; in
   {
     flake.modules.darwin.base = {
       # Use myConfig here
     };
   }
   ```

## Validation and Testing

The test suite validates the dendritic pattern implementation:

```bash
# Fast validation (~5s)
just test-quick

# Full test suite
just test
```

Key tests:
- **TC-008**: Dendritic module discovery (verifies import-tree auto-discovery)
- **TC-009**: Namespace exports (verifies modules merge correctly)
- **TC-013**: Module evaluation isolation (verifies no cross-contamination)
- **TC-014**: SpecialArgs propagation (verifies inputs available to all modules)

## Migration from Traditional Patterns

### Step 1: Identify Monolithic Modules

Look for files >50 lines with multiple logical sections:
- Large `default.nix` files with mixed concerns
- Single files containing unrelated configuration

### Step 2: Extract Logical Units

For each logical unit >7 lines:
1. Create new file in appropriate subdirectory
2. Copy logical unit to new file
3. Wrap in namespace declaration
4. Remove from original file

### Step 3: Remove Manual Imports

Once all modules use namespaces:
1. Remove `imports = [ ... ];` lists
2. Verify `import-tree` auto-discovery works
3. Run tests to validate merging

### Step 4: Eliminate Escape Hatches

Replace underscore-prefixed workarounds:
- `_overlays` → `flake.nixpkgsOverlays` list
- `_modules` → proper namespace declarations

## Common Patterns

### Conditional Merging

```nix
{ lib, ... }: {
  flake.modules.darwin.base = { config, ... }: {
    # Conditional based on machine config
    programs.foo.enable = lib.mkIf config.services.bar.enable true;
  };
}
```

### Cross-Platform Modules

```nix
{ ... }: {
  # Merge into both darwin and nixos base
  flake.modules.darwin.base = {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  };
  flake.modules.nixos.base = {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
```

### Per-Machine Overrides

```nix
# modules/system/base-config.nix - Shared
{ ... }: {
  flake.modules.nixos.base = {
    services.openssh.enable = true;
  };
}

# modules/machines/nixos/cinnabar/custom.nix - Override
{ ... }: {
  flake.modules.nixos."machines/nixos/cinnabar" = {
    services.openssh.ports = [ 2222 ];  # Different port for this machine
  };
}
```

## References

- **Dendritic pattern source**: <https://github.com/dendriticinfra/dendritic-flake-parts>
- **Import-tree**: <https://github.com/vic/import-tree>
- **Flake-parts documentation**: <https://flake.parts>
- **Example implementations**: See CLAUDE.md for repository links

## Refactoring History

The following refactorings were completed in November 2025 (Story 1.7):

1. ✅ Split monolithic modules into focused auto-merged modules (darwin/system-defaults)
2. ✅ Eliminated underscore escape hatches (`_overlays` → `overlays` with list composition)
3. ✅ Implemented DRY cache configuration via `lib/caches.nix`
4. ✅ Extracted disko configs to separate modules per machine
5. ✅ Split user inventory into per-user modules (cameron.nix, crs58.nix)
6. ✅ Removed redundant directories (machines/home/)
7. ✅ Decomposed darwin/system-defaults.nix into 9 focused modules
8. ✅ Refactored overlays to use `flake.nixpkgsOverlays` list composition
9. ✅ Applied >7-line heuristic for optimal module sizing

These improvements reduced boilerplate, improved discoverability, and validated the dendritic pattern for production migration.
