# File Structure Reference

**Last Updated**: 2025-11-17 (Post-refactoring)
**Module Count**: 83 .nix files in modules/

This document provides a comprehensive reference for the test-clan repository file structure after the November 2025 dendritic flake-parts refactoring.

## Overview

The repository uses dendritic flake-parts architecture with pure import-tree auto-discovery.
All modules in `modules/` are automatically discovered and integrated without manual imports.

## Top-Level Structure

```
test-clan/
├── flake.nix              # Minimal flake with import-tree (23 lines)
├── flake.lock             # Input version locks
├── CLAUDE.md              # Project context for AI assistants
├── README.md              # User-facing documentation
├── justfile               # Development task recipes
├── inventory.json         # Clan inventory (auto-generated)
├── docs/                  # Documentation
├── lib/                   # Shared library code (DRY pattern)
├── machines/              # Machine runtime data (facter.json)
├── modules/               # Auto-discovered flake-parts modules (83 files)
├── pkgs/                  # Custom packages (pkgs-by-name pattern)
├── secrets/               # Unencrypted secrets (home-manager configs)
├── sops/                  # Encrypted secrets (clan secrets)
├── terraform/             # Terraform state and generated configs
└── vars/                  # Clan-generated variables and secrets
```

## Core Directories

### docs/ - Documentation

```
docs/
├── architecture/
│   ├── dendritic-pattern.md    # This architecture explained
│   └── file-structure.md       # This document
├── guides/
│   ├── adding-users.md         # User management guide
│   └── age-key-management.md   # Secrets management guide
└── notes/                      # Development notes
    ├── architecture/           # Architecture decisions and patterns
    └── development/            # Development guides and project overview
```

### lib/ - Shared Library Code

```
lib/
└── caches.nix    # Binary cache configuration (DRY pattern)
                  # Used by: flake.nix, modules/system/caches.nix, modules/darwin/caches.nix
```

Single source of truth for cache substituters and public keys.
Prevents duplication across flake.nix nixConfig, darwin modules, and nixos modules.

### modules/ - Auto-Discovered Flake-Parts Modules

All .nix files in this directory are automatically discovered by import-tree and evaluated as flake-parts modules.

```
modules/
├── dev-shell.nix        # Development environment (devShells.default)
├── flake-parts.nix      # Flake-parts configuration imports
├── formatting.nix       # Code formatting (treefmt, pre-commit hooks)
├── systems.nix          # Supported system architectures
├── checks/              # Test suite modules (4 files)
├── clan/                # Clan orchestration and inventory (4 files + subdirs)
├── darwin/              # Darwin (macOS) modules (6 files + subdirs)
├── home/                # Home-manager modules (many files, deeply nested)
├── machines/            # Machine configurations (darwin + nixos)
├── nixpkgs/             # Nixpkgs configuration and overlays (6 files)
├── system/              # Shared system modules (5 files)
└── terranix/            # Infrastructure-as-code (3 files)
```

#### modules/checks/ - Test Suite

```
checks/
├── integration.nix    # VM-based integration tests (2 test cases)
├── nix-unit.nix       # Expression evaluation tests (11 test cases)
├── performance.nix    # CI performance tests (skeleton)
└── validation.nix     # Property validation tests (4 test cases)
```

Comprehensive test coverage: 17 test cases across 3 frameworks.
See README.md for test execution commands.

#### modules/clan/ - Clan Orchestration

```
clan/
├── core.nix           # Imports clan-core and terranix flakeModules
├── machines.nix       # Machine definitions (cinnabar, electrum, gcp-vm)
├── meta.nix           # Clan metadata
└── inventory/
    ├── machines.nix   # Machine inventory declarations
    └── services/      # Service instance configurations
        ├── emergency-access.nix   # Emergency access service
        ├── internet.nix           # Network configuration
        ├── tor.nix                # Tor service
        ├── zerotier.nix           # Zerotier VPN
        └── users/                 # Per-user service instances (dendritic)
            ├── cameron.nix        # Admin user (modern machines)
            └── crs58.nix          # Admin user (legacy machines)
```

