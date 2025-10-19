# Clan integration plan for nixos-unified based configuration

## Executive summary

This document provides a comprehensive integration plan for adding Clan (clan.lol) capabilities to the existing nixos-unified based nix-config repository.
The integration follows a phased approach: Phase 1 adds new remote Clan-managed hosts without disrupting existing local configurations, and Phase 2 evaluates migrating existing hosts to Clan management.

## Repository analysis

### Current nix-config architecture

**Foundation**: nixos-unified with flake-parts
**Structure**:
- `flake.nix`: Uses `flake-parts.lib.mkFlake` with auto-wired imports from `./modules/flake-parts/`
- `configurations/{darwin,home,nixos}/`: Host-specific configurations
- `modules/{darwin,home,nixos}/`: Modular system and home-manager configurations
- `secrets/`: SOPS-based secrets management (both agenix and sops-nix available)
- `overlays/`, `packages/`: Custom package definitions
- `docs/notes/`: Documentation organized by topic

**Current hosts**:
- `stibnite` (darwin): Primary workstation
- `blackphos` (darwin): Secondary system
- `stibnite-nixos`, `blackphos-nixos` (nixos): CI validation mirrors
- `orb-nixos` (nixos): OrbStack/LXD test configurations

**Module organization**:
- Clean separation between darwin-only, home-only, and shared modules
- `modules/flake-parts/nixos-flake.nix` imports nixos-unified's flake modules
- Type-safe, functional patterns emphasized throughout
- Strong preference for explicit effects at boundaries

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

## Integration strategy

### Compatibility analysis

**Strong compatibility**:
- Both use flake-parts as foundational architecture
- Both support SOPS for secrets (clan uses sops-nix, nix-config has both agenix and sops-nix)
- Both emphasize modular, type-safe NixOS configurations
- Both follow functional programming patterns
- Clan's flake module integrates cleanly via flake-parts imports

**Key differences**:
- Clan adds inventory abstraction (not present in nixos-unified)
- Clan's vars system vs. manual secret management
- Clan services vs. plain NixOS modules
- Clan assumes multi-machine coordination, nixos-unified is machine-centric

**Integration approach**:
- Add clan-core as flake input
- Import `clan-core.flakeModules.default` in flake-parts imports
- Define `clan.inventory` for Clan-managed machines
- Keep existing configurations unchanged (stibnite, blackphos)
- Use separate module organization for Clan-specific services

### Directory structure proposal

```
nix-config/
├── flake.nix                      # Add clan-core input
├── configurations/
│   ├── darwin/                    # Unchanged
│   ├── home/                      # Unchanged
│   └── nixos/
│       ├── stibnite-nixos.nix    # Unchanged
│       ├── blackphos-nixos.nix   # Unchanged
│       └── remote/                # NEW: Clan-managed remote hosts
│           ├── hetzner-01.nix
│           └── hetzner-02.nix
├── modules/
│   ├── darwin/                    # Unchanged
│   ├── home/                      # Unchanged
│   ├── nixos/                     # Unchanged
│   ├── flake-parts/
│   │   ├── nixos-flake.nix       # Unchanged
│   │   └── clan.nix               # NEW: Clan inventory and instances
│   └── clan/                      # NEW: Clan-specific shared modules
│       └── hetzner-base.nix
├── secrets/
│   ├── hosts/                     # Existing SOPS structure
│   ├── services/
│   ├── users/
│   └── clan/                      # NEW: Clan vars storage
│       ├── groups/
│       ├── machines/
│       ├── secrets/
│       └── users/
└── docs/notes/
    └── clan-integration/          # This directory
        ├── 00-integration-plan.md # This document
        ├── 01-phase-1-guide.md    # Phase 1 implementation
        └── 02-migration-assessment.md # Phase 2 evaluation
```

**Rationale**:
- Minimal changes to existing structure
- Clear separation between local (nixos-unified) and remote (Clan) hosts
- Clan-specific concerns isolated to new directories
- Both secret management approaches can coexist during transition
- Module organization maintains current patterns

