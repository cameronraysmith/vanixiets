---
title: Nixpkgs fixes
---

Multi-channel nixpkgs resilience system for handling unstable breakage without full rollbacks.

Implemented: 2025-10-13 (Phases 1-3)

## Overview

This infrastructure provides:
- **Multi-channel nixpkgs access**: unstable (default), stable, patched
- **Platform-specific hotfixes**: Selective stable fallbacks for broken packages
- **Upstream patch application**: Apply fixes before they reach your channel
- **Organized per-package overrides**: Build modifications separate from hotfixes
- **Composable architecture**: Five-layer overlay composition for flexibility

## Architecture

### Directory structure

```
overlays/
├── default.nix          # Main composition layer (merges all below)
├── inputs.nix           # Multi-channel nixpkgs access
├── infra/               # Infrastructure files (excluded from autowiring)
│   ├── patches.nix      # Upstream patch list (applied to create patched)
│   └── hotfixes.nix     # Platform-specific stable fallbacks
├── overrides/           # Per-package build modifications
│   ├── default.nix      # Auto-importer (inlined to avoid recursion)
│   ├── README.md        # When to use overrides vs hotfixes vs patches
│   └── *.nix            # Individual package overrides
├── packages/            # Custom derivations
└── debug-packages/      # Experimental packages (not in overlay, see legacyPackages.debug)
```

### Composition layers (in order)

```nix
lib.mergeAttrsList [
  inputs'        # 1. Multi-channel nixpkgs access (stable, unstable, patched)
  hotfixes       # 2. Platform-specific stable fallbacks
  packages       # 3. Custom derivations from packages/
  overrides      # 4. Per-package build modifications
  flakeInputs    # 5. Overlays from flake inputs (nuenv, etc.)
]
```

Order matters: Later layers can reference packages from earlier layers.

Note: Debug/experimental packages are in `legacyPackages.debug` (not overlay) to prevent automatic builds and nixpkgs overrides. See `modules/flake-parts/debug-packages.nix`.

## Component purposes

### 1. inputs.nix - Multi-channel access

Provides multiple nixpkgs variants via overlay:

```nix
pkgs.nixpkgs    # Main unstable (explicit reference)
pkgs.stable     # OS-specific stable (darwin-stable or linux-stable)
pkgs.unstable   # Explicit unstable (same as default)
pkgs.patched    # Unstable with infra/patches.nix applied
```

Example usage:
```nix
# In any nix expression with pkgs
myPackage = pkgs.stable.somePackage;  # Get from stable channel
```

Implementation: Uses flake.lib.systemInput to select OS-specific stable channel.

### 2. infra/hotfixes.nix - Stable fallbacks

Platform-conditional stable fallbacks for completely broken unstable packages.

Structure:
```nix
final: prev:
{
  # Cross-platform hotfixes
}
// (prev.lib.optionalAttrs prev.stdenv.isDarwin {
  # Darwin-wide hotfixes (both aarch64 and x86_64)
  inherit (final.stable) packageX;
})
// (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "x86_64-darwin") {
  # x86_64-darwin specific
})
// (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "aarch64-darwin") {
  # aarch64-darwin specific
})
// (prev.lib.optionalAttrs prev.stdenv.isLinux {
  # Linux-wide hotfixes
})
```

Pattern:
```nix
inherit (final.stable)
  # https://hydra.nixos.org/job/nixpkgs/trunk/packageX.aarch64-darwin
  # Broken in unstable due to [reason]
  # TODO: Remove when [condition]
  packageX
  ;
```

Location: overlays/infra/ (not overlays/) to avoid nixos-unified autowiring conflicts.

### 3. infra/patches.nix - Upstream patches

List of upstream patches to apply to nixpkgs:

Format:
```nix
[
  {
    url = "https://github.com/NixOS/nixpkgs/pull/123456.patch";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  }
]
```

Applied via: prev.applyPatches in inputs.nix to create pkgs.patched

Use when: Upstream fix exists but hasn't reached your channel

### 4. overrides/ - Build modifications

Per-package build modifications organized in dedicated files.

Example file (overrides/packageX.nix):
```nix
# packageX: brief description
#
# Issue: Detailed description
# Reference: Upstream issue link
# TODO: Remove when condition
# Date added: YYYY-MM-DD
#
final: prev: {
  packageX = prev.packageX.overrideAttrs (old: {
    doCheck = false;
  });
}
```

