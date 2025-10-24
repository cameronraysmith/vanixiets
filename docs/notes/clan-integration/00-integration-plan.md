# Clan integration plan for dendritic flake-parts + clan-core migration

## Executive summary

This document provides a comprehensive migration plan for transitioning nix-config from nixos-unified to the dendritic flake-parts pattern with clan-core integration.
The migration follows a staged host-by-host approach: migrate test machines first (blackphos → rosegold → argentum), validate multi-machine coordination, then migrate the primary workstation (stibnite) last.
This eliminates nixos-unified while adopting clan-core's inventory system, vars management, and multi-machine service coordination using the dendritic pattern's `flake.modules.*` namespace.

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
- `blackphos` (darwin, aarch64): Already activated, test migration first (migrate FIRST)
- `rosegold` (darwin, aarch64): Not currently in daily use (migrate SECOND)
- `argentum` (darwin, aarch64): Not currently in daily use (migrate THIRD)
- `stibnite-nixos`, `blackphos-nixos` (nixos): CI validation mirrors
- `orb-nixos` (nixos): OrbStack/LXD test configurations

**Migration order rationale**:
1. **blackphos**: Already has nix-config activated, not primary workstation (lowest risk)
2. **rosegold**: Not in daily use, can test zerotier multi-machine coordination
3. **argentum**: Not in daily use, validates patterns before primary migration
4. **stibnite**: Primary workstation, migrate only after all others proven stable

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
- clan-infra production infrastructure uses dendritic pattern, not nixos-unified
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
│   │   ├── blackphos/default.nix  # First to migrate
│   │   ├── rosegold/default.nix   # Second to migrate
│   │   ├── argentum/default.nix   # Third to migrate
│   │   └── stibnite/default.nix   # Last to migrate (primary)
│   ├── flake-parts/               # Flake-level configuration
│   │   ├── nixpkgs.nix            # Nixpkgs setup and overlays
│   │   ├── host-machines.nix      # Generate darwinConfigurations
│   │   └── clan.nix               # Clan inventory and instances
│   └── users/                     # User configurations
│       └── crs58/default.nix      # User metadata and config
├── secrets/                        # CHANGED: Clan vars only (migrate from sops)
│   ├── groups/
│   │   └── admins/                # Admin group age keys
│   ├── machines/
│   │   ├── blackphos/
│   │   ├── rosegold/
│   │   ├── argentum/
│   │   └── stibnite/
│   ├── secrets/                   # Encrypted secrets
│   └── users/
│       └── crs58/                 # User age keys
├── overlays/                      # Existing overlays preserved
├── packages/                      # Existing packages preserved
└── docs/notes/
    └── clan-integration/          # This directory
        ├── 00-integration-plan.md # This document
        ├── 01-phase-1-guide.md    # Migration implementation
        └── 02-migration-assessment.md # Host-specific considerations
```

**Migration path**:
```
Phase 0: Preparation
- Add clan-core and import-tree inputs
- Create modules/ structure alongside existing files

