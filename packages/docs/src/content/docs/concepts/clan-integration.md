---
title: Clan Integration
description: Multi-machine coordination with clan and clear boundaries with other tools
sidebar:
  order: 6
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

Clan maintains the registry of machines and their deployment targets via `flake.clan.machines.*`:

```nix
# modules/clan/machines.nix
flake.clan.machines = {
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

The inventory assigns machines to service roles via `flake.clan.inventory.*`:

```nix
# modules/clan/inventory/services/zerotier.nix
flake.clan.inventory.instances.zerotier = {
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

### Vars and generators

Clan generates and manages secrets via the vars system using sops encryption under the hood:

- SSH host keys
- Zerotier network identities
- LUKS/ZFS encryption passphrases
- Service-specific credentials
- User secrets

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
| User-level secrets (legacy) | **sops-nix** | Some secrets still in direct sops-nix pending migration to clan vars |
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

Home-manager configuration is defined OUTSIDE clan, using deferred module composition.
When you run `clan machines update` (NixOS) or `just activate` (darwin), home-manager activates as part of system activation.
Clan doesn't know about home-manager specifically.

### User secrets (legacy sops tree)

Hand-written user secrets live outside clan vars, in the legacy `.sops.yaml` + `secrets/` tree.
Each user's home-manager module points sops-nix at that user's file:

```nix
# modules/home/users/crs58/default.nix
sops = {
  defaultSopsFile = ../../../../secrets/home-manager/users/crs58/secrets.yaml;
  secrets.github-token = { };
};
```

## Secrets management

Secrets live in two sops trees that share one operator identity.
The [Secrets Management Guide](/guides/secrets-management) gives the procedures; this section explains how clan fits in.

### Secrets architecture

**Clan vars (machine and generated secrets)**

- **Generated** by clan vars generators (`clan vars generate <machine>`)
- **Examples**: SSH host keys, zerotier identities, service credentials, certificates
- **Storage**: `vars/per-machine/<machine>/` and `vars/shared/`, encrypted to each machine's age key and its users
- **Machine keys**: public in `sops/machines/<machine>/key.json`; private in `sops/secrets/<machine>-age.key/secret`, encrypted to the admin user
- **On the host**: sops-nix reads the machine key from `/var/lib/sops-nix/key.txt`, which only `clan machines update`, `clan machines install` and `clan vars upload <machine>` write

```
vars/per-machine/cinnabar/zerotier/…
vars/per-machine/stibnite/nix-grpc-cert/…
```

**Legacy sops tree (hand-written secrets)**

- **Created** with the sops CLI against `.sops.yaml`'s creation rules
- **Examples**: users' home-manager secrets, operator credentials, cluster secrets, NixOS bridge keys
- **Storage**: `secrets/home-manager/users/<user>/secrets.yaml`, `secrets/shared.yaml`, `secrets/clusters/local/`, `secrets/bridge/`
- **Read with**: each person's age key in `~/.config/sops/age/keys.txt` (derived from their Bitwarden SSH key), or on NixOS the bridge key `hm-sops-bridge` delivers

### Secrets lifecycle

The split is by creation method: clan generates and rotates machine secrets, while people write user secrets by hand.
`checks.x86_64-linux.sops-correspondence` keeps the public keys both trees name in agreement.

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
Deferred modules (define) →  Clan machines (deploy) →  Home-Manager (activates)
───────────────────────────────────────────────────────────────────────────────
modules/home/ai/*.nix      →  clan machines update    →  home-manager switch
modules/home/shell/*.nix   →  (part of system config) →  (part of activation)
```

Home-manager modules defined using deferred module composition, deployed via clan.

### Clan + sops-nix

```
Clan vars (machine secrets)          Legacy sops tree (user secrets)
───────────────────────────          ───────────────────────────────
SSH host keys                        Home-manager API tokens, credentials
Zerotier identities                  Signing keys
Service credentials, certificates    Operator credentials (shared.yaml)
Machine keys (sops/machines)         NixOS bridge keys (secrets/bridge)
```

Both systems use sops-nix on the host.
On NixOS, `clan machines update` installs the machine key and activates.
Darwin hosts are activated locally with `just activate`, which never installs the machine key, so each darwin host with a machine key needs `clan vars upload <host>` once; `just activate` stops with that remedy when the key is missing or differs.

## Machine fleet

Current machines managed by clan:

| Hostname | Type | Platform | Role | Deployment |
|----------|------|----------|------|------------|
| stibnite | Darwin laptop | aarch64-darwin | Workstation | `just activate` (machine key via `clan vars upload`) |
| blackphos | Darwin laptop | aarch64-darwin | Workstation | `just activate` |
| rosegold | Darwin laptop | aarch64-darwin | Workstation | `just activate` (machine key via `clan vars upload`) |
| argentum | Darwin laptop | aarch64-darwin | Workstation | `just activate` (machine key via `clan vars upload`) |
| cinnabar | NixOS VPS | x86_64-linux | Zerotier controller | `clan machines update` |
| electrum | NixOS VPS | x86_64-linux | Server | `clan machines update` |
| galena | NixOS GCP | x86_64-linux | CPU compute | `clan machines update` |
| scheelite | NixOS GCP | x86_64-linux | GPU compute | `clan machines update` |

## Potential misconceptions to avoid

### "Clan manages infrastructure provisioning"

**Reality**: Clan deploys to infrastructure; it doesn't provision infrastructure.
Terranix/terraform creates VMs, networks, DNS records.
Clan installs NixOS and deploys configurations to those resources.

### "Clan replaces home-manager"

**Reality**: Clan coordinates machine deployments which may include home-manager.
Home-manager configurations are defined outside clan using deferred module composition.
Clan's `machines update` deploys the full machine config including home-manager.

### "Clan vars can't handle user secrets"

**Reality**: Clan vars handles all secrets (system and user).
The current mix of clan vars and sops-nix reflects historical patterns, not architectural limitation.
Clan vars uses sops encryption internally and can manage both generated and manually-created secrets.

### "Clan provides NixOS services"

**Reality**: Clan orchestrates deployment of NixOS services across machines.
Clan inventory assigns machines to service roles.
NixOS modules define the actual service configuration.

## External resources

- [Clan documentation](https://clan.lol/) - Official clan documentation
- [clan repository](https://github.com/clan-lol/clan-core) - Source code and examples
- [clan-infra](https://git.clan.lol/clan/clan-infra) - Production clan usage reference

## See also

- [Deferred Module Composition](/concepts/deferred-module-composition/) - Module organization pattern
- [Repository Structure](/reference/repository-structure) - Directory layout
- [Secrets Management](/guides/secrets-management/) - Operational procedures for clan vars and legacy sops-nix
- [ADR-0019: Clan-Core Orchestration](/development/architecture/adrs/0019-clan-core-orchestration/) - Architectural decision record
- [ADR-0020: Deferred module composition + Clan Integration](/development/architecture/adrs/0020-deferred-module-composition-clan-integration/) - Integration patterns ADR