Auto-import: overrides/default.nix imports all *.nix files (inlined to avoid recursion with lib.importOverlays)

Current overrides:
- ghc_filesystem.nix: Disables tests due to clang 21.x on darwin

### 5. flakeInputs - Input overlays

Overlays from flake inputs (nuenv, lazyvim, etc.)

```nix
flakeInputs = {
  nuenv = (inputs.nuenv.overlays.nuenv self super).nuenv;
  # nvim-treesitter from LazyVim-module (applied in flake.nix)
};
```

## Usage patterns

### Decision tree: When unstable breaks

```
Package broken after nixpkgs update?
│
├─ Multiple packages affected?
│  └─ Consider flake.lock rollback, then selective hotfixes
│
├─ Upstream fix exists in PR?
│  └─ Use infra/patches.nix (Strategy: Upstream patch)
│
├─ Package completely broken?
│  └─ Use infra/hotfixes.nix (Strategy: Stable fallback)
│
└─ Package builds but has issues (tests fail, etc.)?
   └─ Use overrides/*.nix (Strategy: Build modification)
```

### Strategy 1: Stable fallback (hotfixes.nix)

When: Package completely broken in unstable, no upstream fix yet

Action: Edit overlays/infra/hotfixes.nix:

```nix
// (prev.lib.optionalAttrs prev.stdenv.isDarwin {
  inherit (final.stable)
    # https://hydra.nixos.org/job/nixpkgs/trunk/packageX.aarch64-darwin
    # Broken in unstable due to llvm 21.x issue
    # TODO: Remove when upstream fixes land
    packageX
    ;
})
```

Test:
```bash
nix eval .#legacyPackages.$(nix eval --raw .#currentSystem).packageX.name
# Should show stable version
```

Removal: When upstream fixes land:
```bash
# Remove from hotfixes.nix
git commit -m "fix(overlays): remove packageX hotfix after upstream fix"
```

### Strategy 2: Upstream patch (patches.nix)

When: Upstream PR exists with fix, not yet in channel

Action: Edit overlays/infra/patches.nix:

```nix
[
  {
    url = "https://github.com/NixOS/nixpkgs/pull/123456.patch";
    hash = "";  # Leave empty initially
  }
]
```

Get hash:
```bash
nix build .#legacyPackages.$(nix eval --raw .#currentSystem).patched.hello 2>&1 | grep "got:"
# Copy the sha256 hash and update patches.nix
```

Reference patched package:
```nix
# In hotfixes.nix or elsewhere:
inherit (final.patched) packageX;
```

Removal: When patch merges:
```bash
# Remove from patches.nix
git commit -m "fix(overlays): remove nixpkgs#123456 patch (merged upstream)"
```

### Strategy 3: Build modification (overrides/*)

When: Package builds but tests fail, needs flags, etc.

Action: Create overlays/overrides/packageX.nix:

```nix
# packageX: tests fail with clang 21.x
#
# Issue: -Werror hits new warnings
# Reference: https://github.com/upstream/packageX/issues/789
# TODO: Remove when upstream fixes tests
# Date added: 2025-10-13
#
final: prev: {
  packageX = prev.packageX.overrideAttrs (old: {
    doCheck = false;
  });
}
```

No restart needed: Auto-imported by overrides/default.nix

Test:
```bash
nix build .#legacyPackages.$(nix eval --raw .#currentSystem).packageX
```

Removal: When upstream fixes build issues:
```bash
rm overlays/overrides/packageX.nix
git commit -m "fix(overlays): remove packageX override after upstream fix"
```

## Examples

### Example 1: llvm 21.x compatibility issue

Scenario: Package fails to compile with llvm 21.x in unstable

Solution: Stable fallback (llvm 19.x from stable)

```nix
# overlays/infra/hotfixes.nix
// (prev.lib.optionalAttrs prev.stdenv.isDarwin {
  inherit (final.stable)
    # https://hydra.nixos.org/job/nixpkgs/trunk/buf.aarch64-darwin
    # Compilation fails with llvm 21.x
    # Uses llvm 19.x from stable
    # TODO: Remove when llvm 21.x compatibility fixed
    buf
    ;
})
```

### Example 2: Test failure on darwin

Scenario: Tests fail with clang 21.x on darwin only

Solution: Build modification (disable tests)

