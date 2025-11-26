# Story 2.10: Electrum config migration

Status: done

## Story

As a system administrator,
I want to switch electrum VPS deployment source from test-clan to infra clan-01 branch,
so that electrum is managed from production infra repository while maintaining zerotier peer connectivity.

## Context

**Epic 2 Phase 3 Story 2 (VPS Migration):**
This is the second story in Epic 2 Phase 3 (VPS Migration). Story 2.9 switched cinnabar deployment to infra and validated zerotier controller functionality. Story 2.10 switches electrum deployment to infra, completing the VPS migration phase.

**Story Type: DEPLOYMENT (Switch Deployment Source):**
- electrum NixOS config ALREADY EXISTS in infra (migrated in Story 2.3)
- Currently DEPLOYED from test-clan
- Must switch to deploying from infra clan-01 branch
- EXACT same pattern as Story 2.9 (cinnabar)

**Execution Model: HYBRID (User-Interactive with AI Assistance)**

Similar to Story 2.9, this story involves:
- **[AI]** tasks: Build validation, clan vars verification, documentation
- **[USER]** tasks: SSH sessions, dry-run diff review, cross-machine validation
- **[HYBRID]** tasks: AI executes deployment, user monitors output

Some commands (SSH into electrum, nh os diff review, cross-machine ping tests) are difficult for Claude Code to execute and capture feedback from. These should be executed by the developer with results reported back to the chat thread for AI analysis.

**LOWER RISK THAN STORY 2.9:**

electrum is a zerotier PEER (not controller) on network db4344343b14b903.
If deployment breaks electrum networking, the mesh remains operational (cinnabar is controller).
This is a LOWER-RISK deployment compared to Story 2.9.

**Deployment Commands (Clan CLI - PREFERRED for NixOS VPS):**
```bash
# Clan CLI - canonical approach for clan-managed NixOS VPS
# Handles: config deployment + vars/secrets to /run/secrets/
clan machines update electrum

# Pre-deployment: regenerate vars if generators changed
clan vars generate electrum

# Check current vars
clan vars list electrum
```

**Alternative (Flake App - nh os switch wrapper):**
```bash
# Preview changes via nh os switch (nixos-rebuild style diff)
just clan-os-dry electrum   # → nix run .#os -- electrum . --dry

# Apply via nh os switch (nixos-rebuild style deployment)
just clan-os-switch electrum  # → nix run .#os -- electrum .
```

## Acceptance Criteria

### AC1: Verify electrum configuration in infra builds

Verify the electrum NixOS configuration builds successfully from infra repository.

**Verification:**
```bash
# Build nixos toplevel
nix build .#nixosConfigurations.electrum.config.system.build.toplevel

# Verify build completes
echo $?  # Exit code 0

# Verify store path created
readlink result
# Expected: /nix/store path for electrum system
```

### AC2: Preserve zerotier peer configuration

Ensure zerotier peer configuration is preserved after switching deployment source.

**Verification:**
```bash
# Verify zerotier config in infra
grep -r "electrum" modules/clan/inventory/services/zerotier.nix || \
  grep -r "zerotier" modules/machines/nixos/electrum/
# Expected: Network ID db4344343b14b903 referenced

# After deployment - verify peer operational
ssh cameron@electrum.zt "zerotier-cli info"
# Expected: 200 info ... ONLINE

ssh cameron@electrum.zt "zerotier-cli listnetworks"
# Expected: db4344343b14b903 with peer status
```

### AC3: Deploy electrum from infra

Execute deployment from infra clan-01 branch successfully using clan CLI.

**Verification:**
```bash
# Execute deployment via clan CLI (preferred for VPS)
clan machines update electrum

# Verify exit code
echo $?  # Exit code 0

# Verify new system generation
ssh cameron@electrum.zt "nixos-rebuild list-generations | head -5"
# Expected: New generation from infra deployment

# Verify vars were deployed
ssh cameron@electrum.zt "ls -la /run/secrets/"
# Expected: Secrets present from clan vars
```

### AC4: Validate SSH access from darwin workstations

Verify SSH access via both zerotier and public IP.

**Verification:**
```bash
# Test zerotier access
ssh cameron@electrum.zt "hostname"
# Expected: electrum

# Test public IP fallback
ssh cameron@162.55.175.87 "hostname"
# Expected: electrum

# Test from blackphos
ssh cameron@electrum.zt "hostname"

# Test from stibnite
ssh cameron@electrum.zt "hostname"
```

### AC5: Validate clan vars deployment

Verify clan vars are properly deployed to /run/secrets/.

