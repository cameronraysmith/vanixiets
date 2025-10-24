# Phase 0 implementation guide: dendritic + clan validation (test-clan)

This guide provides step-by-step instructions for Phase 0 of the dendritic flake-parts + clan-core migration.
Phase 0 validates the integration of dendritic and clan patterns in a minimal test environment (test-clan/) before deploying production infrastructure.
This de-risks the migration by proving the architectural combination works before committing to VPS deployment and darwin host migration.

## Strategic rationale: why Phase 0 is critical

**Problem identified**: The proposed dendritic flake-parts + clan-core integration appears to be architecturally untested in production.

Analysis of reference repositories reveals:
- `~/projects/nix-workspace/clan-infra/`: Uses clan WITHOUT dendritic (manual imports in flake.nix)
- `~/projects/nix-workspace/drupol-dendritic-infra/`: Uses dendritic WITHOUT clan (pure import-tree pattern)
- `~/projects/nix-workspace/jfly-clan-snow/`: Uses clan WITHOUT dendritic (darwin + clan)
- `~/projects/nix-workspace/mic92-clan-dotfiles/`: Uses clan WITHOUT dendritic

**No production example exists combining both patterns.**

**Risk without Phase 0**: Current documentation proposes deploying this untested combination directly to production VPS (cinnabar), creating compound debugging complexity across 8 simultaneous layers:
1. Dendritic pattern (import-tree, flake.modules.*)
2. Clan-core flake-parts integration
3. Terraform/terranix provisioning
4. Hetzner Cloud infrastructure
5. Disko partitioning
6. LUKS encryption
7. Zerotier networking
8. NixOS configuration

**Solution: Phase 0 validation**
- Test dendritic + clan integration in minimal environment (test-clan/)
- Identify and resolve integration challenges before infrastructure deployment
- Document proven patterns for cinnabar (Phase 1) deployment
- Reduce risk by isolating architectural validation from infrastructure complexity

## Prerequisites

- [ ] Read `00-integration-plan.md` for complete migration context
- [ ] Read dendritic pattern documentation: `~/projects/nix-workspace/dendritic-flake-parts/README.md`
- [ ] Read clan getting started: `~/projects/nix-workspace/clan-core/docs/site/getting-started/`
- [ ] Understanding of flake-parts module system
- [ ] Familiarity with nixos module system
- [ ] test-clan repository location: `~/projects/nix-workspace/test-clan/`
- [ ] Age key generated for clan secrets (will do in steps)

## Phase 0 overview

Phase 0 validates dendritic + clan integration by:
1. Converting test-clan from old clan API to dendritic + flake-parts pattern
2. Creating minimal dendritic module structure
3. Configuring clan inventory with single test machine
4. Deploying essential clan services (emergency-access, sshd, zerotier)
5. Testing all critical integration points
6. Building nixosConfiguration successfully
7. Documenting findings and patterns for Phase 1

**Expected duration**: 4-8 hours of focused work + validation time

**Success criteria**: test-clan builds successfully, dendritic + clan integration proven, patterns documented for cinnabar deployment

## Step 1: Examine current test-clan structure

Current test-clan uses the old clan API pattern. Let's understand what needs to change:

**Current pattern** (old clan API):
```bash
cd ~/projects/nix-workspace/test-clan

# Examine current structure
cat flake.nix  # Uses clan-core.lib.clan (old API)
cat clan.nix   # inventory defined but not flake-parts compatible
ls modules/    # Single module, not dendritic structure
```

**Current flake.nix** uses:
```nix
clan = clan-core.lib.clan {
  inherit self;
  imports = [ ./clan.nix ];
  specialArgs = { inherit inputs; };
};
```

**Target pattern** (dendritic + flake-parts):
```nix
inputs.flake-parts.lib.mkFlake { inherit inputs; } (
  inputs.import-tree ./modules
)
```

Key differences:
- Old: `clan-core.lib.clan` wrapper function
- New: `clan-core.flakeModules.default` + flake-parts
- Old: Manual imports from clan.nix
- New: import-tree auto-discovery
- Old: Single-file configuration
- New: Dendritic module structure with flake.modules.* namespace

