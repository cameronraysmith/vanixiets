# Phase 2 migration assessment: existing hosts to Clan

This document evaluates the potential migration of existing hosts (stibnite, blackphos) from pure nixos-unified management to Clan management.

## Important note

**Phase 2 should only be considered after successfully completing Phase 1 and operating Clan-managed remote hosts for 2-3 months.**
This assessment is provided for planning purposes and will be refined based on Phase 1 learnings.

## Current state analysis

### Stibnite (primary workstation, darwin)

**Current setup**:
- Platform: aarch64-darwin (Apple Silicon Mac)
- Management: nix-darwin + home-manager via nixos-unified
- Configuration: `configurations/darwin/stibnite.nix`
- Modules: Extensive darwin-specific and home-manager modules
- Secrets: SOPS-based, manual management
- Services: Homebrew, system preferences, development tools

**Characteristics**:
- Interactive workstation (not server)
- Frequent configuration changes
- Complex darwin-specific settings
- Heavy home-manager usage
- Local-only (not distributed)

### Blackphos (secondary system, darwin)

**Current setup**:
- Platform: aarch64-darwin (Apple Silicon Mac)
- Management: Similar to stibnite
- Configuration: `configurations/darwin/blackphos.nix`
- Usage: Secondary development environment

**Characteristics**:
- Similar to stibnite
- Less frequently used
- Potential testing ground for migration

## Migration benefits analysis

### Potential benefits

**1. Unified secret management via vars**

**Current state**:
```nix
# Manual secret management
sops.secrets.example-secret = {
  sopsFile = ./secrets/hosts/stibnite.yaml;
  # ... manual configuration
};
```

**Clan approach**:
```nix
# Declarative generation
clan.core.vars.generators.example-secret = {
  prompts.value.description = "Example secret";
  script = "...";
  files.secret = { secret = true; };
};

# Automatic reference
services.example.secretFile = config.clan.core.vars.generators.example-secret.files.secret.path;
```

**Benefit**: Less manual secret file management, declarative generation
**Value**: Medium (current approach works, but vars more elegant)

**2. Multi-machine service coordination**

**Example use case**: Backup between stibnite and blackphos
```nix
# Clan inventory approach
inventory.instances.local-backup = {
  module = { name = "borgbackup"; input = "clan-core"; };
  roles.client.machines.stibnite = {};
  roles.server.machines.blackphos = {};
};
```

**Current approach**: Manually configure both machines with shared secrets

**Benefit**: Cleaner multi-machine coordination
**Value**: Low-Medium (only 2 machines, limited distributed services)

**3. Inventory abstraction for common settings**

**Example**: Apply settings to all darwin machines via tags
```nix
inventory.machines = {
  stibnite.tags = [ "darwin" "workstation" ];
  blackphos.tags = [ "darwin" "workstation" ];
};

inventory.instances.common-darwin = {
  # ... applies to all darwin machines
  roles.default.tags."darwin" = {};
};
```

**Benefit**: Reduce duplication across similar machines
**Value**: Low (only 2 similar machines, current approach maintainable)

**4. Consistent tooling across all hosts**

**Benefit**: Same `clan` CLI for local and remote hosts
**Value**: Medium (consistency valuable, but current tools work well)

### Migration costs

**1. Configuration restructuring**

**Required changes**:
- Move machine configs to Clan inventory structure
- Convert services to Clan service instances
- Migrate darwin-specific modules to work with Clan
- Update all module imports and references

**Estimated effort**: 2-3 days for initial migration, 1-2 weeks for validation
**Risk**: High (breaking production workstation setup)

**2. Darwin compatibility validation**

**Unknown factors**:
- Clan's darwin support maturity
- Interaction with nix-darwin-specific features
- Homebrew integration with Clan
- macOS-specific module compatibility

**Required testing**:
- Full functionality validation on darwin
- Homebrew workflow preservation
- System preference management
- GUI application integration

**Estimated effort**: 1 week testing and troubleshooting
**Risk**: Medium-High (darwin support less mature than NixOS)

**3. Home-manager integration patterns**

**Questions**:
- How to organize home-manager modules with Clan inventory?
- Can existing home modules be reused as-is?
- How do per-user settings work with Clan's machine-centric model?

**Required work**:
- Validate home-manager compatibility
- Establish patterns for user-specific vs. machine-specific config
- Test multi-user scenarios

**Estimated effort**: 2-3 days
**Risk**: Low-Medium (home-manager well-supported by Clan)

**4. Secret migration**

**Required actions**:
- Convert existing SOPS secrets to Clan vars generators
- Migrate age keys to Clan structure
- Validate all secret references updated
- Ensure rollback path for sensitive data

