---
title: System-user integration
description: Understanding admin users with integrated home-manager vs non-admin standalone users
---

This infrastructure supports multiple user patterns optimized for different access levels and use cases.

## Pattern overview

### Admin users with integrated home-manager

**Characteristics:**
- One or more admin users per host
- Full system and home-manager configuration
- Requires sudo for system activation
- Configurations live in `modules/machines/darwin/` or `modules/machines/nixos/`

**When to use:**
- Primary users of the machine
- Need system-level configuration changes
- Managing nix-darwin or NixOS system settings

**Deployment:**
```bash
clan machines update <hostname>  # e.g., clan machines update stibnite
```

### Standalone home-manager users

**Characteristics:**
- Additional users on shared machines
- Home environment only, no system access
- No sudo required for home-manager activation
- User modules live in `modules/home/users/`

**When to use:**
- Secondary users on a shared machine
- Users needing consistent environment across machines
- Development/staging users

**Deployment:**
```bash
nh home switch  # For standalone home-manager activation
```

## Directory organization

```
modules/
├── home/
│   └── users/               # User-specific home-manager modules
│       ├── crs58.nix        # Primary admin user module
│       ├── cameron.nix      # Cameron user module (admin alias)
│       ├── raquel.nix       # Raquel user module
│       ├── janettesmith.nix # Janet user module
│       └── christophersmith.nix  # Christopher user module
└── machines/
    ├── darwin/              # Darwin host configurations
    │   ├── stibnite.nix     # Single-user (crs58)
    │   ├── blackphos.nix    # Multi-user (raquel primary, crs58 admin)
    │   ├── rosegold.nix     # Multi-user (janettesmith primary, cameron admin)
    │   └── argentum.nix     # Multi-user (christophersmith primary, cameron admin)
    └── nixos/               # NixOS host configurations
        ├── cinnabar.nix     # Server (cameron)
        ├── electrum.nix     # Server (cameron)
        ├── galena.nix       # Compute (cameron)
        └── scheelite.nix    # GPU compute (cameron)
```

## Configuration patterns

### Single-user darwin host

**Example**: stibnite (crs58's primary workstation)

```nix
# modules/machines/darwin/stibnite.nix
{ config, ... }:
{
  flake.darwinConfigurations.stibnite = config.lib.mkDarwinConfiguration {
    system = "aarch64-darwin";
    modules = [
      config.flake.modules.darwin.core
      config.flake.modules.darwin.apps
    ];
    home-manager.users.crs58 = {
      imports = with config.flake.modules.homeManager; [
        aggregate-core
        aggregate-ai
        aggregate-development
        aggregate-shell
      ];
    };
  };
}
```

**Key points:**
- Single user defined in machine config
- All home-manager aggregates for the user
- System activation deploys both system and home config

### Multi-user darwin host

**Example**: blackphos (raquel's workstation, crs58 as admin)

```nix
# modules/machines/darwin/blackphos.nix
{ config, ... }:
{
  flake.darwinConfigurations.blackphos = config.lib.mkDarwinConfiguration {
    system = "aarch64-darwin";
    modules = [
      config.flake.modules.darwin.core
      config.flake.modules.darwin.apps
    ];
    home-manager.users = {
      raquel = {
        imports = with config.flake.modules.homeManager; [
          aggregate-core
          aggregate-shell
        ];
      };
      crs58 = {
        imports = with config.flake.modules.homeManager; [
          aggregate-core
          aggregate-ai
          aggregate-development
          aggregate-shell
        ];
      };
    };
  };
}
```

**Key points:**
- Multiple users defined in machine config
- Each user gets appropriate aggregates for their role
- Primary user (raquel) has basic config
- Admin user (crs58) has full development config

### NixOS server host

**Example**: cinnabar (zerotier controller)

```nix
# modules/machines/nixos/cinnabar.nix
{ config, ... }:
{
  flake.nixosConfigurations.cinnabar = config.lib.mkNixosConfiguration {
    system = "x86_64-linux";
    modules = [
      config.flake.modules.nixos.core
      config.flake.modules.nixos.services
    ];
    home-manager.users.cameron = {
      imports = with config.flake.modules.homeManager; [
        aggregate-core
        aggregate-development
        aggregate-shell
      ];
    };
  };
}
```

## User modules

### User-specific configuration

Each user has a module in `modules/home/users/`:

```nix
# modules/home/users/user.nix
{ ... }:
{
  flake.modules.homeManager."users/user" = { config, pkgs, ... }: {
    home.username = "user";
    home.homeDirectory = "/Users/user";

    # User-specific settings
    programs.git = {
      userName = "User Name";
      userEmail = "user@example.com";
    };

    # sops-nix user secrets
    sops.secrets."users/user/github-token" = {
      sopsFile = ./../../secrets/users/user.sops.yaml;
    };
  };
}
```

## Secrets management by user type

### Admin users

Admin users access secrets via:
1. User's age key (from `~/.config/sops/age/keys.txt`)
2. Host's SSH key (can decrypt system secrets)

```yaml
# .sops.yaml
keys:
  - &admin age1...
  - &stibnite-host age1...

creation_rules:
  - path_regex: secrets/users/admin\.sops\.yaml$
    key_groups:
      - age:
          - *admin
          - *stibnite-host
```

### Non-admin users

Non-admin users access only their personal secrets:

```yaml
# .sops.yaml
keys:
  - &user age1...

creation_rules:
  - path_regex: secrets/users/user\.sops\.yaml$
    key_groups:
      - age:
          - *user
```

## Machine fleet user assignments

| Host | Primary User | Admin User | Platform |
|------|--------------|------------|----------|
| stibnite | crs58 | crs58 | Darwin |
| blackphos | raquel | crs58 | Darwin |
| rosegold | janettesmith | cameron | Darwin |
| argentum | christophersmith | cameron | Darwin |
| cinnabar | cameron | cameron | NixOS |
| electrum | cameron | cameron | NixOS |
| galena | cameron | cameron | NixOS |
| scheelite | cameron | cameron | NixOS |

## When to choose each pattern

### Use integrated home-manager when:
- You are the primary user of the machine
- You need system-level configuration changes
- You want unified activation (system + home in one command)
- You have sudo access

### Use standalone home-manager when:
- You are a secondary user on a shared machine
- You don't need system-level configuration
- Multiple users need isolated environments on the same host

## Aggregate-based composition

Users receive features through aggregate imports rather than individual modules:

```nix
# Example aggregates
aggregate-core      # XDG, fonts, SSH, basic tools
aggregate-ai        # Claude Code, MCP servers, AI tooling
aggregate-development  # Git, editors, languages
aggregate-shell     # Zsh, fish, starship, tmux
```

This pattern:
- Reduces duplication across user configs
- Makes feature sets consistent
- Simplifies adding/removing features

## See also

- [Host Onboarding Guide](/guides/host-onboarding) - Adding new hosts
- [Home Manager Onboarding](/guides/home-manager-onboarding) - User setup
- [Clan Integration](/concepts/clan-integration) - Deployment coordination
