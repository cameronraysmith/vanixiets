---
title: Dendritic Flake-Parts Architecture
description: Understanding the dendritic pattern where every Nix file is a flake-parts module organized by aspect
---

This infrastructure uses the **dendritic flake-parts pattern**, a module organization approach where every Nix file is a flake-parts module and configuration is organized by *aspect* (feature) rather than by *host*.

## Credits and attribution

The dendritic flake-parts pattern was created and documented by Shahar "Dawn" Or (@mightyiam), establishing a configuration approach where every Nix file is a flake-parts module organized by feature rather than host.

### Foundational projects

- **[flake-parts](https://flake.parts)** by Robert Hensing (@roberth) and Hercules CI - The modular flake framework that enables the dendritic pattern

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

### Dendritic module pattern with namespace merging

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
- import-tree auto-merges them into a single `tools` aggregate
- No manual aggregate definition needed - directory structure creates the namespace
- Each file contributes different programs to the same aggregate module

### Directory-based aggregation

Related features are automatically grouped by directory structure without requiring explicit aggregate definitions.
Each directory becomes an aggregate through import-tree's auto-discovery and namespace merging:

```nix
# modules/home/configurations.nix - imports directory aggregates
{ config, ... }:
{
  # Force module loading order - aggregates processed before homeConfigurations
  # Pattern A multi-aggregate organization (drupol-style):
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
    # Pattern A: All aggregates via auto-merge
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

See [Clan Integration](/concepts/clan-integration/) for how clan orchestrates deployments of dendritic-organized configurations.

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

## See also

- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination with clan
- [Repository Structure](/reference/repository-structure) - Complete directory layout
- [Adding Custom Packages](/guides/adding-custom-packages/) - Practical guide to package customization
- [Handling Broken Packages](/guides/handling-broken-packages/) - Fixing broken packages from nixpkgs
- [ADR-0018: Dendritic Flake-Parts Architecture](/development/architecture/adrs/0018-dendritic-flake-parts-architecture/) - Architectural decision record
- [ADR-0020: Dendritic + Clan Integration](/development/architecture/adrs/0020-dendritic-clan-integration/) - Integration patterns ADR
