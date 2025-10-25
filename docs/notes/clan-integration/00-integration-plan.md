# Clan integration plan for dendritic flake-parts + clan-core migration

## Executive summary

This document provides a comprehensive migration plan for transitioning nix-config from nixos-unified to the dendritic flake-parts pattern with clan-core integration.
The migration follows a validation-first approach with VPS infrastructure: validate dendritic + clan integration in test-clan/ (Phase 0), deploy a Hetzner Cloud VPS (cinnabar) as the foundation with zerotier controller and core services (Phase 1), then migrate darwin hosts progressively (blackphos → rosegold → argentum → stibnite).
Phase 0 de-risks the migration by proving the architectural combination works in a minimal test environment before infrastructure commitment.
The approach validates dendritic + clan on NixOS first, provides always-on infrastructure, and de-risks darwin migration while eliminating nixos-unified and adopting clan-core's inventory system, vars management, and multi-machine service coordination using the dendritic pattern's `flake.modules.*` namespace.

## Strategic rationale: why dendritic pattern with clan?

### Type safety through module system maximization

**Foundation: Nix lacks native type system**
- Nix language provides no compile-time type checking
- Errors often appear only at evaluation or runtime
- Large configurations become difficult to maintain safely

**Solution: Nix module system provides type safety**
- Options with explicit types (bool, int, str, listOf, attrsOf, etc.)
- Type checking at evaluation time
- Clear interfaces between modules
- Validation of configuration values

**flake-parts extends module system to flakes**
- Brings module system benefits to flake organization
- Type-safe flake outputs
- Composable flake configuration
- Both clan-core and clan-infra use flake-parts

**Dendritic pattern maximizes module system usage**
- Every file is a flake-parts module
- Maximum type safety through consistent module usage
- Clear interfaces via config.flake.* namespace
- Eliminates untyped specialArgs pass-through

**Result: incremental type safety improvement**
- Foundation: clan + flake-parts (proven, documented)
- Optimization: dendritic organization (experimental)
- Goal: maximum type safety while preserving clan functionality

### Priority hierarchy

When conflicts arise between dendritic purity and clan functionality:

**1. Primary: clan functionality** (non-negotiable)
- Multi-machine coordination
- Inventory system
- Vars/secrets management
- Service instances and roles
- All clan features must work correctly

**2. Secondary: dendritic pattern** (best-effort)
- Apply where feasible without compromising clan
- Deviate when necessary for clan compatibility
- Document compromises and rationale

**3. Tertiary: pattern purity** (flexible)
- Some specialArgs usage acceptable if clan requires it
- Mixed organization acceptable if necessary
- Pragmatism over orthodoxy

**Principle**: preserve clan functionality, optimize with dendritic where possible.

### What Phase 0 validates

**Not**: "can we combine two untested patterns?"
**Yes**: "how much dendritic can we apply to proven clan+flake-parts?"

**Known foundation**:
- Clan works with flake-parts (clan-core, clan-infra use it)
- Dendritic pattern works (multiple production examples)

**Unknown optimization**:
- How much dendritic organization is compatible with clan?
- Where do dendritic patterns need to be relaxed?
- What compromises are necessary and acceptable?

**Phase 0 answers**: "what's the optimal dendritic/clan balance?"

## Repository analysis

### Current nix-config architecture (pre-migration)

**Foundation**: nixos-unified with flake-parts
**Structure**:
- `flake.nix`: Uses `flake-parts.lib.mkFlake` with auto-wired imports from `./modules/flake-parts/`
- `configurations/{darwin,home,nixos}/`: Host-specific configurations via nixos-unified autowire
- `modules/{darwin,home,nixos}/`: Modular system and home-manager configurations
- `secrets/`: SOPS-based secrets management (both agenix and sops-nix available)
- `overlays/`, `packages/`: Custom package definitions
- `docs/notes/`: Documentation organized by topic

**Current hosts**:
- `stibnite` (darwin, aarch64): Primary daily workstation (migrate LAST)
- `blackphos` (darwin, aarch64): Already activated, test migration (Phase 2)
- `rosegold` (darwin, aarch64): Not currently in daily use (Phase 3)
- `argentum` (darwin, aarch64): Not currently in daily use (Phase 4)
- `stibnite-nixos`, `blackphos-nixos` (nixos): CI validation mirrors
- `orb-nixos` (nixos): OrbStack/LXD test configurations

**New infrastructure (Phase 1)**:
- `cinnabar` (nixos, x86_64): Hetzner Cloud CX53 VPS, zerotier controller, always-on core services

**Migration order rationale**:
1. **cinnabar** (VPS): Deploy first as foundation infrastructure, validates dendritic + clan on NixOS, provides always-on zerotier controller
2. **blackphos**: Connect to cinnabar's zerotier network, validates darwin + clan integration
3. **rosegold**: Validates darwin patterns are reusable, multi-machine coordination
4. **argentum**: Final validation before primary workstation
5. **stibnite**: Primary workstation, migrate only after all others proven stable

