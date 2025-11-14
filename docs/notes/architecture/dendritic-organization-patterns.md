# Dendritic Flake-Parts Configuration Organization Investigation

## Executive Summary

Investigation of dendritic flake-parts architectures (gaetanlepage primary, secondary references) combined with test-clan's existing clan-core integration reveals a clear pattern for organizing nixosConfigurations and darwinConfigurations. The key insight is separating module registration (flake namespace) from machine instantiation (clan.machines), enabling modular composition while maintaining clarity across Unix-like systems.

---

## A. gaetanlepage nixosConfigurations Pattern (Proven Standard)

### Directory Structure

```
modules/
├── flake/                          # Flake output registration
│   ├── hosts.nix                   # Core config: nixosConfigurations, homeConfigurations
│   ├── colmena.nix
│   ├── deploy-rs.nix
│   └── systems.nix
├── hosts/                          # Machine-specific modules (NOT directly in flake outputs)
│   ├── backup/
│   │   ├── _hardware.nix
│   │   ├── _wireguard/
│   │   ├── _zfs.nix
│   │   └── default.nix             # Machine definition (registers to flake namespace)
│   ├── builder/
│   │   ├── default.nix
│   │   └── ...
│   ├── framework/                  # Complex host example
│   │   ├── autofs.nix
│   │   ├── default.nix
│   │   ├── disko.nix
│   │   ├── hardware.nix
│   │   ├── home/
│   │   │   ├── default.nix
│   │   │   └── ...
│   │   ├── login.nix
│   │   ├── misc.nix
│   │   └── wireguard/
│   └── vps/
│       ├── default.nix
│       └── _nixos/
├── nixos/                          # System-level modules (shared across hosts)
│   ├── core/                       # Base: bootloader, nix, users, security
│   │   ├── agenix.nix
│   │   ├── bootloader.nix
│   │   ├── imports.nix
│   │   ├── misc.nix
│   │   ├── nix.nix
│   │   ├── packages.nix
│   │   ├── security.nix
│   │   ├── ssh-server.nix
│   │   ├── users.nix
│   │   └── wireguard-client.nix
│   ├── desktop/                    # Desktop profile (GUI, display, audio)
│   ├── dev/                        # Development tools
│   ├── nvidia.nix
│   └── server/                     # Server profile (caddy, cloud-backup)
└── home/                           # Home-manager modules (user-level)
    ├── core/
    ├── desktop/
    └── ssh-hosts/
```

### File Structure Per Host

Each host directory contains:
- **`default.nix`** - Machine definition (registers to flake namespace, declares system options)
- **`hardware.nix`** - Hardware-specific (bootloader, device drivers, CPU settings)
- **`disko.nix`** - Disk layout and partitioning
- **`misc.nix`** or specific files - Features (networking, services, custom configurations)
- **`home/`** subdirectory - Home-manager configs for users on this host

Example: `hosts/framework/default.nix`:
```nix
{ config, ... }:
{
  nixosHosts.framework = {
    unstable = true;
  };

  flake.modules.nixos.host_framework.imports = with config.flake.modules.nixos; [
    desktop
    dev
  ];
}
```

### Module Composition Approach

1. **System modules first** (`modules/nixos/core`, `modules/nixos/desktop`, etc.)
   - Reusable across hosts
   - Organized by functional concern
   - Imported via `config.flake.modules.nixos.*` from flake namespace

2. **Host-specific configuration** (`modules/hosts/<hostname>/default.nix`)
   - Registers host to flake namespace: `flake.modules.nixos.host_<hostname>`
   - Declares `nixosHosts.<hostname>` options (system, unstable flag)
   - Imports system modules with host-specific overrides

3. **Hardware/disko/misc files** in host directory
   - Not directly imported by default
   - Imported conditionally by host's `default.nix`

### Namespace and Export Pattern

**In `flake/hosts.nix`** (the registration layer):

```nix
hostTypeNixos = types.submodule [
  baseHostModule
  (
    { name, ... }:
    {
      modules = [
        config.flake.modules.nixos.core
        { networking.hostName = name; }
        (config.flake.modules.nixos."host_${name}" or { })
      ];
    }
  )
];

config.flake.nixosConfigurations =
  let
    mkHost = hostname: options:
      options.nixpkgs.lib.nixosSystem {
        inherit (options) system modules;
        specialArgs.inputs = inputs;
      };
  in
  lib.mapAttrs mkHost config.nixosHosts;
```