Phase 1: Module conversion
- Convert modules/{darwin,home,nixos}/* to modules/{base,shell,dev}/*
- Update to flake.modules.{darwin,homeManager,nixos}.* namespace
- Keep existing configurations/ active during conversion

Phase 2: Host migration (blackphos)
- Create modules/hosts/blackphos/default.nix
- Add to clan inventory
- Test and validate
- Once stable, can reference for other hosts

Phase 3: Test hosts (rosegold, argentum)
- Create modules/hosts/{rosegold,argentum}/default.nix
- Test zerotier multi-machine coordination
- Validate dendritic + clan patterns

Phase 4: Primary migration (stibnite)
- Migrate only after others proven stable
- Create modules/hosts/stibnite/default.nix
- Final validation

Phase 5: Cleanup
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
    # Remove nixos-unified
    # nixos-unified.url = "github:srid/nixos-unified";

    # Add clan-core and import-tree
    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.sops-nix.follows = "sops-nix";
    clan-core.inputs.home-manager.follows = "home-manager";
    clan-core.inputs.nix-darwin.follows = "nix-darwin";

    import-tree.url = "github:vic/import-tree";
  };
}
```

**Flake structure** (simplified with import-tree):
```nix
{
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
    (inputs.import-tree ./modules);
  # import-tree recursively imports all .nix files in modules/
  # Each file is a flake-parts module contributing to flake.modules.*
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

      zerotier-local = {
        module = { name = "zerotier"; input = "clan-core"; };
        roles.controller.machines.blackphos = {};
        roles.peer.tags."workstation" = {};
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

## Migration phases

### Phase 0: Preparation (blackphos parallel environment)

**Objective**: Set up dendritic + clan alongside existing nixos-unified

**Tasks**:
- Add clan-core and import-tree flake inputs
- Create `modules/` directory with dendritic structure
- Initialize clan secrets
- Keep existing `configurations/` active

**Success criteria**:
- [ ] Flake evaluates with clan-core integrated
- [ ] import-tree discovers modules/
- [ ] Secrets initialized
- [ ] Existing configs still build

### Phase 1: blackphos migration

**Objective**: Migrate first machine as proof of concept

**Tasks**:
- Convert darwin modules to dendritic pattern in `modules/{base,darwin,shell,dev}/`
- Create `modules/hosts/blackphos/default.nix`
- Add to clan inventory
- Generate vars for blackphos
- Deploy and validate

**Success criteria**:
- [ ] blackphos builds with dendritic + clan
- [ ] All functionality preserved
- [ ] Zerotier network operational (blackphos as controller)
- [ ] Secrets deployed via clan vars

### Phase 2: rosegold migration

**Objective**: Validate patterns on second machine

**Tasks**:
- Create `modules/hosts/rosegold/default.nix` (reuse blackphos patterns)
- Add to clan inventory with zerotier peer role
- Generate vars and deploy
- Test multi-machine zerotier coordination

**Success criteria**:
- [ ] rosegold operational
- [ ] blackphos ↔ rosegold zerotier communication
- [ ] Patterns validated for reuse

### Phase 3: argentum migration

**Objective**: Third machine validation before primary

**Tasks**:
- Create `modules/hosts/argentum/default.nix`
- Add to clan inventory
- Deploy and test
- Validate 3-machine zerotier network

**Success criteria**:
- [ ] argentum operational
- [ ] 3-machine coordination working
- [ ] Ready for primary migration

### Phase 4: stibnite migration

**Objective**: Migrate primary workstation

**Tasks**:
- Create `modules/hosts/stibnite/default.nix`
- Extra validation and testing
- Deploy only after phases 1-3 stable
- Keep fallback path available

**Success criteria**:
- [ ] stibnite operational
- [ ] All daily workflows functional
- [ ] 4-machine zerotier network complete

### Phase 5: Cleanup

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
- clan-infra production infrastructure uses dendritic, not nixos-unified
- Cleaner `flake.modules.*` namespace vs directory autowire
- import-tree auto-discovery more flexible than directory scanning
- Proven scalability (drupol-dendritic-infra, clan-infra)

**Tradeoff**: Migration effort, but progressive per-host approach mitigates risk

### Decision 2: Migration order

**Chosen**: blackphos → rosegold → argentum → stibnite
**Rationale**:
- blackphos already activated, not daily driver (lowest risk)
- rosegold and argentum not in daily use (safe testing grounds)
- stibnite migrated last after patterns proven (highest value, highest risk)
- Multi-machine coordination testable with multiple non-primary hosts

**Tradeoff**: Cannot test on primary workstation until late in process

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
   - **Chosen**: blackphos (first migrated, always on)
   - **Rationale**: Stable, not primary workstation

5. **Rollback strategy**: How to rollback individual host if migration fails?
   - **Approach**: Keep configurations/ until all hosts migrated
   - **Per-host**: Can rebuild from nixos-unified until proven stable

## Next steps

1. **Immediate**: Read `01-phase-1-guide.md` for detailed implementation steps
2. **Phase 0**: Set up dendritic structure parallel to existing configs
3. **Phase 1**: Migrate blackphos, establish patterns
4. **Phases 2-3**: Migrate rosegold and argentum, validate multi-machine
5. **Phase 4**: Migrate stibnite only after others proven
6. **Phase 5**: Clean up legacy infrastructure
7. **Ongoing**: Document learnings, refine patterns

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
- clan-infra: `~/projects/nix-workspace/clan-infra` (production, uses dendritic)
- clan-core: `~/projects/nix-workspace/clan-core` (monorepo with modules and CLI)
- Supporting clan examples:
  - `~/projects/nix-workspace/jfly-clan-snow/` (darwin + clan)
  - `~/projects/nix-workspace/mic92-clan-dotfiles/` (comprehensive, dendritic + clan)
  - `~/projects/nix-workspace/pinpox-clan-nixos/` (custom clan services)

### Local references
- Current config: `~/projects/nix-workspace/nix-config`
- Preferences: `~/.claude/commands/preferences/`
- import-tree: `~/projects/nix-workspace/import-tree/`