**Module organization (will change)**:
- Current: Directory-based autowire (`modules/{darwin,home,nixos}/`)
- Target: Dendritic pattern with `flake.modules.{nixos,homeManager,darwin}.*` namespace
- nixos-unified's specialArgs will be eliminated in favor of `config.flake.*` access
- import-tree will replace manual directory scanning

### Clan architecture overview

**Foundation**: Library-centric design with NixOS modules, Python CLI, and multiple frontends
**Key components**:

1. **Flake integration**: `clan-core.flakeModules.default` provides flake-parts integration
2. **Inventory system**: Abstract service layer for multi-machine coordination
3. **Vars system**: Declarative secret and file generation
4. **Clan services**: New module class (`_class = "clan.service"`) with roles and instances
5. **CLI tools**: `clan` command for machine management, deployment, and var generation

**Core concepts**:

**Inventory**:
- `inventory.machines`: Define all machines with tags and machineClass
- `inventory.instances`: Service instances with roles
- Roles define machine membership and service-specific configuration
- Tags enable bulk machine assignment to roles
- Configuration hierarchy: instance-wide → role-wide → machine-specific

**Vars system**:
- Replaces manual secret management with declarative generators
- `clan.core.vars.generators.<name>`: Define generation logic
- Prompts for user input, dependencies for DAG composition
- Storage backends: SOPS (default), password-store
- Files marked `secret = true` use `.path` (deployed to `/run/secrets/`)
- Files marked `secret = false` use `.value` (accessible in nix store)
- `share = true` for cross-machine secrets
- Automatic generation during deployment or manual via `clan vars generate`

**Clan services**:
- Instance-based: Multiple instances of the same service type
- Role-based: Different roles (client, server, peer, etc.) per instance
- `roles.<name>.interface`: Define configuration options
- `roles.<name>.perInstance`: Map over instances, produce nixosModule
- `perMachine`: Map over machines, produce nixosModule
- Examples: borgbackup, sshd, zerotier, matrix-synapse

### Clan-infra patterns (production reference)

**Flake structure**:
```nix
{
  imports = [
    inputs.clan-core.flakeModules.default
    ./machines/flake-module.nix
    # ... other modules
  ];

  clan = {
    meta.name = "infra";
    specialArgs = { inherit self; };
    inherit self;
    inventory.instances = {
      # Service instances defined here
    };
    secrets.age.plugins = [ "age-plugin-1p" "age-plugin-se" ];
  };
}
```

**Directory organization**:
- `machines/`: Per-machine `configuration.nix` files
- `machines/flake-module.nix`: Inventory and service definitions
- `modules/`: Shared NixOS modules
- `sops/{groups,machines,secrets,users}/`: Clan-managed SOPS structure
- `terraform/`: Cloud provisioning integration

**Instance examples from clan-infra**:
```nix
inventory.instances = {
  emergency-access = {
    module = { name = "emergency-access"; input = "clan-core"; };
    roles.default.tags."all" = {};
  };
  zerotier-claninfra = {
    module = { name = "zerotier"; input = "clan-core"; };
    roles.controller.machines.web01 = {};
    roles.moon.machines.jitsi01.settings = { /* ... */ };
    roles.peer.tags.all = {};
  };
  sshd-clan = {
    module = { name = "sshd"; input = "clan-core"; };
    roles.server.tags.all = {};
    roles.server.settings = {
      certificate.searchDomains = [ "clan.lol" ];
    };
    roles.client.tags.all = {};
  };
};
```

**Admin user workflow** (from clan-infra README):
1. User generates age key: `clan secrets key generate`
2. User provides SSH public key and age public key to admin
3. Admin adds: `clan secrets users add <username> <age-key>`
4. Admin grants access: `clan secrets groups add-user admins <username>`
5. Admin updates `modules/admins.nix` configuration

**Deployment workflow**:
- `clan vars generate <machine>`: Generate vars for a machine
- `clan machines update <machine>`: Deploy configuration
- `clan machines install <machine>`: Initial installation

### Dendritic flake-parts pattern

**Foundation**: Canonical organizational pattern where every Nix file is a flake-parts module
**Key principle**: Eliminate specialArgs pass-through, centralize all values through flake-parts module system

**Core concepts**:

**Module namespace**:
```nix
# Every module contributes to flake.modules namespace
{
  flake.modules = {
    nixos.base = { pkgs, ... }: { /* nixos config */ };
    homeManager.shell = { pkgs, ... }: { /* home-manager config */ };
    darwin.system = { pkgs, ... }: { /* darwin config */ };
  };
}
```

**Directory organization**:
```
modules/
├── base/                    # Foundation modules
│   ├── nix.nix
│   └── system/
├── shell/                   # Shell tools
│   ├── fish.nix
│   └── starship.nix
├── dev/                     # Development tools
│   └── git/
├── hosts/                   # Machine-specific configurations
│   ├── blackphos/default.nix
│   ├── rosegold/default.nix
│   ├── argentum/default.nix
│   └── stibnite/default.nix
├── flake-parts/            # Meta-level flake configuration
│   ├── nixpkgs.nix
│   ├── host-machines.nix
│   └── clan.nix
└── users/                   # User configurations
    └── crs58/default.nix
```

