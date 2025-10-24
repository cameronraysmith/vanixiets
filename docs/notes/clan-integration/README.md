# Dendritic + Clan integration documentation

This directory contains comprehensive documentation for migrating nix-config from nixos-unified to the dendritic flake-parts pattern with clan-core integration.

## Document overview

### 00-integration-plan.md
**Purpose**: Comprehensive analysis and overall migration strategy
**Contents**:
- Repository analysis (current nix-config, dendritic pattern, clan architecture)
- Integration strategy and architectural decisions
- Directory structure (dendritic flat categories)
- Module integration patterns (flake.modules.* namespace)
- Secrets management with clan vars
- Migration phases (blackphos → rosegold → argentum → stibnite)
- Key decisions and tradeoffs
- References to dendritic and clan examples

**When to read**: Start here for complete context and strategic overview

### 01-phase-1-guide.md
**Purpose**: Step-by-step implementation guide for Phase 1 (blackphos migration)
**Contents**:
- Prerequisites and preparation
- 15 detailed migration steps (inputs, dendritic structure, blackphos deployment)
- Code examples using dendritic patterns
- Validation procedures
- Troubleshooting guide
- Guidance for rosegold, argentum, stibnite migrations

**When to read**: When ready to implement Phase 1 (migrating blackphos to dendritic + clan)

### 02-migration-assessment.md
**Purpose**: Validation criteria and assessment for each migration phase
**Contents**:
- Host-specific analysis (blackphos, rosegold, argentum, stibnite)
- Per-phase success criteria and validation tests
- Migration scenarios with concrete validation procedures
- Decision framework (when to proceed vs. pause)
- Recommended conservative timeline (8-12 weeks)
- Rollback procedures

**When to read**: Throughout migration to evaluate readiness for each phase and validate success

## Quick start

### For immediate implementation (Phase 1: blackphos)

1. Read `00-integration-plan.md` (45-60 minutes) - understand dendritic pattern and migration strategy
2. Review prerequisites in `01-phase-1-guide.md`
3. Follow Phase 1 implementation steps 1-15 sequentially
4. Deploy to blackphos and validate
5. Monitor stability for 1-2 weeks before proceeding

### For planning and evaluation

1. Skim `00-integration-plan.md` executive summary
2. Review "Dendritic flake-parts pattern" and "Integration strategy"
3. Read "Migration phases" section for host order rationale
4. Review `02-migration-assessment.md` for per-host validation criteria

### After Phase 1 (blackphos deployed)

1. Monitor blackphos stability for 1-2 weeks
2. Document any issues or pattern refinements needed
3. Review `02-migration-assessment.md` Scenario 2 for rosegold readiness
4. Proceed to Phase 2 (rosegold) when blackphos proven stable

### Progressive migration workflow

**Phase 1** (Week 0-2): Migrate blackphos, validate dendritic + clan patterns
**Phase 2** (Week 3-5): Migrate rosegold, validate multi-machine coordination
**Phase 3** (Week 6-8): Migrate argentum, validate 3-machine network
**Phase 4** (Week 9-11): Migrate stibnite (primary workstation, highest risk)
**Phase 5** (Week 12+): Cleanup (remove nixos-unified, old configs)

## Key concepts

### Dendritic flake-parts pattern

**Core principle**: Eliminate specialArgs, centralize all values through flake-parts module system

**Key features**:
- **Module namespace**: Every module contributes to `flake.modules.{darwin,homeManager,nixos}.*`
- **import-tree auto-discovery**: Recursively imports all .nix files in modules/ directory
- **Metadata sharing**: Use `config.flake.meta.*` for cross-module data (user info, etc.)
- **Host composition**: Hosts import from `config.flake.modules.*` namespace
- **Cross-cutting concerns**: One module can target multiple systems (darwin + homeManager)

**Directory organization**: Flat feature categories instead of system-based hierarchy
```
modules/
├── base/           # Foundation (nix settings, state versions)
├── darwin/         # Darwin-specific modules
├── shell/          # Shell tools (fish, starship)
├── dev/            # Development tools (git, languages)
├── hosts/          # Machine-specific compositions
└── users/          # User metadata and configurations
```

