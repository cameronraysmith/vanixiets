# Story 2.7: Activate blackphos and stibnite from infra

Status: drafted

## Story

As a system administrator,
I want to deploy blackphos and stibnite from infra `clan-01` branch using the validated configurations,
So that both darwin workstations are operational under production infra management with full zerotier mesh connectivity.

## Context

**Epic 2 Phase 2 Final Story:**
This is the third and final story in Epic 2 Phase 2 (Active Darwin Workstations).
Story 2.5 validated blackphos configuration in infra.
Story 2.6 created stibnite configuration in infra.
Story 2.7 activates both workstations from infra, completing Phase 2.

**Story Type: HYBRID DEPLOYMENT (User-Executed with AI Validation):**
- User physically deploys to hardware machines
- AI assists with dry-run analysis, gap identification, and validation
- Iterative refinement expected for stibnite (first dendritic+clan deployment from infra)

**Two Deployment Profiles:**

1. **Blackphos (Straightforward Switch)**:
   - Currently running: test-clan dendritic+clan (Epic 1 Story 1.12)
   - Target: infra clan-01 dendritic+clan
   - Expected: Minimal diff (same architecture, minor augmentations like nix-managed SSH)
   - Approach: Dry-run → verify acceptable diff → switch

2. **Stibnite (Iterative Migration)**:
   - Currently running: infra clan branch (nixos-unified architecture)
   - Target: infra clan-01 branch (dendritic+clan)
   - Expected: Significant diff (architecture change, gaps likely)
   - Approach: Dry-run → analyze diff → identify gaps → implement fixes → repeat until acceptable → switch

**Deployment Commands:**
```bash
# Dry-run to preview changes (shows dix diff)
just clan-darwin-dry blackphos
just clan-darwin-dry stibnite

# Apply changes after dry-run validation
just clan-darwin-switch blackphos
just clan-darwin-switch stibnite

# Interactive mode (dry-run + prompt + switch)
just clan-darwin blackphos
just clan-darwin stibnite
```

## Acceptance Criteria

### AC1: Deploy blackphos from infra clan-01 branch

Deploy blackphos darwin configuration from infra repository, completing switch from test-clan management.

**Verification:**
```bash
# Execute deployment
just clan-darwin-switch blackphos

# Verify successful activation
darwin-rebuild --list-generations | head -5
# Expected: New generation activated from infra

# Verify darwin-rebuild switch completes
echo $?  # Exit code 0

# Verify new generation is from infra (check store path)
readlink /run/current-system
# Expected: /nix/store path from infra build
```

### AC2: Deploy stibnite from infra clan-01 branch

Deploy stibnite darwin configuration from infra repository, completing migration from nixos-unified to dendritic+clan.

**Verification:**
```bash
# Execute deployment
just clan-darwin-switch stibnite

# Verify successful activation
darwin-rebuild --list-generations | head -5
# Expected: New generation activated from infra

# Verify exit code
echo $?  # Exit code 0

# All gaps identified during dry-run analysis resolved
# Document any gaps and their resolutions in Dev Notes
```

### AC3: Validate raquel's workflow on blackphos

Verify raquel's development environment is fully functional with zero regressions from test-clan deployment.

**Verification:**
```bash
# Verify 270 packages functional (raquel)
which gh just rg fd bat eza
# Expected: All commands available

# Test development tools
gh --version
just --version
rg --version

# Verify shell configuration
echo $SHELL
# Expected: /run/current-system/sw/bin/zsh or similar

# Test home-manager integration
home-manager generations | head -3
# Expected: Active generation shown

# Verify raquel's 6 aggregates functional
# (core, development, packages, shell, terminal, tools - NO ai)
```

### AC4: Validate crs58's workflow on stibnite

Verify crs58's primary workstation is fully operational with all tools accessible.

**Verification:**
```bash
# Verify development tools
which gh just rg fd bat eza
# Expected: All commands available

# Verify AI tooling (crs58-specific)
which claude  # claude-code from nix-ai-tools
# Expected: Command available

# Test shell configuration
echo $SHELL
# Expected: zsh

# Test home-manager integration
home-manager generations | head -3
# Expected: Active generation shown

# Verify crs58's 7 aggregates functional
# (ai, core, development, packages, shell, terminal, tools)
```