**Estimated effort**: 1-2 days per machine
**Risk**: High (secret management critical, errors costly)

**5. Rollback complexity**

**Challenge**: Once migrated, rolling back requires:
- Removing Clan infrastructure
- Restoring nixos-unified-only patterns
- Re-migrating secrets to previous structure
- Validating all functionality restored

**Estimated effort**: 1-2 days for rollback
**Risk**: High (complexity of two-way migration)

**6. Learning curve and ongoing maintenance**

**Considerations**:
- Learning Clan abstractions (inventory, roles, instances)
- Understanding when to use Clan services vs. plain modules
- Debugging Clan-specific issues
- Keeping up with Clan development

**Ongoing cost**: 10-20% increase in complexity
**Risk**: Medium (additional abstraction layer)

## Migration scenarios

### Scenario 1: Full migration (both hosts)

**Approach**: Migrate both stibnite and blackphos to Clan management

**Pros**:
- Consistent management across all hosts
- Full utilization of Clan features
- Clean final architecture

**Cons**:
- Highest risk (both production machines)
- Maximum effort required
- No comparison baseline if issues arise

**Recommendation**: Not recommended unless Phase 1 demonstrates overwhelming benefits

### Scenario 2: Partial migration (blackphos only)

**Approach**: Migrate blackphos (secondary machine) to Clan, keep stibnite on nixos-unified

**Pros**:
- Lower risk (secondary machine)
- Allows comparison of approaches
- Fallback to stibnite if issues
- Testing ground for patterns

**Cons**:
- Inconsistent management across machines
- Still requires solving darwin+Clan challenges
- Dual maintenance burden

**Recommendation**: Viable if Phase 1 shows strong benefits and darwin support validated

### Scenario 3: Service-specific migration

**Approach**: Use Clan for specific distributed services, keep core machine management with nixos-unified

**Example**:
```nix
# Clan manages only backup service
inventory.instances.local-backup = {
  module = { name = "borgbackup"; input = "clan-core"; };
  roles.client.machines.stibnite = {};
  roles.server.machines.blackphos = {};
};

# Core machine management stays with nixos-unified
darwinConfigurations.stibnite = {
  # ... existing nixos-unified configuration
  # Import specific Clan services as plain NixOS modules
};
```

**Pros**:
- Minimal disruption to existing setup
- Leverage Clan for specific benefits (multi-machine coordination)
- Gradual adoption path
- Easy rollback of individual services

**Cons**:
- Hybrid approach may be confusing
- Limited benefit compared to full Clan features
- Some architectural inconsistency

**Recommendation**: Most practical if partial benefits desired without full migration

### Scenario 4: No migration

**Approach**: Keep existing hosts on nixos-unified, use Clan only for remote hosts

**Pros**:
- Zero migration risk
- Proven stable configuration unchanged
- Clear separation: local (nixos-unified) vs. remote (Clan)
- Minimal learning curve

**Cons**:
- Dual management approaches
- Miss out on Clan benefits for local hosts
- Duplicate some shared configuration

**Recommendation**: Recommended default position pending Phase 1 evaluation

## Decision framework

### Migration makes sense if:

1. **Phase 1 demonstrates clear operational benefits**
   - Vars system significantly easier than current secret management
   - Multi-machine coordination valuable in practice
   - Clan CLI provides better workflow than current tools

2. **Darwin support is mature and stable**
   - Community adoption on darwin
   - Issues tracked and resolved promptly
   - Documentation covers darwin-specific patterns

3. **Migration effort justified by benefits**
   - Time saved in ongoing management > migration cost
   - Features needed (e.g., multi-machine services) unavailable otherwise
   - Team size or complexity justifies additional tooling

4. **Risk tolerance acceptable**
   - Comfortable with potential breakage during migration
   - Time available for troubleshooting
   - Can afford temporary productivity loss

### Migration should be deferred if:

1. **Phase 1 reveals issues**
   - Vars system more complex than expected
   - Clan abstractions confusing or limiting
   - Bugs or instabilities encountered

2. **Current setup working well**
   - No pain points in existing secret management
   - Limited need for multi-machine coordination
   - nixos-unified patterns well-understood and efficient

3. **Darwin support immature**
   - Few community examples on darwin
   - Known issues with darwin-specific features
   - Homebrew or GUI app integration unclear

4. **Limited time or risk tolerance**
   - Can't afford downtime on primary workstation
   - Other priorities more important
   - Prefer stability over new features

## Recommended decision timeline

**Month 0 (Now)**: Complete Phase 1, deploy first remote host
**Month 1-2**: Operate remote host, evaluate Clan workflows
**Month 3**: Decision point - assess Phase 1 experience

