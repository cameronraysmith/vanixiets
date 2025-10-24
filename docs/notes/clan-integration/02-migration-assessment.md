# Migration validation guide: dendritic + clan host-by-host assessment

This document provides validation criteria and assessment guidelines for the progressive darwin host migration from nixos-unified to dendritic + clan.
Use this guide to evaluate readiness for each migration phase and validate successful migration.

## Migration strategy overview

**Approach**: Progressive host-by-host migration with validation gates

**Order**: blackphos → rosegold → argentum → stibnite

**Rationale**:
1. **blackphos**: Already activated, not primary workstation (lowest risk, establishes patterns)
2. **rosegold**: Not in daily use, enables multi-machine testing (validates zerotier coordination)
3. **argentum**: Not in daily use, final validation before primary (confirms pattern stability)
4. **stibnite**: Primary workstation, migrate last (highest value, highest risk, requires proven patterns)

**Key principle**: Each host must be stable for 1-2 weeks before migrating the next host.

## Host analysis

### blackphos (Phase 1: foundation)

**Current state**:
- Platform: aarch64-darwin (Apple Silicon Mac)
- Management: nix-darwin + home-manager via nixos-unified
- Configuration: `configurations/darwin/blackphos.nix`
- Status: Already has nix-config activated, not primary workstation
- Usage: Secondary development environment

**Migration characteristics**:
- **Risk level**: Low (not primary workstation, can tolerate temporary instability)
- **Migration priority**: First (establishes all patterns for subsequent hosts)
- **Strategic value**: Proves dendritic + clan works on darwin, creates reusable patterns
- **Rollback ease**: High (can rebuild from nixos-unified configurations if needed)

**Success criteria**:
- [ ] Dendritic module structure created and operational
- [ ] All existing functionality preserved
- [ ] Clan inventory and vars system functional
- [ ] Zerotier controller role operational
- [ ] No regressions in daily development workflow
- [ ] Stable for 1-2 weeks before proceeding to rosegold

**Red flags requiring investigation**:
- Build failures or evaluation errors
- Missing functionality compared to nixos-unified version
- Clan vars not deploying correctly
- Zerotier network issues
- Unexpected system behavior

### rosegold (Phase 2: multi-machine validation)

**Current state**:
- Platform: aarch64-darwin (Apple Silicon Mac)
- Management: nix-darwin + home-manager via nixos-unified
- Configuration: `configurations/darwin/rosegold.nix`
- Status: Not currently in daily use
- Usage: Testing and experimental environment

**Migration characteristics**:
- **Risk level**: Low (not in daily use, experimental machine)
- **Migration priority**: Second (validates zerotier multi-machine coordination)
- **Strategic value**: Proves blackphos patterns are reusable, tests clan multi-machine features
- **Rollback ease**: High (not critical system)

**Success criteria**:
- [ ] rosegold configuration builds using blackphos patterns
- [ ] Zerotier peer role connects to blackphos controller
- [ ] blackphos ↔ rosegold network communication functional
- [ ] All home-manager modules work identically to blackphos
- [ ] Patterns confirmed as reusable (minimal customization needed)
- [ ] Stable for 1-2 weeks before proceeding to argentum

**Multi-machine validation tests**:
```bash
# On blackphos (controller)
zerotier-cli listnetworks
zerotier-cli listpeers

# On rosegold (peer)
zerotier-cli status
zerotier-cli listnetworks

# Test connectivity
# From blackphos:
ping <rosegold-zerotier-ip>
ssh crs58@<rosegold-zerotier-ip>

# From rosegold:
ping <blackphos-zerotier-ip>
ssh crs58@<blackphos-zerotier-ip>
```

**Red flags requiring investigation**:
- Pattern modifications needed (indicates blackphos patterns not generic)
- Zerotier peer connection failures
- Network connectivity issues between hosts
- Inconsistent behavior compared to blackphos

### argentum (Phase 3: final validation)

**Current state**:
- Platform: aarch64-darwin (Apple Silicon Mac)
- Management: nix-darwin + home-manager via nixos-unified
- Configuration: `configurations/darwin/argentum.nix`
- Status: Not currently in daily use
- Usage: Testing and backup environment

**Migration characteristics**:
- **Risk level**: Low (not in daily use)
- **Migration priority**: Third (final validation before primary workstation)
- **Strategic value**: Confirms patterns scale to three machines, validates 3-machine zerotier network
- **Rollback ease**: High (not critical system)

**Success criteria**:
- [ ] argentum configuration builds using established patterns
- [ ] Zerotier peer role connects to blackphos controller
- [ ] 3-machine network operational (blackphos ↔ rosegold ↔ argentum)
- [ ] No new issues discovered (patterns proven stable)
- [ ] Stable for 1-2 weeks before considering stibnite migration