**Key insight:** The namespace is hierarchical:
- `config.flake.modules.nixos.core` - shared base
- `config.flake.modules.nixos.desktop` - desktop profile
- `config.flake.modules.nixos.host_<name>` - host-specific (auto-constructed)
- `config.nixosHosts.<name>` - host metadata (system, unstable flag)

### Import-Tree Usage

Flake root:
```nix
outputs = { flake-parts, ... }@inputs:
  flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
```

Import-tree auto-discovers all `.nix` files in `modules/` and makes them available as flake-parts modules. Each module contributes to the flake output via `flake.*` namespace.

---

## B. darwinConfigurations Pattern (Secondary References)

### Reference Implementation: test-clan

**Note:** gaetanlepage has no darwin configs (nixos-only). Darwin patterns come from:
- `test-clan` (existing + validation)
- `mic92-clan-dotfiles` (darwin modules as reference)
- `qubasa-clan-infra` (clan integration pattern)

### Directory Structure (test-clan pattern)

```
modules/
├── machines/
│   ├── nixos/
│   │   ├── cinnabar/
│   │   ├── electrum/
│   │   └── gcp-vm/
│   ├── darwin/
│   │   ├── blackphos/
│   │   │   └── default.nix
│   │   └── test-darwin/
│   │       └── default.nix
│   └── home/
│       └── .keep
├── darwin/                        # Darwin-specific system modules
│   └── base.nix
├── system/                        # Nixos-specific system modules
│   ├── nix-settings.nix
│   ├── admins.nix
│   └── initrd-networking.nix
├── home/
│   └── users/
│       ├── crs58/
│       │   └── default.nix
│       └── raquel/
│           └── default.nix
└── clan/                          # Clan-specific (inventory, machines)
    ├── machines.nix
    ├── inventory/
    └── ...
```

### File Structure Per Darwin Host

Each darwin host (`machines/darwin/<hostname>/default.nix`):
- Minimal structure (compared to nixos)
- Registers to flake namespace: `flake.modules.darwin."machines/darwin/<hostname>"`
- Imports base + optional darwin-specific modules
- Home-manager embedded within darwin config via `home-manager.users.*`

Example: `machines/darwin/blackphos/default.nix` (139 lines):
```nix
{
  flake.modules.darwin."machines/darwin/blackphos" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        inputs.home-manager.darwinModules.home-manager
      ]
      ++ (with flakeModules; [
        base
        # Note: Not importing users module (defines testuser at UID 550)
        # blackphos defines its own users (crs58 + raquel)
      ]);

      # Host identification
      networking.hostName = "blackphos";
      networking.computerName = "blackphos";

      # Platform
      nixpkgs.hostPlatform = "aarch64-darwin";

      # System state version
      system.stateVersion = lib.mkForce 4;

      # Primary user
      system.primaryUser = "crs58";

      # Homebrew configuration
      homebrew = {
        enable = true;
        casks = [ ... ];
        masApps = { ... };
      };

      # Users
      users.users.crs58 = { ... };
      users.users.raquel = { ... };

      # Home-Manager
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.crs58.imports = [ flakeModulesHome."users/crs58" ];
        users.raquel.imports = [ flakeModulesHome."users/raquel" ];
      };
    };
}
```

### Differences from nixos Pattern

| Aspect | nixos | darwin |
|--------|-------|--------|
| **Hardware config** | Separate files (hardware.nix, disko.nix) | Embedded in main config |
| **Users** | System users defined in shared base or host config | Each darwin host manages own users |
| **Home-Manager** | Separate homeConfigurations (standalone or per-host) | Embedded within darwinConfiguration |
| **Package manager** | nixpkgs only | nixpkgs + homebrew (macOS-specific) |
| **System state** | stateVersion per-host | stateVersion per-host (often lower than nixos) |
| **File structure** | More granular (hardware, disko, features) | Single default.nix per host |

### Namespace and Export Pattern

**Darwin modules are registered similarly to nixos:**

```nix
flake.modules.darwin."machines/darwin/<hostname>" = { ... };
```

**But clan.machines instantiation differs:**

```nix
{ config, ... }:
{
  clan.machines = {
    blackphos = {
      imports = [ config.flake.modules.darwin."machines/darwin/blackphos" ];
    };
  };
}
```

