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

**Secrets Inventory (from infra sops-nix):**

| Secret File | Usage | Type | Migration Strategy |
|------------|-------|------|-------------------|
| `admin-user/signing-key.yaml` | Git/jujutsu SSH signing | SSH private key | **Generate new** (ssh-keygen) |
| `admin-user/llm-api-keys.yaml` (glm) | GLM alternative LLM backend | API token | **Import existing** (manual transfer) |
| `admin-user/mcp-api-keys.yaml` (3 keys) | firecrawl, context7, huggingface | API tokens | **Import existing** (manual transfer) |
| `shared.yaml` (BITWARDEN_EMAIL) | Bitwarden password manager | Email address | **Prompt** (user input) |
| `raquel-user/*` | raquel's signing keys, API keys | Same as crs58 | **Same strategies** |

**⚠️ SECURITY PROTOCOL:** Whenever decryption and transfer of secret data is required, the dev agent MUST provide optimal sops/clan CLI commands for the orchestrator to execute interactively, avoiding population of secret values in the chat session.

---

## Acceptance Criteria

### A. Clan Vars Setup and Admin Configuration

**AC1: Clan Admin Keypair Generated**
- [ ] Run `clan secrets key generate` to create admin age keypair
- [ ] Verify keypair stored in `~/.config/sops/age/keys.txt`
- [ ] Record public key for adding users

**AC2: Cameron User Added to Clan Secrets**
- [ ] Run `clan secrets users add cameron --age-key <public-key>`
- [ ] Verify cameron added to `sops/users/cameron/key.json`
- [ ] Age keys configured for encryption/decryption

**AC3: Vars Directory Structure Created**
- [ ] Directory structure: `sops/vars/shared/`, `sops/vars/machines/`
- [ ] Verify clan vars directory structure follows clan-core conventions
- [ ] No conflicts with existing test-clan structure

### B. Vars Generators Defined (Pattern B - in user modules)

**AC4: crs58 Vars Module Created**
- [ ] Create `modules/home/users/crs58/vars.nix` with generators:
  - `ssh-signing-key`: SSH key generator (regenerable via ssh-keygen)
  - `llm-api-keys`: Prompt-based generator for GLM API key
  - `mcp-api-keys`: Multi-prompt generator (firecrawl, context7, huggingface)
  - `bitwarden-config`: Prompt for email
- [ ] Generators export secret file paths via clan.core.vars.generators.X.files.Y
- [ ] Generator types properly configured (password, secret, prompt)

**AC5: raquel Vars Module Created**
- [ ] Create `modules/home/users/raquel/vars.nix` with equivalent generators
- [ ] Same generator types as crs58 (ssh-signing-key, api-keys, bitwarden)
- [ ] Independent vars namespace (raquel vars separate from crs58)

**AC6: Vars Modules Integrated with Dendritic**
- [ ] Vars modules use dendritic export pattern: `flake.modules.homeManager."users/*/vars"`
- [ ] Import-tree auto-discovers vars.nix files
- [ ] User modules import vars via dendritic namespace (not relative paths)
- [ ] Verify flake.modules.homeManager."users/crs58/vars" and "users/raquel/vars" exist

### C. Module Access Pattern Updates (sops-nix → clan vars)