## Step 2: Backup current test-clan

Preserve the current state before modifications:

```bash
cd ~/projects/nix-workspace/test-clan

# Create backup branch
git checkout -b backup-pre-dendritic
git add -A
git commit -m "backup: pre-dendritic state"
git checkout -b phase-0-dendritic-validation main
```

## Step 3: Rewrite flake.nix for dendritic + clan pattern

Replace flake.nix with dendritic pattern:

**File**: `~/projects/nix-workspace/test-clan/flake.nix`

```nix
{
  description = "Test environment for dendritic + clan integration validation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    clan-core.inputs.flake-parts.follows = "flake-parts";

    import-tree.url = "github:vic/import-tree";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      inputs.import-tree ./modules
    );
}
```

**Key changes**:
- Added flake-parts input
- Added import-tree input
- Changed outputs to use `flake-parts.lib.mkFlake`
- Use `import-tree ./modules` for auto-discovery
- Removed old `clan-core.lib.clan` wrapper

**Validation**:
```bash
cd ~/projects/nix-workspace/test-clan
nix flake lock  # Update lockfile
nix flake show  # Verify flake evaluates (will fail initially, that's expected)
```

Expected at this point: Evaluation errors because modules/ doesn't follow dendritic pattern yet.

## Step 4: Create dendritic module directory structure

Create dendritic-style module organization:

```bash
cd ~/projects/nix-workspace/test-clan

# Remove old structure
rm -rf modules/
rm clan.nix

# Create dendritic structure
mkdir -p modules/base
mkdir -p modules/nixos
mkdir -p modules/hosts/test-vm
mkdir -p modules/flake-parts
```

**Directory layout**:
```
modules/
├── base/               # Foundation modules (nix settings)
├── nixos/              # NixOS-specific modules
├── hosts/              # Machine-specific configurations
│   └── test-vm/        # Test machine configuration
└── flake-parts/        # Flake-level modules (clan inventory, nixosConfigurations)
```

## Step 5: Create base nix configuration module

**File**: `~/projects/nix-workspace/test-clan/modules/base/nix.nix`

```nix
{
  flake.modules = {
    nixos.base-nix = {
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@wheel"
        ];

        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
          "https://cache2.clan.lol"
        ];

        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "niks3.clan.lol-1:R1VTRLhKHvKKrx/X36wAMuay2bdagsGylwfF7wPs6ns="
        ];
      };

      nix.gc = {
        automatic = true;
        dates = "weekly";
      };
    };
  };
}
```

**Pattern note**: Defines `flake.modules.nixos.base-nix` in dendritic namespace.

## Step 6: Create nixos server module

**File**: `~/projects/nix-workspace/test-clan/modules/nixos/server.nix`

```nix
{
  flake.modules.nixos.server = {
    # Clan state version management
    clan.core.settings.state-version.enable = true;

    # Basic server configuration
    boot.tmp.cleanOnBoot = true;

    # Firewall
    networking.firewall.enable = true;

    # Automatic garbage collection
    nix.gc = {
      automatic = true;
      dates = [ "weekly" ];
    };

    # Basic packages
    environment.systemPackages = with pkgs; [
      vim
      git
      htop
      curl
      wget
    ];
  };
}
```

## Step 7: Create clan inventory module

This is a critical integration point - clan inventory as flake-parts module:

**File**: `~/projects/nix-workspace/test-clan/modules/flake-parts/clan.nix`

