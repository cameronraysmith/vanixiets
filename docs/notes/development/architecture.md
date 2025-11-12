# Architecture

## Executive Summary

The nix-config infrastructure migration adopts a **validated dendritic flake-parts + clan-core integration pattern** proven through test-clan Phase 0 validation (Stories 1.1-1.7), establishing type-safe module organization with robust multi-machine coordination capabilities across a heterogeneous 5-machine fleet (1 x86_64 NixOS VPS + 4 aarch64 darwin workstations).

The architecture combines three core technologies: **dendritic flake-parts** for type-safe module namespace organization (`flake.modules.*`), **clan-core** for multi-machine coordination (inventory, service instances, vars generation), and **import-tree** for automatic module discovery.
Infrastructure provisioning uses **terraform/terranix** for declarative cloud deployment, **disko** for disk partitioning with ZFS storage, and **zerotier mesh VPN** for always-on network coordination (controller on cinnabar VPS).

**Key Architectural Achievements**:
- **Pure import-tree auto-discovery**: 65-line flake.nix with zero manual imports, all modules discovered automatically
- **Type-safe dendritic namespace**: `flake.modules.{nixos,darwin,homeManager}.*` with explicit option declarations
- **Auto-merge base modules**: System-wide configurations (nix-settings, admins, networking) automatically merged into `flake.modules.nixos.base`
- **Clan inventory coordination**: Tag-based service deployment across heterogeneous platforms (NixOS + darwin)
- **Progressive validation gates**: 1-2 week stability windows between host migrations with explicit rollback procedures
- **Zero-regression mandate**: Comprehensive test harness (17 test cases) validates architectural invariants

**Migration Strategy**: Validation-first approach with test-clan architectural proof (Stories 1.1-1.7 complete), darwin integration validation (Story 1.8 in test-clan), then progressive production refactoring (blackphos → rosegold → argentum → stibnite) with explicit go/no-go gates.

## Project Initialization

This is a **brownfield migration project** transitioning from nixos-unified to dendritic + clan patterns.
There is no single initialization command; the architecture is applied progressively per host with validation gates.

**Proven Pattern Initialization** (from test-clan validation):
```bash
# 1. Repository structure (already exists in infra)
cd ~/projects/nix-workspace/infra
git checkout clan  # Migration branch

# 2. Flake inputs configuration (add clan-core, import-tree, terranix, disko, srvos)
# See Decision Summary table for specific versions

# 3. Module structure creation (dendritic pattern)
mkdir -p modules/{clan,system,machines/{nixos,darwin},terranix,checks}

# 4. Import-tree auto-discovery configuration
# flake.nix outputs: flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules)

# 5. Clan inventory initialization
# modules/clan/meta.nix: clan.meta.name = "nix-config"
# modules/clan/inventory/machines.nix: Define all 5 machines

# 6. Per-host migration (progressive, with validation gates)
# Phase 0: test-clan validation (COMPLETE)
# Story 1.8: blackphos (darwin multi-user) in test-clan
# Production: Apply validated patterns to infra repo
```

**First Implementation Story** (Story 1.8 in test-clan, then apply to infra):
Migrate blackphos darwin host from infra's nixos-unified pattern to test-clan's dendritic + clan pattern, validating multi-user (crs58 admin + raquel non-admin), home-manager integration, and heterogeneous zerotier networking (nixos ↔ darwin) before production refactoring.

## Decision Summary

| Category | Decision | Version | Affects Epics | Rationale | Provided by |
| -------- | -------- | ------- | ------------- | --------- | ----------- |
| **Architectural Pattern** | Dendritic flake-parts + clan-core | flake-parts 7.1.1, clan-core main | All (Epic 1-7) | Maximizes type safety via module system, proven in test-clan Stories 1.1-1.7 with zero regressions | Pattern research + validation |
| **Module Discovery** | import-tree automatic | import-tree latest | All | Eliminates manual imports, auto-discovers all .nix files in modules/ | Dendritic pattern requirement |
| **Infrastructure Provisioning** | terraform via terranix | terranix 2.9.0 | Epic 1 (VPS deployment) | Declarative cloud deployment, proven in clan-infra production | clan-infra reference |
| **Disk Management** | disko with ZFS | disko main, ZFS native | Epic 1-2 (NixOS hosts) | Declarative partitioning, unencrypted ZFS (LUKS deferred), automatic dataset creation | Test-clan validation (Stories 1.4-1.5) |
| **Networking** | Zerotier mesh VPN | zerotier-one 1.14.2 | Epic 1-7 | Always-on coordination independent of darwin host power state, controller on cinnabar VPS | Clan zerotier service |
| **Networking (darwin)** | Multiple options | Varies | Epic 2-6 (darwin hosts) | Zerotier clan service is NixOS-only; darwin requires alternative (see Darwin Networking Options section) | Source code analysis |
| **Secrets Management** | Clan vars generators | clan-core vars system | Epic 1-7 | Declarative secret generation, automatic deployment to /run/secrets/, replaces manual sops-nix | Clan vars architecture |
| **Multi-User Pattern** | Standard NixOS users.users (not clan users service) | NixOS module system | Epic 2-6 (darwin multi-user) | Clan users clanService exists but NOT used; traditional users.users chosen for darwin compatibility + explicit UID control. Per-user vars use naming convention. See "User Management Decision" below. | clan-core analysis + real-world usage (clan-infra, qubasa, pinpox) |
| **Home-Manager** | Portable user-based modules | home-manager 25.05 | All epics | User-based modules (`flake.modules.homeManager."users/{username}"`) support three integration modes (darwin, NixOS, standalone). See Pattern 2 and "Home-Manager Pattern Decision" below. | Test-clan validation + pinpox pattern divergence |
| **Base Module Auto-Merge** | Automatic via import-tree | import-tree feature | All | System-wide modules (nix-settings, admins, initrd-networking) auto-merge to flake.modules.nixos.base | Test-clan proven pattern |
| **Test Framework** | nix-unit + runNixOSTest | nix-unit 2.28.1 | Epic 1 (validation) | Fast expression tests + VM integration tests, 17 test cases in test-clan | Test-clan validation infrastructure |
| **Migration Strategy** | Progressive with stability gates | N/A | Epic 1-7 | 1-2 week validation between hosts, explicit rollback procedures, primary workstation last | Risk mitigation for brownfield |
| **Legacy Elimination** | Remove nixos-unified | Post-migration | Epic 7 (cleanup) | Incompatible with dendritic pattern (specialArgs vs config.flake.*), remove after all hosts migrated | Architectural incompatibility |