### AC5: Confirm zerotier mesh VPN connectivity

Verify all machines are reachable via zerotier mesh VPN network.

**Verification:**
```bash
# Verify zerotier service running
zerotier-cli status
# Expected: 200 info ... ONLINE

# Verify network membership
zerotier-cli listnetworks
# Expected: db4344343b14b903 OK PUBLIC ...

# Test connectivity to all machines
# From blackphos:
ping -c 3 cinnabar.zerotier.ip
ping -c 3 electrum.zerotier.ip
ping -c 3 stibnite.zerotier.ip

# From stibnite:
ping -c 3 cinnabar.zerotier.ip
ping -c 3 electrum.zerotier.ip
ping -c 3 blackphos.zerotier.ip

# All 4 machines reachable: cinnabar, electrum, blackphos, stibnite
```

### AC6: Test SSH access

Verify bidirectional SSH access between all machines via zerotier network.

**Verification:**
```bash
# From blackphos:
ssh cameron@cinnabar.zerotier.ip "hostname"  # Expected: cinnabar
ssh cameron@electrum.zerotier.ip "hostname"  # Expected: electrum
ssh crs58@stibnite.zerotier.ip "hostname"    # Expected: stibnite

# From stibnite:
ssh cameron@cinnabar.zerotier.ip "hostname"  # Expected: cinnabar
ssh cameron@electrum.zerotier.ip "hostname"  # Expected: electrum
ssh raquel@blackphos.zerotier.ip "hostname"  # Expected: blackphos

# All SSH connections succeed without password prompt (SSH key auth)
```

### AC7: Monitor stability for 24-48 hours

Monitor both workstations for stability after deployment with no critical errors.

**Verification:**
```bash
# Check system logs for errors (after 24-48h)
log show --predicate 'eventType == logEvent AND logLevel >= 2' --last 24h | grep -i error | head -20
# Expected: No critical errors related to nix-darwin or home-manager

# Verify no regressions in daily workflows
# - Terminal emulator functional
# - Editor functional (lazyvim, vscode)
# - Git operations working
# - Development tools accessible

# Document any issues discovered in Dev Notes
```

## Tasks / Subtasks

### Track A: Blackphos (Straightforward Switch)

#### Task A1: Blackphos dry-run validation (AC: #1)

- [ ] Execute dry-run
  - [ ] `just clan-darwin-dry blackphos`
  - [ ] Capture diff output
- [ ] Analyze diff output
  - [ ] Document packages being added
  - [ ] Document packages being removed
  - [ ] Document configuration changes
- [ ] Verify changes are expected (minimal diff anticipated)
- [ ] Document any unexpected changes in Dev Notes

#### Task A2: Blackphos execute switch (AC: #1)

- [ ] Execute switch
  - [ ] `just clan-darwin-switch blackphos`
  - [ ] Verify exit code 0
- [ ] Verify successful activation
  - [ ] Check new generation created
  - [ ] Verify store path is from infra build
- [ ] Document switch results

#### Task A3: Blackphos workflow validation (AC: #3)

- [ ] Verify raquel's packages functional
  - [ ] gh, just, rg, fd, bat, eza available
  - [ ] Test each command with `--version`
- [ ] Test development environment
  - [ ] Shell configuration correct (zsh)
  - [ ] Home-manager generation active
- [ ] Verify 6 aggregates functional (no AI for raquel)
- [ ] Document validation results

### Track B: Stibnite (Iterative Migration)

#### Task B1: Stibnite dry-run analysis (AC: #2)

- [ ] Execute dry-run
  - [ ] `just clan-darwin-dry stibnite`
  - [ ] Capture full diff output
- [ ] Document all changes in diff output
  - [ ] Packages being added
  - [ ] Packages being removed (potential gaps)
  - [ ] Configuration changes
  - [ ] Service modifications