**Verification:**
```bash
# Check secrets directory exists
ssh cameron@electrum.zt "ls -la /run/secrets/"
# Expected: Directory exists with secrets

# Check permissions
ssh cameron@electrum.zt "stat -c '%a %U:%G' /run/secrets"
# Expected: Appropriate permissions

# Verify SSH keys deployed
ssh cameron@electrum.zt "ls -la /run/secrets/ | grep -i ssh"
# Expected: SSH-related secrets present
```

### AC6: Test zerotier mesh connectivity

Verify full mesh connectivity between all machines.

**Verification:**
```bash
# Verify peer status on electrum
ssh cameron@electrum.zt "zerotier-cli info"
# Expected: 200 info ... ONLINE

ssh cameron@electrum.zt "zerotier-cli listnetworks"
# Expected: db4344343b14b903 OK PRIVATE

# Verify connectivity to all peers
# From electrum:
ssh cameron@electrum.zt "zerotier-cli peers | grep -E '(cinnabar|blackphos|stibnite)'"
# Expected: All peers listed

# From stibnite (cross-validation):
ping -c 3 electrum.zt
ssh cameron@electrum.zt "hostname"
```

### AC7: Document electrum-specific infrastructure

Document electrum infrastructure details for future reference.

**Verification:**
- [x] Hetzner Cloud specs documented
- [x] ZFS disk layout documented (disko.nix)
- [x] Network configuration documented (systemd-networkd)
- [x] Story completion notes documented
- [x] Phase 3 completion status documented

## Tasks / Subtasks

**Execution Mode Legend:**
- **[AI]** - Can be executed directly by Claude Code
- **[USER]** - Should be executed by human developer, report results back to chat
- **[HYBRID]** - AI prepares/validates, user executes interactive portions

---

### Task 1: Build Validation (AC: #1) [AI]

- [x] Build electrum config from infra
  - [x] `nix build .#nixosConfigurations.electrum.config.system.build.toplevel`
  - [x] Verify build succeeds
  - [x] Document store path: /nix/store/9z6zbymrn6p7w2jh9x0621i6v2mikm86-nixos-system-electrum-25.11.20251115.1d4c883
- [x] Compare with test-clan config for drift
  - [x] Check key configurations match
  - [x] Note any differences in Dev Notes

### Task 2: Clan Vars/Secrets Verification (AC: #2, #5) [AI]

- [x] Audit clan inventory services
  - [x] Review modules/clan/inventory/services/zerotier.nix (electrum peer role)
  - [x] Review modules/clan/inventory/services/users/cameron.nix (targets electrum)
  - [x] Review modules/clan/inventory/services/sshd.nix
- [x] Verify user-cameron service instance
  - [x] Check electrum is targeted
  - [x] Verify cameron user configuration
- [x] Verify zerotier peer configuration
  - [x] Network ID db4344343b14b903 (via `clan vars list electrum`)
  - [x] Peer role (not controller)

### Task 3: Pre-Deployment Checklist (AC: #4) [USER]

**User executes these SSH commands and reports current state to chat.**

- [x] Confirm SSH access via public IP (fallback)
  - [x] `ssh cameron@162.55.175.87 "hostname"` → electrum
  - [x] Document current IP: 162.55.175.87
- [x] Note current zerotier status
  - [x] `sudo zerotier-cli info` → ONLINE status
  - [x] `sudo zerotier-cli listnetworks` → network status
  - [x] Peers visible: cinnabar, blackphos, stibnite
- [x] Document current /run/secrets/ state
  - [x] Current secrets generation

### Task 4: Dry-Run Analysis (AC: #3) [USER → AI]

**Phase 4a: Local dry-run ON electrum [USER]**

User SSHs into electrum, pulls infra, runs dry-run, and shares the diff output in chat for AI analysis.

- [x] SSH into electrum and pull infra clan-01 branch
  ```bash
  ssh -A electrum.zt
  cd ~/projects/nix-workspace/infra  # or wherever infra is cloned
  git fetch origin clan-01
  git checkout clan-01
  git pull origin clan-01
  ```
- [x] Execute local dry-run on electrum
  - [x] `just clan-os-dry electrum` (nh os switch --dry shows diff)
  - [x] **Copy/paste diff output to chat for AI review**
- [x] AI analyzes diff for expected changes
  - [x] Package updates (similar pattern to cinnabar)
  - [x] Any added/removed packages
- [x] Confirm no unexpected changes
- [x] Exit electrum SSH session

**Phase 4b: Verify vars from stibnite [AI]**