---

## C. Clan Integration Structural Impact

### Clan.machines vs flake outputs

Clan uses a two-level system:
1. **Module registration** in flake namespace (same as pure dendritic)
2. **Machine instantiation** in `clan.machines` (clan-specific, not flake.nixosConfigurations/darwinConfigurations)

### Pattern from test-clan and qubasa-clan-infra

**Clan flake.nix entry:**
```nix
clan = inputs.clan-core.lib.clan {
  imports = [ ./clan.nix ];
  machines = {
    cinnabar = { imports = [ ... ]; };
    electrum = { imports = [ ... ]; };
    blackphos = { imports = [ ... ]; };
  };
};

flake.outputs = {
  inherit (clan.config) nixosConfigurations clanInternals;
  clan = clan.config;
};
```

**Key insight:** Clan generates `nixosConfigurations` internally; dendritic modules are imported into clan's machine definitions, not vice versa.

### Clan inventory.instances (service definitions)

Clan adds a layer beyond NixOS modules: **service instances** that span machines.

From `test-clan/modules/clan/inventory/`:
- `services/zerotier.nix` - ZeroTier VPN roles and settings
- `services/internet.nix` - Internet connectivity per machine
- `services/users.nix` - User definitions (separate from system.users)
- `services/tor.nix` - Tor server/client roles

These are **not** dendritic flake.modules. They're clan-specific inventory patterns.

### Compatibility Notes

1. **Clan and dendritic coexist peacefully:**
   - Dendritic modules (`flake.modules.nixos.*`, `flake.modules.darwin.*`) are composable
   - Clan machines import these dendritic modules
   - No conflicts

2. **Home-manager in clan context:**
   - Can be embedded (darwin pattern in test-clan)
   - Or standalone (clan users instance + home configs separately)

3. **Inventory/service instances are orthogonal:**
   - Don't affect dendritic module organization
   - Live in separate namespace: `clan.inventory.instances`

---

## D. Recommended Patterns for test-clan (Story 1.10)

### Proposed Directory Structure

```
modules/
├── machines/
│   ├── nixos/
│   │   ├── cinnabar/                # Existing: Hetzner zerotier coordinator
│   │   │   ├── default.nix
│   │   │   ├── hardware.nix         # Hetzner hardware specifics
│   │   │   ├── disko.nix
│   │   │   └── services.nix         # ZeroTier, networking, terraform
│   │   ├── electrum/                # Existing: ephemeral VPS
│   │   │   └── default.nix
│   │   └── gcp-vm/                  # Existing: GCP VPS
│   │       └── default.nix
│   ├── darwin/
│   │   ├── blackphos/               # Target: raquel's MacBook
│   │   │   ├── default.nix
│   │   │   ├── homebrew.nix         # Homebrew casks/masApps
│   │   │   ├── users.nix            # Users: crs58, raquel
│   │   │   └── services.nix         # ZeroTier, SSH, nix-daemon
│   │   └── test-darwin/             # Existing: test machine
│   │       └── default.nix
│   └── home/                        # Future: standalone home-only configs
│       └── .keep
├── darwin/                          # Darwin system modules (not host-specific)
│   ├── base.nix
│   └── services.nix                 # If darwin-specific services emerge
├── nixos/                           # Nixos system modules (not host-specific)
│   ├── base.nix
│   ├── services.nix                 # If nixos-specific services emerge
│   └── hardware/
│       ├── hetzner.nix              # Hetzner-specific (cinnabar)
│       └── gcp.nix                  # GCP-specific (gcp-vm)
├── system/                          # Shared across all systems
│   ├── nix-settings.nix
│   ├── admins.nix
│   └── ...
├── home/                            # Home-manager modules
│   └── users/
│       ├── crs58/
│       │   └── default.nix
│       └── raquel/
│           └── default.nix
├── clan/                            # Clan-specific
│   ├── machines.nix                 # Instantiate clan.machines from flake.modules
│   ├── inventory/
│   │   ├── machines.nix
│   │   └── services/
│   │       ├── zerotier.nix
│   │       ├── internet.nix
│   │       └── users.nix
│   └── core.nix
└── checks/                          # Validation
    └── ...
```

### Specific Recommendations for blackphos (Story 1.10)

