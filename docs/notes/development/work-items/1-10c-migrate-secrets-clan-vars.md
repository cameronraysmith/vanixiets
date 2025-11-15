# Story 1.10C: Migrate Secrets from sops-nix to Clan Vars

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.10BA (done): Pattern A refactoring provides flake context access for clan vars integration

**Blocks:**
- Story 1.10D (backlog): Feature enablement requires clan vars infrastructure
- Story 1.12 (backlog): Physical deployment needs functional secrets

**Strategic Value:** Establishes clan vars infrastructure (clan-core's recommended secrets pattern) following Pattern B for vars generators (generators in user module directories, NOT the Pattern B that failed for home-manager modules), validates clan vars at scale (6 secrets × 2 users), unblocks Story 1.10D feature enablement (11 features need secrets), provides Epic 2-6 scalable pattern (clan vars shared across 6 machines), proves dendritic + clan vars compatibility using Pattern A architecture.

---

## Story Description

As a system administrator,
I want to migrate 6 sops-nix encrypted secrets to clan vars generators following Pattern B for vars (generators in user modules),
So that test-clan uses clan-core's recommended secrets management pattern and enables scalable multi-machine secret deployment.

**Context:**

Story 1.8 deferred secrets migration, Story 1.10 never addressed secrets (0% clan vars coverage in test-clan). Investigation (2025-11-14) revealed infra has 6 sops-nix encrypted files while test-clan has zero clan vars generators defined. Physical deployment would fail (no SSH signing keys, no MCP API keys, no GLM API key).

**Clan Vars Architecture Understanding:**
- Clan vars IS sops-nix (declarative wrapper interface)
- `clan.core.vars.generators` provides type-safe generators with automatic sops-nix encryption
- macOS explicitly supported (darwin-compatible)
- Pattern B for vars (generators in user modules) aligns with dendritic philosophy
- Pattern A home-manager modules (Story 1.10BA) provide flake context for clan vars access

**Secrets Inventory (from infra sops-nix - VERIFIED 2025-11-15):**

| Secret | Source File | Usage | Type | Migration Strategy |
|--------|------------|-------|------|-------------------|
| `github-token` | `secrets/shared.yaml` | Git operations, gh CLI | API token | **Import existing** (sops decrypt) |
| `ssh-signing-key` | `secrets/users/admin-user/signing-key.yaml` | Git/jujutsu SSH signing | SSH private key | **Generate new** (ssh-keygen) |
| `glm-api-key` | `secrets/users/admin-user/llm-api-keys.yaml` | GLM wrapper backend | API token | **Import existing** (sops decrypt) |
| `firecrawl-api-key` | `secrets/users/admin-user/mcp-api-keys.yaml` | Firecrawl MCP server | API token | **Import existing** (sops decrypt) |
| `huggingface-token` | `secrets/users/admin-user/mcp-api-keys.yaml` | HuggingFace MCP server | API token | **Import existing** (sops decrypt) |
| `bitwarden-email` | `secrets/shared.yaml` | Bitwarden config | Email address | **Import existing** (sops decrypt) |
| `atuin-key` | Runtime extraction | Shell history sync | Encryption key | **Extract existing** (`atuin key --base64`) |

**User Distribution:**
- crs58/cameron (7 secrets): All secrets above
- raquel (4 secrets): github-token, ssh-signing-key, bitwarden-email, atuin-key
- Rationale: raquel uses development + shell aggregates only (no ai tools)

**⚠️ SECURITY PROTOCOL:** Whenever decryption and transfer of secret data is required, the dev agent MUST provide optimal sops/clan CLI commands for the orchestrator to execute interactively, avoiding population of secret values in the chat session.

---

## Implementation Notes (2025-11-15)

**Discovered During Implementation:**

Investigation revealed multiple discrepancies between story assumptions and test-clan reality.
Story updated to reflect actual state based on evidence-based findings.

**Infrastructure Already Exists (AC1-AC3 SKIP):**
- ✅ Admin age keypair exists: 4 keys in `~/.config/sops/age/keys.txt`
- ✅ Sops setup complete: `sops/users/crs58/`, `sops/machines/*`, `sops/secrets/*`
- ✅ Vars directory exists: `vars/shared/`, `vars/per-machine/*` (note: per-machine NOT machines)
- Stories 1.1-1.10A already established sops/vars infrastructure
- **No setup work needed** - proceed directly to generator creation

**User Identity Pattern (Confirmed):**
- Cameron shares crs58 sops identity (same home module, same encryption key)
- Raquel shares crs58 sops identity (development + shell aggregates only)
- Single vars.nix in `modules/home/users/crs58/vars.nix` serves all three usernames
- Conditional secret access based on username (crs58/cameron get all 7, raquel gets subset of 4)

**Module Location Reality (Code Investigation):**
- Aggregates own logic: `modules/home/development/`, `modules/home/ai/`, `modules/home/shell/`
- User modules minimal: `modules/home/users/crs58/default.nix` imports aggregates
- Update paths in aggregates, NOT user directories
- Raquel configuration: development + shell only (no ai aggregate)

**Actual Secrets Inventory (Verified from infra):**

crs58/cameron (7 secrets):
1. `github-token` (shared.yaml) - Git operations, gh CLI
2. `ssh-signing-key` (admin-user/signing-key.yaml) - Git/jujutsu commit signing
3. `glm-api-key` (admin-user/llm-api-keys.yaml) - GLM wrapper
4. `firecrawl-api-key` (admin-user/mcp-api-keys.yaml) - Firecrawl MCP server
5. `huggingface-token` (admin-user/mcp-api-keys.yaml) - HuggingFace MCP server
6. `bitwarden-email` (shared.yaml) - Bitwarden password manager
7. `atuin-key` (extract with `atuin key --base64`) - Atuin shell history sync

raquel (4 secrets for development + shell aggregates):
1. `github-token` - Git operations
2. `ssh-signing-key` - Git commit signing
3. `bitwarden-email` - Bitwarden config
4. `atuin-key` - Shell history sync

**Note:** Only 2 MCP API keys exist (firecrawl, huggingface), not 3.
Original story mentioned "context7" which does not exist in infra secrets.

**Correct Module Paths for Updates:**
- `modules/home/development/git.nix` - ssh-signing-key, github-token
- `modules/home/development/jujutsu.nix` - ssh-signing-key (if configured)
- `modules/home/ai/claude-code/mcp-servers.nix` - firecrawl-api-key, huggingface-token
- `modules/home/ai/claude-code/wrappers.nix` - glm-api-key
- `modules/home/shell/atuin.nix` - atuin-key
- Bitwarden module location TBD (need to find or create)

---

## Acceptance Criteria

### A. Clan Vars Setup and Admin Configuration - ✅ SKIP (Already Complete)

**AC1: Clan Admin Keypair Generated** - ✅ COMPLETE (Stories 1.1-1.10A)
- [x] ~~Run `clan secrets key generate`~~ - Already exists (4 keys in ~/.config/sops/age/keys.txt)
- [x] ~~Verify keypair stored~~ - Verified during investigation (2025-11-15)
- [x] ~~Record public key~~ - Existing infrastructure functional

**AC2: User Added to Clan Secrets** - ✅ COMPLETE (Modified Approach)
- [x] ~~Add cameron to sops users~~ - Cameron shares crs58 sops identity (confirmed pattern)
- [x] ~~Verify sops/users/cameron/~~ - Using sops/users/crs58/ (single identity for cameron/crs58/raquel)
- [x] ~~Age keys configured~~ - Encryption working (verified via existing vars)

**AC3: Vars Directory Structure Created** - ✅ COMPLETE (Stories 1.1-1.10A)
- [x] ~~Directory structure~~ - vars/shared/, vars/per-machine/* exist (note: per-machine NOT machines)
- [x] ~~Verify clan vars structure~~ - Follows clan-core conventions
- [x] ~~No conflicts~~ - Existing vars (user-password-cameron, machine-specific) functional

### B. Vars Generators Defined (Pattern B - in user modules)

**AC4: Unified Vars Module with Conditional Access**
- [ ] Create `modules/home/users/crs58/vars.nix` with 7 generators serving all users
- [ ] Generator structure with conditional username-based access:
  - `github-token`: Prompt generator (all users: crs58, cameron, raquel)
  - `ssh-signing-key`: SSH keygen generator (all users)
  - `glm-api-key`: Prompt generator (crs58/cameron only)
  - `firecrawl-api-key`: Prompt generator (crs58/cameron only)
  - `huggingface-token`: Prompt generator (crs58/cameron only)
  - `bitwarden-email`: Prompt generator (all users)
  - `atuin-key`: Manual extraction generator (all users)
- [ ] Generators export via `clan.core.vars.generators.X.files.Y.path`
- [ ] Conditional logic: crs58/cameron get all 7, raquel gets subset of 4

**AC5: Generator Types Properly Configured**
- [ ] `ssh-signing-key`: Uses ssh-keygen, outputs ed25519_priv + ed25519_pub
- [ ] API token generators: Use password/prompt type with hidden input
- [ ] `bitwarden-email`: Uses prompt type with line input
- [ ] `atuin-key`: Custom generator with manual extraction note
- [ ] All secret files marked with `secret = true`, pub keys `secret = false`

**AC6: Dendritic Integration**
- [ ] Vars module exports to `flake.modules.homeManager."users/crs58/vars"`
- [ ] Import-tree auto-discovers vars.nix file
- [ ] No relative paths (uses dendritic namespace)
- [ ] Verify export: `nix eval .#flake.modules.homeManager."users/crs58/vars" --apply builtins.attrNames`

### C. Module Access Pattern Updates (sops-nix → clan vars)

**AC7: Git Module Updated (all users)**
- [ ] `modules/home/development/git.nix`: Update for SSH signing + GitHub token
  - SSH signing: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path`
  - GitHub token: Add if needed for gh CLI or git operations
  - Allowed signers: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_pub.value`
- [ ] Pattern works for crs58, cameron, raquel (shared vars.nix)
- [ ] Build validation: git config references correct clan vars paths

**AC8: Jujutsu Module Updated (if SSH signing configured)**
- [ ] `modules/home/development/jujutsu.nix`: Update signing key if already configured
- [ ] Reference: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path`
- [ ] Works for all users (crs58, cameron, raquel)

**AC9: MCP Servers API Keys Updated (crs58/cameron only)**
- [ ] `modules/home/ai/claude-code/mcp-servers.nix`: Update 2 API key accesses
  - Firecrawl: `config.clan.core.vars.generators.firecrawl-api-key.files.key.path`
  - HuggingFace: `config.clan.core.vars.generators.huggingface-token.files.token.path`
- [ ] Note: Only 2 MCP keys (no context7)
- [ ] raquel doesn't access (no ai aggregate)

**AC10: GLM Wrapper Updated (crs58/cameron only)**
- [ ] `modules/home/ai/claude-code/wrappers.nix`: Update GLM API key
- [ ] Reference: `config.clan.core.vars.generators.glm-api-key.files.key.path`
- [ ] raquel doesn't access (no ai aggregate)

**AC11: Atuin Shell History Updated (all users)**
- [ ] `modules/home/shell/atuin.nix`: Update encryption key
- [ ] Reference: `config.clan.core.vars.generators.atuin-key.files.key.path`
- [ ] Works for crs58, cameron, raquel (development + shell aggregates)

**AC12: Bitwarden Config Updated (all users)**
- [ ] Find or create Bitwarden/rbw module
- [ ] Reference: `config.clan.core.vars.generators.bitwarden-email.files.email.path`
- [ ] Works for crs58, cameron, raquel

### D. Vars Generation and Validation

**AC13: Manual Secret Extraction (Atuin)**
- [ ] Extract atuin key: `atuin key --base64` (run on machine with existing atuin setup)
- [ ] Record base64 key for manual entry during clan vars generation
- [ ] Note: Atuin key extracted from existing setup, not prompted from infra secrets

**AC14: Generate Vars for All Users**
- [ ] Run: `clan vars generate blackphos` (generates for all configured users)
- [ ] Or per-user: `clan vars generate blackphos --user crs58` then raquel
- [ ] Prompts for secrets (orchestrator enters from infra sops decrypt):
  - github-token (from shared.yaml via sops -d)
  - glm-api-key (from admin-user/llm-api-keys.yaml via sops -d)
  - firecrawl-api-key (from admin-user/mcp-api-keys.yaml via sops -d)
  - huggingface-token (from admin-user/mcp-api-keys.yaml via sops -d)
  - bitwarden-email (from shared.yaml via sops -d)
  - atuin-key (from manual extraction AC13)
- [ ] SSH signing key auto-generated (ssh-keygen, regenerable)
- [ ] Verify encryption: `file vars/per-machine/blackphos/*/secret` shows JSON (sops-encrypted)

**AC15: Build Validation (Corrected Paths)**
- [ ] `nix flake check` passes
- [ ] `nix build .#darwinConfigurations.blackphos.system` succeeds
- [ ] `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` succeeds (note: .activationPackage suffix)
- [ ] `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` succeeds
- [ ] No evaluation errors related to vars access

**AC16: Secrets Accessible in Build**
- [ ] Verify `/run/secrets/vars/*` paths resolve in activation scripts
- [ ] SSH signing key paths: vars/per-machine/blackphos/ssh-signing-key/ed25519_priv
- [ ] API key paths: vars/per-machine/blackphos/{glm,firecrawl,huggingface}/*
- [ ] Atuin key path: vars/per-machine/blackphos/atuin-key/key
- [ ] GitHub token, bitwarden email paths valid

### E. Dendritic + Clan Vars Integration Validation

**AC17: Pattern B Vars Work with Pattern A Modules**
- [ ] Vars generators (Pattern B in user modules) accessible from Pattern A home-manager modules
- [ ] No conflicts between dendritic imports and clan vars access
- [ ] `config.clan.core.vars.generators.*` paths resolve correctly in home-manager modules
- [ ] Flake context (from Pattern A) enables vars access

**AC18: Multi-User Conditional Access**
- [ ] crs58/cameron access all 7 generators (shared identity, full access)
- [ ] raquel accesses subset of 4 generators (conditional logic in vars.nix)
- [ ] No vars namespace conflicts (single vars.nix with conditional access)
- [ ] Shared encryption (all use sops/users/crs58/ age key)

**AC19: Import-Tree Discovers Vars Module**
- [ ] Single vars.nix file auto-discovered in users/crs58/
- [ ] Dendritic namespace export works: `flake.modules.homeManager."users/crs58/vars"`
- [ ] No manual wiring required for vars discovery
- [ ] Imported by user modules (users/crs58/default.nix) via dendritic namespace

### F. GitHub Signing Key Update Documentation

**AC20: Document New SSH Signing Public Key**
- [ ] Extract public key from generated ssh-signing-key: `ssh-keygen -y -f <path>`
- [ ] Document location of new public key
- [ ] Instructions for adding to GitHub (Settings → SSH and GPG keys → Signing keys)
- [ ] Post-deployment validation: Verify commits signed with new key

### G. Documentation

**AC21: Secrets Migration Guide**
- [ ] sops-nix → clan vars conversion documented
- [ ] Migration strategy for each secret type (generate new, import existing, prompt)
- [ ] Security protocol: Manual transfer steps for sensitive secrets
- [ ] Clan vars generator patterns (ssh-keygen, password, prompt)

**AC22: Unified Vars Pattern Documentation**
- [ ] Single vars.nix with conditional access explained
- [ ] Shared sops identity (cameron/crs58/raquel use same encryption key)
- [ ] Conditional secret access: username-based logic (all get 7 vs subset of 4)
- [ ] Pattern A modules access clan vars via `config.clan.core.vars.generators.*`
- [ ] Rationale: Simplifies management, single source of truth for all user secrets

**AC23: Operational Guide**
- [ ] How to add new secrets to existing users
- [ ] How to regenerate vars for new machines
- [ ] How to update GitHub signing keys after deployment
- [ ] Clan vars CLI reference (generate, regenerate, list)

**AC24: Access Pattern Examples**
- [ ] Before/after comparisons: sops-nix → clan vars
- [ ] Code examples: git.nix, mcp-servers.nix, wrappers.nix
- [ ] Multi-user examples: crs58 vs raquel vars access

---

## Tasks / Subtasks

### Task 1: Clan Vars Setup and Admin Configuration (AC: 1-3) - ✅ SKIP

**Status:** Complete from Stories 1.1-1.10A

- [x] ~~1.1: Generate Clan Admin Keypair~~ - Already exists (4 keys verified)
- [x] ~~1.2: Add User to Clan Secrets~~ - crs58 sops user exists, cameron/raquel share identity
- [x] ~~1.3: Verify Vars Directory Structure~~ - vars/shared/, vars/per-machine/* exist and functional

### Task 2: Create Unified Vars Module with Conditional Access (AC: 4-6)

**Estimated Time:** 1.5-2 hours

- [ ] **2.1: Create crs58 vars.nix File**
  - [ ] Create: `modules/home/users/crs58/vars.nix`
  - [ ] Use dendritic export pattern: `flake.modules.homeManager."users/crs58/vars" = { ... }`
  - [ ] Add flake-parts module signature

- [ ] **2.2: Define 7 Generators with Conditional Access**
  - [ ] `github-token`: Prompt generator (all users)
  - [ ] `ssh-signing-key`: SSH keygen (all users), outputs ed25519_priv + ed25519_pub
  - [ ] `glm-api-key`: Prompt generator (crs58/cameron only)
  - [ ] `firecrawl-api-key`: Prompt generator (crs58/cameron only)
  - [ ] `huggingface-token`: Prompt generator (crs58/cameron only)
  - [ ] `bitwarden-email`: Prompt generator (all users)
  - [ ] `atuin-key`: Manual extraction generator (all users)

- [ ] **2.3: Implement Conditional Logic**
  - [ ] Username detection: Use config.home.username or similar
  - [ ] crs58/cameron: Access all 7 generators
  - [ ] raquel: Access 4 generators (github-token, ssh-signing-key, bitwarden-email, atuin-key)
  - [ ] Conditional file exports based on username

- [ ] **2.4: Add Security Notes for Manual Extraction**
  - [ ] atuin-key: Note in generator to run `atuin key --base64` manually
  - [ ] SSH signing key: Auto-generated (ssh-keygen), regenerable
  - [ ] API tokens: Prompt-based, orchestrator enters from infra sops decrypt

- [ ] **2.5: Verify Generator Export**
  - [ ] Check namespace: `nix eval .#flake.modules.homeManager."users/crs58/vars" --apply builtins.attrNames`
  - [ ] Verify import-tree discovers vars.nix
  - [ ] Build test: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage --dry-run`

### ~~Task 3: Define raquel Vars Generators~~ - REMOVED

**Status:** Merged into Task 2 (single vars.nix with conditional access)

### Task 3: Update Module Access Patterns (AC: 7-12)

**Note:** Renumbered from Task 4 after removing separate raquel vars task

**Estimated Time:** 1.5-2 hours

- [ ] **3.1: Update git.nix (all users)**
  - [ ] File: `modules/home/development/git.nix` (aggregate module)
  - [ ] SSH signing: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path`
  - [ ] GitHub token: Add if needed for gh CLI
  - [ ] Allowed signers: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_pub.value`
  - [ ] Works for crs58, cameron, raquel (shared vars.nix)
  - [ ] Build test all users

- [ ] **3.2: Update jujutsu.nix (if configured)**
  - [ ] File: `modules/home/development/jujutsu.nix` (aggregate module)
  - [ ] SSH signing: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path`
  - [ ] Build test

- [ ] **3.3: Update mcp-servers.nix (crs58/cameron only)**
  - [ ] File: `modules/home/ai/claude-code/mcp-servers.nix` (aggregate module)
  - [ ] Replace 2 sops-nix secrets with clan vars paths (Note: only 2, not 3):
    - firecrawl: `config.clan.core.vars.generators.firecrawl-api-key.files.key.path`
    - huggingface: `config.clan.core.vars.generators.huggingface-token.files.token.path`
  - [ ] Conditional access: crs58/cameron only (raquel has no ai aggregate)
  - [ ] Build test crs58

- [ ] **3.4: Update wrappers.nix (crs58/cameron only)**
  - [ ] File: `modules/home/ai/claude-code/wrappers.nix` (aggregate module)
  - [ ] GLM API key: `config.clan.core.vars.generators.glm-api-key.files.key.path`
  - [ ] Build test crs58

- [ ] **3.5: Update atuin.nix (all users)**
  - [ ] File: `modules/home/shell/atuin.nix` (aggregate module)
  - [ ] Encryption key: `config.clan.core.vars.generators.atuin-key.files.key.path`
  - [ ] Works for all users (development + shell aggregates)
  - [ ] Build test all users

- [ ] **3.6: Update/Create Bitwarden Module (all users)**
  - [ ] Find or create Bitwarden/rbw module
  - [ ] Email config: `config.clan.core.vars.generators.bitwarden-email.files.email.path`
  - [ ] Build test all users

- [ ] **3.7: Commit Access Pattern Updates**
  - [ ] Commit: "refactor(story-1.10C): update module access patterns from sops-nix to clan vars"
  - [ ] Verify all 6 modules updated

### Task 4: Generate and Validate Vars (AC: 13-16)

**Note:** Renumbered from Task 5 after removing Task 3

**Estimated Time:** 1-1.5 hours (includes secret transfer protocol)

- [ ] **4.1: Extract Atuin Key Manually (AC13)**
  - [ ] Run on machine with existing atuin: `atuin key --base64`
  - [ ] Record base64 key for entering during vars generation
  - [ ] Note: Manual extraction, not from infra secrets

- [ ] **4.2: Generate Vars for All Users (AC14)**
  - [ ] Run: `clan vars generate blackphos` (generates for all users)
  - [ ] Or per-user if needed: `clan vars generate blackphos --user crs58`
  - [ ] SSH signing key: Auto-generated (ssh-keygen), regenerable
  - [ ] For imported secrets: SECURITY PROTOCOL
    1. Dev agent provides sops decrypt command for infra secrets
    2. Orchestrator: `cd ~/projects/nix-workspace/infra && sops -d secrets/users/admin-user/<file>.yaml`
    3. Orchestrator copies specific key values
    4. Enter when clan vars prompts
  - [ ] Secrets to enter (orchestrator decrypts from infra):
    - github-token (from shared.yaml)
    - glm-api-key (from admin-user/llm-api-keys.yaml)
    - firecrawl-api-key (from admin-user/mcp-api-keys.yaml)
    - huggingface-token (from admin-user/mcp-api-keys.yaml)
    - bitwarden-email (from shared.yaml)
    - atuin-key (from manual extraction AC13)
  - [ ] Verify encryption: `file vars/per-machine/blackphos/*/secret` shows JSON

- [ ] **4.3: Build Validation (AC15)**
  - [ ] `nix flake check` passes
  - [ ] `nix build .#darwinConfigurations.blackphos.system` succeeds
  - [ ] `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` succeeds
  - [ ] `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` succeeds
  - [ ] No evaluation errors related to vars

- [ ] **4.4: Verify Secrets Accessible (AC16)**
  - [ ] Check activation scripts reference correct paths
  - [ ] SSH signing key: vars/per-machine/blackphos/ssh-signing-key/ed25519_priv
  - [ ] API keys: vars/per-machine/blackphos/{glm,firecrawl,huggingface}/*
  - [ ] Atuin key: vars/per-machine/blackphos/atuin-key/key
  - [ ] GitHub token, bitwarden email paths valid

- [ ] **4.5: SSH Signing Path Validation**
  - [ ] Git config references clan vars signing key path
  - [ ] Jujutsu config references clan vars signing key path (if configured)
  - [ ] Document public key location for GitHub update (AC20)

### Task 5: Integration and Multi-User Validation (AC: 17-19)

**Note:** Renumbered from Task 6 after removing Task 3

**Estimated Time:** 30 minutes

- [ ] **5.1: Pattern A Modules + Clan Vars Integration (AC17)**
  - [ ] Verify Pattern A home-manager modules access clan vars
  - [ ] git.nix (Pattern A) → clan vars generators: Works
  - [ ] mcp-servers.nix (Pattern A) → clan vars generators: Works
  - [ ] No conflicts between dendritic imports and clan vars access
  - [ ] Flake context enables vars access via `config.clan.core.vars.generators.*`

- [ ] **5.2: Multi-User Conditional Access (AC18)**
  - [ ] crs58/cameron access all 7 generators (verified in builds)
  - [ ] raquel accesses subset of 4 generators (conditional logic works)
  - [ ] Shared encryption (all use sops/users/crs58/ age key)
  - [ ] No namespace conflicts (single vars.nix serves all users)

- [ ] **5.3: Import-Tree Discovery (AC19)**
  - [ ] Verify vars.nix auto-discovered: `fd vars.nix modules/home/users/crs58/`
  - [ ] Check dendritic export: `nix eval .#flake.modules.homeManager."users/crs58/vars"`
  - [ ] No manual wiring needed for discovery
  - [ ] User modules import via dendritic namespace

- [ ] **5.4: Commit Integration Validation**
  - [ ] Commit: "test(story-1.10C): validate Pattern A + clan vars integration and conditional access"

### Task 6: Documentation (AC: 20-24)

**Note:** Renumbered from Task 7 after removing Task 3

**Estimated Time:** 1-1.5 hours

- [ ] **6.1: Document SSH Signing Public Key (AC20)**
  - [ ] Extract public key: `ssh-keygen -y -f vars/per-machine/blackphos/ssh-signing-key/ed25519_priv`
  - [ ] Document location in story completion notes
  - [ ] GitHub instructions: Settings → SSH and GPG keys → New SSH key → Signing key
  - [ ] Post-deployment validation steps (verify commits signed)

- [ ] **6.2: Create Secrets Migration Guide (AC21)**
  - [ ] Document sops-nix → clan vars conversion process
  - [ ] Migration strategies: generate new (SSH), import existing (API keys), manual extraction (atuin)
  - [ ] Security protocol for manual secret transfer (from Task 4.2)
  - [ ] Clan vars generator patterns (ssh-keygen, password prompts, manual extraction)
  - [ ] File: `docs/notes/development/secrets-migration-guide.md` (test-clan or infra)

- [ ] **6.3: Document Unified Vars Pattern (AC22)**
  - [ ] Single vars.nix with conditional access explained
  - [ ] Shared sops identity (cameron/crs58/raquel use same age key)
  - [ ] Conditional secret access: username-based (7 vs 4 generators)
  - [ ] Pattern A modules access clan vars via `config.clan.core.vars.generators.*`
  - [ ] Rationale: Simplifies management, single source of truth
  - [ ] File: Update `test-clan-validated-architecture.md` with new section

- [ ] **6.4: Create Operational Guide (AC23)**
  - [ ] How to add new secrets: Edit vars.nix conditional logic, run `clan vars generate`
  - [ ] How to regenerate vars for new machines: `clan vars generate <machine>`
  - [ ] How to update GitHub signing keys: Extract public key, update GitHub settings
  - [ ] Clan vars CLI reference: generate, list commands
  - [ ] Manual extraction workflows (atuin key example)
  - [ ] File: `docs/notes/development/clan-vars-ops-guide.md`

- [ ] **6.5: Create Access Pattern Examples (AC24)**
  - [ ] Before/after code snippets: sops-nix → clan vars
  - [ ] Module examples: git.nix, mcp-servers.nix, wrappers.nix, atuin.nix
  - [ ] Conditional access examples: crs58/cameron (all 7) vs raquel (subset 4)
  - [ ] Include in migration guide or architecture doc

- [ ] **6.6: Final Documentation Commit**
  - [ ] Commit: "docs(story-1.10C): comprehensive clan vars migration and operational guides"
  - [ ] Verify documentation files created/updated
  - [ ] Link docs in story completion notes

---

## Dev Notes

### Architectural Context

**Clan Vars Architecture:**

Clan vars is clan-core's declarative interface to sops-nix, providing type-safe generators with automatic encryption:

```nix
# Vars generator (Pattern B - in user module)
# File: modules/home/users/crs58/vars.nix
{
  flake.modules.homeManager."users/crs58/vars" = {
    clan.core.vars.generators = {
      ssh-signing-key = {
        generator = "ssh-keygen";  # Regenerable
        files = {
          ed25519_priv = {};
          ed25519_pub = {};
        };
      };

      mcp-api-keys = {
        generator = "password";  # Prompt-based for secrets
        files = {
          firecrawl = { description = "Firecrawl MCP API key"; };
          context7 = { description = "Context7 MCP API key"; };
          huggingface = { description = "HuggingFace MCP API key"; };
        };
      };
    };
  };
}

# Access in home-manager module (Pattern A)
# File: modules/home/development/git.nix
{ config, pkgs, flake, ... }: {
  programs.git.signing.key =
    config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path;
  # Path resolves to: /run/secrets/vars/ssh-signing-key/ed25519_priv
}
```

**Pattern B for Vars (Different from Pattern B Home-Manager):**

- **Pattern B home-manager (DEPRECATED):** Plain modules without flake context (failed in Story 1.10B)
- **Pattern B vars (VALIDATED):** Generators in user module directories, accessed via Pattern A modules
- **Why Different:** Vars locality (near user config) vs modules composability (require flake context)
- **Integration:** Pattern A modules (with flake parameter) access Pattern B vars (user-local generators)

**Benefits:**
- Type-safe generator interface (ssh-keygen, password, prompt)
- Automatic sops-nix encryption (no manual sops configuration)
- Darwin-compatible (clan vars works on macOS)
- Multi-user isolation (crs58 vars independent from raquel vars)
- Scalable across machines (Epic 2-6: vars shared across 6 machines)

**Secrets Inventory:**

From infra sops-nix analysis (2025-11-14):

| Secret | Current Location (infra) | Type | Users | Migration |
|--------|-------------------------|------|-------|-----------|
| SSH signing key | `admin-user/signing-key.yaml` | Ed25519 private key | crs58, raquel | Generate new (ssh-keygen) |
| GLM API key | `admin-user/llm-api-keys.yaml` | API token | crs58 | Import (manual transfer) |
| Firecrawl MCP key | `admin-user/mcp-api-keys.yaml` | API token | crs58 | Import (manual transfer) |
| Context7 MCP key | `admin-user/mcp-api-keys.yaml` | API token | crs58 | Import (manual transfer) |
| HuggingFace MCP key | `admin-user/mcp-api-keys.yaml` | API token | crs58 | Import (manual transfer) |
| Bitwarden email | `shared.yaml` | Email address | crs58, raquel | Prompt (user input) |

**Security Transfer Protocol:**

For importing existing API keys from infra sops-nix to test-clan clan vars:

1. **Dev Agent Role:** Provide optimal sops and clan CLI commands
2. **Orchestrator Role:** Execute commands interactively to avoid exposing secrets in chat
3. **Process:**
   ```bash
   # Step 1: Dev agent provides decrypt command
   # Orchestrator executes:
   cd ~/projects/nix-workspace/infra
   sops admin-user/llm-api-keys.yaml  # Opens editor with decrypted content

   # Step 2: Orchestrator copies GLM API key value

   # Step 3: Dev agent provides clan vars set command
   # Orchestrator executes:
   cd ~/projects/nix-workspace/test-clan
   clan vars generate blackphos --user crs58
   # Enters GLM API key when prompted
   ```

4. **Validation:** Verify encrypted in sops/vars/, never committed in plaintext

### Learnings from Previous Story (Story 1.10BA)

**From Story 1.10BA (Status: done)**

Story 1.10BA refactored 17 home-manager modules from Pattern B (plain modules) to Pattern A (dendritic exports with flake context). This story (1.10C) builds on that foundation.

**Pattern A Provides Flake Context for Clan Vars:**
- Module signature: `{ config, pkgs, lib, flake, ... }` (includes `flake` parameter)
- Enables `config.clan.core.vars.generators.*` access (clan vars paths)
- Enables `flake.config.*` for user lookups (if needed)
- sops-nix compatibility restored (can use sops OR clan vars)

**Access Pattern Example (from Story 1.10BA git.nix):**
```nix
# Pattern A home-manager module (Story 1.10BA)
{ config, pkgs, lib, flake, ... }: {
  programs.git = {
    # Story 1.10BA restored sops-nix access:
    # signing.key = config.sops.secrets."${user}/signing-key".path;

    # Story 1.10C will update to clan vars:
    signing.key = config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path;
  };
}
```

**Key Takeaway:** Pattern A modules (Story 1.10BA) are ready for clan vars integration (Story 1.10C) because they have flake context access.

**Files to Update (from Story 1.10BA):**
- `modules/home/development/git.nix`: SSH signing key
- `modules/home/development/jujutsu.nix`: SSH signing key
- `modules/home/ai/claude-code/mcp-servers.nix`: 3 MCP API keys
- `modules/home/ai/claude-code/wrappers.nix`: GLM API key
- Bitwarden config module: Email address

**DO NOT Recreate:**
- Pattern B home-manager modules (plain modules without flake context) - use Pattern A
- Underscore directories for modules - Pattern A uses standard directories
- Relative imports - Pattern A uses aggregate namespace imports

**REUSE:**
- Pattern A module structure (flake.modules.homeManager.* pattern)
- Aggregate organization (development, ai, shell)
- Flake context access patterns (flake.inputs, flake.config, config.clan)

[Source: Story 1.10BA Dev Notes, Completion Notes, File List]

### Testing Standards

**Build Validation (CRITICAL):**

All builds must succeed with clan vars integration:

```bash
cd ~/projects/nix-workspace/test-clan

# homeConfigurations (both users)
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage

# darwinConfigurations (full system)
nix build .#darwinConfigurations.blackphos.system

# Verify no evaluation errors related to vars
# Verify /run/secrets/vars/* paths resolve
```

**Vars Generation Validation:**

```bash
# Generate vars for crs58
clan vars generate blackphos --user crs58
# - Prompts for GLM API key → Enter from infra sops
# - Prompts for 3 MCP keys → Enter from infra sops
# - Prompts for Bitwarden email → Enter email
# - Auto-generates SSH signing key → No prompt

# Verify encryption
file sops/vars/crs58/ssh-signing-key/ed25519_priv/secret
# Output: JSON data (sops-encrypted)

# Generate vars for raquel (same process)
clan vars generate blackphos --user raquel
```

**Access Pattern Validation:**

```bash
# Verify paths in nix repl
nix repl
:lf .
:p config.flake.homeConfigurations.aarch64-darwin.crs58.config.programs.git.signing.key
# Output: /run/secrets/vars/ssh-signing-key/ed25519_priv

# Verify MCP server API key paths (crs58 only)
:p config.flake.homeConfigurations.aarch64-darwin.crs58.config.programs.claude-code.mcp.servers.firecrawl.apiKeyPath
# Output: /run/secrets/vars/mcp-api-keys/firecrawl
```

**Multi-User Isolation Validation:**

```bash
# crs58 should have all vars (ssh, mcp, glm, bitwarden)
nix eval .#homeConfigurations.aarch64-darwin.crs58.config.clan.core.vars.generators --apply builtins.attrNames

# raquel should have subset (ssh, bitwarden, no mcp/glm)
nix eval .#homeConfigurations.aarch64-darwin.raquel.config.clan.core.vars.generators --apply builtins.attrNames

# Verify independent encryption
ls -la sops/vars/crs58/
ls -la sops/vars/raquel/
```

### Project Structure Notes

**Vars Directory Structure (Clan Vars Convention):**

```
test-clan/
├── sops/
│   ├── users/
│   │   └── cameron/
│   │       └── key.json              # Cameron age public key
│   └── vars/
│       ├── shared/                   # Shared vars (if any)
│       ├── machines/                 # Machine-specific vars (if any)
│       ├── crs58/                    # User-specific vars (crs58)
│       │   ├── ssh-signing-key/
│       │   │   ├── ed25519_priv/
│       │   │   │   └── secret        # sops-encrypted private key
│       │   │   └── ed25519_pub/
│       │   │       └── secret        # Public key
│       │   ├── mcp-api-keys/
│       │   │   ├── firecrawl/secret
│       │   │   ├── context7/secret
│       │   │   └── huggingface/secret
│       │   ├── llm-api-keys/
│       │   │   └── glm/secret
│       │   └── bitwarden-config/
│       │       └── email/secret
│       └── raquel/                   # User-specific vars (raquel)
│           ├── ssh-signing-key/
│           └── bitwarden-config/
```

**Module Structure (Pattern A + Pattern B Vars):**

```
test-clan/
├── modules/
│   └── home/
│       ├── development/              # Pattern A aggregate
│       │   ├── git.nix               # Accesses clan vars ssh-signing-key
│       │   └── jujutsu.nix           # Accesses clan vars ssh-signing-key
│       ├── ai/                       # Pattern A aggregate
│       │   └── claude-code/
│       │       ├── mcp-servers.nix   # Accesses clan vars mcp-api-keys
│       │       └── wrappers.nix      # Accesses clan vars llm-api-keys
│       └── users/
│           ├── crs58/
│           │   ├── default.nix       # Imports: development, ai, shell
│           │   └── vars.nix          # Pattern B vars generators (NEW)
│           └── raquel/
│               ├── default.nix       # Imports: development, shell
│               └── vars.nix          # Pattern B vars generators (NEW)
```

**Alignment with test-clan Architecture:**

- Clan vars follows clan-core conventions (sops/vars/ directory)
- Pattern B vars (generators in user modules) aligns with dendritic locality
- Pattern A modules (Story 1.10BA) provide flake context for vars access
- Multi-user isolation (crs58, raquel) via independent vars namespaces
- Import-tree auto-discovers vars.nix files (no manual wiring)

**No Conflicts:**
- Clan vars `sops/` does NOT conflict with dendritic `modules/`
- Pattern B vars does NOT conflict with Pattern A modules (different layers)
- User-specific vars (crs58, raquel) isolated in dendritic namespace

### Quick Reference

**Target Repository:** ~/projects/nix-workspace/test-clan/

**Clan Vars Commands:**

```bash
# Setup
clan secrets key generate                    # Generate admin keypair
clan secrets users add cameron --age-key KEY # Add user to secrets

# Vars Generation
clan vars generate blackphos --user crs58    # Generate crs58 vars (prompts for secrets)
clan vars generate blackphos --user raquel   # Generate raquel vars

# Vars Management
clan vars list blackphos                     # List all vars for machine
clan vars show blackphos ssh-signing-key     # Show specific var details
clan vars regenerate blackphos               # Regenerate all vars
```

**Build Commands:**

```bash
cd ~/projects/nix-workspace/test-clan

# Full builds (after vars generated)
nix build .#darwinConfigurations.blackphos.system
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage

# Dry-run builds (before vars generated)
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage --dry-run
```

**Secret Transfer (infra → test-clan):**

```bash
# Decrypt from infra (orchestrator executes)
cd ~/projects/nix-workspace/infra
sops admin-user/llm-api-keys.yaml  # Decrypt GLM key
sops admin-user/mcp-api-keys.yaml  # Decrypt MCP keys

# Import to test-clan (orchestrator enters values when prompted)
cd ~/projects/nix-workspace/test-clan
clan vars generate blackphos --user crs58
# Prompts:
# - GLM API key: [paste from infra sops]
# - Firecrawl key: [paste from infra sops]
# - Context7 key: [paste from infra sops]
# - HuggingFace key: [paste from infra sops]
# - Bitwarden email: [enter email]
```

**Module Files to Update:**

| File | Change | Users |
|------|--------|-------|
| `modules/home/development/git.nix` | sops → clan vars (ssh-signing-key) | crs58, raquel |
| `modules/home/development/jujutsu.nix` | sops → clan vars (ssh-signing-key) | crs58, raquel |
| `modules/home/ai/claude-code/mcp-servers.nix` | sops → clan vars (mcp-api-keys × 3) | crs58 only |
| `modules/home/ai/claude-code/wrappers.nix` | sops → clan vars (llm-api-keys glm) | crs58 only |
| Bitwarden config module | sops → clan vars (bitwarden-config email) | crs58, raquel |

**Vars Generators to Create:**

| User | Vars Module | Generators | Files |
|------|------------|------------|-------|
| crs58 | `modules/home/users/crs58/vars.nix` | ssh-signing-key, mcp-api-keys, llm-api-keys, bitwarden-config | 8 files total |
| raquel | `modules/home/users/raquel/vars.nix` | ssh-signing-key, bitwarden-config | 3 files total |

**Estimated Effort:** 4-6 hours
- Clan vars setup: 30 minutes (Task 1)
- Generators definition: 2 hours (Tasks 2-3)
- Module updates: 1.5-2 hours (Task 4)
- Vars generation + validation: 1-1.5 hours (Task 5-6)
- Documentation: 1-1.5 hours (Task 7)

**Risk Level:** Medium-High (encryption concerns, secret transfer, new pattern)

**Risk Mitigation:**
- Backup `~/.config/sops/age/keys.txt` before migration
- Test vars generation in separate branch first
- Validate encryption before committing (file sops/vars/*/secret shows encrypted JSON)
- Keep infra sops-nix secrets accessible for rollback
- SECURITY PROTOCOL: Manual secret transfer (dev agent provides commands, orchestrator executes)