```nix
{ inputs, ... }:
{
  imports = [ inputs.clan-core.flakeModules.default ];

  clan = {
    meta.name = "test-clan";

    specialArgs = {
      inherit inputs;
    };

    # Machine inventory
    inventory.machines = {
      test-vm = {
        tags = [
          "nixos"
          "test"
        ];
        machineClass = "nixos";
      };
    };

    # Service instances
    inventory.instances = {
      # Emergency access for all machines
      emergency-access = {
        module = {
          name = "emergency-access";
          input = "clan-core";
        };
        roles.default.tags."all" = { };
      };

      # Root user management
      users-root = {
        module = {
          name = "users";
          input = "clan-core";
        };
        roles.default.machines.test-vm = { };
        roles.default.settings = {
          user = "root";
          prompt = false;
          groups = [ ];
        };
      };

      # Zerotier network (test-vm as both controller and peer for simplicity)
      zerotier-test = {
        module = {
          name = "zerotier";
          input = "clan-core";
        };
        # test-vm is controller
        roles.controller.machines.test-vm = { };
        # test-vm is also peer
        roles.peer.machines.test-vm = { };
      };

      # SSH with certificate authority
      sshd-clan = {
        module = {
          name = "sshd";
          input = "clan-core";
        };
        roles.server.tags."all" = { };
        roles.client.tags."all" = { };
      };
    };

    # Secrets configuration
    secrets.sops.defaultGroups = [ "admins" ];
  };
}
```

**Integration point 1**: `imports = [ inputs.clan-core.flakeModules.default ]` integrates clan into flake-parts

**Integration point 2**: Clan inventory coexists with dendritic modules in flake-parts config

## Step 8: Create nixosConfigurations generator

This tests if clan inventory can work alongside dendritic's `flake.modules.nixos.*` pattern:

**File**: `~/projects/nix-workspace/test-clan/modules/flake-parts/host-machines.nix`

```nix
{
  inputs,
  lib,
  config,
  ...
}:
let
  prefix = "hosts/";
  collectHostsModules = modules: lib.filterAttrs (name: _: lib.hasPrefix prefix name) modules;
in
{
  flake.nixosConfigurations = lib.pipe (collectHostsModules config.flake.modules.nixos) [
    (lib.mapAttrs' (
      name: module:
      let
        hostName = lib.removePrefix prefix name;
      in
      {
        name = hostName;
        value = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
          };
          modules = [ module ];
        };
      }
    ))
  ];
}
```

**Integration point 3**: nixosConfigurations generation must not conflict with clan's machineConfigurations

## Step 9: Create test-vm host configuration

**File**: `~/projects/nix-workspace/test-clan/modules/hosts/test-vm/default.nix`

```nix
{
  config,
  pkgs,
  ...
}:
{
  flake.modules.nixos."hosts/test-vm" = {
    imports = [
      # Import dendritic base modules
      config.flake.modules.nixos.base-nix
      config.flake.modules.nixos.server
    ];

    # Host identification
    networking.hostName = "test-vm";

    # System state version
    system.stateVersion = "24.11";

    # Clan SOPS default groups
    clan.core.sops.defaultGroups = [ "admins" ];

    # Enable SSH
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
      };
    };

    # Root SSH keys (replace with your key)
    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderKeyReplaceWithYourActualSSHPublicKey"
    ];

    # Timezone
    time.timeZone = "UTC";

    # Boot loader (for VM)
    boot.loader.grub.enable = true;
    boot.loader.grub.device = "/dev/vda";
  };
}
```

**Integration point 4**: Host module uses `config.flake.modules.nixos.*` to import dendritic modules while being managed by clan inventory

**Important**: Replace the SSH public key with your actual key.

## Step 10: Initialize clan secrets structure

Create clan secrets and initialize age keys:

```bash
cd ~/projects/nix-workspace/test-clan

# Create secrets directory structure
mkdir -p sops/{groups,machines,secrets,users}

# Generate your age key if not already done
# This will create ~/.config/sops/age/keys.txt (Linux) or
# ~/Library/Application Support/sops/age/keys.txt (macOS)
nix run nixpkgs#clan-cli -- secrets key generate

# Extract your public key
# macOS:
YOUR_AGE_KEY=$(grep 'public key:' ~/Library/Application\ Support/sops/age/keys.txt | awk '{print $4}')
# Linux:
# YOUR_AGE_KEY=$(grep 'public key:' ~/.config/sops/age/keys.txt | awk '{print $4}')

echo "Your age public key: $YOUR_AGE_KEY"

# Create admin group
nix run nixpkgs#clan-cli -- secrets groups add admins

# Add yourself as admin
nix run nixpkgs#clan-cli -- secrets users add testuser "$YOUR_AGE_KEY"
nix run nixpkgs#clan-cli -- secrets groups add-user admins testuser
```