**AC7: Git Module SSH Signing Updated (crs58, raquel)**
- [ ] `modules/home/development/git.nix`: Update signing key access
  - Before: `config.sops.secrets."${user.sopsIdentifier}/signing-key".path`
  - After: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path`
- [ ] Pattern works for both crs58 and raquel (user-specific vars)
- [ ] Build validation: git signing config references correct path

**AC8: Jujutsu Module SSH Signing Updated (crs58, raquel)**
- [ ] `modules/home/development/jujutsu.nix`: Update signing key access (same as git)
- [ ] Verify both users get independent signing keys
- [ ] Build validation: jujutsu signing config references correct path

**AC9: MCP Servers API Keys Updated (crs58 only)**
- [ ] `modules/home/ai/claude-code/mcp-servers.nix`: Update 3 API key accesses
  - Before: `config.sops.secrets."mcp-firecrawl-api-key".path`
  - After: `config.clan.core.vars.generators.mcp-api-keys.files.firecrawl.path`
- [ ] Same for context7, huggingface keys
- [ ] raquel doesn't import ai aggregate (no MCP servers)

**AC10: Claude Code GLM Wrapper Updated (crs58 only)**
- [ ] `modules/home/ai/claude-code/wrappers.nix`: Update GLM API key access
- [ ] Reference: `config.clan.core.vars.generators.llm-api-keys.files.glm.path`
- [ ] raquel doesn't use GLM wrapper

**AC11: Bitwarden Email Updated (crs58, raquel)**
- [ ] `modules/home/ai/claude-code/rbw.nix` (crs58) or equivalent: Update Bitwarden email
- [ ] Reference: `config.clan.core.vars.generators.bitwarden-config.files.email.path`
- [ ] Both users get independent Bitwarden configs

### D. Vars Generation and Validation

**AC12: Generate Vars for crs58**
- [ ] Run: `clan vars generate blackphos --user crs58` (or equivalent command)
- [ ] Prompts for imported secrets (GLM API key, MCP keys, Bitwarden email)
- [ ] SSH signing key auto-generated (ssh-keygen)
- [ ] Verify encryption: `file sops/vars/*/secret` shows JSON (sops-encrypted)

**AC13: Generate Vars for raquel**
- [ ] Run: `clan vars generate blackphos --user raquel`
- [ ] Prompts for raquel's secrets
- [ ] Independent vars from crs58 (separate encryption)
- [ ] Verify raquel vars encrypted

**AC14: Build Validation**
- [ ] `nix build .#darwinConfigurations.blackphos.system` succeeds
- [ ] `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` succeeds
- [ ] `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` succeeds
- [ ] No evaluation errors related to vars access

**AC15: Secrets Accessible in Build**
- [ ] Verify `/run/secrets/vars/*` paths resolve in activation scripts
- [ ] SSH signing key paths point to generated keys
- [ ] API key paths point to imported secrets
- [ ] Bitwarden email path valid

**AC16: SSH Signing Validated**
- [ ] Git log shows signing key path configured
- [ ] Jujutsu log shows signing key path configured
- [ ] Post-deployment: GitHub signing keys update documented (see AC G)

### E. Dendritic + Clan Vars Integration Validation

**AC17: Pattern B Vars Work with Pattern A Modules**
- [ ] Vars generators (Pattern B in user modules) accessible from Pattern A home-manager modules
- [ ] No conflicts between dendritic imports and clan vars access
- [ ] `config.clan.core.vars.generators.*` paths resolve correctly in home-manager modules
- [ ] Flake context (from Pattern A) enables vars access

**AC18: Multi-User Vars Isolation**
- [ ] crs58 vars accessible only in crs58 home-manager config
- [ ] raquel vars accessible only in raquel home-manager config
- [ ] No vars namespace conflicts between users
- [ ] Independent encryption (different age keys if applicable)

**AC19: Import-Tree Discovers Vars Modules**
- [ ] vars.nix files auto-discovered in user directories
- [ ] Dendritic namespace exports work: `flake.modules.homeManager."users/*/vars"`
- [ ] No manual wiring required for vars discovery

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

**AC22: Pattern B Vars Documentation**
- [ ] Pattern B for vars (generators in user modules) explained
- [ ] NOT the Pattern B that failed for home-manager modules
- [ ] Dendritic integration: How Pattern A modules access Pattern B vars
- [ ] Rationale: Generator locality (vars near user config)

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

### Task 1: Clan Vars Setup and Admin Configuration (AC: 1-3)

**Estimated Time:** 30 minutes

- [ ] **1.1: Generate Clan Admin Keypair**
  - [ ] Run: `clan secrets key generate`
  - [ ] Verify: `cat ~/.config/sops/age/keys.txt | grep "AGE-SECRET-KEY"`
  - [ ] Record public key from output

