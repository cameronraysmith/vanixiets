# Story 2.9: Cinnabar config migration

Status: done

## Story

As a system administrator,
I want to switch cinnabar VPS deployment source from test-clan to infra clan-01 branch,
so that cinnabar is managed from production infra repository while maintaining zerotier controller functionality.

## Context

**Epic 2 Phase 3 Story 1 (VPS Migration):**
This is the first story in Epic 2 Phase 3 (VPS Migration). Story 2.7 activated darwin workstations (blackphos, stibnite) from infra. Story 2.8 confirmed no obsolete darwin configs require cleanup. Story 2.9 switches cinnabar deployment to infra, completing the first VPS migration.

**Story Type: DEPLOYMENT (Switch Deployment Source):**
- cinnabar NixOS config ALREADY EXISTS in infra (migrated in Story 2.3)
- Currently DEPLOYED from test-clan
- Must switch to deploying from infra clan-01 branch
- Pattern parallels Story 2.7 (darwin activation) but for remote NixOS VPS

**Execution Model: HYBRID (User-Interactive with AI Assistance)**

Similar to Story 2.7, this story involves:
- **[AI]** tasks: Build validation, file review, vars commands, documentation
- **[USER]** tasks: SSH sessions, interactive dry-run diffs, cross-machine validation
- **[HYBRID]** tasks: AI executes deployment, user monitors output

Some commands (SSH into cinnabar, nh dix diff review, cross-machine ping tests) are difficult for Claude Code to execute and capture feedback from. These should be executed by the developer with results reported back to the chat thread for AI analysis.

**CRITICAL CONTEXT: CINNABAR IS THE ZEROTIER CONTROLLER:**

cinnabar serves as the zerotier network controller for network db4344343b14b903.
If deployment breaks networking, ALL mesh connectivity is lost (blackphos, stibnite, electrum).
This is a HIGH-RISK deployment requiring careful validation at each step.

**Deployment Commands (Clan CLI - PREFERRED for NixOS VPS):**
```bash
# Clan CLI - canonical approach for clan-managed NixOS VPS
# Handles: config deployment + vars/secrets to /run/secrets/
clan machines update cinnabar

# Pre-deployment: regenerate vars if generators changed
clan vars generate cinnabar

# Check current vars
clan vars list cinnabar
```

**Alternative (Flake App - nh os switch wrapper):**
```bash
# Preview changes via nh os switch (nixos-rebuild style diff)
just clan-os-dry cinnabar   # → nix run .#os -- cinnabar . --dry

# Apply via nh os switch (nixos-rebuild style deployment)
just clan-os-switch cinnabar  # → nix run .#os -- cinnabar .
```

**When to use which:**
- **`clan machines update`**: Preferred for VPS - handles vars deployment, clan service coordination
- **`just clan-os-*`**: Alternative if you only need config rebuild without vars regeneration

## Acceptance Criteria

### AC1: Verify cinnabar configuration in infra builds

Verify the cinnabar NixOS configuration builds successfully from infra repository.

**Verification:**
```bash
# Build nixos toplevel
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Verify build completes
echo $?  # Exit code 0

# Verify store path created
readlink result
# Expected: /nix/store path for cinnabar system
```

### AC2: Preserve zerotier controller configuration

Ensure zerotier controller configuration is preserved after switching deployment source.

**Verification:**
```bash
# Verify zerotier config in infra
cat modules/clan/inventory/services/zerotier.nix
# Expected: roles.controller.machines."cinnabar" with allowedIps for blackphos + stibnite

# Verify network ID preserved
grep "db4344343b14b903" modules/clan/inventory/services/zerotier.nix || \
  grep -r "zerotier" modules/machines/nixos/cinnabar/
# Expected: Network ID referenced in configuration

# After deployment - verify controller operational
ssh cameron@cinnabar.zt "zerotier-cli info"
# Expected: 200 info ... ONLINE

ssh cameron@cinnabar.zt "zerotier-cli listnetworks"
# Expected: db4344343b14b903 with controller status
```

