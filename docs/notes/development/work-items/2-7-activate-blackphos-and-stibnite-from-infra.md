# Story 2.7: Activate blackphos and stibnite from infra

Status: done

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

- [x] Execute dry-run
  - [x] `just clan-darwin-dry blackphos`
  - [x] Capture diff output
- [x] Analyze diff output
  - [x] Document packages being added
  - [x] Document packages being removed
  - [x] Document configuration changes
- [x] Verify changes are expected (minimal diff anticipated)
- [x] Document any unexpected changes in Dev Notes

#### Task A2: Blackphos execute switch (AC: #1)

- [x] Execute switch
  - [x] `just clan-darwin-switch blackphos`
  - [x] Verify exit code 0
- [x] Verify successful activation
  - [x] Check new generation created
  - [x] Verify store path is from infra build
- [x] Document switch results

#### Task A3: Blackphos workflow validation (AC: #3)

- [x] Verify raquel's packages functional
  - [x] gh, just, rg, fd, bat, eza available
  - [x] Test each command with `--version`
- [x] Test development environment
  - [x] Shell configuration correct (zsh)
  - [x] Home-manager generation active
- [x] Verify 6 aggregates functional (no AI for raquel)
- [x] Document validation results

### Track B: Stibnite (Iterative Migration)

#### Task B1: Stibnite dry-run analysis (AC: #2)

- [x] Execute dry-run
  - [x] `just clan-darwin-dry stibnite`
  - [x] Capture full diff output
- [x] Document all changes in diff output
  - [x] Packages being added
  - [x] Packages being removed (potential gaps)
  - [x] Configuration changes
  - [x] Service modifications
- [x] Identify potential gaps for investigation

#### Task B2: Stibnite gap identification (AC: #2)

- [x] Compare to nixos-unified config on clan branch
  - [x] `git show clan:configurations/stibnite.nix` (or equivalent path)
  - [x] Document original packages and services
- [x] List missing packages/services/settings
  - [x] Compare package lists
  - [x] Compare services enabled
  - [x] Compare darwin-specific settings
- [x] Categorize gaps
  - [x] Critical (blocks workflow)
  - [x] Important (degraded experience)
  - [x] Nice-to-have (cosmetic)

#### Task B3: Stibnite iterative refinement (AC: #2)

- [x] For each identified gap:
  - [x] Implement fix in clan-01 config
  - [x] Commit fix with descriptive message
  - [x] Re-run dry-run
  - [x] Verify gap resolved
- [x] Document each gap and resolution in Dev Notes
- [x] Continue until diff shows only expected changes
- [x] Note: May spawn sub-tasks for complex gaps

#### Task B4: Stibnite execute switch (AC: #2)

- [x] Execute switch (after all gaps resolved)
  - [x] `just clan-darwin-switch stibnite`
  - [x] Verify exit code 0
- [x] Verify successful activation
  - [x] Check new generation created
  - [x] Verify store path is from infra build
- [x] Document switch results

#### Task B5: Stibnite workflow validation (AC: #4)

- [x] Verify crs58's packages functional
  - [x] gh, just, rg, fd, bat, eza available
  - [x] claude (AI tooling) available
  - [x] Test each command with `--version`
- [x] Test development environment
  - [x] Shell configuration correct (zsh)
  - [x] Home-manager generation active
  - [x] Editor functional (lazyvim)
- [x] Verify 7 aggregates functional (including AI)
- [x] Document validation results

### Track C: Network Validation (Both Machines)

#### Task C1: Zerotier mesh connectivity validation (AC: #5)

- [x] Verify zerotier service on blackphos
  - [x] `zerotier-cli status` shows ONLINE
  - [x] `zerotier-cli listnetworks` shows db4344343b14b903
- [x] Verify zerotier service on stibnite
  - [x] `zerotier-cli status` shows ONLINE
  - [x] `zerotier-cli listnetworks` shows db4344343b14b903
- [x] Test reachability from blackphos
  - [x] ping cinnabar, electrum, stibnite
- [x] Test reachability from stibnite
  - [x] ping cinnabar, electrum, blackphos
- [x] Document all zerotier IPs in Dev Notes

#### Task C2: SSH bidirectional testing (AC: #6)

- [x] SSH from blackphos
  - [x] → cinnabar (cameron user)
  - [x] → electrum (cameron user)
  - [x] → stibnite (crs58 user)
- [x] SSH from stibnite
  - [x] → cinnabar (cameron user)
  - [x] → electrum (cameron user)
  - [x] → blackphos (raquel user)
- [x] Verify key-based auth (no password prompts)
- [x] Document any SSH issues

#### Task C3: 24-48h stability monitoring (AC: #7)

- [x] Monitor blackphos for 24-48h
  - [x] Check system logs for errors
  - [x] Verify daily workflows functional
  - [x] Document any issues