**At Month 3 decision point, evaluate**:
1. How often were Clan features valuable vs. friction points?
2. Are there specific use cases for local hosts that Clan would solve?
3. Has Clan darwin support matured?
4. What's the community adoption trajectory?
5. Is the team's Clan expertise sufficient for migration?

**If evaluation positive**: Plan partial migration (Scenario 2 or 3)
**If evaluation mixed**: Continue current approach, re-evaluate at Month 6
**If evaluation negative**: Keep Clan for remote only (Scenario 4)

## Pre-migration checklist (if proceeding)

Before migrating any existing host to Clan:

### Technical validation
- [ ] Phase 1 completed successfully
- [ ] At least 2-3 months operating Clan remote hosts
- [ ] No major issues or blockers encountered
- [ ] Clan darwin support validated (via community or test machine)
- [ ] Home-manager integration patterns established
- [ ] Secret migration path tested and validated

### Operational readiness
- [ ] Full backup of current configurations
- [ ] Rollback procedure documented and tested
- [ ] Time allocated for migration (minimum 1 week low-priority work)
- [ ] Acceptance of potential temporary instability

### Knowledge requirements
- [ ] Comfortable with Clan inventory system
- [ ] Understanding of Clan services vs. plain modules
- [ ] Vars system patterns internalized
- [ ] Troubleshooting experience from Phase 1

### Risk mitigation
- [ ] Secondary machine (blackphos) chosen for initial migration
- [ ] Primary machine (stibnite) kept stable as fallback
- [ ] Migration done during low-stakes period (not before major deadline)
- [ ] Peer review of migration plan (if team environment)

## Specific migration considerations per host

### Stibnite migration (if proceeding)

**High-risk areas**:
- Homebrew integration (clan-core may not support)
- macOS system preferences (darwin-specific)
- Touch ID authentication (pam configuration)
- GUI applications (homebrew casks)

**Recommended approach**:
1. Keep core system management in darwin configuration
2. Use Clan only for cross-machine services (if any)
3. Defer full migration until blackphos validated

**Alternative**: Hybrid approach
```nix
# darwin configuration still primary
darwinConfigurations.stibnite = {
  # Existing configuration
  # Selectively import Clan-managed services
  imports = [
    # Existing imports
    inputs.clan-core.darwinModules.vars # Just use vars system
  ];
};
```

### Blackphos migration (if proceeding)

**Advantages**:
- Secondary machine (lower risk)
- Similar to stibnite (patterns transfer)
- Can serve as testing ground

**Recommended approach**:
1. Full migration to Clan inventory
2. Validate all functionality
3. Document patterns and issues
4. Use learnings for potential stibnite migration

**Validation checklist**:
- [ ] All existing services functioning
- [ ] Homebrew working (or replacement found)
- [ ] System preferences applied correctly
- [ ] Development environment intact
- [ ] Secret management working
- [ ] Home-manager modules functioning
- [ ] No unexpected behaviors

## Conclusion

**Current recommendation**: **Scenario 4 (No migration of existing hosts)**

**Rationale**:
1. Current nixos-unified setup is working well
2. Limited multi-machine coordination needs between local hosts
3. Migration risk and effort not justified by clear benefits
4. Clan's primary value for this use case is remote host management
5. Can re-evaluate after Phase 1 experience

**Re-evaluation triggers**:
- Significant pain points emerge in current local host management
- New requirements for multi-machine coordination across local hosts
- Clan darwin support demonstrates clear maturity and community adoption
- Vars system proves dramatically superior to current secret management
- New Clan features emerge that address specific pain points

## Alternative: Selective feature adoption

Rather than full migration, consider adopting specific Clan features:

**Example 1: Vars system only**
```nix
darwinConfigurations.stibnite = {
  imports = [
    # Existing imports
    inputs.clan-core.darwinModules.vars
  ];

  # Use Clan vars generators for secrets
  clan.core.vars.generators.my-secret = {
    # ... generator definition
  };

  # Rest of configuration unchanged
};
```

**Example 2: Specific service modules**
```nix
darwinConfigurations.stibnite = {
  imports = [
    # Existing imports
    inputs.clan-core.clanServices.borgbackup.roles.client.perInstance.nixosModule
  ];

  # Use Clan's borgbackup client module but not full inventory
};
```

This hybrid approach may provide benefits without full migration overhead.

## Further reading

- Clan darwin support status: Check clan-core issues and discussions
- Community examples: Search for darwin configurations using Clan
- Migration stories: Clan community chat for others' experiences
- Phase 1 retrospective: `./phase-1-retrospective.md` (to be written after Phase 1)
