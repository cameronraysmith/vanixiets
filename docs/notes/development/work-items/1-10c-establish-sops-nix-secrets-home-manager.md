# Story 1.10C: Establish sops-nix Secrets for Home-Manager

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.10BA (done): Pattern A refactoring provides flake context access for sops-nix integration

**Blocks:**
- Story 1.10D (backlog): Feature enablement requires secrets infrastructure
- Story 1.12 (backlog): Physical deployment needs functional secrets

**Strategic Value:** Validates sops-nix for home-manager (proven in infra, Epic 2-6 migration pattern), establishes user-level secrets boundary (system vs user separation), documents two-tier architecture (clan vars for system, sops-nix for users), unblocks Story 1.10D (11 features need secrets access), prevents architectural error propagation to Epic 2-6.

---

## Story Description

As a system administrator,
I want to establish sops-nix secrets management for home-manager user configurations,
So that test-clan users have secure access to personal secrets (API keys, git signing keys, tokens) using proven sops-nix pattern from infra repository.

**Context:**

Investigation (2025-11-15) revealed CRITICAL architectural incompatibility: clan vars module is NixOS-specific and cannot be imported into home-manager context.
Developer implemented 8/12 tasks using clan vars before discovering the incompatibility.

**Architectural Decision (Validated):**
- **System-level secrets** → clan vars (future, when test-clan adds NixOS/darwin machines)
- **User-level secrets** → sops-nix home-manager (Story 1.10C scope)
- **Age keys** → Reuse existing from sops/users/*/key.json (one keypair per user)

**Two-Tier Secrets Architecture:**
- Clan user management (sops/users/*/key.json) for SYSTEM secrets
- sops-nix home-manager with .sops.yaml for USER secrets
- Both use SAME age keypair (simpler, consistent)

**sops-nix Architecture Understanding:**
- Proven pattern in infra repository (working, established)
- Home-manager module: `sops-nix.homeManagerModules.sops`
- Configuration: .sops.yaml with creation_rules for multi-user encryption
- Secret files: YAML encrypted with sops -e
- Age key location: ~/.config/sops/age/keys.txt (shared with clan)

**Secrets Inventory (7 secrets - from infra sops-nix):**

| Secret | Usage | Type | Migration Strategy |
|--------|-------|------|-------------------|
| `github-token` | Git operations, gh CLI | API token | **Import existing** (sops decrypt from infra) |
| `ssh-signing-key` | Git/jujutsu SSH signing | SSH private key | **Import existing** (sops decrypt from infra) |
| `glm-api-key` | GLM wrapper backend | API token | **Import existing** (sops decrypt from infra) |
| `firecrawl-api-key` | Firecrawl MCP server | API token | **Import existing** (sops decrypt from infra) |
| `huggingface-token` | HuggingFace MCP server | API token | **Import existing** (sops decrypt from infra) |
| `bitwarden-email` | Bitwarden config | Email address | **Import existing** (sops decrypt from infra) |
| `atuin-key` | Shell history sync | Encryption key | **Extract existing** (`atuin key --base64`) |

**User Distribution:**
- crs58/cameron (7 secrets): All secrets above (development + ai + shell aggregates)
- raquel (4 secrets): github-token, ssh-signing-key, bitwarden-email, atuin-key (NO AI)
- Rationale: raquel uses development + shell aggregates only (no ai tools)

**⚠️ SECURITY PROTOCOL:** Whenever decryption and transfer of secret data is required, the dev agent MUST provide optimal sops CLI commands for the orchestrator to execute interactively, avoiding population of secret values in the chat session.

---

## Implementation Notes (2025-11-15)

**Architectural Pivot:**

Original story (clan vars approach) encountered critical blocker after 8/12 tasks completed (11 commits):

**Investigation Findings (Explore Agent, 2025-11-15):**
1. **Clan vars + home-manager incompatibility:**
   - ZERO reference repos use clan vars in home-manager modules
   - Evidence: mic92, qubasa, pinpox, jfly, enzime, clan-infra, onix examined
   - Conclusion: Clan vars designed for SYSTEM-level (NixOS/darwin) secrets, NOT home-manager

