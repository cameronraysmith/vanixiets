# Story 2.9: Cinnabar config migration

Status: drafted

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

### Task 1: Build Validation (AC: #1)

- [ ] Build cinnabar config from infra
  - [ ] `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
  - [ ] Verify build succeeds
  - [ ] Document store path
- [ ] Compare with test-clan config for drift
  - [ ] Check key configurations match
  - [ ] Note any differences in Dev Notes

### Task 2: Clan Vars/Secrets Verification (AC: #2, #5)

- [ ] Audit clan inventory services
  - [ ] Review modules/clan/inventory/services/zerotier.nix
  - [ ] Review modules/clan/inventory/services/users/cameron.nix
  - [ ] Review modules/clan/inventory/services/sshd.nix
- [ ] Verify user-cameron service instance
  - [ ] Check cinnabar is targeted
  - [ ] Verify cameron user configuration
- [ ] Verify zerotier controller configuration
  - [ ] Network ID db4344343b14b903
  - [ ] allowedIps includes blackphos + stibnite

### Task 3: Pre-Deployment Checklist (AC: #4)

- [ ] Confirm SSH access via public IP (fallback)
  - [ ] `ssh cameron@49.13.68.78 "hostname"`
  - [ ] Document current IP
- [ ] Note current zerotier status
  - [ ] `ssh cameron@cinnabar.zt "zerotier-cli info"`
  - [ ] `ssh cameron@cinnabar.zt "zerotier-cli listnetworks"`
- [ ] Document current /run/secrets/ state
  - [ ] `ssh cameron@cinnabar.zt "ls -la /run/secrets/"`

### Task 4: Dry-Run Analysis (AC: #3)

**Phase 4a: Local dry-run ON cinnabar (safer - see diff before remote deployment)**

- [ ] SSH into cinnabar and pull infra clan-01 branch
  ```bash
  ssh -A cinnabar.zt
  cd ~/projects/nix-workspace/infra  # or wherever infra is cloned
  git fetch origin clan-01
  git checkout clan-01
  git pull origin clan-01
  ```
- [ ] Execute local dry-run on cinnabar
  - [ ] `just clan-os-dry cinnabar` (nh os switch --dry shows dix diff)
  - [ ] Capture diff output
- [ ] Analyze diff for expected changes
  - [ ] **Expected**: zerotier allowedIps adds stibnite (Story 2.7 change)
  - [ ] **Expected**: SSH config adds stibnite.zt host (Story 2.7 change)
  - [ ] Document any other package/config changes
- [ ] Confirm no unexpected destructive changes to zerotier controller
- [ ] Exit cinnabar SSH session

**Phase 4b: Verify vars from stibnite (before remote deployment)**

- [ ] Verify vars are current
  - [ ] `clan vars list cinnabar`
  - [ ] `clan vars generate cinnabar` (if generators changed)

### Task 5: Execute Deployment (AC: #3)

- [ ] Execute deployment via clan CLI
  - [ ] `clan machines update cinnabar`
  - [ ] Monitor for errors
  - [ ] DO NOT disconnect SSH during deployment
- [ ] Verify deployment success
  - [ ] Exit code 0
  - [ ] New generation created
  - [ ] Vars deployed to /run/secrets/
- [ ] Document deployment results

### Task 6: Post-Deployment Validation (AC: #4, #5, #6)

- [ ] Verify SSH access
  - [ ] zerotier: `ssh cameron@cinnabar.zt "hostname"`
  - [ ] public IP: `ssh cameron@49.13.68.78 "hostname"`
- [ ] Verify zerotier controller status
  - [ ] `zerotier-cli info` shows ONLINE
  - [ ] `zerotier-cli listnetworks` shows network
- [ ] Verify all peers still connected
  - [ ] Test from blackphos → cinnabar, electrum, stibnite
  - [ ] Test from stibnite → cinnabar, electrum, blackphos
- [ ] Verify /run/secrets/ contents
  - [ ] Secrets present
  - [ ] Permissions correct

### Task 7: Documentation (AC: #7)

- [ ] Update Dev Notes with deployment details
- [ ] Document infrastructure details
  - [ ] Hetzner Cloud CX43: 8 vCPU, 16GB RAM, fsn1
  - [ ] ZFS disko layout reference
  - [ ] systemd-networkd configuration
- [ ] Document any issues encountered
- [ ] Add recovery procedures
- [ ] Story 2.10 handoff guidance

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

### Completion Notes List

### File List

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-26 | 1.0 | Story drafted from Epic 2 definition and user-provided context |
| 2025-11-26 | 1.1 | Updated deployment methodology: clan CLI preferred over nh os switch for VPS. Clarified distinction between `clan machines update` and `just clan-os-switch`. Updated AC3, Task 4, Task 5 to use clan CLI. Enhanced rollback strategy. |
| 2025-11-26 | 1.2 | Added detailed SSH connection commands: .zt hostname (simple, via home-manager config) vs public IP fallback (with known_hosts clearing). Documented agent forwarding (-A) pattern. |
| 2025-11-26 | 1.3 | Added local dry-run approach: SSH into cinnabar, pull infra, run dry-run locally to preview changes before remote deployment. Documented expected changes from test-clan → infra (stibnite zerotier/SSH additions from Story 2.7). |
