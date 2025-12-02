---
title: Dendritic Flake-Parts Architecture
description: Understanding the dendritic pattern where every Nix file is a flake-parts module organized by aspect
---

This infrastructure uses the **dendritic flake-parts pattern**, a module organization approach where every Nix file is a flake-parts module and configuration is organized by *aspect* (feature) rather than by *host*.

## Credits and attribution

The dendritic flake-parts pattern was created and documented by **Shahar "Dawn" Or** ([@mightyiam](https://github.com/mightyiam)), establishing a configuration approach where every Nix file is a flake-parts module organized by feature rather than host.

### Foundational projects

- **[flake-parts](https://flake.parts)** by Robert Hensing and Hercules CI - The modular flake framework that enables the dendritic pattern

- **[dendritic](https://github.com/mightyiam/dendritic)** by Shahar "Dawn" Or - Pattern definition, documentation, and reference implementation

- **[import-tree](https://github.com/vic/import-tree)** by Victor Borja (@vic) - Automatic module discovery mechanism that makes dendritic practical at scale

- **[dendrix](https://vic.github.io/dendrix/Dendritic.html)** by Victor Borja - Community ecosystem, comprehensive documentation, and dendritic module distribution

## Core principle

Every Nix file in the repository is a flake-parts module.
Files are organized by **aspect** (feature) rather than by **host**, enabling cross-cutting configuration that spans NixOS, nix-darwin, and home-manager from a single location.

### Traditional vs dendritic organization

**Traditional (host-based)**:
```
configurations/
├── stibnite.nix      # Everything for stibnite
├── blackphos.nix     # Everything for blackphos
└── cinnabar.nix      # Everything for cinnabar
```

Problems: Duplication across hosts, hard to share features, changes require editing multiple files.

**Dendritic (aspect-based)**:
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

## Module structure

### Dendritic module pattern

Every file exports to a namespace under `flake.modules.*`:

```nix
# modules/home/tools/bottom.nix
{ ... }:
{
  flake.modules.homeManager.tools-bottom = { ... }: {
    programs.bottom.enable = true;
  };
}
```

The module:
- Lives at `modules/home/tools/bottom.nix`
- Exports as `flake.modules.homeManager.tools-bottom`
- Can be imported by any home-manager configuration

### Aggregate modules

Related features are grouped into aggregates:

```nix
# modules/home/_aggregates.nix
{ config, ... }:
{
  flake.modules.homeManager = {
    aggregate-ai = {
      imports = with config.flake.modules.homeManager; [
        ai-claude-code
        ai-mcp-servers
        ai-llm-wrappers
      ];
    };
    aggregate-development = {
      imports = with config.flake.modules.homeManager; [
        development-git
        development-editors
        development-languages
      ];
    };
  };
}
```

Machine configurations import aggregates, not individual modules:

```nix
# modules/machines/darwin/stibnite.nix
{
  home-manager.users.crs58 = {
    imports = with config.flake.modules.homeManager; [
      aggregate-ai
      aggregate-development
      aggregate-shell
    ];
  };
}
```

## Auto-discovery via import-tree

The [import-tree](https://github.com/vic/import-tree) mechanism automatically discovers and imports all modules without manual registration.

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

### vs nixos-unified (deprecated)

nixos-unified used directory-based "autowiring" where file paths mapped to flake outputs:
- `configurations/darwin/stibnite.nix` → `darwinConfigurations.stibnite`
- Host-centric organization
- Required specific directory names

Dendritic uses aspect-based organization with explicit module exports:
- Any file can export any module type
- Feature-centric organization
- Directory names are semantic, not required

### vs pure flake-parts

Pure flake-parts requires manual imports in `flake.nix`.
Dendritic adds import-tree for automatic discovery, making it practical for large configurations.

### vs monolithic configurations

Monolithic approaches put all configuration in a few large files.
Dendritic enables fine-grained modules that can be composed, reused, and tested independently.

## Integration with clan

Clan coordinates multi-machine deployments while dendritic organizes the modules being deployed.
They're orthogonal patterns that work together.

See [Clan Integration](clan-integration) for how clan orchestrates deployments of dendritic-organized configurations.

## Practical examples

### Adding a new tool to all users

Create `modules/home/tools/newtool.nix`:

```nix
{ ... }:
{
  flake.modules.homeManager.tools-newtool = { pkgs, ... }: {
    home.packages = [ pkgs.newtool ];
    programs.newtool = {
      enable = true;
      settings = { ... };
    };
  };
}
```

Add to relevant aggregate:

```nix
# In aggregate definition
aggregate-development = {
  imports = with config.flake.modules.homeManager; [
    # ... existing
    tools-newtool
  ];
};
```

All users importing `aggregate-development` now have `newtool`.

### Adding a new darwin host

Create `modules/machines/darwin/newhost.nix`:

```nix
{ config, ... }:
{
  flake.darwinConfigurations.newhost =
    config.lib.mkDarwinConfiguration {
      system = "aarch64-darwin";
      modules = [
        config.flake.modules.darwin.core
        config.flake.modules.darwin.apps
      ];
      home-manager.users.myuser = {
        imports = with config.flake.modules.homeManager; [
          aggregate-core
          aggregate-development
        ];
      };
    };
}
```

The host automatically:
- Gets all darwin modules specified
- Gets all home-manager aggregates for the user
- Is available as `darwinConfigurations.newhost`

## External resources

- [Dendritic pattern documentation](https://vic.github.io/dendrix/Dendritic.html) - Comprehensive explanation by Victor Borja
- [mightyiam/dendritic](https://github.com/mightyiam/dendritic) - Original pattern definition
- [flake.parts](https://flake.parts) - Foundation framework documentation
- [vic/import-tree](https://github.com/vic/import-tree) - Auto-discovery mechanism

## See also

- [Clan Integration](clan-integration) - Multi-machine coordination with clan-core
- [Repository Structure](/reference/repository-structure) - Complete directory layout
