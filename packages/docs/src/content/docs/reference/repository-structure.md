---
title: Repository Structure
description: Directory layout and file-to-flake-output mapping
---

Complete reference for the repository structure and how files map to flake outputs through nixos-unified autowiring.

## Directory tree

```
infra/
├── configurations/      # System and user configurations (autowired)
│   ├── darwin/          # → darwinConfigurations.*
│   ├── nixos/           # → nixosConfigurations.*
│   └── home/            # → legacyPackages.${system}.homeConfigurations.*
├── modules/             # Reusable nix modules (autowired)
│   ├── flake-parts/     # → flakeModules.* (system-agnostic)
│   ├── darwin/          # → darwinModules.* (macOS-specific)
│   ├── nixos/           # → nixosModules.* (Linux-specific)
│   └── home/            # home-manager modules (imported, not autowired)
├── overlays/            # Package modifications (autowired)
│   ├── default.nix      # → overlays.default (5-layer composition)
│   ├── inputs.nix       # → overlays.inputs (multi-channel nixpkgs)
│   ├── infra/           # Infrastructure files (not autowired)
│   ├── overrides/       # Per-package build modifications
│   ├── packages/        # Custom derivations (6 packages)
│   └── debug-packages/  # Experimental packages (see legacyPackages.debug)
├── lib/                 # Shared library functions
│   └── default.nix      # → flake.lib (exported for external use)
├── packages/            # Standalone typescript packages (docs site, etc)
├── scripts/             # Maintenance and utility scripts
│   ├── bisect-nixpkgs.sh    # Find breaking nixpkgs commits
│   ├── verify-system.sh     # Verify system configuration builds
│   └── sops/                # Secrets management helpers
├── secrets/             # Encrypted configuration data (sops-nix)
│   ├── hosts/           # Host-specific secrets
│   ├── users/           # User-specific secrets
│   └── services/        # Service credentials
├── docs/                # Symlink to packages/docs/src/content/docs
└── tests/               # Integration tests
```

## Directory-to-output mapping

### Configurations (autowired by nixos-unified)

| File | Flake output | Activation command |
|------|--------------|-------------------|
| `configurations/darwin/stibnite.nix` | `darwinConfigurations.stibnite` | `darwin-rebuild switch --flake .#stibnite` |
| `configurations/darwin/blackphos.nix` | `darwinConfigurations.blackphos` | `darwin-rebuild switch --flake .#blackphos` |
| `configurations/nixos/orb-nixos/` | `nixosConfigurations.orb-nixos` | `nixos-rebuild switch --flake .#orb-nixos` |
| `configurations/nixos/stibnite-nixos.nix` | `nixosConfigurations.stibnite-nixos` | `nixos-rebuild switch --flake .#stibnite-nixos` |
| `configurations/nixos/blackphos-nixos.nix` | `nixosConfigurations.blackphos-nixos` | `nixos-rebuild switch --flake .#blackphos-nixos` |
| `configurations/home/runner@stibnite.nix` | `legacyPackages.${system}.homeConfigurations.runner@stibnite` | `nix run .#activate-home -- runner@stibnite` |
| `configurations/home/runner@blackphos.nix` | `legacyPackages.${system}.homeConfigurations.runner@blackphos` | `nix run .#activate-home -- runner@blackphos` |
| `configurations/home/raquel@stibnite.nix` | `legacyPackages.${system}.homeConfigurations.raquel@stibnite` | `nix run .#activate-home -- raquel@stibnite` |
| `configurations/home/raquel@blackphos.nix` | `legacyPackages.${system}.homeConfigurations.raquel@blackphos` | `nix run .#activate-home -- raquel@blackphos` |

**Pattern**: File names become configuration names. No manual registration required.

### Modules (autowired by nixos-unified)

| Directory | Flake output | Usage |
|-----------|--------------|-------|
| `modules/flake-parts/*.nix` | `flakeModules.*` | Imported automatically in flake.nix |
| `modules/darwin/*.nix` | `darwinModules.*` | Available for darwin configurations |
| `modules/nixos/*.nix` | `nixosModules.*` | Available for nixos configurations |
| `modules/home/` | (imported directly) | Not autowired; imported via `modules/home/default.nix` |

**Example**: `modules/flake-parts/devshell.nix` defines the development shell, automatically available as `flakeModules.devshell`.

### Overlays (autowired by nixos-unified)

