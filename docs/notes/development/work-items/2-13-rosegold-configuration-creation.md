# Story 2.13: Rosegold configuration creation

Status: drafted

## Story

As a system administrator,
I want to create rosegold darwin configuration in infra,
so that rosegold is ready for deployment in Epic 3.

## Context

**Epic 2 Phase 4 Story 3 (Future Machines):**

This is the third story in Epic 2 Phase 4. Stories 2.11 (test harness) and 2.12 (agents-md consolidation) are complete. Story 2.13 creates the rosegold darwin configuration following the blackphos dual-user pattern. Rosegold is janettesmith's laptop with cameron as admin user.

**Story Type: IMPLEMENTATION (New Configuration)**

This story creates new configuration files from existing patterns:
- Darwin machine config based on blackphos template
- New user (janettesmith) based on raquel pattern
- Admin user (cameron) reusing existing crs58 identity module with username override

**Dual-User Pattern (blackphos template):**

rosegold follows the blackphos dual-user pattern, NOT stibnite single-user:
- **janettesmith** (primary user): Basic user like raquel - 6 aggregates (core, development, packages, shell, terminal, tools) - NO ai aggregate
- **cameron** (admin user): crs58 identity alias - 7 aggregates + ai aggregate, manages homebrew

**Username Override Pattern:**

cameron uses the crs58 identity module with username override:
- Import: `modules/home/users/crs58/default.nix` (shared identity: SSH keys, git config, packages)
- Override: `home.username = "cameron"` via clan inventory service
- The cameron clan inventory service already exists at `modules/clan/inventory/services/users/cameron.nix`

**Estimated Effort:** 4-6 hours

**Risk Level:** LOW (proven patterns from blackphos)

## Acceptance Criteria

### AC1: Create rosegold darwin configuration

Use blackphos as structural template (dual-user pattern).

**Verification:**
```bash
# Verify directory structure
ls -la modules/machines/darwin/rosegold/

# Expected: default.nix exists
```

### AC2: Configure dual-user pattern

Configure janettesmith (primary, basic user like raquel) + cameron (admin, crs58 alias with full aggregates).

**Verification:**
```bash
# Verify user configuration in module
grep -E "(janettesmith|cameron)" modules/machines/darwin/rosegold/default.nix

# Expected: Both users defined with correct aggregates
# janettesmith: 6 aggregates (NO ai)
# cameron: 7 aggregates + ai
```

### AC3: Apply dendritic+clan architecture patterns

Modules, clan inventory, service instances.

**Verification:**
```bash
# Verify clan inventory machine entry
grep "rosegold" modules/clan/inventory/machines.nix

# Verify cameron service targets rosegold
grep "rosegold" modules/clan/inventory/services/users/cameron.nix

# Expected: rosegold in inventory with darwin machineClass
```

### AC4: Validate nix-darwin build success

Build validation (deployment deferred to Epic 3).

**Verification:**
```bash
nix build .#darwinConfigurations.rosegold.system
# Expected: Build succeeds without errors
```

### AC5: Configure zerotier peer role

Network ID db4344343b14b903, peer role for rosegold.

**Verification:**
```bash
# Verify zerotier-one cask in homebrew config
grep "zerotier-one" modules/machines/darwin/rosegold/default.nix

# Expected: zerotier-one in additionalCasks list
```

### AC6: Test configuration evaluation

Evaluate configuration without building.

**Verification:**
```bash
nix eval .#darwinConfigurations.rosegold.config.system.build.toplevel --json | head -c 100
# Expected: Returns valid store path JSON
```

### AC7: Document rosegold-specific configuration

User preferences, package selections, hardware details.

**Verification:**
- [ ] Comments in rosegold/default.nix explain configuration choices
- [ ] UID strategy documented (auto-assignment by nix-darwin during deployment)
- [ ] Homebrew casks simplified for basic user machine

## Tasks / Subtasks

**Execution Mode Legend:**
- **[AI]** - Can be executed directly by Claude Code
- **[USER]** - Should be executed by human developer
- **[HYBRID]** - AI prepares/validates, user executes interactive portions

---

### Task 1: Create janettesmith user module (AC: #2) [AI]