#### File: `modules/machines/darwin/blackphos/default.nix` (single file, comprehensive)

Structure:
```nix
{ config, pkgs, lib, inputs, ... }:
{
  flake.modules.darwin."machines/darwin/blackphos" =
    { ... }:
    {
      imports = [
        inputs.home-manager.darwinModules.home-manager
      ] ++ (with config.flake.modules.darwin; [
        base
      ]);

      # 1. Host identification
      networking.hostName = "blackphos";
      networking.computerName = "blackphos";
      nixpkgs.hostPlatform = "aarch64-darwin";

      # 2. Users (crs58 admin, raquel primary)
      users.users.crs58 = { ... };
      users.users.raquel = { ... };
      users.knownUsers = [ "crs58" "raquel" ];

      # 3. Homebrew (GUI apps, mac-app-store)
      homebrew = { ... };

      # 4. System packages
      environment.systemPackages = [ ... ];

      # 5. Home-manager
      home-manager = {
        users.crs58.imports = [ config.flake.modules.homeManager."users/crs58" ];
        users.raquel.imports = [ config.flake.modules.homeManager."users/raquel" ];
      };
    };
}
```

#### Decision: Single file vs split

**Rationale for single file:**
- Darwin hosts are simpler than nixos (no hardware.nix, disko.nix)
- Embedded home-manager is cleaner than separate homeConfigurations
- 100-150 lines is manageable and reduces indirection
- Different responsibility boundary from gaetanlepage (which uses hosts/ for nixos, but has no darwin)

**If complexity grows later:**
Split into `homebrew.nix`, `users.nix`, `services.nix` as separate files in same directory.

### Module Composition Guidelines

#### For nixos hosts:

1. **Base modules** (apply to all nixos):
   - `config.flake.modules.nixos.base` (nix settings, state version, shared packages)

2. **Hardware modules** (per-machine type):
   - `config.flake.modules.nixos.hardware.hetzner` (cinnabar)
   - `config.flake.modules.nixos.hardware.gcp` (gcp-vm, electrum)

3. **Service/feature modules** (optional per-machine):
   - `config.flake.modules.nixos.services.zerotier` (if clan inventory insufficient)
   - Embedded in host `default.nix` via `imports = [...]`

4. **Host-specific** (in machine `default.nix`):
   - Registers to `flake.modules.nixos."machines/nixos/<hostname>"`
   - Declares hostname, platform
   - Imports base + hardware + optional features

#### For darwin hosts:

1. **Base modules** (apply to all darwin):
   - `config.flake.modules.darwin.base` (nix settings, state version, shared packages)

2. **No hardware modules** (hardware is implicit in darwin host):
   - macOS version is implicit (managed by system)
   - Architecture specified in host via `nixpkgs.hostPlatform`

3. **Host-specific** (in machine `default.nix`):
   - Registers to `flake.modules.darwin."machines/darwin/<hostname>"`
   - Declares hostname, architecture, primaryUser
   - Imports base
   - Defines users, homebrew, home-manager inline

### Namespace Organization

**Principle:** Namespaces reflect functional responsibility, not filesystem location.

```
flake.modules.nixos.
  ├── base                                   # Shared nix settings, packages, users
  ├── hardware.hetzner                       # Hetzner-specific hardware
  ├── hardware.gcp                           # GCP-specific hardware
  ├── machines.nixos.cinnabar                # Host-specific (cinnabar)
  ├── machines.nixos.electrum                # Host-specific (electrum)
  └── machines.nixos.gcp-vm                  # Host-specific (gcp-vm)

flake.modules.darwin.
  ├── base                                   # Shared nix settings, packages
  ├── machines.darwin.blackphos              # Host-specific (blackphos)
  └── machines.darwin.test-darwin            # Host-specific (test-darwin)

flake.modules.homeManager.
  ├── users.crs58                            # Portable home config
  └── users.raquel                           # Portable home config
```

**Key insight:** `machines.nixos.<hostname>` and `machines.darwin.<hostname>` namespaces are distinct. This allows:
- Clear system-type separation
- Easy identification of host-specific vs shared modules
- No collision between nixos and darwin configs

---

## E. Open Questions / Gaps

### 1. Hardware Module Organization for nixos

**Question:** Should hardware be separate files (gaetanlepage style) or embedded?

**Current test-clan approach:** Embedded in host default.nix (cinnabar has 115 lines including disko).

