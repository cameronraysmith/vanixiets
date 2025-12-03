---
title: Flake Apps
description: Reference for nix flake apps that wrap configuration activation
sidebar:
  order: 3
---

This reference documents the flake apps provided by the infra repository.
These apps wrap `nh` (nix-helper) commands for ergonomic configuration activation.

## Overview

| App | Purpose | Wraps | Definition |
|-----|---------|-------|------------|
| `darwin` | Activate darwin configuration | `nh darwin switch` | `modules/darwin/app.nix` |
| `os` | Activate NixOS configuration | `nh os switch` | `modules/nixos/app.nix` |
| `home` | Activate home-manager configuration | `nh home switch` | `modules/home/app.nix` |
| `default` | Alias for `home` | - | `modules/home/app.nix` |

## Dispatch chain

The typical activation flow uses justfile recipes that call flake apps:

```
just activate
    └── just activate-darwin hostname
            └── nix run .#darwin -- hostname . [FLAGS]
                    └── nh darwin switch . -H hostname [FLAGS]
                            └── darwin-rebuild switch --flake .#hostname
```

## darwin

Builds and activates a nix-darwin configuration for the specified hostname.

**Usage:**

```bash
# Remote usage (default flake)
nix run github:cameronraysmith/infra#darwin -- <hostname>

# Local development
nix run .#darwin -- <hostname> .
nix run .#darwin -- <hostname> . --dry
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `hostname` | Yes | Darwin machine hostname (e.g., `stibnite`, `blackphos`) |
| `flake` | No | Flake path (default: remote GitHub repo) |
| `NH_FLAGS` | No | Flags passed to nh: `--dry`, `--verbose`, `--ask` |

**Examples:**

```bash
# Preview changes without applying
nix run .#darwin -- stibnite . --dry

# Apply with verbose output
nix run .#darwin -- blackphos . --verbose

# Ask for confirmation before applying
nix run .#darwin -- stibnite . --ask
```

**Justfile equivalent:** `just activate-darwin <hostname> [FLAGS]`

## os

Builds and activates a NixOS configuration for the specified hostname.

**Usage:**

```bash
# Remote usage (default flake)
nix run github:cameronraysmith/infra#os -- <hostname>

# Local development
nix run .#os -- <hostname> .
nix run .#os -- <hostname> . --dry
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `hostname` | Yes | NixOS machine hostname (e.g., `cinnabar`, `electrum`) |
| `flake` | No | Flake path (default: remote GitHub repo) |
| `NH_FLAGS` | No | Flags passed to nh: `--dry`, `--verbose`, `--ask` |

**Examples:**

```bash
# Preview changes on NixOS server
nix run .#os -- cinnabar . --dry

# Apply configuration
nix run .#os -- cinnabar .
```

**Justfile equivalent:** `just activate-os <hostname> [FLAGS]`

## home

Builds and activates a home-manager configuration for the specified user.
This is also the **default app** for the flake.

**Usage:**

```bash
# Remote usage (as default app)
nix run github:cameronraysmith/infra -- <username>

# Explicit app reference
nix run github:cameronraysmith/infra#home -- <username>

# Local development
nix run .#home -- <username> .
nix run . -- <username> . --dry
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `username` | Yes | Username for home-manager (e.g., `crs58`, `cameron`) |
| `flake` | No | Flake path (default: remote GitHub repo) |
| `NH_FLAGS` | No | Flags passed to nh: `--dry`, `--verbose`, `--ask` |

**Configuration path:**

The app constructs the full home-manager configuration path:
```
homeConfigurations.<system>.<username>.activationPackage
```

For example, on `aarch64-darwin` for user `crs58`:
```
homeConfigurations.aarch64-darwin.crs58.activationPackage
```

**Examples:**

```bash
# Preview home-manager changes
nix run . -- crs58 . --dry

# Apply home-manager configuration
nix run .#home -- crs58 .
```

**Justfile equivalent:** `just activate-home <username> [FLAGS]`

## default

The `default` app is an alias for `home`, enabling ergonomic usage:

```bash
# These are equivalent:
nix run github:cameronraysmith/infra -- crs58
nix run github:cameronraysmith/infra#home -- crs58
```

This makes home-manager activation the most convenient operation since it's the most common use case.

## Common flags

All apps pass through flags to `nh`, which supports:

| Flag | Description |
|------|-------------|
| `--dry` | Preview changes without applying (dry run) |
| `--ask` | Ask for confirmation before applying changes |
| `--verbose` | Show verbose output during build and activation |

These can be combined:

```bash
nix run .#darwin -- stibnite . --dry --verbose
```

## Implementation notes

All apps use the same pattern:

1. Parse hostname/username and optional flake path
2. Default to remote GitHub repository if no flake path provided
3. Pass remaining arguments to `nh` as flags
4. Always include `--accept-flake-config` for nh's internal nix calls
5. Use `exec` to replace the shell process with nh

The apps use `nh` (nix-helper) rather than direct `darwin-rebuild`, `nixos-rebuild`, or `home-manager` commands because nh provides:

- Unified interface across all configuration types
- Better diff output showing what will change
- Automatic sudo elevation when needed
- Cleaner progress output

## See also

- [Justfile Recipes](/reference/justfile-recipes/) - Recipes that wrap these apps
- [CI Jobs](/reference/ci-jobs/) - How CI validates configurations
- [Getting Started](/guides/getting-started/) - Initial setup guide
