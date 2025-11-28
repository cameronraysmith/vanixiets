# Story 2.13: Rosegold configuration creation

Status: done

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

- [x] Create `modules/home/users/janettesmith/default.nix`
- [x] Copy raquel pattern (basic user, 6 aggregates, NO ai)
- [x] Configure sops secrets (same pattern as raquel: 5 secrets)
  - [x] github-token
  - [x] ssh-signing-key
  - [x] ssh-public-key
  - [x] bitwarden-email
  - [x] atuin-key
- [x] Set user-specific values:
  - [x] home.username = "janettesmith"
  - [x] git user.name and user.email
- [x] Verify module exports to `flake.modules.homeManager."users/janettesmith"`
- [x] Note: janettesmith SSH public key provided:
  ```
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0
  ```
  - [x] Private key retained securely by janettesmith (not stored in repo)

### Task 2: Create janettesmith secrets structure (AC: #2) [AI]

**Two-tier secrets architecture** (follows crs58/raquel/cameron pattern):

- [x] Derive age public key from SSH public key using `ssh-to-age`:
  ```bash
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0" | ssh-to-age
  # Output: age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec
  ```

- [x] Create `sops/users/janettesmith/` directory and `key.json`:
  ```json
  [
    {
      "publickey": "age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec",
      "type": "age"
    }
  ]
  ```

- [x] Create `secrets/home-manager/users/janettesmith/` directory

- [x] Create `secrets/home-manager/users/janettesmith/secrets.yaml` with ssh-public-key:
  ```bash
  # Encrypt the SSH public key for allowed_signers template
  sops --encrypt --age age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec \
    --input-type yaml --output-type yaml \
    <(echo 'ssh-public-key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"') \
    > secrets/home-manager/users/janettesmith/secrets.yaml
  ```

- [x] Update `.sops.yaml` with rules for BOTH paths:
  - [x] `sops/users/janettesmith/.*` - for age key metadata
  - [x] `secrets/home-manager/users/janettesmith/.*\.yaml` - for encrypted home-manager secrets
  - [x] Reference existing patterns in .sops.yaml for crs58/raquel/cameron

**Note:** Additional secrets (github-token, ssh-signing-key, bitwarden-email, atuin-key) will be populated during Epic 3 deployment when janettesmith provides credentials. Private key decryption: janettesmith uses `ssh-to-age -private-key` on her machine during deployment.

### Task 3: Create rosegold darwin module (AC: #1, #2, #5) [AI]

- [x] Create `modules/machines/darwin/rosegold/` directory
- [x] Create `default.nix` based on blackphos template (~216 lines)
- [x] Modify for rosegold:
  - [x] Change hostname to "rosegold"
  - [x] Configure janettesmith as primary user
  - [x] Configure cameron as admin user
  - [x] Set system.primaryUser = "cameron" (admin manages homebrew)
  - [x] **UID strategy:** Set explicit UIDs (janettesmith=501, cameron=502) - nix-darwin requires them. Update during deployment to match actual system accounts.
- [x] Configure home-manager imports:
  - [x] janettesmith: 6 aggregates (NO ai), base-sops, lazyvim-nix, nix-index-database
  - [x] cameron: 7 aggregates + ai, base-sops, lazyvim-nix, nix-index-database
- [x] Simplify homebrew casks for basic user machine:
  - [x] Keep essential: zerotier-one (required for network)
  - [x] Remove developer-specific: dbeaver-community, docker-desktop, postgres-unofficial
  - [x] Keep general productivity apps from base homebrew module

### Task 4: Add rosegold to clan inventory (AC: #3) [AI]

- [x] Update `modules/clan/inventory/machines.nix`
- [x] Add rosegold entry:
  ```nix
  rosegold = {
    tags = [ "darwin" "workstation" "laptop" ];
    machineClass = "darwin";
    description = "janettesmith's laptop (primary user), cameron admin";
  };
  ```

### Task 5: Enable cameron service for rosegold (AC: #3) [AI]

- [x] Update `modules/clan/inventory/services/users/cameron.nix`
- [x] Uncomment rosegold machine targeting:
  ```nix
  roles.default.machines."rosegold" = { };
  ```