**Auto-discovery with import-tree**:
```nix
# flake.nix
{
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
    (inputs.import-tree ./modules);
}
```

**Host composition pattern**:
```nix
# modules/hosts/blackphos/default.nix
{
  config, ...
}:
{
  flake.modules.darwin."hosts/blackphos" = { ... }: {
    imports = with config.flake.modules; [
      # Reference modules by namespace
      darwin.base
      darwin.system
      homeManager.shell
      homeManager.dev
    ];

    # Host-specific configuration
    networking.hostName = "blackphos";
    # ...
  };
}
```

**Metadata sharing**:
```nix
# modules/users/crs58/default.nix
{
  config, ...
}:
{
  flake.meta.users.crs58 = {
    email = "user@example.com";
    name = "User Name";
    # ...
  };

  # Used across modules via config.flake.meta.users.crs58
}
```

**Advantages**:
- No specialArgs needed (everything via `config.flake.*`)
- File path = feature name (clear organization)
- Composable features (mix darwin + nixos + home-manager)
- Cross-cutting concerns (modules can target multiple systems)
- Automatic discovery (import-tree)
- Clear option definition (declare once, use everywhere)

**Reference implementation**: `~/projects/nix-workspace/dendritic-flake-parts/`

## Integration strategy

### Architecture alignment

**Dendritic + Clan synergy**:
- Both use flake-parts as foundational architecture
- Dendritic's `flake.modules.*` namespace pairs naturally with Clan's inventory system
- Both eliminate specialArgs in favor of explicit module composition
- Clan's vars system complements dendritic's metadata sharing (`flake.meta.*`)
- Both support SOPS for secrets (clan uses sops-nix)
- Both emphasize modular, type-safe configurations
- import-tree auto-discovery works seamlessly with clan modules

**Architectural incompatibility with nixos-unified**:
- nixos-unified uses specialArgs + directory-based autowire
- Dendritic eliminates specialArgs in favor of `config.flake.*`
- These approaches are mutually exclusive (cannot coexist cleanly)
- clan-infra production infrastructure uses clan + flake-parts with manual imports, not nixos-unified
- Decision: **Abandon nixos-unified** in favor of dendritic + clan

**Migration approach**:
1. Add clan-core and import-tree as flake inputs
2. Create `modules/` directory with dendritic structure
3. Convert modules incrementally to `flake.modules.*` namespace
4. Migrate hosts one at a time: blackphos → rosegold → argentum → stibnite
5. Remove nixos-unified after all hosts migrated
6. Validate at each step before proceeding

**Risk mitigation**:
- Migrate non-primary machines first (blackphos, rosegold, argentum)
- Keep stibnite on nixos-unified until others proven stable
- Each host migration can be rolled back independently
- Dendritic pattern proven in production (drupol-dendritic-infra, clan-infra)
- Multi-machine testing possible with multiple test hosts

### Directory structure (target state)

```
nix-config/
├── flake.nix                      # Simplified: import-tree ./modules
├── modules/                        # CHANGED: Dendritic pattern (flat categories)
│   ├── base/                      # Foundation modules
│   │   ├── nix.nix                # Core nix settings
│   │   └── system.nix             # State versions
│   ├── nixos/                     # NixOS-specific modules
│   │   └── server.nix             # Server configuration
│   ├── darwin/                    # Darwin-specific modules
│   │   ├── homebrew.nix
│   │   └── system-preferences.nix
│   ├── shell/                     # Shell tools
│   │   ├── fish.nix
│   │   ├── starship.nix
│   │   └── direnv.nix
│   ├── dev/                       # Development tools
│   │   └── git/
│   │       ├── git.nix
│   │       └── jj.nix
│   ├── hosts/                     # Machine-specific configurations
│   │   ├── cinnabar/              # Phase 1: VPS infrastructure
│   │   │   ├── default.nix
│   │   │   ├── disko.nix
│   │   │   └── terraform-configuration.nix
│   │   ├── blackphos/default.nix  # Phase 2: First darwin
│   │   ├── rosegold/default.nix   # Phase 3: Second darwin
│   │   ├── argentum/default.nix   # Phase 4: Third darwin
│   │   └── stibnite/default.nix   # Phase 5: Primary workstation
│   ├── flake-parts/               # Flake-level configuration
│   │   ├── nixpkgs.nix            # Nixpkgs setup and overlays
│   │   ├── darwin-machines.nix    # Generate darwinConfigurations
│   │   ├── nixos-machines.nix     # Generate nixosConfigurations
│   │   ├── terranix.nix           # Terraform/terranix configuration
│   │   └── clan.nix               # Clan inventory and instances
│   ├── terranix/                  # Terraform modules
│   │   ├── base.nix               # Base terraform config
│   │   └── ssh-keys.nix           # SSH key generation
│   └── users/                     # User configurations
│       └── crs58/default.nix      # User metadata and config
├── secrets/                        # CHANGED: Clan vars only (migrate from sops)
│   ├── groups/
│   │   └── admins/                # Admin group age keys
│   ├── machines/
│   │   ├── cinnabar/              # VPS secrets
│   │   ├── blackphos/
│   │   ├── rosegold/
│   │   ├── argentum/
│   │   └── stibnite/
│   ├── secrets/                   # Encrypted secrets
│   └── users/
│       └── crs58/                 # User age keys
├── terraform/                      # NEW: Terraform working directory (git-ignored)
│   └── .gitkeep
├── overlays/                      # Existing overlays preserved
├── packages/                      # Existing packages preserved
└── docs/notes/
    └── clan-integration/          # This directory
        ├── 00-integration-plan.md # This document
        ├── 01-phase-1-vps-deployment.md    # Phase 1: VPS infrastructure
        ├── 02-phase-2-blackphos-guide.md   # Phase 2: First darwin host
        └── 03-migration-assessment.md      # Host-specific considerations
```

