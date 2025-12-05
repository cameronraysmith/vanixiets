---
title: "ADR-0003: Overlay Composition Patterns"
---

**Status**: Superseded by [ADR-0017: Dendritic Overlay Patterns](0017-dendritic-overlay-patterns/)

**Historical Context**: This ADR documents nixos-unified overlay patterns used prior to November 2024 migration to dendritic flake-parts + clan architecture.

## Summary

Based on exploration of `nix-config` and `mirkolenz-nixos`, overlay organization follows consistent patterns that must be retained when integrating with nixos-unified.

## Key Findings

### 1. nixos-unified Auto-wiring of Overlays

nixos-unified's `autoWire` module automatically creates `flake.overlays` by scanning `${self}/overlays` directory:

**File**: `~/projects/nix-workspace/nixos-unified/nix/modules/flake-parts/autowire.nix` (lines 54-56)

```nix
overlays =
  forAllNixFiles "${self}/overlays"
    (fn: import fn self.nixos-unified.lib.specialArgsFor.common);
```

**Pattern**:
- Scans `overlays/` directory for `.nix` files and `*/default.nix` directories
- Imports each as an overlay module with special args: `{ flake, ... }`
- Creates `flake.overlays.<name>` for each file/directory

**Impact**: The `infra/` subdirectory in overlays is INTENTIONAL to avoid nixos-unified autowiring conflicts (Phase 1 architecture)

---

## nix-config Overlay Structure

### Directory Layout

```
overlays/
├── default.nix          # Main composition (Phase 1 infrastructure only)
├── inputs.nix           # Multi-channel nixpkgs access (inputs, patched, stable, unstable)
├── infra/              # Phase 1: Infrastructure NOT auto-wired
│   ├── patches.nix      # List of nixpkgs patches to apply (empty in Phase 1)
│   └── hotfixes.nix     # Platform-specific stable fallbacks for broken packages
├── overrides/          # Per-package build modifications (auto-imported)
│   └── default.nix      # Auto-imports *.nix files, merges them
├── packages/           # Custom derivations (auto-imported by lib.packagesFromDirectoryRecursive)
│   ├── starship-jj.nix          # Single-file package derivation
│   ├── cc-statusline-rs.nix     # Single-file package derivation
│   ├── markdown-tree-parser.nix # Single-file package derivation
│   └── atuin-format/            # Multi-file package (directory with package.nix)
│       └── package.nix
│       └── atuin-format.nu
├── debug-packages/     # Experimental packages (NOT in overlay, in legacyPackages)
│   ├── conda-lock.nix
│   ├── holos.nix
│   └── quarto.nix
```

### Main Overlay Composition (default.nix)

**Architecture** (lines 1-12 comments define structure):
1. `inputs` - Multi-channel nixpkgs access (stable, patched, etc.)
2. `hotfixes` - Platform-specific stable fallbacks for broken packages
3. `packages` - Custom derivations
4. `overrides` - Per-package build modifications
5. `flakeInputs` - Overlays from flake inputs (nuenv, etc.)

**Merge Order Matters**: Later layers can reference earlier layers

**Implementation** (lines 28-42):
```nix
# Import layers with lib.packagesFromDirectoryRecursive for packages
fromDirectory =
  directory:
  lib.packagesFromDirectoryRecursive {
    callPackage = lib.callPackageWith self;
    inherit directory;
  };

packages = fromDirectory ./packages;

# Import overlay layers
inputs' = import ./inputs.nix overlayArgs self super;
hotfixes = import ./infra/hotfixes.nix self super;
overrides = import ./overrides overlayArgs self super;
```

---

## Pattern 1: Multi-Channel Nixpkgs (inputs.nix)

**File**: `~/projects/nix-workspace/nix-config/overlays/inputs.nix`

**Purpose**: Provide stable fallback and multiple nixpkgs channels