**3-machine validation tests**:
```bash
# Verify all machines see each other
# On blackphos:
zerotier-cli listpeers | grep -E '(rosegold|argentum)'

# Test full mesh connectivity
# From each machine:
ping <blackphos-zerotier-ip>
ping <rosegold-zerotier-ip>
ping <argentum-zerotier-ip>
```

**Red flags requiring investigation**:
- New issues not seen with blackphos or rosegold
- Zerotier network instability with 3+ peers
- Performance degradation
- Pattern inconsistencies

### stibnite (Phase 4: primary workstation)

**Current state**:
- Platform: aarch64-darwin (Apple Silicon Mac)
- Management: nix-darwin + home-manager via nixos-unified
- Configuration: `configurations/darwin/stibnite.nix`
- Status: Primary daily workstation
- Usage: Primary development environment, daily workflows

**Migration characteristics**:
- **Risk level**: High (primary workstation, daily productivity depends on it)
- **Migration priority**: Last (only after all others proven stable)
- **Strategic value**: Completes migration, enables full 4-machine coordination
- **Rollback ease**: Medium (critical to preserve rollback path)

**Pre-migration requirements**:
- [ ] blackphos stable for 4-6 weeks minimum
- [ ] rosegold stable for 2-4 weeks minimum
- [ ] argentum stable for 2-4 weeks minimum
- [ ] No outstanding issues with dendritic + clan pattern
- [ ] All workflows validated on other hosts
- [ ] Full backup of current stibnite configuration
- [ ] Rollback procedure documented and tested
- [ ] Low-stakes timing (not before important deadline)

**Success criteria**:
- [ ] stibnite configuration builds using established patterns
- [ ] All daily workflows functional (development, communication, etc.)
- [ ] No regressions compared to nixos-unified version
- [ ] Zerotier peer role operational
- [ ] 4-machine network complete and stable
- [ ] Productivity maintained or improved

**High-risk areas for stibnite**:
- Complex darwin-specific configurations
- Daily-use applications and workflows
- Homebrew casks and GUI applications
- System preferences and integrations
- Performance-sensitive workloads

**Rollback procedure**:
1. Boot into recovery mode if necessary
2. Rebuild from nixos-unified configuration: `darwin-rebuild switch --flake .#stibnite-nixos-unified`
3. Verify all functionality restored
4. Document issues for future migration attempt

## Migration validation scenarios

### Scenario 1: blackphos migration validation

**Context**: First migration, establishes all patterns

**Validation focus**:
- Dendritic module structure works on darwin
- import-tree auto-discovery functional
- Clan inventory correctly defines darwin machines
- Clan vars generate and deploy successfully
- Zerotier controller role operational
- All existing functionality preserved

**Test procedure**:
1. **Pre-migration baseline**:
   ```bash
   # Document current functionality
   darwin-rebuild --version
   # Test all critical workflows
   # Document current packages: darwin-rebuild list
   ```

2. **Post-migration verification**:
   ```bash
   # Verify dendritic configuration
   nix eval .#flake.modules.darwin --apply builtins.attrNames

   # Verify host configuration
   nix build .#darwinConfigurations.blackphos.system

   # Verify clan integration
   nix eval .#clan.inventory.machines.blackphos --json

   # Verify vars deployed
   ls -la /run/secrets/

   # Verify zerotier
   zerotier-cli status
   zerotier-cli listnetworks
   ```

3. **Functionality comparison**:
   - Compare package lists: before vs. after
   - Test all development tools (git, editors, languages)
   - Verify shell configuration (fish, aliases, functions)
   - Test system services
   - Validate performance (build times, responsiveness)

4. **Stability monitoring** (1-2 weeks):
   - Daily: Check for errors in system logs
   - Weekly: Run full test suite
   - Document any issues or regressions

**Success gate**: All validation tests pass, no critical issues for 1-2 weeks → Proceed to rosegold

**Failure response**: Investigate issues, fix patterns, repeat validation

### Scenario 2: rosegold multi-machine validation

**Context**: Second migration, validates pattern reusability and multi-machine coordination

**Validation focus**:
- blackphos patterns reusable with minimal changes
- Zerotier multi-machine coordination works
- Network communication between hosts functional
- No new dendritic + clan issues discovered

**Test procedure**:
1. **Pattern reuse validation**:
   ```bash
   # Compare module structures
   diff -u modules/hosts/blackphos/default.nix modules/hosts/rosegold/default.nix

   # Expect only hostName differences
   ```