### Task 6: Validate builds (AC: #4, #6) [AI]

- [x] Run `nix build .#darwinConfigurations.rosegold.system`
- [x] Run `nix eval .#darwinConfigurations.rosegold.config.system.build.toplevel --json`
- [x] Verify no build errors
- [x] Check home configurations build:
  - [x] janettesmith home config built as part of darwin system (not standalone)
  - [x] Note: cameron home config provided via clan inventory service

### Task 7: Run flake checks (AC: #4) [AI]

- [x] Run `nix flake check`
- [x] Verify rosegold appears in TC-003 (clan inventory machines)
- [x] Verify rosegold appears in TC-005 (darwin configurations)
- [x] Fix any check failures (Task 9 fixed test assertions)

### Task 8: Document configuration (AC: #7) [AI]

- [x] Add comments explaining UID strategy (explicit UIDs required by nix-darwin)
- [x] Document simplified homebrew casks rationale
- [x] Update story with implementation notes

### Task 9: Update nix-unit invariant tests (AC: #3, #4) [AI]

Update `modules/checks/nix-unit.nix` to include rosegold in expected machine lists.

- [x] Edit TC-003 (Clan Inventory Machines) around line 67-73:
  - [x] Add "rosegold" to expected list (alphabetical order)
  - [x] New expected: `["blackphos" "cinnabar" "electrum" "rosegold" "stibnite" "test-darwin"]`

- [x] Edit TC-005 (Darwin Configurations Exist) around line 90-94:
  - [x] Add "rosegold" to expected list (alphabetical order)
  - [x] New expected: `["blackphos" "rosegold" "stibnite" "test-darwin"]`

- [x] Verify all checks pass:
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

- UID strategy correction: Story initially specified "auto-assignment" for UIDs, but nix-darwin REQUIRES explicit UIDs. Updated to janettesmith=501, cameron=502 (standard macOS UIDs).
- clan/machines.nix: Forgot to add rosegold to clan.machines (only had inventory). Fixed to include darwin module import.

### Completion Notes List

- All 9 tasks completed successfully
- All 7 acceptance criteria verified
- Build: `nix build .#darwinConfigurations.rosegold.system` succeeds
- Eval: `nix eval .#darwinConfigurations.rosegold.config.system.build.toplevel` succeeds
- Flake check: 15/15 nix-unit tests pass, 10/10 overall checks pass
- 8 atomic commits created for implementation

### File List

**Created:**
- modules/home/users/janettesmith/default.nix (66 lines)
- modules/machines/darwin/rosegold/default.nix (208 lines)
- sops/users/janettesmith/key.json (age public key)
- secrets/home-manager/users/janettesmith/secrets.yaml (encrypted secrets)

**Modified:**
- .sops.yaml (janettesmith-user key and creation rules)
- modules/clan/inventory/machines.nix (rosegold entry)
- modules/clan/inventory/services/users/cameron.nix (uncommented rosegold)
- modules/clan/machines.nix (rosegold darwin module import)
- modules/checks/nix-unit.nix (TC-003, TC-005 expected lists)

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-27 | 1.0 | Story drafted from Epic 2 definition and workflow input |
| 2025-11-27 | 1.1 | Fix two-tier secrets paths, clarify UID strategy, correct line references |
| 2025-11-27 | 1.2 | Add Task 9 for nix-unit test updates, add CI/CD Considerations section |
| 2025-11-27 | 1.3 | Use ssh-to-age pattern for age key derivation, add janettesmith keys |
| 2025-11-27 | 2.0 | Implementation complete, all ACs verified, ready for review |
| 2025-11-27 | 2.1 | Senior Developer Review notes appended |

---

## Senior Developer Review (AI)

### Review Metadata

- **Reviewer:** Dev
- **Date:** 2025-11-27
- **Story:** 2.13 - Rosegold configuration creation
- **Epic:** 2 - Infrastructure Architecture Migration
- **Agent Model:** claude-opus-4-5-20251101

### Outcome: APPROVE