### External References

**Clan Vars Documentation:**
- clan-core source: `~/projects/nix-workspace/clan-core/`
- Clan vars examples: `~/projects/nix-workspace/qubasa-clan-infra/` (complex generators)
- Pattern validation: `~/projects/nix-workspace/mic92-clan-dotfiles/` (legacy sops-nix, 128 secrets)

**Epic 1 Definition:**
- File: `~/projects/nix-workspace/infra/docs/notes/development/epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md`
- Lines 894-1039: Story 1.10C complete definition (this story)
- 16 acceptance criteria (AC A-G) with detailed requirements

**Story 1.10BA Context:**
- File: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10ba-refactor-pattern-a.md`
- Pattern A modules provide flake context for clan vars access
- Module files to update documented (git.nix, jujutsu.nix, mcp-servers.nix, wrappers.nix)

**Architecture Documentation:**
- test-clan architecture: `~/projects/nix-workspace/infra/docs/notes/development/test-clan-validated-architecture.md`
- Section 11 (lines 728-1086): Module system architecture (Pattern A modules + vars access)

**infra sops-nix Secrets (Source):**
- Location: `~/projects/nix-workspace/infra/secrets/`
- Files: `admin-user/signing-key.yaml`, `admin-user/llm-api-keys.yaml`, `admin-user/mcp-api-keys.yaml`, `shared.yaml`
- Migration strategy: Decrypt with sops, import to clan vars via SECURITY PROTOCOL

**Quality Baseline:**
- Story 1.10A: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10A-migrate-user-management-inventory.md`
  - Approved 5/5, comprehensive acceptance criteria, detailed tasks, complete documentation
