---
title: Dendritic + Clan Integration Documentation
---

# Dendritic + Clan integration documentation

This directory contains comprehensive documentation for migrating nix-config from nixos-unified to the dendritic flake-parts pattern with clan-core integration using a VPS-first infrastructure approach.

## Document overview

### 00-integration-plan.md
**Purpose**: Comprehensive analysis and overall migration strategy
**Contents**:
- Repository analysis (current nix-config, dendritic flake-parts pattern, clan architecture)
- Integration strategy and architectural decisions
- Directory structure (dendritic flat categories with terraform/)
- Module integration patterns (flake.modules.* namespace)
- Secrets management with clan vars
- Migration phases (Phase 0 validation → cinnabar VPS → blackphos → rosegold → argentum → stibnite)
- Key decisions and tradeoffs
- References to dendritic and clan examples

**When to read**: Start here for complete context and strategic overview

### 01-phase-0-validation.md
**Purpose**: Step-by-step implementation guide for Phase 0 (dendritic + clan integration validation in test-clan/)
**Contents**:
- Strategic rationale (why Phase 0 is critical before VPS deployment)
- Analysis of reference repositories (no production examples combining dendritic + clan)
- Step-by-step validation in test-clan/ (19 detailed steps)
- Integration points testing
- Findings documentation template
- Patterns extraction for cinnabar deployment
- Troubleshooting integration challenges

**When to read**: Before beginning migration to validate architectural combination in safe environment

### 02-phase-1-vps-deployment.md
**Purpose**: Step-by-step implementation guide for Phase 1 (cinnabar VPS deployment)
**Contents**:
- Prerequisites and Hetzner Cloud setup
- Terraform/terranix configuration for VPS provisioning
- Dendritic + clan infrastructure setup
- Disko configuration (LUKS encryption)
- Core services deployment (zerotier controller, sshd, emergency access)
- Validation procedures and troubleshooting
- Cost management and cleanup procedures

**When to read**: When ready to implement Phase 1 (deploying cinnabar VPS as foundation infrastructure)

### 03-phase-2-blackphos-guide.md
**Purpose**: Step-by-step implementation guide for Phase 2 (first darwin host migration)
**Contents**:
- Prerequisites (Phase 1 completion required)
- Darwin module conversion to dendritic flake-parts pattern
- Connecting to cinnabar's zerotier network as peer
- Home-manager integration
- Validation procedures
- Guidance for subsequent darwin hosts

**When to read**: After Phase 1 completed and cinnabar VPS stable (1-2 weeks)

**Status note**: This guide is being updated to reflect VPS-first workflow. Core steps remain valid but assume Phase 1 infrastructure already exists.

### 04-migration-assessment.md
**Purpose**: Validation criteria and assessment for each migration phase
**Contents**:
- Host-specific analysis (cinnabar VPS, blackphos, rosegold, argentum, stibnite)
- Per-phase success criteria and validation tests
- Migration scenarios with concrete validation procedures
- Decision framework (when to proceed vs. pause)
- Recommended conservative timeline (10-14 weeks with VPS)
- Rollback procedures

**When to read**: Throughout migration to evaluate readiness for each phase and validate success

## Quick start

### For immediate implementation (Phase 0: validation, then Phase 1: cinnabar VPS)

1. Read `00-integration-plan.md` (45-60 minutes) - understand VPS-first approach and Phase 0 rationale
2. Review Phase 0 guide: `01-phase-0-validation.md` - understand integration validation
3. Complete Phase 0 validation in test-clan/ (4-8 hours) - prove dendritic + clan works
4. Document findings and extract patterns
5. Proceed to Phase 1: Review prerequisites in `02-phase-1-vps-deployment.md`
6. Set up Hetzner Cloud account and generate API token
7. Follow Phase 1 implementation steps sequentially (using patterns from Phase 0)
8. Deploy cinnabar VPS and validate infrastructure
9. Monitor stability for 1-2 weeks before darwin migration

### For planning and evaluation

1. Skim `00-integration-plan.md` executive summary
2. Review "Phase 0 validation" rationale (untested architectural combination)
3. Review "VPS-first infrastructure approach" rationale
4. Read "Migration phases" section for complete workflow
5. Review `04-migration-assessment.md` for per-host validation criteria

### After Phase 0 (integration validated)

1. Review integration findings from test-clan/
2. Extract patterns for cinnabar deployment
3. Proceed to Phase 1 (cinnabar VPS) with confidence

### After Phase 1 (cinnabar VPS deployed)

1. Monitor cinnabar stability for 1-2 weeks
2. Verify zerotier controller operational
3. Document any issues or pattern refinements needed
4. Review `04-migration-assessment.md` Phase 2 readiness criteria
5. Proceed to Phase 2 (blackphos) when cinnabar proven stable

### Progressive migration workflow