2. **Multi-machine coordination**:
   ```bash
   # From blackphos (controller):
   zerotier-cli listpeers | grep rosegold
   ping <rosegold-zerotier-ip>
   ssh crs58@<rosegold-zerotier-ip> hostname

   # From rosegold (peer):
   zerotier-cli listnetworks
   ping <blackphos-zerotier-ip>
   ssh crs58@<blackphos-zerotier-ip> hostname
   ```

3. **Cluster services testing**:
   - Test clan vars sharing between hosts
   - Verify clan inventory correctly applies services to both hosts
   - Test any distributed services (if configured)

4. **Stability monitoring** (1-2 weeks):
   - Daily: Check both hosts for errors
   - Weekly: Test multi-machine coordination
   - Document network stability

**Success gate**: rosegold stable, multi-machine features functional for 1-2 weeks → Proceed to argentum

**Failure response**: Fix multi-machine issues, update patterns if needed, repeat validation

### Scenario 3: argentum final validation

**Context**: Third migration, final validation before primary workstation

**Validation focus**:
- Patterns scale to three machines
- No new issues with additional host
- 3-machine network stable
- Ready for primary workstation migration

**Test procedure**:
1. **Third host validation**:
   ```bash
   # Verify argentum uses same patterns
   diff -u modules/hosts/rosegold/default.nix modules/hosts/argentum/default.nix

   # Build and deploy
   nix build .#darwinConfigurations.argentum.system
   darwin-rebuild switch --flake .#argentum
   ```

2. **3-machine network validation**:
   ```bash
   # From blackphos (controller):
   zerotier-cli listpeers | wc -l  # Should show 3+ peers

   # Full mesh connectivity test
   # From each machine, ping all others:
   for host in blackphos rosegold argentum; do
     ping -c 3 <$host-zerotier-ip>
   done
   ```

3. **Pattern stability confirmation**:
   - No modifications needed to existing patterns
   - argentum configuration nearly identical to rosegold (only hostName differs)
   - All three hosts stable and functional

4. **Stability monitoring** (1-2 weeks):
   - Daily: Check all three hosts
   - Weekly: Test full mesh network
   - Document any new issues

**Success gate**: All three hosts stable for 1-2 weeks, no new issues → stibnite migration approved

**Failure response**: Address any issues before considering stibnite migration

### Scenario 4: stibnite migration readiness

**Context**: Final migration of primary workstation

**Validation focus**:
- All previous hosts proven stable long-term
- Patterns mature and well-understood
- Risk mitigation in place
- Rollback plan ready

**Readiness checklist**:
- [ ] blackphos stable for 4-6+ weeks
- [ ] rosegold stable for 2-4+ weeks
- [ ] argentum stable for 2-4+ weeks
- [ ] No outstanding bugs or issues
- [ ] All workflows tested on other hosts
- [ ] Backup of current stibnite config created
- [ ] Rollback procedure documented
- [ ] Time available for troubleshooting (not before deadline)
- [ ] Acceptance of temporary instability if issues arise

**Test procedure**:
1. **Pre-migration preparation**:
   ```bash
   # Full backup
   darwin-rebuild list > ~/stibnite-packages-backup.txt
   cp -r ~/projects/nix-workspace/nix-config ~/nix-config-backup-$(date +%Y%m%d)

   # Document current state
   # List all running services, applications, workflows
   ```

2. **Staged migration**:
   - Deploy dendritic config but don't reboot immediately
   - Test critical workflows before committing
   - Keep terminal session open with rollback command ready

3. **Post-migration critical path validation**:
   - Test all daily-use applications immediately
   - Verify development environment (editors, languages, tools)
   - Check system preferences and settings
   - Test network connectivity (including zerotier to other hosts)
   - Validate performance

4. **Extended validation** (1-2 weeks):
   - Use stibnite as primary workstation
   - Document any issues or regressions
   - Compare productivity to pre-migration baseline

**Success gate**: stibnite stable and functional for 1-2 weeks → Migration complete, proceed to cleanup

**Failure response**: Use rollback procedure, document issues, reassess dendritic + clan approach

## Decision framework

### When to proceed to next phase

Proceed to next migration phase when:
1. **Current phase success criteria met**: All checklist items complete
2. **Stability demonstrated**: No critical issues for 1-2 weeks minimum
3. **Confidence high**: Understand any issues encountered and have fixes
4. **Time available**: Can dedicate time to next migration and potential troubleshooting

### When to pause or rollback

Pause or rollback if:
1. **Critical functionality broken**: Essential workflows don't work
2. **Frequent instability**: System crashes, errors, or unexpected behavior
3. **Unknown issues**: Problems without clear cause or fix
4. **Time constraints**: Important deadline approaching, can't afford disruption
5. **Accumulating technical debt**: Workarounds piling up instead of proper fixes

