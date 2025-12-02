---
title: Clan Integration
description: Multi-machine coordination with clan-core and clear boundaries with other tools
---

[Clan](https://clan.lol/) is our multi-machine coordination and deployment framework.
It orchestrates deployments across NixOS and nix-darwin hosts but does not replace the underlying configuration tools.

## Mental model

Think of clan as **"Kubernetes for NixOS"**.
It coordinates deployment across machines but doesn't replace the underlying NixOS module system, home-manager, or infrastructure provisioning tools.

Kubernetes orchestrates containers but doesn't replace Docker.
Clan orchestrates NixOS deployments but doesn't replace NixOS modules.

## What clan manages

### Machine registry

Clan maintains the registry of machines and their deployment targets via `clan.machines.*`:

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

### Inventory system

The inventory assigns machines to service roles via `clan.inventory.*`:

```nix
# modules/clan/inventory/services/zerotier.nix
inventory.instances.zerotier = {
  roles.controller.machines."cinnabar" = { };
  roles.peer.machines = {
    "electrum" = { };
    "stibnite" = { };
    "blackphos" = { };
  };
};
```

This pattern coordinates multi-machine services.
Cinnabar runs as zerotier controller; other machines join as peers.

### Vars and generators (Tier 1 secrets)

Clan generates and manages system-level secrets via the vars system:

- SSH host keys
- Zerotier network identities
- LUKS/ZFS encryption passphrases
- Service-specific credentials

Generated via `clan vars generate`, stored encrypted in `vars/` directory.

### Deployment tooling

Clan provides unified deployment commands:

- `clan machines install <machine>` - Initial installation (bare metal or VM)
- `clan machines update <machine>` - Configuration updates
- `clan vars generate` - Generate/regenerate secrets

### Service orchestration

Clan coordinates services across multiple machines:

```nix
# Example: User service with password management
inventory.instances.user-cameron = {
  roles.default.machines = {
    "cinnabar" = { };
    "electrum" = { };
    "galena" = { };
  };
};
```

Each service instance can have multiple roles (controller, peer, default, etc.) assigned to different machines.

## What clan does NOT manage

| Capability | Managed by | Relationship to clan |
|------------|------------|---------------------|
| Cloud infrastructure provisioning | **Terranix/Terraform** | Clan deploys TO infrastructure that terranix creates |
| User environment configuration | **Home-Manager** | Deployed WITH clan, not BY clan |
| User-level secrets | **sops-nix** | Tier 2 secrets, parallel to clan vars |
| NixOS/darwin system configuration | **NixOS modules** | Clan imports and deploys configs, doesn't define them |
| Nixpkgs overlays and config | **Flake-level** | Outside clan scope entirely |

### Infrastructure provisioning (Terranix)

Terranix creates cloud infrastructure; clan deploys to it.

```nix
# modules/terranix/hetzner.nix - Creates VMs
resource.hcloud_server.cinnabar = {
  name = "cinnabar";
  server_type = "cx22";
  # ... VM configuration
};

# Provisioner calls clan after VM exists
provisioner.local-exec = {
  command = "clan machines install cinnabar";
};
```

Terranix creates the server, then clan installs NixOS on it.
Clan doesn't provision infrastructure; it consumes infrastructure.

### User environments (Home-Manager)

Home-manager configures user environments.
Clan deploys the full machine configuration, which includes home-manager.

```nix
# modules/machines/darwin/stibnite.nix
home-manager.users.crs58 = {
  imports = with config.flake.modules.homeManager; [
    aggregate-core
    aggregate-ai
    aggregate-development
  ];
};
```

Home-manager configuration is defined OUTSIDE clan, in dendritic modules.
When you run `clan machines update`, home-manager activates as part of system activation.
Clan doesn't know about home-manager specifically.

### User secrets (sops-nix)

User-level secrets are managed by sops-nix, not clan vars.

```nix
# modules/home/core/git.nix
sops.secrets."users/crs58/github-signing-key" = {
  sopsFile = "${inputs.self}/secrets/users/crs58.sops.yaml";
};
```

This is Tier 2 secrets, separate from clan vars (Tier 1).

## Two-tier secrets architecture

The infrastructure uses a two-tier secrets model:

### Tier 1: Clan vars (system-level)

- **Generated** by clan vars system
- **Machine-specific** secrets
- **Examples**: SSH host keys, zerotier identities, LUKS passphrases
- **Managed via**: `clan vars generate`
- **Storage**: `vars/` directory, encrypted

```nix
# Vars are generated automatically
# machines/nixos/cinnabar/vars/zerotier/...
```

### Tier 2: sops-nix (user-level)

- **Manually created** via sops CLI
- **User-specific** secrets
- **Examples**: GitHub tokens, API keys, signing keys, personal credentials
- **Managed via**: `sops secrets/users/username.sops.yaml`
- **Storage**: `secrets/` directory, encrypted with age

```nix
# Secrets manually created and encrypted
sops.secrets."users/crs58/github-token" = {
  sopsFile = ./secrets/users/crs58.sops.yaml;
};
```

### Why two tiers?

**Clan vars** excel at generated, machine-specific secrets.
The vars generator creates SSH keys, zerotier IDs, and other secrets that machines need automatically.

**sops-nix** excels at user-specific, manually-entered secrets.
API tokens, personal credentials, and signing keys must be created by humans, not generated.

The tiers are complementary, not competing.
Clan vars for system infrastructure, sops-nix for user credentials.

## Integration patterns

### Clan + Terranix

```
Terranix (provisions)     →  Clan (deploys)
─────────────────────────────────────────────
terraform.hcloud_server   →  clan machines install
terraform.hcloud_volume   →  (consumed by NixOS config)
```

Terranix creates resources, calls clan to deploy NixOS.

### Clan + Home-Manager

```
Dendritic modules (define) →  Clan machines (deploy) →  Home-Manager (activates)
───────────────────────────────────────────────────────────────────────────────
modules/home/ai/*.nix      →  clan machines update    →  home-manager switch
modules/home/shell/*.nix   →  (part of system config) →  (part of activation)
```

Home-manager modules defined in dendritic structure, deployed via clan.

### Clan + sops-nix

```
Tier 1 (Clan vars)              Tier 2 (sops-nix)
─────────────────               ─────────────────
SSH host keys                   GitHub tokens
Zerotier identities             API keys
LUKS passphrases                Personal credentials
```

Both tiers coexist.
Machine uses clan vars for infrastructure secrets, sops-nix for user secrets.

## Machine fleet

Current machines managed by clan:

| Hostname | Type | Platform | Role | Deployment |
|----------|------|----------|------|------------|
| stibnite | Darwin laptop | aarch64-darwin | Workstation | `clan machines update` |
| blackphos | Darwin laptop | aarch64-darwin | Workstation | `clan machines update` |
| rosegold | Darwin laptop | aarch64-darwin | Workstation | `clan machines update` |
| argentum | Darwin laptop | aarch64-darwin | Workstation | `clan machines update` |
| cinnabar | NixOS VPS | x86_64-linux | Zerotier controller | `clan machines update` |
| electrum | NixOS VPS | x86_64-linux | Server | `clan machines update` |
| galena | NixOS GCP | x86_64-linux | CPU compute | `clan machines update` |
| scheelite | NixOS GCP | x86_64-linux | GPU compute | `clan machines update` |

## Common misconceptions

### "Clan manages infrastructure provisioning"

**Reality**: Clan deploys to infrastructure; it doesn't provision infrastructure.
Terranix/terraform creates VMs, networks, DNS records.
Clan installs NixOS and deploys configurations to those resources.

### "Clan replaces home-manager"

**Reality**: Clan coordinates machine deployments which may include home-manager.
Home-manager configurations are defined outside clan in dendritic modules.
Clan's `machines update` deploys the full machine config including home-manager.

### "Clan secrets replace sops-nix"

**Reality**: Clan vars are system-level generated secrets.
sops-nix handles user-level manually-created secrets.
They're complementary: Tier 1 (clan vars) + Tier 2 (sops-nix).

### "Clan provides NixOS services"

**Reality**: Clan orchestrates deployment of NixOS services across machines.
Clan inventory assigns machines to service roles.
NixOS modules define the actual service configuration.

### "Dendritic flake-parts is a clan feature"

**Reality**: Dendritic is a flake-parts pattern, independent of clan.
Clan is ONE flake-parts module imported alongside others.
Dendritic provides auto-discovery for ALL modules, not just clan.

## External resources

- [Clan documentation](https://clan.lol/) - Official clan-core documentation
- [clan-core repository](https://github.com/clan-core/clan-core) - Source code and examples
- [clan-infra](https://git.clan.lol/clan/clan-infra) - Production clan usage reference

## See also

- [Dendritic Architecture](dendritic-architecture) - Module organization pattern
- [Repository Structure](/reference/repository-structure) - Directory layout