**Reference**: `~/projects/nix-workspace/dendritic-flake-parts/` and production examples in `~/projects/nix-workspace/drupol-dendritic-infra/`

### Clan architecture essentials

**Inventory**: Abstract service layer for multi-machine coordination
- `inventory.machines`: All machines with tags and machineClass
- `inventory.instances`: Service instances with roles
- Configuration hierarchy: instance → role → machine
- Tag-based service distribution across machines

**Vars system**: Declarative secret and file generation
- Replaces manual secret management
- Generators define how to create files from inputs
- Storage backends (SOPS default) handle encryption
- Automatic deployment during machine updates

**Clan services**: New module class for distributed services
- `_class = "clan.service"`
- Role-based (client, server, peer, controller, etc.)
- Instance-based (multiple instances of same service)
- Multi-machine coordination built-in
- Example: zerotier with blackphos as controller, others as peers

### Migration approach

**Strategy**: Progressive host-by-host migration with validation gates

**Order**: blackphos → rosegold → argentum → stibnite

**Rationale**:
- blackphos: Lowest risk, establishes all patterns
- rosegold/argentum: Not in daily use, validates multi-machine coordination
- stibnite: Primary workstation, migrate only after all others proven stable

**Safety**: Parallel environment (dendritic modules/ alongside nixos-unified configurations/), preserve rollback path

## Directory structure (target state after migration)

```
nix-config/
├── flake.nix                      # UPDATED: Uses import-tree ./modules
├── modules/                        # NEW: Dendritic structure (flat categories)
│   ├── base/                      # Foundation modules (nix settings, state versions)
│   ├── darwin/                    # Darwin-specific modules
│   ├── shell/                     # Shell tools (fish, starship, direnv)
│   ├── dev/                       # Development tools (git, languages)
│   ├── hosts/                     # Machine-specific configurations
│   │   ├── blackphos/default.nix  # Phase 1
│   │   ├── rosegold/default.nix   # Phase 2
│   │   ├── argentum/default.nix   # Phase 3
│   │   └── stibnite/default.nix   # Phase 4
│   ├── flake-parts/               # Flake-level configuration
│   │   ├── nixpkgs.nix            # Nixpkgs setup and overlays
│   │   ├── host-machines.nix      # Generate darwinConfigurations
│   │   └── clan.nix               # Clan inventory and instances
│   └── users/                     # User configurations and metadata
│       └── crs58/default.nix
├── secrets/                        # UPDATED: Clan vars structure
│   ├── groups/admins/             # Admin group age keys
│   ├── machines/                  # Per-machine secrets
│   │   ├── blackphos/
│   │   ├── rosegold/
│   │   ├── argentum/
│   │   └── stibnite/
│   ├── secrets/                   # Shared encrypted secrets
│   └── users/crs58/               # User age keys
├── configurations/                # PRESERVED during migration (for rollback)
└── docs/notes/clan-integration/   # This directory
```

## Common workflows

### Migrating a darwin host

```bash
# 1. Create host configuration using dendritic pattern
vim modules/hosts/<hostname>/default.nix

# 2. Generate clan vars
nix run .#clan-cli -- vars generate <hostname>

# 3. Build configuration
nix build .#darwinConfigurations.<hostname>.system

# 4. Deploy to host
darwin-rebuild switch --flake .#<hostname>

# 5. Validate functionality
# Test all workflows, check zerotier, verify secrets deployed
```

### Updating migrated host

```bash
# After configuration changes
darwin-rebuild switch --flake .#<hostname>

# Or using clan (equivalent)
nix run .#clan-cli -- machines update <hostname>
```

### Managing clan secrets

```bash
# Add user
nix run .#clan-cli -- secrets users add <username> <age-key>

# Grant admin access
nix run .#clan-cli -- secrets groups add-user admins <username>

# Generate vars for a host
nix run .#clan-cli -- vars generate <hostname>
```

### Validating dendritic modules

