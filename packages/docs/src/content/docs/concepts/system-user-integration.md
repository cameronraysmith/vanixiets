---
title: System-user integration
description: Understanding admin users with integrated home-manager vs non-admin standalone users
sidebar:
  order: 7
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
│       ├── crs58/           # Primary admin user module
│       │   └── default.nix
│       ├── raquel/          # Additional users...
│       │   └── default.nix
│       ├── janettesmith/
│       │   └── default.nix
│       └── christophersmith/
│           └── default.nix
└── machines/
    ├── darwin/              # Darwin host configurations
    │   ├── stibnite/        # Single-user (crs58)
    │   │   └── default.nix
    │   ├── blackphos/       # Multi-user (raquel primary, crs58 admin)
    │   │   └── default.nix
    │   ├── rosegold/        # Multi-user (janettesmith primary, cameron admin)
    │   │   └── default.nix
    │   └── argentum/        # Multi-user (christophersmith primary, cameron admin)
    │       └── default.nix
    └── nixos/               # NixOS host configurations
        ├── cinnabar/        # Server (cameron)
        │   ├── default.nix
        │   └── disko.nix    # Disk layout
        ├── electrum/
        │   └── default.nix
        ├── galena/
        │   └── default.nix
        └── scheelite/
            └── default.nix
```

## Configuration patterns

### Single-user darwin host

**Example**: stibnite (crs58's primary workstation)

```nix
# modules/machines/darwin/stibnite/default.nix
{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  flake.modules.darwin."machines/darwin/stibnite" =
    { config, pkgs, lib, ... }:
    {
      imports = [
        inputs.home-manager.darwinModules.home-manager
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
      ]);

      networking.hostName = "stibnite";
      nixpkgs.hostPlatform = "aarch64-darwin";

      # Single-user configuration
      users.users.crs58 = {
        uid = 501;
        home = "/Users/crs58";
        shell = pkgs.zsh;
      };

      # Home-Manager configuration
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.crs58.imports = [
          flakeModulesHome."users/crs58"
          flakeModulesHome.ai
          flakeModulesHome.core
          flakeModulesHome.development
          flakeModulesHome.shell
        ];
      };
    };
}
```

**Key points:**
- Uses deferred module composition pattern with `flake.modules.darwin."machines/darwin/hostname"`
- Imports darwin modules and home-manager modules via `config.flake.modules.*`
- Single user defined in machine config with home-manager integration
- System activation deploys both system and home config

### Multi-user darwin host

**Example**: blackphos (raquel's workstation, crs58 as admin)

```nix
# modules/machines/darwin/blackphos/default.nix
{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  flake.modules.darwin."machines/darwin/blackphos" =
    { config, pkgs, lib, ... }:
    {
      imports = [
        inputs.home-manager.darwinModules.home-manager
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
      ]);

      networking.hostName = "blackphos";
      nixpkgs.hostPlatform = "aarch64-darwin";

      # Multi-user configuration
      users.users = {
        raquel = {
          uid = 501;
          home = "/Users/raquel";
          shell = pkgs.zsh;
        };
        crs58 = {
          uid = 502;
          home = "/Users/crs58";
          shell = pkgs.zsh;
        };
      };

      # Home-Manager configuration for multiple users
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.raquel.imports = [
          flakeModulesHome."users/raquel"
          flakeModulesHome.core
          flakeModulesHome.shell
        ];
        users.crs58.imports = [
          flakeModulesHome."users/crs58"
          flakeModulesHome.ai
          flakeModulesHome.core
          flakeModulesHome.development
          flakeModulesHome.shell
        ];
      };
    };
}
```

**Key points:**
- Uses deferred module composition pattern with `flake.modules.darwin."machines/darwin/hostname"`
- Multiple users defined in machine config with separate home-manager imports
- Primary user (raquel) has basic config
- Admin user (crs58) has full development config

### NixOS server host

**Example**: cinnabar (zerotier controller)

```nix
# modules/machines/nixos/cinnabar/default.nix
{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, pkgs, lib, ... }:
    {
      imports = [
        inputs.srvos.nixosModules.server
        inputs.srvos.nixosModules.hardware-hetzner-cloud
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
      ]);

      networking.hostName = "cinnabar";
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";

      # User configuration managed via clan inventory users service
      # See: modules/clan/inventory/services/users.nix
    };
}
```

## User modules

### User-specific configuration

Each user has a module directory in `modules/home/users/<username>/default.nix`:

```nix
# modules/home/users/crs58/default.nix
{
  lib,
  ...
}:
{
  flake.modules.homeManager."users/crs58" =
    { config, pkgs, lib, flake, ... }:
    {
      home.stateVersion = "23.11";
      home.username = lib.mkDefault "crs58";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );

      # User-specific settings
      programs.git.settings = {
        user.name = "Cameron Smith";
        user.email = "cameron.ray.smith@gmail.com";
      };

      # sops-nix user secrets
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/crs58/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = { mode = "0400"; };
        };
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