**Validation**:
```bash
ls -la sops/groups/admins/
ls -la sops/users/testuser/
nix run nixpkgs#clan-cli -- secrets list
```

## Step 11: Test flake evaluation

At this point, test if the dendritic + clan integration evaluates:

```bash
cd ~/projects/nix-workspace/test-clan

# Check flake structure
nix flake show

# Verify import-tree discovered all modules
fd -e nix . modules/

# Check dendritic module namespace
nix eval .#flake.modules.nixos --apply builtins.attrNames
# Expected: [ "base-nix" "hosts/test-vm" "server" ]

# Check clan inventory
nix eval .#clan.inventory --json | jq .

# Verify nixosConfigurations generated
nix eval .#nixosConfigurations --apply builtins.attrNames
# Expected: [ "test-vm" ]
```

**Integration point 5**: All of these should evaluate successfully if dendritic + clan integration works

## Step 12: Build test-vm configuration

Attempt to build the nixosConfiguration:

```bash
cd ~/projects/nix-workspace/test-clan

# Build test-vm configuration (dry-run, won't deploy)
nix build .#nixosConfigurations.test-vm.config.system.build.toplevel

# If successful:
ls -la result/
readlink result
```

**Expected outcome**:
- Build succeeds: Dendritic + clan integration works!
- Build fails: Examine error messages for integration conflicts

**Common issues**:
- `specialArgs` conflicts between dendritic and clan
- Module evaluation order problems
- Clan services not finding dendritic modules
- Missing or duplicate options

## Step 13: Generate clan vars for test-vm

Test clan vars generation:

```bash
cd ~/projects/nix-workspace/test-clan

# Generate all vars for test-vm
nix run nixpkgs#clan-cli -- vars generate test-vm

# You'll be prompted for:
# - Emergency access password
# - Any other service-specific prompts

# Verify vars generated
ls -la sops/machines/test-vm/

# List generated vars
nix run nixpkgs#clan-cli -- vars list test-vm
```

**Integration point 6**: Clan vars system should work with dendritic-structured configuration

## Step 14: Validate clan services integration

Test that clan services can access dendritic modules:

```bash
cd ~/projects/nix-workspace/test-clan

# Check zerotier service configuration
nix eval .#nixosConfigurations.test-vm.config.services.zerotier-one --json | jq .

# Check sshd-clan service
nix eval .#nixosConfigurations.test-vm.config.services.openssh --json | jq .

# Check emergency-access user configuration
nix eval .#nixosConfigurations.test-vm.config.users.users --json | jq 'keys'
```

Expected: All clan services configured correctly, accessing dendritic base modules

## Step 15: Test import-tree discovery

Verify import-tree discovers all dendritic modules correctly:

```bash
cd ~/projects/nix-workspace/test-clan

# List all discovered .nix files
fd -e nix . modules/

# Check each is imported
nix eval .#_module.args --json | jq 'keys'

# Verify flake.modules namespace populated
nix eval .#flake --apply 'flake: flake.modules or {}' --json | jq 'keys'
```

**Integration point 7**: import-tree should discover all dendritic modules AND play nicely with clan flakeModules

## Step 16: Test clan CLI integration

Test clan CLI commands work with dendritic structure:

```bash
cd ~/projects/nix-workspace/test-clan

# List machines
nix run nixpkgs#clan-cli -- machines list

# Show test-vm configuration
nix run nixpkgs#clan-cli -- machines show test-vm

# Verify clan flake detection
nix run nixpkgs#clan-cli -- flakes inspect .
```

Expected: Clan CLI recognizes the flake and can interact with inventory

## Step 17: Optional - deploy to test VM

If you have a test VM or suitable target (optional):

