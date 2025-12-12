---
title: Architecture overview
description: Understanding the architecture combining dendritic flake-parts, clan, and multi-channel overlay composition
sidebar:
  order: 2
---

This infrastructure combines three complementary architectural patterns to create a maintainable, multi-machine configuration that works across macOS and NixOS systems.

## Architecture overview

### Layer 0: Module system foundation (nixpkgs)

Uses nixpkgs' module system primitives for configuration composition.
Flake-parts wraps `lib.evalModules` for flake composition.

**What it provides:**
- **lib.evalModules**: Fixpoint computation resolving modules into final configuration
- **deferredModule type**: Option type for storing module values that are evaluated later by consumers
- **Option merging**: Type-specific merge functions with priority handling

### Layer 1: Base framework (flake-parts)

Uses [flake-parts](https://flake.parts) as the foundation for modular flake composition.
Flake-parts wraps nixpkgs' evalModules for flake outputs, adding flake-specific conventions and ergonomics.

**What it provides:**
- Modular flake composition via evalModules wrapper
- PerSystem configuration helpers (per-system evaluation)
- flake.modules.* namespace convention (deferredModule type)
- Clean separation of concerns across system types

### Layer 2: Deferred module composition (aspect-based pattern)

Uses the deferredModule type (nixpkgs module system primitive) for storing configuration fragments.
Every Nix file is a flake-parts module (evaluated at the top level) that exports deferredModule values (evaluated later when consumers import them), enabling cross-cutting concerns to reference the merged result.

The [aspect-based deferred module composition pattern](/concepts/deferred-module-composition/) organizes these modules by *aspect* (feature) rather than by *host*, with flake-parts providing the evaluation context and namespace conventions.

**Key principle**: Configuration is organized by what it does, not which machine it runs on.

**What it provides:**
- Aspect-based organization (features, not hosts)
- Automatic module discovery via import-tree (adds to evalModules imports list)
- Cross-cutting configuration spanning NixOS, nix-darwin, and home-manager
- Aggregate modules for composing related features (deferredModule monoid composition)

See [Deferred Module Composition](/concepts/deferred-module-composition/) for detailed explanation.

### Layer 3: Multi-machine coordination (clan)

Uses [clan](https://clan.lol/) for multi-machine coordination and deployment.
Clan orchestrates deployments across the machine fleet but doesn't replace underlying NixOS/nix-darwin configuration.

**What it provides:**
- Machine registry and deployment targets
- Inventory system for service orchestration
- Secrets management with encryption (clan vars)
- Unified deployment tooling

See [Clan Integration](/concepts/clan-integration/) for detailed explanation.

### Layer 4: Overlay composition (multi-channel fallback)

Adopts proven patterns from [mirkolenz/nixos](https://github.com/mirkolenz/nixos) for handling nixpkgs unstable breakage with stable fallbacks.

**Key components:**
- **Multi-channel inputs**: Stable, unstable, and patched nixpkgs variants
- **Stable fallbacks infrastructure**: Platform-specific stable fallbacks
- **Five-layer overlay composition**: Structured package and overlay merging

See [Handling Broken Packages](/guides/handling-broken-packages) for operational details.

## Platform support

| Platform | Implementation | Deployment |
|----------|---------------|------------|
| **Darwin** | nix-darwin via clan | `clan machines update <hostname>` |
| **NixOS** | NixOS via clan | `clan machines update <hostname>` |
| **Home-Manager** | Integrated with system configs | Activates with system deployment |

## Directory structure

```
modules/
├── clan/              # Clan integration
│   ├── core.nix       # Clan flakeModule import
│   ├── machines.nix   # Machine registry
│   └── inventory/     # Service instances
├── darwin/            # nix-darwin modules (per-aspect)
├── home/              # home-manager modules (per-aspect)
├── machines/          # Machine-specific configs
│   ├── darwin/        # Darwin hosts
│   └── nixos/         # NixOS hosts
├── nixos/             # NixOS modules (per-aspect)
├── system/            # Cross-platform modules
├── terranix/          # Infrastructure as code
└── nixpkgs/           # Nixpkgs configuration and overlays

pkgs/
└── by-name/           # Custom package derivations
```

## Multi-channel overlay architecture

The overlay system provides stable fallbacks for nixpkgs breakage through internal and external overlays composed in a single pass:

```nix
# Overlay composition order (via lib.composeManyExtensions)
lib.composeManyExtensions [
  channels       # Multi-channel nixpkgs access (stable, unstable, patched)
  stable-fallbacks       # Platform-specific stable fallbacks
  overrides      # Build modifications
  nvim-treesitter # External overlay: nvim-treesitter from flake input
  nuenv          # External overlay: nushell utilities from flake input
  # ... other external overlays from flake inputs
] // customPackages  # Custom derivations from pkgs-by-name
```

### Multi-channel nixpkgs access

```nix
# modules/nixpkgs/overlays/channels.nix
final: prev: {
  inherit inputs nixpkgs patched;
  stable = systemInput system;   # darwin-stable or linux-stable
  unstable = prev;               # Default nixpkgs
}
```

All channels available throughout the configuration for selective package sourcing.

### Stable fallbacks pattern

```nix
# modules/nixpkgs/overlays/stable-fallbacks.nix
final: prev: {
  # Platform-conditional stable fallbacks
  inherit (final.stable) packageName;  # Use stable version

  # Documented with hydra links and removal conditions
}
```

When nixpkgs unstable breaks, apply surgical fixes (stable fallback for one package) without rolling back entire flake.lock (which affects O(10^5) packages).

## Secrets architecture

Clan vars provides unified secrets management with sops encryption.
All secrets (SSH keys, zerotier identities, API tokens, passphrases) are managed through clan vars for consistent deployment and access control.

Migration in progress: some secrets still use legacy direct sops-nix patterns during transition to clan vars.

See [Clan Integration](/concepts/clan-integration/) for detailed secrets architecture and migration status.

## Integration points

### Terranix + Clan

Infrastructure provisioning (terranix) creates cloud resources.
Clan deploys NixOS configurations to those resources.

```
Terranix creates VMs → Clan installs NixOS → Clan deploys config
```

### Dendritic + Clan

Dendritic modules define configurations.
Clan machines import and deploy those configurations.

```
Dendritic modules (aspect-based) → Clan machines (host-based) → Deployment
```

### Home-Manager + Clan

Home-manager modules defined in dendritic structure.
Machine configurations import home-manager modules.
Clan deploys full machine config including home-manager.

## Machine fleet

| Hostname | Platform | Type | Primary User |
|----------|----------|------|--------------|
| stibnite | aarch64-darwin | Laptop | crs58 |
| blackphos | aarch64-darwin | Laptop | raquel |
| rosegold | aarch64-darwin | Laptop | janettesmith |
| argentum | aarch64-darwin | Laptop | christophersmith |
| cinnabar | x86_64-linux | VPS (Hetzner) | cameron |
| electrum | x86_64-linux | VPS (Hetzner) | cameron |
| galena | x86_64-linux | GCP VM | cameron |
| scheelite | x86_64-linux | GCP VM (GPU) | cameron |

All machines managed via `clan machines update <hostname>`.

## Why this architecture

The combination provides:

- **Scalable organization** - Dendritic pattern handles growing complexity
- **Multi-machine coordination** - Clan orchestrates heterogeneous fleet
- **Robust nixpkgs handling** - Overlay patterns provide stable fallbacks
- **Clean separation** - Each layer has clear responsibilities

## References

- [flake-parts](https://flake.parts) - Modular flake composition
- [dendritic pattern](https://vic.github.io/dendrix/Dendritic.html) - Module organization
- [clan](https://clan.lol/) - Multi-machine coordination
- [mirkolenz/nixos](https://github.com/mirkolenz/nixos) - Multi-channel stable fallback patterns

## See also

- [Deferred Module Composition](/concepts/deferred-module-composition/) - Module organization pattern details
- [Clan Integration](/concepts/clan-integration/) - Multi-machine coordination details
- [Repository Structure](/reference/repository-structure) - Complete directory layout
