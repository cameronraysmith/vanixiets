---
title: Repository Structure
description: Directory layout for deferred module composition + clan architecture
sidebar:
  order: 2
---

Complete reference for the repository structure using deferred module composition organization with clan integration.

## Directory tree

```
vanixiets/
├── modules/             # Deferred module composition modules (auto-discovered)
│   ├── clan/            # Clan integration
│   │   ├── core.nix     # Clan flakeModule import
│   │   ├── machines.nix # Machine registry
│   │   ├── meta.nix     # Clan metadata
│   │   └── inventory/   # Service instances and roles
│   ├── darwin/          # nix-darwin modules (per-aspect)
│   │   ├── core/        # Core darwin settings
│   │   ├── apps/        # Application configurations
│   │   └── homebrew/    # Homebrew cask management
│   ├── home/            # home-manager modules (per-aspect)
│   │   ├── ai/          # AI tooling (claude-code, MCP servers)
│   │   ├── core/        # Core settings (XDG, SSH, fonts)
│   │   ├── development/ # Dev tools (git, editors, languages)
│   │   ├── shell/       # Shell configuration
│   │   ├── tools/       # Miscellaneous tools
│   │   ├── packages/    # Package bundles
│   │   ├── users/       # User-specific modules
│   │   └── _aggregates.nix  # Module composition
│   ├── machines/        # Machine-specific configurations
│   │   ├── darwin/      # Darwin hosts
│   │   │   ├── stibnite.nix
│   │   │   ├── blackphos.nix
│   │   │   ├── rosegold.nix
│   │   │   └── argentum.nix
│   │   └── nixos/       # NixOS hosts
│   │       ├── cinnabar.nix
│   │       ├── electrum.nix
│   │       ├── galena.nix
│   │       └── scheelite.nix
│   ├── nixos/           # NixOS modules (per-aspect)
│   │   ├── core/        # Core NixOS settings
│   │   └── services/    # System services
│   ├── nixpkgs/         # Nixpkgs configuration
│   │   ├── configuration.nix
│   │   ├── compose.nix   # Overlay composition into flake.overlays.default
│   │   ├── overlays-option.nix  # flake.nixpkgsOverlays declaration
│   │   ├── per-system.nix   # Per-system nixpkgs configuration
│   │   └── overlays/    # Overlay modules (auto-discovered, appended to list)
│   │       ├── channels.nix  # Multi-channel nixpkgs access
│   │       ├── stable-fallbacks.nix  # Platform-specific stable fallbacks
│   │       ├── overrides.nix  # Per-package build modifications
│   │       ├── nvim-treesitter.nix  # nvim-treesitter-main external overlay
│   │       ├── fish-stable-darwin.nix  # Darwin-specific stable fallback
│   │       └── nuenv.nix  # Nushell utilities external overlay
│   ├── system/          # Cross-platform system modules
│   └── terranix/        # Infrastructure as code
│       ├── base.nix     # Common infrastructure
│       ├── hetzner.nix  # Hetzner VPS definitions
│       └── gcp.nix      # GCP VM definitions
├── pkgs/                # Custom package derivations
│   └── by-name/         # pkgs-by-name pattern
│       ├── atuin-format/
│       ├── beads-viewer/
│       ├── markdown-tree-parser/
│       └── starship-jj/
├── vars/                # Clan vars (generated secrets)
│   └── per-machine/     # Machine-specific vars
├── secrets/             # sops-nix secrets (manual)
│   ├── hosts/           # Host-specific secrets
│   └── users/           # User-specific secrets
├── lib/                 # Shared library functions
│   └── default.nix      # → flake.lib
├── packages/            # Standalone packages
│   └── docs/            # Starlight documentation site
├── scripts/             # Maintenance and utility scripts
├── docs/                # Symlink to packages/docs/src/content/docs
└── .github/             # GitHub Actions workflows
```

## Machine fleet

### Darwin hosts (nix-darwin)

| File | Machine | User | Description |
|------|---------|------|-------------|
| `modules/machines/darwin/stibnite.nix` | stibnite | crs58 | Primary workstation |
| `modules/machines/darwin/blackphos.nix` | blackphos | raquel, crs58 | Secondary workstation |
| `modules/machines/darwin/rosegold.nix` | rosegold | janettesmith, cameron | Family workstation |
| `modules/machines/darwin/argentum.nix` | argentum | christophersmith, cameron | Family workstation |

**Deployment**: `clan machines update <hostname>`

### NixOS hosts

| File | Machine | Type | Description |
|------|---------|------|-------------|
| `modules/machines/nixos/cinnabar.nix` | cinnabar | Hetzner VPS | Zerotier controller |
| `modules/machines/nixos/electrum.nix` | electrum | Hetzner VPS | Server |
| `modules/machines/nixos/galena.nix` | galena | GCP VM | CPU compute (togglable) |
| `modules/machines/nixos/scheelite.nix` | scheelite | GCP VM | GPU compute (togglable) |

**Deployment**: `clan machines update <hostname>`

## Module organization

### Deferred module composition modules (auto-discovered)

Every file in `modules/` is a flake-parts module, auto-discovered via import-tree.
File path determines module organization, not flake output names.

```nix
# modules/home/tools/bottom.nix
{ ... }:
{
  flake.modules.homeManager.tools-bottom = { ... }: {
    programs.bottom.enable = true;
  };
}
```

### Module aggregates

Related modules composed into aggregates for easier imports:

```nix
# modules/home/_aggregates.nix
flake.modules.homeManager = {
  aggregate-ai = { imports = with config.flake.modules.homeManager; [ ai-claude-code ai-mcp-servers ]; };
  aggregate-development = { imports = with config.flake.modules.homeManager; [ development-git development-editors ]; };
  aggregate-shell = { imports = with config.flake.modules.homeManager; [ shell-zsh shell-starship ]; };
};
```