```nix
# overlays/overrides/somePackage.nix
final: prev: {
  somePackage = prev.somePackage.overrideAttrs (old: {
    doCheck = false;
    meta = (old.meta or {}) // {
      broken = false;  # If it was marked broken
    };
  });
}
```

Real example: overlays/overrides/ghc_filesystem.nix (currently active)

### Example 3: Applying upstream patch

Scenario: Upstream fix in PR, not yet in channel

Solution: Apply patch, reference patched version

```nix
# overlays/infra/patches.nix
[
  {
    url = "https://github.com/NixOS/nixpkgs/pull/123456.patch";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  }
]
```

Then reference in hotfixes:
```nix
# overlays/infra/hotfixes.nix
{
  inherit (final.patched)
    packageX  # Uses patched version with PR applied
    ;
}
```

## Integration with nixos-unified

This infrastructure respects nixos-unified's autowiring:

From inputs.nixos-unified.flakeModules.autoWire:
```nix
overlays =
  forAllNixFiles "${self}/overlays"
    (fn: import fn self.nixos-unified.lib.specialArgsFor.common);
```

Exports:
- overlays/default.nix → self.overlays.default (primary, used in perSystem)
- overlays/inputs.nix → self.overlays.inputs (utility overlay)
- overlays/overrides/default.nix → self.overlays.overrides (utility overlay)

Excluded (in subdirectories):
- overlays/infra/patches.nix (data file, not overlay)
- overlays/infra/hotfixes.nix (imported by default.nix, not standalone)
- overlays/overrides/*.nix (imported by overrides/default.nix)

Why infra/ subdirectory?
Prevents infinite recursion from nixos-unified's autowiring attempting to import these as standalone overlays.

## Implementation notes

### Phase 1 (Foundation)

- Added stable nixpkgs inputs (darwin-stable, linux-stable)
- Enhanced lib/ with systemInput, systemOs, importOverlays
- Created infrastructure files (infra/patches.nix, infra/hotfixes.nix)
- Exported flake.lib for easy access

### Phase 2 (Migration)

- Created overlays/inputs.nix for multi-channel access
- Reorganized overrides into overlays/overrides/
- Migrated ghc_filesystem from inline to dedicated file
- Refactored default.nix to 5-layer composition
- Resolved importOverlays recursion by inlining in overrides/default.nix
- Moved debug packages to legacyPackages.debug to prevent automatic builds

### Phase 3 (Validation)

- Comprehensive testing across all layers
- Documentation (this file + handling-broken-packages.md)
- Example scenario validation
- README update

## Maintenance

### Monitoring workflow

```bash
# Weekly: Check active hotfixes
grep -A 3 "inherit.*stable" overlays/infra/hotfixes.nix

# For each package, check hydra
# https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.SYSTEM

# Test without hotfix (temporarily disable)
# Comment out in hotfixes.nix, run: nix flake check

# If passes: remove permanently
# If fails: keep and update TODO comment
```

### Cleanup checklist

- Monthly review of active hotfixes
- After nixpkgs update: test if hotfixes can be removed
- After nixpkgs update: test if patches can be removed
- Update tracking comments with latest status
- Remove overrides when upstream fixes land

### Tracking template

```nix
inherit (final.stable)
  # https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.SYSTEM
  # Issue: [description]
  # Tracking: [upstream issue/PR link]
  # TODO: Remove when [specific condition]
  # Added: YYYY-MM-DD
  packageName
  ;
```

## Troubleshooting

### "Infinite recursion encountered"

- Cause: Using lib.importOverlays from within a file it would import
- Solution: Inline the import logic (see overrides/default.nix)

### "Attribute 'stable' missing"

- Cause: Overlay layer order issue
- Solution: Ensure inputs' layer comes before hotfixes in composition

### "Package not found in stable"

- Check: Package name might differ between channels
- Solution: Use nix search nixpkgs#packageName in both channels

### Multi-channel collision

- Symptom: Unexpected package version
- Debug: nix eval .#legacyPackages.SYSTEM.packageName.version
- Solution: Check layer order in default.nix

## See also

- [Handling broken packages](/guides/handling-broken-packages)
- [Nixpkgs overlays manual](https://nixos.org/manual/nixpkgs/stable/#chap-overlays)
- https://github.com/srid/nixos-unified
- https://github.com/mirkolenz/nixos