### Red flags requiring investigation

Stop and investigate if:
- Build evaluation errors
- Missing packages or functionality
- Clan vars not deploying
- Zerotier network issues
- Performance degradation
- Unexpected system behavior
- Errors in system logs
- Functionality regressions
- Pattern inconsistencies between hosts

### Success indicators

Migration is successful when:
- All hosts build cleanly
- No functionality regressions
- Zerotier multi-machine network operational
- Clan vars system working correctly
- Stable for extended period (weeks)
- Productivity maintained or improved
- Patterns clear and maintainable
- Confidence high in dendritic + clan approach

## Host-specific considerations

### blackphos-specific

**Key testing areas**:
- Development environment (primary use case)
- Git workflows
- Shell configuration (fish, starship)
- Editor/IDE setup
- Zerotier controller functionality

**Watch for**:
- Zerotier controller port conflicts
- Development tool version changes
- Shell behavior differences
- Editor plugin issues

### rosegold-specific

**Key testing areas**:
- Zerotier peer role (connecting to blackphos controller)
- Multi-machine network communication
- Pattern reusability validation

**Watch for**:
- Zerotier peer connection failures
- Network routing issues
- Differences from blackphos requiring pattern changes

### argentum-specific

**Key testing areas**:
- Third machine in zerotier network
- Pattern stability with multiple hosts
- Mesh network connectivity

**Watch for**:
- Network performance with 3+ hosts
- Zerotier scaling issues
- Any new problems not seen with 2 hosts

### stibnite-specific

**Key testing areas**:
- All daily workflows (highest priority)
- Complex darwin configurations
- GUI applications and system preferences
- Performance-sensitive workloads
- Homebrew casks
- Development environment completeness

**Watch for**:
- Homebrew integration issues
- macOS-specific features broken
- Performance regressions
- Daily workflow disruptions
- GUI application problems

**Critical workflows to validate immediately**:
1. Editor/IDE (VSCode, Vim, etc.)
2. Terminal and shell
3. Git and version control
4. Programming language environments
5. Communication apps (if configured via nix)
6. Browser (if configured via nix)
7. System services

## Recommended timeline

**Conservative approach** (recommended):
- **Week 0**: Migrate blackphos
- **Weeks 1-2**: Monitor blackphos stability
- **Week 3**: Migrate rosegold (if blackphos stable)
- **Weeks 4-5**: Monitor rosegold and multi-machine features
- **Week 6**: Migrate argentum (if rosegold stable)
- **Weeks 7-8**: Monitor argentum and 3-machine network
- **Week 9+**: Consider stibnite migration (if all stable)
- **Weeks 10-11**: Monitor stibnite
- **Week 12+**: Cleanup phase (remove nixos-unified)

**Aggressive approach** (higher risk):
- **Week 0**: Migrate blackphos
- **Week 1**: Migrate rosegold (if blackphos functional)
- **Week 2**: Migrate argentum (if rosegold functional)
- **Week 3+**: Consider stibnite (if all functional)

**Recommended**: Conservative approach with flexibility to slow down or pause if issues arise

## Rollback procedures

### Per-host rollback

If a single host migration fails:

```bash
# Rebuild from nixos-unified configuration
# Ensure nixos-unified configurations preserved during migration
darwin-rebuild switch --flake .#<hostname>-nixos-unified

# Or manually:
git checkout <pre-migration-commit>
darwin-rebuild switch --flake .#<hostname>
```

### Full migration rollback

If dendritic + clan approach proves unsuitable:

1. **Preserve nixos-unified configurations** during migration (don't delete)
2. **Rebuild each host** from nixos-unified configs
3. **Remove dendritic modules**: `rm -rf modules/` (after backup)
4. **Remove clan flake inputs**: Edit `flake.nix`
5. **Document reasons** for rollback decision

## Conclusion

**Key principles**:
1. **Progressive migration**: One host at a time, validate before proceeding
2. **Stability first**: Wait 1-2 weeks stability before next phase
3. **Learn from each phase**: Use each migration to refine patterns
4. **Primary last**: Migrate stibnite only after all others proven stable
5. **Preserve rollback**: Keep nixos-unified configs until migration complete

**Success depends on**:
- Careful validation at each phase
- Stability monitoring between phases
- Willingness to pause or rollback if issues arise
- Time for troubleshooting and refinement

**Expected outcome**: After 8-12 weeks, all hosts migrated to dendritic + clan with proven stable patterns, ready for Phase 5 cleanup.