**Pattern**: User inventory decomposed into per-user modules using dendritic pattern (Story 1.7).
Both cameron.nix and crs58.nix declare `clan.inventory.instances.user-*` and auto-merge.

#### modules/darwin/ - macOS System Configuration

```
darwin/
├── base.nix             # Base darwin module namespace declaration
├── caches.nix           # Binary cache config (imports lib/caches.nix)
├── homebrew.nix         # Homebrew package management
├── nix-settings.nix     # Nix daemon configuration
├── profile.nix          # System profile settings
├── users.nix            # User account management
└── system-defaults/     # macOS system defaults (9 focused modules)
    ├── custom-user-prefs.nix   # Custom user preferences
    ├── dock.nix                # Dock configuration
    ├── finder.nix              # Finder settings
    ├── input-devices.nix       # Mouse/trackpad settings
    ├── loginwindow.nix         # Login window configuration
    ├── misc-defaults.nix       # Miscellaneous defaults
    ├── nsglobaldomain.nix      # NSGlobalDomain settings
    ├── screencapture.nix       # Screenshot settings
    └── window-manager.nix      # Window management
```

**Pattern**: All system-defaults modules merge into `flake.modules.darwin.base` automatically.
Previously a single 143-line monolithic file, decomposed into 9 focused modules (~12-20 lines each) in Story 1.7.

#### modules/home/ - Home-Manager Configuration

```
home/
├── app.nix              # Home app for portable activation
├── configurations.nix   # homeConfigurations output structure
├── ai/
│   ├── default.nix      # AI tools aggregate module
│   └── claude-code/     # Claude Code configuration
│       ├── ccstatusline-settings.nix
│       ├── default.nix
│       ├── mcp-servers.nix
│       └── wrappers.nix
├── base/
│   └── sops.nix         # sops-nix integration (Pattern A)
├── development/
│   ├── default.nix      # Development aggregate module
│   ├── git.nix          # Git configuration
│   ├── jujutsu.nix      # Jujutsu VCS
│   ├── starship.nix     # Shell prompt
│   ├── zsh.nix          # Zsh shell
│   ├── neovim/          # Neovim configuration
│   ├── wezterm/         # WezTerm terminal
│   └── zed/             # Zed editor
├── shell/
│   ├── default.nix      # Shell aggregate module
│   ├── atuin.nix        # Shell history
│   ├── bash.nix         # Bash shell
│   ├── rbw.nix          # Bitwarden CLI
│   ├── tmux.nix         # Terminal multiplexer
│   ├── yazi.nix         # File manager
│   ├── zellij.nix       # Terminal multiplexer
│   └── nushell/         # Nushell configuration
└── users/
    ├── default.nix      # Users namespace exports
    ├── crs58/           # crs58 user identity module
    │   └── default.nix
    └── raquel/          # raquel user identity module
        └── default.nix
```

**Pattern**: Aggregate modules (ai/default.nix, development/default.nix, shell/default.nix) compose focused configurations.
Used by clan inventory user modules to build complete user environments.

#### modules/machines/ - Machine Configurations

```
machines/
├── darwin/
│   ├── blackphos/       # Raquel's macOS laptop
│   │   └── default.nix
│   └── test-darwin/     # Test darwin machine
│       └── default.nix
└── nixos/
    ├── cinnabar/        # Hetzner CX43 VPS (BIOS, GRUB, ZFS)
    │   ├── default.nix
    │   ├── disko.nix    # Disk configuration (dendritic)
    │   └── terraform-configuration.nix
    ├── electrum/        # Hetzner CCX23 VPS (UEFI, systemd-boot, ZFS+LUKS)
    │   ├── default.nix
    │   ├── disko.nix    # Disk configuration (dendritic)
    │   └── terraform-configuration.nix
    └── gcp-vm/          # GCP test VM
        ├── default.nix
        └── disko.nix    # Disk configuration (dendritic)
```

**Pattern**: Each machine's disko.nix merges into machine-specific namespace.
Enables focused disk configuration modules separate from main machine config.
Previously inline in default.nix, extracted in Story 1.7.

