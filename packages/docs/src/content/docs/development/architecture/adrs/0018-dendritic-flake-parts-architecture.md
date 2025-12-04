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

specialArgs anti-pattern:
nixos-unified's autowiring mechanism used `specialArgs` to pass flake context into modules.
This created implicit dependencies and made module behavior non-obvious.
Modules received configuration through hidden channels rather than explicit imports.

Implicit module wiring:
File paths mapped directly to flake outputs (e.g., `configurations/darwin/stibnite.nix` became `darwinConfigurations.stibnite`).
While convenient for small configurations, this created coupling between directory structure and flake schema.
Renaming or reorganizing required understanding the autowiring rules.

Host-centric organization:
Configuration organized by machine rather than feature.
Adding a new capability (e.g., AI tooling) meant editing multiple host files.
Feature duplication across hosts led to drift and maintenance burden.

Limited module composition:
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

Organizational principle:
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

Configuration in flake.nix:
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

Result: Minimal flake.nix (23 lines) with 83+ auto-discovered modules.

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

The existing nixos-unified architecture worked adequately when this infrastructure managed 2-3 machines, but scaling to 8 machines across two platforms exposed fundamental organizational problems.
Adding AI tooling meant editing 8 separate host configuration files, each time risking inconsistencies in which tools appeared on which machines.
The specialArgs mechanism became a debugging nightmare - when a module failed, tracing the failure required understanding which implicit dependencies were injected and in what order.
More critically, nixos-unified provided no inventory abstraction for clan-core integration, which this fleet requires for zerotier VPN coordination across darwin laptops and nixos servers.
The path-based autowiring rules were convenient for the initial setup but became a liability when restructuring was needed - renaming a directory meant understanding the implicit mapping from filesystem paths to flake outputs.

### Raw flake-parts without dendritic pattern

Flake-parts provides the infrastructure for modular flake composition, but without the dendritic organizational pattern, it requires explicit module registration in flake.nix for every new file.
At 83 modules (and growing), this fleet would require maintaining a massive imports list, and every new feature would mean editing the root flake.nix file.
The dendritic pattern's import-tree mechanism eliminates this registration burden entirely - creating a new file under `modules/` automatically includes it.
More importantly, raw flake-parts provides no organizational convention, meaning each implementation develops its own directory structure and namespace patterns.
The dendritic pattern brings a proven structure that works across multiple production implementations, reducing cognitive load when switching contexts.

### Snowfall lib

Snowfall lib offers an alternative organizational framework with its own opinionated structure and conventions.
We chose the dendritic pattern instead because it aligns more closely with the flake-parts ecosystem that clan-core is built on.
Clan is itself a flake-parts module, and the dendritic namespace exports (`flake.modules.*`) integrate naturally with clan's inventory system.
Additionally, import-tree's discovery mechanism is simpler and more transparent than Snowfall's loader - it's easier to reason about "every .nix file under modules/ is imported" than to learn Snowfall's specific directory naming conventions.
The existence of multiple high-quality production implementations (drupol, mightyiam, gaetanlepage) using the dendritic pattern provided confidence that the architecture scales and integrates well with common NixOS patterns.

### NixOS modules only (no flake-parts)

The traditional NixOS module system provides powerful composition capabilities, but this fleet includes 4 darwin laptops alongside 4 nixos servers.
Darwin uses nix-darwin's module system, which is similar to but separate from NixOS modules, and coordinating shared configuration between the two without a unifying abstraction would mean duplicating every cross-platform feature.
Flake-parts provides the perSystem abstraction that enables defining packages and configurations in a platform-agnostic way, then specializing only where necessary.
Additionally, the standard NixOS module approach lacks the namespace export pattern that dendritic uses to create composable aggregates - machine configurations would need to import every individual module rather than importing high-level aggregates like `flakeModulesHome.ai` that bundle related functionality.

## Consequences

### Positive

The dendritic pattern's feature-based organization eliminates the duplication problem that plagued the nixos-unified architecture.
When we define AI tooling once in `modules/home/ai/`, every machine configuration can import that aggregate and receive the entire suite of tools consistently.
This changes the operational model from "edit 8 machine files to add a feature" to "create one feature file and import it where needed."
The impact becomes clear when considering that changes propagate automatically - updating the AI tooling aggregate updates all machines simultaneously, eliminating version drift across the fleet.

This organizational shift makes dependencies explicit and traceable.
Reading a machine configuration shows exactly which aggregates it imports (`flakeModulesHome.ai`, `flakeModulesHome.development`), and reading those aggregate definitions shows which specific modules contribute to them.
Debugging transforms from archeology (tracing implicit specialArgs flows through multiple layers) to simple reference following.
When a module fails to build, the error message points directly to the file and the imports it depends on, rather than requiring mental reconstruction of the autowiring rules.

The auto-discovery mechanism scales gracefully precisely because it removes humans from the registration loop.
At 83 modules, manually maintaining an imports list would be error-prone and tedious.
Import-tree scans the `modules/` directory recursively and imports every `.nix` file it finds, which means adding module 84 requires only creating the file in the appropriate directory.
No flake.nix edits, no merge conflicts in centralized configuration, no possibility of forgetting to register a new module.
This architectural property becomes increasingly valuable as the configuration grows - complexity remains constant regardless of module count.

Cross-platform consistency emerges naturally from flake-parts' perSystem abstraction.
The same organizational patterns work identically for darwin modules, nixos modules, and home-manager modules.
Home-manager aggregates work on both darwin and nixos hosts without modification, and platform-specific concerns are isolated to the machine-specific configuration files under `modules/machines/darwin/` and `modules/machines/nixos/`.
This unification is critical for this fleet's 4 darwin laptops and 4 nixos servers - shared tooling lives in cross-platform aggregates while platform-specific settings remain isolated.