- Story 1.10BA: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10ba-refactor-pattern-a.md`
  - Approved, Pattern A architecture validated, builds passing, features restored

---

## Dev Agent Record

### Context Reference

- Story Context XML: `docs/notes/development/work-items/1-10c-migrate-secrets-clan-vars.context.xml` (Generated: 2025-11-15)

### Agent Model Used

<!-- Agent model name and version will be recorded during implementation -->

### Debug Log References

<!-- Links to debug sessions, error analysis, investigation notes -->

### Completion Notes List

<!-- Implementation session summaries, discoveries, decisions -->

### File List

<!-- Files created/modified during implementation -->

---

## Learnings

<!-- Post-implementation insights, architectural discoveries, pattern validations -->
<!-- This section will be populated during implementation or Party Mode checkpoint -->

---

## Change Log

### 2025-11-15 - Story Created

- Story 1.10C drafted following create-story workflow
- Comprehensive story definition based on Epic 1 lines 894-1039
- 24 acceptance criteria across 7 sections (AC A-G)
- 7 tasks with detailed subtasks mapped to ACs
- Security protocol documented: Manual secret transfer to avoid exposing values in chat
- Pattern B for vars explained (different from deprecated Pattern B home-manager)
- Secrets inventory documented: 6 secrets (ssh-signing-key, 4 API keys, bitwarden email)
- Migration strategies defined: Generate new (ssh), import existing (APIs), prompt (email)
- Module access patterns documented: sops-nix → clan vars transformations
- Multi-user isolation: crs58 (all secrets) vs raquel (subset)
- Learnings from Story 1.10BA integrated: Pattern A modules ready for clan vars
- Testing standards: Build validation (3 builds), vars generation, access patterns, multi-user isolation
- Quick reference: Clan vars commands, build commands, secret transfer protocol, module files table
- External references: clan-core examples, Epic 1 definition, Story 1.10BA context, architecture docs
- Estimated effort: 4-6 hours (setup 30m + generators 2h + updates 1.5-2h + generation 1-1.5h + docs 1-1.5h)
- Risk level: Medium-High (encryption, secret transfer, new pattern)
- Risk mitigation: Backups, separate branch testing, encryption validation, security protocol
- Strategic value: Clan vars infrastructure, Epic 2-6 scalable pattern, dendritic + clan vars compatibility
- Dependencies: Story 1.10BA (Pattern A flake context)
- Blocks: Story 1.10D (feature enablement), Story 1.12 (physical deployment)