- [ ] Identify potential gaps for investigation

#### Task B2: Stibnite gap identification (AC: #2)

- [ ] Compare to nixos-unified config on clan branch
  - [ ] `git show clan:configurations/stibnite.nix` (or equivalent path)
  - [ ] Document original packages and services
- [ ] List missing packages/services/settings
  - [ ] Compare package lists
  - [ ] Compare services enabled
  - [ ] Compare darwin-specific settings
- [ ] Categorize gaps
  - [ ] Critical (blocks workflow)
  - [ ] Important (degraded experience)
  - [ ] Nice-to-have (cosmetic)

#### Task B3: Stibnite iterative refinement (AC: #2)

- [ ] For each identified gap:
  - [ ] Implement fix in clan-01 config
  - [ ] Commit fix with descriptive message
  - [ ] Re-run dry-run
  - [ ] Verify gap resolved
- [ ] Document each gap and resolution in Dev Notes
- [ ] Continue until diff shows only expected changes
- [ ] Note: May spawn sub-tasks for complex gaps

#### Task B4: Stibnite execute switch (AC: #2)

- [ ] Execute switch (after all gaps resolved)
  - [ ] `just clan-darwin-switch stibnite`
  - [ ] Verify exit code 0
- [ ] Verify successful activation
  - [ ] Check new generation created
  - [ ] Verify store path is from infra build
- [ ] Document switch results

#### Task B5: Stibnite workflow validation (AC: #4)

- [ ] Verify crs58's packages functional
  - [ ] gh, just, rg, fd, bat, eza available
  - [ ] claude (AI tooling) available
  - [ ] Test each command with `--version`
- [ ] Test development environment
  - [ ] Shell configuration correct (zsh)
  - [ ] Home-manager generation active
  - [ ] Editor functional (lazyvim)
- [ ] Verify 7 aggregates functional (including AI)
- [ ] Document validation results

### Track C: Network Validation (Both Machines)

#### Task C1: Zerotier mesh connectivity validation (AC: #5)

- [ ] Verify zerotier service on blackphos
  - [ ] `zerotier-cli status` shows ONLINE
  - [ ] `zerotier-cli listnetworks` shows db4344343b14b903
- [ ] Verify zerotier service on stibnite
  - [ ] `zerotier-cli status` shows ONLINE
  - [ ] `zerotier-cli listnetworks` shows db4344343b14b903
- [ ] Test reachability from blackphos
  - [ ] ping cinnabar, electrum, stibnite
- [ ] Test reachability from stibnite
  - [ ] ping cinnabar, electrum, blackphos
- [ ] Document all zerotier IPs in Dev Notes

#### Task C2: SSH bidirectional testing (AC: #6)

- [ ] SSH from blackphos
  - [ ] → cinnabar (cameron user)
  - [ ] → electrum (cameron user)
  - [ ] → stibnite (crs58 user)
- [ ] SSH from stibnite
  - [ ] → cinnabar (cameron user)
  - [ ] → electrum (cameron user)
  - [ ] → blackphos (raquel user)
- [ ] Verify key-based auth (no password prompts)
- [ ] Document any SSH issues

#### Task C3: 24-48h stability monitoring (AC: #7)

- [ ] Monitor blackphos for 24-48h
  - [ ] Check system logs for errors
  - [ ] Verify daily workflows functional
  - [ ] Document any issues
- [ ] Monitor stibnite for 24-48h
  - [ ] Check system logs for errors
  - [ ] Verify daily workflows functional
  - [ ] Document any issues
- [ ] Update Dev Notes with monitoring results
- [ ] Update story status when stability confirmed

## Dev Notes

### Learnings from Previous Story

**From Story 2.6 (Status: done)**

- **Implementation Complete**: Stibnite darwin config created (182 lines vs blackphos 217)
- **Single-User Pattern**: crs58 only (no raquel) - simpler than blackphos
- **7 Aggregates Configured**: ai, core, development, packages, shell, terminal, tools
- **Zerotier Ready**: Network db4344343b14b903 configured, _zerotier.nix copied from blackphos
- **Darwin Features**: TouchID, MaxAuthTries 20, zsh, documentation enabled
- **Clan Registration**: stibnite in machines.nix and inventory/machines.nix
- **Build Validation**: Darwin system builds successfully
- **Story 2.7 Handoff Guidance**: Both machines ready, join order blackphos first then stibnite