- [ ] Create `modules/home/users/janettesmith/default.nix`
- [ ] Copy raquel pattern (basic user, 6 aggregates, NO ai)
- [ ] Configure sops secrets (same pattern as raquel: 5 secrets)
  - [ ] github-token
  - [ ] ssh-signing-key
  - [ ] ssh-public-key
  - [ ] bitwarden-email
  - [ ] atuin-key
- [ ] Set user-specific values:
  - [ ] home.username = "janettesmith"
  - [ ] git user.name and user.email
- [ ] Verify module exports to `flake.modules.homeManager."users/janettesmith"`
- [ ] Note: janettesmith SSH public key provided:
  ```
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0
  ```
  - [ ] Private key retained securely by janettesmith (not stored in repo)

### Task 2: Create janettesmith secrets structure (AC: #2) [AI]

**Two-tier secrets architecture** (follows crs58/raquel/cameron pattern):

- [ ] Derive age public key from SSH public key using `ssh-to-age`:
  ```bash
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0" | ssh-to-age
  # Output: age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec
  ```

- [ ] Create `sops/users/janettesmith/` directory and `key.json`:
  ```json
  [
    {
      "publickey": "age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec",
      "type": "age"
    }
  ]
  ```

- [ ] Create `secrets/home-manager/users/janettesmith/` directory

- [ ] Create `secrets/home-manager/users/janettesmith/secrets.yaml` with ssh-public-key:
  ```bash
  # Encrypt the SSH public key for allowed_signers template
  sops --encrypt --age age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec \
    --input-type yaml --output-type yaml \
    <(echo 'ssh-public-key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"') \
    > secrets/home-manager/users/janettesmith/secrets.yaml
  ```

- [ ] Update `.sops.yaml` with rules for BOTH paths:
  - [ ] `sops/users/janettesmith/.*` - for age key metadata
  - [ ] `secrets/home-manager/users/janettesmith/.*\.yaml` - for encrypted home-manager secrets
  - [ ] Reference existing patterns in .sops.yaml for crs58/raquel/cameron

**Note:** Additional secrets (github-token, ssh-signing-key, bitwarden-email, atuin-key) will be populated during Epic 3 deployment when janettesmith provides credentials. Private key decryption: janettesmith uses `ssh-to-age -private-key` on her machine during deployment.

### Task 3: Create rosegold darwin module (AC: #1, #2, #5) [AI]

- [ ] Create `modules/machines/darwin/rosegold/` directory
- [ ] Create `default.nix` based on blackphos template (~216 lines)
- [ ] Modify for rosegold:
  - [ ] Change hostname to "rosegold"
  - [ ] Configure janettesmith as primary user
  - [ ] Configure cameron as admin user
  - [ ] Set system.primaryUser = "cameron" (admin manages homebrew)
  - [ ] **UID strategy:** Do NOT set `users.users.janettesmith.uid` or `users.users.cameron.uid` - leave undefined for nix-darwin auto-assignment during deployment. UIDs will be assigned based on existing system state on rosegold.
- [ ] Configure home-manager imports:
  - [ ] janettesmith: 6 aggregates (NO ai), base-sops, lazyvim-nix, nix-index-database
  - [ ] cameron: 7 aggregates + ai, base-sops, lazyvim-nix, nix-index-database
- [ ] Simplify homebrew casks for basic user machine:
  - [ ] Keep essential: zerotier-one (required for network)
  - [ ] Remove developer-specific: dbeaver-community, docker-desktop, postgres-unofficial
  - [ ] Keep general productivity apps from base homebrew module

### Task 4: Add rosegold to clan inventory (AC: #3) [AI]

- [ ] Update `modules/clan/inventory/machines.nix`
- [ ] Add rosegold entry:
  ```nix
  rosegold = {
    tags = [ "darwin" "workstation" "laptop" ];
    machineClass = "darwin";
    description = "janettesmith's laptop (primary user), cameron admin";
  };
  ```

### Task 5: Enable cameron service for rosegold (AC: #3) [AI]

- [ ] Update `modules/clan/inventory/services/users/cameron.nix`
- [ ] Uncomment rosegold machine targeting:
  ```nix
  roles.default.machines."rosegold" = { };
  ```