- [ ] **1.2: Add Cameron User to Clan Secrets**
  - [ ] Get cameron's age public key (from existing setup or generate)
  - [ ] Run: `clan secrets users add cameron --age-key <public-key>`
  - [ ] Verify: `ls -la sops/users/cameron/`
  - [ ] Check: `cat sops/users/cameron/key.json`

- [ ] **1.3: Verify Vars Directory Structure**
  - [ ] Check structure: `tree sops/vars/` (if exists)
  - [ ] Create if needed: `mkdir -p sops/vars/{shared,machines}`
  - [ ] Verify no conflicts with existing test-clan structure

### Task 2: Define crs58 Vars Generators (AC: 4, 6)

**Estimated Time:** 1-1.5 hours

- [ ] **2.1: Create crs58 vars.nix File**
  - [ ] Create: `modules/home/users/crs58/vars.nix`
  - [ ] Use dendritic export pattern: `flake.modules.homeManager."users/crs58/vars" = { ... }`
  - [ ] Add flake-parts module signature

- [ ] **2.2: Define SSH Signing Key Generator**
  - [ ] Generator type: `clan.core.vars.generator` with ssh-keygen
  - [ ] Output files: `ed25519_priv`, `ed25519_pub`
  - [ ] Regenerable: Uses ssh-keygen to create new key
  - [ ] Reference clan-core generator examples

- [ ] **2.3: Define LLM API Keys Generator**
  - [ ] Generator type: prompt-based for GLM API key
  - [ ] Output file: `glm`
  - [ ] Prompt message: "Enter GLM API key for crs58"
  - [ ] Secret stored encrypted in sops/vars/

- [ ] **2.4: Define MCP API Keys Generator**
  - [ ] Generator type: multi-prompt for 3 keys (firecrawl, context7, huggingface)
  - [ ] Output files: `firecrawl`, `context7`, `huggingface`
  - [ ] Each with dedicated prompt message
  - [ ] All secrets encrypted separately

- [ ] **2.5: Define Bitwarden Config Generator**
  - [ ] Generator type: prompt for email address
  - [ ] Output file: `email`
  - [ ] Prompt message: "Enter Bitwarden email for crs58"

- [ ] **2.6: Verify Generator Export**
  - [ ] Check namespace: `nix eval .#flake.modules.homeManager."users/crs58/vars" --apply builtins.attrNames`
  - [ ] Verify import-tree discovers vars.nix
  - [ ] Build test: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage --dry-run`

### Task 3: Define raquel Vars Generators (AC: 5, 6)

**Estimated Time:** 30 minutes (copy and adapt from crs58)

- [ ] **3.1: Create raquel vars.nix File**
  - [ ] Create: `modules/home/users/raquel/vars.nix`
  - [ ] Use dendritic export: `flake.modules.homeManager."users/raquel/vars" = { ... }`
  - [ ] Copy crs58 generators structure

- [ ] **3.2: Adapt Generators for raquel**
  - [ ] ssh-signing-key: Same generator type, independent key
  - [ ] llm-api-keys: Prompt for raquel's GLM key (if needed, or omit)
  - [ ] mcp-api-keys: Likely omit (raquel doesn't use ai aggregate)
  - [ ] bitwarden-config: Prompt for raquel's email

- [ ] **3.3: Verify raquel Namespace**
  - [ ] Check: `nix eval .#flake.modules.homeManager."users/raquel/vars" --apply builtins.attrNames`
  - [ ] Verify independent from crs58 vars
  - [ ] Build test for raquel

### Task 4: Update Module Access Patterns (AC: 7-11)

**Estimated Time:** 1.5-2 hours