#### modules/nixpkgs/ - Nixpkgs Configuration and Overlays

```
nixpkgs/
├── compose.nix          # Overlay composition (final flake.overlays.default)
├── default.nix          # Default nixpkgs configuration
├── overlays-option.nix  # flake.overlays option declaration
├── per-system.nix       # Per-system nixpkgs instances
└── overlays/            # Overlay modules (dendritic list concatenation)
    ├── channels.nix     # Multi-channel nixpkgs (stable/unstable)
    ├── hotfixes.nix     # Package fixes and patches
    └── overrides.nix    # Version overrides
```

**Pattern**: Each overlay module appends to `flake.nixpkgsOverlays` list.
compose.nix uses `lib.composeManyExtensions` to merge all overlays.
Eliminates `_overlays` escape hatch (Story 1.7).

#### modules/system/ - Shared System Modules

```
system/
├── admins.nix           # Admin user account configuration
├── caches.nix           # Binary cache config (DRY pattern, imports lib/caches.nix)
├── initrd-networking.nix # Early boot networking (SSH unlock)
├── nix-optimization.nix  # Nix store optimization
└── nix-settings.nix      # Nix daemon settings
```

Modules in this directory merge into both `flake.modules.darwin.base` and `flake.modules.nixos.base` for cross-platform configuration.

#### modules/terranix/ - Infrastructure-as-Code

```
terranix/
├── base.nix       # Base terranix configuration (providers, variables)
├── config.nix     # Terranix perSystem configuration
└── hetzner.nix    # Hetzner Cloud resources (VPS definitions)
```

Terranix modules generate `config.tf.json` consumed by OpenTofu/Terraform.
See README.md Terraform Workflow section for deployment patterns.

### pkgs/ - Custom Packages

```
pkgs/
└── by-name/
    └── ccstatusline/    # Claude Code statusline tool
        └── package.nix
```

Uses pkgs-by-name pattern from nixpkgs for automatic package discovery.
Packages auto-merged into overlays via perSystem.packages and referenced in overlays/compose.nix.

### secrets/ - Unencrypted Secrets (Home-Manager)

```
secrets/
└── home-manager/
    └── users/
        ├── crs58/       # crs58 user secrets
        │   ├── atuin-key
        │   ├── git-signing-key
        │   └── openai-api-key
        └── raquel/      # raquel user secrets
            └── atuin-key
```

**Tier 2 secrets** (two-tier architecture from Story 1.10C):
- User-level secrets managed by sops-nix
- Age encryption using SSH key derived from Bitwarden
- Per-user encryption (crs58: 8 secrets, raquel: 5 secrets)

### sops/ - Encrypted Secrets (Clan)

```
sops/
├── machines/            # Machine age keys (public keys only)
│   ├── cinnabar/
│   │   └── key.json
│   ├── electrum/
│   │   └── key.json
│   └── gcp-vm/
│       └── key.json
├── secrets/             # Clan secrets (encrypted)
│   ├── cinnabar-age.key/
│   ├── electrum-age.key/
│   ├── gcp-vm-age.key/
│   ├── hetzner-api-token/
│   └── tf-passphrase/
└── users/               # User age keys (public keys only)
    ├── crs58/
    │   └── key.json
    └── raquel/
        └── key.json
```

**Tier 1 secrets** (two-tier architecture from Story 1.10C):
- System-level secrets managed by clan
- Machine age keys for system secrets
- Infrastructure credentials (Hetzner API, terraform passphrase)

### vars/ - Clan-Generated Variables

```
vars/
├── per-machine/
│   ├── cinnabar/
│   │   ├── emergency-access/
│   │   ├── initrd-ssh/
│   │   ├── state-version/
│   │   ├── tor_tor/
│   │   ├── user-password-root/
│   │   └── zerotier/
│   ├── electrum/
│   │   ├── emergency-access/
│   │   ├── initrd-ssh/
│   │   ├── luks-password/
│   │   ├── state-version/
│   │   ├── tor_tor/
│   │   ├── user-password-root/
│   │   ├── zerotier/
│   │   └── zfs/
│   └── gcp-vm/
│       ├── emergency-access/
│       ├── initrd-ssh/
│       ├── state-version/
│       ├── tor_tor/
│       ├── user-password-root/
│       └── zerotier/
└── shared/
    └── user-password-cameron/
        ├── user-password/
        └── user-password-hash/
```