- [x] Verify vars are current
  - [x] `clan vars list electrum`
  - [x] `clan vars generate electrum` (only if needed)

### Task 5: Execute Deployment (AC: #3) [HYBRID]

**AI can execute `clan machines update` from stibnite, but user should monitor and be ready to intervene.**

- [x] Execute deployment via clan CLI
  - [x] `clan machines update electrum`
  - [x] Monitor for errors (user watches terminal output)
  - [x] DO NOT disconnect SSH during deployment
- [x] Verify deployment success
  - [x] Exit code 0
  - [x] New generation created
  - [x] Vars deployed
- [x] Document deployment results

### Task 6: Post-Deployment Validation (AC: #4, #5, #6) [USER]

**User executes validation commands and reports results to chat. AI cannot easily execute cross-machine SSH tests.**

- [x] Verify SSH access
  - [x] zerotier: `ssh cameron@electrum.zt` working
  - [x] public IP: `ssh cameron@162.55.175.87` working
- [x] Verify zerotier peer status (on electrum)
  - [x] `zerotier-cli info` → ONLINE (d17e6d27cc 1.16.0 ONLINE)
  - [x] `zerotier-cli listnetworks` → network status (db4344343b14b903 OK PRIVATE)
- [x] Verify all peers still connected
  - [x] cinnabar (controller): connected (db4344343b DIRECT 4ms)
  - [x] blackphos: connected (0ee971d9e0 DIRECT 224ms)
  - [x] stibnite: connected (3e1059d43a DIRECT 118ms)
- [x] Verify /run/secrets/ contents (on electrum)
  - [x] Secrets directory updated (/run/secrets/vars/openssh, tor_tor, zerotier)
- [x] Verify new generation
- [x] **Report validation results to chat**

### Task 7: Documentation (AC: #7) [AI]

- [x] Update Dev Notes with deployment details
- [x] Document infrastructure details
  - [x] Hetzner Cloud specs (see Dev Notes)
  - [x] ZFS disko layout reference (modules/machines/nixos/electrum/disko.nix)
  - [x] systemd-networkd configuration (Hetzner-specific via srvos)
- [x] Document any issues encountered (rosetta-builder SSH fix)
- [x] Phase 3 completion status (cinnabar + electrum both migrated)

## Dev Notes

### Learnings from Previous Story

**From Story 2.9 (Status: done)**

- **Deployment successful**: cinnabar switched from test-clan to infra clan-01 on 2025-11-26
- **Zerotier controller preserved**: Network db4344343b14b903 operational
- **All peers connected**: blackphos, stibnite, electrum all reachable post-deployment
- **Generation 20**: New NixOS generation created, secrets updated to /run/secrets.d/14
- **Package changes applied**: claude-code updated, backlog-md/droid/opencode removed

**Key Fix from Story 2.9 (ALREADY APPLIED):**
- `--accept-flake-config` issue FIXED in commits 7307bae2, 60cce700
- Both justfile recipes AND nh commands now include the flag
- No similar issue expected for electrum deployment

**Deployment Pattern (validated):**
1. Build validation from stibnite
2. Clan vars verification
3. SSH into VPS, pull infra, dry-run locally
4. Deploy via `clan machines update` from stibnite
5. Post-deployment validation