### Task 6: Validate builds (AC: #4, #6) [AI]

- [ ] Run `nix build .#darwinConfigurations.rosegold.system`
- [ ] Run `nix eval .#darwinConfigurations.rosegold.config.system.build.toplevel --json`
- [ ] Verify no build errors
- [ ] Check home configurations build:
  - [ ] `nix build .#homeConfigurations.aarch64-darwin.janettesmith.activationPackage`
  - [ ] Note: cameron home config may need separate validation (clan inventory provides it)

### Task 7: Run flake checks (AC: #4) [AI]

- [ ] Run `nix flake check`
- [ ] Verify rosegold appears in TC-003 (clan inventory machines)
- [ ] Verify rosegold appears in TC-005 (darwin configurations)
- [ ] Fix any check failures

### Task 8: Document configuration (AC: #7) [AI]

- [ ] Add comments explaining UID auto-assignment strategy (no explicit UIDs set)
- [ ] Document simplified homebrew casks rationale
- [ ] Update story with implementation notes

### Task 9: Update nix-unit invariant tests (AC: #3, #4) [AI]

Update `modules/checks/nix-unit.nix` to include rosegold in expected machine lists.

- [ ] Edit TC-003 (Clan Inventory Machines) around line 67-73:
  - [ ] Add "rosegold" to expected list (alphabetical order)
  - [ ] New expected: `["blackphos" "cinnabar" "electrum" "rosegold" "stibnite" "test-darwin"]`

- [ ] Edit TC-005 (Darwin Configurations Exist) around line 90-94:
  - [ ] Add "rosegold" to expected list (alphabetical order)
  - [ ] New expected: `["blackphos" "rosegold" "stibnite" "test-darwin"]`

- [ ] Verify all checks pass:
  ```bash
  nix flake check
  ```

**Why this matters:** These are invariant tests that assert the expected machine inventory. Without this update, `nix flake check` will fail after rosegold is added, blocking CI validation.

**Note:** CI runs on x86_64-linux and cannot BUILD darwin configurations, but it CAN evaluate them via `nix flake check` and nix-unit. These tests validate structure, not runtime behavior.

## Dev Notes

### Learnings from Previous Story

**From Story 2.12 (Status: done)**

- **Pre-migrated consolidation**: Story 2.12 work was already completed in test-clan before Story 2.3 migration
- **agents-md consolidation**: Single canonical `_agents-md.nix` with 7 correct import sites, zero duplication
- **Architecture validated**: Two-tier pattern (option definition + configuration) follows dendritic conventions
- **No work required**: Party Mode investigation confirmed clean migration state

**From Story 2.11 (Status: done)**

- **All 4 hosts operational**: stibnite, blackphos, cinnabar, electrum deployed from infra clan-01
- **CI stabilized**: 9 iterative fixes, all jobs green
- **Test harness validated**: 21 checks across aarch64-darwin and x86_64-linux
- **cached-ci-job pattern**: Essential for new configurations (follow hash-sources pattern)