**Migration path**:
```
Phase 1: VPS Infrastructure (cinnabar)
- Add clan-core, import-tree, terranix, disko, srvos inputs
- Create modules/ structure alongside existing files
- Setup terraform/terranix for Hetzner Cloud
- Deploy cinnabar VPS with zerotier controller
- Validate dendritic + clan on NixOS first

Phase 2: First darwin host (blackphos)
- Convert darwin modules to dendritic pattern
- Create modules/hosts/blackphos/default.nix
- Connect to cinnabar's zerotier network as peer
- Validate darwin + clan integration

Phase 3: Second darwin host (rosegold)
- Create modules/hosts/rosegold/default.nix
- Test multi-darwin coordination
- Validate patterns are reusable

Phase 4: Third darwin host (argentum)
- Create modules/hosts/argentum/default.nix
- Final validation before primary workstation

Phase 5: Primary workstation (stibnite)
- Migrate only after all others proven stable
- Create modules/hosts/stibnite/default.nix
- Complete 5-machine network

Phase 6: Cleanup
- Remove configurations/ directory
- Remove nixos-unified flake input and module
- Migrate all secrets to clan vars
```

**Rationale**:
- Dendritic pattern: flat feature categories, clear module namespace
- import-tree: automatic discovery eliminates manual imports
- clan inventory: centralized multi-machine coordination
- Progressive migration: each host independently testable
- Rollback safety: old structure remains until all hosts migrated

### Flake modifications

**Input additions**:
```nix
{
  inputs = {
    # Remove nixos-unified (after all hosts migrated)
    # nixos-unified.url = "github:srid/nixos-unified";

    # Add clan-core and import-tree
    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.sops-nix.follows = "sops-nix";
    clan-core.inputs.home-manager.follows = "home-manager";
    clan-core.inputs.nix-darwin.follows = "nix-darwin";

    import-tree.url = "github:vic/import-tree";

    # Add terraform/terranix for VPS provisioning
    terranix.url = "github:terranix/terranix";
    terranix.inputs.flake-parts.follows = "flake-parts";
    terranix.inputs.nixpkgs.follows = "nixpkgs";

    # Add disko for declarative partitioning
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Add srvos for server hardening
    srvos.url = "github:nix-community/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

**Flake structure** (simplified with import-tree):
```nix
{
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { ... }: {
        imports = [
          inputs.terranix.flakeModule
          # Import all .nix files from modules/ recursively
          (inputs.import-tree ./modules)
        ];
      }
    );
  # import-tree recursively imports all .nix files in modules/
  # Each file is a flake-parts module contributing to flake.modules.*
  # terranix.flakeModule provides perSystem.terranix configuration
}
```

**Remove nixos-unified module** from `modules/flake-parts/nixos-flake.nix`:
```nix
# DELETE THIS FILE or remove nixos-unified imports:
# - inputs.nixos-unified.flakeModules.default
# - inputs.nixos-unified.flakeModules.autoWire
```

**New file** `modules/flake-parts/clan.nix`:
```nix
{ inputs, ... }:
{
  imports = [
    inputs.clan-core.flakeModules.default
  ];

  clan = {
    meta.name = "nix-config";
    specialArgs = { inherit inputs; };

    inventory.machines = {
      cinnabar = {
        tags = [ "nixos" "vps" "cloud" ];
        machineClass = "nixos";
      };
      blackphos = {
        tags = [ "darwin" "workstation" ];
        machineClass = "darwin";
      };
      rosegold = {
        tags = [ "darwin" "workstation" ];
        machineClass = "darwin";
      };
      argentum = {
        tags = [ "darwin" "workstation" ];
        machineClass = "darwin";
      };
      stibnite = {
        tags = [ "darwin" "workstation" "primary" ];
        machineClass = "darwin";
      };
    };

    inventory.instances = {
      # Essential services
      emergency-access = {
        module = { name = "emergency-access"; input = "clan-core"; };
        roles.default.tags."workstation" = {};
      };

      users-crs58 = {
        module = { name = "users"; input = "clan-core"; };
        roles.default.tags."workstation" = {};
        roles.default.settings = {
          user = "crs58";
          share = true;
        };
      };

      users-root = {
        module = { name = "users"; input = "clan-core"; };
        roles.default.machines.cinnabar = {};
        roles.default.settings = {
          user = "root";
          prompt = false;
          groups = [ ];
        };
      };

      zerotier-local = {
        module = { name = "zerotier"; input = "clan-core"; };
        # cinnabar is controller (always-on VPS)
        roles.controller.machines.cinnabar = {};
        # All machines are peers
        roles.peer.tags."all" = {};
      };

      sshd-clan = {
        module = { name = "sshd"; input = "clan-core"; };
        roles.server.tags."all" = {};
        roles.client.tags."all" = {};
      };
    };

    secrets.sops.defaultGroups = [ "admins" ];
  };
}
```

**New file** `modules/flake-parts/host-machines.nix`:
```nix
{
  inputs,
  lib,
  config,
  ...
}:
let
  prefix = "hosts/";
  collectHostsModules = modules:
    lib.filterAttrs (name: _: lib.hasPrefix prefix name) modules;
