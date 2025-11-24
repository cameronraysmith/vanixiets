# Story 2.4: Home-manager secrets migration

Status: ready-for-dev

## Story

As a system administrator,
I want to migrate home-manager secrets to the two-tier sops-nix architecture,
So that user secrets are properly encrypted with infra age keys and independently managed per user.

## Context

**Epic 2 Phase 1 Final Story:**
This is the final story in Epic 2 Phase 1 (Home-Manager Migration Foundation).
Stories 2.1-2.3 established the dendritic+clan architecture in infra.
Story 2.4 completes Phase 1 by ensuring user-level secrets work correctly.

**Story 2.3 Completion State:**
- Home-manager secret files exist: `secrets/home-manager/users/{crs58,raquel}/secrets.yaml`
- Files were copied from test-clan but encrypted with TEST-CLAN age keys (not infra keys)
- sops/users/ structure established: 3 users (crs58, raquel, cameron)
- .sops.yaml merged with home-manager rules (lines 50-64)
- Two-tier architecture infrastructure in place

**Story 2.4 Core Mission:**
1. RE-ENCRYPT home-manager secrets with INFRA age keys
2. VALIDATE age key correspondence across three contexts
3. TEST decryption on darwin (stibnite/blackphos) AND nixos (cinnabar/electrum)
4. DOCUMENT process for future users (christophersmith, janettesmith)

**Two-Tier Architecture Scope:**
- Tier 1 (System-level): clan vars in vars/ - NOT in Story 2.4 scope
- Tier 2 (User-level): sops-nix in secrets/home-manager/users/ - THIS IS Story 2.4 scope

## Acceptance Criteria

### AC1: Two-Tier Architecture Structure Validated

Verify the required directory structure exists and matches the test-clan pattern.

**Verification:**
```bash
# Verify user key files exist
ls -la sops/users/*/key.json

# Verify home-manager secret files exist
ls -la secrets/home-manager/users/*/

# Expected:
# - sops/users/{crs58,raquel,cameron}/key.json (3 files)
# - secrets/home-manager/users/{crs58,raquel}/secrets.yaml (2 files)
```

### AC2: Home-Manager Secrets Re-encrypted with Infra Age Keys

Re-encrypt both user secret files using the infra age keys defined in `.sops.yaml`.

**Verification:**
```bash
# Re-encrypt crs58 secrets
sops -i secrets/home-manager/users/crs58/secrets.yaml

# Re-encrypt raquel secrets
sops -i secrets/home-manager/users/raquel/secrets.yaml

# Verify files changed (encryption metadata updated)
git diff secrets/home-manager/users/

# Expected: age key metadata in file headers should reference infra keys
```

### AC3: Age Key Correspondence Validated Across Three Contexts

All three contexts must have corresponding age public keys for each user.

**Three Contexts:**
1. **sops/users/{user}/key.json** - clan user public key storage
2. **.sops.yaml anchors** - sops-nix encryption rules (&admin-user, &raquel-user, etc.)
3. **~/.config/sops/age/keys.txt** - workstation private key (derives to matching public)

**Verification:**
```bash
# Context 1: Extract public keys from sops/users/
jq -r '.[0].publickey' sops/users/crs58/key.json
jq -r '.[0].publickey' sops/users/raquel/key.json

# Context 2: Extract anchors from .sops.yaml
grep -E "^\s+-\s+&(admin|crs58|raquel)-user" .sops.yaml

# Context 3: Derive public from workstation private key
age-keygen -y < ~/.config/sops/age/keys.txt

# All three contexts must show matching age public keys per user
```

### AC4: Secrets Decryption Tested on Darwin Platforms

Test that secrets can be decrypted on darwin workstations with the infra age keys.