```bash
cd ~/projects/nix-workspace/test-clan

# Deploy to existing NixOS machine or create VM
# VM creation (if you want to test deployment):
nix run nixpkgs#nixos-rebuild -- build-vm --flake .#test-vm

# Or install to real machine:
# nix run nixpkgs#clan-cli -- machines install test-vm \
#   --target-host root@test-vm-ip \
#   -i ~/.ssh/id_ed25519
```

This step is optional but provides the most complete validation

## Step 18: Document integration findings

Create a findings document based on your experience:

**File**: `~/projects/nix-workspace/test-clan/INTEGRATION-FINDINGS.md`

Template:
```markdown
# Dendritic + Clan integration findings

Date: YYYY-MM-DD
Tester: [your name]

## What works perfectly

- [ ] import-tree discovers all dendritic modules
- [ ] clan-core.flakeModules.default integrates with flake-parts
- [ ] flake.modules.nixos.* namespace accessible from clan services
- [ ] Clan inventory evaluation succeeds
- [ ] nixosConfigurations generation works
- [ ] Clan vars generation succeeds
- [ ] Clan services (emergency-access, sshd, zerotier) configure correctly
- [ ] nixosConfiguration builds successfully
- [ ] (Optional) Deployment to test-vm succeeds

## What requires compromise

- Describe any deviations from pure dendritic pattern
- Describe any clan features that needed adjustment
- Note any conflicts resolved

## What doesn't work

- List any blockers or failures
- Describe integration conflicts

## Necessary pattern adjustments

- Document patterns that differ from reference implementations
- Note workarounds or special configurations needed

## Integration challenges and solutions

### Challenge 1: [describe]
**Solution**: [describe]

### Challenge 2: [describe]
**Solution**: [describe]

## Recommendations for cinnabar deployment

1. [Recommendation based on findings]
2. [Recommendation based on findings]

## Open questions

- [Questions requiring further investigation]
```

Fill this template based on your actual experience with the integration

## Step 19: Create reference patterns for cinnabar

Extract proven patterns for use in Phase 1:

**File**: `~/projects/nix-workspace/test-clan/PATTERNS.md`

```markdown
# Proven patterns for cinnabar deployment

## Flake structure

The following pattern successfully integrates dendritic + clan:

```nix
# flake.nix
inputs.flake-parts.lib.mkFlake { inherit inputs; } (
  inputs.import-tree ./modules
)
```

## Module organization

```
modules/
├── base/               # Foundation (works with clan)
├── nixos/              # NixOS-specific (works with clan services)
├── hosts/              # Host configs (works with clan inventory)
└── flake-parts/        # Clan integration point
    ├── clan.nix        # Inventory and instances
    └── host-machines.nix  # nixosConfigurations generator
```

## Host configuration pattern

```nix
flake.modules.nixos."hosts/hostname" = {
  imports = [
    config.flake.modules.nixos.base-nix
    config.flake.modules.nixos.server
  ];
  # Host-specific config
};
```

## Clan inventory pattern

```nix
# modules/flake-parts/clan.nix
{ inputs, ... }:
{
  imports = [ inputs.clan-core.flakeModules.default ];

  clan = {
    meta.name = "name";
    inventory.machines = { /* ... */ };
    inventory.instances = { /* ... */ };
  };
}
```

## Notes

- Clan flakeModules.default must be imported in a flake-parts module
- specialArgs should include `inherit inputs` for access in modules
- nixosConfigurations can be generated from flake.modules.nixos."hosts/*"
- Clan inventory coexists peacefully with dendritic namespace
```

## Validation checklist

After completing all steps:

- [ ] Flake evaluates successfully: `nix flake show`
- [ ] import-tree discovers all modules: `fd -e nix . modules/`
- [ ] Dendritic module namespace populated: `nix eval .#flake.modules.nixos --apply builtins.attrNames`
- [ ] Clan inventory evaluates: `nix eval .#clan.inventory --json`
- [ ] nixosConfigurations generated: `nix eval .#nixosConfigurations --apply builtins.attrNames`
- [ ] test-vm configuration builds: `nix build .#nixosConfigurations.test-vm.config.system.build.toplevel`
- [ ] Clan secrets initialized: `ls sops/groups/admins/`
- [ ] Clan vars generated: `nix run nixpkgs#clan-cli -- vars list test-vm`
- [ ] Clan services configured: verify in build output
- [ ] Integration findings documented: `INTEGRATION-FINDINGS.md` created
- [ ] Patterns documented for cinnabar: `PATTERNS.md` created
- [ ] (Optional) Deployment tested: test-vm deployed successfully