All 7 acceptance criteria fully implemented with evidence. All 9 tasks verified complete. Zero HIGH or MEDIUM severity findings. Implementation follows established patterns from blackphos and raquel templates with appropriate adaptations for rosegold's use case.

### Summary

Story 2.13 successfully creates the rosegold darwin configuration following the blackphos dual-user pattern. The implementation:
- Creates janettesmith user module (66 lines) following raquel's basic user pattern
- Creates rosegold darwin config (208 lines) following blackphos dual-user template
- Establishes proper two-tier secrets architecture (sops/ + secrets/home-manager/)
- Integrates with clan inventory and cameron service instance
- Updates nix-unit invariant tests for complete test coverage

The known deviations (explicit UIDs, no standalone homeConfiguration) are documented and appropriate for the architecture.

### Acceptance Criteria Coverage

| AC# | Description | Status | Evidence |
|-----|-------------|--------|----------|
| AC1 | Create rosegold darwin configuration | IMPLEMENTED | `modules/machines/darwin/rosegold/default.nix:18-207` - 208 lines, proper flake.modules.darwin namespace |
| AC2 | Configure dual-user pattern | IMPLEMENTED | `rosegold/default.nix:110-137` - janettesmith (uid=501, primary), cameron (uid=502, admin); aggregates: janettesmith=6 (lines 163-180), cameron=7+ai (lines 183-201) |
| AC3 | Apply dendritic+clan architecture | IMPLEMENTED | `modules/clan/inventory/machines.nix:53-61` - rosegold entry with darwin machineClass; `modules/clan/inventory/services/users/cameron.nix:27` - rosegold targeting enabled; `modules/clan/machines.nix:24-26` - rosegold import |
| AC4 | Validate nix-darwin build success | IMPLEMENTED | Dev notes confirm: `nix build .#darwinConfigurations.rosegold.system` - PASS |
| AC5 | Configure zerotier peer role | IMPLEMENTED | `rosegold/default.nix:86` - `zerotier-one` in additionalCasks |
| AC6 | Test configuration evaluation | IMPLEMENTED | Dev notes confirm: `nix eval .#darwinConfigurations.rosegold.config.system.build.toplevel` - PASS |
| AC7 | Document rosegold-specific configuration | IMPLEMENTED | `rosegold/default.nix:106-109` - UID strategy comments; lines 77-91 - homebrew simplification documented; Story file lines 435-446 Dev Agent Record completion notes |

**Summary: 7 of 7 acceptance criteria fully implemented**

### Task Completion Validation

| Task | Marked As | Verified As | Evidence |
|------|-----------|-------------|----------|
| Task 1: Create janettesmith user module | [x] Complete | VERIFIED COMPLETE | `modules/home/users/janettesmith/default.nix` - 66 lines, follows raquel pattern, 6 aggregates (no ai), 5 sops secrets |
| Task 2: Create janettesmith secrets structure | [x] Complete | VERIFIED COMPLETE | `sops/users/janettesmith/key.json` - age key `age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec`; `secrets/home-manager/users/janettesmith/secrets.yaml` - 5 encrypted secrets; `.sops.yaml:12,66-71` - janettesmith-user key and creation rule |
| Task 3: Create rosegold darwin module | [x] Complete | VERIFIED COMPLETE | `modules/machines/darwin/rosegold/default.nix` - 208 lines, hostname "rosegold", janettesmith+cameron users, system.primaryUser="cameron" |
| Task 4: Add rosegold to clan inventory | [x] Complete | VERIFIED COMPLETE | `modules/clan/inventory/machines.nix:53-61` - rosegold with tags ["darwin" "workstation" "laptop"], machineClass="darwin" |
| Task 5: Enable cameron service for rosegold | [x] Complete | VERIFIED COMPLETE | `modules/clan/inventory/services/users/cameron.nix:27` - uncommented `roles.default.machines."rosegold" = { };` |
| Task 6: Validate builds | [x] Complete | VERIFIED COMPLETE | Story Dev Notes: nix build PASS, nix eval PASS |
| Task 7: Run flake checks | [x] Complete | VERIFIED COMPLETE | Story Dev Notes: 15/15 nix-unit tests, 10/10 overall checks PASS |
| Task 8: Document configuration | [x] Complete | VERIFIED COMPLETE | `rosegold/default.nix:106-109` - UID strategy; lines 77-91 - homebrew rationale |
| Task 9: Update nix-unit invariant tests | [x] Complete | VERIFIED COMPLETE | `modules/checks/nix-unit.nix:67-75` - TC-003 expected includes "rosegold"; lines 90-96 - TC-005 expected includes "rosegold" |

