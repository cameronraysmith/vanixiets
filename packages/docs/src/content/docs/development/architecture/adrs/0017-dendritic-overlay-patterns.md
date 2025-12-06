---
title: "ADR-0017: Dendritic Overlay Patterns"
---

- **Status**: Accepted
- **Date**: 2024-12-02
- **Scope**: Nix configuration
- **Supersedes**: [ADR-0003: Overlay composition patterns](0003-overlay-composition-patterns/)

## Context

The migration from nixos-unified to dendritic flake-parts + clan architecture (November 2024) required restructuring overlay organization to align with dendritic module patterns and eliminate nixos-unified-specific conventions.

### Key architectural changes

**Framework transition**:
- nixos-unified's `autoWire` mechanism eliminated (no specialArgs pattern)
- Dendritic flake-parts list concatenation pattern adopted
- Overlay location moved from `overlays/` to `modules/nixpkgs/overlays/`
- pkgs-by-name pattern adopted for custom packages (following nixpkgs RFC 140)

**Organizational shift**:
- From file-based autowiring to explicit list concatenation
- From hidden `overlays/infra/` subdirectory to structured `modules/nixpkgs/overlays/`
- From single `overlays/default.nix` composition to dendritic `compose.nix`
- From implicit module discovery to explicit `flake.nixpkgsOverlays` list

## Decision

Adopt five-layer overlay architecture using dendritic flake-parts list concatenation pattern.

### Layer 1: Multi-Channel Nixpkgs Access (channels overlay)

**Location**: `modules/nixpkgs/overlays/channels.nix`

**Purpose**: Provide access to multiple nixpkgs channels for surgical package fixes without system-wide flake.lock rollback.

**Exports**:
- `inputs` - Raw flake inputs reference
- `nixpkgs` - Main nixpkgs (unstable) for reference
- `patched` - nixpkgs with patches applied (uses applyPatches)
- `stable` - OS-specific stable nixpkgs (darwin-stable or linux-stable)
- `unstable` - Explicit unstable nixpkgs (same as nixpkgs, for clarity)

**Implementation pattern**:
```nix
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev:
      let
        nixpkgsConfig = {
          system = prev.stdenv.hostPlatform.system;
          config = { allowUnfree = true; };
        };
      in
      {
        inherit inputs;
        nixpkgs = import inputs.nixpkgs nixpkgsConfig;
        patched = import (prev.applyPatches {
          name = "nixpkgs-patched";
          src = inputs.nixpkgs.outPath;
          patches = []; # Empty in infra currently
        }) nixpkgsConfig;
        stable = if prev.stdenv.isDarwin
          then import inputs.nixpkgs-darwin-stable nixpkgsConfig
          else import inputs.nixpkgs-linux-stable nixpkgsConfig;
        unstable = import inputs.nixpkgs nixpkgsConfig;
      }
    )
  ];
}
```

### Layer 2: Platform-Specific Hotfixes

**Location**: `modules/nixpkgs/overlays/hotfixes.nix`

**Purpose**: Selectively use stable versions when unstable packages break, avoiding flake.lock rollbacks that affect all packages.

**Pattern**:
```nix
{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      # Cross-platform hotfixes
      inherit (final.stable)
        # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.aarch64-darwin
        micromamba  # fmt library compatibility issue
        ;
    }
    // (prev.lib.optionalAttrs prev.stdenv.isDarwin { ... })
    // (prev.lib.optionalAttrs prev.stdenv.isLinux { ... })
    )
  ];
}
```

**Key properties**:
- Uses `final.stable.packageName` for stable fallback
- Documents each hotfix with hydra link
- Platform conditionals: `isDarwin`, `isLinux`, specific system checks
- Remove when upstream fixes land in unstable

### Layer 3: Custom Packages (pkgs-by-name)

**Location**: `pkgs/by-name/<package>/package.nix`

**Pattern**: drupol flat structure (NOT nested like nixpkgs)
- `pkgs/by-name/starship-jj/package.nix` (correct)
- NOT `pkgs/by-name/st/starship-jj/package.nix` (nixpkgs nesting)

**Auto-discovery**: `pkgs-by-name-for-flake-parts.flakeModule` provides `perSystem.packages` from directory structure.

