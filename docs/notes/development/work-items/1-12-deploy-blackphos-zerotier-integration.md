# Story 1.12: Deploy blackphos and Integrate into Zerotier Network

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** backlog

**Dependencies:**
- Story 1.10BA (done): Pattern A refactoring (17 modules, full functionality)
- Story 1.10C (done): sops-nix infrastructure validated
- Story 1.11 (deferred): Type-safe architecture (soft dependency - deferred pending Story 1.12 empirical evidence)

**Blocks:**
- Story 1.13 (backlog): Integration findings documentation requires Story 1.12 deployment experience
- Story 1.14 (backlog): GO/NO-GO decision depends on heterogeneous networking validation

**Strategic Value:** First physical hardware deployment in Epic 1, validates configuration completeness on actual darwin hardware, proves heterogeneous networking (nixos ↔ nix-darwin) across 3-machine network, discovers zerotier darwin integration solution for Epic 3-6 (3 more darwin migrations: blackphos prod, rosegold, argentum), provides zero-regression validation checklist for production deployments, informs Story 1.11 necessity assessment (type-safe architecture decision), de-risks Epic 2-6 timeline (darwin deployment pattern validated empirically).

---

## Story Description

As a system administrator,
I want to deploy the fully-migrated blackphos configuration to physical hardware and integrate into the test-clan zerotier network,
So that I validate heterogeneous networking (nixos ↔ nix-darwin), prove multi-platform coordination works, and complete Epic 1 architectural validation with real hardware evidence.

**Context:**

Story 1.12 is the **first physical deployment** in Epic 1.
All prior stories (1.1-1.10E) worked with configuration development and virtual machines.
Story 1.12 deploys to actual laptop hardware and validates real-world functionality.

**Configuration State:**

Blackphos configuration is **production-ready** after multi-story evolution:
- Story 1.8: Initial migration from infra to test-clan (darwin + home-manager modules)
- Story 1.8A: Portable home-manager modules extracted (crs58, raquel)
- Story 1.10BA: Pattern A refactoring (17 modules in dendritic aggregates)
- Story 1.10C: sops-nix secrets integration (SSH signing, API keys, user secrets)
- Story 1.10DB: Overlay architecture migration (5 layers functional)
- Story 1.10E: Feature enablement (ccstatusline, claude-code, catppuccin themes)

**Current Build Status:**
```
darwinConfigurations.blackphos.system ✅ BUILDS
homeConfigurations.aarch64-darwin.crs58 ✅ BUILDS (122 derivations)
homeConfigurations.aarch64-darwin.raquel ✅ BUILDS (105 derivations)
```

**Configuration Location:** `test-clan/modules/machines/darwin/blackphos/default.nix` (173 lines)

**Users Configured:**
- crs58 (UID 550, admin): SSH keys, home-manager (development + ai + shell aggregates), sops-nix secrets
- raquel (UID 551, primary): SSH keys, home-manager (development + shell aggregates), sops-nix secrets

**Features Enabled:**
- System: Homebrew (8 casks + 1 masApp), TouchID sudo, zsh system-wide
- Development: LazyVim, git signing, jujutsu, atuin, nix-ai-tools (claude-code)
- AI Tooling: MCP servers, API keys (sops-nix), GLM wrapper
- Shell/Terminal: tmux (catppuccin theme), zsh, starship, ccstatusline

**Zerotier Network State (from Story 1.9):**

Current 2-machine network operational:
- cinnabar (nixos VPS): zerotier controller, network ID db4344343b14b903
- electrum (nixos VPS): zerotier peer, bidirectional connectivity validated (1-12ms latency)

Story 1.12 adds blackphos as **third peer** (first darwin peer), validates **heterogeneous networking** (nixos ↔ nix-darwin).

**Critical Investigation Required: Zerotier Darwin Integration**

**Problem:** clan-core zerotier module is NixOS-specific (uses systemd services).
nix-darwin has NO native zerotier module (verified via repository search).

**Investigation Needed (AC B):**

Research and implement ONE of these approaches:

**Option A: Homebrew Cask**
- Install: `homebrew.casks = [ "zerotier-one" ];`
- Configuration: Manual join via CLI (`sudo zerotier-cli join db4344343b14b903`)
- Pros: Simple installation, well-maintained cask, standard macOS UX
- Cons: Non-declarative join, manual configuration, homebrew dependency

**Option B: Custom Launchd Service**
- Install zerotier-one package from nixpkgs
- Create custom launchd.daemons.zerotier-one service
- Configuration: declarative network join via launchd args
- Pros: Nix-native, declarative configuration, no homebrew
- Cons: Custom module development, platform-specific launchd knowledge

**Option C: Manual Installation with Nix Wrapper**
- Install zerotier binary from nixpkgs
- User manages service startup (launchctl load)
- Configuration: manual CLI join, non-declarative
- Pros: Minimal nix integration, zero module code
- Cons: Completely manual, not reproducible, defeats nix benefits

**Recommended Starting Point:** Option A (homebrew cask) for Story 1.12 validation.
Document approach used, platform-specific challenges, and potential improvements for Epic 3-6 darwin migrations.

**Story 1.11 Deferral Context (Party Mode Decision 2025-11-16):**

Story 1.11 (type-safe home-manager architecture with homeHosts pattern) was **deferred** pending Story 1.12 empirical evidence.

**Rationale:** Current architecture (Stories 1.8A + 1.10BA + 1.10C) proven at scale:
- 270 packages preserved exactly across migrations
- 17 home-manager modules using Pattern A aggregates
- 4+ users configured (crs58, raquel, testuser, cameron)
- sops-nix secrets functional across all users
- All builds passing, zero regressions

**Decision Framework:** Deploy blackphos to physical hardware FIRST (Story 1.12), assess type-safety necessity based on REAL deployment experience.

**Re-evaluation Checkpoint:** Story 1.13 documentation phase (Party Mode assessment framework, epic lines 1858-1937).

**Criteria:**
- **GO (execute Story 1.11):** Deployment reveals typos/errors, machine-specific configs needed, homeHosts improves dendritic patterns
- **MODIFY:** Some elements valuable (CI checks) but not full homeHosts pattern
- **SKIP (permanent):** No issues encountered, current architecture elegant and maintainable, homeHosts adds unnecessary complexity

Story 1.12 provides **empirical evidence** for this decision (not speculation).

**Why This Story Matters:**

1. **First Physical Deployment:** All prior work was configuration development. Story 1.12 proves configuration actually works on real hardware.

2. **Zero-Regression Validation:** crs58 and raquel daily workflows must remain functional. Any regression blocks Epic 2-6 confidence.

3. **Heterogeneous Networking:** Validates nixos ↔ nix-darwin coordination pattern critical for production fleet (4 darwin laptops + 1-2 nixos VPS).

4. **Zerotier Darwin Solution:** Informs Epic 3-6 darwin migrations (blackphos prod in Epic 3, rosegold in Epic 4, argentum in Epic 5). Solving once in Story 1.12 saves 6-9 hours in Epic 3-6.

5. **Story 1.11 Necessity Assessment:** Deployment experience informs type-safe architecture decision (GO/MODIFY/SKIP). Prevents premature optimization.

6. **GO/NO-GO Decision Input:** Story 1.14 GO/NO-GO decision requires heterogeneous networking validation. Story 1.12 provides critical evidence.

---

## Acceptance Criteria

### A. Blackphos Deployment to Physical Hardware

**Target:** Deploy configuration to actual blackphos laptop hardware, validate zero regressions.

**Implementation:**

1. Pre-deployment validation:
   ```bash
   # Verify configuration builds successfully
   cd ~/projects/nix-workspace/test-clan
   nix build .#darwinConfigurations.blackphos.system

   # Verify home-manager configurations build
   nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
   nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage
   ```

2. Deploy to blackphos hardware:
   ```bash
   # On blackphos laptop
   cd ~/projects/nix-workspace/test-clan
   darwin-rebuild switch --flake .#blackphos
   ```

3. Post-deployment validation:
   - System boots successfully
   - All services start without errors
   - No activation script failures
   - System state matches expected configuration

4. User workflow validation (crs58):
   - LazyVim opens successfully (`nvim`)
   - Git signing works (`git commit -S -m "test"`)
   - Claude Code launches (`cc`)
   - tmux starts with catppuccin theme (`tmux`)
   - ccstatusline displays correctly (Claude Code status line)
   - MCP servers accessible (API keys loaded)
   - Atuin history syncs (`atuin sync`)

5. User workflow validation (raquel):
   - LazyVim opens successfully
   - Git configuration correct
   - Shell environment functional (zsh, starship)
   - tmux starts with catppuccin theme
   - Development tools accessible

6. Zero-regression checklist:
   - All homebrew casks installed and functional
   - TouchID sudo authentication works
   - SSH keys loaded correctly
   - sops-nix secrets decrypted to /run/secrets/
   - Environment variables set correctly
   - All 122 crs58 packages present
   - All 105 raquel packages present

**Pass Criteria:**
- `darwin-rebuild switch --flake .#blackphos` succeeds without errors
- All crs58 daily workflows functional (LazyVim, git signing, Claude Code, tmux, atuin)
- All raquel daily workflows functional (LazyVim, shell, development tools)
- Zero regressions from pre-deployment state
- Performance acceptable (no slowdowns, no freezes)
- sops-nix secrets decrypted and accessible

**Estimated effort:** 1-2 hours (deployment, validation, regression testing)

---

### B. Zerotier Peer Configuration (INVESTIGATION REQUIRED)

**Target:** Configure zerotier on blackphos (darwin) and join test-clan network as peer.

**Critical Constraint:** nix-darwin has NO native zerotier module (verified).

**Investigation Required:**

Research and implement ONE approach from these options:

**Option A: Homebrew Cask (RECOMMENDED for Story 1.12)**

Implementation:
```nix
# modules/machines/darwin/blackphos/default.nix
homebrew.casks = [
  # ... existing casks ...
  "zerotier-one"
];
```

Manual join (non-declarative):
```bash
# After homebrew activation
sudo zerotier-cli join db4344343b14b903
```

Verification:
```bash
sudo zerotier-cli listnetworks
# Expected: db4344343b14b903 (cinnabar network)
sudo zerotier-cli peers
# Expected: cinnabar + electrum in peer list
```