### Flake modifications

**Input additions**:
```nix
{
  inputs = {
    # Existing inputs...
    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.sops-nix.follows = "sops-nix";
    clan-core.inputs.home-manager.follows = "home-manager";
  };
}
```

**Import additions** in `flake.nix`:
```nix
{
  imports = with builtins;
    map (fn: ./modules/flake-parts/${fn}) (attrNames (readDir ./modules/flake-parts));
  # This will automatically pick up ./modules/flake-parts/clan.nix
}
```

**New file** `modules/flake-parts/clan.nix`:
```nix
{ inputs, ... }:
{
  imports = [
    inputs.clan-core.flakeModules.default
  ];

  clan = {
    meta.name = "nix-config-remote";
    specialArgs = { inherit inputs; };
    inventory.machines = {
      # Remote Clan-managed machines defined here
    };
    inventory.instances = {
      # Clan service instances defined here
    };
    secrets.sops.defaultGroups = [ "admins" ];
  };
}
```

### Module integration patterns

**Pattern 1: Isolated Clan services**
Create Clan-specific modules that only apply to Clan-managed hosts:
```nix
# modules/clan/hetzner-base.nix
{ lib, ... }:
{
  # Common configuration for all Hetzner remote hosts
  networking.firewall.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  # ... Hetzner-specific settings
}
```

**Pattern 2: Shared module adaptation**
Some existing modules can be reused for both local and Clan-managed hosts:
```nix
# modules/nixos/shared/nix.nix (existing)
# Already works for both local and Clan-managed hosts
```

**Pattern 3: Conditional Clan features**
Use `lib.mkIf` to conditionally enable Clan features:
```nix
{ config, lib, ... }:
{
  config = lib.mkIf (config.clan.core.settings.machine.name != null) {
    # Clan-specific configuration
  };
}
```

### Secrets management integration

**Coexistence strategy**:
- Existing secrets continue using current sops-nix/agenix setup
- New Clan-managed machines use Clan vars system
- Both store encrypted secrets in git (compatible approaches)
- Gradual migration possible by converting existing secrets to vars generators

**Clan vars directory**:
```
secrets/clan/
├── groups/
│   └── admins/          # Admin age keys
├── machines/
│   ├── hetzner-01/      # Per-machine age keys
│   └── hetzner-02/
├── secrets/
│   └── (encrypted files managed by clan CLI)
└── users/
    └── crs58/           # User age keys
```

**Initialization**:
```bash
# Generate age key for yourself
clan secrets key generate

# Create admin group
mkdir -p secrets/clan/groups/admins
clan secrets groups add admins

# Add yourself as admin
clan secrets users add crs58 <your-age-public-key>
clan secrets groups add-user admins crs58
```

## Phase 1: New remote hosts with Clan

### Objectives

- Add Clan capabilities without disrupting existing configurations
- Deploy 1-2 Hetzner remote hosts using Clan
- Demonstrate Clan's multi-machine coordination
- Validate vars system for secrets management
- Establish patterns for future remote deployments

### Success criteria

- [ ] Clan-core integrated into flake
- [ ] At least one remote host successfully deployed
- [ ] Vars system managing SSH keys, user passwords
- [ ] SSHD service with CA-signed certificates working
- [ ] Existing local hosts (stibnite, blackphos) unaffected
- [ ] Documentation updated with deployment workflow
- [ ] CI continues passing

### Implementation steps

See `01-phase-1-guide.md` for detailed implementation steps.

## Phase 2: Migration assessment

### Evaluation criteria

**Benefits of migrating existing hosts to Clan**:
1. **Unified management**: Single toolset for all hosts
2. **Multi-machine services**: Leverage Clan services across local and remote
3. **Declarative secrets**: Replace manual secret management with vars
4. **Service instances**: Cleaner organization of distributed services
5. **Inventory abstraction**: Tag-based configuration reduces duplication