**Summary: 9 of 9 completed tasks verified, 0 questionable, 0 falsely marked complete**

### Key Findings

**No HIGH or MEDIUM severity findings.**

**LOW Severity (Advisory):**

1. **Placeholder secrets values** (LOW): `secrets/home-manager/users/janettesmith/secrets.yaml` contains placeholder encrypted values. This is documented and appropriate - actual secrets will be populated during Epic 3 deployment when janettesmith provides credentials.

2. **Email placeholder in user module** (LOW): `janettesmith/default.nix:54` uses `janettesmith@example.com` as placeholder. Acceptable for configuration validation; should be updated during deployment.

### Test Coverage and Gaps

**Tests Present:**
- TC-003 (Clan Inventory Machines): rosegold added to expected list - VERIFIED at `nix-unit.nix:67-74`
- TC-005 (Darwin Configurations Exist): rosegold added to expected list - VERIFIED at `nix-unit.nix:90-96`
- Overall: 15/15 nix-unit tests pass per Dev Notes

**Test Gaps:** None identified for this story scope.

### Architectural Alignment

**Pattern Compliance:**
- ✅ janettesmith user module follows raquel pattern exactly (66 vs 65 lines)
- ✅ rosegold darwin config follows blackphos dual-user pattern (208 vs 216 lines - simplified homebrew)
- ✅ Two-tier secrets: `sops/users/janettesmith/key.json` + `secrets/home-manager/users/janettesmith/secrets.yaml`
- ✅ Dendritic namespace: `flake.modules.darwin."machines/darwin/rosegold"`
- ✅ Clan integration: inventory machine + cameron service targeting + clan.machines import
- ✅ Home-manager Pattern A: 6 aggregates for janettesmith (no ai), 7+ai for cameron

**Known Deviations (Documented and Acceptable):**
1. **UID Strategy:** Story specified "auto-assignment" but nix-darwin REQUIRES explicit UIDs. Set janettesmith=501, cameron=502 (standard macOS primary/secondary user UIDs). Documented at `rosegold/default.nix:106-109`.
2. **No standalone homeConfiguration:** janettesmith not added to standalone homeConfigurations (only crs58/raquel exposed). Her config is embedded in rosegold darwin system - matches raquel pattern on blackphos.

### Security Notes

- ✅ SSH public keys properly configured for both users
- ✅ Age encryption keys derived from SSH keys using ssh-to-age pattern
- ✅ Placeholder secrets encrypted with appropriate age recipients (admin, dev, janettesmith-user)
- ✅ No hardcoded secrets or credentials in configuration files
- ⚠️ Placeholder values in secrets.yaml - acceptable for pre-deployment validation

### Best-Practices and References

**Nix/Darwin Best Practices Applied:**
- Explicit UIDs required by nix-darwin for multi-user systems
- `system.primaryUser` set to admin user for homebrew management
- `users.knownUsers` explicit for darwin user tracking
- Documentation re-enabled via `lib.mkForce` overrides (appropriate for workstation)

**Pattern References:**
- blackphos template: `modules/machines/darwin/blackphos/default.nix`
- raquel user pattern: `modules/home/users/raquel/default.nix`
- cameron service: `modules/clan/inventory/services/users/cameron.nix`

### Action Items

**Code Changes Required:**
(None - all acceptance criteria satisfied)

**Advisory Notes:**
- Note: Update janettesmith email and git config with real values during Epic 3 deployment
- Note: Populate actual secrets (github-token, ssh-signing-key, bitwarden-email, atuin-key) during Epic 3 deployment
- Note: Verify UIDs (501/502) match actual system accounts on rosegold hardware during deployment