### AC3: Deploy cinnabar from infra

Execute deployment from infra clan-01 branch successfully using clan CLI.

**Verification:**
```bash
# Execute deployment via clan CLI (preferred for VPS)
clan machines update cinnabar

# Verify exit code
echo $?  # Exit code 0

# Verify new system generation
ssh cameron@cinnabar.zt "nixos-rebuild list-generations | head -5"
# Expected: New generation from infra deployment

# Verify vars were deployed
ssh cameron@cinnabar.zt "ls -la /run/secrets/"
# Expected: Secrets present from clan vars
```

### AC4: Validate SSH access from darwin workstations

Verify SSH access via both zerotier and public IP.

**Verification:**
```bash
# Test zerotier access
ssh cameron@cinnabar.zt "hostname"
# Expected: cinnabar

# Test public IP fallback
ssh cameron@49.13.68.78 "hostname"
# Expected: cinnabar

# Test from blackphos
ssh cameron@cinnabar.zt "hostname"

# Test from stibnite
ssh cameron@cinnabar.zt "hostname"
```

### AC5: Validate clan vars deployment

Verify clan vars are properly deployed to /run/secrets/.

**Verification:**
```bash
# Check secrets directory exists
ssh cameron@cinnabar.zt "ls -la /run/secrets/"
# Expected: Directory exists with secrets

# Check permissions
ssh cameron@cinnabar.zt "stat -c '%a %U:%G' /run/secrets"
# Expected: Appropriate permissions

# Verify SSH keys deployed
ssh cameron@cinnabar.zt "ls -la /run/secrets/ | grep -i ssh"
# Expected: SSH-related secrets present
```

### AC6: Test zerotier controller status

Verify zerotier controller is fully operational after deployment.

**Verification:**
```bash
# Verify controller status
ssh cameron@cinnabar.zt "zerotier-cli info"
# Expected: 200 info ... ONLINE

# List network members
ssh cameron@cinnabar.zt "zerotier-cli listnetworks"
# Expected: db4344343b14b903 OK PUBLIC

# Verify peers still connected
# From blackphos:
ping -c 3 cinnabar.zt
ping -c 3 electrum.zt
ping -c 3 stibnite.zt

# From stibnite:
ping -c 3 cinnabar.zt
ping -c 3 electrum.zt
ping -c 3 blackphos.zt
```

### AC7: Document cinnabar-specific infrastructure

Document cinnabar infrastructure details for future reference.

**Verification:**
- [ ] Hetzner Cloud CX43 specs documented (8 vCPU, 16GB RAM, fsn1 location)
- [ ] ZFS disk layout documented (disko.nix)
- [ ] Network configuration documented (systemd-networkd)
- [ ] Recovery procedures documented
- [ ] Story 2.10 handoff guidance documented

## Tasks / Subtasks

**Execution Mode Legend:**
- **[AI]** - Can be executed directly by Claude Code
- **[USER]** - Should be executed by human developer, report results back to chat
- **[HYBRID]** - AI prepares/validates, user executes interactive portions

Some tasks involve SSH sessions, interactive diffs, or commands that span multiple hops.
These are marked [USER] and should be executed by the developer with output shared in the chat thread for AI analysis.

---

### Task 1: Build Validation (AC: #1) [AI]