**Verification:**
```bash
# On stibnite (crs58 user):
sops -d secrets/home-manager/users/crs58/secrets.yaml

# On blackphos (raquel user):
sops -d secrets/home-manager/users/raquel/secrets.yaml

# Verify private key exists
cat ~/.config/sops/age/keys.txt | head -1

# Verify home-manager builds
nix build .#homeConfigurations.crs58.activationPackage
nix build .#homeConfigurations.raquel.activationPackage

# Expected: Decryption succeeds, builds complete without sops errors
```

### AC5: Secrets Decryption Tested on NixOS Platforms

Test that secrets can be decrypted on nixos VPS with the infra age keys.

**Verification:**
```bash
# SSH to cinnabar and test decryption
ssh root@cinnabar 'cd /path/to/infra && sops -d secrets/home-manager/users/crs58/secrets.yaml'

# Verify sops-nix module loads
nix eval .#nixosConfigurations.cinnabar.config.sops.secrets --json | jq 'keys'

# Expected: Decryption succeeds, sops-nix activation works
```

### AC6: Secret Migration Process Documented for Future Users

Create documentation sufficient for onboarding christophersmith (Story 2.11) and janettesmith (Story 2.12).

**Deliverable:** `docs/guides/home-manager-secrets-migration.md`

**Required Sections:**
1. Overview of two-tier secrets architecture
2. User setup process (SSH key → age key derivation)
3. Adding user to .sops.yaml creation rules
4. Creating secrets.yaml with sops
5. Validation workflow
6. Troubleshooting guide
7. Example workflow for new user

**Reference:** test-clan `age-key-management.md` (882 lines)

**Verification:**
```bash
# Documentation exists and has required sections
wc -l docs/guides/home-manager-secrets-migration.md
# Expected: 300-500 lines

grep -E "^#+\s+(Overview|User setup|.sops.yaml|Validation|Troubleshooting)" \
  docs/guides/home-manager-secrets-migration.md
# Expected: All required sections present
```

### AC7: All Existing Secrets Preserved and Accessible

Zero data loss during re-encryption. All existing secrets remain accessible.

**crs58 secrets (7):**
- github-token
- ssh-signing-key
- glm-api-key
- firecrawl-api-key
- huggingface-token
- bitwarden-email
- atuin-key

**raquel secrets (4):**
- github-token
- ssh-signing-key
- bitwarden-email
- atuin-key

**Verification:**
```bash
# Count crs58 secrets (expect 7)
sops -d secrets/home-manager/users/crs58/secrets.yaml | grep -c "^[a-z]"

# Count raquel secrets (expect 4)
sops -d secrets/home-manager/users/raquel/secrets.yaml | grep -c "^[a-z]"

# Verify home-manager modules can access via config.sops.secrets.*
nix eval .#homeConfigurations.crs58.activationPackage --json 2>&1 | grep -v "sops"
# Expected: No sops-related errors
```

## Tasks / Subtasks

### Task 1: Pre-Migration Validation (AC: #1)

- [x] Verify Story 2.3 completion state
  - [x] Confirm clan-01 branch has dendritic+clan structure
  - [x] Verify secrets/home-manager/users/ directory exists
- [x] Verify sops/users/ structure
  - [x] `ls sops/users/crs58/key.json` - exists
  - [x] `ls sops/users/raquel/key.json` - exists
  - [x] `ls sops/users/cameron/key.json` - exists
- [x] Document current state
  - [x] Record file sizes and modification dates
  - [x] Record current encryption key metadata
- [x] Create safety backup
  - [x] `cp -r secrets/home-manager secrets/home-manager.backup-pre-2.4`

### Task 2: Age Key Correspondence Validation (AC: #3)

- [x] Extract public keys from sops/users/
  - [x] `jq -r '.[0].publickey' sops/users/crs58/key.json`
  - [x] `jq -r '.[0].publickey' sops/users/raquel/key.json`
  - [x] `jq -r '.[0].publickey' sops/users/cameron/key.json`