**Costs of migration**:
1. **Breaking changes**: Existing configurations need restructuring
2. **Learning curve**: New abstractions (inventory, roles, instances)
3. **Tooling change**: Switch from nixos-unified's patterns to Clan's
4. **Testing overhead**: Validate all existing functionality preserved
5. **Complexity**: Additional layer of abstraction

**Recommendation**:
- Defer Phase 2 until Phase 1 validates Clan's benefits in production
- Re-evaluate after 2-3 months of operating Clan-managed remote hosts
- Likely candidates for migration: services that benefit from multi-machine coordination (backups, monitoring, overlay networks)
- Unlikely candidates: Local-only configurations, homebrew setup, darwin-specific features

See `02-migration-assessment.md` for detailed analysis.

## Key decisions and tradeoffs

### Decision 1: Separate directory structure vs. unified

**Chosen**: Separate directories for Clan-managed hosts
**Rationale**:
- Minimizes risk to existing configurations
- Clear separation of concerns
- Easier rollback if Clan doesn't meet needs
- Gradual migration path

**Tradeoff**: Some duplication of shared modules

### Decision 2: Dual secrets systems vs. full migration

**Chosen**: Dual systems (existing + Clan vars)
**Rationale**:
- Existing secrets continue working
- Clan vars proven in new deployments before migration
- No forced migration timeline
- Lower risk

**Tradeoff**: Two systems to maintain temporarily

### Decision 3: Instance organization in flake vs. separate files

**Chosen**: Single `modules/flake-parts/clan.nix` for inventory
**Rationale**:
- Follows clan-infra pattern
- Inventory naturally centralized (service coordination)
- Easier to see complete multi-machine topology
- Consistent with flake-parts philosophy

**Tradeoff**: Large file as instances grow (can refactor later)

### Decision 4: Clan services vs. plain NixOS modules

**Chosen**: Use Clan services for multi-machine coordination, plain modules for single-machine
**Rationale**:
- Leverage Clan's strengths (inventory, roles, multi-machine)
- Keep simple configurations simple
- Gradual adoption of Clan abstractions

**Tradeoff**: Two module styles in same repo

## Open questions

1. **SOPS backend configuration**: Does Clan's default SOPS setup conflict with existing sops-nix configuration?
   - **Investigation needed**: Test both systems in same flake
   - **Mitigation**: Use separate secret paths

2. **Home-manager integration**: Can Clan-managed machines use existing home-manager modules?
   - **Answer**: Yes, Clan imports home-manager, works normally
   - **Pattern**: Reference home modules from Clan machine configs

3. **Darwin support**: Can Clan manage darwin machines?
   - **Answer**: Clan supports darwin via machineClass = "darwin"
   - **Validation needed**: Test with local darwin hosts

4. **Build caching**: How does Clan affect cachix/binary cache usage?
   - **Answer**: Transparent, Clan uses standard nix builds
   - **Benefit**: Can cache Clan-core derivations

5. **Deployment authentication**: How to bootstrap SSH access to fresh Hetzner hosts?
   - **Pattern from clan-infra**: Terraform deploys SSH keys, then Clan takes over
   - **Alternative**: Hetzner rescue mode + manual key installation

## Next steps

1. **Immediate**: Read `01-phase-1-guide.md` and begin Phase 1 implementation
2. **After Phase 1**: Operate remote hosts for 2-3 months, gather experience
3. **Future**: Re-evaluate Phase 2 migration based on Phase 1 learnings
4. **Ongoing**: Document patterns, update this plan as understanding evolves

## References

### Clan documentation
- Architecture decisions: `~/projects/nix-workspace/clan-core/docs/site/decisions/`
- Vars system: `~/projects/nix-workspace/clan-core/docs/site/guides/vars/`
- Inventory: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/`
- Getting started: `~/projects/nix-workspace/clan-core/docs/site/getting-started/`

### Example repositories
- clan-infra: `~/projects/nix-workspace/clan-infra` (production infrastructure)
- clan-core: `~/projects/nix-workspace/clan-core` (monorepo with modules and CLI)

### Local references
- Current config: `~/projects/nix-workspace/nix-config`
- Preferences: `~/.claude/commands/preferences/`
