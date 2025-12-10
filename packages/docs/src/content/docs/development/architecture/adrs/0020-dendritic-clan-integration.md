---
title: "ADR-0020: Dendritic + Clan Integration"
---

- **Status**: Accepted
- **Date**: 2024-11-20
- **Scope**: Architecture integration
- **Synthesizes**: [ADR-0018: Dendritic flake-parts architecture](0018-dendritic-flake-parts-architecture/), [ADR-0019: Clan-core orchestration](0019-clan-core-orchestration/)

## Context

Adopting both dendritic flake-parts ([ADR-0018](0018-dendritic-flake-parts-architecture/)) and clan ([ADR-0019](0019-clan-core-orchestration/)) required solving integration challenges.
Neither was designed with the other in mind.

### Integration challenges

**Namespace boundaries**:
- Dendritic exports to `flake.modules.*` namespaces
- Clan expects configurations via `clan.machines.*`
- Need pattern for dendritic modules consumed by clan registry

**Module system integration**:
This integration works because both dendritic and clan use the same module system foundation from nixpkgs.
Dendritic modules are deferredModule type (nixpkgs `lib/types.nix` primitive) that delay evaluation until the final configuration is computed.
The `flake.modules.*` option has type `lazyAttrsOf deferredModule`, creating a namespace of deferred modules that can be imported into any evaluation context.
When clan machines import these deferred modules via their imports list, the modules are added to evalModules and evaluated with clan's module arguments (the final system configuration).
This explains why the integration is seamless: both systems use the same underlying module system primitives (deferredModule, evalModules, fixpoint computation), just with different evaluation contexts—flake-parts evaluates with class "flake" to build the namespace, while clan evaluates with nixosSystem or darwinSystem to build machine configurations.

**Module discovery vs machine registry**:
- import-tree auto-discovers all `*.nix` files as flake-parts modules
- Clan maintains explicit machine registry
- Machine configurations must be both: discovered modules AND registry entries

**Two secrets systems**:
- Clan vars: system-level generated secrets
- sops-nix: user-level manual secrets
- Both use age encryption but different storage patterns

**Cross-platform consistency**:
- Clan inventory coordinates machines
- Dendritic home-manager modules should work across darwin and nixos
- Service instances span both platforms

### What needed to work together

```
┌─────────────────────────────────────────────────────────────┐
│                    flake.nix (minimal)                       │
│                    └── imports import-tree                   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    modules/ (dendritic)                      │
│  ├── clan/machines.nix    → clan.machines registry          │
│  ├── home/ai/             → flake.modules.homeManager.ai    │
│  ├── machines/darwin/     → flake.modules.darwin.*          │
│  └── machines/nixos/      → flake.modules.nixos.*           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 clan.machines.* registry                     │
│  └── imports from flake.modules.darwin/nixos                 │
└─────────────────────────────────────────────────────────────┘
```

## Decision

Integrate dendritic and clan via **namespace export → clan import** pattern where machine modules export to dendritic namespaces and clan registry imports from those namespaces.

### Pattern 1: Machine configuration export

Machine configurations export to `flake.modules.{darwin,nixos}.*` namespaces:

```nix
# modules/machines/darwin/stibnite/default.nix
{ config, ... }:
let
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  # Export machine config to dendritic namespace
  flake.modules.darwin."machines/darwin/stibnite" =
    { pkgs, lib, inputs, ... }:
    {
      imports = with flakeModules; [
        base
        ssh-known-hosts
      ];

      networking.hostName = "stibnite";

      # Home-manager imports from dendritic aggregates
      home-manager.users.crs58.imports = [
        flakeModulesHome."users/crs58"
        flakeModulesHome.ai
        flakeModulesHome.development
      ];
    };
}
```

Key insight: Machine config is a flake-parts module that exports to namespace.
File at `modules/machines/darwin/stibnite/` exports to `flake.modules.darwin."machines/darwin/stibnite"`.

### Pattern 2: Clan registry imports

Clan machine registry imports from dendritic namespaces:

