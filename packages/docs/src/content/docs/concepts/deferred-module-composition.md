---
title: Deferred module composition
description: Understanding deferred module composition where every Nix file is a module organized by aspect
sidebar:
  order: 5
---

This infrastructure uses **deferred module composition** (a popular approach referred to as the dendritic flake-parts pattern), where every Nix file is a flake-parts module that exports deferredModule values (configuration fragments stored for later evaluation by consumers like NixOS, nix-darwin, or home-manager), and configuration is organized by *aspect*—a cross-cutting concern that spans multiple configuration classes (NixOS, nix-darwin, home-manager) rather than being confined to a single host.
The pattern leverages the Nix module system's fixpoint semantics to enable compositional configuration across platforms.
See [Why "aspect"](#why-aspect) below for the full rationale behind this terminology.

## Credits and attribution

This deferred module composition pattern correpsonds to a configuration approach where every Nix file is a flake-parts module organized by feature rather than host.

### Dependencies

- **[flake-parts](https://flake.parts)** by Robert Hensing (@roberth) and Hercules CI (@hercules-ci) - The modular flake framework that enables defining and integrating deferred modules to configure multiple systems
- **[import-tree](https://github.com/vic/import-tree)** by Victor Borja (@vic) - Automatic module discovery mechanism from a given directory subtree

### Example projects

- **[drupol/infra](https://github.com/drupol/infra)** by Pol Dellaiera (@drupol) - Uses flake-parts based deferred modules and illustrates the "aspect"-based factorization of dependencies.
- **[GaetanLepage/nix-config](https://github.com/GaetanLepage/nix-config)** by Gaétan Lepage (@GaetanLepage) - Uses flake-parts based deferred modules and illustrates configuration of a host posessing a GPU.

### Reference documentation

- **[dendrix](https://vic.github.io/dendrix/Dendritic.html)** by Victor Borja (@vic) - Community ecosystem, documentation, and dendritic module "distribution"
- **[dendritic](https://github.com/mightyiam/dendritic)** by Shahar "Dawn" Or (@mightyiam) - "Awesome" dendritic flake-parts

## Why "aspect"

The term "aspect" in this context refers to a cross-cutting concern or feature that spans multiple configuration classes (NixOS, nix-darwin, home-manager).
This terminology draws from [Aspect-Oriented Programming (AOP)](https://en.wikipedia.org/wiki/Aspect-oriented_programming), where "aspects" are program functionalities that cut across multiple modules without clean encapsulation in any single component.
We use "aspect" rather than simply "feature" to emphasize this cross-cutting nature: an aspect isn't confined to a single host or platform, it's a concern that applies broadly across your infrastructure.

In the dendritic pattern, an aspect is a unified capability defined once and applied across relevant platforms.
Rather than defining SSH configuration separately for each host, the "SSH aspect" configures SSH across NixOS (server setup), nix-darwin (builtin ssh client), and home-manager (client config) from a single location.
This aspect-oriented organization eliminates duplication and makes features composable.

**Key characteristics of an aspect:**

- Defined once in a dedicated module (e.g., `modules/home/shell/zsh.nix` for the zsh aspect)
- Spans multiple configuration classes where relevant (may configure NixOS, darwin, and home-manager from the same file)
- Automatically available to all hosts that import it (no per-host duplication)
- Can have platform-specific implementations while maintaining unified intent (e.g., a scrolling-desktop aspect using niri on Linux, different tooling on macOS)

This aspect-based organization is the key difference from traditional host-centric configuration, where all settings for a host live together regardless of their purpose.

## Core principle

Every Nix file in the repository is a flake-parts module (evaluated at the top level with class "flake") that exports deferredModule values (evaluated later when consumers import them).
This means modules delay evaluation until the final configuration is computed, enabling them to reference merged results without circular dependencies.

Files are organized by **aspect** (feature) rather than by **host**, enabling cross-cutting configuration that spans NixOS, nix-darwin, and home-manager from a single location.
The module system's fixpoint computation resolves these cross-cutting references into a coherent configuration.

### The two-layer architecture

In the dendritic pattern, every file participates in two distinct evaluation contexts:

**Outer layer (the file itself)**: A flake-parts module evaluated with `class = "flake"`.
The file's top-level function is called immediately during the collection phase of the top-level `evalModules`.

**Inner layer (stored values)**: deferredModule values assigned to `flake.modules.<class>.<name>`.
These values are NOT evaluated by the top-level evalModules—they're collected into an imports list via the deferredModule type's merge function and only evaluated when a consumer (NixOS, nix-darwin, home-manager) imports them into their own `evalModules` call.

Example file `modules/home/tools/bat.nix`:

```nix
# OUTER: This entire file IS a flake-parts module (evaluated immediately)
{ ... }:
{
  # INNER: This VALUE is a deferredModule (evaluated later by home-manager)
  flake.modules.homeManager.tools = { ... }: {
    programs.bat.enable = true;
  };
}
```

The outer module function executes during flake evaluation.
The inner value (`{ ... }: { programs.bat.enable = true; }`) is stored without evaluation.
When a home-manager configuration imports `flakeModulesHome.tools`, *then* that inner module is evaluated with home-manager's `config`, `pkgs`, etc.

### Understanding the mechanism

The dendritic pattern works because of three compositional layers:

**Layer 0: Module system foundation** (nixpkgs `lib.evalModules`)

Module functions are called immediately during the collection phase, receiving a `config` argument that is a lazy reference to the final fixpoint result.
The "deferral" is in the lazy evaluation of config values, not in suspending function calls.
When you write `{ config, ... }: { ... }`, the `config` argument refers to the final merged configuration after all modules have been evaluated together.
The module system computes this fixpoint via lazy evaluation, resolving cross-module dependencies without infinite recursion as long as there are no strict cycles.

**Layer 1: Flake-parts framework**

Flake-parts wraps `evalModules` for flake outputs, providing:

- The `flake.modules.*` namespace convention for organizing deferred modules by class (darwin, nixos, homeManager)
- The `perSystem` abstraction for per-architecture evaluation
- Integration with flake schema (packages, apps, devShells, etc.)

**Layer 2: Aspect-based organization**

This deferred module composition pattern adds organizational conventions to flake-parts:

- Auto-discovery via import-tree (automatically populate evalModules imports list from directory tree)
- Directory-based namespace merging (multiple files → single aggregate via deferredModule composition)
- Aspect-oriented structure (organize by feature, not by host)

The key insight: this is an organizational pattern for deferred modules, not a fundamentally different abstraction.
The composition works because the module system orchestrates two complementary algebraic structures: at the type level, deferredModule values form a monoid under imports list concatenation (enabling order-independent module collection), while at the semantic level, merged configuration values form a join-semilattice after fixpoint computation (enabling declarative configuration merging with priority overrides).

For detailed explanation of module system primitives, see [Module System Primitives](/concepts/module-system-primitives/).
For how flake-parts uses these primitives, see [Flake-parts as Module System Abstraction](/concepts/flake-parts-module-system/).

### Traditional vs aspect-based organization

**Traditional (host-based)**:

```
configurations/
├── stibnite.nix      # Everything for stibnite
├── blackphos.nix     # Everything for blackphos
└── cinnabar.nix      # Everything for cinnabar
```

Problems: Duplication across hosts, hard to share features, changes require editing multiple files.

**Aspect-based**:

```
modules/
├── darwin/
│   └── defaults.nix       # macOS defaults for ALL darwin hosts
├── home/
│   ├── ai/                # AI tooling for ALL users
│   ├── development/       # Dev tools for ALL users
│   └── shell/             # Shell config for ALL users
├── nixos/
│   └── services/          # Services for ALL nixos hosts
└── machines/
    ├── darwin/stibnite.nix    # Stibnite-specific only
    └── nixos/cinnabar.nix     # Cinnabar-specific only
```

Benefits: Features defined once, automatically available across all relevant hosts.
Machine-specific configs contain only truly unique settings.

## Module structure and composition

The module system's deferredModule type enables namespace merging: multiple files can export to the same namespace, and the module system automatically composes them via its merge semantics.

### Deferred module pattern with namespace merging

Every file exports to a namespace under `flake.modules.*`, and files within the same directory automatically merge into a shared namespace:

```nix
# modules/home/tools/bottom.nix
{ ... }:
{
  flake.modules.homeManager.tools = { ... }: {
    programs.bottom = {
      enable = true;
      settings = {
        flags.enable_gpu_memory = true;
        # ... configuration
      };
    };
  };
}

# modules/home/tools/pandoc.nix
{ ... }:
{
  flake.modules.homeManager.tools = { ... }: {
    programs.pandoc.enable = true;
  };
}
```

The key insight:

- Both files live in `modules/home/tools/`
- Both export to the same namespace: `flake.modules.homeManager.tools`
- The module system's deferredModule type merges them into a single aggregate (deferredModule forms a monoid under concatenation)
- import-tree auto-discovers files and adds them to evalModules imports list
- No manual aggregate definition needed - directory structure + module system merging creates the namespace
- Each file contributes different programs to the same aggregate module

### Directory-based aggregation

Related features are automatically grouped by directory structure without requiring explicit aggregate definitions.
Each directory becomes an aggregate through import-tree's auto-discovery and namespace merging:

```nix
# modules/home/configurations.nix - imports directory aggregates
{ config, ... }:
{
  # Force module loading order - aggregates processed before homeConfigurations
  # Multi-aggregate organization (drupol-style):
  #   - core: base config (catppuccin, fonts, bitwarden, xdg, session-variables, ssh)
  #   - development: dev environment (git, jujutsu, neovim, wezterm, zed, starship, zsh)
  #   - ai: AI-assisted tools (claude-code, mcp-servers, glm wrappers, ccstatusline)
  #   - shell: shell/terminal environment (atuin, yazi, zellij, tmux, bash, nushell)
  #   - packages: organized package sets (terminal, development, compute, security, database, publishing)
  #   - terminal: terminal utilities (direnv, fzf, lsd, bat, btop, htop, jq, nix-index, zoxide)
  #   - tools: additional tools (awscli, k9s, pandoc, nix, gpg, macchina, tealdeer, texlive)
  imports = [
    ./core
    ./development
    ./ai
    ./shell
    ./packages
    ./terminal
    ./tools
    ./users
  ];
}
```

How it works:

- Each directory import (e.g., `./ai`) triggers import-tree to discover all `*.nix` files inside
- Files in `ai/` that export to `flake.modules.homeManager.ai` auto-merge into a single aggregate
- No explicit aggregate definition needed - the directory IS the aggregate boundary
- Machine configurations can import entire aggregates or specific parts

Machine configurations import aggregates by referencing the auto-merged namespace:

```nix
# modules/machines/darwin/stibnite/default.nix
{
  home-manager.users.crs58.imports = [
    flakeModulesHome."users/crs58"
    flakeModulesHome.base-sops
    # Import aggregate modules for crs58
    # All aggregates via auto-merge
    flakeModulesHome.ai          # All files from modules/home/ai/*
    flakeModulesHome.core        # All files from modules/home/core/*
    flakeModulesHome.development # All files from modules/home/development/*
    flakeModulesHome.packages    # All files from modules/home/packages/*
    flakeModulesHome.shell       # All files from modules/home/shell/*
    flakeModulesHome.terminal    # All files from modules/home/terminal/*
    flakeModulesHome.tools       # All files from modules/home/tools/*
  ];
}
```

## Auto-discovery via import-tree

The [import-tree](https://github.com/vic/import-tree) mechanism automatically discovers modules and adds them to the module system's imports list.
This leverages the module system's recursive import expansion: evalModules processes the `imports` option to discover all modules transitively.

### How it works

```nix
# flake.nix
{
  imports = [
    inputs.import-tree.flakeModule
  ];

  # Auto-discover all modules
  flake.autoImport = {
    path = ./modules;
    exclude = name: name == "README.md";
  };
}
```

This scans `modules/` recursively and imports every `.nix` file as a flake-parts module.

**Module system integration**:

What import-tree does:

1. Recursively scans `./modules` for all `.nix` files
2. Adds them to a top-level `imports` list passed to evalModules

What the module system does:

1. Processes the imports list via `collectModules` (recursive expansion, disabledModules filtering)
2. Merges modules via `mergeModules` (option declarations + definitions)
3. Computes fixpoint where `config` refers to final merged result
4. Returns configuration with all modules composed

The composition is lazy: module functions execute immediately during collection, but the config values they reference are evaluated on demand, enabling circular-looking references (module A references config set by module B, which references config set by module A) to resolve via fixpoint as long as there are no strict cycles.

### Benefits over manual registration

- **No flake.nix updates**: Add a file, it's automatically included
- **Predictable structure**: File path determines module location
- **Scales gracefully**: Works with 10 modules or 500 modules
- **Self-documenting**: Directory tree is the module registry

## Directory structure

```
modules/
├── clan/              # Clan integration (machines, inventory, services)
│   ├── core.nix       # Clan flakeModule import
│   ├── machines.nix   # Machine registry
│   └── inventory/     # Service instances and roles
├── darwin/            # nix-darwin modules (per-aspect)
│   ├── core/          # Core darwin settings
│   ├── apps/          # Application configurations
│   └── homebrew/      # Homebrew cask management
├── home/              # home-manager modules (per-aspect)
│   ├── ai/            # AI tools (claude-code, MCP servers)
│   ├── core/          # Core settings (XDG, SSH, fonts)
│   ├── development/   # Dev environment (git, editors, languages)
│   ├── shell/         # Shell configuration (zsh, fish, nushell)
│   └── users/         # User-specific modules
├── machines/          # Machine-specific configurations
│   ├── darwin/        # Darwin hosts (stibnite, blackphos, rosegold, argentum)
│   └── nixos/         # NixOS hosts (cinnabar, electrum, galena, scheelite)
├── nixos/             # NixOS modules (per-aspect)
│   ├── core/          # Core NixOS settings
│   └── services/      # System services
├── system/            # Cross-platform system modules
└── terranix/          # Cloud infrastructure (Hetzner, GCP)
```

## Comparison with other patterns

### vs nixos-unified

nixos-unified used directory-based "autowiring" where file paths mapped to flake outputs:

- `configurations/darwin/stibnite.nix` → `darwinConfigurations.stibnite`
- Host-centric organization
- Required specific directory names

This deferred module composition pattern uses aspect-based organization:

- Any file can export deferred modules to any namespace (flake-parts convention)
- Feature-centric organization enabled by module system's compositional semantics
- Directory names are semantic, not required (import-tree discovers based on file existence)
- Composition works via deferredModule monoid structure, not directory autowiring

### vs pure flake-parts

Pure flake-parts requires manual imports in `flake.nix` to populate the module system's imports list.
This deferred module composition pattern adds import-tree for automatic discovery of modules, making it practical for large configurations.

Both use the same underlying module system primitives (deferredModule type, evalModules fixpoint).
This pattern adds organizational conventions (directory-based namespace merging, auto-discovery) on top of flake-parts' module system integration.

### vs monolithic configurations

Monolithic approaches put all configuration in a few large files.
This deferred module composition pattern enables fine-grained modules that can be composed, reused, and tested independently.

## Integration with clan

Clan coordinates multi-machine deployments while this deferred module composition pattern organizes the modules being deployed.
The integration works because both use the same module system foundation: clan calls nixosSystem or darwinSystem (which call evalModules), importing deferred modules from `flake.modules.*` namespaces.

This pattern exports deferred modules → clan imports them → evalModules resolves fixpoint with clan's arguments (system, config, pkgs, etc.).

See [Clan Integration](/concepts/clan-integration/) for how clan orchestrates deployments of configurations organized with this pattern.

## Practical examples

### Adding a new tool to all users

Create `modules/home/tools/newtool.nix`:

```nix
{ ... }:
{
  flake.modules.homeManager.tools = { pkgs, ... }: {
    home.packages = [ pkgs.newtool ];
    programs.newtool = {
      enable = true;
      settings = { ... };
    };
  };
}
```

That's it!
The file is automatically discovered by import-tree, merged into the `tools` aggregate with other files in `modules/home/tools/`, and available to all users importing `flakeModulesHome.tools`.
No manual aggregate registration needed.

### Adding a new darwin host

Machine configuration is a two-step process: export as module, then register with clan.

**Step 1:** Create `modules/machines/darwin/newhost/default.nix` exporting machine configuration:

```nix
{ config, ... }:
let
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  # Export as flake.modules.darwin."machines/darwin/newhost"
  flake.modules.darwin."machines/darwin/newhost" =
    { pkgs, lib, inputs, ... }:
    {
      imports = [
        inputs.home-manager.darwinModules.home-manager
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
      ]);

      networking.hostName = "newhost";
      nixpkgs.hostPlatform = "aarch64-darwin";

      # User configuration
      users.users.myuser = {
        home = "/Users/myuser";
        shell = pkgs.zsh;
      };

      # Home-Manager for myuser
      home-manager.users.myuser.imports = [
        flakeModulesHome."users/myuser"
        flakeModulesHome.base-sops
        # Import aggregates
        flakeModulesHome.ai
        flakeModulesHome.core
        flakeModulesHome.development
        flakeModulesHome.shell
      ];
    };
}
```

**Step 2:** Register in `modules/clan/machines.nix`:

```nix
{ config, ... }:
{
  clan.machines = {
    # ... existing machines
    newhost = {
      imports = [ config.flake.modules.darwin."machines/darwin/newhost" ];
    };
  };
}
```

The host is now:

- Available as `clan.machines.newhost` for clan orchestration
- Composed from auto-merged directory aggregates
- Ready for deployment with `clan machines update newhost`

## External resources

- [Dendritic pattern documentation](https://vic.github.io/dendrix/Dendritic.html) - Comprehensive explanation by Victor Borja
- [mightyiam/dendritic](https://github.com/mightyiam/dendritic) - Original pattern definition
- [flake.parts](https://flake.parts) - Foundation framework documentation
- [vic/import-tree](https://github.com/vic/import-tree) - Auto-discovery mechanism

## Module system foundations

Understanding the algebraic primitives that enable this deferred module composition pattern:

- [Module System Primitives](/concepts/module-system-primitives/) - Detailed deferredModule and evalModules explanation with three-tier (intuitive/computational/formal) treatment
- [Flake-parts as Module System Abstraction](/concepts/flake-parts-module-system/) - What flake-parts adds to the module system (perSystem, namespace conventions, class-based organization)
- [Terminology Glossary](/development/context/glossary/) - Quick reference for module system vs flake-parts vs dendritic terminology

## See also

- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination with clan
- [Repository Structure](/reference/repository-structure) - Complete directory layout
- [Adding Custom Packages](/guides/adding-custom-packages/) - Practical guide to package customization
- [Handling Broken Packages](/guides/handling-broken-packages/) - Fixing broken packages from nixpkgs
- [ADR-0018: Dendritic Flake-Parts Architecture](/development/architecture/adrs/0018-dendritic-flake-parts-architecture/) - Architectural decision record
- [ADR-0020: Dendritic + Clan Integration](/development/architecture/adrs/0020-dendritic-clan-integration/) - Integration patterns ADR
