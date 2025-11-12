# Technology Stack Details

## Core Technologies

**Nix Ecosystem**:
- **Nix package manager**: 2.18+ (experimental features: nix-command, flakes)
- **nixpkgs**: unstable channel (flake input follows)
- **NixOS**: 24.11+ (cinnabar, electrum VPS)
- **nix-darwin**: Latest (darwin workstations)
- **home-manager**: 25.05 (user environment management)

**Flake Architecture**:
- **flake-parts**: 7.1.1 (module system for flakes, foundation for dendritic + clan)
- **import-tree**: Latest (automatic module discovery, zero manual imports)
- **dendritic flake-parts pattern**: Type-safe namespace (`flake.modules.*`), auto-merge base modules

**Multi-Machine Coordination**:
- **clan-core**: main branch (inventory system, service instances, vars generators, multi-machine deployment)
- **Clan inventory**: Tag-based machine organization (nixos/darwin, cloud/workstation, primary)
- **Clan service instances**: Role-based deployment (controller/peer, server/client, default)
- **Clan vars**: Declarative secret generation (automatic deployment to /run/secrets/)

**Infrastructure Provisioning**:
- **terraform**: 1.5+ (infrastructure-as-code for cloud providers)
- **terranix**: 2.9.0 (Nix-based terraform configuration generation)
- **Hetzner Cloud**: CX43 VPS (4 vCPU, 16GB RAM, 160GB NVMe, ~€12/month per machine)
- **Google Cloud Platform**: e2-micro VM (test/dev workloads, ~$5/month)

**Disk Management**:
- **disko**: main branch (declarative disk partitioning, automatic dataset creation)
- **ZFS**: Native filesystem (unencrypted, compression=zstd, snapshots enabled)
- **Boot**: UEFI + systemd-boot (hetzner-ccx23), BIOS + GRUB (hetzner-cx43)

**Networking**:
- **zerotier-one**: 1.14.2 (mesh VPN, controller on cinnabar, peers on all machines)
- **Zerotier network**: Single network ID shared across all machines
- **SSH with CA certificates**: Clan sshd service with certificate-based authentication

**Security**:
- **srvos**: Server hardening modules (security baseline for VPS)
- **Age encryption**: Clan vars encryption (sops backend)
- **SSH CA**: Centralized certificate authority for SSH access

**Testing**:
- **nix-unit**: 2.28.1 (fast expression evaluation tests, ~1s)
- **runNixOSTest**: NixOS VM integration tests (~2-5min, Linux-only)
- **Test categories**: Structural, architectural, behavioral, type-safety, deployment-safety

## Integration Points

**Flake-Parts + Import-Tree**:
```nix
# flake.nix (65 lines total, pure import-tree)
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    # ... other inputs
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
      (inputs.import-tree ./modules);  # Single line: auto-discover all modules
}
```

**Import-Tree Auto-Discovery**:
- Recursively scans `modules/` directory for all `.nix` files
- Each file is a flake-parts module contributing to `config.flake.*`
- No manual imports required (add file → auto-discovered)
- Base modules auto-merge: `system/*.nix` → `flake.modules.nixos.base`

**Clan-Core Integration** (3 integration points):

**1. Core Import** (`modules/clan/core.nix`):
```nix
{ inputs, ... }:
{
  imports = [
    inputs.clan-core.flakeModules.default     # Clan inventory system
    inputs.terranix.flakeModule               # Terraform integration
  ];
}
```

**2. Metadata** (`modules/clan/meta.nix`):
```nix
{
  clan.meta.name = "nix-config";
  clan.specialArgs = { inherit inputs; inherit self; };  # Minimal framework pass-through
}
```

**3. Machine Registration** (`modules/clan/machines.nix`):
```nix
{ config, ... }:
{
  clan.machines.cinnabar = {
    nixpkgs.hostPlatform = "x86_64-linux";
    imports = [
      config.flake.modules.nixos."machines/nixos/cinnabar"  # Reference dendritic module
    ];
  };

  clan.machines.blackphos = {
    nixpkgs.hostPlatform = "aarch64-darwin";
    imports = [
      config.flake.modules.darwin."machines/darwin/blackphos"
    ];
  };
}
```

**Terranix Integration** (`perSystem.terranix`):
```nix
# modules/terranix/base.nix
{ inputs, ... }:
{
  perSystem = { config, pkgs, system, ... }: {
    terranix.terraform = {
      terraform.required_providers = {
        hcloud.source = "hetznercloud/hcloud";
        google.source = "hashicorp/google";
      };
    };
  };
}
```

**Home-Manager Integration** (darwin + NixOS):
```nix
# In machine config (e.g., blackphos)
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.crs58 = { config, ... }: {
    imports = with config.flake.modules.homeManager; [
      core.zsh
      core.starship
      core.git
      users.crs58.dev-tools
    ];
    home.stateVersion = "25.05";
  };
}
```
