# Technology Stack Details

**Last Updated**: 2025-11-21
**Status**: Updated post-Epic 1 validation

## Core Technologies

**Nix Ecosystem**:
- **Nix package manager**: 2.18+ (experimental features: nix-command, flakes)
- **nixpkgs**: Multi-channel (stable 25.05 + unstable, five-layer overlay composition)
- **NixOS**: 25.05 (cinnabar, electrum VPS - Epic 1 validated)
- **nix-darwin**: Latest (darwin workstations - blackphos Epic 1 validated)
- **home-manager**: 25.05 (user environment management, Pattern A validated)

**Flake Architecture** (Epic 1 validated):
- **flake-parts**: 7.1.1 (module system for flakes, foundation for dendritic + clan)
- **import-tree**: Latest (automatic module discovery, 83 modules in test-clan, zero manual imports)
- **dendritic flake-parts pattern**: Type-safe namespace (`flake.modules.*`), auto-merge base modules, >7 line heuristic validated
- **Validation**: test-clan flake.nix:4-6 (entire pattern in 3 lines), 18 tests passing, zero regressions across 21 Epic 1 stories

**Multi-Machine Coordination** (Epic 1 validated):
- **clan-core**: cameronraysmith/clan-core dev branch (inventory system, service instances, vars generators, multi-machine deployment)
- **Clan inventory**: Tag-based machine organization (nixos/darwin, cloud/workstation, primary) - heterogeneous fleet validated
- **Clan service instances**: Role-based deployment (controller/peer, server/client, default) - zerotier controller validated
- **Clan vars**: Declarative secret generation (automatic deployment to /run/secrets/, two-tier architecture with sops-nix)
- **Validation**: Stories 1.3, 1.9, 1.12 - cinnabar + electrum + blackphos coordination, zerotier mesh operational
- **Architectural limitation**: Clan inventory cannot reference flake module namespaces directly (use relative imports pattern)

**Infrastructure Provisioning** (Epic 1 validated):
- **terraform**: 1.5+ (infrastructure-as-code for cloud providers)
- **terranix**: 2.9.0 (Nix-based terraform configuration generation)
- **Hetzner Cloud**: CX43 (cinnabar: 4 vCPU, 16GB RAM, 160GB NVMe, ~€12/month), CCX23 (electrum: similar specs)
- **Validation**: Stories 1.4-1.5, 1.9 - cinnabar + electrum operational on Hetzner, LUKS encryption validated
- **Google Cloud Platform**: e2-micro VM (test/dev workloads, ~$5/month) - not validated in Epic 1, deferred

**Disk Management** (Epic 1 validated):
- **disko**: main branch (declarative disk partitioning, automatic dataset creation)
- **LUKS encryption**: Validated for VPS root filesystems (cinnabar, electrum operational with LUKS)
- **ZFS**: Native filesystem (compression=zstd, snapshots enabled) - used on top of LUKS
- **Boot**: UEFI + systemd-boot (electrum CCX23), BIOS + GRUB (cinnabar CX43)
- **Validation**: Story 1.5 - LUKS proven reliable, ZFS native encryption deferred due to implementation issues

**Networking** (Epic 1 validated):
- **zerotier-one**: 1.14.2 (mesh VPN, controller on cinnabar, peers on all machines including darwin)
- **Zerotier network**: db4344343b14b903 (heterogeneous nixos ↔ darwin coordination, 1-12ms latency)
- **Darwin zerotier**: Homebrew cask + activation script (Story 1.12 validated, MINOR limitation acceptable)
- **SSH with CA certificates**: Clan sshd service with certificate-based authentication
- **Validation**: Stories 1.9, 1.12 - bidirectional SSH coordination across heterogeneous fleet, production stability 3+ weeks