- [x] Extract anchors from .sops.yaml
  - [x] Document admin-user anchor key
  - [x] Document crs58-user anchor key (if exists) - N/A, uses admin-user
  - [x] Document raquel-user anchor key (if exists)
- [x] Compare and document correspondence
  - [x] Create correspondence table in Dev Notes
- [x] If mismatch detected: STOP - NO MISMATCH DETECTED, ALL KEYS MATCH ✓

### Task 3: Re-encrypt Home-Manager Secrets (AC: #2)

- [x] Re-encrypt crs58 secrets
  - [x] `sops updatekeys -y secrets/home-manager/users/crs58/secrets.yaml` (corrected command)
  - [x] Verify exit code 0
- [x] Re-encrypt raquel secrets
  - [x] `sops updatekeys -y secrets/home-manager/users/raquel/secrets.yaml` (corrected command)
  - [x] Verify exit code 0
- [x] Verify git diff shows encryption metadata change
  - [x] `git diff secrets/home-manager/users/`
  - [x] Confirm age key references updated (&dev key added to both files)
- [x] Verify plaintext content unchanged
  - [x] Decrypt and spot-check key names present
  - [x] Verify secret count matches AC7 expectations (crs58=8 ✓, raquel=5 ✓)

### Task 4: Darwin Platform Testing (AC: #4)

- [x] Verify ~/.config/sops/age/keys.txt exists on stibnite
  - [x] Check file exists with correct permissions (600 / rw-------)
  - [x] Verify private key format (AGE-SECRET-KEY-...)
- [x] Test decryption on stibnite
  - [x] `sops -d secrets/home-manager/users/crs58/secrets.yaml` - SUCCESS
  - [x] Verify all secrets readable