The dendritic pattern aligns architecturally with clan-core because both are built on flake-parts modules.
Clan's machine registry consumes the same namespace exports (`flake.modules.darwin.*`, `flake.modules.nixos.*`) that dendritic produces, creating a natural integration point.
Machine configurations export to namespaces that clan reads when building the fleet inventory, which enables clan's multi-machine orchestration to work seamlessly with the dendritic organization.
This architectural coherence eliminated what could have been a significant impedance mismatch between the configuration framework and the deployment orchestration layer.

Finally, multiple production implementations validate that this pattern works at scale and integrates well with the broader NixOS ecosystem.
The drupol, mightyiam, and gaetanlepage configurations demonstrate the pattern applied to real infrastructure with diverse requirements, and their continued operation provides evidence that the architectural approach is sound and maintainable over time.

### Negative

The pattern requires understanding flake.modules.* namespace exports, which imposes a learning curve for contributors unfamiliar with flake-parts.
This is less immediately intuitive than nixos-unified's "file at path X creates output Y" convention where the filesystem structure directly determines flake outputs.
However, the explicit imports make debugging straightforward once the pattern is understood - reading a machine configuration shows exactly which aggregates it imports, and reading those aggregates shows which modules contribute.
The trade-off is initial complexity for long-term maintainability, which becomes favorable as the configuration scales beyond a handful of machines.

Converting from nixos-unified required restructuring all configurations, which consumed substantial engineering effort during Epic 2 (November 2024).
The migration involved moving approximately 83 modules from host-centric organization to aspect-based organization, reorganizing imports to use namespace exports, and validating that every module continued to function correctly after the transition.
This ~40 hours of migration work was necessary because the two architectures organize configuration fundamentally differently - nixos-unified's implicit autowiring cannot be mechanically transformed into dendritic's explicit namespace exports.
The investment pays dividends in ongoing maintenance burden reduction, but it represents real upfront cost that delayed other development work.

Namespace discipline failures create silent build failures that can be difficult to diagnose without understanding the auto-merging mechanism.
When multiple files in the same directory export to different namespaces, import-tree imports them all but they don't merge into a single aggregate.
Machine configurations that import the expected aggregate name then fail to receive the modules that exported to incorrect namespaces, and the error manifests as missing packages or services rather than an obvious "wrong namespace" message.
Contributors must learn that directory structure determines namespace identity - all files under `modules/home/ai/` must export to `flake.modules.homeManager.ai` for the aggregation to work correctly.

Directory structure conventions use syntactic markers that aren't self-documenting without external knowledge.
The underscore prefix convention (`_overlays/`) excludes directories from import-tree scanning, which is useful for organizing code that shouldn't be auto-discovered but requires contributors to know that underscore has semantic meaning.
Similarly, the namespace export pattern (`flake.modules.homeManager.ai`) follows a convention that must be learned rather than inferred.
These conventions are documented in this ADR and the concepts documentation, but they represent tribal knowledge that new contributors must acquire before they can confidently add modules.

### Neutral

Dendritic modules remain NixOS/home-manager modules at their core, which means the pattern adds organizational structure rather than introducing fundamentally new abstractions.
A contributor who understands NixOS module development already possesses most of the knowledge needed to work with dendritic modules - the same option declarations, the same configuration merging semantics, the same module system features all work identically.
The dendritic pattern simply prescribes where modules should live in the filesystem and how they should export to namespaces for consumption by machine configurations.
This conceptual alignment means skills transfer directly from standard NixOS module development, and existing documentation about NixOS module patterns remains applicable.
The learning investment focuses narrowly on organizational conventions rather than requiring mastery of an entirely new configuration system.

Documentation for the dendritic pattern exists but is scattered across multiple reference implementations rather than consolidated in a single authoritative source.
The dendrix documentation, mightyiam's configuration, and drupol's setup each demonstrate aspects of the pattern, but newcomers must synthesize understanding from these distributed examples.
This fragmentation creates a steeper initial learning curve than a framework with comprehensive official documentation would provide.
However, this ADR and the concepts documentation in this repository fill that gap for contributors to this specific infrastructure, providing a single reference that explains the pattern's application to this fleet's needs.
The scattered ecosystem documentation remains valuable for seeing how different implementations adapt the pattern to their specific requirements.

## Validation evidence

### Epic 1 (November 2024)

Pattern validated in test-clan repository before production migration:

- Story 1.1-1.2: Initial dendritic structure established
- Story 1.6: Test harness with 18 tests validating auto-discovery
- Story 1.7: Pure dendritic pattern achieved with zero regressions
- Stories 1.8-1.10: Cross-platform modules validated (darwin + nixos)
- Story 1.12: Physical deployment successful (blackphos darwin laptop)

Metrics:
- 83 auto-discovered modules
- 23-line minimal flake.nix
- 270 packages preserved across migration (zero regression)
- All 7 patterns rated HIGH confidence in GO/NO-GO decision

### Epic 2 (November 2024)

Production migration to infra repository:

- Stories 2.1-2.3: Wholesale migration from test-clan patterns
- Stories 2.5-2.7: Darwin workstations (stibnite, blackphos) operational
- Stories 2.9-2.10: NixOS VPS (cinnabar, electrum) operational
- Stories 2.13-2.14: New machines (rosegold, argentum) created using patterns

Result: 8-machine fleet fully operational under dendritic architecture.

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
