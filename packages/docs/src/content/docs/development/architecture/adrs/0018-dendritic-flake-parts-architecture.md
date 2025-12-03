---
title: "ADR-0018: Dendritic Flake-Parts Architecture"
---

- **Status**: Accepted
- **Date**: 2024-11-20
- **Scope**: Nix configuration architecture
- **Related**: [ADR-0017: Dendritic overlay patterns](0017-dendritic-overlay-patterns/)

## Context

This infrastructure required a scalable Nix configuration architecture to manage 8 machines across 2 platforms (4 darwin laptops, 4 nixos servers) with 5 users, supporting both development workstations and cloud infrastructure.

The prior approach used nixos-unified, which presented several architectural limitations that became apparent as the fleet grew.

### nixos-unified limitations

**specialArgs anti-pattern**:
nixos-unified's autowiring mechanism used `specialArgs` to pass flake context into modules.
This created implicit dependencies and made module behavior non-obvious.
Modules received configuration through hidden channels rather than explicit imports.

**Implicit module wiring**:
File paths mapped directly to flake outputs (e.g., `configurations/darwin/stibnite.nix` became `darwinConfigurations.stibnite`).
While convenient for small configurations, this created coupling between directory structure and flake schema.
Renaming or reorganizing required understanding the autowiring rules.

**Host-centric organization**:
Configuration organized by machine rather than feature.
Adding a new capability (e.g., AI tooling) meant editing multiple host files.
Feature duplication across hosts led to drift and maintenance burden.

**Limited module composition**:
Cross-cutting concerns (features spanning darwin, nixos, home-manager) required manual coordination.
No standardized pattern for shared modules.

### Requirements for new architecture

- Support 8 machines across darwin and nixos platforms
- Enable feature-based organization (add once, available everywhere)
- Eliminate implicit dependencies (explicit imports only)
- Support clan-core for multi-machine orchestration (see [ADR-0019](0019-clan-core-orchestration/))
- Scale to 100+ modules without manual registration

## Decision

Adopt the **dendritic flake-parts pattern** where every Nix file is a flake-parts module organized by aspect (feature) rather than host.

### Pattern overview

Every `.nix` file in the `modules/` directory is a flake-parts module.
Files export to namespaces under `flake.modules.*` and are auto-discovered by import-tree.

**Organizational principle**:
```
modules/
├── home/ai/           # AI tools for ALL users
├── home/development/  # Dev environment for ALL users
├── machines/darwin/   # Machine-specific (darwin)
├── machines/nixos/    # Machine-specific (nixos)
└── nixos/services/    # Services for ALL nixos hosts
```

Features defined once in aspect directories, consumed by machine configurations.
Machine-specific files contain only truly unique settings.

### import-tree auto-discovery