- [ ] **4.1: Update git.nix SSH Signing**
  - [ ] File: `modules/home/development/git.nix`
  - [ ] Replace sops-nix path with clan vars path
  - [ ] Before: `config.sops.secrets."${user.sopsIdentifier}/signing-key".path`
  - [ ] After: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path`
  - [ ] Handle user-specific vars (crs58 vs raquel)
  - [ ] Build test after change

- [ ] **4.2: Update jujutsu.nix SSH Signing**
  - [ ] File: `modules/home/development/jujutsu.nix`
  - [ ] Same clan vars path as git.nix
  - [ ] Verify user-specific vars work
  - [ ] Build test

- [ ] **4.3: Update mcp-servers.nix API Keys (crs58 only)**
  - [ ] File: `modules/home/ai/claude-code/mcp-servers.nix`
  - [ ] Replace 3 sops-nix secrets with clan vars paths:
    - firecrawl: `config.clan.core.vars.generators.mcp-api-keys.files.firecrawl.path`
    - context7: `config.clan.core.vars.generators.mcp-api-keys.files.context7.path`
    - huggingface: `config.clan.core.vars.generators.mcp-api-keys.files.huggingface.path`
  - [ ] Update sops.templates to reference new paths
  - [ ] Build test (crs58 only - raquel doesn't import ai aggregate)

- [ ] **4.4: Update wrappers.nix GLM API Key (crs58 only)**
  - [ ] File: `modules/home/ai/claude-code/wrappers.nix`
  - [ ] Replace sops-nix secret with clan vars path
  - [ ] After: `config.clan.core.vars.generators.llm-api-keys.files.glm.path`
  - [ ] Verify GLM wrapper package references correct path
  - [ ] Build test

- [ ] **4.5: Update Bitwarden Email (crs58, raquel)**
  - [ ] File: Locate rbw.nix or Bitwarden config module
  - [ ] Replace sops-nix path with clan vars path
  - [ ] After: `config.clan.core.vars.generators.bitwarden-config.files.email.path`
  - [ ] Both users get independent configs
  - [ ] Build test for both users

- [ ] **4.6: Commit Access Pattern Updates**
  - [ ] Commit: "refactor(story-1.10C): update module access patterns from sops-nix to clan vars"
  - [ ] Verify all modules updated (git, jujutsu, mcp-servers, wrappers, rbw)

### Task 5: Generate and Validate Vars (AC: 12-16)

**Estimated Time:** 1-1.5 hours (includes secret transfer protocol)

- [ ] **5.1: Generate crs58 Vars**
  - [ ] Run: `clan vars generate blackphos --user crs58` (or equivalent)
  - [ ] For regenerable secrets (ssh-signing-key): Auto-generated, verify output
  - [ ] For imported secrets (GLM, MCP keys): SECURITY PROTOCOL
    1. Dev agent provides optimal sops command to decrypt from infra
    2. Orchestrator executes: `cd ~/projects/nix-workspace/infra && sops <file>`
    3. Orchestrator copies values
    4. Dev agent provides optimal clan vars set command
    5. Orchestrator enters values interactively
  - [ ] For prompted secrets (Bitwarden email): Enter value when prompted
  - [ ] Verify encryption: `file sops/vars/*/secret` shows JSON encrypted

- [ ] **5.2: Generate raquel Vars**
  - [ ] Run: `clan vars generate blackphos --user raquel`
  - [ ] Same SECURITY PROTOCOL for secret transfer
  - [ ] Verify independent encryption from crs58
  - [ ] Check vars directory structure for raquel

- [ ] **5.3: Build Validation (All Configs)**
  - [ ] Build darwinConfigurations: `nix build .#darwinConfigurations.blackphos.system`
  - [ ] Build crs58 home: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`
  - [ ] Build raquel home: `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage`
  - [ ] No evaluation errors related to vars
  - [ ] Record build success

- [ ] **5.4: Verify Secrets Accessible**
  - [ ] Check activation scripts reference `/run/secrets/vars/*` paths
  - [ ] SSH signing key paths resolve
  - [ ] API key paths resolve
  - [ ] Bitwarden email path valid
  - [ ] Verify in nix repl if needed: `nix repl` → `:lf .` → inspect config

- [ ] **5.5: SSH Signing Path Validation**
  - [ ] Git config shows signing key path: Check `programs.git.signing.key` in build
  - [ ] Jujutsu config shows signing key path: Check `programs.jujutsu.signing.key`
  - [ ] Paths point to clan vars generated keys
  - [ ] Document public key location for GitHub update (AC20)

### Task 6: Integration and Multi-User Validation (AC: 17-19)

**Estimated Time:** 30 minutes

- [ ] **6.1: Pattern A + Pattern B Integration**
  - [ ] Verify Pattern A home-manager modules access Pattern B vars
  - [ ] git.nix (Pattern A) → crs58 vars (Pattern B): Works
  - [ ] mcp-servers.nix (Pattern A) → crs58 vars (Pattern B): Works
  - [ ] No conflicts between dendritic imports and clan vars access
  - [ ] Flake context enables vars access (from extraSpecialArgs)

- [ ] **6.2: Multi-User Vars Isolation**
  - [ ] crs58 config only sees crs58 vars
  - [ ] raquel config only sees raquel vars
  - [ ] Check namespace separation in builds
  - [ ] Verify no cross-contamination

- [ ] **6.3: Import-Tree Discovery**
  - [ ] Verify vars.nix auto-discovered: `fd vars.nix modules/home/users/`
  - [ ] Check dendritic exports: `nix eval .#flake.modules.homeManager --apply builtins.attrNames | grep vars`
  - [ ] No manual wiring needed for discovery

- [ ] **6.4: Commit Integration Validation**
  - [ ] Commit: "test(story-1.10C): validate Pattern A+B integration and multi-user vars"

### Task 7: Documentation (AC: 20-24)

**Estimated Time:** 1-1.5 hours

- [ ] **7.1: Document SSH Signing Public Key**
  - [ ] Extract crs58 public key: `ssh-keygen -y -f sops/vars/crs58/ssh-signing-key/ed25519_priv`
  - [ ] Extract raquel public key (same command for raquel path)
  - [ ] Document location in story completion notes
  - [ ] GitHub instructions: Settings → SSH and GPG keys → New SSH key → Signing key
  - [ ] Post-deployment validation steps

- [ ] **7.2: Create Secrets Migration Guide**
  - [ ] Document sops-nix → clan vars conversion process
  - [ ] Migration strategies table (generate new, import existing, prompt)
  - [ ] Security protocol for manual secret transfer (steps from Task 5.1)
  - [ ] Clan vars generator patterns (ssh-keygen, password, prompt examples)
  - [ ] File: `docs/notes/development/secrets-migration-guide.md` (in test-clan or infra)

- [ ] **7.3: Document Pattern B for Vars**
  - [ ] Explain Pattern B vars (generators in user modules) vs Pattern B home-manager (deprecated)
  - [ ] Why different patterns: Vars locality (near user config) vs modules composability
  - [ ] Dendritic integration: Pattern A modules + Pattern B vars works
  - [ ] Rationale section in architecture doc
  - [ ] File: Update `test-clan-validated-architecture.md` Section 11 or new section

- [ ] **7.4: Create Operational Guide**
  - [ ] How to add new secrets: Edit vars.nix, run `clan vars generate`
  - [ ] How to regenerate vars for new machines: `clan vars generate <machine>`
  - [ ] How to update GitHub signing keys: Extract public key, add to GitHub settings
  - [ ] Clan vars CLI reference: generate, regenerate, list, show commands
  - [ ] File: `docs/notes/development/clan-vars-ops-guide.md`

- [ ] **7.5: Access Pattern Examples**
  - [ ] Before/after comparison table: sops-nix paths → clan vars paths
  - [ ] Code examples from actual modules:
    - git.nix signing key
    - mcp-servers.nix API keys (3 examples)
    - wrappers.nix GLM key
  - [ ] Multi-user examples: Show crs58 vs raquel vars access patterns
  - [ ] Include in secrets migration guide or separate examples doc

- [ ] **7.6: Final Documentation Commit**
  - [ ] Commit: "docs(story-1.10C): comprehensive clan vars migration and operational guides"
  - [ ] Verify all 4 documentation files created/updated
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
