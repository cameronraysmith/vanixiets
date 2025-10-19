# Clan integration documentation

This directory contains comprehensive documentation for integrating Clan (clan.lol) capabilities into the nixos-unified based nix-config repository.

## Document overview

### 00-integration-plan.md
**Purpose**: Comprehensive analysis and overall integration strategy
**Contents**:
- Repository analysis (current nix-config, Clan architecture, clan-infra patterns)
- Integration strategy and compatibility analysis
- Proposed directory structure and flake modifications
- Module integration patterns
- Secrets management integration approach
- Key decisions and tradeoffs
- Open questions and next steps

**When to read**: Start here for complete context and strategic overview

### 01-phase-1-guide.md
**Purpose**: Step-by-step implementation guide for Phase 1
**Contents**:
- Prerequisites and preparation
- 15 detailed implementation steps
- Code examples and configurations
- Validation procedures
- Troubleshooting guide
- Post-deployment checklist

**When to read**: When ready to implement Phase 1 (adding Clan for remote hosts)

### 02-migration-assessment.md
**Purpose**: Evaluation of migrating existing hosts to Clan
**Contents**:
- Current state analysis (stibnite, blackphos)
- Benefits vs. costs analysis
- Four migration scenarios with recommendations
- Decision framework and timeline
- Pre-migration checklist
- Host-specific considerations

**When to read**: After Phase 1 completion, when evaluating migration of existing hosts

## Quick start

### For immediate implementation

1. Read `00-integration-plan.md` (30-45 minutes)
2. Review prerequisites in `01-phase-1-guide.md`
3. Follow Phase 1 implementation steps sequentially
4. Document learnings and issues encountered

### For planning and evaluation

1. Skim `00-integration-plan.md` executive summary
2. Review "Integration strategy" and "Directory structure proposal"
3. Read decision rationale sections
4. Note open questions relevant to your use case

### After Phase 1 deployment

1. Operate remote Clan-managed hosts for 2-3 months
2. Document experiences, pain points, and benefits
3. Read `02-migration-assessment.md` with context from Phase 1
4. Use decision framework to evaluate Phase 2

## Key concepts

### Clan architecture essentials

**Inventory**: Abstract service layer for multi-machine coordination
- `inventory.machines`: All machines with tags and machineClass
- `inventory.instances`: Service instances with roles
- Configuration hierarchy: instance → role → machine

**Vars system**: Declarative secret and file generation
- Replaces manual secret management
- Generators define how to create files from inputs
- Storage backends (SOPS default) handle encryption
- Automatic deployment during machine updates

**Clan services**: New module class for distributed services
- `_class = "clan.service"`
- Role-based (client, server, peer, etc.)
- Instance-based (multiple instances of same service)
- Multi-machine coordination built-in

### Integration approach

**Phase 1 (Recommended immediate action)**:
- Add Clan for new remote hosts only
- Existing hosts (stibnite, blackphos) unchanged
- Validate Clan benefits without migration risk
- Establish patterns for future use

**Phase 2 (Future consideration)**:
- Evaluate migrating existing hosts to Clan
- Defer decision until Phase 1 learnings available
- Multiple scenarios available (full, partial, service-specific, none)
- Default recommendation: keep existing hosts as-is

## Directory structure (post-Phase 1)

```
nix-config/
├── configurations/nixos/remote/   # NEW: Clan-managed remote hosts
├── modules/
│   ├── flake-parts/clan.nix       # NEW: Clan inventory and instances
│   └── clan/                       # NEW: Clan-specific shared modules
├── secrets/clan/                   # NEW: Clan vars storage
│   ├── groups/
│   ├── machines/
│   ├── secrets/
│   └── users/
└── docs/notes/clan-integration/   # This directory
```

## Common workflows

### Adding a new remote host

```bash
# 1. Create configuration
vim configurations/nixos/remote/new-host.nix

# 2. Add to inventory
vim modules/flake-parts/clan.nix  # Add to inventory.machines

# 3. Generate vars
nix run .#clan-cli -- vars generate new-host

# 4. Deploy
nix run .#clan-cli -- machines install new-host --target-host root@<ip>
```

### Updating remote host

```bash
nix run .#clan-cli -- machines update <hostname>
```

### Managing secrets

```bash
# Add user
nix run .#clan-cli -- secrets users add <username> <age-key>

# Grant admin access
nix run .#clan-cli -- secrets groups add-user admins <username>
```

## Success metrics for Phase 1

- [ ] Remote host successfully deployed via Clan
- [ ] Vars system managing secrets effectively
- [ ] Multi-machine services (e.g., SSHD, emergency-access) functioning
- [ ] Existing local hosts completely unaffected
- [ ] Deployment workflow clearer than previous approaches
- [ ] Documentation sufficient for repeating process

## Red flags requiring Phase 2 reconsideration

- Frequent Clan bugs or instabilities
- Vars system more complex than manual management
- Abstractions (inventory, roles) more confusing than helpful
- Poor darwin support or community adoption
- Breaking changes in Clan without clear migration path

## Resources

### Local documentation
- Integration plan: `./00-integration-plan.md`
- Implementation guide: `./01-phase-1-guide.md`
- Migration assessment: `./02-migration-assessment.md`

### Clan documentation
- Getting started: `~/projects/nix-workspace/clan-core/docs/site/getting-started/`
- Vars system: `~/projects/nix-workspace/clan-core/docs/site/guides/vars/`
- Inventory: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/`
- Architecture decisions: `~/projects/nix-workspace/clan-core/docs/site/decisions/`

### Example repositories
- clan-infra: `~/projects/nix-workspace/clan-infra` (production infrastructure)
- clan-core: `~/projects/nix-workspace/clan-core` (modules and CLI)
- srid-nixos-config: `~/projects/nix-workspace/srid-nixos-config` (nixos-unified example)

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
