---
title: "Story 1.8: Validate and document clan secrets/vars workflow on Hetzner VMs"
---

Status: drafted

## Story

As a system administrator,
I want to validate the clan secrets/vars workflow and document operational patterns,
So that I understand the complete secrets lifecycle before proceeding to GCP deployment and can replicate these patterns in production.

## Context

**Post-Stories 1.5-1.7 Reality Check:**

Story 1.8 was originally drafted to validate clan secrets from scratch.
However, Stories 1.5-1.7 already accomplished most of the originally planned work:

**Already Complete (from Story 1.5):**
- Clan vars generated for all 3 machines (hetzner-ccx23, hetzner-cx43, gcp-vm)
- Vars deployed to `/run/secrets/vars/` on Hetzner VMs with correct permissions
- Zerotier identity persistent across reboots (validated)
- LUKS passphrase working via clan vars
- Emergency-access passwords functional
- Hetzner API token and terraform passphrase in clan secrets

**Validated Architecture (from Stories 1.6-1.7):**
- Test harness operational (18 tests, all passing)
- Pure dendritic flake-parts pattern with import-tree
- Clan-core integration proven with zero conflicts
- Comprehensive test coverage for regression/invariant/feature/integration scenarios

**Current State of Secrets Infrastructure:**
```
~/projects/nix-workspace/test-clan/
├── sops/
│   ├── secrets/           # Encrypted secrets
│   │   ├── hetzner-api-token/
│   │   ├── tf-passphrase/
│   │   ├── hetzner-ccx23-age.key/
│   │   ├── hetzner-cx43-age.key/
│   │   └── gcp-vm-age.key/
│   ├── machines/          # Machine age keys
│   │   ├── hetzner-ccx23/key.json
│   │   ├── hetzner-cx43/key.json
│   │   └── gcp-vm/key.json
│   └── users/             # User age keys
│       └── crs58/key.json
└── vars/
    └── per-machine/       # Generated vars (encrypted secrets + facts)
        ├── hetzner-ccx23/
        │   ├── initrd-ssh/
        │   ├── zerotier/
        │   ├── luks-password/
        │   ├── emergency-access/
        │   ├── user-password-root/
        │   ├── zfs/
        │   ├── state-version/
        │   └── tor_tor/
        ├── hetzner-cx43/ (similar structure, no LUKS)
        └── gcp-vm/ (similar structure)
```

**Gaps Identified:**

While the infrastructure is operational, the following gaps exist that Story 1.8 must address:

1. **SSH Host Keys:** Current vars include `initrd-ssh` keys but NOT runtime SSH host keys for sshd
   - Consequence: SSH host keys may be ephemeral (regenerated on rebuild)
   - Need to validate persistence across `nixos-rebuild switch`

2. **Test Coverage Gap:** TC-007 (secrets-generation) is currently a smoke test only
   - Only validates `clan` CLI is available
   - Does NOT test actual vars generation, encryption, or deployment
   - Need comprehensive test for vars lifecycle

3. **Documentation Gap:** No SECRETS-MANAGEMENT.md documenting operational patterns
   - Vars vs secrets distinction unclear
   - Generation/deployment workflow not documented
   - Troubleshooting guidance missing

4. **Workflow Validation:** Vars workflow works but not explicitly validated end-to-end
   - Need to prove understanding by executing complete lifecycle
   - Regeneration workflow untested
   - Multi-machine coordination patterns not documented

**Revised Story Focus:**