**Phase 0** (Week 0-1): Validate dendritic + clan in test-clan/, document integration findings
**Phase 1** (Week 1-3): Deploy cinnabar VPS, validate dendritic + clan on NixOS, establish zerotier controller
**Phase 2** (Week 4-6): Migrate blackphos, validate darwin + clan integration, connect to zerotier network
**Phase 3** (Week 7-9): Migrate rosegold, validate multi-darwin coordination
**Phase 4** (Week 10-12): Migrate argentum, final validation before primary workstation
**Phase 5** (Week 13-15): Migrate stibnite (primary workstation, highest risk)
**Phase 6** (Week 16+): Cleanup (remove nixos-unified, old configs)

## Key concepts

### Dendritic flake-parts pattern

**Why dendritic? Type safety through module system**

Nix lacks a native type system, but the Nix module system provides type checking through explicit option types.
flake-parts extends the module system to flakes.
The dendritic flake-parts pattern maximizes module system usage, thereby maximizing type safety in flake configurations.

Both clan-core and clan-infra already use flake-parts.
The dendritic flake-parts pattern is an incremental optimization that increases type safety by organizing all code as flake-parts modules.

**Priority**: clan functionality is primary; dendritic is a best-effort optimization applied where compatible.

**Core principle**: eliminate specialArgs, centralize all values through flake-parts module system

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
├── nixos/          # NixOS-specific modules
├── darwin/         # Darwin-specific modules
├── shell/          # Shell tools (fish, starship)
├── dev/            # Development tools (git, languages)
├── hosts/          # Machine-specific compositions
│   ├── cinnabar/   # VPS infrastructure
│   ├── blackphos/  # Darwin hosts
│   ├── rosegold/
│   ├── argentum/
│   └── stibnite/
├── flake-parts/    # Flake-level modules (clan inventory, terranix)
├── terranix/       # Terraform/terranix modules
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
# 1. Create host configuration using dendritic flake-parts pattern
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

### Phase 0 (test-clan validation)
- [ ] test-clan flake evaluates successfully
- [ ] import-tree discovers all dendritic modules
- [ ] Clan inventory evaluates correctly
- [ ] nixosConfiguration builds for test-vm
- [ ] Clan vars generation succeeds
- [ ] Integration points documented
- [ ] Patterns extracted for cinnabar
- [ ] No critical blockers identified
- [ ] Findings document completed

### Phase 1 (cinnabar VPS)
- [ ] Hetzner Cloud VPS provisioned via terraform
- [ ] Dendritic module structure created and operational
- [ ] NixOS installed with LUKS encryption
- [ ] Clan vars deployed successfully
- [ ] Zerotier controller operational on cinnabar
- [ ] SSH access functional
- [ ] Stable for 1-2 weeks
- [ ] Darwin hosts (stibnite, blackphos, rosegold, argentum) still build with nixos-unified

### Phase 2 (blackphos)
- [ ] blackphos builds with dendritic + clan (darwin modules converted)
- [ ] All functionality preserved (no regressions)
- [ ] Zerotier peer connects to cinnabar controller
- [ ] cinnabar ↔ blackphos network functional
- [ ] SSH via zerotier works (certificate-based)
- [ ] Stable for 1-2 weeks

### Phase 3 (rosegold)
- [ ] rosegold builds using blackphos patterns (minimal changes)
- [ ] Zerotier peer connects to cinnabar controller
- [ ] 3-machine network functional (cinnabar ↔ blackphos ↔ rosegold)
- [ ] Patterns confirmed reusable
- [ ] Stable for 1-2 weeks

### Phase 4 (argentum)
- [ ] argentum builds using established patterns
- [ ] 4-machine zerotier network operational
- [ ] No new issues discovered
- [ ] Stable for 1-2 weeks
- [ ] Ready for stibnite migration

### Phase 5 (stibnite)
- [ ] stibnite builds using proven patterns
- [ ] All daily workflows functional
- [ ] No productivity loss
- [ ] 5-machine network complete (cinnabar + 4 darwin)
- [ ] Stable for 1-2 weeks

### Phase 6 (cleanup)
- [ ] All hosts migrated successfully
- [ ] nixos-unified removed
- [ ] Old configurations cleaned up
- [ ] Documentation updated

## Red flags requiring pause or rollback

- Phase 0: Integration blockers preventing test-clan from building
- Phase 0: Architectural conflicts between dendritic and clan
- Build evaluation errors
- Missing functionality compared to nixos-unified
- Dendritic flake-parts patterns require excessive customization per host
- Clan vars not deploying correctly
- Zerotier network instabilities
- Frequent system crashes or errors
- Unknown issues without clear fixes
- Productivity significantly impacted (stibnite)

## Resources

### Local documentation
- Integration plan: `./00-integration-plan.md` (start here)
- Phase 0 validation: `./01-phase-0-validation.md` (test-clan integration testing)
- Phase 1 VPS guide: `./02-phase-1-vps-deployment.md` (cinnabar deployment)
- Phase 2 darwin guide: `./03-phase-2-blackphos-guide.md` (blackphos migration)
- Migration assessment: `./04-migration-assessment.md` (validation criteria)

### Dendritic flake-parts pattern
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
- clan-infra: `~/projects/nix-workspace/clan-infra` (production clan + flake-parts with manual imports)
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