**Option B: Custom Launchd Service**

Implementation:
```nix
# modules/machines/darwin/blackphos/zerotier.nix
{ config, pkgs, lib, ... }:
{
  environment.systemPackages = [ pkgs.zerotierone ];

  launchd.daemons.zerotier-one = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.zerotierone}/bin/zerotier-one"
        "-p9993"
        "db4344343b14b903"  # Auto-join network
      ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}
```

Pros: Declarative configuration, nix-native
Cons: Custom module development, requires launchd expertise

**Option C: Manual Installation**

Implementation:
```nix
environment.systemPackages = [ pkgs.zerotierone ];
```

Manual service management:
```bash
# User manages zerotier-one startup via launchctl
# NOT RECOMMENDED: defeats nix benefits
```

**Implementation Decision:**

For Story 1.12, implement **Option A (homebrew cask)** FIRST.

**Rationale:**
- Simple installation (blackphos already uses homebrew for 8 casks)
- Well-maintained zerotier-one cask
- Standard macOS UX (users familiar with zerotier GUI)
- Lowest risk for first physical deployment
- Manual join documented clearly for Epic 3-6 reuse

**Documentation Required:**

1. Approach chosen (A, B, or C)
2. Configuration code added
3. Manual steps required (if any)
4. Platform-specific challenges encountered
5. Potential improvements for Epic 3-6 darwin migrations
6. Whether custom nix-darwin module is worth developing

**Pass Criteria:**
- Zerotier service running on blackphos
- Blackphos joined network db4344343b14b903
- Blackphos visible in cinnabar controller peer list
- Approach documented in dev notes with rationale
- Manual steps (if any) clearly documented
- Platform challenges captured for Epic 3-6 planning

**Estimated effort:** 2-3 hours (research, implementation, testing, documentation)

---

### C. Heterogeneous Network Validation

**Target:** Validate 3-machine zerotier network operational (cinnabar + electrum + blackphos) with nixos ↔ nix-darwin connectivity.

**Network Topology:**

```
cinnabar (nixos VPS, controller)
  ↕ zerotier network db4344343b14b903
electrum (nixos VPS, peer)
  ↕
blackphos (darwin laptop, peer) [NEW in Story 1.12]
```

**Implementation:**

1. Verify blackphos peer registration:
   ```bash
   # On cinnabar (controller)
   sudo zerotier-cli listnetworks
   # Expected: db4344343b14b903 with 3 members

   sudo zerotier-cli peers
   # Expected: electrum + blackphos in peer list
   ```

2. Get zerotier IPs:
   ```bash
   # On cinnabar
   ip addr show zt0
   # Expected: 10.147.x.x (example IP)

   # On electrum
   ip addr show zt0
   # Expected: 10.147.y.y (example IP)

   # On blackphos (darwin)
   ifconfig feth0
   # Expected: 10.147.z.z (example IP)
   # Note: darwin uses feth0 interface, not zt0
   ```

3. Test bidirectional connectivity (blackphos → nixos):
   ```bash
   # On blackphos
   ping -c 5 <cinnabar-zt-ip>
   # Expected: 5 packets transmitted, 5 received, <50ms typical

   ping -c 5 <electrum-zt-ip>
   # Expected: 5 packets transmitted, 5 received, <50ms typical
   ```

4. Test bidirectional connectivity (nixos → blackphos):
   ```bash
   # On cinnabar
   ping -c 5 <blackphos-zt-ip>
   # Expected: 5 packets transmitted, 5 received, <50ms typical

   # On electrum
   ping -c 5 <blackphos-zt-ip>
   # Expected: 5 packets transmitted, 5 received, <50ms typical
   ```

5. Measure network latency:
   ```bash
   # On blackphos
   ping -c 20 <cinnabar-zt-ip> | tail -1
   # Expected: avg latency <50ms (acceptable for coordination)

   ping -c 20 <electrum-zt-ip> | tail -1
   # Expected: avg latency <50ms
   ```

6. Test network stability:
   ```bash
   # Leave ping running for 5 minutes
   ping <cinnabar-zt-ip>
   # Expected: 0% packet loss, stable latency
   ```

**Pass Criteria:**
- 3-machine network operational (cinnabar + electrum + blackphos)
- Blackphos can ping both nixos VMs via zerotier IPs
- Both nixos VMs can ping blackphos via zerotier IP
- Network latency <50ms typical (acceptable for coordination)
- 0% packet loss over 5-minute stability test
- Interface names documented (zt0 on nixos, feth0 on darwin)
- Heterogeneous networking proven (nixos ↔ nix-darwin works)

**Estimated effort:** 30 minutes (network validation, latency measurement)

---

### D. Cross-Platform SSH Validation

**Target:** Validate SSH connectivity across heterogeneous network using clan-managed SSH keys.

**Implementation:**

1. SSH from blackphos to cinnabar:
   ```bash
   # On blackphos
   ssh cameron@<cinnabar-zt-ip>
   # Expected: Login succeeds, certificate-based authentication

   # Verify clan vars loaded
   whoami
   # Expected: cameron

   # Verify home directory
   pwd
   # Expected: /home/cameron
   ```

2. SSH from blackphos to electrum:
   ```bash
   # On blackphos
   ssh testuser@<electrum-zt-ip>
   # Expected: Login succeeds, certificate-based authentication

   # Verify user environment
   whoami
   # Expected: testuser
   ```

3. SSH from cinnabar to blackphos:
   ```bash
   # On cinnabar
   ssh crs58@<blackphos-zt-ip>
   # Expected: Login succeeds, certificate-based authentication

   # Verify darwin environment
   uname -s
   # Expected: Darwin

   # Verify home directory
   pwd
   # Expected: /Users/crs58
   ```

4. SSH from electrum to blackphos:
   ```bash
   # On electrum
   ssh crs58@<blackphos-zt-ip>
   # Expected: Login succeeds
   ```

5. Test SSH as raquel (blackphos second user):
   ```bash
   # On cinnabar
   ssh raquel@<blackphos-zt-ip>
   # Expected: Login succeeds, certificate-based authentication

   # Verify user environment
   whoami
   # Expected: raquel

   pwd
   # Expected: /Users/raquel
   ```

6. Verify clan-managed SSH keys functional:
   ```bash
   # On blackphos
   ls -la ~/.ssh/
   # Expected: id_ed25519 (from sops-nix), authorized_keys (from config)

   # Verify host keys
   ls -la /etc/ssh/
   # Expected: ssh_host_* keys (darwin location)
   ```

**Pass Criteria:**
- SSH from blackphos → cinnabar/electrum works (both directions)
- SSH from cinnabar/electrum → blackphos works (both directions)
- Certificate-based authentication functional across platforms
- Clan-managed SSH keys operational (sops-nix on darwin)
- Both crs58 and raquel SSH access validated
- No password prompts (key-based authentication only)

**Estimated effort:** 30 minutes (SSH testing, key verification)

---

### E. Clan Vars/Secrets Validation on Darwin

**Target:** Verify clan vars and sops-nix secrets work correctly on darwin platform.

**Implementation:**

1. Verify /run/secrets/ directory (darwin location):
   ```bash
   # On blackphos (as crs58)
   ls -la /run/secrets/
   # Expected: Directory exists with proper permissions

   # Verify user secrets present
   ls -la /run/secrets/crs58/
   # Expected: git-signing-key, ssh-private-key, github-api-token, etc.
   ```

2. Check secrets permissions (darwin-compatible):
   ```bash
   # On blackphos
   stat -f "%Sp %u:%g" /run/secrets/crs58/git-signing-key
   # Expected: 0400 (read-only by owner), owned by crs58 UID

   stat -f "%Sp %u:%g" /run/secrets/crs58/ssh-private-key
   # Expected: 0400, owned by crs58 UID
   ```

3. Verify secrets accessible to user processes:
   ```bash
   # On blackphos (as crs58)
   cat /run/secrets/crs58/git-signing-key | head -1
   # Expected: -----BEGIN OPENSSH PRIVATE KEY----- (example output only) # gitleaks:allow

   # Verify git signing uses secret
   git config --get user.signingkey
   # Expected: /run/secrets/crs58/git-signing-key
   ```

4. Verify SSH host keys functional:
   ```bash
   # On blackphos
   sudo ls -la /etc/ssh/ssh_host_*
   # Expected: ssh_host_ed25519_key (from clan vars or sops-nix)

   # Verify sshd uses keys
   sudo launchctl list | grep ssh
   # Expected: org.openssh.sshd running
   ```

5. Verify multi-user secrets (crs58 + raquel):
   ```bash
   # On blackphos
   ls -la /run/secrets/crs58/
   # Expected: crs58 secrets present

   ls -la /run/secrets/raquel/
   # Expected: raquel secrets present (git-signing-key, ssh-private-key)

   # Verify permissions separation
   stat -f "%u" /run/secrets/crs58/git-signing-key
   # Expected: 550 (crs58 UID)

   stat -f "%u" /run/secrets/raquel/git-signing-key
   # Expected: 551 (raquel UID)
   ```

6. Verify sops.templates functional on darwin:
   ```bash
   # On blackphos (as crs58)
   cat ~/.ssh/allowed_signers
   # Expected: Multi-line template with crs58 SSH public keys

   cat ~/.config/gh/hosts.yml
   # Expected: GitHub token from secret
   ```

7. Test secret rotation (age key management):
   ```bash
   # On blackphos
   ls -la ~/.config/sops/age/keys.txt
   # Expected: Age private key present, 0400 permissions

   # Verify key works with sops
   cd ~/projects/nix-workspace/test-clan
   sops secrets/crs58/default.yaml
   # Expected: File decrypts successfully, shows secrets
   ```

**Pass Criteria:**
- /run/secrets/ populated with proper permissions (darwin-compatible)
- SSH host keys functional (sshd starts successfully)
- User secrets accessible to crs58 and raquel
- No permission issues on darwin platform
- sops.templates work correctly (allowed_signers, gh hosts.yml)
- Multi-user encryption verified (crs58 + raquel separate namespaces)
- Age key management functional (~/.config/sops/age/keys.txt)
- Secrets rotation possible (sops edit works)