| File | Flake output | Purpose |
|------|--------------|---------|
| `overlays/default.nix` | `overlays.default` | 5-layer composition (inputs → hotfixes → packages → overrides → flakeInputs) |
| `overlays/inputs.nix` | `overlays.inputs` | Multi-channel nixpkgs access (stable, unstable, patched) |
| `overlays/overrides/default.nix` | `overlays.overrides` | Auto-imported per-package build modifications |

**Custom packages** (defined in overlays, exposed via packages output):
- From `overlays/packages/`: cc-statusline-rs, starship-jj, markdown-tree-parser, atuin-format
- From `nix-ai-tools` (flake input): claude-code-bin (auto-updated daily)
- From `landrun-nix` (flake input): Landlock-based sandboxing for applications (Linux only)

**Experimental packages** (not in overlay, manual build only):
- From `overlays/debug-packages/` → `legacyPackages.debug`: conda-lock, holos, quarto
- Access: `nix build .#debug.<package>` or `just debug-build <package>`

**Note**: The `overlays/infra/` subdirectory is intentionally excluded from autowiring to avoid conflicts:
- `infra/hotfixes.nix`: Platform-specific stable fallbacks
- `infra/patches.nix`: Upstream patch infrastructure

### Library functions

| File | Flake output | Exported functions |
|------|--------------|-------------------|
| `lib/default.nix` | `flake.lib` | `mdFormat`, `systemInput`, `systemOs`, `importOverlays` |

**Usage in other files**:
```nix
# flake.lib is available throughout the configuration
inherit (flake.lib) systemInput systemOs;
```

## Current flake outputs

Complete output listing from `om show .`:

**Packages** (nix build .#<name>):
- nvim-treesitter-main
- starship-jj - starship plugin for jj
- atuin-format - Format atuin history with Catppuccin Mocha
- claude-code-bin - Agentic coding tool (auto-updated daily)
- activate - Activate NixOS/nix-darwin/home-manager configurations
- cc-statusline-rs - Claude Code statusline implementation in Rust
- default - Activate configurations (alias)
- markdown-tree-parser - Markdown tree structure parser
- update - Update primary flake inputs

**Devshells** (nix develop .#<name>):
- default - Dev environment for infra

**Checks** (nix flake check):
- pre-commit

**NixOS Configurations** (nixos-rebuild switch --flake .#<name>):
- blackphos-nixos
- orb-nixos
- stibnite-nixos

**Darwin Configurations** (darwin-rebuild switch --flake .#<name>):
- stibnite
- blackphos

**NixOS Modules**:
- default
- common

**Overlays**:
- inputs - Multi-channel nixpkgs access
- overrides - Build modifications
- default - 5-layer composition

## Import mechanics

### Configurations

Configurations import modules and overlays:

```nix
# configurations/darwin/hostname.nix
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: {
  # Modules imported via nixpkgs module system
  imports = [
    inputs.self.darwinModules.common
  ];

  # Overlays applied via nixpkgs.overlays
  nixpkgs.overlays = [
    inputs.self.overlays.default
  ];
}
```

### Modules

Modules are composable and can import other modules:

```nix
# modules/nixos/common.nix
{ config, lib, pkgs, ... }: {
  # Module configuration
}
```

### Overlays

Overlays modify or add packages to nixpkgs:

```nix
# overlays/packages/mypackage.nix
final: prev: {
  mypackage = final.callPackage ./derivation.nix { };
}
```

## What gets autowired vs manual

### Autowired (file → output automatic)

- `configurations/darwin/` → darwinConfigurations
- `configurations/nixos/` → nixosConfigurations
- `configurations/home/` → homeConfigurations
- `modules/flake-parts/` → flakeModules
- `modules/darwin/` → darwinModules
- `modules/nixos/` → nixosModules
- `overlays/*.nix` → overlays

### Manual (explicit specification required)

- `modules/home/` - Imported via default.nix, not autowired
- `overlays/infra/` - Excluded from autowiring (helper infrastructure)
- `lib/` - Exported as flake.lib via flake-parts
- `packages/` - TypeScript packages (not nix derivations)

## See also

- [Understanding Autowiring](/concepts/understanding-autowiring) - How directory-based autowiring works
- [Nix-Config Architecture](/concepts/nix-config-architecture) - Three-layer architecture explanation
- [Multi-User Patterns](/concepts/multi-user-patterns) - Admin vs non-admin user organization