- [x] Build cinnabar config from infra
  - [x] `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
  - [x] Verify build succeeds
  - [x] Document store path: `/nix/store/qwy236vajvwdvaafz0xnmw5ga8k10pc8-nixos-system-cinnabar-25.11.20251115.1d4c883`
- [x] Compare with test-clan config for drift
  - [x] Check key configurations match
  - [x] Note any differences in Dev Notes

### Task 2: Clan Vars/Secrets Verification (AC: #2, #5) [AI]

- [x] Audit clan inventory services
  - [x] Review modules/clan/inventory/services/zerotier.nix
  - [x] Review modules/clan/inventory/services/users/cameron.nix
  - [x] Review modules/clan/inventory/services/sshd.nix
- [x] Verify user-cameron service instance
  - [x] Check cinnabar is targeted
  - [x] Verify cameron user configuration
- [x] Verify zerotier controller configuration
  - [x] Network ID db4344343b14b903 (confirmed via `clan vars list cinnabar`)
  - [x] allowedIps includes blackphos + stibnite

### Task 3: Pre-Deployment Checklist (AC: #4) [USER]

**User executes these SSH commands and reports current state to chat.**

- [x] Confirm SSH access via public IP (fallback)
  - [x] `ssh cameron@49.13.68.78 "hostname"` → cinnabar
  - [x] Document current IP: 49.13.68.78
- [x] Note current zerotier status
  - [x] `sudo zerotier-cli info` → 200 info db4344343b 1.16.0 ONLINE
  - [x] `sudo zerotier-cli listnetworks` → db4344343b14b903 OK PRIVATE
  - [x] Peers visible: blackphos (0ee971d9e0), stibnite (3e1059d43a), electrum (d17e6d27cc)
- [x] Document current /run/secrets/ state
  - [x] `/run/secrets → /run/secrets.d/13` (symlink, deployed 2025-11-20)

### Task 4: Dry-Run Analysis (AC: #3) [USER → AI]

**Phase 4a: Local dry-run ON cinnabar [USER]**

User SSHs into cinnabar, pulls infra, runs dry-run, and shares the dix diff output in chat for AI analysis.

- [x] SSH into cinnabar and pull infra clan-01 branch
  ```bash
  ssh -A cinnabar.zt
  cd ~/projects/nix-workspace/infra  # or wherever infra is cloned
  git fetch origin clan-01
  git checkout clan-01
  git pull origin clan-01
  ```
- [x] Execute local dry-run on cinnabar
  - [x] `just clan-os-dry cinnabar` (nh os switch --dry shows dix diff)
  - [x] **Copy/paste diff output to chat for AI review**
- [x] AI analyzes diff for expected changes
  - [x] Package updates: claude-code 2.0.42→2.0.54, crush 0.18.1→0.18.6, gemini-cli 0.15.3→0.18.0
  - [x] Added: atuin-format, hm_.radiclekeysradicle.pub, zerotier-join
  - [x] Removed: backlog-md, droid, opencode (disabled in infra packages)
- [x] Confirm no unexpected destructive changes to zerotier controller
- [x] Exit cinnabar SSH session

**Phase 4b: Verify vars from stibnite [AI]**

- [x] Verify vars are current
  - [x] `clan vars list cinnabar` (executed, all vars present)
  - [x] `clan vars generate cinnabar` (not needed, vars are current)

### Task 5: Execute Deployment (AC: #3) [HYBRID]

**AI can execute `clan machines update` from stibnite, but user should monitor and be ready to intervene.**

- [x] Execute deployment via clan CLI
  - [x] `clan machines update cinnabar`
  - [x] Monitor for errors (user watches terminal output) - no errors
  - [x] DO NOT disconnect SSH during deployment
- [x] Verify deployment success
  - [x] Exit code 0
  - [x] New generation created: `/nix/store/8j5s9fj4l1v66yj8cfyjy6h72x23qidj-nixos-system-cinnabar-25.11.20251115.1d4c883`
  - [x] Vars deployed (secrets already up to date)
- [x] Document deployment results: 9 derivations built, GRUB updated, user units reloaded

### Task 6: Post-Deployment Validation (AC: #4, #5, #6) [USER]

**User executes validation commands and reports results to chat. AI cannot easily execute cross-machine SSH tests.**

- [x] Verify SSH access
  - [x] zerotier: `ssh cameron@cinnabar.zt` working (used for validation commands)
  - [x] public IP: used by clan machines update (49.13.68.78)
- [x] Verify zerotier controller status (on cinnabar)
  - [x] `zerotier-cli info` → 200 info db4344343b 1.16.0 ONLINE
  - [x] `zerotier-cli listnetworks` → db4344343b14b903 OK PRIVATE
- [x] Verify all peers still connected
  - [x] blackphos (0ee971d9e0): connected, 244ms
  - [x] stibnite (3e1059d43a): connected, 110ms
  - [x] electrum (d17e6d27cc): connected, 0ms
- [x] Verify /run/secrets/ contents (on cinnabar)
  - [x] `/run/secrets → /run/secrets.d/14` (updated from 13)
- [x] Verify new generation: 20, built 2025-11-26 16:42:19, Current=True
- [x] **Report validation results to chat**

### Task 7: Documentation (AC: #7) [AI]

- [x] Update Dev Notes with deployment details
- [x] Document infrastructure details
  - [x] Hetzner Cloud CX43: 8 vCPU, 16GB RAM, fsn1 (already documented in Dev Notes)
  - [x] ZFS disko layout reference (modules/machines/nixos/cinnabar/disko.nix)
  - [x] systemd-networkd configuration (via srvos hardware-hetzner-cloud)
- [x] Document any issues encountered
- [x] Add recovery procedures (already documented in Rollback Strategy)
- [x] Story 2.10 handoff guidance

## Dev Notes

### Learnings from Previous Story

**From Story 2.7 (Status: done)**

- **Track A (Blackphos)**: Switch from test-clan successful, minimal diff
- **Track B (Stibnite)**: Iterative migration with gap fixes (nix-rosetta-builder, colima, incus)
- **Track C (Network)**: Zerotier mesh fully operational
  - stibnite authorized via `zerotier-members allow` on cinnabar controller
  - All 4 machines connected: cinnabar, electrum, blackphos, stibnite
- **SSH bidirectional**: All .zt hostnames working
- **Configuration persistence**: allowedIps updated in both infra and test-clan

**Key Commits from Story 2.7:**
- `9be2ddac` feat(darwin): add colima module for OCI container management
- `f1947616` feat(stibnite): add nix-rosetta-builder and colima configuration
- `30d41ee4` feat(ssh): add stibnite.zt to zerotier network hosts
- `62accb11` feat(zerotier): add stibnite to allowedIps for darwin member authorization

[Source: docs/notes/development/work-items/2-7-activate-blackphos-and-stibnite-from-infra.md#Dev-Agent-Record]

### Expected Changes: test-clan → infra

cinnabar is currently deployed from test-clan. When switching to infra, the dry-run should show these **expected** changes from Story 2.7 work that was done in infra but NOT in test-clan:

**1. Zerotier allowedIps (modules/clan/inventory/services/zerotier.nix):**
- test-clan: blackphos + electrum only
- infra: blackphos + electrum + **stibnite** (commit `62accb11`)

**2. SSH config (modules/home/core/ssh.nix):**
- test-clan: cinnabar.zt, electrum.zt, blackphos.zt
- infra: adds **stibnite.zt** host definition (commit `30d41ee4`)

**3. Potential minor differences:**
- Package versions (if infra flake.lock differs from test-clan)
- Any other Story 2.3-2.7 changes not backported to test-clan

**What should NOT change:**
- Zerotier controller role (cinnabar remains controller)
- Zerotier network ID (db4344343b14b903)
- User configuration (cameron via clan inventory)
- Core services (sshd, networking)

If the dry-run shows unexpected large changes, investigate before proceeding.

### Existing Cinnabar Configuration in Infra

**Location:** modules/machines/nixos/cinnabar/
```
modules/machines/nixos/cinnabar/
├── default.nix    # 92 lines - Main NixOS configuration
└── disko.nix      # 69 lines - ZFS disk layout
```

**Key Features Configured:**
- srvos.nixosModules.server + hardware-hetzner-cloud
- home-manager integration via user-cameron service
- ZFS boot configuration (devNodes = "/dev/disk/by-path")
- Hetzner-specific networking (systemd-networkd)
- SSH MaxAuthTries = 20 (accommodates Bitwarden SSH agent)
- cameron user via clan inventory (not inline config)

### Infrastructure Management Stack

**1. Terranix (modules/terranix/hetzner.nix):**
- Defines cinnabar VM: cx43, 8 vCPU, 16GB RAM, fsn1 location
- Uses `clan machines install` for initial provisioning
- Command: `nix run .#terraform`

