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
| `home-as` | Activate another user's home configuration as the current login | `nh home switch` | `modules/home/app.nix` |
| `home-trial` | Activate a user's portable home subset for trial use (no secrets, no identity overrides) | `nh home switch` | `modules/home/app.nix` |
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
nix run github:cameronraysmith/vanixiets#darwin -- <hostname>

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
nix run github:cameronraysmith/vanixiets#os -- <hostname>

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
nix run github:cameronraysmith/vanixiets -- <username>

# Explicit app reference
nix run github:cameronraysmith/vanixiets#home -- <username>

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
homeConfigurations."<username>@<system>".activationPackage
```

For example, on `aarch64-darwin` for user `crs58`:
```
homeConfigurations."crs58@aarch64-darwin".activationPackage
```

**Examples:**

```bash
# Preview home-manager changes
nix run . -- crs58 . --dry

# Apply home-manager configuration
nix run .#home -- crs58 .
```

**Justfile equivalent:** `just activate-home <username> [FLAGS]`

## home-as

Activates the home-manager configuration of one user (the *target*) under the currently logged-in account (the *runner*).
Use this when the same human operates the machine under more than one login (for example, an admin account and a personal account share the same human, but each has its own user module and secrets).

The runner provides the active `$HOME` and identity at activation time; the target provides the full content module, including its own secrets and identity overrides.
The app rewrites `home.username` and `home.homeDirectory` so the configuration activates against the runner's account without colliding with target's own home directory.

**Usage:**

```bash
# Remote usage (default flake)
nix run github:cameronraysmith/vanixiets#home-as -- <target-username>

# Local development
nix run .#home-as -- <target-username> .
nix run .#home-as -- <target-username> . --dry
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `target-username` | Yes | The user whose full home-manager content should be activated (e.g., `crs58`, `cameron`) |
| `flake` | No | Flake path (default: remote GitHub repo) |
| `NH_FLAGS` | No | Flags passed to nh: `--dry`, `--verbose`, `--ask` |

**Configuration path:**

The app resolves the target user's full configuration and rebinds it to the runner's login:
```
homeConfigurations."<target-username>@<system>".activationPackage
```

**Examples:**

```bash
# Activate cameron's full home (with secrets) under whoever is logged in
nix run .#home-as -- cameron .

# Preview the result without applying
nix run .#home-as -- cameron . --dry
```

## home-trial

Activates a *portable* subset of a user's home-manager configuration without their identity overrides or secrets.
Use this for stranger trials: a user who is not the target but wants to evaluate the target's tooling and dotfiles in a safe, ephemeral way (no decryption keys required, no git identity rewrites, no host-specific signing).

`home-trial` resolves to the registry-referenced `flake.modules.homeManager."portable/<target-username>"` content rather than the full `users/<target-username>` module.
The portable subset is the part of the user's configuration that composes cleanly into any account.

**Usage:**

```bash
# Remote usage (default flake)
nix run github:cameronraysmith/vanixiets#home-trial -- <target-username>

# Local development
nix run .#home-trial -- <target-username> .
nix run .#home-trial -- <target-username> . --dry
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `target-username` | Yes | The user whose portable home subset should be trialed |
| `flake` | No | Flake path (default: remote GitHub repo) |
| `NH_FLAGS` | No | Flags passed to nh: `--dry`, `--verbose`, `--ask` |

**Configuration path:**

The app builds an activation package from the portable content alone:
```
homeConfigurations."<target-username>@<system>".activationPackage
```

The underlying configuration imports `flake.modules.homeManager."portable/<target-username>"` and binds runner identity from the active login, so no target secrets, age keys, or signing material are needed.

**Examples:**

```bash
# Trial cameron's portable dotfiles under your own login
nix run .#home-trial -- cameron .

# Preview without applying
nix run .#home-trial -- cameron . --dry
```

## default

The `default` app is an alias for `home`, enabling ergonomic usage:

```bash
# These are equivalent:
nix run github:cameronraysmith/vanixiets -- crs58
nix run github:cameronraysmith/vanixiets#home -- crs58
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