in
{
  flake.darwinConfigurations = lib.pipe
    (collectHostsModules config.flake.modules.darwin) [
      (lib.mapAttrs' (
        name: module:
        let
          hostName = lib.removePrefix prefix name;
        in
        {
          name = hostName;
          value = inputs.nix-darwin.lib.darwinSystem {
            specialArgs = { inherit inputs; };
            modules = [
              inputs.home-manager.darwinModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
              }
              module
            ];
          };
        }
      ))
    ];
}
```

### Module integration patterns (dendritic)

**Pattern 1: Base modules (cross-platform)**
```nix
# modules/base/nix.nix
{
  flake.modules = {
    nixos.base = { pkgs, ... }: {
      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        trusted-users = [ "root" "@wheel" ];
      };
    };

    darwin.base = { pkgs, ... }: {
      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        trusted-users = [ "root" "@admin" ];
      };
    };
  };
}
```

**Pattern 2: Cross-cutting modules (system + home)**
```nix
# modules/shell/fish.nix
{
  flake.modules = {
    darwin.shell = {
      programs.fish.enable = true;
    };

    homeManager.shell = { pkgs, ... }: {
      programs.fish = {
        enable = true;
        shellAliases = {
          ls = "eza";
          cat = "bat";
        };
      };
    };
  };
}
```

**Pattern 3: Host-specific composition**
```nix
# modules/hosts/blackphos/default.nix
{
  config, ...
}:
{
  flake.modules.darwin."hosts/blackphos" = { ... }: {
    imports = with config.flake.modules; [
      darwin.base
      darwin.system
      darwin.homebrew
    ];

    # Host-specific config
    networking.hostName = "blackphos";
    system.stateVersion = 5;

    # Home-manager for user
    home-manager.users.crs58 = {
      imports = with config.flake.modules.homeManager; [
        shell
        dev
      ];
      home.stateVersion = "25.05";
    };
  };
}
```

**Pattern 4: Metadata sharing**
```nix
# modules/users/crs58/default.nix
{
  config, ...
}:
{
  # Define metadata
  flake.meta.users.crs58 = {
    email = "user@example.com";
    name = "User Name";
    sshKeys = [ "ssh-ed25519 AAAAC3..." ];
  };

  # Use in darwin module
  flake.modules.darwin.users = { ... }: {
    users.users.crs58 = {
      description = config.flake.meta.users.crs58.name;
      openssh.authorizedKeys.keys = config.flake.meta.users.crs58.sshKeys;
    };
  };

  # Use in home-manager module
  flake.modules.homeManager.users = { ... }: {
    programs.git = {
      userName = config.flake.meta.users.crs58.name;
      userEmail = config.flake.meta.users.crs58.email;
    };
  };
}
```

**Pattern 5: Conditional features by tag**
```nix
# modules/dev/tools.nix
{
  config, lib, ...
}:
{
  flake.modules.homeManager.dev = { pkgs, ... }: {
    home.packages = with pkgs; [
      ripgrep
      fd
      jq
    ] ++ lib.optionals (builtins.elem "primary" config.clan.inventory.machines.${config.networking.hostName}.tags) [
      # Extra tools only on primary workstation
      kubectl
      terraform
    ];
  };
}
```

### Secrets management (clan vars)

**Migration strategy**:
- Replace sops-nix/agenix with clan vars system
- Migrate secrets during host conversion (Phase 0-4)
- Clan vars provides declarative generation and deployment
- Single encrypted secrets store in git

**Clan vars directory structure**:
```
secrets/
├── groups/
│   └── admins/              # Admin group age keys
├── machines/
│   ├── blackphos/           # Per-machine age keys and secrets
│   ├── rosegold/
│   ├── argentum/
│   └── stibnite/
├── secrets/                 # Shared encrypted secrets
└── users/
    └── crs58/               # User age keys