## Evaluation framework: assessing dendritic feasibility

Phase 0 determines how much dendritic pattern can be applied while preserving clan functionality.

### Evaluation criteria

**Technical validation** (required):
- [ ] Clan functionality works correctly
- [ ] All clan services operational
- [ ] Multi-machine coordination functional
- [ ] Secrets/vars system working

**Pattern optimization** (best-effort):
- [ ] How much code uses flake.modules.* namespace?
- [ ] Where are dendritic compromises necessary?
- [ ] Are compromises localized or pervasive?
- [ ] Does dendritic improve clarity or add complexity?

**Trade-off assessment**:
- Benefits gained: type safety, organization clarity
- Costs incurred: complexity, maintenance burden, community support
- Balance: are benefits worth costs?

### Decision scenarios

**Scenario A: clean integration (>80% dendritic)**
- Minimal compromises required
- Clan features work with dendritic organization
- Code is clearer than vanilla clan+flake-parts
- Type safety benefits realized
→ **Decision**: proceed with dendritic+clan to Phase 1

**Scenario B: partial integration (40-80% dendritic)**
- Some dendritic compromises necessary
- Certain clan features require specialArgs
- Mixed organization (some dendritic, some standard)
- Type safety partially improved
→ **Decision**: use hybrid approach, document deviations
→ **Evaluation**: assess if partial benefits justify complexity

**Scenario C: minimal integration (<40% dendritic)**
- Pervasive conflicts with clan patterns
- Most code requires dendritic violations
- Marginal type safety improvement
- Added complexity outweighs benefits
→ **Decision**: use vanilla clan+flake-parts (clan-infra pattern)
→ **Rationale**: proven approach, community support, simpler

**Scenario D: fundamental incompatibility**
- Architectural conflicts prevent clan functionality
- Essential clan features broken with dendritic
- No viable compromise path
→ **Decision**: abandon dendritic, use standard clan
→ **Pivot**: follow clan-infra organization exactly

### Acceptable compromises

**When dendritic patterns must be relaxed**:

1. **Clan requires specialArgs**:
   - Document why and where
   - Minimize usage scope
   - Acceptable: clan functionality > dendritic purity

2. **Clan modules need standard imports**:
   - Use standard flake-parts alongside import-tree
   - Mixed approach acceptable
   - Acceptable: pragmatic hybrid

3. **Clan services incompatible with flake.modules.***:
   - Use clan patterns for service definitions
   - Use dendritic for other modules
   - Acceptable: best tool for each job

4. **import-tree conflicts with clan discovery**:
   - Manual imports for clan components
   - import-tree for other modules
   - Acceptable: incremental benefit

**Unacceptable compromises**:

1. Breaking clan functionality for dendritic purity
2. Significant complexity without type safety benefit
3. Patterns that future contributors cannot understand
4. Maintenance burden that outweighs benefits

### Alternative: vanilla clan pattern

If Phase 0 shows dendritic adds more complexity than value:

**Reference**: `~/projects/nix-workspace/clan-infra/`

**Organization**:
- Standard flake-parts (no import-tree)
- Manual imports in flake.nix
- Proven clan integration
- Maintained by clan developers
- Strong community support

**Benefits**:
- Well-documented pattern
- Production-proven
- Community troubleshooting available
- Simpler for contributors

**Trade-off**:
- Less type safety than full dendritic
- Manual module imports
- Some specialArgs usage

**When to choose**:
- Phase 0 shows dendritic conflicts are pervasive
- Complexity outweighs type safety benefits
- Team prefers proven patterns
- Time constraints favor simplicity

This is a **valid, production-proven alternative**, not a failure case.