```nix
# modules/clan/machines.nix
{ config, ... }:
{
  clan.machines = {
    stibnite = {
      nixpkgs.hostPlatform = "aarch64-darwin";
      # Import from dendritic namespace
      imports = [ config.flake.modules.darwin."machines/darwin/stibnite" ];
    };
    cinnabar = {
      nixpkgs.hostPlatform = "x86_64-linux";
      imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
    };
    # ... 6 more machines
  };
}
```

Two-step registration:
1. Machine module exports to `flake.modules.{darwin,nixos}.*`
2. Clan registry imports that exported module

This indirection enables:
- Dendritic auto-discovery of machine modules
- Explicit clan registry control
- Namespace consistency across the codebase

### Pattern 3: clanModules from dendritic namespaces

Clan service modules (clanModules) can import shared configuration from dendritic namespaces:

```nix
# modules/clan/inventory/services/ssh-known-hosts.nix
{ config, ... }:
{
  clan.inventory.instances.ssh-known-hosts = {
    module = { ... }: {
      # Import shared SSH config from dendritic namespace
      imports = [ config.flake.modules.common.ssh-known-hosts ];
    };
    roles.default.machines = {
      "cinnabar" = { };
      "electrum" = { };
      # ... all machines
    };
  };
}
```

Service configuration defined once in dendritic module, reused across clan inventory.

### Pattern 4: Two-tier secrets integration

**Tier 1: Clan vars** for system-level secrets:

```nix
# Generated by clan vars generate
# Stored in vars/<machine>/<service>/...
# Accessed via clan modules automatically
```

**Tier 2: sops-nix** for user-level secrets:

```nix
# modules/home/core/git.nix
{ config, inputs, ... }:
{
  flake.modules.homeManager.core = { ... }: {
    sops.secrets."users/${config.home.username}/github-signing-key" = {
      sopsFile = "${inputs.self}/secrets/users/${config.home.username}.sops.yaml";
    };
  };
}
```

**Age key reuse**: Same age keys work for both systems.
Machine keys derived from SSH host keys.
User keys stored in `~/.config/sops/age/keys.txt`.

### Pattern 5: Cross-platform module reuse

Home-manager modules work across darwin and nixos via dendritic aggregates:

```nix
# modules/home/ai/claude-code.nix - works on any platform
{ ... }:
{
  flake.modules.homeManager.ai = { pkgs, ... }: {
    home.packages = [ pkgs.claude-code ];
  };
}

# modules/machines/darwin/stibnite - darwin host
home-manager.users.crs58.imports = [ flakeModulesHome.ai ];

# modules/machines/nixos/cinnabar - nixos host
home-manager.users.cameron.imports = [ flakeModulesHome.ai ];
```

Same `ai` aggregate imported on both platforms.
Platform-specific logic handled within modules via `pkgs.stdenv.isDarwin`.

### Directory structure

```
modules/
├── clan/                    # Clan integration layer
│   ├── core.nix             # Clan flakeModule import
│   ├── machines.nix         # Machine registry (imports from namespaces)
│   └── inventory/           # Service instances
│       └── services/        # Per-service inventory
├── darwin/                  # Darwin modules (exported to flake.modules.darwin.*)
├── home/                    # Home-manager modules (exported to flake.modules.homeManager.*)
│   ├── ai/                  # AI tools aggregate
│   ├── core/                # Core settings aggregate
│   ├── development/         # Dev tools aggregate
│   └── users/               # Per-user modules
├── machines/                # Machine-specific (export to namespaces)
│   ├── darwin/              # Darwin hosts → flake.modules.darwin."machines/darwin/*"
│   └── nixos/               # NixOS hosts → flake.modules.nixos."machines/nixos/*"
├── nixos/                   # NixOS modules (exported to flake.modules.nixos.*)
└── system/                  # Cross-platform system modules
```

## Integration workflows

### Adding a new machine

1. Create machine module at `modules/machines/{darwin,nixos}/<hostname>/default.nix`
2. Export to namespace: `flake.modules.{darwin,nixos}."machines/{darwin,nixos}/<hostname>"`
3. Register in `modules/clan/machines.nix` importing from namespace
4. Add to relevant inventory services

File auto-discovered by import-tree, manually registered in clan.

### Adding a new feature

1. Create module at `modules/home/<aspect>/<feature>.nix`
2. Export to namespace: `flake.modules.homeManager.<aspect>`
3. Import in machine configs: `flakeModulesHome.<aspect>`