Generated by `clan vars generate`.
Required before first deployment (terraform wrapper calls `clan machines install` which needs these vars).

## Module Count by Category

| Category | File Count | Description |
|----------|------------|-------------|
| checks/ | 4 | Test suite modules |
| clan/ | 10 | Clan orchestration and inventory |
| darwin/ | 16 | macOS system configuration |
| home/ | 25+ | Home-manager user configurations |
| machines/ | 8 | Machine-specific configurations |
| nixpkgs/ | 6 | Nixpkgs configuration and overlays |
| system/ | 5 | Shared system modules |
| terranix/ | 3 | Infrastructure-as-code |
| **Total** | **83** | Auto-discovered .nix modules |

## Key Organizational Patterns

### 1. Dendritic Auto-Merge

Multiple files declaring same namespace automatically merge:

```
modules/darwin/system-defaults/dock.nix     → flake.modules.darwin.base
modules/darwin/system-defaults/finder.nix   → flake.modules.darwin.base
modules/darwin/system-defaults/loginwindow.nix → flake.modules.darwin.base
```

All merge into single `flake.modules.darwin.base` namespace.

### 2. Per-Entity Modules

Complex entities decomposed into focused per-entity modules:

```
modules/clan/inventory/services/users/cameron.nix  # One user per file
modules/clan/inventory/services/users/crs58.nix    # One user per file
```

### 3. DRY via lib/

Shared configuration data extracted to lib/ directory:

```
lib/caches.nix                  # Source of truth
├─→ flake.nix                   # CLI usage (literal)
├─→ modules/system/caches.nix   # Machine configs (import)
└─→ modules/darwin/caches.nix   # Darwin configs (import)
```

### 4. List Concatenation for Overlays

Overlays use list composition instead of escape hatches:

```
modules/nixpkgs/overlays/channels.nix   → flake.nixpkgsOverlays
modules/nixpkgs/overlays/hotfixes.nix   → flake.nixpkgsOverlays
modules/nixpkgs/overlays/overrides.nix  → flake.nixpkgsOverlays
```

All concatenated and composed in modules/nixpkgs/compose.nix.

## Navigation Tips

### Finding Configuration by Topic

| Topic | Location |
|-------|----------|
| Binary caches | lib/caches.nix (source), modules/system/caches.nix (usage) |
| macOS dock settings | modules/darwin/system-defaults/dock.nix |
| User configuration | modules/home/users/{username}/ |
| Machine disk layout | modules/machines/{os}/{machine}/disko.nix |
| Service instances | modules/clan/inventory/services/ |
| Test cases | modules/checks/ |
| Infrastructure resources | modules/terranix/ |

### Finding Module by Namespace

| Namespace | Files |
|-----------|-------|
| flake.modules.darwin.base | All modules/darwin/*.nix + system-defaults/*.nix |
| flake.modules.nixos.base | modules/system/*.nix |
| flake.nixpkgsOverlays | modules/nixpkgs/overlays/*.nix |
| clan.inventory.instances.* | modules/clan/inventory/services/**/*.nix |

## References

- **Dendritic pattern**: See docs/architecture/dendritic-pattern.md
- **Module organization**: See dendritic-pattern.md "Module Organization Philosophy"
- **Test suite**: See README.md "Testing" section
- **User management**: See docs/guides/adding-users.md

## Update History

- **2025-11-17**: Post-refactoring structure (83 modules, dendritic pattern)
- **2025-11-16**: Story 1.10C complete (two-tier secrets architecture)
- **2025-11-15**: Story 1.7 complete (9 architectural improvements)
- **2025-11-14**: Pre-refactoring baseline