This story now focuses on:
- Validating SSH host key persistence (AC #1-2)
- Enhancing TC-007 test to cover vars lifecycle (AC #3)
- Creating comprehensive secrets management documentation (AC #4)
- Validating end-to-end vars workflow understanding (AC #5-6)

**Strategic Importance:**

Story 1.9 (GCP terraform) and Story 1.10 (GCP deployment) will replicate this secrets workflow for GCP VM.
Understanding the complete lifecycle NOW ensures smooth GCP integration later.

## Acceptance Criteria

1. **SSH Host Key Persistence Validated:**
   - SSH host keys added to clan vars for hetzner-ccx23 (if not present)
   - Rebuild test: `nixos-rebuild switch` does NOT change SSH host key fingerprint
   - SSH connection works without host key warning after rebuild
   - Host keys stored in vars/per-machine/hetzner-ccx23/sshd/ (or appropriate location)

2. **Vars Lifecycle Test Enhanced (TC-007):**
   - Current TC-007 smoke test replaced with comprehensive vars lifecycle test
   - New test validates: vars directory structure, secret encryption (age recipients), public facts accessibility, vars generation repeatability
   - Test runs in test harness without requiring deployed infrastructure
   - Test passes in `nix flake check` and `./tests/run-all.sh all`

3. **Secrets Management Documentation Created:**
   - docs/notes/clan/SECRETS-MANAGEMENT.md created with comprehensive coverage
   - Sections: Overview (vars vs secrets), Age encryption (admins group, machine keys), Vars structure (per-machine layout, secret/fact distinction), Generation workflow (clan CLI commands, service instance integration), Deployment mechanism (/run/secrets/ tmpfs, sops-nix integration), Operational patterns (adding new secrets, rotating keys, troubleshooting)
   - Examples from test-clan (zerotier, LUKS, SSH keys, emergency-access)
   - Troubleshooting section with common failure modes
   - Reference implementation: test-clan vars structure

4. **Vars Workflow Validation:**
   - Execute complete vars lifecycle on hetzner-ccx23: inspect current vars, regenerate specific var (e.g., emergency-access password), verify encryption (age recipients correct), deploy to VM, validate on VM (/run/secrets/ updated)
   - Document workflow steps with actual commands used
   - Prove repeatable workflow understanding

5. **Multi-Machine Vars Patterns Documented:**
   - Document how vars differ between machines (zerotier controller vs peer, LUKS vs no-LUKS)
   - Document shared secrets (if any) via admins group
   - Document machine-specific encryption (age keys per machine)
   - Examples: hetzner-ccx23 (controller, LUKS, ZFS) vs hetzner-cx43 (peer, no-LUKS)

6. **Vars Generation Repeatable:**
   - Demonstrate vars regeneration for new machine (gcp-vm vars already exist, use as example)
   - Document `clan vars generate <machine>` workflow
   - Validate generated vars have correct structure and encryption

## Tasks / Subtasks

- [ ] **Task 1: Validate SSH Host Key Persistence** (AC: #1)
  - [ ] SSH to hetzner-ccx23: `ssh root@162.55.175.87`
  - [ ] Record current SSH host key fingerprint: `ssh-keyscan 162.55.175.87`
  - [ ] Check if SSH host keys in vars: `ls -la ~/projects/nix-workspace/test-clan/vars/per-machine/hetzner-ccx23/sshd/` (if exists)
  - [ ] If SSH host keys NOT in vars:
    - [ ] Research clan-core sshd service module for SSH host key vars integration
    - [ ] Check if sshd-clan service instance generates SSH host key vars
    - [ ] If not automatic, document as known gap (may be acceptable)
  - [ ] Execute rebuild test: `ssh root@162.55.175.87 "nixos-rebuild switch"`
  - [ ] Verify SSH host key fingerprint unchanged: `ssh-keyscan 162.55.175.87` (compare to baseline)
  - [ ] Test SSH connection works without host key warning
  - [ ] Document findings: are SSH host keys persistent via vars or ephemeral?

- [ ] **Task 2: Enhance TC-007 Secrets Test** (AC: #2)
  - [ ] Read current TC-007 implementation: `~/projects/nix-workspace/test-clan/modules/checks/validation.nix`
  - [ ] Design comprehensive vars lifecycle test:
    - Test 1: Vars directory structure exists (`vars/per-machine/`)
    - Test 2: Machine vars directories present for all 3 machines
    - Test 3: Expected var categories present (zerotier, emergency-access, state-version)
    - Test 4: Secret files have age recipients (machines + users symlinks)
    - Test 5: Public facts are readable (zerotier-ip/value, state-version/version/value)
    - Test 6: Vars generation is idempotent (re-running doesn't fail)
  - [ ] Implement enhanced TC-007 test in `modules/checks/validation.nix`
  - [ ] Run test: `nix build .#checks.x86_64-linux.secrets-generation`
  - [ ] Verify test passes with current vars structure
  - [ ] Run full test suite: `cd ~/projects/nix-workspace/test-clan && ./tests/run-all.sh all`
  - [ ] Commit enhanced test: `git add modules/checks/validation.nix && git commit -m "test(vars): enhance TC-007 with comprehensive vars lifecycle validation"`

- [ ] **Task 3: Create SECRETS-MANAGEMENT.md Documentation** (AC: #3)
  - [ ] Create docs/notes/clan/SECRETS-MANAGEMENT.md
  - [ ] Write Overview section:
    - Define vars vs secrets distinction
    - Explain age encryption model
    - Describe sops-nix integration
  - [ ] Write Age Encryption section:
    - Document admins group (sops/users/)
    - Document machine keys (sops/machines/)
    - Explain encryption recipients (users + machines)
  - [ ] Write Vars Structure section:
    - Document per-machine layout (vars/per-machine/<machine>/)
    - Explain secret vs fact files
    - Show examples from test-clan (zerotier, LUKS, emergency-access)
  - [ ] Write Generation Workflow section:
    - Document `clan vars generate <machine>` command
    - Explain service instance integration (vars generated from service definitions)
    - Show examples: zerotier identity, LUKS passphrase, emergency-access password
  - [ ] Write Deployment Mechanism section:
    - Explain /run/secrets/ tmpfs
    - Document sops-nix activation
    - Show permissions model (root:keys, 0600)
  - [ ] Write Operational Patterns section:
    - Adding new secrets to service instances
    - Rotating secrets (regenerate specific var)
    - Multi-machine coordination (controller vs peer roles)
  - [ ] Write Troubleshooting section:
    - Vars generation failures (age keys missing)
    - Deployment failures (sops-nix not activated)
    - Permission issues (keys group membership)
    - Common errors and solutions
  - [ ] Add examples from test-clan with actual file paths
  - [ ] Commit documentation: `git add docs/notes/clan/SECRETS-MANAGEMENT.md && git commit -m "docs(clan): add comprehensive secrets management guide"`

- [ ] **Task 4: Validate Vars Workflow End-to-End** (AC: #4)
  - [ ] Navigate to test-clan: `cd ~/projects/nix-workspace/test-clan`
  - [ ] Enter nix develop shell: `nix develop`
  - [ ] Inspect current vars for hetzner-ccx23:
    - `ls -R vars/per-machine/hetzner-ccx23/`
    - `cat vars/per-machine/hetzner-ccx23/zerotier/zerotier-ip/value`
    - `ls -la vars/per-machine/hetzner-ccx23/zerotier/zerotier-identity-secret/`
  - [ ] Verify age encryption:
    - Check recipients: `ls vars/per-machine/hetzner-ccx23/zerotier/zerotier-identity-secret/users/`
    - Verify machine key link: `ls -la vars/per-machine/hetzner-ccx23/zerotier/zerotier-identity-secret/machines/`
  - [ ] Test vars regeneration (backup first):
    - `cp -r vars/per-machine/hetzner-ccx23/emergency-access vars/per-machine/hetzner-ccx23/emergency-access.bak`
    - `clan vars generate hetzner-ccx23` (regenerate all vars)
    - Verify new vars generated (timestamps updated)
    - `diff -r vars/per-machine/hetzner-ccx23/emergency-access vars/per-machine/hetzner-ccx23/emergency-access.bak` (should differ)
  - [ ] Validate vars on VM (SSH to hetzner-ccx23):
    - `ssh root@162.55.175.87 "ls -la /run/secrets/vars/"`
    - Verify secrets present with correct permissions (0600, root:keys)
  - [ ] Document complete workflow with commands in story completion notes

- [ ] **Task 5: Document Multi-Machine Vars Patterns** (AC: #5)
  - [ ] Compare vars between machines:
    - `diff -qr vars/per-machine/hetzner-ccx23/ vars/per-machine/hetzner-cx43/`
    - Note differences: zerotier-network-id (controller only), luks-password (ccx23 only), zfs/key (ccx23 only)
  - [ ] Document machine role differences in SECRETS-MANAGEMENT.md:
    - Controller machine (ccx23): zerotier-network-id fact, zerotier-identity-secret
    - Peer machines (cx43, gcp-vm): zerotier-identity-secret only
    - LUKS machines (ccx23): luks-password/key secret
    - ZFS machines (ccx23): zfs/key secret (disabled in current config but var exists)
  - [ ] Document shared secrets model:
    - All secrets encrypted for admins group (crs58)
    - Machine-specific encryption (each machine can decrypt its own secrets)
    - No cross-machine secret sharing in current test-clan setup
  - [ ] Add multi-machine coordination examples to documentation
  - [ ] Update SECRETS-MANAGEMENT.md with multi-machine patterns

- [ ] **Task 6: Validate Vars Generation Repeatable** (AC: #6)
  - [ ] Document vars generation for new machine (use gcp-vm as example since vars exist):
    - Machine added to clan inventory: `nix eval .#clan.inventory.machines.gcp-vm --json | jq .`
    - Service instances configured for gcp-vm (zerotier peer role)
    - Vars generated: `clan vars generate gcp-vm`
    - Result: vars/per-machine/gcp-vm/ populated with service-specific vars
  - [ ] Validate generated vars structure:
    - `ls -R vars/per-machine/gcp-vm/`
    - Verify expected vars present: zerotier, emergency-access, initrd-ssh, user-password-root, state-version
    - Verify age encryption: check users/ and machines/ symlinks
  - [ ] Document vars generation workflow in SECRETS-MANAGEMENT.md
  - [ ] Add example commands for adding new machine to documentation

- [ ] **Task 7: Update Story 1.8 Completion Notes** (AC: all)
  - [ ] Document what was ALREADY COMPLETE from Stories 1.5-1.7
  - [ ] Document what Story 1.8 ACTUALLY validated:
    - SSH host key persistence findings
    - Enhanced TC-007 test implementation
    - Vars lifecycle understanding
    - Multi-machine coordination patterns
  - [ ] Reference SECRETS-MANAGEMENT.md as primary documentation
  - [ ] List files created/modified:
    - CREATED: docs/notes/clan/SECRETS-MANAGEMENT.md
    - MODIFIED: modules/checks/validation.nix (enhanced TC-007)
  - [ ] Mark story as done in sprint-status.yaml

## Dev Notes

### Revised Story Scope

**Original Story 1.8 Scope (from epic):**
- Initialize clan secrets and vars from scratch
- Validate entire secrets infrastructure ground-up
- Deploy and validate on Hetzner VMs

**Actual Situation (post-Stories 1.5-1.7):**
- Clan secrets/vars already operational
- Infrastructure deployed and validated
- Test harness comprehensive
- Dendritic architecture proven

**Revised Story 1.8 Focus:**
- **Validation**: Confirm existing infrastructure understood
- **Testing**: Enhance TC-007 from smoke test to lifecycle test
- **Documentation**: Comprehensive SECRETS-MANAGEMENT.md guide
- **Operational Understanding**: Prove vars workflow mastery

### Why Story 1.8 Still Necessary

Despite most work being complete, Story 1.8 is NOT redundant because:

1. **Operational Understanding:** Vars workflow is working but not explicitly validated
   - Need to prove we understand the lifecycle
   - Need to document operational patterns
   - Story 1.9-1.10 will replicate for GCP

2. **Test Coverage:** TC-007 is smoke test only
   - Current test validates CLI availability
   - Need comprehensive vars lifecycle test
   - Test harness needs this coverage

3. **Documentation:** No guide for secrets management
   - Troubleshooting scenarios undocumented
   - Multi-machine patterns unclear
   - Future operators need operational guide

4. **SSH Host Keys:** Potential gap identified
   - Need to validate SSH host key persistence
   - May discover missing vars integration
   - Critical for production use

### Architectural Context

**Clan Vars Architecture:**

```
Vars = Secrets (encrypted) + Facts (public)

Generation:
  Service Instances → Vars Generators → vars/per-machine/<machine>/

Encryption:
  Secrets encrypted via age for: admins group + machine key

Deployment:
  vars/ → sops-nix activation → /run/secrets/vars/ (tmpfs)

Lifecycle:
  1. Define service instances in inventory
  2. Generate vars: clan vars generate <machine>
  3. Vars stored in vars/per-machine/<machine>/
  4. Deployment: clan machines install or nixos-rebuild
  5. Secrets available at /run/secrets/vars/ on target machine
```

**Service Instance → Vars Mapping:**

| Service Instance | Vars Generated |
|------------------|----------------|
| zerotier (controller) | zerotier-identity-secret, zerotier-network-id, zerotier-ip |
| zerotier (peer) | zerotier-identity-secret, zerotier-ip |
| emergency-access | password, password-hash |
| users-root | user-password, user-password-hash |
| initrd-ssh | id_ed25519, id_ed25519.pub |
| sshd-clan | (SSH host keys?) - need to validate |
| disko (LUKS) | luks-password/key |
| disko (ZFS encryption) | zfs/key |

**Expected Vars for hetzner-ccx23:**

Based on service instances configured:
- zerotier: identity-secret (secret), network-id (fact), zerotier-ip (fact)
- emergency-access: password (secret), password-hash (fact)
- users-root: user-password (secret), user-password-hash (secret)
- initrd-ssh: id_ed25519 (secret), id_ed25519.pub (fact)
- luks-password: key (secret) - from disko configuration
- zfs: key (secret) - present but disabled (encryption issue from Story 1.5)
- state-version: version (fact)
- tor_tor: hostname (secret), hs_ed25519_secret_key (secret) - present in vars

**Differences Between Machines:**

| Machine | Controller | LUKS | ZFS | SSH Host Keys? |
|---------|-----------|------|-----|---------------|
| hetzner-ccx23 | ✓ | ✓ | ✓ (disabled) | ? |
| hetzner-cx43 | ✗ | ✗ | ✗ | ? |
| gcp-vm | ✗ | ? | ✗ | ? |

### Learnings from Previous Stories

**From Story 1.5 (Hetzner Deployment):**

- Vars deployed successfully to `/run/secrets/vars/` on Hetzner VMs
- Zerotier identity persistent (not ephemeral) due to vars
- LUKS passphrase working via vars (no manual passphrase needed)
- ZFS encryption disabled due to boot hang (vars present but unused)
- Sops-nix integration functional
- No failed services, vars deployment clean

**Key Files Created in Story 1.5:**
- `vars/per-machine/hetzner-ccx23/` (complete vars structure)
- `vars/per-machine/hetzner-cx43/` (peer configuration)
- `sops/machines/hetzner-ccx23/key.json` (machine age key)

**From Story 1.6 (Test Harness):**

- 18 tests implemented (12 nix-unit + 4 runCommand + 2 runNixOSTest)
- Test architecture: modules/checks/ with import-tree auto-discovery
- TC-007 (secrets-generation) is smoke test only - validates clan CLI availability
- Test execution: `./tests/run-all.sh all` (~11s full suite)
- Hybrid pattern: nix-unit for property tests, withSystem for derivation tests

**Key Files Created in Story 1.6:**
- `modules/checks/nix-unit.nix` (expression evaluation tests)
- `modules/checks/validation.nix` (TC-007 secrets smoke test)
- `modules/checks/integration.nix` (VM boot tests)
- `tests/run-all.sh` (test execution script)

**TC-007 Current Implementation:**
```nix
secrets-generation = pkgs.runCommand "secrets-generation" {
  nativeBuildInputs = [ inputs'.clan-core.packages.default ];
} ''
  # Smoke test: verify clan CLI available
  clan secrets --help > /dev/null 2>&1
  echo "✓ Clan CLI available"

  # Note: Full secrets generation test deferred
  touch $out
'';
```

**Enhancement Needed for Story 1.8:**
- Validate vars directory structure exists
- Check machine-specific vars present
- Verify age encryption (recipients)
- Test public facts accessible
- Validate vars generation idempotent

**From Story 1.7 (Dendritic Refactoring):**

- Pure dendritic flake-parts pattern achieved
- `flake.nix` uses: `(inputs.import-tree ./modules)`
- All feature tests passing (TC-008, TC-009)
- Zero regressions confirmed
- Manual machine registration retained (Step 2.5 deferred)

**Key Architectural Decisions from Story 1.7:**
- Pure import-tree at flake root (no mixed patterns)
- Namespace imports in host modules
- Base modules auto-discovered from modules/system/
- Clan-core integration preserved via modules/clan/core.nix

**Implications for Story 1.8:**
- Test harness ready for enhanced TC-007 test
- Dendritic pattern proven - can focus on vars workflow
- No architectural uncertainty - pure validation story

### Solo Operator Workflow

This story is LOW RISK validation and documentation:
- No infrastructure changes (VMs already deployed)
- No configuration changes (secrets already working)
- Focus: understanding, testing, documenting

**Expected execution time:** 2-3 hours
- Task 1 (SSH host keys): 30 minutes
- Task 2 (enhance TC-007): 45 minutes
- Task 3 (SECRETS-MANAGEMENT.md): 60 minutes
- Tasks 4-6 (validation): 30 minutes
- Task 7 (completion notes): 15 minutes

**Operational Safety:**
- No terraform operations (no cloud changes)
- No VM deployments (no nixos-rebuild on remote)
- Test-only SSH access (read-only inspection)
- Documentation-focused (low risk)

### SSH Host Keys Investigation

**Question:** Are SSH host keys persistent via vars or ephemeral?

**Investigation Steps:**
1. SSH to hetzner-ccx23 and record host key fingerprint
2. Check if SSH host keys present in vars/per-machine/hetzner-ccx23/
3. Execute `nixos-rebuild switch` on VM
4. Verify SSH host key fingerprint unchanged
5. Document findings

**Possible Outcomes:**

**Outcome A: SSH Host Keys in Vars (IDEAL)**
- Vars include sshd host keys (ssh_host_ed25519_key, etc.)
- Rebuild preserves host key fingerprint
- No host key warnings
- Pattern validated for production

**Outcome B: SSH Host Keys Ephemeral (ACCEPTABLE)**
- No sshd host keys in vars (only initrd-ssh)
- Rebuild may regenerate host keys
- Document as known limitation
- May be acceptable for test infrastructure

**Outcome C: SSH Host Keys Config-Driven (ACCEPTABLE)**
- Host keys managed via nixos configuration (not vars)
- Persistent across rebuilds via configuration.nix
- Different pattern than other secrets
- Document distinction

**Action Based on Outcome:**
- Outcome A: Document as working pattern
- Outcome B: Document as gap, assess if blocker for production
- Outcome C: Document alternative pattern

### Test Coverage Strategy

**Current TC-007 (Smoke Test):**
- Validates clan CLI availability only
- Runs in check derivation (no actual workspace)
- Fast (~1s) but minimal coverage

**Enhanced TC-007 (Lifecycle Test):**
- Validates actual vars directory structure
- Checks machine-specific vars present
- Verifies age encryption configured
- Tests public facts accessible
- Still runs in check derivation (no deployment needed)
- Slower (~5s) but comprehensive

**Test Implementation Pattern:**
```nix
secrets-generation = pkgs.runCommand "secrets-generation" {
  nativeBuildInputs = [ pkgs.jq ];
  varsPath = "${self}/vars";  # Reference vars directory in repo
} ''
  # Test 1: Vars directory structure
  test -d "$varsPath/per-machine" || exit 1

  # Test 2: Machine vars present
  for machine in hetzner-ccx23 hetzner-cx43 gcp-vm; do
    test -d "$varsPath/per-machine/$machine" || exit 1
  done

  # Test 3: Expected var categories
  test -d "$varsPath/per-machine/hetzner-ccx23/zerotier" || exit 1

  # Test 4: Age encryption (symlinks to recipients)
  test -L "$varsPath/per-machine/hetzner-ccx23/zerotier/zerotier-identity-secret/users/crs58" || exit 1

  # Test 5: Public facts readable
  test -f "$varsPath/per-machine/hetzner-ccx23/zerotier/zerotier-ip/value" || exit 1

  touch $out
'';
```

### Documentation Structure

**SECRETS-MANAGEMENT.md Outline:**

1. **Overview**
   - Purpose: Declarative secrets management for multi-machine coordination
   - Key concepts: vars vs secrets, age encryption, sops-nix
   - Reference implementation: test-clan repository

2. **Architecture**
   - Vars = Secrets (encrypted) + Facts (public)
   - Age encryption model (admins group + machine keys)
   - Sops-nix integration for deployment
   - Lifecycle: generate → store → deploy

3. **Vars Structure**
   - Directory layout: vars/per-machine/<machine>/
   - Service instance → vars mapping
   - Secret vs fact file structure
   - Age recipients (users/ and machines/ symlinks)

4. **Generation Workflow**
   - Service instances define required vars
   - `clan vars generate <machine>` command
   - Vars generators create secrets and facts
   - Encryption applied via age

5. **Deployment Mechanism**
   - Vars deployed to /run/secrets/vars/ (tmpfs)
   - Sops-nix activation at system boot
   - Permissions: root:keys, 0600 for secrets
   - Systemd services read from /run/secrets/

6. **Operational Patterns**
   - Adding new machine: inventory → generate → deploy
   - Rotating secrets: regenerate specific var → deploy
   - Multi-machine coordination: controller vs peer roles
   - Shared secrets: admins group encryption

7. **Examples from test-clan**
   - Zerotier identity (controller vs peer)
   - LUKS passphrase (persistent encryption)
   - Emergency access (root password recovery)
   - SSH keys (initrd and runtime)

8. **Troubleshooting**
   - Vars generation failures (age keys missing)
   - Deployment failures (sops-nix not activated)
   - Permission issues (keys group membership)
   - Common errors and solutions

### References

- [Source: docs/notes/development/epics.md#Story-1.8]
- [Prerequisite: docs/notes/development/work-items/1-5-deploy-hetzner-vm-and-validate-stack.md]
- [Prerequisite: docs/notes/development/work-items/1-6-implement-comprehensive-test-harness-for-test-clan.md]
- [Prerequisite: docs/notes/development/work-items/1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness.md]
- [Upstream: clan-core vars documentation]
- [Upstream: sops-nix documentation]
- [Upstream: age encryption]

### Expected Validation Points

After this story completes:
- ✅ Vars workflow completely understood and documented
- ✅ TC-007 test covers vars lifecycle comprehensively
- ✅ SECRETS-MANAGEMENT.md provides operational guide
- ✅ SSH host key persistence validated (outcome documented)
- ✅ Multi-machine coordination patterns clear
- ✅ Ready for Story 1.9 (GCP terraform with secrets workflow replication)

**What Story 1.8 does NOT cover:**
- GCP-specific secrets (Story 1.9-1.10)
- Cross-machine secret sharing (not required for Phase 0)
- Secrets rotation in production (post-migration concern)
- Long-term key management strategy (Epic 7)

### Important Constraints

**Zero-regression mandate does NOT apply:**
- Test infrastructure (experimental test-clan)
- Documentation-focused story (no infrastructure changes)

**Operational Safety:**
- No cloud resource changes
- No VM configuration changes
- Read-only inspection of deployed systems
- Test enhancements only

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->

### Debug Log References

### Completion Notes List

### File List

## Change Log

**2025-11-07 (Story Update - Post-Stories 1.5-1.7 Reality Check):**

This story was completely rewritten based on actual completion state of Stories 1.5-1.7.

**Original Story 1.8 Assumptions:**
- Clan secrets would be initialized from scratch
- Vars would be generated for the first time
- Complete secrets infrastructure would be validated ground-up
- Story was drafted before Stories 1.6-1.7 were inserted (numbering off by 2)

**Actual Situation Post-Stories 1.5-1.7:**
- ✅ Clan vars already generated for all 3 machines (Story 1.5)
- ✅ Vars deployed and validated on Hetzner VMs (Story 1.5 AC #11)
- ✅ Zerotier identity persistent (Story 1.5 AC #10)
- ✅ Test harness operational with 18 tests (Story 1.6)
- ✅ Pure dendritic pattern proven (Story 1.7)
- ✅ TC-007 exists but is smoke test only (validates clan CLI availability)
- ❌ No SECRETS-MANAGEMENT.md documentation
- ❌ SSH host key persistence not explicitly validated
- ❌ Vars lifecycle not comprehensively tested

**Story 1.8 Revised Scope:**
- **REMOVED:** All "initialize from scratch" tasks (already complete)
- **REMOVED:** All "first-time vars generation" tasks (already done in Story 1.5)
- **REMOVED:** Basic vars deployment validation (completed in Story 1.5)
- **RETAINED:** SSH host key persistence validation (gap identified)
- **RETAINED:** Documentation creation (SECRETS-MANAGEMENT.md)
- **ADDED:** Enhance TC-007 from smoke test to lifecycle test
- **ADDED:** Validate vars workflow understanding end-to-end
- **ADDED:** Document multi-machine coordination patterns

**Acceptance Criteria Changes:**
- Original 9 ACs → Revised 6 ACs (more focused)
- AC #1: NEW - SSH host key persistence validation
- AC #2: NEW - Enhance TC-007 test (was smoke test)
- AC #3: RETAINED - SECRETS-MANAGEMENT.md documentation
- AC #4: NEW - Vars workflow end-to-end validation
- AC #5: NEW - Multi-machine patterns documentation
- AC #6: REVISED - Vars generation repeatability (use existing gcp-vm vars as example)
- REMOVED: ACs #1-2 (secrets initialization - already done)
- REMOVED: AC #3 (Hetzner API token - validated in Story 1.5)
- REMOVED: AC #4 (vars generation - completed in Story 1.5)
- REMOVED: AC #5 (vars deployment - validated in Story 1.5)
- REMOVED: AC #7 (zerotier identity - validated in Story 1.5)

**Context Section Rewritten:**
- Added "Post-Stories 1.5-1.7 Reality Check" explaining actual state
- Added "Already Complete" section listing work from Story 1.5
- Added "Validated Architecture" section from Stories 1.6-1.7
- Added "Current State of Secrets Infrastructure" with directory tree
- Added "Gaps Identified" section focusing on remaining work
- Added "Revised Story Focus" clarifying new scope
- Added "Strategic Importance" explaining why story still necessary

**Dev Notes Enhanced:**
- Added "Revised Story Scope" section explaining the rewrite
- Added "Why Story 1.8 Still Necessary" justification
- Added "Learnings from Previous Stories" with comprehensive findings from 1.5-1.7
- Added "SSH Host Keys Investigation" with outcome scenarios
- Added "Test Coverage Strategy" for TC-007 enhancement
- Added "Documentation Structure" for SECRETS-MANAGEMENT.md

**All story number references corrected:**
- Original draft referenced "Story 1.6" (meant 1.8 in new numbering)
- All internal references updated to correct story numbers
- Prerequisites updated: Stories 1.5, 1.6, 1.7

**Estimated effort reduced:**
- Original: 2-4 hours (full secrets infrastructure validation)
- Revised: 2-3 hours (validation + documentation focus)

**Risk level unchanged:** Low (validation and documentation)