## Troubleshooting

### Issue: Flake evaluation fails with "infinite recursion"

**Cause**: Circular imports or module conflicts

**Solution**:
```bash
# Check for circular dependencies
nix eval .#_module.args --show-trace

# Verify import-tree is discovering correct files
fd -e nix . modules/
```

### Issue: Clan inventory not found

**Error**: `attribute 'clan' missing`

**Solution**: Verify clan.nix imports `clan-core.flakeModules.default`:
```nix
# modules/flake-parts/clan.nix
{ inputs, ... }:
{
  imports = [ inputs.clan-core.flakeModules.default ];
  clan = { /* ... */ };
}
```

### Issue: nixosConfigurations empty

**Error**: `nix eval .#nixosConfigurations` returns `{}`

**Solution**: Check host-machines.nix logic:
```bash
# Verify hosts modules exist
nix eval .#flake.modules.nixos --apply 'builtins.attrNames'
# Should include "hosts/test-vm"

# Check collection logic
nix eval .#flake.modules.nixos --apply 'modules: builtins.filter (name: lib.hasPrefix "hosts/" name) (builtins.attrNames modules)'
```

### Issue: Clan vars generation fails

**Error**: `No generators found for machine`

**Solution**: Verify clan services define generators:
```bash
# Check what generators are expected
nix eval .#nixosConfigurations.test-vm.config.clan.core.vars.generators --json | jq 'keys'

# Ensure clan services are imported
nix eval .#clan.inventory.instances --json | jq 'keys'
```

### Issue: Module namespace not accessible in hosts

**Error**: `config.flake.modules.nixos.base-nix is undefined`

**Solution**: Ensure host module receives flake-parts config:
```nix
# Incorrect:
{ pkgs, ... }: { imports = [ config.flake.modules.nixos.base-nix ]; }

# Correct:
{ config, pkgs, ... }: { imports = [ config.flake.modules.nixos.base-nix ]; }
```

### Issue: import-tree not discovering modules

**Solution**: Verify .nix files are in modules/ and follow naming conventions:
```bash
# All .nix files should be discovered
fd -e nix . modules/

# Verify no .gitignore excludes
cat .gitignore | grep -E '\.nix|modules'
```

### Issue: Clan and dendritic specialArgs conflict

**Error**: Conflicting specialArgs definitions

**Solution**: Consolidate specialArgs in clan.nix:
```nix
clan = {
  specialArgs = { inherit inputs; };
  # Other clan config
};
```

Do not duplicate in nixosSystem calls

## Common integration challenges

### Challenge: Accessing dendritic modules from clan services

**Pattern**:
```nix
# Clan services can access dendritic base modules through imports
flake.modules.nixos."hosts/test-vm" = {
  imports = [
    config.flake.modules.nixos.base-nix  # Works!
    config.flake.modules.nixos.server    # Works!
  ];
};
```

### Challenge: Clan inventory vs. nixosConfigurations

**Finding**: Both can coexist. Clan inventory manages service instances, nixosConfigurations provides build targets.

**Pattern**:
```nix
# clan.nix defines inventory
inventory.machines.test-vm = { /* ... */ };

# host-machines.nix generates nixosConfigurations
flake.nixosConfigurations.test-vm = nixosSystem { /* ... */ };
```

### Challenge: import-tree discovering non-module files

**Solution**: Only include .nix files that are flake-parts modules in modules/:
```bash
# Move non-module files elsewhere
mv modules/data.nix lib/data.nix
mv modules/constants.nix lib/constants.nix
```

## Integration points summary

1. **import-tree + clan flakeModules**: Both work through flake-parts, no conflict
2. **flake.modules.* + clan inventory**: Coexist in flake-parts config
3. **nixosConfigurations + clan machines**: Can be generated independently
4. **Dendritic modules + clan services**: Services can import dendritic modules
5. **Clan vars + dendritic structure**: Vars system works regardless of module organization
6. **specialArgs**: Managed by clan configuration, accessed in dendritic modules
7. **Module discovery**: import-tree discovers all modules including flake-parts/clan.nix