**Current packages**:
- `atuin-format/` - Multi-file package (package.nix + atuin-format.nu)
- `markdown-tree-parser/` - Single-file python package
- `starship-jj/` - Single-file rust package

Note: ccstatusline was previously a custom package but is now sourced from the llm-agents flake input.

**Integration**: Custom packages exported via `withSystem` in `compose.nix`:
```nix
customPackages = withSystem prev.stdenv.hostPlatform.system (
  { config, ... }: config.packages or {}
);
```

### Layer 4: Per-Package Overrides

**Location**: `modules/nixpkgs/overlays/overrides.nix`

**Purpose**: Build modifications (overrideAttrs, test disabling, patches).

**Pattern**:
```nix
{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      # Package-specific overrideAttrs customizations
      # Example:
      # somePackage = prev.somePackage.overrideAttrs (oldAttrs: {
      #   doCheck = false;  # Disable tests
      # });
    })
  ];
}
```

**Current state**: Placeholder for future modifications (no overrides yet in infra).

### Layer 5: External Flake Overlays

**Location**: `modules/nixpkgs/compose.nix`

**Purpose**: Integrate overlays from external flake inputs.

**Pattern**:
```nix
# External flake overlays
nuenvOverlay = inputs.nuenv.overlays.nuenv;

# Composed in final overlay
(nuenvOverlay final prev)
```

**Current external overlays**:
- `nuenv` - Nushell script packaging (from inputs.nuenv.overlays.nuenv)

### Dendritic List Concatenation Pattern

**Option declaration** (`modules/nixpkgs/overlays-option.nix`):
```nix
{ lib, flake-parts-lib, ... }:
{
  options = {
    flake = mkSubmoduleOptions {
      nixpkgsOverlays = mkOption {
        type = types.listOf types.unspecified;
        default = [];
        description = ''
          List of nixpkgs overlays to be composed together.
          Multiple modules can append to this list.
        '';
      };
    };
  };
}
```

**List concatenation** (each overlay module):
```nix
{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: { ... })
  ];
}
```

**Composition** (`modules/nixpkgs/compose.nix`):
```nix
{
  flake.overlays.default = final: prev:
    let
      internalOverlays = lib.composeManyExtensions config.flake.nixpkgsOverlays;
      nuenvOverlay = inputs.nuenv.overlays.nuenv;
      customPackages = withSystem prev.stdenv.hostPlatform.system (
        { config, ... }: config.packages or {}
      );
    in
    (internalOverlays final prev) // customPackages // (nuenvOverlay final prev);
}
```

## Consequences

### Positive

**Clear separation of concerns**:
- Layer 1 (channels): Multi-channel access
- Layer 2 (hotfixes): Platform-specific fixes
- Layer 3 (pkgs-by-name): Custom packages
- Layer 4 (overrides): Build modifications
- Layer 5 (external): Flake input overlays

**Follows nixpkgs patterns**:
- pkgs-by-name matches nixpkgs RFC 140
- Overlay composition uses standard `lib.composeManyExtensions`
- Platform conditionals use nixpkgs stdlib (`stdenv.isDarwin`, etc.)

**Dendritic architecture benefits**:
- List concatenation enables module composition
- No hidden `overlays/infra/` subdirectory (explicit structure)
- Each overlay in `modules/nixpkgs/overlays/*.nix` appends to list
- Clear composition order in `compose.nix`

**Surgical package fixes remain functional**:
- Layer 1-2 enable stable fallbacks without flake.lock rollback
- Hydra links document why each hotfix exists
- Platform-specific conditionals isolate fixes to affected systems

**Custom packages organized predictably**:
- Flat `pkgs/by-name/<package>/` structure
- Auto-discovery via `pkgs-by-name-for-flake-parts`
- Supports both single-file and multi-file packages

**External overlays cleanly integrated**:
- Explicit composition in `compose.nix`
- Clear separation from internal overlays
- Easy to add/remove external dependencies

### Negative

**Path migration required**:
- Old: `overlays/` → New: `modules/nixpkgs/overlays/`
- Old: `overlays/infra/` → New: `modules/nixpkgs/overlays/`
- Old: `overlays/packages/` → New: `pkgs/by-name/`
- Requires updating documentation and references