[Source: docs/notes/development/work-items/2-11-test-harness-and-ci-validation.md#Dev-Agent-Record]

### User Identity Architecture

**cameron username override pattern:**

The cameron clan inventory service (`modules/clan/inventory/services/users/cameron.nix`) already exists and demonstrates the username override pattern:

```nix
# Import crs58 identity, override username to cameron
home-manager.users.cameron.imports = [
  inputs.self.modules.homeManager."users/crs58"
  # ... aggregates ...
];
home-manager.users.cameron.home.username = "cameron";
```

This pattern:
- Reuses crs58 identity (SSH keys, git config, packages)
- Overrides username for new machines
- Avoids code duplication
- cameron age key already exists: `sops/users/cameron/key.json`

**janettesmith user creation:**

Following raquel pattern from `modules/home/users/raquel/default.nix`:
- Basic user (6 aggregates, NO ai)
- 5 secrets (github-token, ssh-signing-key, ssh-public-key, bitwarden-email, atuin-key)
- Separate sops-nix defaultSopsFile path

### Age Key Derivation Pattern

This repo uses `ssh-to-age` to derive age public keys from SSH public keys:

- **Single identity:** SSH key is source of truth (no separate age keypair)
- **Age key derived:** `echo "<ssh-pubkey>" | ssh-to-age`
- **Stored in repo:** Only age PUBLIC key in `sops/users/<user>/key.json`
- **Private key decryption:** User runs `ssh-to-age -private-key -i ~/.ssh/id_ed25519` on their machine

**janettesmith keys:**
```
SSH public:  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0
Age public:  age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec
```

### UID Assignment Strategy

**Do NOT set UIDs in configuration** - leave `users.users.janettesmith.uid` and `users.users.cameron.uid` undefined for nix-darwin auto-assignment during deployment.

UIDs will be assigned based on existing system state on rosegold:
- If janettesmith/cameron accounts exist on rosegold: nix-darwin uses existing UIDs
- If not: nix-darwin assigns from available pool (501+ for first user, 502+ for additional)

This approach:
- Avoids conflicts with existing macOS user accounts
- Follows nix-darwin best practice for new machine onboarding
- Matches blackphos pattern (where UIDs were set to match pre-existing system accounts)

### Homebrew Cask Simplification

rosegold is a basic user machine (janettesmith's primary use case: productivity, not development).

**Keep from base homebrew module** (40 apps):
- All base apps appropriate for general use

**Additional casks for rosegold:**
- `zerotier-one` - Required for network connectivity

**Omit developer-specific casks** (unlike blackphos/stibnite):
- `codelayer-nightly` - Dev tool
- `dbeaver-community` - Database tool
- `docker-desktop` - Container tool
- `postgres-unofficial` - Database server
- `gpg-suite` - Crypto tools (optional for basic user)
- `inkscape` - Vector graphics (optional)
- `keycastr` - Key overlay (dev presentations)
- `meld` - Diff tool

### CI/CD Considerations

- CI runs on x86_64-linux runners (no aarch64-darwin)
- Darwin configs are EVALUATED (not built) via `nix flake check`
- nix-unit tests (TC-003, TC-005) validate machine inventory structure
- Rosegold must be added to expected lists in `modules/checks/nix-unit.nix` or CI will fail
- Task 9 ensures test assertions match actual configuration

### Project Structure Notes

**Files to create:**
```
modules/
├── home/
│   └── users/
│       └── janettesmith/
│           └── default.nix      # NEW: Basic user module (raquel pattern)
└── machines/
    └── darwin/
        └── rosegold/
            └── default.nix      # NEW: Darwin config (blackphos pattern)
```

**Two-tier secrets structure** (follows crs58/raquel/cameron pattern):
```
sops/
└── users/
    └── janettesmith/
        └── key.json             # Age key (generated during Epic 3 deployment)

secrets/
└── home-manager/
    └── users/
        └── janettesmith/
            └── secrets.yaml     # Encrypted secrets (populated during Epic 3)
```

**Files to modify:**
```
modules/clan/inventory/machines.nix           # Add rosegold entry
modules/clan/inventory/services/users/cameron.nix  # Uncomment rosegold targeting
modules/checks/nix-unit.nix                   # Add rosegold to TC-003 and TC-005 expected lists
.sops.yaml                                    # Add janettesmith rules for BOTH paths
```

### References

- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md) - Story 2.13 definition (lines 336-347)
- [Architecture - Project Structure](docs/notes/development/architecture/project-structure.md) - Module organization
- [blackphos template](modules/machines/darwin/blackphos/default.nix) - Dual-user darwin pattern (~216 lines)
- [raquel user module](modules/home/users/raquel/default.nix) - Basic user pattern (65 lines)
- [cameron clan service](modules/clan/inventory/services/users/cameron.nix) - Username override pattern (103 lines)
- [crs58 user module](modules/home/users/crs58/default.nix) - Admin identity module (84 lines)

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
| 2025-11-27 | 1.0 | Story drafted from Epic 2 definition and workflow input |
| 2025-11-27 | 1.1 | Fix two-tier secrets paths, clarify UID strategy, correct line references |
| 2025-11-27 | 1.2 | Add Task 9 for nix-unit test updates, add CI/CD Considerations section |
| 2025-11-27 | 1.3 | Use ssh-to-age pattern for age key derivation, add janettesmith keys |
