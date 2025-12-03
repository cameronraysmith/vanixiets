---
title: Nix-Config Architecture
description: Understanding the architecture combining dendritic flake-parts, clan-core, and multi-channel overlay composition
---

This infrastructure combines three complementary architectural patterns to create a maintainable, multi-machine nix-config that works across macOS and NixOS systems.

## Architecture overview

### Layer 1: Base framework (flake-parts)

Uses [flake-parts](https://flake.parts) as the foundation for modular flake composition.
This enables perSystem configurations and composable flake modules, providing the structural foundation for organizing nix code.

**What it provides:**
- Modular flake composition
- PerSystem configuration helpers
- Clean separation of concerns across system types

### Layer 2: Module organization (dendritic pattern)

Uses the [dendritic flake-parts pattern](/concepts/dendritic-architecture/) for module organization.
Every Nix file is a flake-parts module, organized by *aspect* (feature) rather than by *host*.

**Key principle**: Configuration is organized by what it does, not which machine it runs on.

**What it provides:**
- Aspect-based organization (features, not hosts)
- Automatic module discovery via import-tree
- Cross-cutting configuration spanning NixOS, nix-darwin, and home-manager
- Aggregate modules for composing related features

See [Dendritic Architecture](/concepts/dendritic-architecture/) for detailed explanation.

### Layer 3: Multi-machine coordination (clan-core)

Uses [clan-core](https://clan.lol/) for multi-machine coordination and deployment.
Clan orchestrates deployments across the machine fleet but doesn't replace underlying NixOS/nix-darwin configuration.

**What it provides:**
- Machine registry and deployment targets
- Inventory system for service orchestration
- System-level secrets generation (clan vars)
- Unified deployment tooling

See [Clan Integration](/concepts/clan-integration/) for detailed explanation.

### Layer 4: Overlay composition (multi-channel resilience)

Adopts proven resilience patterns from [mirkolenz/nixos](https://github.com/mirkolenz/nixos) for handling nixpkgs unstable breakage.

**Key components:**
- **Multi-channel inputs**: Stable, unstable, and patched nixpkgs variants
- **Hotfixes infrastructure**: Platform-specific stable fallbacks
- **Five-layer overlay composition**: Structured package and overlay merging

See [Nixpkgs Hotfixes Infrastructure](/development/architecture/nixpkgs-hotfixes) for operational details.

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

The overlay system provides resilience against nixpkgs breakage through five layers:

```nix
# Layer composition order
lib.mergeAttrsList [
  inputs'        # Layer 1: Multi-channel nixpkgs access
  hotfixes       # Layer 2: Platform-specific stable fallbacks
  packages       # Layer 3: Custom derivations
  overrides      # Layer 4: Build modifications
  flakeInputs    # Layer 5: Overlays from flake inputs
]
```

### Multi-channel nixpkgs access

```nix
# modules/nixpkgs/overlays/inputs.nix
final: prev: {
  inherit inputs nixpkgs patched;
  stable = systemInput system;   # darwin-stable or linux-stable
  unstable = prev;               # Default nixpkgs
}
```

All channels available throughout the configuration for selective package sourcing.

### Hotfixes pattern

```nix
# modules/nixpkgs/overlays/infra/hotfixes.nix
final: prev: {
  # Platform-conditional stable fallbacks
  inherit (final.stable) packageName;  # Use stable version

  # Documented with hydra links and removal conditions
}
```

When nixpkgs unstable breaks, apply surgical fixes (stable fallback for one package) without rolling back entire flake.lock (which affects O(10^5) packages).

## Secrets architecture

Two-tier secrets model:

| Tier | System | Purpose | Management |
|------|--------|---------|------------|
| **Tier 1** | Clan vars | System-level generated secrets | `clan vars generate` |
| **Tier 2** | sops-nix | User-level manual secrets | `sops secrets/...` |

- **Tier 1 examples**: SSH host keys, zerotier identities, LUKS passphrases
- **Tier 2 examples**: GitHub tokens, API keys, signing keys

See [Clan Integration](/concepts/clan-integration/) for details on two-tier secrets.

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
- **Robust nixpkgs handling** - Overlay patterns provide resilience
- **Clean separation** - Each layer has clear responsibilities

## References

- [flake-parts](https://flake.parts) - Modular flake composition
- [dendritic pattern](https://vic.github.io/dendrix/Dendritic.html) - Module organization
- [clan-core](https://clan.lol/) - Multi-machine coordination
- [mirkolenz/nixos](https://github.com/mirkolenz/nixos) - Multi-channel resilience patterns

## See also

- [Dendritic flake-parts Architecture](/concepts/dendritic-architecture/) - Module organization pattern details
- [Clan Integration](/concepts/clan-integration/) - Multi-machine coordination details
- [Repository Structure](/reference/repository-structure) - Complete directory layout
