---
title: Nix-Config Architecture
description: Understanding the three-layer architecture combining flake-parts, nixos-unified, and multi-channel resilience
---

This configuration combines three complementary architectural patterns to create a maintainable, resilient nix-config that works across macOS and NixOS systems.

## Three-layer architecture

### Layer 1: Base framework (flake-parts)

Uses [flake-parts](https://github.com/hercules-ci/flake-parts) as the foundation for modular flake composition.
This enables perSystem configurations and composable flake modules, providing the structural foundation for organizing nix code.

**What it provides:**
- Modular flake composition
- PerSystem configuration helpers
- Clean separation of concerns across system types

### Layer 2: Autowiring layer (nixos-unified)

Integrates [nixos-unified](https://github.com/srid/nixos-unified) as flake-parts modules to provide **directory-based autowiring**.

**Directory-to-output mapping:**
- `configurations/` → darwinConfigurations, nixosConfigurations, homeConfigurations
- `modules/` → darwinModules, nixosModules, flakeModules
- `overlays/` → overlays.*

This eliminates manual wiring in flake.nix.
File paths become flake outputs automatically.

See [Understanding Autowiring](understanding-autowiring) for detailed explanation.

### Layer 3: Resilience layer (multi-channel nixpkgs patterns)

Adopts proven resilience patterns from [mirkolenz/nixos](https://github.com/mirkolenz/nixos) for handling nixpkgs unstable breakage.

**Key components:**
- **Multi-channel inputs**: Stable, unstable, and patched nixpkgs variants
- **Hotfixes infrastructure**: Platform-specific stable fallbacks (`overlays/infra/hotfixes.nix`)
- **Upstream patches**: Apply fixes before they reach your channel (`overlays/infra/patches.nix`)
- **Organized overrides**: Per-package build modifications (`overlays/overrides/`)
- **5-layer overlay composition**: Structured package and overlay merging

**Critical distinction**: mirkolenz/nixos uses flake-parts alone.
This configuration integrates mirkolenz's overlay patterns into nixos-unified's autowiring framework.

**Adaptation**: mirkolenz patterns live in `overlays/` (autowired) with infrastructure files in `overlays/infra/` (excluded from autowiring to prevent conflicts).
The overlay composition logic remains unchanged, only the directory organization adapted for nixos-unified compatibility.

See [Nixpkgs Hotfixes Infrastructure](/development/architecture/nixpkgs-hotfixes) for operational details.

## Platform support

- **darwin**: macOS systems via nix-darwin
- **nixos**: Linux systems via NixOS
- **home**: Standalone home-manager for non-admin users

## Integration of mirkolenz patterns

### What was adopted

The following patterns were adopted from [mirkolenz/nixos](https://github.com/mirkolenz/nixos):

**Multi-channel nixpkgs inputs** (flake.nix):
```nix
nixpkgs-darwin-stable.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin";
nixpkgs-linux-stable.url = "github:nixos/nixpkgs/nixos-25.05";
```

**Library helpers** (lib/default.nix):
- `systemInput`: Select OS-specific nixpkgs input (darwin-stable vs linux-stable)
- `systemOs`: Extract OS from system string (aarch64-darwin → darwin)
- `importOverlays`: Auto-import overlay directory

**Multi-channel access layer** (overlays/inputs.nix):
- Exports: `inputs`, `nixpkgs`, `patched`, `stable`, `unstable`
- Uses `systemInput` to select appropriate stable channel per OS
- Uses `applyPatches` to create patched nixpkgs variant

**Hotfixes pattern** (overlays/infra/hotfixes.nix):
- Platform-conditional stable fallbacks: `inherit (final.stable) packageName;`
- Structured: cross-platform → darwin → darwin-arch-specific → linux
- Documents hydra links and removal conditions

**Patches pattern** (overlays/infra/patches.nix):
- List of fetchpatch specifications for upstream fixes
- Applied in inputs.nix via `applyPatches`

**Organized overrides** (overlays/overrides/):
- Per-package build modifications
- Auto-imported via `lib.importOverlays`
- Example: `ghc_filesystem.nix` with `enableParallelBuilding = false;`

**5-layer overlay composition** (overlays/default.nix):
```nix
lib.mergeAttrsList [
  inputs'        # Multi-channel nixpkgs access
  hotfixes       # Platform-specific stable fallbacks
  packages       # Custom derivations
  overrides      # Build modifications
  flakeInputs    # Overlays from flake inputs
]
```

Debug/experimental packages are in `legacyPackages.debug` (not overlay) to prevent automatic builds and nixpkgs overrides.

### How patterns were adapted for nixos-unified

**Critical difference**: mirkolenz/nixos uses flake-parts directly without autowiring.
The integration required adapting patterns to work with nixos-unified's directory-based autowiring.

| Aspect | mirkolenz/nixos | infra (adapted) | Reason |
|--------|-----------------|-----------------|--------|
| Directory | `pkgs/` | `overlays/` | nixos-unified autowires `overlays/` |
| Infrastructure files | `pkgs/hotfixes.nix` | `overlays/infra/hotfixes.nix` | Exclude from autowiring (prevents unwanted overlay outputs) |
| | `pkgs/patches.nix` | `overlays/infra/patches.nix` | Same reason |
| Composition file | `pkgs/default.nix` | `overlays/default.nix` | Autowired as `overlays.default` |
| Lib argument | `args@{ lib', ... }` | `{ flake, ... }` | Access flake.lib instead of specialArgs |
| Flake wiring | Manual in flake-modules | Autowired | nixos-unified scans `overlays/` directory |

The overlay composition logic is identical (same merge order, same layer purposes).
Only the organization changed to prevent nixos-unified from creating unwanted `overlays.hotfixes` and `overlays.patches` outputs.

### Why this integration matters

When nixpkgs unstable breaks, you can apply surgical fixes (stable fallback for one package) without rolling back your entire flake.lock (which affects `O(10^5)` packages).
The directory structure remains clean and intuitive thanks to autowiring.

The combination provides:
- **Ergonomic architecture** (nixos-unified eliminates boilerplate)
- **Robust nixpkgs handling** (mirkolenz patterns provide resilience)
- **Clean integration** (adapted directory structure maintains both benefits)

## References

- [flake-parts](https://github.com/hercules-ci/flake-parts) - Modular flake composition
- [nixos-unified](https://github.com/srid/nixos-unified) - Directory-based autowiring
- [mirkolenz/nixos](https://github.com/mirkolenz/nixos) - Multi-channel resilience patterns