No clan changes needed - features flow through dendritic aggregates.

### Adding a new service

1. Create inventory file at `modules/clan/inventory/services/<service>.nix`
2. Define roles and machine assignments
3. Optionally import shared config from dendritic namespace

Service coordination via clan, shared config via dendritic.

## Consequences

### Positive

**Clear separation of concerns**:
- Dendritic: Module organization and auto-discovery
- Clan: Machine registry and deployment orchestration
- Each system does what it's designed for

**Namespace consistency**:
All configuration exports to `flake.modules.*` namespaces.
Machine configs, home modules, darwin modules all follow same pattern.
Predictable structure across entire codebase.

**Explicit integration points**:
`modules/clan/machines.nix` is THE integration point between dendritic and clan.
Easy to audit, easy to understand.
No hidden wiring.

**Feature modules remain portable**:
Home-manager aggregates don't know about clan.
Same `ai` module works on any machine, any platform.
Clan-specific coordination separate from feature implementation.

**Two-tier secrets complements both**:
Clan vars for generated system secrets.
sops-nix for user credentials.
Same age keys, different purposes.
Clean separation reduces confusion.

### Negative

**Two-step machine registration**:
Must export to namespace AND register in clan.
More steps than if clan directly auto-discovered machines.
Intentional trade-off for explicit control.

**Conceptual overhead**:
Understanding integration requires grasping both patterns.
Contributors need to know: dendritic namespaces AND clan registry.
Documentation critical.

**Namespace string conventions**:
`flake.modules.darwin."machines/darwin/stibnite"` uses string key with slash.
Convention must be followed consistently.
Typos cause silent failures.

**Split configuration sources**:
Machine definition in `modules/machines/`.
Machine registration in `modules/clan/machines.nix`.
Related files in different directories.

### Neutral

**Clan remains optional**:
Dendritic pattern works without clan (as proven in reference implementations).
Clan adds orchestration ON TOP of dendritic organization.
Could theoretically remove clan, keep dendritic structure.

**Home-manager unchanged**:
home-manager modules are standard NixOS home-manager modules.
Dendritic organization doesn't change how modules work internally.
Skills transfer from standard home-manager development.

**Flake-parts foundation**:
Both dendritic and clan are flake-parts modules.
Integration happens within flake-parts composition.
Standard flake-parts patterns apply.

## Validation evidence

### Initial validation (November 2024)

Integration validated in test-clan:

- blackphos migration proved darwin namespace export pattern
- Portable home modules extracted to dendritic aggregates
- Complete migration validated two-step machine registration
- Two-tier secrets architecture established
- Physical deployment validated end-to-end integration

Validation metrics:
- 3 machines integrated (darwin + nixos)
- 17 home-manager modules in dendritic aggregates
- Two-tier secrets operational

### Production migration (November 2024)

Production migration:

- 8 machines registered via pattern
- All machines use namespace export → clan import
- Home-manager aggregates shared across all users
- Secrets working across both tiers

### GCP infrastructure (December 2024)

GCP nodes validated pattern at scale:

- galena, scheelite added via standard pattern
- No pattern modifications needed
- Integration approach stable

## References

### Internal

- [Dendritic Architecture concept documentation](/concepts/dendritic-architecture)
- [Clan Integration concept documentation](/concepts/clan-integration)
- [ADR-0018: Dendritic flake-parts architecture](0018-dendritic-flake-parts-architecture/)
- [ADR-0019: Clan-core orchestration](0019-clan-core-orchestration/)
- [ADR-0011: SOPS secrets management](0011-sops-secrets-management/)
- [ADR-0017: Dendritic overlay patterns](0017-dendritic-overlay-patterns/)
- [Module System Primitives](/notes/development/modulesystem/primitives/) - deferredModule and evalModules foundations
- [Terminology Glossary](/notes/development/modulesystem/terminology-glossary/) - Module system terminology guide

### External

- [dendritic pattern](https://github.com/mightyiam/dendritic)
- [clan](https://github.com/clan-lol/clan-core)
- [nixpkgs.molybdenum.software-dendritic-clan](https://github.com/nixpkgs-community/nixpkgs.molybdenum.software) - Dendritic + clan combination reference