[Source: docs/notes/development/work-items/2-6-stibnite-config-migration.md#Dev-Agent-Record]

### Deployment Methodology

**Justfile Recipes (clan group):**

| Recipe | Command | Description |
|--------|---------|-------------|
| `clan-darwin-dry` | `nix run .#darwin -- {host} . --dry` | Preview changes (dix diff) |
| `clan-darwin-switch` | `nix run .#darwin -- {host} .` | Apply changes |
| `clan-darwin` | dry + prompt + switch | Interactive mode |

**Alternative Direct Commands:**
```bash
# nh darwin with dix diff
nix run .#darwin -- blackphos . --dry
nix run .#darwin -- blackphos .

# Traditional darwin-rebuild
darwin-rebuild switch --flake .#blackphos
darwin-rebuild switch --flake .#stibnite
```

### Gap Analysis Workflow (for stibnite)

When dry-run reveals unexpected changes:

1. **Inspect diff**: Note packages being removed or changed
2. **Compare configs**:
   ```bash
   # View current nixos-unified config
   git show clan:configurations/stibnite.nix  # or configurations/darwin/stibnite.nix

   # Compare to new dendritic+clan config
   cat modules/machines/darwin/stibnite/default.nix
   ```
3. **Document gap**: Add to Dev Notes with description
4. **Implement fix**: Update clan-01 config
5. **Verify fix**: Re-run `just clan-darwin-dry stibnite`
6. **Repeat** until diff shows only expected changes

### Rollback Strategy

**Blackphos Rollback (to test-clan):**
```bash
cd ~/projects/nix-workspace/test-clan
just clan-darwin-switch blackphos
# Or: darwin-rebuild switch --flake .#blackphos
```

**Stibnite Rollback (to nixos-unified):**
```bash
cd ~/projects/nix-workspace/infra
git checkout clan
darwin-rebuild switch --flake .#stibnite
```

### Project Structure Notes

**Deployment Target Configs:**
```
modules/machines/darwin/blackphos/
├── default.nix        # 217 lines - dual-user darwin config
└── _zerotier.nix      # 100 lines - zerotier activation script

modules/machines/darwin/stibnite/
├── default.nix        # 182 lines - single-user darwin config
└── _zerotier.nix      # 100 lines - zerotier activation script
```

**Key Files:**
- Justfile: lines 327-403 (clan group recipes)
- Zerotier Network ID: db4344343b14b903

### Zerotier Network Details

| Machine | Role | Platform | Expected IP |
|---------|------|----------|-------------|
| cinnabar | Controller | NixOS VPS | (from zerotier-cli) |
| electrum | Peer | NixOS VPS | (from zerotier-cli) |
| blackphos | Peer | Darwin | (from zerotier-cli) |
| stibnite | Peer | Darwin | (from zerotier-cli) |

### References

**Source Documentation:**
- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md) - Story 2.7 definition (lines 178-194)
- [Architecture - Deployment](docs/notes/development/architecture/deployment-architecture.md) - Deployment commands

**Predecessor Stories:**
- [Story 2.5](docs/notes/development/work-items/2-5-blackphos-config-migration-to-infra.md) - Blackphos validation (provides deployment readiness)
- [Story 2.6](docs/notes/development/work-items/2-6-stibnite-config-migration.md) - Stibnite config creation (provides deployment readiness)

**Epic 1 References:**
- [Story 1.12](docs/notes/development/work-items/1-12-deploy-blackphos-zerotier-integration.md) - Original blackphos zerotier deployment (test-clan)

**Successor Stories:**
- Story 2.8 (backlog) - Cleanup unused darwin configs

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

### Completion Notes List

### File List

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-25 | 1.0 | Story drafted from Epic 2 definition and user-provided context |