**Dendritic conventions add complexity**:
- Underscore prefix for non-module directories (e.g., `_overlays/` if needed)
- Explicit `flake.nixpkgsOverlays` list management
- List concatenation pattern not immediately obvious

**Composition order must be understood**:
- Internal overlays → custom packages → external overlays
- Order matters (later layers can reference earlier layers)
- Not enforced by type system (runtime composition)

### Neutral

**mirkolenz-nixos reference patterns remain valid**:
- Layer 3-4 patterns similar (custom packages, overrides)
- Different composition mechanism (dendritic vs flocken)
- Same underlying concepts

**Multi-channel resilience preserved**:
- ADR principles from nixpkgs-hotfixes still apply
- Stable fallback mechanism unchanged
- Platform-specific fixes still functional

**pkgs-by-name simplification**:
- Drupol flat structure (no nested categories)
- Simpler than nixpkgs nested structure
- Trade-off: less organization for large package sets

## Directory Structure

```
modules/nixpkgs/
├── default.nix          # Main integration, imports submodules
├── overlays-option.nix  # Declares flake.nixpkgsOverlays list option
├── per-system.nix       # Configures perSystem pkgs
├── compose.nix          # Composes overlays into flake.overlays.default
└── overlays/
    ├── channels.nix     # Layer 1: Multi-channel access
    ├── hotfixes.nix     # Layer 2: Platform fixes
    ├── overrides.nix    # Layer 4: Build modifications
    ├── nvim-treesitter-main.nix  # Special overlay
    └── fish-stable-darwin.nix    # Special overlay

pkgs/
└── by-name/             # Layer 3: Custom packages
    ├── atuin-format/
    │   ├── package.nix
    │   └── atuin-format.nu
    ├── markdown-tree-parser/
    │   └── package.nix
    └── starship-jj/
        └── package.nix
```

## Usage in Machine Configurations

Machine configurations reference the composed overlay:

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.self.overlays.default ];
}
```

This single overlay includes all five layers in correct composition order.

## Migration from nixos-unified Pattern

### Before (nixos-unified with ADR-0003)

```
overlays/
├── default.nix          # Manual composition
├── inputs.nix           # Multi-channel access
├── infra/              # Hidden from autowiring
│   ├── patches.nix
│   └── hotfixes.nix
├── packages/           # Custom derivations
│   ├── starship-jj.nix
│   └── atuin-format/
│       └── package.nix
└── overrides/          # Auto-imported overrides
    └── default.nix

# Usage
perSystem = { lib, ... }: {
  _module.args.pkgs = import inputs.nixpkgs {
    overlays = lib.attrValues self.overlays;
  };
};
```

### After (dendritic flake-parts with ADR-0017)

```
modules/nixpkgs/
├── default.nix          # Integration (imports submodules)
├── overlays-option.nix  # List option declaration
├── compose.nix          # Dendritic composition
└── overlays/
    ├── channels.nix     # Multi-channel access
    ├── hotfixes.nix     # Platform fixes
    └── overrides.nix    # Build modifications

pkgs/by-name/           # Custom packages
├── starship-jj/
│   └── package.nix
└── atuin-format/
    ├── package.nix
    └── atuin-format.nu

# Usage
nixpkgs.overlays = [ inputs.self.overlays.default ];
```

## References

### Internal

- [ADR-0003: Overlay composition patterns](0003-overlay-composition-patterns/) (superseded)
- test-clan validation: `~/projects/nix-workspace/test-clan/`
- Drupol dendritic reference: `~/projects/nix-workspace/drupol-dendritic-infra/`
- mirkolenz-nixos reference: `~/projects/nix-workspace/mirkolenz-nixos/`

### External

- [nixpkgs RFC 140 (pkgs-by-name)](https://github.com/NixOS/rfcs/pull/140)
- [pkgs-by-name-for-flake-parts](https://github.com/drupol/pkgs-by-name-for-flake-parts)
- [dendritic flake-parts pattern](https://github.com/drupol/dendritic)

### Migration Evidence

- November 2024 migration: nixos-unified → dendritic + clan
- test-clan validation: Architecture validated
- Current implementation: `modules/nixpkgs/` in infra repository