**Estimated effort:** 30 minutes (secrets validation, permissions testing)

---

### F. Integration Findings Documentation

**Target:** Document deployment process, zerotier darwin approach, platform challenges, networking results.

**Documentation Structure:**

Create dev notes section in work item with following content:

**1. Deployment Process Documentation:**

```markdown
## Physical Deployment Process

### Pre-Deployment Checklist
- [ ] Configuration builds successfully (`nix build .#darwinConfigurations.blackphos.system`)
- [ ] Home-manager builds successful (crs58 + raquel)
- [ ] All tests passing (nix flake check)
- [ ] Backup existing /etc configuration (if migrating from old system)

### Deployment Commands
1. `cd ~/projects/nix-workspace/test-clan`
2. `darwin-rebuild switch --flake .#blackphos`
3. Observe activation script output for errors
4. Reboot if kernel extensions loaded (rare on darwin)

### Post-Deployment Validation
- [ ] System boots successfully
- [ ] All services running (launchctl list)
- [ ] Homebrew casks installed
- [ ] TouchID sudo works
- [ ] User workflows functional (crs58 + raquel)

### Manual Steps Required
- [Document any manual steps here]

### Deployment Duration
- Configuration build: [X minutes]
- Activation: [Y minutes]
- Total: [Z minutes]
```

**2. Zerotier Darwin Integration Documentation:**

```markdown
## Zerotier Darwin Integration

### Approach Chosen
[Option A / Option B / Option C]

### Rationale
[Why this approach was selected for Story 1.12]

### Configuration Code
[Nix code added to blackphos configuration]

### Manual Steps Required
[If any - e.g., "sudo zerotier-cli join db4344343b14b903"]

### Verification Commands
[Commands used to verify zerotier operational]

### Platform-Specific Challenges
1. [Challenge 1: Description and resolution]
2. [Challenge 2: Description and resolution]
3. [etc.]

### Interface Naming
- Darwin uses `feth0` (not `zt0` like nixos)
- Verified via: `ifconfig feth0`

### Recommendations for Epic 3-6
[Potential improvements for future darwin migrations]

### Custom Module Development
[Worth developing nix-darwin zerotier module? Yes/No/Maybe, rationale]
```

**3. Platform-Specific Challenges:**

```markdown
## Darwin Platform Challenges

### Secrets Management
- Darwin secrets location: `/run/secrets/` (vs `/var/run/secrets/` on nixos)
- Permissions model: [Any differences from nixos?]
- sops-nix compatibility: [Any darwin-specific issues?]

### Homebrew Integration
- Nix vs homebrew package conflicts: [Any observed?]
- Cask activation timing: [Any issues?]
- Cleanup behavior: [zap vs uninstall differences?]

### System Activation
- darwin-rebuild vs nixos-rebuild differences: [Observed differences]
- Launchd vs systemd: [Service management differences]
- Activation script behavior: [Any darwin-specific quirks?]

### Performance
- Build times: [darwin vs nixos comparison if available]
- Activation duration: [Observed performance]
- Memory usage: [Any concerns?]
```

**4. Heterogeneous Networking Results:**

```markdown
## Heterogeneous Networking Validation

### Network Topology
- cinnabar (nixos VPS, zerotier controller): [zt IP]
- electrum (nixos VPS, zerotier peer): [zt IP]
- blackphos (darwin laptop, zerotier peer): [zt IP]

### Connectivity Matrix

| Source | Target | Protocol | Result | Latency |
|--------|--------|----------|--------|---------|
| blackphos | cinnabar | zerotier | ✅/❌ | X ms |
| blackphos | electrum | zerotier | ✅/❌ | X ms |
| cinnabar | blackphos | zerotier | ✅/❌ | X ms |
| electrum | blackphos | zerotier | ✅/❌ | X ms |

### SSH Connectivity

| Source | Target | User | Result | Notes |
|--------|--------|------|--------|-------|
| blackphos | cinnabar | cameron | ✅/❌ | [any issues?] |
| blackphos | electrum | testuser | ✅/❌ | [any issues?] |
| cinnabar | blackphos | crs58 | ✅/❌ | [any issues?] |
| cinnabar | blackphos | raquel | ✅/❌ | [any issues?] |
| electrum | blackphos | crs58 | ✅/❌ | [any issues?] |

### Network Stability
- Packet loss: [%]
- Latency stability: [stable / variable]
- 5-minute test results: [summary]

### Platform Differences Observed
- Interface naming: zt0 (nixos) vs feth0 (darwin)
- [Other differences observed]

### Reliability Assessment
- Production-ready: Yes/No
- Concerns: [Any reliability concerns?]
- Recommendations: [For production deployment]
```

**5. Epic 2-6 Migration Guidance:**

```markdown
## Epic 2-6 Migration Value

### Patterns Validated
1. Physical darwin deployment process
2. Zero-regression validation checklist
3. Zerotier darwin integration approach
4. Heterogeneous networking pattern

### Time Savings Estimate
- Epic 3 (blackphos prod): [X hours saved via Story 1.12 learnings]
- Epic 4 (rosegold): [Y hours saved]
- Epic 5 (argentum): [Z hours saved]
- Total: [A-B hours saved across Epic 3-6]

### Reusable Artifacts
1. Zerotier darwin configuration code
2. Zero-regression validation checklist
3. Platform-specific workarounds documentation
4. SSH cross-platform validation process

### Gotchas Documented
1. [Gotcha 1 and workaround]
2. [Gotcha 2 and workaround]
3. [etc.]