**Security** (Epic 1 validated):
- **srvos**: Server hardening modules (security baseline for VPS)
- **Age encryption**: Two-tier architecture (Tier 1: clan vars for system secrets, Tier 2: sops-nix for user secrets)
- **sops-nix**: Mic92/sops-nix (user-level secrets, multi-user encryption validated)
- **SSH-to-age derivation**: Deterministic age key derivation from SSH keys (Bitwarden source of truth)
- **Multi-user encryption**: crs58 (8 secrets), raquel (5 secrets) - cross-platform validated (darwin + nixos)
- **SSH CA**: Centralized certificate authority for SSH access
- **Validation**: Stories 1.10A, 1.10C - two-tier secrets architecture proven, shared age keypair pattern validated
- **Reference**: `~/projects/nix-workspace/test-clan/docs/architecture/secrets-and-vars-architecture.md` (279 lines)

**Testing** (Epic 1 validated):
- **nix-unit**: 2.28.1 (fast expression evaluation tests, ~1s)
- **runNixOSTest**: NixOS VM integration tests (~2-5min, Linux-only)
- **Test categories**: Structural, architectural, behavioral, type-safety, deployment-safety
- **Validation**: Story 1.6 - 18 tests implemented (12 nix-unit + 4 validation + 2 integration)
- **Zero-regression principle**: Maintained across all 21 Epic 1 stories, test harness enabled aggressive Story 1.7 refactoring
- **Reference**: test-clan test harness, comprehensive architectural invariant validation

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

## Epic 1 Validated Integrations

**Flake Input Overlays** (Layer 5 of five-layer overlay architecture, Stories 1.10D-1.10E):

**lazyvim-nix** (pfassina/lazyvim-nix):
- Purpose: Neovim configuration as flake input (replaces custom LazyVim-module)
- Validation: Epic 1 opportunistic improvement, integrated in Story 1.10E
- Benefits: Upstream maintenance, ecosystem alignment, reduced custom code
- Usage: `programs.neovim.package = pkgs.lazyvim-nix.neovim;`

**catppuccin-nix** (catppuccin/nix):
- Purpose: Catppuccin theme management for multiple applications
- Validation: Epic 1 opportunistic improvement, integrated in Story 1.10E
- Benefits: Consistent theming across editors, terminals, system UI
- Usage: `catppuccin.enable = true; catppuccin.flavor = "mocha";`

**nix-ai-tools** (numtide/nix-ai-tools):
- Purpose: AI development tools (claude-code, aider) packaged for nix
- Validation: Epic 1 integration, replaces custom claude-code packaging
- Benefits: Upstream maintenance, latest versions, ecosystem tooling
- Usage: `home.packages = [ pkgs.claude-code ];`

**nuenv** (hallettj/nuenv):
- Purpose: Nushell-based script execution and package building
- Validation: Test-clan integration (writeShellApplication branch)
- Benefits: Type-safe shell scripting, better error handling
- Usage: Build scripts, automation tasks

**Overlay Composition Pattern** (Five Layers, Stories 1.10D, 1.10DA, 1.10DB):
1. **Layer 1 (inputs)**: Multi-channel nixpkgs (stable 25.05 + unstable)
2. **Layer 2 (hotfixes)**: Platform fallbacks (micromamba from stable when unstable broken)
3. **Layer 3 (pkgs-by-name)**: Custom packages (ccstatusline via pkgs-by-name-for-flake-parts)
4. **Layer 4 (overrides)**: Package build modifications
5. **Layer 5 (flakeInputs)**: Flake input overlays (lazyvim-nix, catppuccin-nix, nix-ai-tools, nuenv)

**Validation Evidence**:
- All 5 layers empirically validated in Epic 1 (epic-1-retro-2025-11-20.md:347-362)
- Zero package conflicts across layers
- Opportunistic improvements pattern proven (LazyVim-module → lazyvim-nix, custom packaging → ecosystem flake inputs)

**References**:
- Epic 1 Retrospective: `docs/notes/development/epic-1-retro-2025-11-20.md` (lines 100-111: Opportunistic improvements)
- Test-clan flake.nix: Lines 61-74 (flake input declarations)
- Five-layer overlay documentation: Story 1.10DA, 1.10DB validation