[Source: docs/notes/development/work-items/2-9-cinnabar-config-migration.md#Dev-Agent-Record]

### Existing Electrum Configuration in Infra

**Location:** modules/machines/nixos/electrum/
```
modules/machines/nixos/electrum/
├── default.nix    # Main NixOS configuration
└── disko.nix      # ZFS disk layout
```

**Key Features Configured:**
- srvos.nixosModules.server + hardware-hetzner-cloud
- home-manager integration via user-cameron service
- ZFS boot configuration
- Hetzner-specific networking (systemd-networkd)
- cameron user via clan inventory

### Infrastructure Details

**Hetzner Cloud:**
- Public IP: 162.55.175.87
- Location: fsn1 (Falkenstein)
- Model: Similar to cinnabar (cx43 or equivalent)

**Zerotier Network:**
- Network ID: db4344343b14b903
- Role: **PEER** (cinnabar is controller)
- Expected peers: cinnabar, blackphos, stibnite

### Deployment Methodology

**Clan CLI (PREFERRED for NixOS VPS):**
```bash
# Full clan deployment - config + vars/secrets
clan machines update electrum

# Pre-check: list current vars
clan vars list electrum

# Regenerate vars if generators changed
clan vars generate electrum
```

**Connection via SSH to electrum:**

Preferred (zerotier mesh via home-manager SSH config):
```bash
# Simple - .zt hostname configured in modules/home/core/ssh.nix
ssh -A electrum.zt
```

Fallback (public IP):
```bash
IP=162.55.175.87 && \
ssh-keygen -R ${IP} && \
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -A cameron@${IP}
```

### Rollback Strategy

If deployment breaks electrum:

1. **SSH via public IP (may need known_hosts clearing):**
   ```bash
   IP=162.55.175.87 && \
   ssh-keygen -R ${IP} && \
   ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -A cameron@${IP}
   ```

2. **Redeploy from test-clan (preferred rollback):**
   ```bash
   cd ~/projects/nix-workspace/test-clan
   clan machines update electrum
   ```

3. **Local rollback on electrum (if SSH works):**
   ```bash
   ssh -A electrum.zt
   sudo nixos-rebuild switch --rollback
   ```

4. **If SSH broken:** Use Hetzner console for recovery

### Key Differences from Story 2.9

| Aspect | Story 2.9 (cinnabar) | Story 2.10 (electrum) |
|--------|---------------------|----------------------|
| Zerotier role | **Controller** | **Peer** |
| Risk level | HIGH | LOWER |
| allowedIps | Manages blackphos, stibnite | N/A (peer only) |
| Deployment impact | Network outage if broken | Only electrum affected |

### Project Structure Notes

**Electrum Config:**
```
modules/machines/nixos/electrum/
├── default.nix        # Main NixOS config
└── disko.nix          # ZFS disk layout

modules/clan/inventory/services/
├── zerotier.nix       # Electrum as peer
├── sshd.nix           # SSH server config
└── users/cameron.nix  # User config targeting electrum
```

**Zerotier Network:**
| Machine | Role | Platform | Status |
|---------|------|----------|--------|
| cinnabar | Controller | NixOS VPS | Migrated (Story 2.9) |
| electrum | **Peer** | NixOS VPS | **This story** |
| blackphos | Peer | Darwin | Active |
| stibnite | Peer | Darwin | Active |

### References

**Source Documentation:**
- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md) - Story 2.10 definition (lines 241-257)
- [Architecture - Deployment](docs/notes/development/architecture/deployment-architecture.md) - NixOS VPS deployment commands

**Predecessor Stories:**
- [Story 2.9](docs/notes/development/work-items/2-9-cinnabar-config-migration.md) - Cinnabar migration (same pattern, DONE)

**Successor Stories:**
- Story 2.11 (backlog) - Rosegold configuration creation (Phase 4)

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

- Rosetta-builder SSH "too many authentication failures" diagnosed and fixed
- Build initially failed due to rosetta-builder VM crash (memory/state issue)
- Solution: Added `IdentitiesOnly yes` SSH config (050-rosetta-builder-identities.conf)

### Completion Notes List

**Deployment Summary (2025-11-26):**
- electrum switched from test-clan to infra clan-01 branch
- Store path: /nix/store/9z6zbymrn6p7w2jh9x0621i6v2mikm86-nixos-system-electrum-25.11.20251115.1d4c883
- Zerotier peer status: ONLINE on network db4344343b14b903
- All peers connected: cinnabar (4ms), blackphos (224ms), stibnite (118ms)
- Clan vars deployed: /run/secrets/vars/{openssh,tor_tor,zerotier}

**Package Changes:**
- Updated: claude-code 2.0.42→2.0.54, crush 0.18.1→0.18.6, gemini-cli 0.15.3→0.18.0
- Added: atuin-format, rosetta-restart, zerotier-join
- Removed: backlog-md, droid, opencode (disabled packages)

**Infrastructure Fix (bonus):**
- Added `rosetta-restart` shell command for nix-rosetta-builder VM management
- Fixed SSH config for rosetta-builder (IdentitiesOnly workaround for Bitwarden SSH agent)

**Phase 3 Completion:**
- Story 2.9 (cinnabar): DONE - zerotier controller migrated
- Story 2.10 (electrum): DONE - zerotier peer migrated
- Both VPS machines now deployed from infra clan-01 branch

### File List

**Modified:**
- modules/machines/darwin/stibnite/default.nix (rosetta-builder SSH fix)
- modules/home/tools/commands/_system-tools.nix (rosetta-restart command)
- modules/home/tools/commands/_descriptions.nix (rosetta-restart description)
- docs/notes/development/sprint-status.yaml (story status)

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-26 | 1.0 | Story drafted from Epic 2 definition, Story 2.9 pattern, and user-provided context |
| 2025-11-26 | 2.0 | Story completed - electrum deployed from infra, all ACs verified, Phase 3 complete |