### Recommended Improvements
1. [Improvement 1 for Epic 3-6]
2. [Improvement 2 for Epic 3-6]
3. [etc.]
```

**Pass Criteria:**
- All 5 documentation sections complete
- Deployment process documented with commands and timing
- Zerotier darwin approach documented with rationale
- Platform-specific challenges captured with resolutions
- Heterogeneous networking results documented with connectivity matrix
- Epic 2-6 migration value articulated with time savings estimate
- Manual steps (if any) clearly documented
- Gotchas and workarounds captured for future reference

**Estimated effort:** 30 minutes (documentation writing, consolidation)

---

## Task Groups

### Task Group 1: Pre-Deployment Preparation and Validation

**Objective:** Ensure blackphos configuration is production-ready before physical deployment.

**Tasks:**

1. **Verify Configuration Builds:**
   ```bash
   cd ~/projects/nix-workspace/test-clan
   nix build .#darwinConfigurations.blackphos.system
   # Expected: Build succeeds, result symlink created
   ```

2. **Verify Home-Manager Builds:**
   ```bash
   nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
   nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage
   # Expected: Both builds succeed
   ```

3. **Run Test Suite:**
   ```bash
   nix flake check
   # Expected: All tests pass
   ```

4. **Review Configuration for Darwin-Specific Issues:**
   - Check launchd services configured correctly
   - Verify homebrew casks list complete
   - Confirm TouchID sudo enabled
   - Review user UIDs (550, 551) match expectations

5. **Document Pre-Deployment State:**
   - Current blackphos configuration (if migrating from old system)
   - Backup strategy (if needed)
   - Rollback plan (if deployment fails)

**Validation Gates:**
- [ ] darwinConfigurations.blackphos.system builds successfully
- [ ] crs58 home-manager builds successfully (122 derivations)
- [ ] raquel home-manager builds successfully (105 derivations)
- [ ] All tests passing (nix flake check)
- [ ] Configuration reviewed for platform-specific issues
- [ ] Pre-deployment state documented

**Estimated effort:** 30 minutes

---

### Task Group 2: Physical Deployment to Blackphos Hardware

**Objective:** Deploy configuration to physical blackphos laptop and validate zero regressions.

**Tasks:**

1. **Execute Deployment:**
   ```bash
   # On blackphos laptop
   cd ~/projects/nix-workspace/test-clan
   darwin-rebuild switch --flake .#blackphos
   ```

   Observe:
   - Activation script output
   - Any error messages
   - Service start confirmations
   - Deployment duration

2. **Post-Deployment System Validation:**
   ```bash
   # Verify system state
   darwin-rebuild --version
   # Expected: nix-darwin version displayed

   # Verify hostname
   hostname
   # Expected: blackphos

   # Verify platform
   uname -m
   # Expected: arm64
   ```

3. **Service Validation:**
   ```bash
   # List running launchd services
   launchctl list | grep -E "(homebrew|nix|sshd)"
   # Expected: Key services running

   # Verify homebrew activation
   brew list --cask
   # Expected: All 8 casks installed
   ```

4. **Zero-Regression Validation (crs58):**

   **LazyVim:**
   ```bash
   nvim --version
   # Expected: Neovim v0.10.x with LazyVim config

   nvim test.txt
   # Expected: LazyVim UI loads, plugins functional
   ```

   **Git Signing:**
   ```bash
   git config --get user.signingkey
   # Expected: /run/secrets/crs58/git-signing-key

   cd /tmp && git init test-repo && cd test-repo
   git commit --allow-empty -S -m "test signing"
   # Expected: Commit succeeds with GPG signature
   ```

   **Claude Code:**
   ```bash
   cc --version
   # Expected: Claude Code version displayed

   # Verify ccstatusline integration
   cc # Launch Claude Code
   # Expected: Status line displays with ccstatusline formatting
   ```

   **Tmux + Catppuccin:**
   ```bash
   tmux new-session -d -s test
   tmux list-sessions
   # Expected: test session listed

   tmux attach -t test
   # Expected: Catppuccin theme applied (visual verification)
   tmux kill-session -t test
   ```

   **Atuin:**
   ```bash
   atuin status
   # Expected: Atuin configured, sync status displayed

   atuin sync
   # Expected: Sync succeeds (or reports no changes)
   ```

5. **Zero-Regression Validation (raquel):**

   Switch to raquel user:
   ```bash
   su - raquel
   ```

   **LazyVim:**
   ```bash
   nvim --version
   # Expected: Neovim v0.10.x with LazyVim config
   ```

   **Git Configuration:**
   ```bash
   git config --get user.name
   # Expected: Raquel Smith (or configured name)

   git config --get user.email
   # Expected: raquel's email from config
   ```

   **Shell Environment:**
   ```bash
   echo $SHELL
   # Expected: /run/current-system/sw/bin/zsh

   starship --version
   # Expected: Starship prompt version displayed
   ```

   **Tmux:**
   ```bash
   tmux new-session -d -s test
   tmux attach -t test
   # Expected: Catppuccin theme applied
   tmux kill-session -t test
   ```

6. **Secrets Validation:**
   ```bash
   # Verify /run/secrets/ populated
   ls -la /run/secrets/crs58/
   # Expected: git-signing-key, ssh-private-key, github-api-token, etc.

   ls -la /run/secrets/raquel/
   # Expected: raquel's secrets present

   # Check permissions
   stat -f "%Sp %u:%g" /run/secrets/crs58/git-signing-key
   # Expected: 0400, owned by crs58 (UID 550)
   ```

7. **Performance Validation:**
   - System responsiveness: No slowdowns, no freezes
   - Application launch times: Acceptable (LazyVim, Claude Code)
   - Memory usage: Within normal bounds
   - Disk usage: No unexpected growth

8. **Document Deployment Results:**
   - Deployment duration
   - Any errors encountered (and resolutions)
   - Manual steps required (if any)
   - Zero-regression checklist completion

**Validation Gates:**
- [ ] darwin-rebuild switch succeeds without errors
- [ ] All launchd services running
- [ ] All homebrew casks installed
- [ ] crs58 daily workflows functional (LazyVim, git signing, Claude Code, tmux, atuin)
- [ ] raquel daily workflows functional (LazyVim, shell, development tools)
- [ ] sops-nix secrets decrypted and accessible
- [ ] Performance acceptable (no regressions)
- [ ] Deployment results documented

**Estimated effort:** 1-1.5 hours

---

### Task Group 3: Zerotier Darwin Integration

**Objective:** Configure zerotier on blackphos (darwin) and join test-clan network as peer.

**Tasks:**

1. **Research Zerotier Darwin Options:**

   **Option A: Homebrew Cask**
   - Review zerotier-one cask availability: `brew info zerotier-one`
   - Check cask version and maintenance status
   - Understand GUI vs CLI usage

   **Option B: Custom Launchd Service**
   - Review nixpkgs zerotierone package: `nix search nixpkgs zerotier`
   - Research launchd configuration patterns
   - Check nix-darwin launchd.daemons interface

   **Option C: Manual Installation**
   - Understand limitations (non-declarative, not recommended)
   - Document as anti-pattern

2. **Implement Chosen Approach (Recommended: Option A for Story 1.12):**

   **Option A Implementation:**

   Edit `modules/machines/darwin/blackphos/default.nix`:
   ```nix
   homebrew.casks = [
     # ... existing casks ...
     "zerotier-one"
   ];
   ```

   Rebuild configuration:
   ```bash
   darwin-rebuild switch --flake .#blackphos
   ```

   Verify cask installed:
   ```bash
   brew list --cask | grep zerotier
   # Expected: zerotier-one
   ```

   Manual join (non-declarative):
   ```bash
   sudo zerotier-cli join db4344343b14b903
   # Expected: 200 join OK
   ```

   **Alternative: Option B Implementation (if Option A insufficient):**

   Create `modules/machines/darwin/blackphos/zerotier.nix`:
   ```nix
   { config, pkgs, lib, ... }:
   {
     environment.systemPackages = [ pkgs.zerotierone ];

     launchd.daemons.zerotier-one = {
       serviceConfig = {
         ProgramArguments = [
           "${pkgs.zerotierone}/bin/zerotier-one"
           "-p9993"
         ];
         KeepAlive = true;
         RunAtLoad = true;
         StandardOutPath = "/var/log/zerotier-one.log";
         StandardErrorPath = "/var/log/zerotier-one.log";
       };
     };
   }
   ```

   Import in blackphos/default.nix:
   ```nix
   imports = [
     # ... existing imports ...
     ./zerotier.nix
   ];
   ```

   Rebuild and verify:
   ```bash
   darwin-rebuild switch --flake .#blackphos
   launchctl list | grep zerotier
   # Expected: zerotier-one service running
   ```

3. **Verify Zerotier Service Running:**
   ```bash
   # Check service status (Option A - homebrew)
   sudo launchctl list | grep zerotier
   # Expected: com.zerotier.one running

   # OR (Option B - custom module)
   launchctl list | grep zerotier
   # Expected: zerotier-one running
   ```

4. **Join Zerotier Network:**
   ```bash
   sudo zerotier-cli join db4344343b14b903
   # Expected: 200 join OK
   ```

5. **Verify Network Membership:**
   ```bash
   sudo zerotier-cli listnetworks
   # Expected:
   # 200 listnetworks <OK>
   # db4344343b14b903 ... OK PUBLIC

   sudo zerotier-cli peers
   # Expected: cinnabar and electrum in peer list
   ```

6. **Authorize Peer on Controller (if needed):**
   ```bash
   # On cinnabar (controller)
   sudo zerotier-cli listnetworks
   # Expected: db4344343b14b903 with 3 members

   # If blackphos not authorized, authorize via zerotier web UI or CLI
   # (Network configuration may auto-authorize via roles.peer.tags.all)
   ```

7. **Get Blackphos Zerotier IP:**
   ```bash
   # On blackphos (darwin uses feth0 interface, not zt0)
   ifconfig feth0
   # Expected: inet 10.147.x.x (example zerotier IP)

   # Save IP for connectivity tests
   BLACKPHOS_ZT_IP=$(ifconfig feth0 | grep 'inet ' | awk '{print $2}')
   echo $BLACKPHOS_ZT_IP
   ```

8. **Document Zerotier Integration:**
   - Approach chosen (A, B, or C)
   - Configuration code added
   - Manual steps required
   - Platform-specific challenges encountered
   - Interface naming (feth0 vs zt0)
   - Recommendations for Epic 3-6

**Validation Gates:**
- [ ] Zerotier service running on blackphos
- [ ] Blackphos joined network db4344343b14b903
- [ ] Blackphos visible in cinnabar controller peer list
- [ ] Zerotier IP assigned to blackphos (feth0 interface)
- [ ] Approach documented with rationale
- [ ] Manual steps (if any) clearly documented
- [ ] Platform challenges captured

**Estimated effort:** 2-3 hours (research, implementation, testing, documentation)

---

### Task Group 4: Network and Integration Validation

**Objective:** Validate heterogeneous network (nixos ↔ nix-darwin), cross-platform SSH, clan vars/secrets, and document findings.

**Tasks:**

**4.1: Heterogeneous Network Connectivity**

1. **Get Zerotier IPs:**
   ```bash
   # On cinnabar
   CINNABAR_ZT_IP=$(ip addr show zt0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
   echo "cinnabar: $CINNABAR_ZT_IP"

   # On electrum
   ELECTRUM_ZT_IP=$(ip addr show zt0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
   echo "electrum: $ELECTRUM_ZT_IP"

   # On blackphos (darwin)
   BLACKPHOS_ZT_IP=$(ifconfig feth0 | grep 'inet ' | awk '{print $2}')
   echo "blackphos: $BLACKPHOS_ZT_IP"
   ```

2. **Test Bidirectional Connectivity (blackphos → nixos):**
   ```bash
   # On blackphos
   ping -c 5 $CINNABAR_ZT_IP
   # Expected: 5 packets transmitted, 5 received, 0% packet loss
   # Expected latency: <50ms typical

   ping -c 5 $ELECTRUM_ZT_IP
   # Expected: 5 packets transmitted, 5 received, 0% packet loss
   # Expected latency: <50ms typical
   ```

3. **Test Bidirectional Connectivity (nixos → blackphos):**
   ```bash
   # On cinnabar
   ping -c 5 $BLACKPHOS_ZT_IP
   # Expected: 5 packets transmitted, 5 received, 0% packet loss

   # On electrum
   ping -c 5 $BLACKPHOS_ZT_IP
   # Expected: 5 packets transmitted, 5 received, 0% packet loss
   ```

4. **Measure Network Latency:**
   ```bash
   # On blackphos
   ping -c 20 $CINNABAR_ZT_IP | tail -1
   # Expected: avg latency <50ms

   ping -c 20 $ELECTRUM_ZT_IP | tail -1
   # Expected: avg latency <50ms
   ```

5. **Test Network Stability (5-minute test):**
   ```bash
   # On blackphos
   ping -c 300 $CINNABAR_ZT_IP
   # Expected: 0% packet loss, stable latency over 5 minutes
   ```

6. **Document Network Topology:**
   - Create connectivity matrix table
   - Document latency measurements
   - Note any platform differences (feth0 vs zt0)
   - Assess production readiness

**4.2: Cross-Platform SSH Validation**

1. **SSH from blackphos to cinnabar:**
   ```bash
   # On blackphos
   ssh cameron@$CINNABAR_ZT_IP
   # Expected: Login succeeds, certificate-based authentication

   # Verify environment
   whoami
   # Expected: cameron

   pwd
   # Expected: /home/cameron

   exit
   ```

2. **SSH from blackphos to electrum:**
   ```bash
   # On blackphos
   ssh testuser@$ELECTRUM_ZT_IP
   # Expected: Login succeeds

   whoami
   # Expected: testuser

   exit
   ```

3. **SSH from cinnabar to blackphos (crs58):**
   ```bash
   # On cinnabar
   ssh crs58@$BLACKPHOS_ZT_IP
   # Expected: Login succeeds

   # Verify darwin environment
   uname -s
   # Expected: Darwin

   pwd
   # Expected: /Users/crs58

   exit
   ```

4. **SSH from cinnabar to blackphos (raquel):**
   ```bash
   # On cinnabar
   ssh raquel@$BLACKPHOS_ZT_IP
   # Expected: Login succeeds

   whoami
   # Expected: raquel

   pwd
   # Expected: /Users/raquel

   exit
   ```

5. **SSH from electrum to blackphos:**
   ```bash
   # On electrum
   ssh crs58@$BLACKPHOS_ZT_IP
   # Expected: Login succeeds

   exit
   ```

6. **Verify Clan-Managed SSH Keys:**
   ```bash
   # On blackphos (crs58)
   ls -la ~/.ssh/
   # Expected: id_ed25519 (from sops-nix), authorized_keys (from config)

   # Verify host keys
   sudo ls -la /etc/ssh/ssh_host_*
   # Expected: ssh_host_ed25519_key (darwin location)
   ```

7. **Document SSH Results:**
   - Create SSH connectivity matrix table
   - Note authentication method (certificate-based)
   - Document any platform differences
   - Verify both users (crs58 + raquel) work

**4.3: Clan Vars/Secrets Validation on Darwin**

1. **Verify /run/secrets/ Directory:**
   ```bash
   # On blackphos (as crs58)
   ls -la /run/secrets/
   # Expected: Directory exists with proper permissions

   ls -la /run/secrets/crs58/
   # Expected: git-signing-key, ssh-private-key, github-api-token, anthropic-api-key, openai-api-key, etc.

   ls -la /run/secrets/raquel/
   # Expected: raquel's secrets (git-signing-key, ssh-private-key)
   ```

2. **Check Secrets Permissions (Darwin-Compatible):**
   ```bash
   # On blackphos
   stat -f "%Sp %u:%g" /run/secrets/crs58/git-signing-key
   # Expected: 0400 (read-only by owner), owned by crs58 UID (550)

   stat -f "%Sp %u:%g" /run/secrets/raquel/git-signing-key
   # Expected: 0400, owned by raquel UID (551)
   ```

3. **Verify Secrets Accessible to User Processes:**
   ```bash
   # On blackphos (as crs58)
   cat /run/secrets/crs58/git-signing-key | head -1
   # Expected: -----BEGIN OPENSSH PRIVATE KEY----- (example output only) # gitleaks:allow

   # Verify git signing uses secret
   git config --get user.signingkey
   # Expected: /run/secrets/crs58/git-signing-key

   # Test git signing
   cd /tmp && git init test-repo && cd test-repo
   git commit --allow-empty -S -m "test signing"
   # Expected: Commit succeeds with signature
   ```

4. **Verify SSH Host Keys Functional:**
   ```bash
   # On blackphos
   sudo ls -la /etc/ssh/ssh_host_*
   # Expected: ssh_host_ed25519_key present

   # Verify sshd running
   sudo launchctl list | grep ssh
   # Expected: com.openssh.sshd running
   ```

5. **Verify sops.templates Functional on Darwin:**
   ```bash
   # On blackphos (as crs58)
   cat ~/.ssh/allowed_signers
   # Expected: Multi-line template with crs58 SSH public keys
   # Example:
   # crs58 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+
   # crs58 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+
   # (... additional keys ...)

   cat ~/.config/gh/hosts.yml
   # Expected: GitHub token from secret
   # Example:
   # github.com:
   #   oauth_token: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   #   user: cameronraysmith
   ```

6. **Test Secret Rotation (Age Key Management):**
   ```bash
   # On blackphos
   ls -la ~/.config/sops/age/keys.txt
   # Expected: Age private key present, 0400 permissions

   # Verify key works with sops
   cd ~/projects/nix-workspace/test-clan
   sops secrets/crs58/default.yaml
   # Expected: File decrypts successfully, shows secrets in editor
   ```

7. **Verify Multi-User Encryption:**
   ```bash
   # On blackphos
   # crs58 should be able to decrypt crs58 secrets
   sops secrets/crs58/default.yaml
   # Expected: Success

   # crs58 should NOT be able to decrypt raquel secrets (different age key)
   sops secrets/raquel/default.yaml
   # Expected: Error (not authorized)

   # Switch to raquel
   su - raquel

   # raquel should be able to decrypt raquel secrets
   cd ~/projects/nix-workspace/test-clan
   sops secrets/raquel/default.yaml
   # Expected: Success
   ```

8. **Document Secrets Validation Results:**
   - /run/secrets/ location confirmed (darwin-compatible)
   - Permissions model validated (0400, user-owned)
   - sops.templates working (allowed_signers, gh hosts.yml)
   - Multi-user encryption verified
   - Age key management functional
   - Any platform differences documented

**4.4: Integration Findings Documentation**

1. **Create Dev Notes Section:**

   Populate AC F documentation structure with actual results:

   **Section 1: Physical Deployment Process**
   - Pre-deployment checklist completion
   - Deployment commands executed
   - Deployment duration (build + activation)
   - Post-deployment validation results
   - Manual steps required (if any)
   - Any errors encountered and resolutions

   **Section 2: Zerotier Darwin Integration**
   - Approach chosen (A/B/C) with rationale
   - Configuration code added
   - Manual steps required (if any)
   - Verification commands used
   - Platform-specific challenges and resolutions
   - Interface naming (feth0 vs zt0)
   - Recommendations for Epic 3-6
   - Custom module development assessment

   **Section 3: Platform-Specific Challenges**
   - Secrets management (location, permissions, sops-nix compatibility)
   - Homebrew integration (conflicts, activation, cleanup)
   - System activation (darwin-rebuild vs nixos-rebuild differences)
   - Performance (build times, activation duration, memory usage)

   **Section 4: Heterogeneous Networking Results**
   - Network topology with IPs
   - Connectivity matrix (all 6 paths tested)
   - SSH connectivity matrix (5 user combinations tested)
   - Network stability results (latency, packet loss)
   - Platform differences observed
   - Reliability assessment (production-ready?)

   **Section 5: Epic 2-6 Migration Value**
   - Patterns validated (deployment, validation, networking)
   - Time savings estimate (across Epic 3-6 darwin migrations)
   - Reusable artifacts (code, checklists, documentation)
   - Gotchas documented with workarounds
   - Recommended improvements for future migrations

2. **Review Documentation Completeness:**
   - [ ] All 5 sections complete
   - [ ] Deployment process documented with actual results
   - [ ] Zerotier darwin approach documented with rationale
   - [ ] Platform-specific challenges captured with resolutions
   - [ ] Heterogeneous networking results with connectivity matrices
   - [ ] Epic 2-6 migration value articulated with time savings

**Validation Gates:**
- [ ] 3-machine network operational (cinnabar + electrum + blackphos)
- [ ] Bidirectional connectivity validated (6 paths: blackphos→cinnabar, blackphos→electrum, cinnabar→blackphos, electrum→blackphos, and vice versa)
- [ ] Network latency <50ms typical, 0% packet loss
- [ ] SSH works from blackphos to nixos VMs (cameron@cinnabar, testuser@electrum)
- [ ] SSH works from nixos VMs to blackphos (crs58, raquel)
- [ ] Certificate-based authentication functional
- [ ] Clan-managed SSH keys operational
- [ ] /run/secrets/ populated with proper permissions on darwin
- [ ] sops-nix secrets accessible (crs58 + raquel)
- [ ] sops.templates functional (allowed_signers, gh hosts.yml)
- [ ] Multi-user encryption verified
- [ ] All 5 documentation sections complete
- [ ] Integration findings documented with empirical evidence

**Estimated effort:** 1.5-2 hours (connectivity testing, SSH validation, secrets verification, documentation)

---

## Quality Gates

### Quality Gate 1: Configuration Build Quality

**Target:** Verify blackphos configuration builds successfully with zero errors.

**Validation:**
```bash
cd ~/projects/nix-workspace/test-clan
nix build .#darwinConfigurations.blackphos.system --show-trace
# Expected: Build succeeds, no warnings, no evaluation errors

nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
# Expected: Build succeeds, 122 derivations

nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage
# Expected: Build succeeds, 105 derivations
```

**Pass Criteria:**
- All 3 builds succeed without errors
- No evaluation warnings
- Package counts match expectations (122 crs58, 105 raquel)
- Build reproducibility (multiple builds produce identical results)

---

### Quality Gate 2: Physical Deployment Success

**Target:** Physical deployment to blackphos hardware succeeds without errors.

**Validation:**
```bash
# On blackphos
darwin-rebuild switch --flake .#blackphos
# Expected: Activation succeeds, all services start, no errors
```

**Pass Criteria:**
- darwin-rebuild switch succeeds
- All launchd services start successfully
- All homebrew casks installed
- TouchID sudo works
- sops-nix secrets decrypted to /run/secrets/
- System boots successfully after deployment
- No activation script failures

---

### Quality Gate 3: Zero-Regression Validation

**Target:** All pre-deployment functionality preserved, no regressions.

**Validation:**

**crs58 workflows:**
- LazyVim opens and loads plugins successfully
- Git signing works (commit with -S flag succeeds)
- Claude Code launches with ccstatusline integration
- tmux starts with catppuccin theme
- Atuin history syncs successfully
- MCP servers accessible (API keys loaded)
- All 122 packages present in environment

**raquel workflows:**
- LazyVim opens successfully
- Git configuration correct
- Shell environment functional (zsh, starship)
- tmux starts with catppuccin theme
- Development tools accessible
- All 105 packages present in environment

**Pass Criteria:**
- All crs58 daily workflows functional (6/6 checks pass)
- All raquel daily workflows functional (5/5 checks pass)
- Zero regressions from pre-deployment state
- Performance acceptable (no slowdowns, no freezes)
- All expected packages present (package count match)

---

### Quality Gate 4: Heterogeneous Network Operational

**Target:** 3-machine zerotier network operational with nixos ↔ nix-darwin connectivity.

**Validation:**
```bash
# On blackphos
ping -c 10 $CINNABAR_ZT_IP
# Expected: 0% packet loss, <50ms latency

ping -c 10 $ELECTRUM_ZT_IP
# Expected: 0% packet loss, <50ms latency

# On cinnabar
ping -c 10 $BLACKPHOS_ZT_IP
# Expected: 0% packet loss, <50ms latency

# On electrum
ping -c 10 $BLACKPHOS_ZT_IP
# Expected: 0% packet loss, <50ms latency
```

**Pass Criteria:**
- 3-machine network operational (cinnabar + electrum + blackphos)
- Bidirectional connectivity validated (all 4 paths successful)
- Network latency <50ms typical
- 0% packet loss over 5-minute stability test
- SSH works across all platforms (6 user combinations)
- Certificate-based authentication functional
- Heterogeneous networking proven (nixos ↔ nix-darwin works)

---

### Quality Gate 5: Documentation Completeness

**Target:** Integration findings documented comprehensively for Epic 2-6 reuse.

**Validation:**

Review documentation sections in AC F dev notes:
- [ ] Physical deployment process documented with commands and timing
- [ ] Zerotier darwin approach documented with rationale and code
- [ ] Platform-specific challenges captured with resolutions
- [ ] Heterogeneous networking results documented with connectivity matrices
- [ ] Epic 2-6 migration value articulated with time savings estimate
- [ ] Manual steps (if any) clearly documented
- [ ] Gotchas and workarounds captured

**Pass Criteria:**
- All 5 documentation sections complete
- Deployment process includes actual commands used
- Zerotier darwin approach includes rationale and configuration code
- Platform challenges include specific resolutions
- Networking results include connectivity and SSH matrices
- Epic 2-6 value includes time savings estimate
- Documentation quality sufficient for Epic 3-6 teams to replicate

---

## Success Criteria

**Story 1.12 is DONE when:**

1. ✅ **AC A:** Blackphos deployed to physical hardware, zero regressions validated
2. ✅ **AC B:** Zerotier configured on darwin, blackphos joined network as peer
3. ✅ **AC C:** 3-machine heterogeneous network operational (cinnabar + electrum + blackphos)
4. ✅ **AC D:** Cross-platform SSH validated (nixos ↔ darwin, all user combinations)
5. ✅ **AC E:** Clan vars/secrets validated on darwin (/run/secrets/, sops-nix functional)
6. ✅ **AC F:** Integration findings documented (deployment, zerotier, networking, challenges, Epic 2-6 value)

**All 5 Quality Gates PASS:**
- Configuration builds successfully
- Physical deployment succeeds
- Zero regressions validated
- Heterogeneous network operational
- Documentation complete

**Strategic Outcomes Achieved:**
- First physical hardware deployment validated
- Configuration completeness proven on real darwin hardware
- Zerotier darwin integration solution discovered and documented
- Heterogeneous networking validated (nixos ↔ nix-darwin proven pattern)
- Zero-regression validation checklist created for Epic 2-6
- Story 1.11 necessity assessment data collected (deployment experience)
- Epic 2-6 darwin deployment pattern validated empirically

---

## Story 1.11 Necessity Assessment Framework

**Context:** Story 1.11 (type-safe home-manager architecture) deferred pending Story 1.12 empirical evidence (Party Mode decision 2025-11-16).

**Assessment Checkpoint:** After Story 1.12 completion, evaluate Story 1.11 necessity using evidence from physical deployment experience.

**Evidence Collection During Story 1.12:**

1. **Typos/Errors Encountered:**
   - Were there typos in configuration files caught only at runtime?
   - Did deployment reveal evaluation errors not caught at build time?
   - Would type checking have prevented issues?

2. **Machine-Specific Configuration Needs:**
   - Did blackphos require machine-specific home-manager configs?
   - Would homeHosts pattern improve machine-specific configuration?
   - Are current platform conditionals (pkgs.stdenv.isDarwin) sufficient?

3. **Multi-User Configuration Complexity:**
   - Did crs58 + raquel configuration management reveal complexity?
   - Would type-safe user configuration improve maintainability?
   - Are current portable modules (users/crs58, users/raquel) sufficient?

4. **Pattern Elegance:**
   - Is current architecture (Pattern A + sops-nix + portable modules) elegant?
   - Does homeHosts pattern add value or unnecessary complexity?
   - Would type-safe architecture improve dendritic patterns?

5. **Epic 2-6 Scaling Concerns:**
   - Will current architecture scale to 6 machines × 4+ users?
   - Are type safety benefits worth refactoring effort?
   - What Epic 2-6 time savings would type-safe architecture provide?

**Decision Criteria (from Epic lines 1894-1914):**

**GO (execute Story 1.11 before Story 1.14):**
- Deployment revealed 2+ typos/errors that type checking would prevent
- Machine-specific configs needed and homeHosts pattern improves them
- Multi-user complexity suggests type-safe architecture benefits
- Epic 2-6 scaling concerns justify 10-16h refactoring investment
- Type-safe architecture improves dendritic patterns significantly

**MODIFY (partial implementation):**
- Some Story 1.11 elements valuable (CI type checks) but not full homeHosts
- Type safety desirable but homeHosts complexity not justified
- Hybrid approach: type validation without architectural refactoring

**SKIP (permanent deferral):**
- Zero issues encountered during deployment
- Current architecture (Pattern A + sops-nix + portable modules) elegant and maintainable
- No machine-specific configs needed beyond platform conditionals
- Multi-user configuration manageable with current patterns
- homeHosts adds unnecessary complexity for 6 machines × 4 users
- Epic 2-6 teams confident in current architecture

**Assessment Process:**

1. Complete Story 1.12 (all 6 ACs satisfied)
2. Collect evidence using framework above
3. Document findings in Story 1.12 dev notes
4. Schedule Party Mode assessment (Story 1.13 documentation phase)
5. Party Mode evaluates evidence using decision criteria
6. Decision outcome documented in Story 1.13
7. If GO/MODIFY: Execute Story 1.11 before Story 1.14 GO/NO-GO
8. If SKIP: Proceed directly to Story 1.13 → Story 1.14 GO/NO-GO

**Current Hypothesis (pre-deployment):**

Party Mode team leans toward **SKIP** (permanent deferral) based on:
- Current architecture proven at scale (270 pkgs, 17 modules, 4+ users)
- All builds passing, zero regressions across 5 stories (1.10BA-1.10E)
- Pattern A + sops-nix + portable modules elegant and maintainable
- Type-safe architecture complexity not justified for 6 machines × 4 users
- Epic 2-6 timeline benefits from skipping 10-16h refactoring

**Story 1.12 provides empirical evidence to validate or refute this hypothesis.**

---

## Development Notes

### Implementation Log

**[To be populated during Story 1.12 execution]**

**Pre-Deployment (Task Group 1):**
- Configuration build results:
- Home-manager build results:
- Test suite results:
- Pre-deployment state documented:

**Physical Deployment (Task Group 2):**
- Deployment command executed:
- Deployment duration:
- Activation script output:
- Any errors encountered:
- Post-deployment validation results:
- Zero-regression checklist completion:

**Zerotier Integration (Task Group 3):**
- Research findings:
- Approach chosen (A/B/C):
- Rationale for approach:
- Configuration code added:
- Manual steps required:
- Verification results:
- Platform-specific challenges:
- Recommendations for Epic 3-6:

**Network/Integration Validation (Task Group 4):**
- Zerotier IPs assigned:
- Connectivity test results:
- SSH test results:
- Secrets validation results:
- Network stability results:
- Documentation sections completed:

**Quality Gates:**
- QG1 (Configuration Build): PASS/FAIL
- QG2 (Physical Deployment): PASS/FAIL
- QG3 (Zero-Regression): PASS/FAIL
- QG4 (Heterogeneous Network): PASS/FAIL
- QG5 (Documentation): PASS/FAIL

---

### Zerotier Darwin Integration Deep Dive

**[To be populated during AC B implementation]**

**Option A: Homebrew Cask (RECOMMENDED for Story 1.12)**

**Pros:**
- Simple installation (blackphos already uses homebrew)
- Well-maintained zerotier-one cask (official zerotier release)
- Standard macOS UX (GUI + menubar icon)
- Familiar to macOS users
- Auto-updates via homebrew onActivation.autoUpdate
- Lowest risk for first physical deployment

**Cons:**
- Manual join required (non-declarative): `sudo zerotier-cli join <network-id>`
- Not fully nix-managed (homebrew dependency)
- Network membership not in configuration files
- Manual step for each deployment (requires documentation)
- Homebrew cleanup behavior (zap vs uninstall)

**Configuration:**
```nix
# modules/machines/darwin/blackphos/default.nix
homebrew.casks = [
  # ... existing casks ...
  "zerotier-one"
];
```

**Manual Join:**
```bash
# After homebrew activation
sudo zerotier-cli join db4344343b14b903
```

**Verification:**
```bash
brew list --cask | grep zerotier
sudo zerotier-cli listnetworks
sudo zerotier-cli peers
```

**Epic 3-6 Implications:**
- Reusable pattern for blackphos prod (Epic 3), rosegold (Epic 4), argentum (Epic 5)
- Manual join documented clearly in deployment checklist
- Potential improvement: Automate join via activation script

---

**Option B: Custom Launchd Service**

**Pros:**
- Nix-native (uses pkgs.zerotierone from nixpkgs)
- Declarative configuration (network join in launchd args)
- No homebrew dependency
- Fully reproducible (network membership in config)
- Service management via nix-darwin launchd.daemons interface

**Cons:**
- Custom module development required (no nix-darwin zerotier module exists)
- Platform-specific launchd knowledge needed
- Higher complexity for first physical deployment
- Testing burden (ensure service starts correctly)
- May require debugging launchd service configuration

**Configuration:**
```nix
# modules/machines/darwin/blackphos/zerotier.nix
{ config, pkgs, lib, ... }:
{
  environment.systemPackages = [ pkgs.zerotierone ];

  launchd.daemons.zerotier-one = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.zerotierone}/bin/zerotier-one"
        "-p9993"
        # Note: Auto-join via args may not work, investigate zerotier-one CLI
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/var/log/zerotier-one.log";
      StandardErrorPath = "/var/log/zerotier-one.log";
    };
  };
}
```

**Import in blackphos/default.nix:**
```nix
imports = [
  # ... existing imports ...
  ./zerotier.nix
];
```

**Verification:**
```bash
launchctl list | grep zerotier
cat /var/log/zerotier-one.log
```

**Epic 3-6 Implications:**
- If Option B successful, reusable module for all darwin machines
- Could be contributed back to nix-darwin community (nix-darwin/modules/services/zerotier.nix)
- Declarative network join eliminates manual step
- Higher initial investment (2-3h) but saves time in Epic 3-6 (1h per machine = 3h saved)

---

**Option C: Manual Installation (NOT RECOMMENDED)**

**Pros:**
- Minimal nix integration (just package in environment.systemPackages)
- Zero module code needed
- Simple to understand

**Cons:**
- Completely manual service management (defeats nix benefits)
- Not reproducible (user must remember to launchctl load)
- No declarative configuration
- Anti-pattern for nix-based system management
- Epic 2-6 teams would need to replicate manual steps

**Configuration:**
```nix
environment.systemPackages = [ pkgs.zerotierone ];
```

**Manual Service Management:**
```bash
# User must manually start zerotier-one service
sudo zerotier-one -d
sudo zerotier-cli join db4344343b14b903
```

**Epic 3-6 Implications:**
- Not recommended for Epic 3-6 (defeats nix benefits)
- Manual steps error-prone and non-reproducible

---

**Recommendation for Story 1.12:**

Implement **Option A (homebrew cask)** FIRST.

**Rationale:**
1. **Lowest Risk:** Blackphos is first physical deployment, minimize complexity
2. **Time Efficiency:** 30 minutes implementation vs 2-3h for Option B
3. **Proven Pattern:** Homebrew already used for 8 casks, well-understood
4. **Standard UX:** Users familiar with zerotier GUI
5. **Epic 2-6 Validation:** If Option A insufficient, Option B can be implemented in Epic 3-6

**Potential Future Improvement (Epic 3-6):**

If Option A successful but manual join is pain point:
- Automate join via activation script:
  ```nix
  system.activationScripts.postActivation.text = ''
    if ! sudo zerotier-cli listnetworks | grep -q db4344343b14b903; then
      sudo zerotier-cli join db4344343b14b903
    fi
  '';
  ```
- Or develop Option B custom module for full declarative config
- Or contribute nix-darwin zerotier module to community

**Document Decision in AC B:**
- Approach chosen: Option A (homebrew cask)
- Rationale: [reasons above]
- Manual steps: `sudo zerotier-cli join db4344343b14b903`
- Platform challenges: [any encountered]
- Recommendations: [for Epic 3-6]

---

### Platform-Specific Challenges

**[To be populated during Story 1.12 execution]**

**Secrets Management on Darwin:**
- Darwin secrets location: `/run/secrets/` (vs `/var/run/secrets/` on nixos)
- Permissions model: [darwin-specific differences?]
- sops-nix compatibility: [any darwin-specific issues?]
- sops.templates functionality: [any platform quirks?]

**Homebrew Integration:**
- Nix vs homebrew package conflicts: [any observed?]
- Cask activation timing: [any issues?]
- Cleanup behavior (zap vs uninstall): [differences noted?]
- Homebrew services vs nix-darwin launchd: [coordination challenges?]

**System Activation:**
- darwin-rebuild vs nixos-rebuild differences: [observed differences]
- Launchd vs systemd service management: [platform differences]
- Activation script behavior: [any darwin-specific quirks?]
- Rollback process: [darwin-specific considerations?]

**Performance:**
- Build times: [darwin vs nixos comparison if available]
- Activation duration: [observed performance]
- Memory usage: [any concerns?]
- Disk usage: [nix store growth on darwin?]

**Zerotier Platform Differences:**
- Interface naming: zt0 (nixos) vs feth0 (darwin) [CONFIRMED]
- Service management: systemd (nixos) vs launchd (darwin)
- GUI availability: Linux zerotier-cli only vs macOS GUI + CLI
- Configuration paths: [any differences?]

---

### Epic 2-6 Migration Value

**[To be populated during Story 1.12 execution]**

**Patterns Validated:**

1. **Physical Darwin Deployment Process:**
   - Commands: [actual commands used]
   - Duration: [actual deployment time]
   - Validation checklist: [zero-regression checklist items]
   - Manual steps: [any required]

2. **Zero-Regression Validation:**
   - crs58 workflows: [6 checks validated]
   - raquel workflows: [5 checks validated]
   - Performance validation: [results]

3. **Zerotier Darwin Integration:**
   - Approach: [A/B/C]
   - Configuration code: [actual implementation]
   - Manual steps: [documented]
   - Platform workarounds: [documented]

4. **Heterogeneous Networking:**
   - Network topology: [3-machine network validated]
   - Connectivity: [bidirectional tests passed]
   - SSH cross-platform: [all user combinations validated]
   - Latency: [measured results]

**Time Savings Estimate:**

**Epic 3 (blackphos prod migration):**
- Zerotier darwin integration: [X hours saved via Story 1.12 solution]
- Physical deployment process: [Y hours saved via checklist]
- Zero-regression validation: [Z hours saved via established checklist]
- Subtotal: [A hours saved]

**Epic 4 (rosegold migration):**
- Zerotier darwin integration: [X hours saved]
- Physical deployment process: [Y hours saved]
- Zero-regression validation: [Z hours saved]
- Subtotal: [B hours saved]

**Epic 5 (argentum migration):**
- Zerotier darwin integration: [X hours saved]
- Physical deployment process: [Y hours saved]
- Zero-regression validation: [Z hours saved]
- Subtotal: [C hours saved]

**Total Epic 3-6 Time Savings: [A+B+C = X-Y hours]**

**Reusable Artifacts:**

1. **Zerotier Darwin Configuration Code:**
   - File: [path to zerotier config]
   - Lines: [X lines of config]
   - Reusable: Yes/No

2. **Zero-Regression Validation Checklist:**
   - crs58 workflows: [6 items]
   - raquel workflows: [5 items]
   - Performance: [3 items]
   - Total: [14 validation items]
   - Reusable: Yes (copy to Epic 3-6 stories)

3. **Platform-Specific Workarounds:**
   - [Workaround 1: description and code]
   - [Workaround 2: description and code]
   - [etc.]

4. **SSH Cross-Platform Validation:**
   - Connectivity matrix: [6 test paths]
   - Verification commands: [documented]
   - Reusable: Yes

**Gotchas Documented:**

1. **[Gotcha 1]:**
   - Problem: [description]
   - Resolution: [workaround or fix]
   - Epic 3-6 impact: [how to avoid]

2. **[Gotcha 2]:**
   - Problem: [description]
   - Resolution: [workaround or fix]
   - Epic 3-6 impact: [how to avoid]

3. **[etc.]**

**Recommended Improvements for Epic 3-6:**

1. **[Improvement 1]:**
   - Current state: [what Story 1.12 did]
   - Improvement: [what Epic 3-6 could do better]
   - Effort: [estimated hours]
   - Value: [benefit to Epic 3-6]

2. **[Improvement 2]:**
   - Current state: [what Story 1.12 did]
   - Improvement: [what Epic 3-6 could do better]
   - Effort: [estimated hours]
   - Value: [benefit to Epic 3-6]

3. **[etc.]**

---

### Story 1.11 Necessity Evidence

**[To be populated during Story 1.12 execution]**

**Evidence Category 1: Typos/Errors Encountered**

Were there typos in configuration files caught only at runtime?
- [Yes/No]
- [If yes: describe errors, would type checking prevent?]

Did deployment reveal evaluation errors not caught at build time?
- [Yes/No]
- [If yes: describe errors, would type checking prevent?]

**Evidence Category 2: Machine-Specific Configuration Needs**

Did blackphos require machine-specific home-manager configs?
- [Yes/No]
- [If yes: describe configs, would homeHosts improve?]

Would homeHosts pattern improve machine-specific configuration?
- [Yes/No/Maybe]
- [Rationale:]

Are current platform conditionals (pkgs.stdenv.isDarwin) sufficient?
- [Yes/No]
- [Rationale:]

**Evidence Category 3: Multi-User Configuration Complexity**

Did crs58 + raquel configuration management reveal complexity?
- [Yes/No]
- [If yes: describe complexity, would type-safe improve?]

Would type-safe user configuration improve maintainability?
- [Yes/No/Maybe]
- [Rationale:]

Are current portable modules (users/crs58, users/raquel) sufficient?
- [Yes/No]
- [Rationale:]

**Evidence Category 4: Pattern Elegance**

Is current architecture (Pattern A + sops-nix + portable modules) elegant?
- [Yes/No]
- [Rationale:]

Does homeHosts pattern add value or unnecessary complexity?
- [Value/Complexity]
- [Rationale:]

Would type-safe architecture improve dendritic patterns?
- [Yes/No/Maybe]
- [Rationale:]

**Evidence Category 5: Epic 2-6 Scaling Concerns**

Will current architecture scale to 6 machines × 4+ users?
- [Yes/No/Maybe]
- [Rationale:]

Are type safety benefits worth refactoring effort (10-16h)?
- [Yes/No]
- [Rationale:]

What Epic 2-6 time savings would type-safe architecture provide?
- [Estimate: X hours saved OR negative value]
- [Rationale:]

**Preliminary Assessment:**
[GO / MODIFY / SKIP]

**Rationale:**
[Summary of evidence supporting preliminary assessment]

**Final Decision Checkpoint:**
Story 1.13 documentation phase (Party Mode assessment)

---

### Empirical Validation Evidence

**[To be populated during Story 1.12 execution]**

**Configuration Build Evidence:**
```bash
# Commands executed
nix build .#darwinConfigurations.blackphos.system
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage

# Results
[build output, timing, any warnings/errors]
```

**Physical Deployment Evidence:**
```bash
# Command executed
darwin-rebuild switch --flake .#blackphos

# Output
[activation script output, timing, any errors]
```

**Zerotier Integration Evidence:**
```bash
# Commands executed
[zerotier configuration, join, verification]

# Output
[zerotier-cli output, network status, peer list]
```

**Network Connectivity Evidence:**
```bash
# Commands executed
ping -c 10 $CINNABAR_ZT_IP
ping -c 10 $ELECTRUM_ZT_IP
[etc.]

# Results
[ping statistics, latency measurements]
```

**SSH Connectivity Evidence:**
```bash
# Commands executed
ssh cameron@$CINNABAR_ZT_IP
ssh testuser@$ELECTRUM_ZT_IP
ssh crs58@$BLACKPHOS_ZT_IP (from cinnabar)
ssh raquel@$BLACKPHOS_ZT_IP (from cinnabar)
[etc.]

# Results
[connection success/failure, authentication method, any errors]
```

**Secrets Validation Evidence:**
```bash
# Commands executed
ls -la /run/secrets/crs58/
stat -f "%Sp %u:%g" /run/secrets/crs58/git-signing-key
cat ~/.ssh/allowed_signers
[etc.]