2. **User age key management architecture:**
   - Clan user management (sops/users/*/key.json) for SYSTEM secrets
   - sops-nix home-manager uses SEPARATE .sops.yaml configuration
   - BOTH can use SAME age keypair (one per user, simpler)
   - Conclusion: Two-tier architecture (system vs user secrets)

**Scope Change:**

**Original Title:** "Migrate Secrets from sops-nix to Clan Vars"
**Updated Title:** "Establish sops-nix Secrets for Home-Manager"

**Original Approach:** clan vars generators in home-manager modules
**Updated Approach:** sops-nix home-manager module with .sops.yaml configuration

**Rationale for Change:**
1. Clan vars incompatible with home-manager (NixOS-specific module)
2. sops-nix proven pattern in infra repository (working, established)
3. Reference repos validate two-tier architecture (system vs user secrets)
4. Simpler implementation (YAML secrets vs generator scripts)
5. Matches Epic 1 goal (validate architecture for infra migration)

**Work Completed (Salvageable from Clan Vars Attempt):**

Keep (8 tasks, 66% of work):
- ✅ Module updates: git.nix, jujutsu.nix, mcp-servers.nix, wrappers.nix, atuin.nix, rbw.nix
  - Only need to change access pattern (clan vars → sops.secrets)
  - Module structure and logic correct
- ✅ Conditional user access: crs58/cameron (7 secrets) vs raquel (4 secrets)
  - Pattern validated, just different implementation
- ✅ Atomic commits: 11 commits, well-documented
  - Easy to modify for sops-nix approach

Revert (2-3 tasks, 33% of work):
- ❌ Clan vars module import: (inputs.clan-core + "/nixosModules/clanCore/vars")
  - Replace with sops-nix module import
- ❌ vars.nix generators: modules/home/users/crs58/vars.nix
  - Replace with sops secrets declarations + secrets.yaml files
- ❌ Clan vars references: config.clan.core.vars.generators.*
  - Replace with config.sops.secrets.*

**Infrastructure Already Exists (AC1-AC3 SKIP):**
- ✅ Admin age keypair exists: 4 keys in `~/.config/sops/age/keys.txt`
- ✅ Sops setup complete: `sops/users/crs58/`, `sops/machines/*`, `sops/secrets/*`
- Stories 1.1-1.10A already established sops infrastructure
- **Age keys can be reused** - extract public keys from sops/users/*/key.json

---

## Acceptance Criteria

### A. Infrastructure Setup (AC1-AC3) - ✅ SKIP (Unchanged)

**AC1: Admin Keypair** - ✅ COMPLETE (Stories 1.1-1.10A)
- [x] Admin age keypair exists (4 keys in ~/.config/sops/age/keys.txt)
- [x] Public keys available in sops/users/*/key.json

**AC2: User Setup** - ✅ COMPLETE (Stories 1.1-1.10A)
- [x] crs58 sops user configured
- [x] Cameron/raquel share crs58 identity (single encryption key)

**AC3: Directory Structure** - ✅ COMPLETE (Stories 1.1-1.10A)
- [x] sops/ infrastructure exists
- [x] Age keys configured and functional

### B. sops-nix Configuration (AC4-AC6) - UPDATED

**AC4: Create .sops.yaml with Multi-User Encryption Configuration**
- [ ] Extract age public keys from sops/users/*/key.json
- [ ] Define creation_rules for per-user and shared secrets:
  - `secrets/home-manager/users/crs58/.*\.yaml$` encrypted for admin + crs58-user
  - `secrets/home-manager/users/raquel/.*\.yaml$` encrypted for admin + raquel-user
- [ ] Configure admin recovery key
- [ ] Multi-user encryption working (each user can only decrypt their secrets)

**AC5: Create sops-nix Home-Manager Module Infrastructure**
- [ ] Import sops-nix.homeManagerModules.sops in flake inputs
- [ ] Create base sops module: `modules/home/base/sops.nix`
- [ ] Configure sops.age.keyFile pointing to `${config.xdg.configHome}/sops/age/keys.txt`
- [ ] Set up base module for all users

**AC6: Define User-Specific sops Secrets Declarations**
- [ ] crs58: 7 secrets in `modules/home/users/crs58/sops.nix`
  - github-token, ssh-signing-key, glm-api-key, firecrawl-api-key, huggingface-token, bitwarden-email, atuin-key
- [ ] raquel: 4 secrets in `modules/home/users/raquel/sops.nix`
  - github-token, ssh-signing-key, bitwarden-email, atuin-key
- [ ] Conditional access via separate files (not runtime logic)
- [ ] Set defaultSopsFile per user

### C. Secret Files Creation (AC7-AC9) - NEW

**AC7: Create crs58 Secrets File**
- [ ] Path: `secrets/home-manager/users/crs58/secrets.yaml`
- [ ] Contents: All 7 secrets in YAML format
- [ ] Encryption: `sops -e` (encrypted for crs58 + admin)
- [ ] Source: Import from infra via sops decrypt + manual entry

**AC8: Create raquel Secrets File**
- [ ] Path: `secrets/home-manager/users/raquel/secrets.yaml`
- [ ] Contents: 4 secrets subset
- [ ] Encryption: `sops -e` (encrypted for raquel + admin)
- [ ] Source: Import from infra via sops decrypt + manual entry

**AC9: Verify Secrets Encryption**
- [ ] Test decryption: `sops -d secrets/home-manager/users/*/secrets.yaml`
- [ ] Verify age keys work correctly
- [ ] Confirm multi-user encryption (each user can only decrypt their secrets)
- [ ] File permissions correct (secret files encrypted, not plaintext)

### D. Module Access Pattern Updates (AC10-AC15) - UPDATED

**AC10: Update development/git.nix (all users)**
- [ ] Change: `config.clan.core.vars.*` → `config.sops.secrets.*`
- [ ] SSH signing: `config.sops.secrets.ssh-signing-key.path`
- [ ] GitHub token: `config.sops.secrets.github-token.path`
- [ ] Works for crs58, cameron, raquel (Pattern A modules)

**AC11: Update development/jujutsu.nix (all users)**
- [ ] SSH signing: `config.sops.secrets.ssh-signing-key.path`
- [ ] Works for crs58, cameron, raquel

**AC12: Update ai/claude-code/mcp-servers.nix (crs58/cameron only)**
- [ ] Firecrawl: `config.sops.secrets.firecrawl-api-key.path`
- [ ] HuggingFace: `config.sops.secrets.huggingface-token.path`
- [ ] Note: Only 2 MCP keys (no context7)
- [ ] raquel doesn't access (no ai aggregate)

**AC13: Update ai/claude-code/wrappers.nix (crs58/cameron only)**
- [ ] GLM: `config.sops.secrets.glm-api-key.path`
- [ ] raquel doesn't access (no ai aggregate)

**AC14: Update shell/atuin.nix (all users)**
- [ ] Atuin: `config.sops.secrets.atuin-key.path`
- [ ] Works for crs58, cameron, raquel (development + shell aggregates)

**AC15: Update/create Bitwarden module (all users)**
- [ ] Bitwarden: `config.sops.secrets.bitwarden-email.path`
- [ ] Works for crs58, cameron, raquel

### E. Build Validation (AC16-AC18) - UPDATED

**AC16: Nix Build Validation**
- [ ] `nix flake check` passes
- [ ] `nix build .#darwinConfigurations.blackphos.system` succeeds
- [ ] `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` succeeds
- [ ] `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` succeeds
- [ ] No evaluation errors related to sops

**AC17: sops-nix Deployment Validation**
- [ ] Secrets deployed to `$XDG_RUNTIME_DIR/secrets.d/`
- [ ] Symlinks created in `~/.config/sops-nix/secrets/`
- [ ] File permissions correct (secret files mode 0400)
- [ ] Paths resolve correctly in activation scripts

**AC18: Multi-User Isolation Validation**
- [ ] crs58 can access all 7 secrets
- [ ] raquel can access only 4 secrets (no AI)
- [ ] Verify raquel CANNOT decrypt crs58's AI API keys
- [ ] Age key encryption working per user

### F. Integration Validation (AC19-AC21) - UPDATED

**AC19: sops-nix Works with Pattern A Modules**
- [ ] Pattern A home-manager modules access sops secrets cleanly
- [ ] No conflicts between dendritic imports and sops access
- [ ] Flake context (from Pattern A) enables sops usage
- [ ] git.nix, mcp-servers.nix, wrappers.nix, atuin.nix all work

**AC20: Age Key Integration**
- [ ] Same age private key used by clan secrets AND sops-nix
- [ ] Key location: `~/.config/sops/age/keys.txt`
- [ ] Public keys in .sops.yaml match sops/users/*/key.json
- [ ] One keypair per user (simpler, consistent)

**AC21: Import-Tree Discovers sops Modules**
- [ ] sops-nix modules auto-discovered correctly
- [ ] Dendritic namespace export works with sops config
- [ ] Base sops module imported by user modules

### G. Documentation (AC22-AC24) - UPDATED

**AC22: Two-Tier Secrets Architecture Documentation**
- [ ] Document: System secrets (clan vars, future) vs User secrets (sops-nix, now)
- [ ] Location: Architecture doc Section 12
- [ ] Include: Age key reuse pattern, .sops.yaml configuration
- [ ] Rationale: Clan vars NixOS-specific, sops-nix home-manager compatible

**AC23: Age Key Management and sops-nix Operational Guide**
- [ ] Create docs/guides/age-key-management.md:
  - SSH-to-age derivation pattern (infra justfile workflow)
  - Clan user creation with SSH-derived keys (clan secrets users add)
  - Age key correspondence validation (jq, age-keygen -y)
  - Public key extraction for .sops.yaml (from clan user files)
  - Epic 2-6 new user workflow (Bitwarden → infra → clan → sops-nix)
- [ ] sops-nix operations (in age-key-management.md or separate section):
  - Adding new secrets (edit + encrypt workflow)
  - Multi-user encryption (creation_rules)
  - Secret rotation (re-encryption)
  - Troubleshooting (common errors, solutions)

**AC24: Access Pattern Examples**
- [ ] Before/after: clan vars approach vs sops-nix approach
- [ ] Code examples: git.nix, mcp-servers.nix, atuin.nix
- [ ] Multi-user examples: crs58 vs raquel sops configuration
- [ ] YAML secret file structure examples

---

## Tasks / Subtasks

### Task 1: Infrastructure Setup (AC1-AC3) - ✅ SKIP

**Status:** Complete from Stories 1.1-1.10A

- [x] 1.1: Admin age keypair exists
- [x] 1.2: crs58 sops user configured, cameron/raquel share identity
- [x] 1.3: sops/ infrastructure functional

### Task 2: Configure sops-nix Infrastructure (AC4-AC6)

**Estimated Time:** 1 hour

- [ ] **2.1: Create .sops.yaml with Multi-User Configuration**
  - [ ] Extract age public keys from sops/users/*/key.json (jq command)
  - [ ] Define keys section with anchors (&crs58-user, &raquel-user, &admin)
  - [ ] Define creation_rules for per-user secrets paths
  - [ ] Configure admin recovery key
  - [ ] Test encryption: `sops -e test.yaml` with .sops.yaml rules

- [ ] **2.2: Create Base sops-nix Module**
  - [ ] Path: `modules/home/base/sops.nix`
  - [ ] Import sops-nix home-manager module
  - [ ] Configure age.keyFile location: `${config.xdg.configHome}/sops/age/keys.txt`
  - [ ] Add flake-parts module signature
  - [ ] Export to dendritic namespace

- [ ] **2.3: Create Per-User sops Modules**
  - [ ] crs58: `modules/home/users/crs58/sops.nix` with 7 secrets declarations
  - [ ] raquel: `modules/home/users/raquel/sops.nix` with 4 secrets declarations
  - [ ] Set defaultSopsFile per user (secrets/home-manager/users/*/secrets.yaml)
  - [ ] Configure secret options (mode, owner, group if needed)

### Task 3: Create and Encrypt Secrets (AC7-AC9)

**Estimated Time:** 45 minutes

- [ ] **3.1: Create crs58 secrets.yaml**
  - [ ] Create directory: `secrets/home-manager/users/crs58/`
  - [ ] Create unencrypted YAML with 7 secrets (placeholders initially)
  - [ ] Import from infra: SECURITY PROTOCOL
    1. Dev agent provides sops decrypt command for infra secrets
    2. Orchestrator: `cd ~/projects/nix-workspace/infra && sops -d secrets/...`
    3. Orchestrator copies specific key values
    4. Populate crs58 secrets.yaml
  - [ ] Encrypt with sops: `sops -e -i secrets/home-manager/users/crs58/secrets.yaml`
  - [ ] Verify encryption: file shows binary/JSON encrypted data

- [ ] **3.2: Create raquel secrets.yaml**
  - [ ] Create directory: `secrets/home-manager/users/raquel/`
  - [ ] Create unencrypted YAML with 4 secrets (subset)
  - [ ] Import same secrets as crs58 (github-token, ssh-signing-key, bitwarden-email, atuin-key)
  - [ ] Encrypt with sops: `sops -e -i secrets/home-manager/users/raquel/secrets.yaml`
  - [ ] Verify encryption

- [ ] **3.3: Verify Secrets Encryption**
  - [ ] Test decryption: `sops -d secrets/home-manager/users/crs58/secrets.yaml`
  - [ ] Test decryption: `sops -d secrets/home-manager/users/raquel/secrets.yaml`
  - [ ] Confirm multi-user isolation (each user age key works)
  - [ ] Verify .sops.yaml creation_rules working correctly

### Task 4: Update Module Access Patterns (AC10-AC15)

**Estimated Time:** 1 hour

- [ ] **4.1: Update git.nix (all users)**
  - [ ] File: `modules/home/development/git.nix`
  - [ ] SSH signing: `config.sops.secrets.ssh-signing-key.path`
  - [ ] GitHub token: `config.sops.secrets.github-token.path` (if needed)
  - [ ] Build test: crs58, raquel

- [ ] **4.2: Update jujutsu.nix (if configured)**
  - [ ] File: `modules/home/development/jujutsu.nix`
  - [ ] SSH signing: `config.sops.secrets.ssh-signing-key.path`
  - [ ] Build test

- [ ] **4.3: Update mcp-servers.nix (crs58/cameron only)**
  - [ ] File: `modules/home/ai/claude-code/mcp-servers.nix`
  - [ ] Replace 2 sops-nix secrets with sops paths:
    - firecrawl: `config.sops.secrets.firecrawl-api-key.path`
    - huggingface: `config.sops.secrets.huggingface-token.path`
  - [ ] Conditional access: crs58/cameron only
  - [ ] Build test crs58

- [ ] **4.4: Update wrappers.nix (crs58/cameron only)**
  - [ ] File: `modules/home/ai/claude-code/wrappers.nix`
  - [ ] GLM API key: `config.sops.secrets.glm-api-key.path`
  - [ ] Build test crs58

- [ ] **4.5: Update atuin.nix (all users)**
  - [ ] File: `modules/home/shell/atuin.nix`
  - [ ] Encryption key: `config.sops.secrets.atuin-key.path`
  - [ ] Build test all users

- [ ] **4.6: Update/Create Bitwarden Module (all users)**
  - [ ] Find or create Bitwarden/rbw module
  - [ ] Email config: `config.sops.secrets.bitwarden-email.path`
  - [ ] Build test all users

- [ ] **4.7: Commit Access Pattern Updates**
  - [ ] Commit: "refactor(story-1.10C): update module access patterns to sops-nix"
  - [ ] Verify all 6 modules updated

### Task 5: Build and Validate (AC16-AC18)

**Estimated Time:** 30 minutes

- [ ] **5.1: Run Build Validation (AC16)**
  - [ ] `nix flake check`
  - [ ] `nix build .#darwinConfigurations.blackphos.system`
  - [ ] `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`
  - [ ] `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage`
  - [ ] Verify no evaluation errors

- [ ] **5.2: Test sops-nix Deployment (AC17)**
  - [ ] Check secrets deployed to `$XDG_RUNTIME_DIR/secrets.d/`
  - [ ] Verify symlinks in `~/.config/sops-nix/secrets/`
  - [ ] File permissions: mode 0400 for secret files
  - [ ] Paths resolve in activation scripts

- [ ] **5.3: Verify Multi-User Isolation (AC18)**
  - [ ] crs58 accesses all 7 secrets
  - [ ] raquel accesses only 4 secrets
  - [ ] Verify raquel cannot decrypt crs58's AI API keys
  - [ ] Age key encryption per user working

### Task 6: Integration and Testing (AC19-AC21)

**Estimated Time:** 30 minutes

- [ ] **6.1: Validate Pattern A + sops-nix Integration (AC19)**
  - [ ] Pattern A modules access sops secrets cleanly
  - [ ] No conflicts between dendritic imports and sops access
  - [ ] Flake context enables sops usage
  - [ ] All updated modules work (git, jujutsu, mcp, wrappers, atuin, rbw)

- [ ] **6.2: Verify Age Key Reuse Working (AC20)**
  - [ ] Same age private key used by clan AND sops-nix
  - [ ] Key location: `~/.config/sops/age/keys.txt`
  - [ ] Public keys in .sops.yaml match sops/users/*/key.json
  - [ ] One keypair per user confirmed

- [ ] **6.3: Test Import-Tree Discovery (AC21)**
  - [ ] sops-nix modules auto-discovered
  - [ ] Dendritic namespace export works
  - [ ] Base sops module imported correctly

- [ ] **6.4: Commit Integration Validation**
  - [ ] Commit: "test(story-1.10C): validate Pattern A + sops-nix integration"

### Task 7: Documentation (AC22-AC24)

**Estimated Time:** 60 minutes (updated for age-key-management.md scope)

- [ ] **7.1: Document Two-Tier Architecture (AC22)**
  - [ ] File: `test-clan-validated-architecture.md` Section 12
  - [ ] System secrets (clan vars, future) vs User secrets (sops-nix, now)
  - [ ] Age key reuse pattern
  - [ ] .sops.yaml configuration examples
  - [ ] Rationale: Clan vars NixOS-specific incompatibility

- [ ] **7.2: Create Age Key Management + sops-nix Operational Guide (AC23)**
  - [ ] File: `~/projects/nix-workspace/test-clan/docs/guides/age-key-management.md`
  - [ ] SSH-to-age derivation pattern:
    - Document infra justfile workflow (just sops-sync-keys)
    - Explain Bitwarden SSH keys as source of truth
    - Show age key extraction from ~/.config/sops/age/keys.txt
  - [ ] Clan user creation with SSH-derived keys:
    - clan secrets users add command with --age-key flag
    - Public key extraction: jq -r '.[0].publickey' sops/users/*/key.json
    - Key correspondence validation (derived public matches clan public)
  - [ ] sops-nix .sops.yaml configuration:
    - Extract public keys from clan user files
    - Define creation_rules for multi-user encryption
    - Verify private keys exist in shared keyfile
  - [ ] Epic 2-6 new user workflow:
    - Generate SSH key in Bitwarden (sops-${username}-ssh)
    - Run infra justfile to derive age keys
    - Add to test-clan clan users with derived public key
    - Configure .sops.yaml for new user's secrets
  - [ ] sops-nix operations:
    - Adding new secrets (edit + sops -e workflow)
    - Multi-user encryption (creation_rules syntax)
    - Secret rotation (re-encryption)
    - Troubleshooting (common errors, validation commands)

- [ ] **7.3: Write Access Pattern Examples (AC24)**
  - [ ] Before/after: clan vars → sops-nix
  - [ ] Code examples: git.nix, mcp-servers.nix, atuin.nix
  - [ ] Multi-user examples: crs58 (7 secrets) vs raquel (4 secrets)
  - [ ] YAML secret file structure
  - [ ] Include in migration guide or architecture doc

- [ ] **7.4: Final Documentation Commit**
  - [ ] Commit: "docs(story-1.10C): sops-nix architecture and operational guides"

**Total Estimated Time:** 4.75 hours (within original 3-5h estimate range, updated for age-key-management.md scope)

---

## Dev Notes

### Architectural Context

**Two-Tier Secrets Architecture (Epic 1 Finding):**

The architectural investigation revealed that clan-core provides TWO separate secrets systems:

1. **System-Level Secrets (clan vars):**
   - Module: `clan-core.nixosModules.clanCore.vars`
   - Scope: NixOS/nix-darwin system configurations
   - Use Case: Machine secrets, system services, VPN credentials
   - Storage: `sops/vars/`
   - Access: `config.clan.core.vars.generators.*`
   - **Status in test-clan:** Future (when machines added in Epic 2-6)

2. **User-Level Secrets (sops-nix home-manager):**
   - Module: `sops-nix.homeManagerModules.sops`
   - Scope: Home-manager user configurations
   - Use Case: Personal API keys, git signing, shell tools
   - Storage: `secrets/home-manager/users/*/`
   - Access: `config.sops.secrets.*`
   - **Status in test-clan:** This story (Story 1.10C)

**Key Insight:** Both tiers can use the SAME age keypair (one per user), simplifying key management.

**Age Key Reuse Pattern:**

```bash
# Extract public keys from clan's existing user files
cd ~/projects/nix-workspace/test-clan

# crs58 public key
jq -r '.[0].publickey' sops/users/crs58/key.json
# Output: age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8

# Use in .sops.yaml for sops-nix home-manager
keys:
  - &crs58-user age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8
  - &admin age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv
```

**sops-nix Home-Manager Pattern (from infra):**

```nix
# modules/home/base/sops.nix
{ config, pkgs, flake, ... }:
{
  flake.modules.homeManager.base-sops = { config, ... }: {
    sops = {
      age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
      # Per-user modules will set defaultSopsFile
    };
  };
}

# modules/home/users/crs58/sops.nix
{ config, flake, ... }:
{
  sops = {
    defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/crs58/secrets.yaml";

    secrets = {
      github-token = { };
      ssh-signing-key = { mode = "0400"; };
      glm-api-key = { };
      firecrawl-api-key = { };
      huggingface-token = { };
      bitwarden-email = { };
      atuin-key = { };
    };
  };
}

# modules/home/development/git.nix (Pattern A module)
{ config, pkgs, lib, flake, ... }: {
  programs.git.signing.key = config.sops.secrets.ssh-signing-key.path;
  # Path resolves to: ~/.config/sops-nix/secrets/ssh-signing-key
}
```

**.sops.yaml Structure (Multi-User Encryption):**

```yaml
keys:
  # Reuse public keys from clan's sops/users/*/key.json
  - &crs58-user age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8
  - &raquel-user age12w0rmmskrds6m334w7qrcmpms5lpe3llah6wf8ry5jtatvuxku2sarl8ut
  - &admin age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv

creation_rules:
  - path_regex: secrets/home-manager/users/crs58/.*\.yaml$
    key_groups:
      - age: [*admin, *crs58-user]
  - path_regex: secrets/home-manager/users/raquel/.*\.yaml$
    key_groups:
      - age: [*admin, *raquel-user]
```

**Secret File Structure:**

```yaml
# secrets/home-manager/users/crs58/secrets.yaml (before encryption)
github-token: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ssh-signing-key: <multi-line SSH private key imported from infra>
glm-api-key: sk-proj-xxxxxxxxxxxxxxxxxxxx
firecrawl-api-key: fc-xxxxxxxxxxxxxxxxxxxx
huggingface-token: hf_xxxxxxxxxxxxxxxxxxxx
bitwarden-email: cameron.ray.smith@gmail.com
atuin-key: <base64-encoded-key>

# After encryption with: sops -e -i secrets/home-manager/users/crs58/secrets.yaml
# File becomes JSON encrypted data, readable only by age keys in creation_rules
```

**Security Transfer Protocol:**

For importing existing secrets from infra to test-clan:

1. **Dev Agent Role:** Provide optimal sops decrypt commands
2. **Orchestrator Role:** Execute commands interactively to avoid exposing secrets in chat
3. **Process:**
   ```bash
   # Step 1: Dev agent provides decrypt command
   # Orchestrator executes:
   cd ~/projects/nix-workspace/infra
   sops -d secrets/users/admin-user/llm-api-keys.yaml
   # Output shows decrypted YAML

   # Step 2: Orchestrator copies specific key values

   # Step 3: Populate test-clan secrets YAML (unencrypted)
   cd ~/projects/nix-workspace/test-clan
   # Edit secrets/home-manager/users/crs58/secrets.yaml
   # Paste values from infra

   # Step 4: Encrypt with sops
   sops -e -i secrets/home-manager/users/crs58/secrets.yaml
   ```

4. **Validation:** Verify encrypted (file shows binary/JSON), never commit plaintext

### Learnings from Previous Story (Story 1.10BA)

**From Story 1.10BA (Status: done)**

Story 1.10BA refactored 17 home-manager modules from Pattern B (plain modules) to Pattern A (dendritic exports with flake context). This story (1.10C) builds on that foundation.

**Pattern A Provides Flake Context for sops-nix:**
- Module signature: `{ config, pkgs, lib, flake, ... }` (includes `flake` parameter)
- Enables `config.sops.secrets.*` access (sops-nix paths)
- Enables `flake.inputs.self` for defaultSopsFile paths
- sops-nix compatibility restored (home-manager module)

**Access Pattern Example (from Story 1.10BA git.nix):**
```nix
# Pattern A home-manager module (Story 1.10BA)
{ config, pkgs, lib, flake, ... }: {
  programs.git = {
    # Story 1.10C will update to sops-nix:
    signing.key = config.sops.secrets.ssh-signing-key.path;
  };
}
```

**Key Takeaway:** Pattern A modules (Story 1.10BA) are ready for sops-nix integration (Story 1.10C) because they have flake context access.

**Files to Update (from Story 1.10BA):**
- `modules/home/development/git.nix`: SSH signing key, GitHub token
- `modules/home/development/jujutsu.nix`: SSH signing key
- `modules/home/ai/claude-code/mcp-servers.nix`: 2 MCP API keys
- `modules/home/ai/claude-code/wrappers.nix`: GLM API key
- `modules/home/shell/atuin.nix`: Atuin encryption key
- Bitwarden module: Email address

**DO NOT Recreate:**
- Pattern B home-manager modules (plain modules without flake context)
- Underscore directories for modules
- Relative imports

**REUSE:**
- Pattern A module structure (flake.modules.homeManager.* pattern)
- Aggregate organization (development, ai, shell)
- Flake context access patterns (flake.inputs, config.sops)

[Source: Story 1.10BA Dev Notes, Completion Notes, File List]

### Testing Standards

**Build Validation (CRITICAL):**

All builds must succeed with sops-nix integration:

```bash
cd ~/projects/nix-workspace/test-clan

# homeConfigurations (both users)
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage

# darwinConfigurations (full system)
nix build .#darwinConfigurations.blackphos.system

# Verify no evaluation errors related to sops
# Verify ~/.config/sops-nix/secrets/* paths resolve
```

**Secrets Encryption Validation:**

```bash
# Verify encryption
file secrets/home-manager/users/crs58/secrets.yaml
# Output: JSON data (sops-encrypted)

# Test decryption (with correct age key)
sops -d secrets/home-manager/users/crs58/secrets.yaml
# Output: Decrypted YAML with secrets

# Test multi-user isolation
# crs58 age key should decrypt crs58 secrets
# crs58 age key should NOT decrypt raquel secrets (unless admin)
```

**Access Pattern Validation:**

```bash
# Verify paths in nix repl
nix repl
:lf .
:p config.flake.homeConfigurations.aarch64-darwin.crs58.config.programs.git.signing.key
# Output: ~/.config/sops-nix/secrets/ssh-signing-key
```

### Project Structure Notes

**Secrets Directory Structure (sops-nix Convention):**

```
test-clan/
├── .sops.yaml                         # Multi-user encryption rules
├── sops/
│   └── users/
│       ├── crs58/
│       │   └── key.json               # Age public key (reuse for .sops.yaml)
│       └── raquel/
│           └── key.json               # Age public key (reuse for .sops.yaml)
├── secrets/
│   └── home-manager/
│       └── users/
│           ├── crs58/
│           │   └── secrets.yaml       # sops-encrypted YAML (7 secrets)
│           └── raquel/
│               └── secrets.yaml       # sops-encrypted YAML (4 secrets)
```

**Module Structure (Pattern A + sops-nix):**

```
test-clan/
├── modules/
│   └── home/
│       ├── base/
│       │   └── sops.nix               # Base sops-nix configuration
│       ├── development/               # Pattern A aggregate
│       │   ├── git.nix                # Accesses config.sops.secrets.ssh-signing-key
│       │   └── jujutsu.nix            # Accesses config.sops.secrets.ssh-signing-key
│       ├── ai/                        # Pattern A aggregate
│       │   └── claude-code/
│       │       ├── mcp-servers.nix    # Accesses config.sops.secrets.firecrawl/huggingface
│       │       └── wrappers.nix       # Accesses config.sops.secrets.glm-api-key
│       ├── shell/                     # Pattern A aggregate
│       │   └── atuin.nix              # Accesses config.sops.secrets.atuin-key
│       └── users/
│           ├── crs58/
│           │   ├── default.nix        # Imports: development, ai, shell
│           │   └── sops.nix           # 7 secrets declarations (NEW)
│           └── raquel/
│               ├── default.nix        # Imports: development, shell
│               └── sops.nix           # 4 secrets declarations (NEW)
```

**Alignment with test-clan Architecture:**

- sops-nix home-manager module (proven in infra)
- Pattern A modules (Story 1.10BA) provide flake context for sops access
- Multi-user isolation (crs58 7 secrets, raquel 4 secrets) via separate files
- Import-tree auto-discovers sops.nix files (no manual wiring)
- Age keys reused from clan (one keypair per user)

**No Conflicts:**
- sops-nix `secrets/` does NOT conflict with clan `sops/vars/` (future)
- sops-nix home-manager does NOT conflict with Pattern A modules (compatible)
- User-specific sops modules isolated in dendritic namespace

### Quick Reference

**Target Repository:** ~/projects/nix-workspace/test-clan/

**sops-nix Commands:**

```bash
# Encrypt secrets file
sops -e -i secrets/home-manager/users/crs58/secrets.yaml

# Decrypt secrets file (for verification)
sops -d secrets/home-manager/users/crs58/secrets.yaml

# Edit encrypted secrets
sops secrets/home-manager/users/crs58/secrets.yaml

# Extract age public key from clan
jq -r '.[0].publickey' sops/users/crs58/key.json
```

**Build Commands:**

```bash
cd ~/projects/nix-workspace/test-clan

# Full builds (after secrets encrypted)
nix build .#darwinConfigurations.blackphos.system
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage

# Flake check
nix flake check
```

**Secret Transfer (infra → test-clan):**

```bash
# Decrypt from infra (orchestrator executes)
cd ~/projects/nix-workspace/infra
sops -d secrets/users/admin-user/llm-api-keys.yaml  # GLM key
sops -d secrets/users/admin-user/mcp-api-keys.yaml  # MCP keys
sops -d secrets/shared.yaml                          # GitHub token, Bitwarden email

# Populate test-clan secrets (orchestrator copies values)
cd ~/projects/nix-workspace/test-clan
# Edit secrets/home-manager/users/crs58/secrets.yaml (unencrypted)
# Paste values from infra

# Encrypt test-clan secrets
sops -e -i secrets/home-manager/users/crs58/secrets.yaml
sops -e -i secrets/home-manager/users/raquel/secrets.yaml
```

**Module Files to Update:**

| File | Change | Users |
|------|--------|-------|
| `modules/home/development/git.nix` | Add sops ssh-signing-key, github-token | crs58, raquel |
| `modules/home/development/jujutsu.nix` | Add sops ssh-signing-key | crs58, raquel |
| `modules/home/ai/claude-code/mcp-servers.nix` | Add sops firecrawl, huggingface | crs58 only |
| `modules/home/ai/claude-code/wrappers.nix` | Add sops glm-api-key | crs58 only |
| `modules/home/shell/atuin.nix` | Add sops atuin-key | crs58, raquel |
| Bitwarden/rbw module | Add sops bitwarden-email | crs58, raquel |

**sops Modules to Create:**

| User | Module Path | Secrets Count | Files |
|------|------------|---------------|-------|
| crs58 | `modules/home/users/crs58/sops.nix` | 7 | github-token, ssh-signing-key, glm-api-key, firecrawl-api-key, huggingface-token, bitwarden-email, atuin-key |
| raquel | `modules/home/users/raquel/sops.nix` | 4 | github-token, ssh-signing-key, bitwarden-email, atuin-key |

**Estimated Effort:** 4.75 hours (updated from 4.5h for age-key-management.md scope)
- Infrastructure setup: ✅ SKIP (already complete)
- sops-nix config: 1 hour (Task 2)
- Secret files creation: 45 minutes (Task 3)
- Module updates: 1 hour (Task 4)
- Build validation: 30 minutes (Task 5)
- Integration testing: 30 minutes (Task 6)
- Documentation: 60 minutes (Task 7, expanded for age key management guide)

**Risk Level:** Medium (encryption concerns, secret transfer, architectural pivot)

**Risk Mitigation:**
- Backup `~/.config/sops/age/keys.txt` before changes
- Test secret encryption in separate branch first
- Validate decryption before committing (sops -d)
- Keep infra sops-nix secrets accessible for reference
- SECURITY PROTOCOL: Manual secret transfer (dev agent provides commands, orchestrator executes)
- Salvage 66% of clan vars work (module updates, conditional access, commits)

### External References

**infra Repository Pattern:**
- File: `~/projects/nix-workspace/infra/modules/home/all/core/sops.nix`
- Shows: Working sops-nix home-manager configuration
- Pattern: Matches recommended approach exactly
- Secrets: `~/projects/nix-workspace/infra/secrets/` (source for migration)

**Explore Agent Findings (2025-11-15):**
- Investigation 1: Clan vars + home-manager incompatibility (ZERO reference repos)
- Investigation 2: User age key management architecture (two-tier, reuse keys)
- Complete code examples, validation commands, workflows

**Epic 1 Definition:**
- File: `~/projects/nix-workspace/infra/docs/notes/development/epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md`
- Lines 894-1039: Story 1.10C original definition (clan vars approach)
- Note: Scope changed to sops-nix based on architectural findings

**Story 1.10BA Context:**
- File: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10ba-refactor-pattern-a.md`
- Pattern A modules provide flake context for sops-nix access
- Module files to update documented (git.nix, jujutsu.nix, mcp-servers.nix, wrappers.nix)

**Architecture Documentation:**
- test-clan architecture: `~/projects/nix-workspace/infra/docs/notes/development/test-clan-validated-architecture.md`
- Section 11 (lines 728-1086): Module system architecture (Pattern A modules)
- Section 12 (to be added): Two-tier secrets architecture

**Quality Baseline:**
- Story 1.10A: Approved 5/5, comprehensive ACs, detailed tasks, complete docs
- Story 1.10BA: Approved, Pattern A validated, builds passing, features restored

---

## Dev Agent Record

### Context Reference

- Story Context XML: `docs/notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.context.xml` (To be updated: 2025-11-15)

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

### 2025-11-15 - Story Updated (Architectural Pivot)

- Scope changed from clan vars to sops-nix approach
- Rationale: Clan vars incompatible with home-manager (NixOS-specific module)
- Architectural finding: Two-tier secrets (system: clan vars, user: sops-nix)
- 24 acceptance criteria updated for sops-nix pattern
- 7 tasks updated: Infrastructure setup (skip), sops-nix config (new), secret files (new), module updates (modified), builds (updated), integration (updated), docs (updated)
- Security protocol documented: Manual secret transfer to avoid exposing values in chat
- Age key reuse pattern: Extract from sops/users/*/key.json for .sops.yaml
- Multi-user isolation: Separate files (crs58/sops.nix 7 secrets, raquel/sops.nix 4 secrets)
- .sops.yaml configuration: creation_rules for per-user encryption
- Secret file structure: YAML encrypted with sops -e
- Module access patterns: config.sops.secrets.* (NOT config.clan.core.vars.*)
- Work salvageable: 66% (module updates, conditional access, atomic commits)
- Work to revert: 33% (clan vars imports, generators, references)
- Estimated effort: 4.5 hours (infrastructure skip + sops-nix config 1h + secrets 45m + modules 1h + builds 30m + integration 30m + docs 45m)
- Risk level: Medium (encryption concerns, secret transfer, architectural pivot)
- External references: infra sops-nix pattern, Explore agent findings, Epic 1 definition, Story 1.10BA context, architecture docs
- Strategic value: Validates sops-nix for home-manager (Epic 2-6 migration), establishes user-level secrets boundary, documents two-tier architecture, unblocks Story 1.10D, prevents architectural error propagation

### 2025-11-15 - Story Created (Original)

- Story 1.10C drafted following create-story workflow (clan vars approach)
- Comprehensive story definition based on Epic 1 lines 894-1039
- 24 acceptance criteria across 7 sections (AC A-G)
- 7 tasks with detailed subtasks mapped to ACs
- Security protocol documented: Manual secret transfer
- Pattern B for vars explained (generators in user modules)
- Secrets inventory documented: 7 secrets (github-token, ssh-signing-key, glm-api-key, firecrawl-api-key, huggingface-token, bitwarden-email, atuin-key)
- Migration strategies defined: Generate new (ssh), import existing (APIs), manual extraction (atuin)
- Module access patterns documented: sops-nix → clan vars transformations (NOW REVERSED)
- Multi-user isolation: crs58 (all secrets) vs raquel (subset)
- Learnings from Story 1.10BA integrated: Pattern A modules ready for secrets
