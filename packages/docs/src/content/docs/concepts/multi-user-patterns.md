---
title: Multi-User Patterns
description: Understanding admin users with integrated home-manager vs non-admin standalone users
---

This nix-config supports two distinct user patterns, each optimized for different access levels and use cases.

## Pattern overview

### Admin users: Integrated home-manager

**Characteristics:**
- One admin user per host
- Full system and home-manager configuration
- Requires sudo for activation
- Configurations live in `configurations/darwin/` or `configurations/nixos/`

**When to use:**
- Primary user of the machine
- Need system-level configuration changes
- Managing nix-darwin or NixOS system settings

**Activation:**
```bash
nix run . hostname  # e.g., nix run . stibnite
```

### Non-admin users: Standalone home-manager

**Characteristics:**
- Multiple non-admin users per host supported
- Home environment only, no system access
- No sudo required for activation
- Configurations live in `configurations/home/`

**When to use:**
- Secondary users on a shared machine
- CI/CD runners (e.g., GitHub Actions runners)
- Guest users needing consistent environment

**Activation:**
```bash
nix run . user@hostname  # e.g., nix run . runner@stibnite
```

## Directory organization

```
configurations/
├── darwin/                # Admin users on macOS
│   ├── stibnite.nix       # Admin user on stibnite host
│   └── blackphos.nix      # Admin user on blackphos host
├── nixos/                 # Admin users on NixOS
│   └── orb-nixos.nix      # Admin user on orb-nixos host
└── home/                  # Non-admin users (standalone)
    ├── runner@stibnite.nix    # Runner user on stibnite
    ├── runner@blackphos.nix   # Same runner user, different host
    └── raquel@blackphos.nix   # Another user on blackphos
```

## Configuration structure

### Admin user configuration

**File**: `configurations/darwin/${hostname}.nix` or `configurations/nixos/${hostname}.nix`

```nix
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: {
  # System-level settings
  networking.hostName = "hostname";

  # User account (defined in config.nix)
  users.users.admin = {
    home = "/Users/admin";  # or /home/admin on Linux
    # ... system user configuration
  };

  # Integrated home-manager
  home-manager.users.admin = { ... };
}
```

**Key points:**
- Single file defines both system and home config
- Admin user defined in `config.nix`
- home-manager runs as part of system activation
- Changes require sudo

### Non-admin user configuration

**File**: `configurations/home/${user}@${host}.nix`

```nix
{
  inputs,
  config,
  pkgs,
  ...
}: {
  # Home-manager only
  home = {
    username = "runner";
    homeDirectory = "/Users/runner";  # or /home/runner on Linux
    stateVersion = "24.05";
  };

  # User environment configuration
  programs = { ... };
  home.packages = [ ... ];
}
```

**Key points:**
- Standalone home-manager configuration
- No system-level settings (no sudo needed)
- User defined in `config.nix`
- Independent of system configuration

## User definition in config.nix

All users (both admin and non-admin) are defined in the central `config.nix`:

```nix
{
  users = {
    # Admin user
    admin = {
      username = "admin";
      fullname = "Admin User";
      email = "admin@example.com";
      sshKey = "ssh-ed25519 AAAAC3Nza...";
      isAdmin = true;
    };

    # Non-admin users
    runner = {
      username = "runner";
      fullname = "CI Runner";
      email = "runner@example.com";
      sshKey = "ssh-ed25519 AAAAC3Nza...";
      isAdmin = false;
    };

    raquel = {
      username = "raquel";
      fullname = "Raquel User";
      email = "raquel@example.com";
      sshKey = "ssh-ed25519 AAAAC3Nza...";
      isAdmin = false;
    };
  };
}
```

## Secrets management differences

### Admin users

Secrets are decrypted using:
1. User's age key (from `~/.config/sops/age/keys.txt`)
2. Host's SSH key (from `/etc/ssh/ssh_host_ed25519_key`)

Both keys must be in `.sops.yaml` for the secrets the admin needs.

### Non-admin users

Secrets are decrypted using:
1. User's age key only (from `~/.config/sops/age/keys.txt`)

Non-admin users cannot access host SSH keys, so they rely solely on their personal age keys.

## Practical scenarios

### Scenario 1: Single-user macOS machine

**Setup**: One admin user, full control

```
stibnite (macOS)
└── admin user "crs58" (configurations/darwin/stibnite.nix)
```

**Activation:**
```bash
nix run . stibnite  # Applies system + home config for crs58
```

### Scenario 2: Shared macOS machine

**Setup**: One admin, one non-admin user

```
blackphos (macOS)
├── admin user "cameron" (configurations/darwin/blackphos.nix)
└── non-admin user "raquel" (configurations/home/raquel@blackphos.nix)
```

**Activation:**
```bash
# Cameron (admin) activates system + home
nix run . blackphos

# Raquel (non-admin) activates home only (no sudo)
nix run . raquel@blackphos
```

### Scenario 3: CI/CD runner on multiple hosts

**Setup**: Same runner user on different machines

```
stibnite (macOS)
├── admin "crs58" (configurations/darwin/stibnite.nix)
└── runner "runner" (configurations/home/runner@stibnite.nix)

blackphos (macOS)
├── admin "cameron" (configurations/darwin/blackphos.nix)
└── runner "runner" (configurations/home/runner@blackphos.nix)
```

The runner user has consistent environment across hosts but host-specific configuration when needed.

**Activation on each host:**
```bash
# On stibnite
nix run . runner@stibnite

# On blackphos
nix run . runner@blackphos
```

## When to choose each pattern

### Use admin pattern (integrated home-manager) when:
- You are the primary/sole user of the machine
- You need to configure system-level settings
- You want unified activation (system + home in one command)
- You have sudo access

### Use non-admin pattern (standalone home-manager) when:
- You are a secondary user on a shared machine
- You don't have or don't need sudo access
- You want independent home environment management
- You're setting up CI/CD runner accounts
- Multiple users need isolated environments on the same host

## See also

- [Host Onboarding Guide](/guides/host-onboarding) - Setting up a new admin user host
- [Home Manager Onboarding](/guides/home-manager-onboarding) - Setting up non-admin users
- [Secrets Management](/guides/secrets-management) - Managing user and host secrets