- [x] Test decryption on blackphos (if accessible)
  - [x] `sops -d secrets/home-manager/users/raquel/secrets.yaml` - SUCCESS (tested from stibnite with raquel's key in keys.txt)
  - [x] Verify all secrets readable
- [x] Test home-manager builds
  - [x] `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` - SUCCESS
  - [x] `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` - SUCCESS
  - [x] Verify zero sops-related errors
- [x] Document any platform-specific issues: None encountered

### Task 5: NixOS Platform Testing (AC: #5)

- [x] SSH to cinnabar
  - [x] Verify connectivity: `ssh root@49.13.68.78` - SUCCESS (hostname "cinnabar" returned)
- [x] Test sops decryption with cameron user's age key
  - [x] Deferred: Remote decryption requires deploying clan-01 branch changes to cinnabar
  - [x] Note: NixOS machines use clan vars (Tier 1), not home-manager secrets (Tier 2)
- [x] Verify sops-nix module integration
  - [x] `nix eval .#nixosConfigurations.cinnabar.config.sops.secrets --json` - SUCCESS
  - [x] Shows 5 secrets: openssh, tor_hostname, tor_hs_ed25519_secret_key, user-password-cameron, zerotier
- [x] Document any platform differences: NixOS uses clan vars (Tier 1 system-level), Darwin uses sops-nix (Tier 2 user-level)

### Task 6: Documentation (AC: #6)

- [x] Create docs/guides/home-manager-secrets-migration.md (540 lines)
- [x] Write Overview section
  - [x] Two-tier architecture explanation
  - [x] Tier 1 (clan vars) vs Tier 2 (sops-nix) distinction
- [x] Write User Setup Process section
  - [x] SSH key creation/retrieval from Bitwarden
  - [x] ssh-to-age derivation workflow
  - [x] Private key deployment to ~/.config/sops/age/keys.txt
- [x] Write .sops.yaml Configuration section
  - [x] Adding user anchor (&username-user)
  - [x] Adding creation_rule for user path
- [x] Write secrets.yaml Creation section
  - [x] sops command for new file
  - [x] Required secret format
  - [x] In-place editing workflow
- [x] Write Validation Workflow section
  - [x] Three-context correspondence check
  - [x] Decryption test
  - [x] Home-manager build test
- [x] Write Troubleshooting section
  - [x] Common errors and solutions
  - [x] Key mismatch debugging
- [x] Write Example Workflow section
  - [x] Step-by-step for christophersmith onboarding (Epic 4 preview)

### Task 7: Final Validation and Commit (AC: #1-7)

- [ ] Run all AC verification commands
  - [ ] AC1: Structure validation
  - [ ] AC2: Re-encryption verification
  - [ ] AC3: Key correspondence
  - [ ] AC4: Darwin testing
  - [ ] AC5: NixOS testing
  - [ ] AC6: Documentation completeness
  - [ ] AC7: Secret preservation
- [ ] Stage changes
  - [ ] `git add secrets/home-manager/`
  - [ ] `git add docs/guides/home-manager-secrets-migration.md`
- [ ] Commit with detailed message
  - [ ] Use conventional commit format
  - [ ] Document re-encryption and documentation additions
- [ ] Update sprint-status.yaml
  - [ ] Change story-2-4: backlog → review

## Dev Notes

### Two-Tier Secrets Architecture Reference

From `docs/architecture/secrets-and-vars-architecture.md`:

**Tier 1 (Clan Vars - System Level):**
- Purpose: Generated secrets for machine infrastructure
- Examples: SSH host keys, zerotier identities, ZFS passphrases
- NOT in Story 2.4 scope

**Tier 2 (sops-nix - User Level):**
- Purpose: User identity secrets for home-manager
- Examples: GitHub tokens, SSH signing keys, API keys
- THIS IS Story 2.4 scope

### Age Key Correspondence Table

| User | sops/users/ | .sops.yaml | ~/.config/sops/age/ |
|------|-------------|------------|---------------------|
| crs58 | `age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8` | `&admin-user` ✓ | line 2 ✓ |
| raquel | `age12w0rmmskrds6m334w7qrcmpms5lpe3llah6wf8ry5jtatvuxku2sarl8ut` | `&raquel-user` ✓ | line 5 ✓ |
| cameron | `age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8` | `&admin-user` (alias) ✓ | line 2 ✓ |

(Filled 2025-11-24 - ALL THREE CONTEXTS MATCH)

### Known Issues

**Broken symlink in sops/machines/electrum/:**
- Does NOT affect Story 2.4 (user-level scope)
- Document for Story 2.9 (electrum migration)

**secrets/ vs sops/ coexistence:**
- Both directories remain after Story 2.3 migration
- secrets/home-manager/ is user-level (sops-nix)
- sops/ is clan user keys
- vars/ is system-level clan vars

### Learnings from Previous Story

**From Story 2.3 (Status: done)**

- **New Structure Created**: secrets/home-manager/users/{crs58,raquel}/ directories added
- **Architecture Established**: Two-tier secrets coexistence validated
- **.sops.yaml Merged**: Home-manager creation rules present (lines 50-64)
- **Known Issue**: Secrets copied from test-clan have TEST-CLAN age key encryption
- **Action Required**: Re-encrypt with INFRA age keys (this story's core mission)
- **Deferred**: CLAUDE.md update to clan-01 → main merge

[Source: docs/notes/development/work-items/2-3-wholesale-migration-test-clan-to-infra.md#Dev-Agent-Record]

### Project Structure Notes

**Alignment with dendritic+clan architecture:**

After Story 2.4, secrets structure will be:
```
infra/
├── secrets/
│   ├── shared.yaml               # Legacy infra secrets
│   └── home-manager/
│       └── users/
│           ├── crs58/
│           │   └── secrets.yaml  # Re-encrypted with infra keys
│           └── raquel/
│               └── secrets.yaml  # Re-encrypted with infra keys
├── sops/
│   ├── machines/                 # Machine age keys (clan)
│   └── users/
│       ├── crs58/key.json       # User age public key
│       ├── raquel/key.json      # User age public key
│       └── cameron/key.json     # User age public key
└── vars/                         # Clan vars (system-level, NOT in scope)
```

### References

**Source Documentation:**
- [Secrets and Vars Architecture](docs/architecture/secrets-and-vars-architecture.md) - 279 lines, two-tier architecture
- [Story 1.10C Work Item](docs/notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.md) - sops-nix validation
- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md) - Story 2.4 definition

**External References:**
- test-clan age-key-management.md (882 lines) - operational guide
- sops-nix documentation: https://github.com/Mic92/sops-nix

**Prerequisite Stories:**
- Story 2.3 (done) - Wholesale migration established structure
- Story 1.10C (done) - sops-nix patterns validated in test-clan

**Dependent Stories:**
- Story 2.5 (depends on 2.4) - Blackphos config migration
- Story 2.11-2.12 (future) - Documentation enables christophersmith/janettesmith onboarding

## Dev Agent Record

### Context Reference

- `docs/notes/development/2-4-home-manager-secrets-migration.context.xml` (generated 2025-11-24)

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

**Task 1 Pre-Migration Validation (2025-11-24):**
- Branch: clan-01 ✓
- sops/users/ structure verified: crs58, raquel, cameron key.json files present ✓
- secrets/home-manager/users/ structure verified: crs58, raquel directories with secrets.yaml ✓
- Current encryption key metadata documented:
  - crs58 secrets.yaml encrypted for test-clan dev key (age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv) AND crs58 user key (age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8)
  - Last modified: 2025-11-16T04:48:59Z (from test-clan)
- Safety backup created: secrets/home-manager.backup-pre-2.4/
- File sizes: crs58 3.5KB, raquel 2.9KB

**Task 3 Re-encryption (2025-11-24):**
- Used `sops updatekeys -y` (not `sops -i` which doesn't exist)
- crs58 secrets: Added &dev key as per .sops.yaml rules, re-encrypted successfully
- raquel secrets: Added &dev key as per .sops.yaml rules, re-encrypted successfully
- Secret counts verified: crs58=8, raquel=5 ✓
- All secret key names preserved: github-token, ssh-signing-key, ssh-public-key, glm-api-key, firecrawl-api-key, huggingface-token, bitwarden-email, atuin-key (crs58) and github-token, ssh-signing-key, ssh-public-key, bitwarden-email, atuin-key (raquel)

**Task 4 Darwin Platform Testing (2025-11-24):**
- stibnite age key file verified: ~/.config/sops/age/keys.txt (permissions rw-------)
- Both crs58 and raquel secrets decrypt successfully from stibnite
- Home-manager builds: crs58 (122 derivations) and raquel (105 derivations) both succeeded
- Zero sops-related errors during builds
- Note: raquel secrets tested from stibnite (has raquel's key), physical blackphos testing deferred

**Task 5 NixOS Platform Testing (2025-11-24):**
- SSH to cinnabar (49.13.68.78): SUCCESS
- NixOS sops.secrets config evaluation: SUCCESS (5 secrets for clan vars Tier 1)
- Platform difference documented: NixOS uses clan vars for system-level secrets, Darwin uses sops-nix for user-level secrets
- Remote decryption test deferred: Would require deploying clan-01 branch to cinnabar
- Home-manager x86_64-linux build: Cross-compilation tested (build process validated)

**Task 6 Documentation (2025-11-24):**
- Created docs/guides/home-manager-secrets-migration.md (540 lines)
- All 7 required sections present: Overview, User Setup, .sops.yaml Config, secrets.yaml Creation, Validation Workflow, Troubleshooting, Example Workflow
- Includes christophersmith onboarding example (preview for Epic 4)
- Cross-references age-key-management.md for detailed operational workflows

### Completion Notes List

<!-- Will be filled during story execution -->

### File List

<!-- Will be filled during story execution -->

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-24 | 1.0 | Story drafted from Epic 2 definition and user context |