**2. Clan CLI commands:**
- `clan machines list` - List managed machines
- `clan machines update cinnabar` - Update/deploy cinnabar
- `clan vars generate cinnabar` - Generate vars for cinnabar
- `clan secrets` - Manage secrets

**3. Justfile recipes (clan group):**
- `just clan-os-dry cinnabar` - Preview NixOS changes
- `just clan-os-switch cinnabar` - Apply NixOS changes
- `just clan-os cinnabar` - Interactive (dry + prompt + switch)

### Clan Inventory Services for Cinnabar

**Zerotier Controller (modules/clan/inventory/services/zerotier.nix):**
```nix
roles.controller.machines."cinnabar" = {
  settings = {
    allowedIps = [
      "fddb:4344:343b:14b9:399:930e:e971:d9e0"  # blackphos
      "fddb:4344:343b:14b9:399:933e:1059:d43a"  # stibnite
    ];
  };
};
```

**User (modules/clan/inventory/services/users/cameron.nix):**
- Targets: cinnabar, electrum
- User: cameron
- Groups: wheel, networkmanager
- Home-manager: crs58 identity with all 7 aggregates

**SSHD (modules/clan/inventory/services/sshd.nix):**
- Server role for all NixOS machines
- Basic configuration without CA certificates

### Deployment Methodology

