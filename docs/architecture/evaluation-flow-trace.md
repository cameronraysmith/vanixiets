# Test-Clan Complete Evaluation Flow Trace

## Executive Summary

This document maps the complete evaluation path in test-clan from `flake.nix` entry point through to machine build outputs, specifically identifying where `nixpkgs.config` instantiation occurs and where external creation assertions can fail.

**Key Finding**: The evaluation splits into three distinct paths:
1. **Flake-parts perSystem path** (lines 15-37 in per-system.nix) - creates pkgs at module evaluation time
2. **Clan machine path** (clan-core internal) - instantiates nixpkgs per-machine WITHOUT perSystem context
3. **Flake modules export path** - provides modules to clan via `config.flake.modules.*`

The assertion failure occurs when clan tries to use externally-provided modules (that assume perSystem's pkgs) inside its own nixpkgs instantiation context.

---

## Part 1: Flake Entry Point

### File: `/Users/crs58/projects/nix-workspace/test-clan/flake.nix` (109 lines)

**Lines 1-6**: Entry function
```nix
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
```

**What happens**:
- `inputs.import-tree ./modules` recursively discovers all `.nix` files in `modules/` directory
- Returns a function that takes flake-parts module arguments
- `flake-parts.lib.mkFlake` evaluates all discovered modules with eval-modules system
- Modules execute in evaluation order (filesystem traversal)

**Lines 8-82**: Input dependencies
- All inputs pinned in flake.lock
- Includes `flake-parts`, `clan-core`, `import-tree`
- Critical: Most inputs follow main `nixpkgs` (lines 10-82)

---

## Part 2: Module Discovery and Evaluation Order

### How import-tree Works

**Import-tree semantics** (discovered by flake-parts at line 6):
- Recursively scans `modules/` directory
- Generates list of `.nix` files by alphabetical path order
- Converts filesystem paths to flake-parts module imports
- Each `.nix` file becomes a separate flake-parts module evaluation

**Evaluation order** (filesystem sort):
```
modules/checks/*.nix
modules/clan/*.nix           # clan/core.nix FIRST (imports clan-core flakeModule)
modules/clan/inventory/*.nix
modules/clan/machines.nix    # LAST in clan/ (references config.flake.modules.*)
modules/darwin/*.nix
modules/dev-shell.nix
modules/flake-parts.nix      # Enables flake.modules merging
modules/formatting.nix
modules/home/*.nix
modules/lib/*.nix
modules/machines/*.nix       # Exports flake.modules.nixos.* and flake.modules.darwin.*
modules/nixos/*.nix
modules/nixpkgs/*.nix        # Configures perSystem pkgs
modules/system/*.nix         # Exports flake.modules.nixos.base (auto-merges)
modules/systems.nix
modules/terranix/*.nix
```

**Critical ordering constraint**: `clan/machines.nix` executes AFTER all module exports are available in `config.flake.modules.*`.

---

## Part 3: Nixpkgs Configuration Layer (perSystem)

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/nixpkgs/default.nix` (19 lines)

**Structure**: Dendritic pattern with three submodules
```
nixpkgs/
├── default.nix          (this file - imports submodules)
├── overlays-option.nix  (declares flake.nixpkgsOverlays as mergeable list)
├── per-system.nix       (configures perSystem pkgs)
├── compose.nix          (composes overlays into flake.overlays.default)
└── overlays/
    ├── channels.nix     (multi-channel access: stable, unstable, patched)
    ├── hotfixes.nix     (cross-platform package hotfixes)
    ├── overrides.nix    (package build modifications)
    ├── nvim-treesitter-main.nix
    ├── fish-stable-darwin.nix
    └── markdown-tree-parser.nix
```

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/nixpkgs/per-system.nix` (38 lines)

**Context**: This is a flake-parts module with `perSystem` hook.

**Lines 15-37**: perSystem evaluation block
```nix
perSystem = { system, ... }: {
  _module.args.pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = config.flake.nixpkgsOverlays ++ [ inputs.nuenv.overlays.nuenv ];
  };
  pkgsDirectory = ../../pkgs/by-name;
};
```

**What happens here**:
1. **Scope**: Runs within `perSystem` context (per-system evaluation)
2. **Instance creation**: Calls `import inputs.nixpkgs` → creates NEW nixpkgs instance
3. **Config context**: Within this instance's eval, `config.allowUnfree = true` is valid (externally-provided config)
4. **Overlay composition**: 
   - `config.flake.nixpkgsOverlays` - auto-collected from all overlay modules via list concatenation
   - `inputs.nuenv.overlays.nuenv` - external overlay
5. **Result**: `_module.args.pkgs` makes this pkgs available to all perSystem evaluations

**Critical design point**: This pkgs instance is ONLY available within perSystem scope. It's used for:
- Checks
- Packages  
- Development shells
- Devshells evaluation

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/nixpkgs/overlays-option.nix` (32 lines)

**Purpose**: Declares `flake.nixpkgsOverlays` as a mergeable list option.

```nix
options = {
  flake = mkSubmoduleOptions {
    nixpkgsOverlays = mkOption {
      type = types.listOf types.unspecified;
      default = [ ];
    };
  };
};
```

**Why needed**: Allows multiple modules to independently declare:
```nix
flake.nixpkgsOverlays = [ overlay1 ];  # Module A
flake.nixpkgsOverlays = [ overlay2 ];  # Module B
```

Without this declaration, flake-parts would treat assignments as conflicts instead of mergeable list items.

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/nixpkgs/compose.nix` (45 lines)

**Purpose**: Composes `flake.nixpkgsOverlays` list into `flake.overlays.default`.

```nix
flake.overlays.default = final: prev:
  let
    internalOverlays = lib.composeManyExtensions config.flake.nixpkgsOverlays;
    nuenvOverlay = inputs.nuenv.overlays.nuenv;
    customPackages = withSystem prev.stdenv.hostPlatform.system (
      { config, ... }: config.packages or { }
    );
  in
  (internalOverlays final prev) // customPackages // (nuenvOverlay final prev);
```

**Composition order**:
1. Internal overlays (channels, hotfixes, overrides, nvim-treesitter-main)
2. Custom packages from pkgs-by-name
3. External overlays (nuenv)

**Key feature**: `withSystem` to access pkgs-by-name packages for target system.

### Overlay Modules

#### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/nixpkgs/overlays/channels.nix` (61 lines)

Exports to `flake.nixpkgsOverlays`:
```nix
flake.nixpkgsOverlays = [
  (final: prev: {
    inputs = inputs;
    nixpkgs = import inputs.nixpkgs { system = prev.stdenv.hostPlatform.system; config.allowUnfree = true; };
    patched = import patched-nixpkgs { ... };
    stable = (import inputs.nixpkgs-darwin-stable | inputs.nixpkgs-linux-stable) { ... };
    unstable = import inputs.nixpkgs { ... };
  })
];
```

**Design**: Creates multi-channel access within pkgs:
- `pkgs.stable.somePackage` → stable version
- `pkgs.unstable.somePackage` → unstable version
- `pkgs.patched.somePackage` → patched version (empty in test-clan)

#### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/nixpkgs/overlays/hotfixes.nix` (61 lines)

Exports platform-specific package hotfixes via overlay:
```nix
flake.nixpkgsOverlays = [
  (final: prev: {
    # Cross-platform
    inherit (final.stable) micromamba;
    # Darwin-specific (if any)
    # Linux-specific (if any)
  })
];
```

#### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/nixpkgs/overlays/overrides.nix` (29 lines)

Placeholder for per-package build modifications via `overrideAttrs`.

#### Other overlays
- `nvim-treesitter-main.nix` - treesitter parser versions
- `fish-stable-darwin.nix` - Darwin-specific fish shell version
- `markdown-tree-parser.nix` - Custom markdown parsing package

---

## Part 4: Flake-Parts Module System Setup

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/flake-parts.nix` (8 lines)

```nix
imports = [
  inputs.flake-parts.flakeModules.modules  # Enable flake.modules merging
  inputs.nix-unit.modules.flake.default
];
```

**What this does**:
- Imports flake-parts' `modules` flakeModule
- Enables `flake.modules.*` namespace for dendritic composition
- This allows multiple modules to append to `flake.modules.nixos.*` and `flake.modules.darwin.*`

---

## Part 5: Clan Integration

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/core.nix` (7 lines)

```nix
imports = [
  inputs.clan-core.flakeModules.default
  inputs.terranix.flakeModule
];
```

**What happens**:
- Imports clan-core flakeModule
- This sets up `clan.machines`, `clan.inventory`, `clanInternals` namespaces
- Makes clan machine definitions available

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/machines.nix` (24 lines)

```nix
clan.machines = {
  cinnabar = {
    imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
  };
  electrum = {
    imports = [ config.flake.modules.nixos."machines/nixos/electrum" ];
  };
  gcp-vm = {
    imports = [ config.flake.modules.nixos."machines/nixos/gcp-vm" ];
  };
  test-darwin = {
    imports = [ config.flake.modules.darwin."machines/darwin/test-darwin" ];
  };
  blackphos = {
    imports = [ config.flake.modules.darwin."machines/darwin/blackphos" ];
  };
};
```

**Critical interaction**:
- Clan takes these machine definitions
- For EACH machine, clan evaluates its modules in a NixOS/nix-darwin module context
- **NOT** in the flake-parts `perSystem` context
- Each machine gets its own independent nixpkgs instantiation

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/meta.nix` (11 lines)

```nix
clan = {
  meta.name = "test-clan";
  meta.description = "Phase 0: Architectural validation + infrastructure deployment";
  meta.tld = "clan";
  specialArgs = { inherit inputs; };
};
```

Passes flake inputs to all machines via specialArgs (needed for accessing overlays).

---

## Part 6: Machine Module Exports (Dendritic Composition)

### System Modules - Auto-merged into `flake.modules.nixos.base`

Multiple files declare and merge into the same namespace:

#### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/system/nix-settings.nix` (23 lines)

```nix
flake.modules.nixos.base = { lib, ... }: {
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.trusted-users = ["root" "@wheel"];
  system.stateVersion = lib.mkDefault "24.11";
};
```

#### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/system/caches.nix` (17 lines)

```nix
flake.modules.nixos.base = {
  nix.settings.substituters = cacheConfig.substituters;
  nix.settings.trusted-public-keys = cacheConfig.publicKeys;
};

flake.modules.darwin.base = {
  nix.settings.substituters = cacheConfig.substituters;
  nix.settings.trusted-public-keys = cacheConfig.publicKeys;
};
```

**Auto-merge result**: All three base modules merge into single `flake.modules.nixos.base` attribute.

#### Other system modules

- `admins.nix` - Adds admin user configuration
- `initrd-networking.nix` - Network boot configuration
- `nix-optimization.nix` - Nix store optimization

---

## Part 7: Machine-Specific Module Exports

### File: `/Users/crs58/projects/nix-workspace/test-clan/modules/machines/nixos/cinnabar/default.nix` (86 lines)

**Structure**: Exports a complete machine module to flake namespace.

```nix
flake.modules.nixos."machines/nixos/cinnabar" = 
  { config, pkgs, lib, ... }: {
    imports = with flakeModules; [
      base
      inputs.srvos.nixosModules.server
      inputs.srvos.nixosModules.hardware-hetzner-cloud
      inputs.home-manager.nixosModules.home-manager
    ];

    nixpkgs.hostPlatform = "x86_64-linux";

    # This was removed in commit 71a2758
    # Used to be: nixpkgs.config.allowUnfreePredicate = ...
    # NOW: Only nixpkgs.config.allowUnfreePredicate is used (machine-level)

    nixpkgs.overlays = [ inputs.self.overlays.default ];

    # ... rest of config ...
  };
```

**Key points**:
1. **Function signature**: Takes `config`, `pkgs`, `lib` - standard NixOS module signature
2. **Imports base**: Pulls in `flake.modules.nixos.base` (auto-merged system config)
3. **Overlays**: References `inputs.self.overlays.default` (composed from flake.nixpkgsOverlays)
4. **No perSystem context**: This module is evaluated OUTSIDE perSystem

### Why This Pattern Works (vs Why It Broke)

**OLD PATTERN** (commit 71a2758): Machine config set `nixpkgs.config.allowUnfree = true`
- This created conflict: Machine module tried to set nixpkgs config
- But clan instantiates nixpkgs OUTSIDE machine module context
- Assertion failure: "Cannot set nixpkgs.config from externally-created instance"

**NEW PATTERN** (commit 71a2758): Remove `nixpkgs.config` from machine modules
- Use `allowUnfreePredicate` instead (specific package filtering)
- Configure perSystem `allowUnfree = true` at line 21 of per-system.nix
- Overlays handle unfree packages via predicate

---

## Part 8: Complete Evaluation Flow - Cinnabar Example

### Step 1: Flake.nix Entry (global)
```
flake.nix (lines 1-6)
  ↓
import-tree discovers modules/
  ↓
Evaluates all .nix files as flake-parts modules
```

### Step 2: Module Evaluation (first pass - builds namespaces)

**Evaluation order**:

```
1. modules/checks/*.nix      (checks module system)
2. modules/clan/core.nix     (imports clan-core flakeModule)
   ↓
   Clan setup: clan.machines, clan.inventory, clanInternals
3. modules/clan/inventory/machines.nix (declares machine inventory)
4. modules/flake-parts.nix   (enables flake.modules merging)
5. modules/system/*.nix      (appends to flake.modules.nixos.base)
6. modules/machines/nixos/cinnabar/default.nix (exports cinnabar module)
7. modules/nixpkgs/overlays/*.nix (appends to flake.nixpkgsOverlays)
8. modules/nixpkgs/per-system.nix (configures perSystem pkgs)
   ↓
   Creates pkgs via: import inputs.nixpkgs {
     inherit system;
     config.allowUnfree = true;
     overlays = config.flake.nixpkgsOverlays ++ [inputs.nuenv];
   }
9. modules/clan/machines.nix (imports config.flake.modules.nixos.cinnabar)
   ↓
   Clan evaluates machine definition
```

### Step 3: Clan Machine Evaluation (for cinnabar)

```
clan.machines.cinnabar = {
  imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
}
  ↓
Clan evaluates the cinnabar machine module in NixOS context:
  - nixpkgs gets instantiated by clan for x86_64-linux
  - Machine module receives: { config, pkgs, lib, ... }
  - pkgs = clan's own nixpkgs instance (NOT perSystem pkgs)
  - Module imports:
    * flake.modules.nixos.base (system config: nix settings, caches, etc.)
    * inputs.srvos.nixosModules.server
    * inputs.srvos.nixosModules.hardware-hetzner-cloud
    * inputs.home-manager.nixosModules.home-manager
  - Configuration:
    * nixpkgs.hostPlatform = "x86_64-linux"
    * nixpkgs.overlays = [ inputs.self.overlays.default ]
    * networking.hostName = "cinnabar"
    * [other config...]
```

### Step 4: Nixpkgs Instantiation in Clan Context

```
Clan instantiates nixpkgs for x86_64-linux (internally):
  import inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [
      inputs.self.overlays.default   (← from machine module)
      # ... any other overlays clan adds ...
    ];
  }
  ↓
Evaluates overlays.default (from compose.nix):
  - Internal overlays:
    * channels.nix: multi-channel access
    * hotfixes.nix: package fixes
    * overrides.nix: build mods
    * nvim-treesitter-main.nix: treesitter versions
  - Custom packages (pkgs-by-name)
  - External overlays (nuenv)
  ↓
Returns final pkgs instance to machine module
```

### Step 5: Machine Build

```
Machine module receives final pkgs
  ↓
Evaluates all NixOS options with pkgs available
  ↓
System derivation: /nix/store/xxx-nixos-system-cinnabar-25.11...
```

---

## Part 9: Where Assertion Failures Occur

### Assertion Error: "Cannot set nixpkgs.config from externally-created instance"

**When it happens**: Machine module tries to set nixpkgs options in config, but clan already instantiated nixpkgs.

**Code that triggers it**:
```nix
# WRONG - causes assertion failure
flake.modules.nixos."machines/nixos/cinnabar" = { config, ... }: {
  nixpkgs.config.allowUnfree = true;  # ← Assertion fires here
};
```

**Why**:
1. Machine module is evaluated AFTER nixpkgs instantiation
2. Clan has already called `import inputs.nixpkgs { ... }`
3. Trying to set `nixpkgs.config` at module level fails
4. The option doesn't exist because nixpkgs was created before module evaluation

**Solution**:
```nix
# CORRECT - uses machine-specific option
flake.modules.nixos."machines/nixos/cinnabar" = { lib, ... }: {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "graphite-cli"
      "ngrok"
    ];
};
```

This works because:
- `allowUnfreePredicate` is evaluated AFTER nixpkgs instantiation
- It's a function that filters packages, not global config
- Can be applied to specific machines without global config conflict

---

## Part 10: Alternative Evaluation Paths

### Path A: perSystem Usage (successful)

**Where**: Checks, packages, devshells, custom apps
**Context**: Evaluated in `perSystem` block with proper pkgs
**Configuration**: `config.allowUnfree = true` in per-system.nix

```
perSystem = { system, ... }: {
  _module.args.pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;         ← Works here
    overlays = config.flake.nixpkgsOverlays ++ [...];
  };
  # Now all perSystem evaluations have pkgs with allowUnfree
}
```

### Path B: Clan Machine Usage (careful)

**Where**: nixos/darwin machine configurations
**Context**: Outside perSystem, independent nixpkgs instantiation
**Configuration**: Use predicates, NOT global config

```
flake.modules.nixos."machines/nixos/cinnabar" = { lib, ... }: {
  nixpkgs.overlays = [ inputs.self.overlays.default ];  ← Works
  nixpkgs.config.allowUnfreePredicate = pkg: [...];     ← Works
  nixpkgs.config.allowUnfree = true;                    ← FAILS
};
```

### Path C: Overlay Usage (flexible)

**Where**: Overlays can be applied to any nixpkgs instance
**Context**: Function-based (not config-based)
**Scope**: perSystem overlays OR clan-instantiated overlays

```
flake.overlays.default = final: prev: {
  # Can be applied anywhere
  # Works in perSystem pkgs
  # Works in clan machine pkgs
  # Works in custom pkgs instantiations
};
```

---

## Part 11: Complete File Dependency Graph

### Evaluation Order by Category

**Early (clan setup)**:
```
clan/core.nix
  ↓ imports clan-core.flakeModules.default
  ↓
clan/inventory/machines.nix
clan/meta.nix
```

**Middle (nixpkgs config)**:
```
nixpkgs/overlays-option.nix (declares flake.nixpkgsOverlays)
  ↓
nixpkgs/overlays/*.nix (appends overlay functions)
  ↓
nixpkgs/compose.nix (composes into flake.overlays.default)
  ↓
nixpkgs/per-system.nix (creates perSystem pkgs)
  ↓ references config.flake.nixpkgsOverlays
  ↓ references config.flake.overlays.default
  ↓
system/*.nix (appends to flake.modules.nixos.base)
```

**Late (machine definitions)**:
```
machines/nixos/*.nix (exports flake.modules.nixos."machines/...")
machines/darwin/*.nix (exports flake.modules.darwin."machines/...")
  ↓ reference flake.modules.nixos.base
  ↓ reference inputs.self.overlays.default
  ↓
clan/machines.nix (imports config.flake.modules.nixos.* and darwin.*)
```

### File Dependency Matrix

```
┌─────────────────────────┬──────────────────────────────┐
│ File                    │ Depends On                   │
├─────────────────────────┼──────────────────────────────┤
│ flake.nix               │ inputs.import-tree           │
│ flake-parts.nix         │ inputs.flake-parts           │
│ clan/core.nix           │ inputs.clan-core             │
│ clan/machines.nix       │ config.flake.modules.*       │
│ nixpkgs/per-system.nix  │ config.flake.nixpkgsOverlays │
│ nixpkgs/compose.nix     │ config.flake.nixpkgsOverlays │
│ machines/nixos/*.nix    │ flake.modules.nixos.base     │
│                         │ inputs.self.overlays.default │
│ system/nix-settings.nix │ flake.modules.nixos.base     │
└─────────────────────────┴──────────────────────────────┘
```

---

## Part 12: Nixpkgs Configuration Points Summary

### Point 1: perSystem Global Config (per-system.nix, line 21)
```nix
_module.args.pkgs = import inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;        ← Applies to all perSystem evaluations
  overlays = [...];
};
```

**Scope**: perSystem checks, packages, devshells  
**Works**: YES (within perSystem context)

### Point 2: Overlay Functions (overlays/*.nix)
```nix
flake.nixpkgsOverlays = [
  (final: prev: {
    # No config here, just attribute modifications
  })
];
```

**Scope**: Applied to both perSystem and clan machines  
**Works**: YES (function-based, no config)

### Point 3: Machine-Specific Predicates (machines/nixos/cinnabar/default.nix)
```nix
nixpkgs.config.allowUnfreePredicate = pkg:
  builtins.elem (lib.getName pkg) ["graphite-cli" "ngrok"];
```

**Scope**: Applied during clan machine eval  
**Works**: YES (predicate evaluation happens after nixpkgs instantiation)

### Point 4: Machine Global Config (REMOVED)
```nix
# NO LONGER USED
nixpkgs.config.allowUnfree = true;
```

**Scope**: Was applied during clan machine eval  
**Works**: NO (assertion failure)  
**Why**: Clan instantiates nixpkgs before evaluating machine module

---

## Summary: Evaluation Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         FLAKE.NIX ENTRY POINT                          │
│               import-tree ./modules (auto-discovery)                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│              FLAKE-PARTS EVAL-MODULES SYSTEM (ALL MODULES)              │
│  • Discovers all .nix files in modules/ by filesystem order            │
│  • Evaluates as flake-parts modules                                    │
│  • Merges identical namespaces (deep merge for attrs, concat for lists)│
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
        ┌───────────────────────────┴────────────────────────────┐
        ↓                                                         ↓
┌──────────────────────────────┐                    ┌────────────────────────────┐
│  FLAKE-PARTS perSystem PATH  │                    │  CLAN MACHINE PATH         │
│                              │                    │                            │
│ Per-system.nix:              │                    │ clan/core.nix imports      │
│  import inputs.nixpkgs {     │                    │ clan-core flakeModule      │
│    inherit system;           │                    │                            │
│    config.allowUnfree = true;│                    │ clan/machines.nix:         │
│    overlays = [overlays list]│                    │  imports from config.flake.│
│  }                           │                    │  modules.nixos.*           │
│                              │                    │                            │
│ Result: perSystem pkgs       │                    │ Clan evaluates each        │
│ Available for:               │                    │ machine in nixpkgs context │
│  - Checks                    │                    │ (independent instantiation)│
│  - Packages                  │                    │                            │
│  - Devshells                 │                    │ Machines use:              │
│                              │                    │  - overlays.default        │
│                              │                    │  - allowUnfreePredicate    │
│                              │                    │  - srvos, home-manager     │
└──────────────────────────────┘                    └────────────────────────────┘
        ↓                                                      ↓
    SUCCESS                                              SUCCESS
    (pkgs available)                               (system derivation)
```

---

## Key Learnings

1. **Evaluation happens in layers**: Global flake-parts eval, then perSystem, then per-machine

2. **nixpkgs config is context-specific**: 
   - Safe in perSystem (before clan)
   - NOT safe in machine modules (after clan instantiation)
   - Use predicates instead for per-machine customization

3. **Overlays are flexible**: Work in any context (perSystem or clan)

4. **Module exports via config.flake.modules.***: Enable dendritic composition but ONLY after all modules evaluate

5. **Clan orchestration happens last**: After all flake-parts modules have built the namespace

6. **The assertion error indicates**: Machine module is trying to configure nixpkgs AFTER clan already created the instance

---

## Recommended Reading Order

1. This trace (complete understanding)
2. `/Users/crs58/projects/nix-workspace/test-clan/docs/architecture/dendritic-pattern.md` (pattern explanation)
3. `/Users/crs58/projects/nix-workspace/test-clan/flake.nix` (entry point)
4. `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/machines.nix` (clan integration)
5. `/Users/crs58/projects/nix-workspace/test-clan/modules/machines/nixos/cinnabar/default.nix` (example machine)