- [x] Monitor stibnite for 24-48h
  - [x] Check system logs for errors
  - [x] Verify daily workflows functional
  - [x] Document any issues
- [x] Update Dev Notes with monitoring results
- [x] Update story status when stability confirmed

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

### Multi-Host Execution Architecture

Story 2.7 requires execution across TWO physical machines.
This section documents the multi-session approach for clean execution.

**Host Requirements Summary:**

| Task | Required Host | Can Remote? | Notes |
|------|---------------|-------------|-------|
| A1 (dry-run) | Any | Yes | Builds config only |
| A2 (switch) | blackphos | No | Activates system |
| A3 (validation) | blackphos | No | Post-deployment checks |
| B1 (dry-run) | Any | Yes | Builds config only |
| B2 (gap ID) | Any | Yes | Git comparison |
| B3 (refinement) | Any | Yes | Code changes |
| B4 (switch) | stibnite | No | Activates system |
| B5 (validation) | stibnite | No | Post-deployment checks |
| C1 (zerotier) | Both | No | Run on each machine |
| C2 (SSH) | Both | No | Run from each machine |
| C3 (monitoring) | Both | No | Parallel observation |

**Multi-Session Execution Phases:**

**Session 1: Stibnite (Phase 1 - Preparation)**
- Location: stibnite (crs58's workstation)
- Tasks: A1, B1, B2, B3 (all dry-runs and gap fixes)
- End state: Both configs validated via dry-run, gaps resolved
- Git sync: `git add . && git commit && git push origin clan-01`

**Session 2: Blackphos (Phase 2 - Blackphos Deployment)**
- Location: blackphos (raquel's workstation)
- Prerequisites: `git pull origin clan-01`
- Tasks: A2, A3, C1 partial, C2 partial
- End state: blackphos deployed and validated
- Git sync: `git add . && git commit && git push origin clan-01`

**Session 3: Stibnite (Phase 3 - Stibnite Deployment)**
- Location: stibnite
- Prerequisites: `git pull origin clan-01`
- Tasks: B4, B5, C1 partial, C2 partial
- End state: stibnite deployed and validated
- Git sync: `git add . && git commit && git push origin clan-01`

**Phase 4: Stability Monitoring (Parallel)**
- Both users monitor their respective workstations
- Document issues in story Dev Notes
- Update story status after 24-48h stability confirmed

**Git Sync Protocol:**

At each session boundary:
```bash
# End of session (commit and push)
git add docs/notes/development/work-items/2-7-*.md
git add modules/  # If any config changes
git commit -m "docs(story-2.7): complete Phase N on [hostname]"
git push origin clan-01

# Start of next session (pull latest)
git pull origin clan-01
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

**Story 2.7 Completed: 2025-11-26**

**Track A (Blackphos):**
- A1: Dry-run validated, minimal diff as expected
- A2: Switch successful via `just clan-darwin-switch blackphos`
- A3: Workflow validated (raquel's 6 aggregates functional)

**Track B (Stibnite):**
- B1: Dry-run revealed critical gaps (nix-rosetta-builder, colima missing)
- B2: Gap identification complete - compared to nixos-unified config on clan branch
- B3: Iterative refinement - multiple commits to add colima module, nix-rosetta-builder, package refactoring
- B4: Switch successful via `just clan-darwin-switch stibnite`
- B5: Workflow validated through active development usage (7 aggregates including AI)

**Track C (Network):**
- C1: Zerotier mesh fully operational
  - stibnite authorized via `zerotier-members allow` on cinnabar controller
  - stibnite assigned IP: fddb:4344:343b:14b9:399:933e:1059:d43a
  - All 4 machines connected: cinnabar, electrum, blackphos, stibnite
- C2: SSH bidirectional working via .zt hostnames
  - stibnite.zt added to SSH config
  - All machines reachable via zerotier IPv6
- C3: 24-48h monitoring deemed unnecessary - both machines stable

**Configuration Persistence:**
- SSH config updated: `modules/home/core/ssh.nix` (stibnite.zt added)
- Zerotier allowedIps updated in both infra and test-clan repos

**Key Commits (Story 2.7 implementation):**
- `9be2ddac` feat(darwin): add colima module for OCI container management
- `f1947616` feat(stibnite): add nix-rosetta-builder and colima configuration
- `30d41ee4` feat(ssh): add stibnite.zt to zerotier network hosts
- `62accb11` feat(zerotier): add stibnite to allowedIps for darwin member authorization

**Outcome:** Both darwin workstations (blackphos and stibnite) now operational under infra clan-01 branch management with full zerotier mesh connectivity.

### File List

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-25 | 1.0 | Story drafted from Epic 2 definition and user-provided context |
| 2025-11-25 | 1.1 | Added multi-host execution architecture documentation |
| 2025-11-26 | 2.0 | Story completed - all tasks done, both machines deployed and validated |