```

**Initialization**:
```bash
# Generate age key for yourself
nix run nixpkgs#clan-cli -- secrets key generate

# Create admin group
nix run nixpkgs#clan-cli -- secrets groups add admins

# Add yourself as admin
YOUR_AGE_KEY=$(grep 'public key:' ~/.config/sops/age/keys.txt | awk '{print $4}')
nix run nixpkgs#clan-cli -- secrets users add crs58 "$YOUR_AGE_KEY"
nix run nixpkgs#clan-cli -- secrets groups add-user admins crs58
```

**Secret migration example**:
```nix
# Old: manual sops secret
sops.secrets.example = {
  sopsFile = ./secrets/hosts/blackphos.yaml;
  # Manual management
};

# New: clan vars generator
clan.core.vars.generators.example = {
  prompts.value.description = "Example secret";
  script = ''
    echo -n "$(cat $prompts/value)" > $out/secret
  '';
  files.secret = { secret = true; };
};

# Use: config.clan.core.vars.generators.example.files.secret.path
```

## Phase 0 validation rationale

**Critical discovery**: No production examples exist combining dendritic + clan patterns.

Reference repository analysis reveals:
- `~/projects/nix-workspace/clan-infra/`: Uses clan WITHOUT dendritic (manual imports)
- `~/projects/nix-workspace/drupol-dendritic-infra/`: Uses dendritic WITHOUT clan (pure import-tree)
- `~/projects/nix-workspace/jfly-clan-snow/`: Uses clan WITHOUT dendritic (darwin)
- `~/projects/nix-workspace/mic92-clan-dotfiles/`: Uses clan WITHOUT dendritic

**Risk without Phase 0**: Deploying untested architectural combination directly to production VPS creates compound debugging complexity across 8 simultaneous layers (dendritic, clan, terraform, hetzner, disko, LUKS, zerotier, NixOS).

**Solution: Phase 0 validation in test-clan/**
- Validate dendritic + clan integration in minimal environment
- Test all critical integration points before infrastructure commitment
- Document findings and extract patterns
- Prove architectural combination works
- Reduce risk before VPS deployment

**Expected outcome**: Proven patterns ready for cinnabar deployment with confidence.

## Migration phases

### Phase 0: Validation (test-clan/)

**Objective**: determine optimal balance of dendritic pattern with clan functionality

**Foundation**: clan + flake-parts (proven in clan-core, clan-infra)
**Experiment**: how much dendritic optimization is compatible?

**Tasks**:
- Create minimal test-clan/ environment
- Implement clan with flake-parts (known working)
- Apply dendritic patterns where feasible
- Document where compromises are necessary
- Evaluate type safety benefits vs complexity costs

**Outcomes** (all valid):
- Dendritic-optimized clan (best case)
- Hybrid approach (pragmatic)
- Vanilla clan pattern (proven alternative)

**Success criteria**:
- [ ] Clan functionality validated
- [ ] Dendritic feasibility assessed
- [ ] Pattern decision made for Phase 1
- [ ] Trade-offs documented

**Not a pass/fail on full dendritic adoption.**
**Is a characterization of what's feasible and beneficial.**

**Timeline**: 1 week for implementation + validation

**Detailed guide**: `01-phase-0-validation.md`

### Phase 1: VPS infrastructure (cinnabar)

**Objective**: Deploy always-on infrastructure and validate dendritic + clan on NixOS

**Strategic value**: VPS-first approach validates the integration on clan's native platform (NixOS) before attempting darwin migration, provides stable foundation for darwin hosts

**Tasks**:
- Add clan-core, import-tree, terranix, disko, srvos flake inputs
- Create `modules/` directory with dendritic structure
- Initialize clan secrets (age keys, API tokens)
- Setup terraform/terranix for Hetzner Cloud provisioning
- Create `modules/hosts/cinnabar/` with disko configuration
- Configure zerotier controller role on cinnabar
- Deploy VPS via terraform + clan machines install
- Keep existing `configurations/` active (darwin hosts unaffected)

**Success criteria**:
- [ ] Flake evaluates with all new inputs
- [ ] Terranix configuration generates valid terraform
- [ ] Hetzner Cloud VPS provisioned successfully
- [ ] NixOS installed on cinnabar with LUKS encryption
- [ ] Zerotier controller operational on cinnabar
- [ ] SSH daemon with CA certificates
- [ ] Emergency access functional
- [ ] Clan vars deployed correctly
- [ ] Existing darwin configs still build

**Timeline**: 1-2 weeks for deployment + 1-2 weeks monitoring stability

**Detailed guide**: `02-phase-1-vps-deployment.md`

### Phase 2: First darwin host (blackphos)

**Objective**: Migrate first darwin machine, validate darwin + clan integration

**Tasks**:
- Convert darwin modules to dendritic pattern in `modules/{base,darwin,shell,dev}/`
- Create `modules/hosts/blackphos/default.nix`
- Configure blackphos as zerotier peer (connects to cinnabar controller)
- Add to clan inventory
- Generate vars for blackphos
- Deploy with darwin-rebuild switch

**Success criteria**:
- [ ] blackphos builds with dendritic + clan
- [ ] All functionality preserved (no regressions)
- [ ] Zerotier peer connects to cinnabar controller
- [ ] cinnabar ↔ blackphos network communication functional
- [ ] SSH via zerotier network works (certificate-based)
- [ ] Secrets deployed via clan vars
- [ ] Stable for 1-2 weeks

**Detailed guide**: `03-phase-2-blackphos-guide.md`

### Phase 3: Second darwin host (rosegold)

**Objective**: Validate darwin patterns are reusable

**Tasks**:
- Create `modules/hosts/rosegold/default.nix` (reuse blackphos patterns)
- Add to clan inventory with zerotier peer role
- Generate vars and deploy
- Test multi-darwin coordination

**Success criteria**:
- [ ] rosegold operational with minimal pattern customization
- [ ] 3-machine network operational (cinnabar ↔ blackphos ↔ rosegold)
- [ ] Patterns validated for reuse
- [ ] Stable for 1-2 weeks

### Phase 4: Third darwin host (argentum)

**Objective**: Final validation before primary workstation

**Tasks**:
- Create `modules/hosts/argentum/default.nix`
- Add to clan inventory
- Deploy and test
- Validate 4-machine zerotier network

**Success criteria**:
- [ ] argentum operational
- [ ] 4-machine coordination working
- [ ] No new issues discovered
- [ ] Ready for primary workstation migration
- [ ] Stable for 1-2 weeks

### Phase 5: Primary workstation (stibnite)

**Objective**: Migrate primary workstation

**Tasks**:
- Create `modules/hosts/stibnite/default.nix`
- Extra validation and testing
- Deploy only after phases 1-4 stable (4-6 weeks minimum)
- Keep fallback path available

**Success criteria**:
- [ ] stibnite operational
- [ ] All daily workflows functional
- [ ] 5-machine zerotier network complete
- [ ] Productivity maintained or improved
- [ ] Stable for 1-2 weeks

### Phase 6: Cleanup

**Objective**: Remove legacy infrastructure

**Tasks**:
- Delete `configurations/` directory
- Remove nixos-unified flake input
- Remove old secrets structure
- Update documentation

**Success criteria**:
- [ ] Clean dendritic + clan architecture
- [ ] No nixos-unified remnants
- [ ] Documentation updated

## Key decisions and tradeoffs

### Decision 1: Dendritic pattern vs. nixos-unified

**Chosen**: Abandon nixos-unified, adopt dendritic pattern
**Rationale**:
- Dendritic + clan architectural alignment (both eliminate specialArgs)
- clan-infra production infrastructure uses clan + flake-parts (with manual imports), demonstrating clan viability
- Cleaner `flake.modules.*` namespace vs directory autowire
- import-tree auto-discovery more flexible than directory scanning
- Proven dendritic scalability (drupol-dendritic-infra); proven clan scalability (clan-infra)

**Tradeoff**: Migration effort, but progressive per-host approach mitigates risk

### Decision 2: Migration order

**Chosen**: test-clan (validation) → cinnabar (VPS) → blackphos → rosegold → argentum → stibnite
**Rationale**:
- **Test-clan first**: Validates integration before infrastructure commitment
- **VPS first**: Validates dendritic + clan on NixOS (clan's native platform) before darwin
- **Always-on infrastructure**: Provides stable zerotier controller independent of darwin hosts
- **De-risks darwin migration**: Core services proven working before touching daily-use machines
- **Progressive validation**: Each host validates patterns before moving to next
- **Primary workstation last**: stibnite migrated only after all others proven stable

**Tradeoff**: Adds Hetzner Cloud cost (~€24/month) and 1 week validation time, but provides significant risk reduction and operational benefits

### Decision 3: Clan vars vs. sops-nix/agenix

**Chosen**: Fully migrate to clan vars
**Rationale**:
- Declarative generation cleaner than manual management
- Integrated with clan deployment workflow
- Proven in clan-infra production
- Single secret management approach

**Tradeoff**: Must migrate all secrets, but done incrementally per host

### Decision 4: Flat module organization vs. nested

**Chosen**: Flat feature categories (modules/{base,shell,dev,hosts}/)
**Rationale**:
- Dendritic pattern: file path = feature name
- Clear namespace (flake.modules.{nixos,darwin,homeManager}.*)
- Cross-cutting concerns enabled (one module, multiple targets)
- Matches reference implementations

**Tradeoff**: Different from nixos-unified's modules/{darwin,home,nixos}/ but cleaner separation

### Decision 5: specialArgs usage (minimal vs. extensive)

**Context**: Apparent tension between dendritic anti-pattern and clan usage

**Dendritic principle** (from dendritic-flake-parts/README.md:70-88):
- specialArgs pass-through is an anti-pattern
- Values should be shared via `config.flake.*` instead
- Every file can read/write to flake-parts config

**Clan usage** (from clan-infra/machines/flake-module.nix:10):
- Uses `specialArgs = { inherit self; }` (minimal passing)
- Necessary for clan's flakeModules integration
- Migration docs use `specialArgs = { inherit inputs; }`

**Chosen**: Minimal specialArgs acceptable, extensive pass-through avoided

**Distinction**:
- **Acceptable (minimal)**: `specialArgs = { inherit inputs; }` or `{ inherit self; }`
  - Passes only essential flake infrastructure
  - Minimal surface area (1-2 values)
  - Required for framework integration (clan, flake-parts)
  - Matches production patterns (clan-infra)

- **Anti-pattern (extensive)**: `specialArgs = { inherit pkgs lib config user host system; ... }`
  - Passes many values through specialArgs
  - Bypasses module system type checking
  - Creates implicit dependencies
  - Hard to track value sources
  - What dendritic warns against

**Rationale**:
- Clan requires minimal specialArgs for flakeModules integration
- This is not the anti-pattern dendritic warns against
- Anti-pattern is extensive pass-through of many values
- Minimal framework passing is acceptable pragmatism
- Dendritic's value comes from organizing application/user values via config.flake.*, not from eliminating all specialArgs

**Guideline**:
- Framework values (inputs, self): acceptable in specialArgs
- Application values (pkgs, lib, config, user-defined): use config.flake.* instead
- When in doubt: can this value be accessed via config.flake.*? If yes, use that.

**Tradeoff**: Slight deviation from pure dendritic orthodoxy, but maintains practical clan compatibility while preserving core dendritic benefits

## Open questions

1. **Module conversion strategy**: Convert all modules at once or incrementally?
   - **Chosen**: Incrementally per host to enable rollback
   - **Approach**: Create modules/ alongside configurations/, migrate per host

2. **Home-manager integration with dendritic**: How to structure home-manager modules?
   - **Pattern**: `flake.modules.homeManager.*` imported in host configs
   - **Validation**: Test with blackphos first

3. **Darwin-specific features**: Do all darwin features work with clan?
   - **Homebrew**: Should work as normal NixOS module
   - **System preferences**: Standard darwin module
   - **Validation**: Test thoroughly with blackphos

4. **Zerotier network topology**: Which machine is controller?
   - **Chosen**: cinnabar (VPS, always-on infrastructure)
   - **Rationale**: VPS provides stable controller that doesn't depend on darwin hosts being powered on
   - **Previous consideration**: blackphos was considered, but darwin machines may not be always-on

5. **Rollback strategy**: How to rollback individual host if migration fails?
   - **Approach**: Keep configurations/ until all hosts migrated
   - **Per-host**: Can rebuild from nixos-unified until proven stable

## Next steps

1. **Immediate**: Read `01-phase-0-validation.md` for dendritic + clan integration validation
2. **Phase 0**: Validate integration in test-clan/, document findings
3. **Phase 1**: Deploy cinnabar VPS using proven patterns (read `02-phase-1-vps-deployment.md`)
4. **Phase 2**: Migrate blackphos (read `03-phase-2-blackphos-guide.md`), establish darwin patterns
5. **Phases 3-4**: Migrate rosegold and argentum, validate multi-darwin
6. **Phase 5**: Migrate stibnite only after all others proven
7. **Phase 6**: Clean up legacy infrastructure
8. **Ongoing**: Document learnings, refine patterns

## References

### Dendritic pattern
- Canonical pattern: `~/projects/nix-workspace/dendritic-flake-parts/`
- README: `~/projects/nix-workspace/dendritic-flake-parts/README.md`
- Production examples:
  - `~/projects/nix-workspace/drupol-dendritic-infra/` (comprehensive)
  - `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/`
  - `~/projects/nix-workspace/mightyiam-dendritic-infra/`
  - `~/projects/nix-workspace/vic-dendritic-vix/`

### Clan documentation
- Architecture decisions: `~/projects/nix-workspace/clan-core/docs/site/decisions/`
- Vars system: `~/projects/nix-workspace/clan-core/docs/site/guides/vars/`
- Inventory: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/`
- Getting started: `~/projects/nix-workspace/clan-core/docs/site/getting-started/`

### Example repositories
- clan-infra: `~/projects/nix-workspace/clan-infra` (production clan + flake-parts with manual imports)
- clan-core: `~/projects/nix-workspace/clan-core` (monorepo with modules and CLI)
- Supporting clan examples:
  - `~/projects/nix-workspace/jfly-clan-snow/` (darwin + clan)
  - `~/projects/nix-workspace/mic92-clan-dotfiles/` (comprehensive clan usage)
  - `~/projects/nix-workspace/pinpox-clan-nixos/` (custom clan services)

### Local references
- Current config: `~/projects/nix-workspace/nix-config`
- Preferences: `~/.claude/commands/preferences/`
- import-tree: `~/projects/nix-workspace/import-tree/`