**Version Verification** (as of 2025-11-11):
- flake-parts: 7.1.1 (stable)
- clan-core: main branch (git+https://git.clan.lol/clan/clan-core)
- import-tree: latest (github:vic/import-tree)
- terranix: 2.9.0 (github:terranix/terranix)
- disko: main (github:nix-community/disko)
- zerotier-one: 1.14.2 (nixpkgs#zerotierone)
- nix-unit: 2.28.1 (nixpkgs#nix-unit)
- home-manager: 25.05 (follows nixpkgs unstable)

**Dendritic Pattern Compromises**:
- **Minimal specialArgs acceptable**: Clan requires `specialArgs = { inherit inputs; inherit self; }` for flakeModules integration (framework values only, not extensive pass-through)
- **Auto-merge replaces pure exports**: Base modules auto-merge via import-tree instead of explicit exports (pragmatic dendritic adaptation)
- **Clan coordination over pure dendritic**: When clan functionality conflicts with dendritic purity, clan takes precedence (documented deviations)

## Architectural Decisions

### User Management Decision: Traditional vs Clan Users Service

**Investigation Date:** 2025-11-12

**Question:** Should we use clan-core's native users clanService or traditional NixOS `users.users.*` definitions?

**Clan Users ClanService Analysis:**

Clan-core provides `clanServices/users/` for multi-machine user account coordination via inventory service instances:

```nix
# Clan pattern (NOT used in our architecture)
inventory.instances.user-crs58 = {
  module = { name = "users"; input = "clan-core"; };
  roles.default.tags.all = { };  # Deploy on all machines
  roles.default.settings = {
    user = "crs58";
    groups = [ "wheel" ];
    share = true;  # Same password across machines
  };
};
```

**Features:**
- Automatic password generation and distribution
- Cross-machine password coordination (`share = true`)
- Tag-based deployment to machine subsets
- Built-in vars integration (`user-password-{username}`)

**Real-World Usage Analysis:**

Examined clan-infra and developer repos (qubasa, mic92, pinpox):
- **clan-infra:** Uses users service ONLY for root account, regular users via traditional definitions
- **qubasa-clan-infra:** NO users service usage, all traditional definitions
- **pinpox-clan-nixos:** NO users service usage, all traditional definitions

**Finding:** Real-world clan usage favors traditional `users.users.*` approach for regular users.

**Decision: Use Traditional `users.users.*` Definitions**

**Rationale:**

1. **Darwin Compatibility** (CRITICAL):
   - Users clanService sets `users.mutableUsers = false` (line 150 of `clanServices/users/default.nix`)
   - Darwin requires mutable users for system integration
   - 4 of 5 machines in our fleet are darwin

2. **Explicit UID Control** (IMPORTANT):
   - Users service auto-assigns UIDs
   - Multi-machine consistency requires explicit UID coordination (crs58 = 550, raquel = 551)
   - Traditional definitions provide explicit UID control per machine

3. **Per-Machine Flexibility** (IMPORTANT):
   - SSH keys differ per machine for security
   - Home directories may vary (darwin `/Users/` vs NixOS `/home/`)
   - Traditional definitions allow per-machine customization

4. **Real-World Validation**:
   - Clan-infra (production) uses hybrid: users service for root, traditional for regular users
   - All examined repos favor traditional approach for regular users
   - Pattern proven across heterogeneous fleets

**Trade-offs:**

| Aspect | Traditional Definitions | Users ClanService |
|--------|------------------------|-------------------|
| Darwin Support | ✅ Native | ❌ Incompatible (`users.mutableUsers = false`) |
| UID Control | ✅ Explicit | ❌ Auto-assigned |
| Per-Machine SSH Keys | ✅ Easy | ⚠️ Requires overrides |
| Cross-Machine Password | ⚠️ Manual vars | ✅ Automatic (`share = true`) |
| Service Abstraction | ❌ Manual | ✅ Declarative |
| Complexity | ✅ Simple | ⚠️ Additional layer |

**Conclusion:** Traditional approach is DIVERGENT from clan's native capability but JUSTIFIED by darwin compatibility and UID control requirements. Real-world usage validates this pattern.

**Implementation:** See Pattern 3 (Darwin Multi-User) for per-user vars naming convention (`ssh-key-{username}`) that provides similar organization without clanService dependency.

---

### Home-Manager Pattern Decision: User-Based vs Profile-Based Modules

**Investigation Date:** 2025-11-12

**Question:** How should home-manager configurations be organized for cross-platform reuse?

**Clan Examples Analysis:**

Only 1 of 3 examined clan repositories uses home-manager:

- **pinpox-clan-nixos:** Uses profile-based exports (`flake.homeConfigurations.desktop`)
  ```nix
  homeConfigurations.desktop = { ... }: {
    imports = [ ./home-manager/profiles/desktop ];
  };
  # Machine usage:
  home-manager.users.pinpox = flake-self.homeConfigurations.desktop;
  ```

- **Other repos:** No home-manager integration found (qubasa, mic92, clan-infra)

**Decision: User-Based Modules via Dendritic Namespace**

**Pattern:**
```nix
flake.modules.homeManager."users/crs58" = { config, pkgs, lib, ... }: { ... };
```

**Rationale:**

1. **Multi-User Granularity:**
   - blackphos has 2 users (crs58 admin + raquel non-admin) with different configs
   - User-based modules allow per-user customization naturally
   - Profile-based would require mapping profiles to users

2. **Dendritic Integration:**
   - Uses `flake.modules.*` namespace (dendritic pattern)
   - Auto-discovered via import-tree
   - Self-composable via `config.flake.modules`

3. **Three Integration Modes:**
   - Darwin integrated: `darwinModules.home-manager` + imports
   - NixOS integrated: `nixosModules.home-manager` + imports
   - Standalone: `homeConfigurations.{username}` for `nh home switch`

**Comparison:**

| Aspect | User-Based (Our Approach) | Profile-Based (Pinpox) |
|--------|---------------------------|------------------------|
| Multi-User Support | ✅ Natural | ⚠️ Requires mapping |
| Granularity | Per-user modules | Per-profile configs |
| Dendritic Integration | ✅ Namespace exports | ❌ Direct flake outputs |
| Reusability | Users share modules | Profiles reused |
| Cross-Platform | ✅ Works anywhere | ✅ Works anywhere |

**Conclusion:** User-based approach is DIVERGENT from pinpox pattern but SUPERIOR for multi-user machines. Fills gap in clan ecosystem (no standard home-manager patterns exist).

**Implementation:** See Pattern 2 (Portable Home-Manager Modules) for complete pattern documentation.

**Evidence:** Comprehensive clan-core investigation (2025-11-12) covering:
- Clan-core source analysis (`clanServices/users/`, vars/secrets patterns)
- Clan-infra production usage patterns
- Developer repositories (qubasa, mic92, pinpox)
- Alignment assessment matrix with trade-off analysis

---

## Project Structure

```
nix-config/  (infra repository)
├── flake.nix                                   # 65-line pure import-tree flake
├── flake.lock                                  # Dependency version lock
├── .pre-commit-config.yaml                     # Git hooks (gitleaks, nixfmt)
├── modules/                                    # Dendritic flake-parts modules (auto-discovered)
│   ├── clan/                                   # Clan-core integration (4 files)
│   │   ├── core.nix                            # Import clan-core + terranix flakeModules
│   │   ├── meta.nix                            # Clan metadata + specialArgs propagation
│   │   ├── machines.nix                        # Machine registration (reference dendritic modules)
│   │   └── inventory/                          # Clan inventory (machines + service instances)
│   │       └── machines.nix                    # 5 machines: cinnabar, blackphos, rosegold, argentum, stibnite
│   ├── system/                                 # System-wide NixOS configs (auto-merge to base)
│   │   ├── admins.nix                          # Admin users with SSH keys (crs58)
│   │   ├── nix-settings.nix                    # Nix daemon config (experimental-features, trusted-users)
│   │   └── initrd-networking.nix               # SSH in initrd for remote LUKS unlock (if needed)
│   ├── darwin/                                 # Darwin-specific modules
│   │   ├── base.nix                            # System-wide darwin config (nix settings, state version)
│   │   ├── users.nix                           # Darwin user management (UID 550+ range)
│   │   └── homebrew.nix                        # Homebrew integration (casks for GUI apps)
│   ├── home/                                   # Home-manager modules (dendritic namespace)
│   │   ├── core/                               # Shared home config (shell, git, editors)
│   │   │   ├── zsh.nix
│   │   │   ├── starship.nix
│   │   │   └── git.nix
│   │   └── users/                              # Per-user home configurations
│   │       ├── crs58/                          # Admin user (development tools)
│   │       │   ├── default.nix
│   │       │   └── dev-tools.nix
│   │       ├── raquel/                         # Non-admin user (blackphos)
│   │       │   └── default.nix
│   │       ├── christophersmith/               # Non-admin user (argentum)
│   │       │   └── default.nix
│   │       └── janettesmith/                   # Non-admin user (rosegold)
│   │           └── default.nix
│   ├── machines/                               # Machine-specific configurations
│   │   ├── nixos/                              # NixOS machines
│   │   │   ├── cinnabar/                       # Hetzner VPS (always-on)
│   │   │   │   ├── default.nix                 # Host config (imports base, users, disko)
│   │   │   │   ├── disko.nix                   # ZFS disk layout
│   │   │   │   └── hardware-configuration.nix  # Generated hardware config
│   │   │   └── electrum/                       # Hetzner VPS (togglable)
│   │   │       ├── default.nix
│   │   │       ├── disko.nix
│   │   │       └── hardware-configuration.nix
│   │   └── darwin/                             # Darwin machines
│   │       ├── blackphos/                      # Phase 2: First darwin (raquel + crs58)
│   │       │   └── default.nix
│   │       ├── rosegold/                       # Phase 3: Second darwin (janettesmith + crs58)
│   │       │   └── default.nix
│   │       ├── argentum/                       # Phase 4: Third darwin (christophersmith + crs58)
│   │       │   └── default.nix
│   │       └── stibnite/                       # Phase 5: Primary workstation (crs58 only)
│   │           └── default.nix
│   ├── terranix/                               # Terraform modules (perSystem.terranix)
│   │   ├── base.nix                            # Provider config (hcloud, google)
│   │   ├── config.nix                          # Global terraform config
│   │   └── hetzner.nix                         # Hetzner resources (servers, SSH keys)
│   └── checks/                                 # Test harness (nix-unit + integration)
│       ├── nix-unit.nix                        # Expression evaluation tests
│       ├── integration.nix                     # VM boot tests (runNixOSTest)
│       ├── validation.nix                      # Structural validation tests
│       └── performance.nix                     # Build performance tests
├── sops/                                       # Clan vars storage (encrypted secrets)
│   ├── machines/                               # Per-machine secrets
│   │   ├── cinnabar/
│   │   │   ├── secrets/                        # Encrypted (zerotier-identity-secret, sshd keys)
│   │   │   └── facts/                          # Public facts (zerotier-ip, network-id)
│   │   ├── blackphos/
│   │   ├── rosegold/
│   │   ├── argentum/
│   │   └── stibnite/
│   └── shared/                                 # Shared secrets (if share=true in generators)
├── terraform/                                  # Terraform working directory (git-ignored)
│   ├── .terraform/                             # Provider plugins
│   ├── terraform.tfstate                       # State file (git-ignored, sensitive)
│   └── .gitkeep
├── docs/notes/                                 # Migration documentation
│   ├── clan/
│   │   └── integration-plan.md                 # Phase 0-6 migration strategy
│   └── development/
│       ├── PRD.md                              # Product Requirements Document
│       ├── epics.md                            # Epic breakdown (7 epics, 34 stories)
│       ├── sprint-status.yaml                  # Current sprint status
│       ├── test-clan-validated-architecture.md # Validated patterns from test-clan
│       └── architecture.md                     # This document
└── .envrc                                      # Direnv integration (nix develop shell)
```

**Directory Organization Rationale**:
- **Flat feature categories** (clan/, system/, darwin/, home/, terranix/) not nested by platform (dendritic pattern)
- **Machine configs in machines/{nixos,darwin}/** for platform-specific hosts
- **Auto-merge base** (system/*.nix → flake.modules.nixos.base automatically)
- **Import-tree auto-discovery** (no manual imports, all .nix files discovered)
- **Clan integration via modules/clan/** (separate from application modules)
- **Test harness in modules/checks/** (validation as code)

## Epic to Architecture Mapping

| Epic | Architecture Components | Key Modules | Clan Services Used | Test Coverage |
| ---- | ----------------------- | ----------- | ------------------ | ------------- |
| **Epic 1: Architectural Validation** (Phase 0, test-clan) | Dendritic + clan integration, NixOS VMs (cinnabar/electrum), terraform/terranix, disko/ZFS, zerotier mesh, comprehensive test harness | modules/clan/core.nix, modules/system/*.nix, modules/machines/nixos/*, modules/terranix/*.nix, modules/checks/*.nix | zerotier (controller on cinnabar), emergency-access, tor, users | 17 test cases (nix-unit + integration + validation) |
| **Epic 2: VPS Infrastructure Foundation** (Phase 1, production nix-config + blackphos) | Apply validated patterns to infra repo, migrate blackphos darwin (multi-user), heterogeneous networking (nixos ↔ darwin) | modules/darwin/base.nix, modules/darwin/users.nix, modules/home/users/{crs58,raquel}/, modules/machines/darwin/blackphos/ | zerotier (peer role, darwin workaround), sshd-clan, users-crs58, users-raquel | Existing test-clan tests + darwin-specific validation |
| **Epic 3: First Darwin Migration** (Phase 2, rosegold) | Validate darwin pattern reusability, multi-machine coordination (3 machines), 3-user fleet (crs58 + raquel + janettesmith) | modules/machines/darwin/rosegold/, modules/home/users/janettesmith/ | Same as blackphos (reuse patterns) | Pattern reusability validation, 3-machine network tests |
| **Epic 4: Multi-Darwin Validation** (Phase 3, argentum) | 4-machine network validation, 4-user fleet, final validation before primary workstation | modules/machines/darwin/argentum/, modules/home/users/christophersmith/ | Same patterns (3rd iteration validation) | 4-machine mesh network validation, coordination tests |
| **Epic 5: Primary Workstation Migration** (Phase 4, stibnite) | 5-machine complete fleet, primary workstation with all productivity workflows, cumulative stability (4-6 weeks) | modules/machines/darwin/stibnite/ | Complete fleet coordination | Comprehensive workflow validation, productivity assessment |
| **Epic 6: Legacy Cleanup** (Phase 5) | Remove nixos-unified, finalize secrets migration (full clan vars or hybrid), clean architecture | Remove configurations/ directory, nixos-unified flake input | Finalize secret management strategy | Architecture coherence validation |

**Cross-Epic Dependencies**:
- Epic 1 → Epic 2: Validated patterns (dendritic + clan) applied to production
- Epic 2 → Epic 3-5: Darwin patterns established, replicated with minimal customization
- Epic 3-4 → Epic 5: Cumulative stability (4-6 weeks) required before stibnite
- All Epics → Epic 6: Complete migration enables cleanup

## Technology Stack Details

### Core Technologies

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

### Integration Points

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

## Novel Pattern Designs

**Pattern 1: Auto-Merge Base Modules via Import-Tree**

**Problem**: Dendritic pattern requires explicit module exports, but system-wide configurations (nix settings, admin users, initrd networking) should be automatically available to all machines without manual imports.

**Solution**: Import-tree automatically merges all files in `modules/system/` into `flake.modules.nixos.base`:

```nix
# modules/system/nix-settings.nix
{ flake.modules.nixos.base.nix.settings = { experimental-features = ["nix-command" "flakes"]; }; }

# modules/system/admins.nix
{ flake.modules.nixos.base.users.users.crs58 = { extraGroups = ["wheel"]; }; }

# Result: Single merged base module
flake.modules.nixos.base = {
  nix.settings = { ... };
  users.users.crs58 = { ... };
  boot.initrd.network = { ... };
};
```

**Benefits**:
- Zero manual imports for base functionality
- Single reference in machine configs: `imports = [ config.flake.modules.nixos.base ];`
- Add new system-wide config: create file in `system/` → auto-merged
- Test-clan validated (Stories 1.1-1.7, 17 test cases passing)

**Pattern 2: Portable Home-Manager Modules with Dendritic Integration**

**Problem**: User home-manager configurations need to work across platforms (darwin + NixOS) and support three integration modes (darwin integrated, NixOS integrated, standalone) without duplication.

**Gap Identified (Story 1.8)**: blackphos implemented inline home configs, blocking cross-platform reuse. This is a feature regression from infra's proven modular pattern.

**Solution (Story 1.8A)**: Extract home configs into portable modules that export to dendritic namespace and support all three integration modes.

**Module Structure:**
```nix
# modules/home/users/{username}/default.nix
{
  flake.modules.homeManager."users/{username}" = { config, pkgs, lib, ... }: {
    home.stateVersion = "23.11";
    programs.zsh.enable = true;
    programs.starship.enable = true;
    programs.git.enable = true;
    home.packages = with pkgs; [ git gh ... ];
  };
}
```

**Three Integration Modes:**

**Mode 1: Darwin Integrated** (blackphos example)
```nix
# In darwin machine module
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.crs58.imports = [
    config.flake.modules.homeManager."users/crs58"
  ];
}
```

**Mode 2: NixOS Integrated** (cinnabar Story 1.9)
```nix
# In NixOS machine module
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.crs58.imports = [
    config.flake.modules.homeManager."users/crs58"
  ];
}
```

**Mode 3: Standalone** (nh home CLI workflow)
```nix
# In modules/home/configurations.nix
{
  flake.homeConfigurations.crs58 = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs { system = "aarch64-darwin"; };
    modules = [
      config.flake.modules.homeManager."users/crs58"
    ];
  };
}

# Usage: nh home switch . -c crs58
```

**Benefits:**
- Single source of truth (DRY principle): User defined once, used on 6 machines
- Cross-platform portability: Same module works on darwin and NixOS
- Three deployment contexts: Integrated (system + home), standalone (home only)
- Dendritic auto-discovery: No manual imports in flake.nix
- Username-only naming: No @hostname for maximum portability
- Clan compatible: Users defined per machine, configs imported modularly

**Lesson from Story 1.8:**
Inline home configs are anti-pattern for multi-machine infrastructure. Always modularize user configs to enable cross-platform reuse.

**Pattern 3: Darwin Multi-User with Per-User Vars Naming**

**Problem**: Clan vars generators are machine-scoped, not user-scoped. Multi-user darwin machines (blackphos: raquel + crs58) need separate secrets per user.

**Solution**: Use naming convention in generator names:

```nix
# Generate per-user secrets with naming convention
clan.core.vars.generators."ssh-key-crs58" = {
  files."id_ed25519".neededFor = "users";
  files."id_ed25519.pub".secret = false;
  script = ''ssh-keygen -t ed25519 -N "" -C "crs58@${config.networking.hostName}" -f "$out"/id_ed25519'';
};

clan.core.vars.generators."ssh-key-raquel" = {
  files."id_ed25519".neededFor = "users";
  files."id_ed25519.pub".secret = false;
  script = ''ssh-keygen -t ed25519 -N "" -C "raquel@${config.networking.hostName}" -f "$out"/id_ed25519'';
};

# Result storage
vars/per-machine/blackphos/ssh-key-crs58/id_ed25519
vars/per-machine/blackphos/ssh-key-raquel/id_ed25519
```

**Admin vs Non-Admin Differentiation**:
```nix
# modules/darwin/users.nix
users.users.crs58 = {
  uid = 550;
  extraGroups = [ "admin" ];  # Darwin equivalent of "wheel"
  home = "/Users/crs58";
};

users.users.raquel = {
  uid = 551;
  extraGroups = [ ];  # No admin group = no sudo
  home = "/Users/raquel";
};

# Security configuration
security.sudo.wheelNeedsPassword = false;  # Passwordless sudo for admins
```

**Home-Manager Per-User**:
```nix
home-manager.users.crs58.imports = with config.flake.modules.homeManager; [
  core.zsh
  users.crs58.dev-tools  # Admin user gets full dev environment
];

home-manager.users.raquel.imports = with config.flake.modules.homeManager; [
  core.zsh  # Non-admin gets minimal shell config only
];
```

**Benefits**:
- Standard NixOS user management (no clan-specific patterns)
- Per-user secrets via generator naming convention
- Clear admin/non-admin separation via `extraGroups`
- Home-manager configs scale independently
- Validated in production examples (clan-infra admins.nix, mic92 bernie machine)

**Pattern 3: Darwin Networking Options (Zerotier Workaround)**

**Problem**: Clan zerotier service is NixOS-only (systemd dependencies, no darwin support). Darwin hosts need mesh networking but clan service doesn't work.

**Solution**: Multiple validated options with trade-offs:

**Option A: Homebrew Zerotier** (maintains zerotier consistency):
```nix
# modules/darwin/homebrew.nix
homebrew.enable = true;
homebrew.casks = [ "zerotier-one" ];  # GUI app via homebrew

# Manual network join after installation
# Use clan-generated network-id: /run/secrets/zerotier-network-id
# Command: zerotier-cli join $(cat /run/secrets/zerotier-network-id)
```

**Option B: Custom Launchd Service** (nix-managed zerotier):
```nix
# modules/darwin/zerotier-custom.nix
launchd.daemons.zerotierone = {
  serviceConfig = {
    Program = "${pkgs.zerotierone}/bin/zerotier-one";
    ProgramArguments = [ "${pkgs.zerotierone}/bin/zerotier-one" ];
    KeepAlive = true;
    RunAtLoad = true;
  };
};

# Reference identity from clan vars
environment.etc."zerotier-one/identity.secret".source =
  config.clan.core.vars.generators.zerotier.files.zerotier-identity-secret.path;
```

**Hybrid Approach** (recommended for Story 1.8):
- Use clan vars generators for identity/network-id (platform-agnostic Python scripts)
- Manual zerotier setup on darwin (homebrew or custom launchd)
- Cinnabar controller auto-accepts peers using clan-generated zerotier-ip

**Benefits**:
- Maintains clan vars for identity management (reusable patterns)
- Defers darwin networking implementation to Story 1.8 (experimental validation)
- Multiple proven alternatives (tailscale, homebrew, custom launchd)
- No blocking unknowns for architecture documentation

**Pattern 4: Terranix Toggle-Based Deployment**

**Problem**: Multiple cloud VMs (cinnabar always-on, electrum togglable) need declarative deployment control without destroying terraform state.

**Solution**: Per-machine `enabled` flag in terranix configuration:

```nix
# modules/terranix/hetzner.nix
{ config, lib, ... }:
let
  machines = {
    hetzner-ccx23 = {
      enabled = false;  # Destroy this VM
      server_type = "ccx23";
      location = "nbg1";
    };
    hetzner-cx43 = {
      enabled = true;   # Deploy this VM
      server_type = "cx43";
      location = "fsn1";
    };
  };

  enabledMachines = lib.filterAttrs (_: m: m.enabled) machines;
in
{
  perSystem = { config, pkgs, ... }: {
    terranix.terraform.resource.hcloud_server = lib.mapAttrs (name: cfg: {
      name = name;
      server_type = cfg.server_type;
      location = cfg.location;
      # ...
    }) enabledMachines;
  };
}
```

**Terraform Operations**:
```bash
# Deploy enabled machines only
nix run .#terraform.terraform -- apply

# Toggle machine: set enabled = false → terraform apply → VM destroyed
# Toggle back: set enabled = true → terraform apply → VM recreated
```

**Benefits**:
- Declarative VM lifecycle management
- Toggle without manual terraform destroy commands
- Preserves terraform state for both machines
- Test-clan validated (hetzner-ccx23 toggled off, hetzner-cx43 deployed)

**Pattern 5: Test Harness with Multiple Categories**

**Problem**: Complex infrastructure requires different validation types (fast expression tests, slow VM integration tests, structural validation, performance benchmarks).

**Solution**: Multi-category test harness with selective execution:

```nix
# modules/checks/nix-unit.nix
flake.checks."${system}".test-nix-unit-all = pkgs.stdenv.mkDerivation {
  name = "test-nix-unit-all";
  buildCommand = ''
    export HOME=$TMPDIR
    ${nix-unit}/bin/nix-unit \
      --flake "${self}#checks.${system}.nix-unit-tests" \
      --eval-store "$HOME"
  '';
};

# modules/checks/integration.nix (runNixOSTest)
flake.checks."${system}".test-vm-boot-hetzner-ccx23 =
  self.nixosConfigurations.hetzner-ccx23.config.system.build.vmWithBootLoaderTest or null;
```

**Test Execution Matrix**:
| Category | Tool | Tests | Duration | Systems | Purpose |
|----------|------|-------|----------|---------|---------|
| nix-unit | nix-unit | 11 | ~1s | all (x86_64-linux, aarch64-linux, aarch64-darwin) | Fast expression evaluation |
| integration | runNixOSTest | 2 | ~2-5min | Linux only | VM boot validation |
| validation | runCommand | 4 | ~4s | all | Structural invariants |
| performance | runCommand | 0 | ~0s | all | Build time benchmarks (future) |

**Selective Execution**:
```bash
# Fast tests only (< 5s)
nix flake check --no-build

# Full validation (includes VM tests)
nix flake check

# Specific category
nix build .#checks.x86_64-linux.test-nix-unit-all
```

**Benefits**:
- Fast feedback loop (nix-unit tests ~1s)
- Comprehensive validation (17 test cases across 4 categories)
- Platform-aware (VM tests skip on darwin)
- Test-clan validated (all 17 tests passing)

## Implementation Patterns

### Naming Conventions

**Module Files**:
- **Kebab-case**: `nix-settings.nix`, `admins.nix`, `initrd-networking.nix`
- **Feature-based**: File name = feature name (dendritic principle)
- **Platform prefixes** (when needed): `darwin-base.nix`, `nixos-server.nix`

**Module Namespace**:
- **Platform separation**: `flake.modules.{nixos,darwin,homeManager}.*`
- **Dot notation**: `flake.modules.nixos.base`, `flake.modules.darwin.users`
- **Machine prefix**: `flake.modules.nixos."machines/nixos/cinnabar"`

**Clan Inventory**:
- **Machine names**: Lowercase, single word (cinnabar, blackphos, rosegold, argentum, stibnite)
- **Service instances**: Kebab-case with purpose (zerotier-local, sshd-clan, emergency-access, users-crs58)
- **Tags**: Lowercase, categorical (nixos, darwin, cloud, workstation, primary)

**Vars Generators**:
- **Per-user naming**: `ssh-key-{username}`, `user-password-{username}`
- **Per-service naming**: `openssh`, `zerotier`, `tor-identity`
- **Shared naming**: `openssh-ca` (with `share = true`)

### Code Organization

**Module Structure** (dendritic pattern):
```nix
# modules/system/nix-settings.nix
{
  flake.modules.nixos.base = { config, pkgs, lib, ... }: {
    # Module content auto-merges to base
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "@wheel" ];
    };
  };
}
```

**Machine Configuration**:
```nix
# modules/machines/nixos/cinnabar/default.nix
{ config, ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = { pkgs, lib, ... }: {
    imports = [
      config.flake.modules.nixos.base  # Auto-merged system-wide config
      ./disko.nix                       # Machine-specific disk layout
      ./hardware-configuration.nix      # Generated hardware config
    ];

    # Machine-specific configuration
    networking.hostName = "cinnabar";
    networking.hostId = "8425e349";  # Required for ZFS
    system.stateVersion = "24.11";

    # Clan integration
    nixpkgs.hostPlatform = "x86_64-linux";
  };
}
```

**Home-Manager Configuration**:
```nix
# modules/home/users/crs58/default.nix
{ config, ... }:
{
  flake.modules.homeManager.users-crs58 = { config, pkgs, lib, ... }: {
    # User-specific home configuration
    programs.git = {
      userName = "crs58";
      userEmail = "crs58@example.com";
    };

    # Development tools for admin user
    home.packages = with pkgs; [
      ripgrep
      fd
      jq
      kubectl
    ];
  };
}
```

**Clan Inventory Structure**:
```nix
# modules/clan/inventory/machines.nix
{
  clan.inventory = {
    machines = {
      cinnabar = {
        tags = [ "nixos" "cloud" "vps" "controller" ];
        machineClass = "nixos";
      };
      blackphos = {
        tags = [ "darwin" "workstation" "multi-user" ];
        machineClass = "darwin";
      };
      # ... other machines
    };

    instances = {
      zerotier-local = {
        module = { name = "zerotier"; input = "clan-core"; };
        roles.controller.machines.cinnabar = {};
        roles.peer.tags."all" = {};  # All machines join network
      };
      sshd-clan = {
        module = { name = "sshd"; input = "clan-core"; };
        roles.server.tags."all" = {};
        roles.client.tags."all" = {};
      };
      emergency-access = {
        module = { name = "emergency-access"; input = "clan-core"; };
        roles.default.tags."workstation" = {};  # Workstations only
      };
    };
  };
}
```

### Error Handling

**Flake Evaluation Errors**:
- **Strategy**: Validate with `nix flake check` before deployment
- **Test coverage**: 17 test cases catch structural errors early
- **Error pattern**: Explicit error messages via `assert` or `lib.mkIf` guards

**Example**:
```nix
# modules/machines/nixos/cinnabar/disko.nix
{ lib, ... }:
{
  assertions = [
    {
      assertion = config.networking.hostId != null;
      message = "ZFS requires networking.hostId to be set";
    }
  ];
}
```

**Deployment Errors**:
- **Clan vars generation**: Pre-generate vars before deployment (`clan vars generate <machine>`)
- **Terraform failures**: Use `--dry-run` before `apply`, validate with `terraform plan`
- **SSH access**: Ensure SSH keys in clan vars before remote deployment

**Rollback Strategy**:
```bash
# Per-machine rollback (if deployment fails)
darwin-rebuild switch --flake .#blackphos --rollback

# Terraform rollback
nix run .#terraform.terraform -- destroy  # VPS is disposable, redeploy from config

# Git rollback
git revert <commit>  # Revert to previous working configuration
```

**Error Logging**:
- **System logs**: `journalctl -u clan-vars.service` (vars deployment)
- **Build logs**: `nix log /nix/store/<drv>` (build failures)
- **Terraform logs**: `TF_LOG=DEBUG nix run .#terraform.terraform -- apply` (infrastructure debugging)

### Logging Strategy

**Clan Vars Deployment**:
```nix
# Automatic logging via systemd (NixOS) or launchd (darwin)
systemd.services.clan-vars = {
  serviceConfig.StandardOutput = "journal";
  serviceConfig.StandardError = "journal";
};

# View logs
journalctl -u clan-vars.service --since today
```

**Terraform Operations**:
```bash
# Enable debug logging
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform/debug.log
nix run .#terraform.terraform -- apply
```

**Nix Build Logs**:
```bash
# Verbose build output
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel --print-build-logs

# Store path logs
nix log /nix/store/<drv>
```

**Test Execution Logs**:
```bash
# nix-unit with verbose output
nix-unit --flake ".#checks.x86_64-linux.nix-unit-tests" --verbose

# Integration test logs
nix build .#checks.x86_64-linux.test-vm-boot-hetzner-ccx23 --print-build-logs
```

## Data Architecture

### Clan Vars Storage Structure

**Machine-Scoped Secrets** (default):
```
sops/machines/<machine-name>/
├── secrets/                    # Encrypted secrets (age encryption)
│   ├── zerotier-identity-secret
│   ├── openssh.id_ed25519
│   ├── ssh-key-crs58.id_ed25519      # Per-user secret (naming convention)
│   └── ssh-key-raquel.id_ed25519
└── facts/                      # Public facts (unencrypted)
    ├── zerotier-ip             # IPv6 address in zerotier network
    ├── zerotier-network-id     # Network ID for peers to join
    └── openssh.id_ed25519.pub  # SSH public host key
```

**Shared Secrets** (`share = true` in generator):
```
sops/shared/<generator-name>/
├── openssh-ca.id_ed25519           # SSH CA private key (shared across all machines)
└── openssh-ca.id_ed25519.pub       # SSH CA public key
```

**Terraform State** (git-ignored, sensitive):
```
terraform/
├── terraform.tfstate           # Current infrastructure state
├── terraform.tfstate.backup    # Previous state (automatic backup)
└── .terraform/                 # Provider plugins and modules
```

### Inventory Data Model

**Machine Definition**:
```nix
{
  machineName = {
    tags = [ "platform" "environment" "role" ];  # Tag-based categorization
    machineClass = "nixos" | "darwin";            # Platform type
    installedAt = <timestamp>;                    # Installation timestamp (clan-managed)
  };
}
```

**Service Instance Definition**:
```nix
{
  instanceName = {
    module = {
      name = "service-name";        # Service module name (e.g., "zerotier")
      input = "clan-core" | "self"; # Flake input providing module
    };
    roles = {
      roleName = {
        machines = { machineName = { settings = {}; }; };  # Explicit machine assignment
        tags."tagName" = { settings = {}; };               # Tag-based assignment
        settings = {};                                      # Role-wide settings
      };
    };
    settings = {};  # Instance-wide settings
  };
}
```

**Configuration Hierarchy** (instance → role → machine):
1. Instance-wide settings apply to all roles
2. Role-wide settings override instance settings
3. Machine-specific settings override role settings

### Hardware Configuration Data

**NixOS Hardware** (generated by nixos-generate-config):
```nix
# machines/nixos/cinnabar/hardware-configuration.nix
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  # Disko-managed, included for reference only
  fileSystems."/" = {
    device = "/dev/disk/by-label/zfs";
    fsType = "zfs";
  };

  # Platform
  nixpkgs.hostPlatform = "x86_64-linux";
}
```

**Darwin Hardware** (manual specification):
```nix
# machines/darwin/blackphos/default.nix
{
  # Platform
  nixpkgs.hostPlatform = "aarch64-darwin";

  # macOS-specific settings
  system.stateVersion = 5;
  networking.computerName = "blackphos";
  networking.localHostName = "blackphos";
}
```

## API Contracts

### Dendritic Module Interface

**Module Export Pattern**:
```nix
# Every module contributes to flake.modules.* namespace
{
  flake.modules.<platform>.<feature-name> = { config, pkgs, lib, ... }: {
    # NixOS/darwin/home-manager module content
  };
}
```

**Module Import Pattern**:
```nix
# Machines reference modules via config.flake.modules
{
  imports = with config.flake.modules.<platform>; [
    base           # Auto-merged system-wide config
    feature1       # Explicit feature import
    feature2
  ];
}
```

**Contract**:
- **Input**: Standard NixOS module arguments (`config`, `pkgs`, `lib`, `inputs` via specialArgs)
- **Output**: Configuration merged into machine config
- **No side effects**: Pure configuration, no external state modification
- **Type-safe**: Options declared with explicit types

### Clan Vars Generator Interface

**Generator Definition**:
```nix
{
  clan.core.vars.generators.<generator-name> = {
    files = {
      "<filename>" = {
        secret = true | false;     # Encrypt file? (true = /run/secrets/, false = nix store)
        deploy = true | false;     # Deploy to target machine? (default: true)
        neededFor = [ "users" ];   # Deployment stage (users, boot, network, etc.)
      };
    };
    dependencies = [ "<other-generator>" ];  # Run after these generators
    share = true | false;          # Share across all machines? (default: false)
    prompts = {
      "<prompt-name>" = {
        type = "line" | "hidden" | "multiline";
        description = "User-facing prompt text";
      };
    };
    script = ''
      # Bash script with runtimeInputs available in PATH
      # Output files to $out/<filename>
      # Read prompts from $prompts/<prompt-name>
    '';
    runtimeInputs = [ pkgs.package1 pkgs.package2 ];  # Packages available in script
  };
}
```

**Generator Execution**:
```bash
# Generate vars for a machine
clan vars generate <machine-name>

# Regenerate specific generator
clan vars generate <machine-name> --generator <generator-name>

# View generated facts (public)
clan facts show <machine-name>
```

**Output Structure**:
- **Secrets**: `sops/machines/<machine>/secrets/<generator>.<filename>` (encrypted)
- **Facts**: `sops/machines/<machine>/facts/<generator>.<filename>` (unencrypted)
- **Deployment**: `/run/secrets/<generator>.<filename>` (on target machine)

**Contract**:
- **Idempotent**: Re-running generator produces same output (deterministic where possible)
- **Isolated**: Generators run in isolated environment with only declared runtimeInputs
- **Atomic**: All files generated or none (transaction-like)
- **Versioned**: Generated files tracked in git (sops/), encrypted via age

### Clan Service Instance Interface

**Service Module Contract**:
```nix
{
  _class = "clan.service";  # Required service class marker

  roles.<roleName> = {
    interface.options = {
      # Options available to this role (standard NixOS options)
    };

    perInstance = { lib, config, pkgs, name, value, ... }: {
      nixosModule | darwinModule = { config, ... }: {
        # Configuration applied to machines with this role
        # Access instance settings via value.settings
        # Access role settings via value.roles.<roleName>.settings
      };
    };
  };

  perMachine = { lib, config, pkgs, name, value, ... }: {
    nixosModule | darwinModule = { config, ... }: {
      # Configuration applied to all machines using this service
      # Access machine-specific settings
    };
  };
}
```

**Service Deployment**:
- **Inventory declaration**: Define service instance with roles in `clan.inventory.instances`
- **Machine assignment**: Assign machines to roles via explicit machines or tags
- **Configuration hierarchy**: Instance → Role → Machine settings
- **Module generation**: Clan generates nixosModule/darwinModule per machine

**Built-in Services** (clan-core):
- **zerotier**: Mesh VPN (controller/peer/moon roles)
- **sshd**: SSH daemon with CA certificates (server/client roles)
- **emergency-access**: Root password recovery (default role)
- **users**: User account management (default role)
- **tor**: Tor hidden services (default role)

## Security Architecture

### Secrets Encryption

**Age-Based Encryption** (via clan vars):
- **Admin group keys**: `sops/groups/admins/` (multiple admin age keys)
- **Per-machine keys**: Generated during clan init, used for machine-specific secrets
- **Encryption**: Secrets encrypted with all admin keys + target machine key
- **Decryption**: Only target machine + admins can decrypt secrets

**Key Distribution**:
```bash
# Admin generates age key
clan secrets key generate

# Admin provides public age key to repository maintainer
cat ~/.config/sops/age/keys.txt | grep "public key:"

# Maintainer adds admin to admins group
clan secrets groups add-user admins <username> <age-public-key>

# Admin can now decrypt all secrets
clan vars generate <machine-name>
```

### SSH Access Control

**Certificate-Based Authentication** (clan sshd service):
- **SSH CA**: Centralized certificate authority managed by clan
- **Certificate issuance**: Automatic certificate generation for authorized users
- **No password authentication**: `PasswordAuthentication no` enforced
- **Public key fallback**: SSH keys in `users.users.<user>.openssh.authorizedKeys.keys`

**Root Access**:
```nix
# Auto-grant root access to all wheel users (clan-infra pattern)
users.users.root.openssh.authorizedKeys.keys = builtins.concatMap
  (user: user.openssh.authorizedKeys.keys)
  (builtins.attrValues (
    lib.filterAttrs (_name: value:
      value.isNormalUser && builtins.elem "wheel" value.extraGroups
    ) config.users.users
  ));
```

**Emergency Access** (clan emergency-access service):
- **Password recovery**: Root password set via clan vars (workstations only)
- **Console access**: Login via console/physical access with emergency password
- **Not on VPS**: Emergency access disabled on VPS to prevent remote exploitation

### Firewall Configuration

**NixOS Firewall** (cinnabar/electrum):
```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 ];         # SSH
  allowedUDPPorts = [ 9993 ];       # Zerotier
  interfaces."zt*".allowedTCPPorts = [ ];  # Zerotier interfaces (mesh-internal services)
};
```

**Darwin Firewall**:
```nix
# macOS built-in firewall (socketfilterfw)
system.defaults.alf = {
  globalstate = 1;                  # Firewall enabled
  allowsignedenabled = 1;           # Allow signed applications
  stealthenabled = 1;               # Stealth mode (don't respond to ping)
};
```

### VPS Hardening

**srvos Modules** (clan-infra pattern):
```nix
imports = [
  inputs.srvos.nixosModules.server            # Security baseline
  inputs.srvos.nixosModules.mixins-nix-experimental  # Nix experimental features
];
```

**Hardening Features**:
- Minimal package set (no unnecessary packages)
- SSH hardening (key-only auth, no root password login)
- Automatic security updates (nixpkgs tracking)
- Restricted systemd service permissions
- Audit logging enabled

### Zerotier Network Security

**Mesh VPN Encryption**:
- **End-to-end encryption**: All traffic encrypted with AES-256
- **Network isolation**: Separate zerotier network for infrastructure
- **Controller authorization**: Peers require controller approval (auto-accept via inventory)

**Network Access Control**:
```nix
# Cinnabar controller auto-accepts peers from inventory
systemd.services.zerotier-inventory-autoaccept = {
  # Automatically authorize peers based on zerotier-ip fact
  # Only machines in clan inventory are auto-accepted
};
```

## Performance Considerations

### Build Performance

**Baseline Measurements** (test-clan validation):
- **Flake evaluation**: ~1-2s (pure import-tree, 29 modules)
- **NixOS build** (cinnabar): ~45s (cached), ~5min (uncached)
- **Darwin build** (test-darwin): ~30s (cached), ~3min (uncached)
- **Test suite** (17 tests): ~5s (fast), ~11s (with integration)

**Optimization Strategies**:
- **Shared nixpkgs**: `useGlobalPkgs = true` (share packages across system/home-manager)
- **Binary cache**: Use cachix or nix-community cache for common packages
- **Parallel builds**: `nix.settings.max-jobs = "auto"` (utilize all CPU cores)
- **Flake lock**: Pin dependencies to avoid unexpected rebuilds

### Deployment Performance

**Clan Vars Generation**:
- **Per-machine**: ~2-5s (generate identity + secrets)
- **Parallelizable**: Generate vars for multiple machines concurrently
- **Cached**: Vars only regenerated if generator changes

**Terraform Operations**:
- **Plan**: ~5-10s (API queries to cloud providers)
- **Apply** (new VPS): ~2-3min (VM creation + SSH key distribution)
- **Apply** (no changes): ~5s (state verification only)

**System Activation**:
- **darwin-rebuild switch**: ~10-30s (depending on changes)
- **nixos-rebuild switch**: ~20-60s (depending on changes)
- **Remote deployment**: Add ~10-30s for SSH overhead + nix-copy-closure

### Network Performance

**Zerotier Latency**:
- **Direct connection** (local network): ~1-5ms overhead
- **Relayed connection** (via moon): ~20-50ms overhead (depends on moon location)
- **WAN latency**: Depends on internet connection (not critical for development)

**Build Transfer**:
- **nix-copy-closure**: Transfer built artifacts to remote machines
- **Optimization**: Use `--use-substitutes` to fetch from binary cache on target

### Scalability Limits

**Current Fleet**: 5 machines (1 VPS + 4 darwin workstations)

**Proven Scalability** (from production examples):
- **clan-infra**: 20+ machines (web servers, build machines, jitsi, gitea)
- **Dendritic pattern**: Scales to hundreds of modules (drupol-dendritic-infra)
- **Zerotier**: Free tier supports up to 100 peers

**Performance Bottlenecks**:
- **Flake evaluation**: Linear with module count (import-tree auto-discovery overhead)
- **Test suite**: Integration tests scale with VM count (2-5min per VM)
- **Terraform state**: Single state file for all infrastructure (manual locking)

## Deployment Architecture

### Development Workflow

**Local Development**:
```bash
# Activate development shell (direnv automatic)
cd ~/projects/nix-workspace/infra
direnv allow  # or: nix develop

# Validate changes
nix flake check                  # Fast structural validation
nix build .#darwinConfigurations.blackphos.system --dry-run  # Build check

# Run test suite
nix build .#checks.x86_64-linux.test-nix-unit-all  # Fast tests (~1s)
nix flake check                                     # Full validation (~11s)

# Generate vars for machine
clan vars generate blackphos

# Deploy to local machine
darwin-rebuild switch --flake .#blackphos

# Deploy to remote machine (VPS)
clan machines update cinnabar
```

**Git Workflow**:
```bash
# Development on clan branch
git checkout clan
git pull origin clan

# Per-host feature branches (optional)
git checkout -b blackphos-migration
# ... make changes ...
git commit -m "feat(blackphos): migrate to dendritic + clan"
git push origin blackphos-migration

# Merge after validation
git checkout clan
git merge blackphos-migration
```

### Terraform Deployment

**Infrastructure Provisioning**:
```bash
# Generate terraform configuration
nix build .#terraform.terraform

# Initialize terraform
nix run .#terraform.terraform -- init

# Plan changes (dry-run)
nix run .#terraform.terraform -- plan

# Apply changes
nix run .#terraform.terraform -- apply

# Destroy infrastructure (toggle enabled=false in config, then apply)
nix run .#terraform.terraform -- apply
```

**State Management**:
- **Local state**: `terraform/terraform.tfstate` (git-ignored)
- **Manual locking**: Single developer, no remote state backend needed
- **Backup**: `terraform.tfstate.backup` automatically created

### NixOS VPS Deployment

**Initial Installation** (Hetzner Cloud):
```bash
# 1. Provision VPS via terraform
nix run .#terraform.terraform -- apply

# 2. Install NixOS via clan (automatic disko partitioning)
clan machines install cinnabar --target-host root@<ip> --update-hardware-config nixos-facter --yes

# 3. System boots with full configuration
# SSH access via clan sshd service (certificate-based)
# Zerotier controller operational
# Clan vars deployed to /run/secrets/
```

**Configuration Updates**:
```bash
# Generate vars (if generator changed)
clan vars generate cinnabar

# Deploy configuration update
clan machines update cinnabar

# Or use nixos-rebuild directly
nixos-rebuild switch --flake .#cinnabar --target-host root@cinnabar.zerotier.ip
```

### Darwin Deployment

**Initial Setup** (blackphos example):
```bash
# 1. Create machine configuration
# modules/machines/darwin/blackphos/default.nix created

# 2. Add to clan inventory
# modules/clan/inventory/machines.nix: blackphos entry added

# 3. Generate vars
clan vars generate blackphos

# 4. Deploy on machine (local execution)
cd ~/projects/nix-workspace/infra
darwin-rebuild switch --flake .#blackphos

# 5. Join zerotier network (if using zerotier)
# Manual or homebrew-based setup (see Darwin Networking Options)
```

**Configuration Updates**:
```bash
# On blackphos machine
cd ~/projects/nix-workspace/infra
git pull origin clan
darwin-rebuild switch --flake .#blackphos
```

### Rollback Procedures

**Per-Machine Rollback**:
```bash
# Darwin (boot menu selection or command)
darwin-rebuild switch --flake .#blackphos --rollback

# NixOS (boot menu selection or command)
nixos-rebuild switch --flake .#cinnabar --rollback --target-host root@cinnabar.zerotier.ip
```

**Git-Based Rollback**:
```bash
# Revert last commit
git revert HEAD

# Redeploy previous configuration
darwin-rebuild switch --flake .#blackphos
```

**Terraform Rollback**:
```bash
# VPS is disposable - destroy and recreate
nix run .#terraform.terraform -- destroy
nix run .#terraform.terraform -- apply
clan machines install cinnabar  # Reinstall from configuration
```

### CI/CD Integration

**GitHub Actions** (future enhancement):
```yaml
name: Validation

on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - run: nix flake check
```

**Pre-Commit Hooks** (current):
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks  # Prevent committing secrets

  - repo: https://github.com/nix-community/nixpkgs-fmt
    rev: master
    hooks:
      - id: nixfmt-rfc-style  # Nix code formatting
```

## Development Environment

### Prerequisites

**Host Machine Requirements**:
- **NixOS**: 24.11+ or darwin: macOS 13+ (Ventura or later)
- **Nix package manager**: 2.18+ with flakes enabled
- **Disk space**: 20GB+ free (for nix store, builds, VMs)
- **Internet**: Required for flake inputs, binary caches, terraform

**Developer Tools**:
- **Git**: 2.40+ (for repository management)
- **direnv**: 2.32+ (automatic nix develop activation)
- **Age**: 1.1+ (for secrets encryption, installed via nix)
- **Zerotier CLI**: 1.14+ (for network management, installed via nix or homebrew)

**Optional Tools**:
- **nix-unit**: For running test suite locally
- **terraform**: For manual infrastructure operations (provided via flake)
- **cachix**: For binary cache (faster builds)

### Setup Commands

**Initial Repository Setup**:
```bash
# Clone repository
git clone https://github.com/cameronraysmith/nix-config.git ~/projects/nix-workspace/infra
cd ~/projects/nix-workspace/infra

# Checkout migration branch
git checkout clan

# Allow direnv (automatic nix develop)
direnv allow

# Initialize clan secrets (first-time only)
nix run nixpkgs#clan-cli -- secrets key generate
YOUR_AGE_KEY=$(grep 'public key:' ~/.config/sops/age/keys.txt | awk '{print $4}')
echo "Provide this age key to repository maintainer: $YOUR_AGE_KEY"

# After maintainer adds you to admins group
clan secrets groups show admins  # Verify you're listed

# Generate vars for machine you'll manage
clan vars generate blackphos  # or cinnabar, etc.
```

**Hetzner Cloud Setup** (for VPS provisioning):
```bash
# Obtain API token from Hetzner Cloud console
# Store in clan secrets
clan secrets set hetzner-api-token
# Paste token when prompted
```

**Validation**:
```bash
# Verify flake evaluates
nix flake show

# Run test suite
nix flake check

# Build machine configuration (dry-run)
nix build .#darwinConfigurations.blackphos.system --dry-run
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel --dry-run
```

**Development Shell Activated**:
```bash
# Check available commands (from devShell)
nix flake show

# Available commands
clan                # Clan CLI for machine management
terraform           # Terraform CLI (via terranix)
nix-unit            # Test runner
# ... other tools in devShell
```

### Editor Integration

**VSCode/VSCodium**:
```json
// .vscode/settings.json
{
  "nix.enableLanguageServer": true,
  "nix.serverPath": "nil",
  "[nix]": {
    "editor.defaultFormatter": "jnoortheen.nix-ide",
    "editor.formatOnSave": true
  }
}
```

**Neovim** (with nil LSP):
```lua
-- ~/.config/nvim/lua/lsp.lua
require('lspconfig').nil_ls.setup({
  settings = {
    ['nil'] = {
      formatting = { command = { "nixfmt" } },
    },
  },
})
```

**Direnv Integration** (automatic nix develop):
```bash
# .envrc (already in repository)
use flake

# Allow direnv
direnv allow

# Shell automatically loads nix develop when entering directory
```

## Darwin Networking Options

**Problem**: Clan's zerotier service is NixOS-only (systemd dependencies, no darwin module). Darwin machines need alternative networking approach.

### Option 1: Homebrew Zerotier (Maintains Consistency)

**Status**: ⚠️ Unvalidated (theoretical, requires Story 1.8 testing)

**Setup**:
```nix
# modules/darwin/homebrew.nix
{
  homebrew.enable = true;
  homebrew.casks = [ "zerotier-one" ];
}

# Deploy
darwin-rebuild switch --flake .#blackphos

# Manual network join (after GUI installation)
# 1. Open Zerotier One from Applications
# 2. Join network: cat /run/secrets/zerotier-network-id
# 3. Verify: zerotier-cli status
```

**Integration with Clan Vars**:
```bash
# Network ID from clan vars (generated on controller)
NETWORK_ID=$(cat /run/secrets/zerotier-network-id)

# Join network (command-line alternative to GUI)
zerotier-cli join $NETWORK_ID

# Verify connection
zerotier-cli listnetworks
zerotier-cli listpeers
```

**Pros**:
- Maintains zerotier consistency with NixOS machines
- Uses clan-generated network-id (partial integration)
- GUI app for management
- Same VPN as test-clan validation

**Cons**:
- Not fully nix-managed (homebrew + GUI app)
- Manual network join required
- No automatic peer acceptance (controller auto-accept may not work)
- Requires testing in Story 1.8

### Option 2: Custom Launchd Service (Full Nix Control)

**Status**: ⚠️ Unvalidated (complex, inspired by mic92 hyprspace pattern)

**Setup**:
```nix
# modules/darwin/zerotier-custom.nix
{ config, pkgs, lib, ... }:
{
  # Install zerotier-one package
  environment.systemPackages = [ pkgs.zerotierone ];

  # Custom launchd service
  launchd.daemons.zerotierone = {
    serviceConfig = {
      ProgramArguments = [ "${pkgs.zerotierone}/bin/zerotier-one" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/var/log/zerotier-one.log";
      StandardErrorPath = "/var/log/zerotier-one.log";
    };
  };

  # Deploy identity from clan vars
  environment.etc."zerotier-one/identity.secret" = {
    source = config.clan.core.vars.generators.zerotier.files.zerotier-identity-secret.path;
    mode = "0600";
  };

  # Join network on activation
  system.activationScripts.zerotier-join.text = ''
    sleep 5  # Wait for zerotier-one to start
    NETWORK_ID=$(cat ${config.clan.core.vars.generators.zerotier.files.zerotier-network-id.path})
    ${pkgs.zerotierone}/bin/zerotier-cli join $NETWORK_ID
  '';
}
```

**Pros**:
- Fully declarative (nix-managed)
- Integrates with clan vars (identity + network-id)
- No GUI app required
- Maximum control over zerotier configuration

**Cons**:
- Complex implementation (requires darwin launchd expertise)
- Untested (requires Story 1.8 validation)
- May have edge cases (identity deployment timing, service lifecycle)
- Higher maintenance burden

### Option 3: Hybrid Clan Vars + Manual Zerotier (Pragmatic)

**Status**: ✅ Recommended for Story 1.8 (minimal risk, validates integration)

**Setup**:
```nix
# Use clan vars generators (platform-agnostic)
clan.core.vars.generators.zerotier = {
  files.zerotier-ip.secret = false;
  files.zerotier-identity-secret = { };
  files.zerotier-network-id.secret = false;
  script = ''
    python3 ${./generate.py} --mode identity \
      --ip "$out/zerotier-ip" \
      --identity-secret "$out/zerotier-identity-secret" \
      --network-id ${networkId}
  '';
};

# Manual zerotier setup (homebrew or custom)
# Clan controller (cinnabar) auto-accepts peer using zerotier-ip fact
```

**Workflow**:
```bash
# 1. Generate vars on darwin machine
clan vars generate blackphos

# 2. Install zerotier (manual or homebrew)
# Option A: brew install zerotier-one
# Option B: Download from zerotier.com

# 3. Join network using clan-generated network-id
NETWORK_ID=$(cat /run/secrets/zerotier-network-id)
zerotier-cli join $NETWORK_ID

# 4. Verify controller auto-accepts (cinnabar sees blackphos zerotier-ip)
ssh root@cinnabar.zerotier.ip "zerotier-cli listpeers | grep blackphos"
```

**Pros**:
- Reuses clan vars infrastructure (identity generation proven)
- Minimal custom code (leverage existing zerotier installation methods)
- Validates clan var integration patterns before full automation
- Easy to upgrade to Option 2 or 3 later (vars already generated)

**Cons**:
- Partially manual (not fully declarative)
- Requires documentation for manual steps
- Network join not automatic on system activation

### Recommendation for Story 1.8

**Use Option 3 (Hybrid Clan Vars + Manual Zerotier)** for initial validation:

1. Validates clan vars integration with darwin
2. Proves controller auto-accept works with darwin peers
3. Minimal risk (manual fallback if issues)
4. Provides data for architecture refinement

**Future Enhancement** (Epic 2+):
- Implement Option 1 (Homebrew) if zerotier consistency is priority
- Implement Option 2 (Custom Launchd) if full nix control required

**Decision Deferred to Story 1.8**: Test hybrid approach, gather data, refine architecture based on findings.

## Architecture Decision Records (ADRs)

### ADR-001: Adopt Dendritic Flake-Parts + Clan-Core Integration

**Status**: Accepted (validated in test-clan Stories 1.1-1.7)

**Context**: Current nixos-unified architecture lacks type safety, has unclear module boundaries, and doesn't support multi-machine coordination. Dendritic flake-parts provides type-safe namespace organization, clan-core provides multi-machine inventory system, but no production examples combine them.

**Decision**: Adopt dendritic flake-parts pattern with clan-core integration, validated through test-clan Phase 0 before production deployment.

**Consequences**:
- ✅ Maximum type safety via module system option declarations
- ✅ Clear module namespace (`flake.modules.*`)
- ✅ Multi-machine coordination via clan inventory
- ✅ Zero-regression validation (17 test cases in test-clan)
- ⚠️ Minimal specialArgs required (framework values only)
- ⚠️ Auto-merge base modules (pragmatic dendritic adaptation)
- ❌ No pure dendritic orthodoxy (clan functionality takes precedence)

### ADR-002: Use ZFS Unencrypted (Defer LUKS)

**Status**: Accepted (implemented in test-clan Stories 1.4-1.5)

**Context**: Original plan included LUKS encryption for VPS. ZFS provides compression, snapshots, and integrity checking. LUKS adds complexity (initrd networking for remote unlock) and minor performance overhead.

**Decision**: Use unencrypted ZFS for VPS (cinnabar, electrum), defer LUKS to future enhancement if security requirements change.

**Consequences**:
- ✅ Simplified VPS deployment (no initrd SSH setup)
- ✅ ZFS benefits (compression=zstd, snapshots, integrity)
- ✅ Faster deployment (no encryption key management)
- ⚠️ Data at rest not encrypted (acceptable for infrastructure configuration)
- ⏭️ Can add LUKS later without architectural changes (disko supports both)

### ADR-003: Progressive Migration with Stability Gates

**Status**: Accepted (defined in PRD, validated in test-clan)

**Context**: Brownfield migration across 5 heterogeneous machines (1 VPS + 4 darwin) with unproven architectural combination. Primary workstation (stibnite) is daily productivity critical.

**Decision**: Migrate progressively (test-clan validation → cinnabar → blackphos → rosegold → argentum → stibnite) with 1-2 week stability gates between phases, primary workstation last.

**Consequences**:
- ✅ Risk mitigation (each phase validates before next)
- ✅ Rollback capability (per-host, independent)
- ✅ Pattern refinement (learnings from early phases improve later phases)
- ✅ Primary workstation protected (only migrated after 4-6 weeks cumulative stability)
- ⚠️ Extended timeline (13-15 weeks conservative, 4-6 weeks aggressive)
- ⚠️ Dual architecture maintenance (nixos-unified + dendritic during migration)

### ADR-004: Darwin Networking via Multiple Options (Deferred to Story 1.8)

**Status**: Proposed (decision deferred to Story 1.8 experimental validation)

**Context**: Clan zerotier service is NixOS-only (systemd dependencies). Darwin requires alternative approach. Three options identified: Homebrew Zerotier, Custom Launchd, Hybrid Clan Vars + Manual. Tailscale eliminated due to incompatibility with darwin machines serving as VPN mesh servers.

**Decision**: Test hybrid approach (Option 3) in Story 1.8, defer final decision based on validation findings.

**Consequences**:
- ✅ Validates clan vars integration with darwin
- ✅ Proves controller auto-accept works with darwin peers
- ✅ Multiple fallback options (homebrew, custom launchd)
- ⚠️ Partially manual (not fully declarative initially)
- ⏭️ Architecture refinement after Story 1.8 data collection

### ADR-005: Multi-User via Standard NixOS Patterns (No Clan Magic)

**Status**: Accepted (validated via source code analysis of production examples)

**Context**: Multi-user darwin machines (blackphos: raquel + crs58, rosegold: janettesmith + crs58, argentum: christophersmith + crs58) require per-user secrets and home-manager configs. Clan has no built-in user management.

**Decision**: Use standard NixOS `users.users` for user definitions, per-user vars generator naming convention (`ssh-key-{username}`), separate home-manager modules per user.

**Consequences**:
- ✅ Standard patterns (no clan lock-in)
- ✅ Validated in production (clan-infra admins.nix, mic92 bernie machine)
- ✅ Clear admin/non-admin separation via `extraGroups = ["wheel"]`
- ✅ Home-manager scales independently
- ⚠️ Per-user secrets via naming convention (not first-class clan feature)
- ✅ No special clan user management needed

### ADR-006: Remove nixos-unified (Post-Migration Only)

**Status**: Accepted (cleanup in Epic 7 after all hosts migrated)

**Context**: nixos-unified uses specialArgs + directory autowire, incompatible with dendritic pattern (config.flake.*). Both cannot coexist cleanly.

**Decision**: Maintain nixos-unified during migration (Epics 1-6), remove completely in Epic 7 cleanup after all hosts migrated.

**Consequences**:
- ✅ Rollback safety (can revert to nixos-unified during migration)
- ✅ Progressive elimination (per-host migration reduces nixos-unified footprint)
- ✅ Clean final architecture (no legacy after Epic 7)
- ⚠️ Dual architecture maintenance (temporary complexity)
- ⚠️ Explicit removal step required (Epic 7, Story 7.1)

---

_Generated by BMAD Decision Architecture Workflow v1.3.2_
_Date: 2025-11-11_
_For: Dev_