**Implementation**:
```nix
{ flake, ... }:
final: prev:
let
  inherit (prev) lib;
  inherit (flake) inputs;
  lib' = inputs.self.lib;  # Access lib through inputs.self
  os = lib'.systemOs system;
  nixpkgsConfig = { inherit system; config = { allowUnfree = true; }; };
in
{
  inherit inputs;
  nixpkgs = import inputs.nixpkgs nixpkgsConfig;
  patched = import (prev.applyPatches { 
    name = "nixpkgs-patched"; 
    src = inputs.nixpkgs.outPath; 
    patches = map prev.fetchpatch (import ./infra/patches.nix); 
  }) nixpkgsConfig;
  stable = import (lib'.systemInput { 
    inherit os; 
    name = "nixpkgs"; 
    channel = "stable"; 
  }) nixpkgsConfig;
  unstable = import inputs.nixpkgs nixpkgsConfig;
}
```

**Key Points**:
- Exposes: `inputs`, `nixpkgs`, `patched`, `stable`, `unstable`
- Uses `lib.systemOs system` to select OS-specific stable input
- Uses `lib.systemInput` to select channel based on OS (darwin-stable vs linux-stable)
- Access to `lib` via `inputs.self.lib` (nixos-unified doesn't include lib in specialArgsFor.common)

---

## Pattern 2: Platform-Specific Hotfixes (hotfixes.nix)

**File**: `~/projects/nix-workspace/nix-config/overlays/infra/hotfixes.nix`

**Purpose**: Selectively use stable versions when unstable breaks

**Implementation**:
```nix
final: prev:
{
  # Cross-platform hotfixes
  inherit (final.stable)
    # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.aarch64-darwin
    micromamba  # fmt library compatibility issue across all platforms
    ;
}
// (prev.lib.optionalAttrs prev.stdenv.isDarwin { ... })
// (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "x86_64-darwin") { ... })
// (prev.lib.optionalAttrs prev.stdenv.isLinux { ... })
```

**Key Points**:
- Uses `final.stable.packageName` for stable fallback
- Documents with hydra link for each hotfix
- Platform conditionals: `isDarwin`, `isLinux`, specific system checks
- Prevents flake.lock rollbacks affecting all packages

---

## Pattern 3: Packages (Single and Multi-file)

### Single-file Packages

**Example**: `starship-jj.nix`
```nix
{ lib, rustPlatform, fetchCrate, ... }:
let
  pname = "starship-jj";
  version = "0.5.1";
in
rustPlatform.buildRustPackage { ... }
```

**Import Pattern**: 
- File name without `.nix` becomes package name
- `lib.packagesFromDirectoryRecursive` auto-imports with callPackage

### Multi-file Packages (Directory)

**Example**: `atuin-format/package.nix`
```nix
{ nuenv, atuin, ... }:
nuenv.writeShellApplication {
  name = "atuin-format";
  runtimeInputs = [ atuin ];
  text = ''...${builtins.readFile ./atuin-format.nu}'';
}
```

**Pattern**:
- Directory name becomes package name
- Must have `package.nix` as entry point
- Can reference sibling files: `builtins.readFile ./atuin-format.nu`
- Other files in directory (e.g., `.nu`, `.json`) are accessible

---

## Pattern 4: Overrides (Auto-imported)

**File**: `~/projects/nix-workspace/nix-config/overlays/overrides/default.nix`

**Purpose**: Per-package build modifications (overrideAttrs, test disabling, etc.)

**Implementation**:
```nix
{ flake, ... }:
final: prev:
let
  filterPath = name: type:
    !lib.hasPrefix "_" name && type == "regular" && 
    lib.hasSuffix ".nix" name && name != "default.nix";
  
  dirContents = builtins.readDir ./.;
  filteredContents = lib.filterAttrs filterPath dirContents;
  overlayFiles = builtins.attrNames filteredContents;
  
  importedOverlays = builtins.foldl' (
    acc: name:
    let
      overlay = import (./. + "/${name}") final prev;
    in
    acc // overlay
  ) { } overlayFiles;
in
importedOverlays
```

**Key Points**:
- Auto-imports all `*.nix` except `default.nix` and `_*.nix` (underscore = disabled)
- Each file: `final: prev: { ... }`
- Merges all returned attributes
- Useful for: overrideAttrs, test disabling, build flags, patches

---

## mirkolenz-nixos Overlay Structure

### Directory Layout

```
pkgs/
├── default.nix          # Main composition
├── inputs.nix           # Multi-channel nixpkgs + external packages
├── hotfixes.nix         # Platform-specific stable fallbacks
├── patches.nix          # List of patches (empty)
├── overrides/           # Per-package modifications
│   ├── caddyWithPlugins.nix
│   ├── nixos-rebuild-ng.nix
│   ├── pdfpc.nix
│   ├── sambaTimeMachine.nix
│   └── virt-manager.nix
└── derivations/         # Custom packages (auto-imported)
    ├── empty.nix
    ├── gibo.nix
    ├── bibtexbrowser.nix
    ├── bun-apps.nix
    ├── caddy-docker.nix
    ├── builder/
    ├── copilot-cli/
    └── ... (30+ more packages)
```

### Registration Pattern (flake-modules/default.nix)

```nix
flake = {
  lib = lib';
  overlays.default = import ../pkgs self.overlayArgs;  # Single overlay
  nixpkgsConfig = { allowUnfree = true; ... };
  overlayArgs = { inherit self inputs lib' ; };
};

perSystem = { pkgs, ... }: {
  _module.args.pkgs = import inputs.nixpkgs {
    inherit system;
    config = self.nixpkgsConfig;
    overlays = [ self.overlays.default ];  # Used in perSystem
  };
};
```

### Composition (pkgs/default.nix)

```nix
args@{ lib', ... }:
final: prev:
let
  current = lib.packagesFromDirectoryRecursive {
    inherit (final) callPackage;
    directory = ./derivations;  # Auto-import all packages
  };
  
  overrides = lib'.importOverlays ./overrides final prev;  # Auto-import overrides
  
in
lib.mergeAttrsList [
  (args.inputs.nix-darwin.overlays.default final prev)
  (import ./inputs.nix args final prev)
  (import ./hotfixes.nix final prev)
  pkgs
  overrides
  { drvsExport = drvs // flatScopeDrvs // overrides; }
]
```

### Key Difference from nix-config

**mirkolenz-nixos** (flocken-based):
- Single `overlays.default` exposed to flake
- Uses `lib'.importOverlays` helper function from flocken
- Supports scoped packages (e.g., `vimPlugins.*`)
- Exports `drvsExport` and `drvsUpdate` for CI

**nix-config** (nixos-unified-based):
- Multiple named overlays (one per file/directory in `overlays/`)
- Uses `lib.packagesFromDirectoryRecursive` for packages
- Cleaner separation: one overlay per concerns (inputs, hotfixes, packages, overrides)

---

## Import Patterns

### 1. Package Import Pattern (used by both)

```nix
lib.packagesFromDirectoryRecursive {
  callPackage = lib.callPackageWith self;  # or lib.callPackageWith pkgs
  directory = ./packages;
};
```

**Result**: Discovers `.nix` files and directories with `default.nix`, imports as packages

### 2. Overlay Argument Pattern

**nix-config** (nixos-unified):
```nix
import ./overlays/inputs.nix overlayArgs self super
# where overlayArgs = { inherit flake; }
# and overlay signature: { flake, ... }: final: prev: { ... }
```

**mirkolenz-nixos** (flocken):
```nix
import ../pkgs self.overlayArgs
# where overlayArgs = { inherit self inputs lib'; }
# and overlay signature: { self, inputs, lib', ... }: final: prev: { ... }
```

**nixos-unified autoWire**:
```nix
import fn self.nixos-unified.lib.specialArgsFor.common
# where fn is path to overlay file
# and overlay signature: { ... }: final: prev: { ... }
# specialArgsFor.common includes: flake, inputs (but NOT lib directly)
```

### 3. Manual Overlay Merging

```nix
lib.mergeAttrsList [
  inputs'        # Multi-channel nixpkgs access
  hotfixes       # Platform-specific stable fallbacks
  packages       # Custom derivations
  overrides      # Per-package build modifications
  flakeInputs    # Overlays from flake inputs
]
```

---

## nixos-unified Integration Conventions

### Phase 1 Architecture (Current - nix-config)

**Design Decision**: Infrastructure files (`inputs.nix`, `hotfixes.nix`) placed in `overlays/infra/` subdirectory to avoid nixos-unified autowiring conflicts.

**Reason**: 
- nixos-unified autoWires all `.nix` files in `overlays/` as separate named overlays
- Infrastructure overlays are internal composition details, not meant as independent overlays
- Subdirectory prevents accidental autowiring of infrastructure layers

**Result**:
- `flake.overlays` only contains: `packages/*`, `overrides/*`, `debug-packages/*` (no infrastructure)
- Main composition in `overlays/default.nix` manually imports and merges all layers
- `perSystem` references `self.overlays` which is composed internally

### Merge Process in nix-config

```nix
# overlays/default.nix
self: super:
let
  fromDirectory = ...;
  packages = fromDirectory ./packages;
  
  inputs' = import ./inputs.nix overlayArgs self super;
  hotfixes = import ./infra/hotfixes.nix self super;
  overrides = import ./overrides overlayArgs self super;
  flakeInputs = { nuenv = ...; };
in
lib.mergeAttrsList [
  inputs'
  hotfixes
  packages
  overrides
  flakeInputs
]
```

### perSystem Usage

```nix
# flake.nix perSystem block
perSystem = { lib, system, ... }: {
  _module.args.pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = lib.attrValues self.overlays ++ [ inputs.lazyvim.overlays.nvim-treesitter-main ];
    config.allowUnfree = true;
  };
};
```

**Note**: `lib.attrValues self.overlays` collects all autowired overlays and applies them together

---

## Patterns to Retain

### 1. Infrastructure in `overlays/infra/`

Keep infrastructure files in subdirectory to avoid autowiring:
- `overlays/infra/patches.nix`
- `overlays/infra/hotfixes.nix`

### 2. Multi-Layer Overlay Composition

Maintain separation of concerns:
- **inputs**: Multi-channel nixpkgs access
- **hotfixes**: Platform-specific fallbacks
- **packages**: Custom derivations
- **overrides**: Per-package modifications
- **flakeInputs**: External overlay integration

### 3. Package Directory Patterns

Support both import styles:
- Single-file packages: `packages/packageName.nix`
- Multi-file packages: `packages/packageName/package.nix` + supporting files

### 4. Auto-import with Filtering

Filter patterns used in overrides:
```nix
!lib.hasPrefix "_" name          # Skip _filename.nix (underscore = disabled)
type == "regular"                 # Only .nix files
lib.hasSuffix ".nix" name        # Ensure .nix extension
name != "default.nix"            # Skip default.nix itself
```

### 5. Platform-Specific Overlays

Use lib functions for platform conditionals:
- `prev.lib.optionalAttrs prev.stdenv.isDarwin { ... }`
- `prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "x86_64-darwin") { ... }`
- `prev.lib.optionalAttrs prev.stdenv.isLinux { ... }`

### 6. hotfixes Pattern

Keep commented hydra links for each hotfix:
```nix
inherit (final.stable)
  # https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.SYSTEM
  packageName
  ;
```

---

## nixos-unified Special Args

### Available in Overlay Context

When nixos-unified autowires overlays via:
```nix
import fn self.nixos-unified.lib.specialArgsFor.common
```

Available special args:
- `flake` - The self flake
- `inputs` - All flake inputs
- **NOT included**: `lib` (workaround: use `inputs.self.lib`)

### Custom Args Pattern

To pass additional context beyond specialArgsFor.common, create overlay with pattern:
```nix
{ flake, ... }: final: prev: { ... }
```

The `...` captures any additional arguments from import context.

---

## Summary of Key Differences

| Aspect | nix-config | mirkolenz-nixos |
|--------|-----------|-----------------|
| Framework | nixos-unified | flocken |
| Overlay Count | Multiple (auto-wired) | Single default |
| Package Directory | `overlays/packages/` | `pkgs/derivations/` |
| Override Directory | `overlays/overrides/` | `pkgs/overrides/` |
| Infrastructure | `overlays/infra/` | `pkgs/inputs.nix` + `hotfixes.nix` |
| Main Composition | `overlays/default.nix` | `pkgs/default.nix` |
| Lib Access | Via `inputs.self.lib` | Via `lib'` in args |
| Override Filter | `_*.nix` disabled files | Same pattern |
| Package Scopes | Flat structure | Supports scoped (vimPlugins, etc.) |