# Results
[directory listings, permissions, template outputs]
```

---

## References

**Epic Document:**
- File: `docs/notes/development/epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md`
- Story Section: Lines 2146-2220 (75 lines)
- Story ID: 1.12
- Story Title: Deploy blackphos and Integrate into Zerotier Network

**Template Stories:**
- Story 1.10D: `docs/notes/development/work-items/1-10d-validate-custom-package-overlays.md` (2,138 lines, empirical validation baseline, 9.5/10 clarity)
- Story 1.10DB: `docs/notes/development/work-items/1-10db-execute-overlay-architecture-migration.md` (1,788 lines, empirical validation alternative)

**Dependency Stories:**
- Story 1.8: `docs/notes/development/work-items/1-8-migrate-blackphos-from-infra-to-test-clan.md` (initial migration)
- Story 1.8A: `docs/notes/development/work-items/1-8a-extract-portable-home-manager-modules.md` (portable modules)
- Story 1.10BA: `docs/notes/development/work-items/1-10ba-refactor-pattern-a.md` (Pattern A refactoring, 17 modules)
- Story 1.10C: `docs/notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.md` (sops-nix integration)
- Story 1.10DB: `docs/notes/development/work-items/1-10db-execute-overlay-architecture-migration.md` (overlay migration)
- Story 1.10E: `docs/notes/development/work-items/1-10e-enable-remaining-features.md` (feature enablement)

**Configuration Files:**
- Blackphos: `test-clan/modules/machines/darwin/blackphos/default.nix` (173 lines)
- Zerotier: `test-clan/modules/clan/inventory/services/zerotier.nix` (network ID db4344343b14b903)
- crs58 portable: `test-clan/modules/home/users/crs58/default.nix`
- raquel portable: `test-clan/modules/home/users/raquel/default.nix`

**Architecture Documentation:**
- Architecture: `test-clan/docs/notes/development/architecture.md` (Section 11: sops-nix integration, Section 13.1: pkgs-by-name, Section 13.2: overlays)
- Home-Manager Type-Safe: `docs/notes/development/home-manager-type-safe-architecture.md` (Story 1.11 reference)

**Sprint Status:**
- File: `docs/notes/development/sprint-status.yaml`
- Story 1.11: Line 257 (deferred status)
- Story 1.12: Line 272 (backlog status, to be updated to in-progress)

**Party Mode Decision:**
- Date: 2025-11-16
- Decision: Defer Story 1.11 pending Story 1.12 empirical evidence
- Framework: Epic lines 1858-1937 (GO/MODIFY/SKIP criteria)

**Zerotier Network (Story 1.9):**
- Network ID: db4344343b14b903
- Controller: cinnabar (nixos VPS)
- Peers: electrum (nixos VPS)
- Connectivity: bidirectional, 1-12ms latency
- Story: `docs/notes/development/work-items/1-9-rename-vms-cinnabar-electrum-establish-zerotier.md`

**External References:**
- nix-darwin repository: `~/projects/nix-workspace/nix-darwin/`
- nix-darwin services: `~/projects/nix-workspace/nix-darwin/modules/services/` (no zerotier module)
- Homebrew zerotier cask: `brew info zerotier-one`
- Zerotier documentation: https://docs.zerotier.com/

---

## Estimated Effort

**Total Estimated Effort:** 4-6 hours

**Breakdown:**

**Task Group 1: Pre-Deployment (30 min):**
- Verify configuration builds (15 min)
- Review darwin-specific configs (10 min)
- Document pre-deployment state (5 min)

**Task Group 2: Physical Deployment (1-1.5h):**
- Execute deployment (30 min)
- Post-deployment system validation (15 min)
- Zero-regression validation (crs58 + raquel) (30 min)
- Document deployment results (15 min)

**Task Group 3: Zerotier Darwin Integration (2-3h):**
- Research options (A/B/C) (30 min)
- Implement chosen approach (1h)
- Verify service and network join (30 min)
- Document approach and challenges (30 min)

**Task Group 4: Network/Integration Validation (1.5-2h):**
- Heterogeneous network connectivity (30 min)
- Cross-platform SSH validation (30 min)
- Clan vars/secrets validation on darwin (30 min)
- Integration findings documentation (30 min)

**Contingency:** +1h for unexpected issues (darwin platform quirks, zerotier challenges)

**Risk Factors:**
- Medium risk: First physical deployment (real hardware, user workflows critical)
- Medium risk: Zerotier darwin integration uncertainty (no nix-darwin module)
- Low risk: Configuration tested extensively (Stories 1.8-1.10E)
- Low risk: Network validation straightforward (proven pattern from Story 1.9)

---

## Notes

**Story Context:**

Story 1.12 is a **critical validation checkpoint** in Epic 1.
It's the first physical hardware deployment and the first heterogeneous networking test (nixos ↔ nix-darwin).
Success validates that all prior configuration work (Stories 1.8-1.10E) actually works on real darwin hardware.

**Story Lineage (blackphos evolution):**
1. Story 1.8: Initial migration from infra → test-clan (darwin + home-manager modules)
2. Story 1.8A: Portable home-manager modules extracted (crs58, raquel)
3. Story 1.10BA: Pattern A refactoring (17 modules in dendritic aggregates)
4. Story 1.10C: sops-nix secrets integration (SSH signing, API keys, user secrets)
5. Story 1.10DB: Overlay architecture migration (5 layers functional)
6. Story 1.10E: Feature enablement (ccstatusline, claude-code, catppuccin themes)
7. **Story 1.12: Physical deployment + heterogeneous networking** [THIS STORY]

**Critical Success Factors:**

1. **Zero Regressions:** crs58 and raquel daily workflows MUST remain functional. Any regression blocks Epic 2-6 confidence.

2. **Zerotier Darwin Solution:** Finding a working zerotier darwin integration saves 6-9 hours in Epic 3-6 (3 more darwin migrations).

3. **Heterogeneous Networking:** Proving nixos ↔ nix-darwin coordination validates production fleet architecture (4 darwin + 1-2 nixos).

4. **Story 1.11 Decision:** Deployment experience informs type-safe architecture necessity (GO/MODIFY/SKIP decision in Story 1.13).

5. **Epic 1 GO/NO-GO Input:** Story 1.14 GO/NO-GO decision requires heterogeneous networking validation from Story 1.12.

**Epic 1 Coverage After Story 1.12:**

- ✅ Dendritic flake-parts pattern (Story 1.2, 1.7)
- ✅ Clan inventory and services (Story 1.3, 1.9)
- ✅ Terraform + clan integration (Story 1.4, 1.5)
- ✅ Test harness (Story 1.6)
- ✅ Pattern A home-manager modules (Story 1.10BA)
- ✅ sops-nix secrets (Story 1.10C)
- ✅ Custom package overlays (Story 1.10D)
- ✅ 5-layer overlay architecture (Story 1.10DB)
- ✅ Feature enablement (Story 1.10E)
- ✅ **Physical darwin deployment** (Story 1.12) [NEW]
- ✅ **Heterogeneous networking** (Story 1.12) [NEW]

**Epic 1 Coverage Target:** 95% architectural validation achieved.

**Remaining Epic 1 Work:**
- Story 1.13: Documentation consolidation (3-4h)
- Story 1.14: GO/NO-GO decision (1-2h)
- Total remaining: 4-6h

**Epic 1 Total Effort (as of Story 1.12 start):**
- Stories 1.1-1.10E: ~50-60 hours
- Story 1.12 (estimated): 4-6 hours
- Stories 1.13-1.14 (estimated): 4-6 hours
- **Epic 1 Total: ~58-72 hours**

**Epic 2-6 Time Savings from Story 1.12:**
- Zerotier darwin solution: 6-9 hours saved (3 machines × 2-3h research)
- Physical deployment process: 3-6 hours saved (3 machines × 1-2h process discovery)
- Zero-regression checklist: 2-4 hours saved (3 machines × 40min-1h validation)
- **Total Epic 2-6 Savings: 11-19 hours**

**Return on Investment (Story 1.12):**
- Investment: 4-6 hours (Story 1.12 effort)
- Return: 11-19 hours (Epic 2-6 savings)
- **ROI: 1.8x - 4.75x**

Story 1.12 pays for itself nearly 2-5x over in Epic 2-6 time savings.

**Quality Target:**

This work item targets **9.5/10 clarity** matching Story 1.10D baseline:
- Comprehensive investigation documented (zerotier darwin research)
- Empirical validation with deployment proof (physical hardware evidence)
- Clear task breakdown with validation steps
- Epic 2-6 migration value articulated

**Completion Target:**

Story 1.12 estimated to complete in **1-2 days** (4-6 hours total effort).
Upon completion, provides critical input for Story 1.13 documentation and Story 1.14 GO/NO-GO decision.

---

## Work Item Metadata

**Created:** [Date]
**Template:** Story 1.10D (2,138 lines, empirical validation baseline)
**Target Length:** 1,800-2,200 lines (deployment + investigation + validation)
**Quality Target:** 9.5/10 clarity (match Story 1.10D)
**Estimated Effort:** 4-6 hours
**Risk Level:** Medium (physical hardware, zerotier darwin uncertainty)
**Strategic Value:** First physical deployment, heterogeneous networking, Epic 2-6 darwin pattern

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)
**Sprint:** Epic 1 (ongoing)
**Story ID:** 1.12
**Story Title:** Deploy blackphos and Integrate into Zerotier Network

**Dependencies Satisfied:**
- ✅ Story 1.10BA (Pattern A refactoring, 17 modules)
- ✅ Story 1.10C (sops-nix infrastructure)
- ⏸️ Story 1.11 (type-safe architecture - soft dependency, deferred)

**Blocks:**
- Story 1.13 (integration findings documentation)
- Story 1.14 (GO/NO-GO decision)

**Key Context:**
- First physical hardware deployment in Epic 1
- First heterogeneous networking test (nixos ↔ nix-darwin)
- Zerotier darwin investigation required (no nix-darwin module)
- Story 1.11 necessity assessment data collection
- Epic 1 GO/NO-GO decision input

**Success Criteria:**
- All 6 acceptance criteria (A-F) satisfied
- All 5 quality gates PASS
- Zero regressions validated
- Heterogeneous networking proven
- Integration findings documented

---