```bash
# Check import-tree discovered modules
fd -e nix . modules/

# Verify module namespace
nix eval .#flake.modules.darwin --apply builtins.attrNames
nix eval .#flake.modules.homeManager --apply builtins.attrNames

# Check host configurations generated
nix eval .#darwinConfigurations --apply builtins.attrNames

# Verify clan inventory
nix eval .#clan.inventory --json
```

## Success metrics per migration phase

### Phase 1 (blackphos)
- [ ] Dendritic module structure created and operational
- [ ] blackphos builds with dendritic + clan
- [ ] All functionality preserved (no regressions)
- [ ] Clan vars deployed successfully
- [ ] Zerotier controller operational on blackphos
- [ ] Stable for 1-2 weeks
- [ ] Other hosts (stibnite, rosegold, argentum) still build with nixos-unified

### Phase 2 (rosegold)
- [ ] rosegold builds using blackphos patterns (minimal changes)
- [ ] Zerotier peer connects to blackphos controller
- [ ] 2-machine network functional (blackphos ↔ rosegold)
- [ ] Patterns confirmed reusable
- [ ] Stable for 1-2 weeks

### Phase 3 (argentum)
- [ ] argentum builds using established patterns
- [ ] 3-machine zerotier network operational
- [ ] No new issues discovered
- [ ] Stable for 1-2 weeks
- [ ] Ready for stibnite migration

### Phase 4 (stibnite)
- [ ] stibnite builds using proven patterns
- [ ] All daily workflows functional
- [ ] No productivity loss
- [ ] 4-machine network complete
- [ ] Stable for 1-2 weeks

### Phase 5 (cleanup)
- [ ] All hosts migrated successfully
- [ ] nixos-unified removed
- [ ] Old configurations cleaned up
- [ ] Documentation updated

## Red flags requiring pause or rollback

- Build evaluation errors
- Missing functionality compared to nixos-unified
- Dendritic patterns require excessive customization per host
- Clan vars not deploying correctly
- Zerotier network instabilities
- Frequent system crashes or errors
- Unknown issues without clear fixes
- Productivity significantly impacted (stibnite)

## Resources

### Local documentation
- Integration plan: `./00-integration-plan.md` (start here)
- Implementation guide: `./01-phase-1-guide.md` (blackphos migration steps)
- Migration assessment: `./02-migration-assessment.md` (validation criteria)
- Interactive prompt: `./prompt-interactive-integration.md` (guided migration)

### Dendritic pattern
- Pattern documentation: `~/projects/nix-workspace/dendritic-flake-parts/README.md`
- Production examples:
  - `~/projects/nix-workspace/drupol-dendritic-infra/` (comprehensive)
  - `~/projects/nix-workspace/mic92-clan-dotfiles/` (dendritic + clan)
  - `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/`

### Clan documentation
- Getting started: `~/projects/nix-workspace/clan-core/docs/site/getting-started/`
- Vars system: `~/projects/nix-workspace/clan-core/docs/site/guides/vars/`
- Inventory: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/`
- Architecture decisions: `~/projects/nix-workspace/clan-core/docs/site/decisions/`

### Example repositories
- clan-infra: `~/projects/nix-workspace/clan-infra` (production dendritic + clan)
- clan-core: `~/projects/nix-workspace/clan-core` (modules and CLI)
- jfly-clan-snow: `~/projects/nix-workspace/jfly-clan-snow/` (darwin + clan example)

### Community
- Matrix: `#clan:clan.lol`
- IRC: `#clan` on hackint

## Maintenance

This documentation should be updated:

1. **After Phase 1 completion**: Add retrospective document with learnings
2. **When Clan patterns evolve**: Update examples and recommendations
3. **If migration attempted**: Document actual migration experience
4. **When issues discovered**: Add to troubleshooting sections
5. **As community best practices emerge**: Incorporate proven patterns

## Questions or issues

If you encounter issues or have questions not covered in this documentation:

1. Check troubleshooting sections in implementation guide
2. Review Clan documentation in `clan-core/docs/`
3. Search clan-infra for similar patterns
4. Consult Clan community channels
5. Document the issue and resolution for future reference

## Document history

- 2025-10-19: Initial comprehensive integration plan created based on repository analysis
- Future: Update with Phase 1 retrospective and actual implementation learnings