Machine configs import aggregates:

```nix
# modules/machines/darwin/stibnite.nix
home-manager.users.crs58.imports = with config.flake.modules.homeManager; [
  aggregate-core
  aggregate-ai
  aggregate-development
  aggregate-shell
];
```

## Clan integration

### Machine registry

```nix
# modules/clan/machines.nix
clan.machines = {
  stibnite = {
    nixpkgs.hostPlatform = "aarch64-darwin";
    imports = [ config.flake.modules.darwin."machines/darwin/stibnite" ];
  };
  cinnabar = {
    nixpkgs.hostPlatform = "x86_64-linux";
    imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
  };
};
```

### Inventory services

```nix
# modules/clan/inventory/services/zerotier.nix
inventory.instances.zerotier = {
  roles.controller.machines."cinnabar" = { };
  roles.peer.machines = {
    "electrum" = { };
    "stibnite" = { };
    "blackphos" = { };
    "rosegold" = { };
    "argentum" = { };
    "galena" = { };
    "scheelite" = { };
  };
};
```

## Overlay architecture

### Overlay composition

All overlays are collected into `flake.nixpkgsOverlays` via deferred module composition list concatenation, then composed in order using `lib.composeManyExtensions`, followed by merging custom packages:

```nix
# modules/nixpkgs/compose.nix - composed via lib.composeManyExtensions
[
  channels.nix              # Multi-channel nixpkgs access (stable, unstable, patched)
  stable-fallbacks.nix      # Platform-specific stable fallbacks
  overrides.nix             # Per-package build modifications
  nvim-treesitter.nix       # External overlay: nvim-treesitter-main
  nuenv.nix                 # External overlay: nushell utilities
  fish-stable-darwin.nix    # External overlay: darwin-specific stable fallback
] // customPackages         # Merge pkgs-by-name derivations
```

Each overlay module appends to `flake.nixpkgsOverlays` via:
```nix
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    inputs.flakeInput.overlays.exported
  ];
}
```

This pattern enables both internal overlays (pure functions) and external overlays (from flake inputs) to be composed together without hardcoding input selection at the point of composition.

### Custom packages

Packages defined using pkgs-by-name pattern:

| Package | Location | Description |
|---------|----------|-------------|
| atuin-format | `pkgs/by-name/atuin-format/` | Atuin history formatter |
| beads-viewer | `pkgs/by-name/beads-viewer/` | TUI for Beads issue tracker |
| markdown-tree-parser | `pkgs/by-name/markdown-tree-parser/` | Markdown tree parser |
| starship-jj | `pkgs/by-name/starship-jj/` | Starship jj plugin |

Note: ccstatusline was previously a custom package but is now sourced from the llm-agents flake input.

## Secrets structure

### Clan vars (system secrets)

```
vars/
├── per-machine/
│   ├── cinnabar/
│   │   ├── zerotier/    # Zerotier identity
│   │   └── ssh/         # SSH host keys
│   └── electrum/
│       └── ...
```

Generated via `clan vars generate`, encrypted with machine age keys.

### sops-nix (legacy user secrets)

```
secrets/
├── hosts/
│   └── cinnabar.sops.yaml
├── users/
│   ├── crs58.sops.yaml
│   ├── raquel.sops.yaml
│   └── cameron.sops.yaml
└── .sops.yaml           # Encryption rules
```

Manually created, encrypted with user age keys.

## Infrastructure as code

### Terranix modules

```nix
# modules/terranix/hetzner.nix
resource.hcloud_server.cinnabar = {
  name = "cinnabar";
  server_type = "cx22";
  image = "ubuntu-24.04";
};

# modules/terranix/gcp.nix
resource.google_compute_instance.galena = {
  name = "galena";
  machine_type = "e2-standard-8";
  zone = "us-west1-b";
};
```

**Deployment**: `nix run .#terraform -- apply`

## Key flake outputs

### Configurations

| Output | Command |
|--------|---------|
| `darwinConfigurations.stibnite` | `clan machines update stibnite` |
| `darwinConfigurations.blackphos` | `clan machines update blackphos` |
| `nixosConfigurations.cinnabar` | `clan machines update cinnabar` |
| `homeConfigurations.crs58` | `nh home switch` |

### Packages

| Output | Description |
|--------|-------------|
| `packages.${system}.claude-code-bin` | Claude Code (from llm-agents) |
| `packages.${system}.activate` | Configuration activation script |
| `packages.${system}.atuin-format` | Atuin history formatter |
| `packages.${system}.starship-jj` | Starship jj plugin |

### Development

| Output | Command |
|--------|---------|
| `devShells.${system}.default` | `nix develop` |
| `checks.${system}.pre-commit` | `nix flake check` |

## Directory naming conventions

### Underscore prefix

Files/directories starting with `_` have special meaning:

- `_aggregates.nix` - Module composition definitions
- `_overlays/` - Overlay definitions (not auto-exported as separate outputs)

### Module paths

Module paths follow pattern: `modules/{platform}/{aspect}/{feature}.nix`

Examples:
- `modules/home/ai/claude-code.nix` - AI tooling for home-manager
- `modules/darwin/core/defaults.nix` - Core darwin settings
- `modules/nixos/services/zerotier.nix` - Zerotier service for NixOS

## See also

- [Deferred Module Composition](/concepts/deferred-module-composition) - Module organization pattern
- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination
- [Architecture overview](/concepts/architecture-overview) - Overall architecture