**Recommendation:** Keep embedded until complexity justifies split:
- `cinnabar/default.nix` - 115 lines (OK)
- If grows >150 lines, split to `cinnabar/hardware.nix`, `cinnabar/disko.nix`

### 2. Clan inventory.instances vs dendritic modules

**Question:** When should a feature be in `clan.inventory.instances` vs `flake.modules.nixos/darwin`?

**Answer (from investigation):**
- **Inventory instances**: Features that span multiple machines (zerotier peer/controller, borgbackup client/server roles)
- **Dendritic modules**: Features local to a machine type or host (hardware, bootloader, GUI, nix settings)

**Current pattern:** Don't duplicate. If clan provides inventory instance (zerotier), import it in clan.machines, not as dendritic module.

### 3. Home-manager placement decision

**Question:** Embed home configs in darwin default.nix vs standalone homeConfigurations?

**Current test-clan approach:** Embedded for darwin (cleaner, reduces indirection).

**Rationale:** 
- Darwin: Users are strongly bound to host (crs58 on blackphos = ~ on that machine)
- NixOS: Users could theoretically move between machines (but clan.machines binds them to machines anyway)

**Recommendation:** Keep embedded for darwin. If nixos adopts standalone, it's orthogonal.

### 4. System state version management

**Question:** How to coordinate stateVersion across nixos and darwin?

**Current test-clan approach:**
- nixos base: `system.stateVersion = lib.mkDefault "24.11"`
- darwin base: `system.stateVersion = 5`
- Hosts can override with `lib.mkForce`

**Recommendation:** Document per-machine state version policy. Consider separate docs/state-versions.md if managing many machines.

### 5. Clan.nix machines instantiation

**Question:** Should `clan.machines` be auto-generated from `flake.modules` or manually defined?

**Current test-clan approach:** Manually defined in `modules/clan/machines.nix`:
```nix
clan.machines = {
  cinnabar = { imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ]; };
  blackphos = { imports = [ config.flake.modules.darwin."machines/darwin/blackphos" ]; };
};
```

**Pros:** Explicit, flexible (can add clan-only config)
**Cons:** Duplication if flake.modules already defines hosts

**Recommendation:** Keep explicit. Allows clan config injection layer (example: inventory instance defaults per machine).

---

## F. Architecture Decision Summary for Story 1.10

### Goals for test-clan (dendritic + clan integration):

1. **Separation of concerns:**
   - Dendritic modules define capabilities (hardware, services, users)
   - Clan machines compose them + add clan-specific inventory
   - Home-manager handles user environments

2. **Modularity:**
   - System modules (base, hardware, services) are reusable
   - Host-specific configs minimal and focused
   - Clear namespace hierarchy

3. **Clarity for multi-system fleet:**
   - `machines/nixos/` for Linux systems
   - `machines/darwin/` for macOS systems
   - Obvious at a glance which machines are which type

4. **Pragmatism:**
   - Don't over-engineer (single file per host until complexity justifies)
   - Follow gaetanlepage pattern for nixos (proven, well-structured)
   - Adapt darwin pattern from test-clan/mic92 (pragmatic, embedded)

### Validation Approach:

- blackphos migration (Story 1.10) uses recommended patterns
- Verify nixosConfigurations generation still works with clan.machines binding
- Test home-manager embedded in darwin config
- Document patterns in architecture.md update

---

## References

### Investigation Sources

1. **Primary:** `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config`
   - `modules/flake/hosts.nix` - nixosConfigurations/homeConfigurations generation
   - `modules/hosts/` - Host organization
   - `modules/nixos/core`, `modules/nixos/desktop` - System modules

2. **Secondary (darwin):** `~/projects/nix-workspace/test-clan`
   - `modules/machines/darwin/blackphos/default.nix` - Darwin host pattern
   - `modules/darwin/base.nix` - Darwin base modules
   - `modules/clan/machines.nix` - Clan instantiation

3. **Clan reference:** `~/projects/nix-workspace/qubasa-clan-infra`
   - `flake.nix` - Clan library integration
   - `clan.nix` - Inventory instances pattern
   - `machines/` - Simple clan machine structure

4. **Darwin detail:** `~/projects/nix-workspace/mic92-clan-dotfiles`
   - `darwinModules/` - Reusable darwin system modules