Unlike darwin (local `darwin-rebuild`), NixOS VPS uses remote deployment. There are TWO approaches available:

**1. Clan CLI (PREFERRED for NixOS VPS):**
```bash
# Full clan deployment - config + vars/secrets
clan machines update cinnabar

# Pre-check: list current vars
clan vars list cinnabar

# Regenerate vars if generators changed
clan vars generate cinnabar
```

**Why clan CLI is preferred:**
- Handles vars deployment to `/run/secrets/` automatically
- Proper clan service coordination
- Native integration with clan inventory
- Designed for clan-managed machines

**2. Flake App (Alternative - nh os switch):**
```bash
# Preview changes (nixos-rebuild style diff)
just clan-os-dry cinnabar   # → nix run .#os -- cinnabar . --dry

# Apply changes (nixos-rebuild style)
just clan-os-switch cinnabar  # → nix run .#os -- cinnabar .
```

**When to use flake app:**
- Quick config-only rebuilds (no vars changes)
- Preview diffs with nice nh output
- Situations where you explicitly don't want vars regeneration

**Connection via SSH to cinnabar:**

Preferred (zerotier mesh via home-manager SSH config):
```bash
# Simple - .zt hostname configured in modules/home/core/ssh.nix
ssh -A cinnabar.zt
```

Fallback (public IP - may need known_hosts clearing):
```bash
# Host key may change between deployments/reinstalls
IP=49.13.68.78 && \
ssh-keygen -R ${IP} && \
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -A cameron@${IP}
```

Note: The `.zt` hostnames work because Story 2.7 activated infra clan-01 on stibnite,
which includes home-manager SSH config with zerotier host definitions.

**Note on justfile recipes:**
The infra justfile `clan-os-*` recipes use `nix run .#os` which wraps `nh os switch`.
This is different from darwin deployment where `nix run .#darwin` wraps `nh darwin switch`.
For NixOS VPS, prefer direct `clan machines update` for full clan integration.

### Rollback Strategy

If deployment breaks cinnabar:

1. **SSH via public IP (may need known_hosts clearing):**
   ```bash
   IP=49.13.68.78 && \
   ssh-keygen -R ${IP} && \
   ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -A cameron@${IP}
   ```

