# Story 2.10: Electrum config migration

Status: drafted

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
- [ ] Hetzner Cloud specs documented
- [ ] ZFS disk layout documented (disko.nix)
- [ ] Network configuration documented (systemd-networkd)
- [ ] Story completion notes documented
- [ ] Phase 3 completion status documented

## Tasks / Subtasks

**Execution Mode Legend:**
- **[AI]** - Can be executed directly by Claude Code
- **[USER]** - Should be executed by human developer, report results back to chat
- **[HYBRID]** - AI prepares/validates, user executes interactive portions

---

### Task 1: Build Validation (AC: #1) [AI]

- [ ] Build electrum config from infra
  - [ ] `nix build .#nixosConfigurations.electrum.config.system.build.toplevel`
  - [ ] Verify build succeeds
  - [ ] Document store path
- [ ] Compare with test-clan config for drift
  - [ ] Check key configurations match
  - [ ] Note any differences in Dev Notes

### Task 2: Clan Vars/Secrets Verification (AC: #2, #5) [AI]

- [ ] Audit clan inventory services
  - [ ] Review modules/clan/inventory/services/zerotier.nix (electrum peer role)
  - [ ] Review modules/clan/inventory/services/users/cameron.nix (targets electrum)
  - [ ] Review modules/clan/inventory/services/sshd.nix
- [ ] Verify user-cameron service instance
  - [ ] Check electrum is targeted
  - [ ] Verify cameron user configuration
- [ ] Verify zerotier peer configuration
  - [ ] Network ID db4344343b14b903 (via `clan vars list electrum`)
  - [ ] Peer role (not controller)

### Task 3: Pre-Deployment Checklist (AC: #4) [USER]

**User executes these SSH commands and reports current state to chat.**

- [ ] Confirm SSH access via public IP (fallback)
  - [ ] `ssh cameron@162.55.175.87 "hostname"` → electrum
  - [ ] Document current IP: 162.55.175.87
- [ ] Note current zerotier status
  - [ ] `sudo zerotier-cli info` → ONLINE status
  - [ ] `sudo zerotier-cli listnetworks` → network status
  - [ ] Peers visible: cinnabar, blackphos, stibnite
- [ ] Document current /run/secrets/ state
  - [ ] Current secrets generation

### Task 4: Dry-Run Analysis (AC: #3) [USER → AI]

**Phase 4a: Local dry-run ON electrum [USER]**

User SSHs into electrum, pulls infra, runs dry-run, and shares the diff output in chat for AI analysis.

- [ ] SSH into electrum and pull infra clan-01 branch
  ```bash
  ssh -A electrum.zt
  cd ~/projects/nix-workspace/infra  # or wherever infra is cloned
  git fetch origin clan-01
  git checkout clan-01
  git pull origin clan-01
  ```
- [ ] Execute local dry-run on electrum
  - [ ] `just clan-os-dry electrum` (nh os switch --dry shows diff)
  - [ ] **Copy/paste diff output to chat for AI review**
- [ ] AI analyzes diff for expected changes
  - [ ] Package updates (similar pattern to cinnabar)
  - [ ] Any added/removed packages
- [ ] Confirm no unexpected changes
- [ ] Exit electrum SSH session

**Phase 4b: Verify vars from stibnite [AI]**

- [ ] Verify vars are current
  - [ ] `clan vars list electrum`
  - [ ] `clan vars generate electrum` (only if needed)

### Task 5: Execute Deployment (AC: #3) [HYBRID]

**AI can execute `clan machines update` from stibnite, but user should monitor and be ready to intervene.**

- [ ] Execute deployment via clan CLI
  - [ ] `clan machines update electrum`
  - [ ] Monitor for errors (user watches terminal output)
  - [ ] DO NOT disconnect SSH during deployment
- [ ] Verify deployment success
  - [ ] Exit code 0
  - [ ] New generation created
  - [ ] Vars deployed
- [ ] Document deployment results

### Task 6: Post-Deployment Validation (AC: #4, #5, #6) [USER]

**User executes validation commands and reports results to chat. AI cannot easily execute cross-machine SSH tests.**

- [ ] Verify SSH access
  - [ ] zerotier: `ssh cameron@electrum.zt` working
  - [ ] public IP: `ssh cameron@162.55.175.87` working
- [ ] Verify zerotier peer status (on electrum)
  - [ ] `zerotier-cli info` → ONLINE
  - [ ] `zerotier-cli listnetworks` → network status
- [ ] Verify all peers still connected
  - [ ] cinnabar (controller): connected
  - [ ] blackphos: connected
  - [ ] stibnite: connected
- [ ] Verify /run/secrets/ contents (on electrum)
  - [ ] Secrets directory updated
- [ ] Verify new generation
- [ ] **Report validation results to chat**

### Task 7: Documentation (AC: #7) [AI]

- [ ] Update Dev Notes with deployment details
- [ ] Document infrastructure details
  - [ ] Hetzner Cloud specs
  - [ ] ZFS disko layout reference
  - [ ] systemd-networkd configuration
- [ ] Document any issues encountered
- [ ] Phase 3 completion status (cinnabar + electrum both migrated)

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

### Completion Notes List

### File List

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-26 | 1.0 | Story drafted from Epic 2 definition, Story 2.9 pattern, and user-provided context |