## Success criteria: evaluating Phase 0 outcomes

Phase 0 is successful when it provides **clear answers** about dendritic feasibility with clan, regardless of whether full dendritic pattern is achievable.

### Required outcomes (must achieve all)

**Technical validation**:
- [ ] test-clan/ repository builds successfully
- [ ] Clan functionality works (inventory, vars, services)
- [ ] Multi-machine coordination operational (if tested with multiple VMs)
- [ ] Secrets/vars system functional
- [ ] At least one deployment successful (VM or test machine)

**Integration characterization**:
- [ ] Documented: what dendritic patterns work cleanly with clan
- [ ] Documented: where compromises are necessary
- [ ] Documented: specific clan features requiring dendritic violations
- [ ] Evaluated: type safety benefits gained vs complexity added

**Decision readiness**:
- [ ] Clear recommendation: full dendritic / hybrid / vanilla clan
- [ ] Rationale: why recommendation is appropriate
- [ ] Patterns identified: specific approach for Phase 1 (cinnabar)
- [ ] Compromises accepted: documented deviations with justification

### Outcome scenarios (all valid)

**Outcome 1: dendritic-optimized clan** (best case)
- Most code follows dendritic pattern
- Minimal compromises needed
- Clear type safety benefits
- Code clearer than alternatives
→ Proceed to Phase 1 with dendritic+clan

**Outcome 2: hybrid approach** (pragmatic)
- Dendritic where compatible
- Standard clan patterns where necessary
- Mixed organization documented
- Net benefit positive but modest
→ Proceed to Phase 1 with hybrid pattern

**Outcome 3: vanilla clan** (proven alternative)
- Dendritic compromises too extensive
- Standard clan+flake-parts simpler
- Complexity outweighs type safety gains
- Follow clan-infra pattern
→ Proceed to Phase 1 with vanilla clan

**All three outcomes are successful Phase 0 completions.**

Success = informed decision, not necessarily full dendritic adoption.

### Failure criteria (restart Phase 0)

Phase 0 fails only if:
- Cannot get clan working at all (with or without dendritic)
- Cannot build test-clan/ repository
- Cannot evaluate integration trade-offs
- No clear pattern identified for Phase 1

Technical clan functionality is required.
Full dendritic pattern is aspirational.

## Next steps: Phase 1 (cinnabar VPS deployment)

After Phase 0 validation succeeds:

1. **Review integration findings**: Read `INTEGRATION-FINDINGS.md` and `PATTERNS.md`
2. **Extract proven patterns**: Apply successful patterns to cinnabar configuration
3. **Begin Phase 1**: Follow `02-phase-1-vps-deployment.md` (renamed from 01)
4. **Reference test-clan**: Use as template when creating cinnabar modules
5. **Apply learnings**: Incorporate any necessary compromises or adjustments discovered in Phase 0

**Key advantage**: Phase 1 (cinnabar) deployment will use proven patterns, significantly reducing risk

**Timeline**: Complete Phase 0 → Wait for validation (1-2 days) → Proceed to Phase 1

## Additional resources

### Dendritic pattern
- Pattern documentation: `~/projects/nix-workspace/dendritic-flake-parts/README.md`
- Production examples:
  - `~/projects/nix-workspace/drupol-dendritic-infra/` (dendritic only, no clan)

### Clan documentation
- Getting started: `~/projects/nix-workspace/clan-core/docs/site/getting-started/`
- Inventory: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/`
- Vars: `~/projects/nix-workspace/clan-core/docs/site/guides/vars/`
- Services: `~/projects/nix-workspace/clan-core/clanServices/`

### Example repositories
- clan-infra: `~/projects/nix-workspace/clan-infra` (clan only, no dendritic)
- jfly-clan-snow: `~/projects/nix-workspace/jfly-clan-snow/` (darwin + clan)

### Test environment
- test-clan: `~/projects/nix-workspace/test-clan/` (this validation environment)

## Document history

- 2025-10-24: Created Phase 0 validation guide for dendritic + clan integration testing