2. **Redeploy from test-clan (preferred rollback):**
   ```bash
   cd ~/projects/nix-workspace/test-clan
   clan machines update cinnabar  # Full clan deployment with vars
   # Alternative: just os-switch cinnabar (nh os switch wrapper)
   ```

3. **Local rollback on cinnabar (if SSH works):**
   ```bash
   ssh -A cinnabar.zt  # or via public IP if zerotier broken
   sudo nixos-rebuild switch --rollback
   # Or: sudo /run/current-system/bin/switch-to-configuration switch
   ```

4. **If SSH broken:** Use Hetzner console for recovery
   - Login to Hetzner Cloud console
   - Access VPS via VNC/console
   - Boot previous generation from GRUB menu
   - Or: `nixos-rebuild switch --rollback` from console

### Key Considerations

1. **NO TERRAFORM STATE CONFLICT:**
   - cinnabar VM already exists (provisioned from test-clan)
   - Story 2.9 is about NixOS config deployment, NOT VM provisioning
   - Do NOT run `nix run .#terraform` unless reprovisioning

2. **ZEROTIER CONTROLLER CONTINUITY:**
   - Network ID: db4344343b14b903
   - Controller config in clan inventory (zerotier.nix)
   - Must verify controller role preserved after switch

3. **SSH ACCESS PRESERVATION:**
   - Maintain SSH access throughout migration
   - Fallback: Public IP 49.13.68.78

### Project Structure Notes

**Cinnabar Config:**
```
modules/machines/nixos/cinnabar/
├── default.nix        # Main NixOS config (92 lines)
└── disko.nix          # ZFS disk layout (69 lines)

modules/clan/inventory/services/
├── zerotier.nix       # Zerotier controller config
├── sshd.nix           # SSH server config
└── users/cameron.nix  # User config targeting cinnabar
```

**Zerotier Network:**
| Machine | Role | Platform | Zerotier IP |
|---------|------|----------|-------------|
| cinnabar | Controller | NixOS VPS | fddb:...controller |
| electrum | Peer | NixOS VPS | fddb:...peer |
| blackphos | Peer | Darwin | fddb:4344:343b:14b9:399:930e:e971:d9e0 |
| stibnite | Peer | Darwin | fddb:4344:343b:14b9:399:933e:1059:d43a |

### Story 2.9 Deployment Record

**Deployment Date:** 2025-11-26 16:42:19 UTC

**Source:** infra clan-01 branch (commit 60cce700)

**Deployment Method:** `clan machines update cinnabar` from stibnite

**Results:**
- Build: 9 derivations built on cinnabar
- Store path: `/nix/store/8j5s9fj4l1v66yj8cfyjy6h72x23qidj-nixos-system-cinnabar-25.11.20251115.1d4c883`
- Generation: 20 (previous: 19)
- Secrets: `/run/secrets.d/14` (previous: 13)

**Package Changes:**
- Updated: claude-code 2.0.42→2.0.54, crush 0.18.1→0.18.6, gemini-cli 0.15.3→0.18.0
- Added: atuin-format, hm_.radiclekeysradicle.pub, zerotier-join
- Removed: backlog-md, droid, opencode (disabled in infra packages)
- Size delta: -220 MiB (18.3 GiB → 18.1 GiB)

**Post-Deployment Validation:**
- Zerotier controller: ONLINE, network db4344343b14b903 OK PRIVATE
- All peers connected: blackphos, stibnite, electrum
- SSH access: working via both zerotier and public IP

### Issues Encountered and Fixes

**Issue: `--accept-flake-config` required twice**

When running `just clan-os-dry cinnabar` on cinnabar, the command failed due to interactive prompts for extra-substituters. The flag was needed for both `nix run` and `nh os switch`.

**Fix:** Two commits added `--accept-flake-config` at both layers:
- `7307bae2` fix(justfile): add --accept-flake-config to clan recipes
- `60cce700` fix(apps): add --accept-flake-config to nh commands

### Story 2.10 Handoff Guidance

**Electrum Migration Pattern:**

Story 2.10 (Electrum config migration) follows the same pattern as Story 2.9:

1. **Build validation**: `nix build .#nixosConfigurations.electrum.config.system.build.toplevel`
2. **Clan vars verification**: `clan vars list electrum`
3. **Pre-deployment SSH check**: `ssh cameron@electrum.zt "sudo zerotier-cli info"`
4. **Dry-run on electrum**: SSH in, pull infra, `just clan-os-dry electrum`
5. **Deploy**: `clan machines update electrum`
6. **Validate**: zerotier peer status, SSH access, secrets

**Key Differences:**
- electrum is a zerotier *peer*, not controller (lower risk)
- No allowedIps management required
- Same user-cameron service configuration

**Note:** The `.zt` hostnames are SSH config aliases, not DNS. System commands like `ping` require zerotier IPv6 addresses. Future enhancement: configure zerotier DNS on controller.

### References

**Source Documentation:**
- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md) - Story 2.9 definition (lines 222-237)
- [Architecture - Deployment](docs/notes/development/architecture/deployment-architecture.md) - NixOS VPS deployment commands

**Predecessor Stories:**
- [Story 2.7](docs/notes/development/work-items/2-7-activate-blackphos-and-stibnite-from-infra.md) - Darwin activation pattern (provides deployment methodology)
- [Story 2.3](docs/notes/development/work-items/2-3-wholesale-migration-test-clan-to-infra.md) - Wholesale migration (cinnabar config exists in infra)

**Successor Stories:**
- Story 2.10 (backlog) - Electrum config migration

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

- Story 2.9 execution started 2025-11-26
- Task 1-2 completed immediately (build cached, vars verified)
- Task 3-4 user-interactive SSH validation and dry-run analysis
- Task 5 deployment via `clan machines update cinnabar`
- Task 6 post-deployment validation confirmed all services operational
- Discovered --accept-flake-config issue, fixed in commits 7307bae2, 60cce700

### Completion Notes List

- cinnabar successfully switched from test-clan to infra clan-01 deployment source
- Zerotier controller functionality preserved (network db4344343b14b903)
- All mesh peers connected post-deployment (blackphos, stibnite, electrum)
- Package updates applied: claude-code, crush, gemini-cli
- Disabled packages removed: backlog-md, droid, opencode
- New packages added: atuin-format, zerotier-join
- NixOS generation 20 active, secrets generation 14

### File List

**Modified:**
- justfile (--accept-flake-config for clan recipes)
- modules/darwin/app.nix (--accept-flake-config for nh darwin)
- modules/home/app.nix (--accept-flake-config for nh home)
- modules/nixos/app.nix (--accept-flake-config for nh os)
- docs/notes/development/work-items/2-9-cinnabar-config-migration.md (this story)

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-26 | 1.0 | Story drafted from Epic 2 definition and user-provided context |
| 2025-11-26 | 1.1 | Updated deployment methodology: clan CLI preferred over nh os switch for VPS. Clarified distinction between `clan machines update` and `just clan-os-switch`. Updated AC3, Task 4, Task 5 to use clan CLI. Enhanced rollback strategy. |
| 2025-11-26 | 1.2 | Added detailed SSH connection commands: .zt hostname (simple, via home-manager config) vs public IP fallback (with known_hosts clearing). Documented agent forwarding (-A) pattern. |
| 2025-11-26 | 1.3 | Added local dry-run approach: SSH into cinnabar, pull infra, run dry-run locally to preview changes before remote deployment. Documented expected changes from test-clan → infra (stibnite zerotier/SSH additions from Story 2.7). |
| 2025-11-26 | 1.4 | Added execution mode annotations [AI]/[USER]/[HYBRID] to all tasks. Documented hybrid execution model in Context section. Some tasks (SSH sessions, interactive diffs, cross-machine tests) require user execution with results reported to chat. |
| 2025-11-26 | 1.5 | Story execution complete. Fixed --accept-flake-config issue (commits 7307bae2, 60cce700). Deployment successful: generation 20, all zerotier peers connected. |