The [import-tree](https://github.com/vic/import-tree) mechanism by Victor Borja enables automatic module discovery without manual registration.

**Configuration in flake.nix**:
```nix
{
  imports = [ inputs.import-tree.flakeModule ];

  flake.autoImport = {
    path = ./modules;
    exclude = name: name == "README.md";
  };
}
```

This scans `modules/` recursively and imports every `.nix` file as a flake-parts module.
Adding a new file automatically includes it - no flake.nix updates required.

**Result**: Minimal flake.nix (23 lines) with 83+ auto-discovered modules.

### Module namespace exports

Modules export to `flake.modules.*` namespaces for consumption:

```nix
# modules/home/ai/claude-code.nix
{ ... }:
{
  flake.modules.homeManager.ai = { pkgs, ... }: {
    home.packages = [ pkgs.claude-code ];
    # ... configuration
  };
}
```

Multiple files in the same directory export to the same namespace, auto-merging into aggregates:
- `modules/home/ai/claude-code.nix` + `modules/home/ai/mcp-servers.nix` merge into `flake.modules.homeManager.ai`
- Directory structure creates the namespace boundaries

### Directory organization

```
modules/
├── clan/              # Clan integration (machines, inventory, services)
├── darwin/            # nix-darwin modules (per-aspect)
│   ├── core/          # Core darwin settings
│   ├── apps/          # Application configurations
│   └── homebrew/      # Homebrew cask management
├── home/              # home-manager modules (per-aspect)
│   ├── ai/            # AI tools (claude-code, MCP servers)
│   ├── core/          # Core settings (XDG, SSH, fonts)
│   ├── development/   # Dev environment (git, editors, languages)
│   ├── shell/         # Shell configuration (zsh, fish, nushell)
│   ├── packages/      # Organized package sets
│   ├── terminal/      # Terminal utilities
│   ├── tools/         # Additional tools
│   └── users/         # User-specific modules
├── machines/          # Machine-specific configurations
│   ├── darwin/        # Darwin hosts (stibnite, blackphos, rosegold, argentum)
│   └── nixos/         # NixOS hosts (cinnabar, electrum, galena, scheelite)
├── nixos/             # NixOS modules (per-aspect)
│   ├── core/          # Core NixOS settings
│   └── services/      # System services
├── nixpkgs/           # Overlay architecture (see ADR-0017)
├── system/            # Cross-platform system modules
├── terranix/          # Cloud infrastructure (Hetzner, GCP)
└── checks/            # Validation and testing
```

### Machine configuration pattern

Machine configurations import aggregates from the namespace:

```nix
# modules/machines/darwin/stibnite/default.nix
{ config, ... }:
let
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  flake.modules.darwin."machines/darwin/stibnite" =
    { pkgs, lib, inputs, ... }:
    {
      # ... darwin configuration

      home-manager.users.crs58.imports = [
        flakeModulesHome."users/crs58"
        flakeModulesHome.ai          # All AI tools
        flakeModulesHome.core        # Core settings
        flakeModulesHome.development # Dev environment
        flakeModulesHome.shell       # Shell config
      ];
    };
}
```

### Comparison with nixos-unified

| Aspect | nixos-unified | Dendritic flake-parts |
|--------|---------------|----------------------|
| Module discovery | Path-based autowiring | import-tree auto-discovery |
| Configuration passing | specialArgs (implicit) | Namespace exports (explicit) |
| Organization | By host | By aspect/feature |
| Module registration | Required specific paths | Any path under modules/ |
| flake.nix size | 50-100+ lines | 23 lines |
| Adding features | Edit multiple host files | Create single aspect file |

## Alternatives considered

### Stay with nixos-unified

**Rejected**.

While functional for smaller configurations, nixos-unified's limitations compounded as the fleet grew:
- specialArgs pollution made module debugging difficult
- Host-centric organization led to duplication across 8 machines
- Implicit wiring rules were poorly documented
- No clear path to clan-core integration

### Raw flake-parts without dendritic pattern

**Rejected**.

Flake-parts provides the foundation but requires manual module registration.
Without import-tree auto-discovery:
- Every new module requires flake.nix update
- No organizational convention (structure varies per implementation)
- Doesn't scale to 100+ modules
- No standardized namespace pattern for aggregates

### Snowfall lib

**Not evaluated in depth**.

Snowfall provides a different organizational pattern with its own conventions.
The dendritic pattern was selected based on:
- Alignment with flake-parts ecosystem (broader adoption)
- Reference implementations in production (drupol, mightyiam, gaetanlepage)
- import-tree's simpler discovery mechanism
- Clan-core compatibility (clan is a flake-parts module)

### NixOS modules only (no flake-parts)

**Rejected**.

Standard NixOS module system works for NixOS but:
- No darwin support (nix-darwin has separate module system)
- No standardized cross-platform pattern
- No perSystem abstraction for platform-agnostic packages
- Limited ecosystem tooling

## Consequences

### Positive

**Feature-based organization eliminates duplication**:
Define AI tooling once in `modules/home/ai/`, import in any machine configuration.
Changes propagate automatically to all machines using that aggregate.

**Explicit imports make dependencies visible**:
No hidden specialArgs or autowiring.
Reading a module shows exactly what it depends on.
Debugging reduced from tracing implicit flows to following explicit imports.

**Auto-discovery scales gracefully**:
83 modules discovered automatically.
Adding module 84 requires only creating the file.
No registration, no flake.nix changes, no configuration drift.

**Cross-platform consistency**:
Same patterns work for darwin, nixos, and home-manager modules.
Aggregates can span platforms (home-manager modules work on both darwin and nixos).

**Aligns with clan-core**:
Clan is a flake-parts module.
Dendritic namespace exports integrate naturally with clan inventory.
Machine configurations export to namespaces consumed by `clan.machines.*`.

**Industry validation**:
Pattern proven by multiple production implementations:
- [drupol-dendritic-infra](https://github.com/drupol/nixos-config)
- [mightyiam-dendritic-infra](https://github.com/mightyiam/nix-config)
- [gaetanlepage-dendritic-nix-config](https://github.com/GaetanLepage/nix-config)

### Negative

**Learning curve for contributors**:
Understanding `flake.modules.*` namespace exports requires familiarity with flake-parts.
Not as immediately intuitive as "file at path X creates output Y".

**Migration effort required**:
Converting from nixos-unified involved restructuring all configurations.
Epic 2 (November 2024) dedicated to migration (~40 hours effort).

**Namespace discipline required**:
Incorrect namespace exports create silent failures.
Must ensure files in same directory export to same namespace for auto-merging.

**Directory structure conventions**:
Underscore prefix (`_overlays/`) excludes from import-tree.
Contributors must learn these conventions.

### Neutral

**Conceptual alignment with NixOS modules**:
Dendritic modules are still NixOS/home-manager modules at the core.
The pattern adds organizational structure, not new abstractions.
Skills transfer from standard NixOS module development.

**Documentation exists but scattered**:
Pattern documented across multiple sources (dendrix, mightyiam, drupol).
No single authoritative reference.
This ADR and concepts documentation fill that gap for this repository.

## Validation evidence

### Epic 1 (November 2024)

Pattern validated in test-clan repository before production migration:

- **Story 1.1-1.2**: Initial dendritic structure established
- **Story 1.6**: Test harness with 18 tests validating auto-discovery
- **Story 1.7**: Pure dendritic pattern achieved with zero regressions
- **Stories 1.8-1.10**: Cross-platform modules validated (darwin + nixos)
- **Story 1.12**: Physical deployment successful (blackphos darwin laptop)

**Metrics**:
- 83 auto-discovered modules
- 23-line minimal flake.nix
- 270 packages preserved across migration (zero regression)
- All 7 patterns rated HIGH confidence in GO/NO-GO decision

### Epic 2 (November 2024)

Production migration to infra repository:

- **Stories 2.1-2.3**: Wholesale migration from test-clan patterns
- **Stories 2.5-2.7**: Darwin workstations (stibnite, blackphos) operational
- **Stories 2.9-2.10**: NixOS VPS (cinnabar, electrum) operational
- **Stories 2.13-2.14**: New machines (rosegold, argentum) created using patterns

**Result**: 8-machine fleet fully operational under dendritic architecture.

## References

### Internal

- [Dendritic Architecture concept documentation](/concepts/dendritic-architecture)
- [ADR-0017: Dendritic overlay patterns](0017-dendritic-overlay-patterns/)
- [ADR-0019: Clan-core orchestration](0019-clan-core-orchestration/)
- [ADR-0020: Dendritic + Clan integration](0020-dendritic-clan-integration/)
- Epic 1 GO/NO-GO decision: `docs/notes/development/go-no-go-decision.md`

### External

- [dendritic pattern](https://github.com/mightyiam/dendritic) by Shahar "Dawn" Or
- [import-tree](https://github.com/vic/import-tree) by Victor Borja
- [dendrix documentation](https://vic.github.io/dendrix/Dendritic.html)
- [flake.parts](https://flake.parts) - Foundation framework
- [drupol-dendritic-infra](https://github.com/drupol/nixos-config) - Reference implementation
- [mightyiam-dendritic-infra](https://github.com/mightyiam/nix-config) - Pattern creator's config
- [gaetanlepage-dendritic-nix-config](https://github.com/GaetanLepage/nix-config) - Reference implementation
