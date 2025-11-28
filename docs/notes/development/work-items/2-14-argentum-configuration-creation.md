# Story 2.14: Argentum configuration creation

Status: done

## Story

As a system administrator,
I want to create argentum darwin configuration in infra,
so that argentum is ready for deployment in Epic 4.

## Context

**Epic 2 Phase 4 Story 4 (Future Machines - FINAL):**

This is the fourth and final story in Epic 2 Phase 4, completing the Infrastructure Architecture Migration epic. Story 2.13 (rosegold) established the pattern; Story 2.14 applies the identical pattern to argentum (christophersmith's laptop).

**Story Type: IMPLEMENTATION (New Configuration)**

This story creates new configuration files from existing patterns:
- Darwin machine config based on rosegold template (Story 2.13)
- New user (christophersmith) based on janettesmith pattern (Story 2.13)
- Admin user (cameron) reusing existing crs58 identity module with username override

**Dual-User Pattern (rosegold template):**

argentum follows the rosegold/blackphos dual-user pattern:
- **christophersmith** (primary user): Basic user like raquel - 6 aggregates (core, development, packages, shell, terminal, tools) - NO ai aggregate
- **cameron** (admin user): crs58 identity alias - 7 aggregates + ai aggregate, manages homebrew

**Estimated Effort:** 3-4 hours (faster than Story 2.13 due to rosegold template)

**Risk Level:** LOW (follows proven rosegold pattern from Story 2.13)

## Acceptance Criteria

### AC1: Create argentum darwin configuration

Use rosegold (Story 2.13) as structural template (dual-user pattern).

**Verification:**
```bash
# Verify directory structure
ls -la modules/machines/darwin/argentum/

# Expected: default.nix exists
```

**Result:** PASS - `modules/machines/darwin/argentum/default.nix` created (207 lines)

### AC2: Configure dual-user pattern

Configure christophersmith (primary, basic user like raquel) + cameron (admin, crs58 alias with full aggregates).

**Verification:**
```bash
# Verify user configuration in module
grep -E "(christophersmith|cameron)" modules/machines/darwin/argentum/default.nix

# Expected: Both users defined with correct aggregates
# christophersmith: 6 aggregates (NO ai)
# cameron: 7 aggregates + ai
```

**Result:** PASS - Both users configured, christophersmith=6 aggregates, cameron=7+ai

### AC3: Apply dendritic+clan architecture patterns

Modules, clan inventory, service instances.

**Verification:**
```bash
# Verify clan inventory machine entry
grep "argentum" modules/clan/inventory/machines.nix

# Verify cameron service targets argentum
grep "argentum" modules/clan/inventory/services/users/cameron.nix

# Expected: argentum in inventory with darwin machineClass
```

**Result:** PASS - argentum added to inventory, clan.machines, and cameron service enabled

### AC4: Validate nix-darwin build success

Build validation (deployment deferred to Epic 4).

**Verification:**
```bash
nix build .#darwinConfigurations.argentum.system
# Expected: Build succeeds without errors
```

**Result:** PASS - Build succeeded with 54 derivations

### AC5: Configure zerotier peer role

Network ID db4344343b14b903, peer role for argentum.

**Verification:**
```bash
# Verify zerotier-one cask in homebrew config
grep "zerotier-one" modules/machines/darwin/argentum/default.nix

# Expected: zerotier-one in additionalCasks list
```

**Result:** PASS - zerotier-one in additionalCasks (line 86)

### AC6: Test configuration evaluation

Evaluate configuration without building.

**Verification:**
```bash
nix eval .#darwinConfigurations.argentum.config.system.build.toplevel --json | head -c 100
# Expected: Returns valid store path JSON
```

**Result:** PASS - Returns `/nix/store/b2l4qmvm2hby8s90ir31ppxfxg8bnpn9-darwin-system-25.11.973db96`

### AC7: Document argentum-specific configuration

User preferences, package selections, hardware details.

**Result:** PASS
- Comments in argentum/default.nix explain UID strategy (lines 105-109)
- Homebrew casks simplified for basic user machine (lines 77-92)
- Implementation notes in this story file

## Tasks / Subtasks

### Task 1: Create christophersmith user module (AC: #2) [AI]

- [x] Create `modules/home/users/christophersmith/default.nix`
- [x] Copy janettesmith pattern (basic user, 6 aggregates, NO ai)
- [x] Configure sops secrets (5 secrets like janettesmith)
- [x] Set user-specific values (username, git config)
- [x] Verify module exports to `flake.modules.homeManager."users/christophersmith"`

### Task 2: Create christophersmith secrets structure (AC: #2) [AI]

- [x] Derive age public key from SSH public key using ssh-to-age
- [x] Create `sops/users/christophersmith/key.json`
- [x] Create `secrets/home-manager/users/christophersmith/secrets.yaml`
- [x] Update `.sops.yaml` with christophersmith rules

### Task 3: Create argentum darwin module (AC: #1, #2, #5) [AI]

- [x] Create `modules/machines/darwin/argentum/` directory
- [x] Create `default.nix` based on rosegold template (207 lines)
- [x] Configure christophersmith as primary user (uid=501)
- [x] Configure cameron as admin user (uid=502)
- [x] Set zerotier-one in additionalCasks

### Task 4: Add argentum to clan inventory (AC: #3) [AI]

- [x] Update `modules/clan/inventory/machines.nix` with argentum entry
- [x] Update `modules/clan/machines.nix` with argentum import

### Task 5: Enable cameron service for argentum (AC: #3) [AI]

- [x] Uncomment argentum in `modules/clan/inventory/services/users/cameron.nix`

### Task 6: Validate builds (AC: #4, #6) [AI]

- [x] Run `nix build .#darwinConfigurations.argentum.system` - PASS
- [x] Run `nix eval .#darwinConfigurations.argentum.config.system.build.toplevel --json` - PASS

### Task 7: Run flake checks (AC: #4) [AI]

- [x] Run `nix flake check` - PASS (16/16 tests)
- [x] Verify argentum appears in TC-003 (clan inventory machines) - PASS
- [x] Verify argentum appears in TC-005 (darwin configurations) - PASS

### Task 8: Update nix-unit invariant tests (AC: #3, #4) [AI]

- [x] Add "argentum" to TC-003 expected list
- [x] Add "argentum" to TC-005 expected list

## Dev Notes

### Learnings from Previous Story

**From Story 2.13 (rosegold) (Status: done)**

- **Template proven**: rosegold implementation validated pattern for future darwin machines
- **UID strategy**: Explicit UIDs required (501 primary, 502 admin)
- **ssh-to-age derivation**: Age keys derived from SSH public keys, not generated separately
- **Two-tier secrets**: sops/users/<user>/key.json + secrets/home-manager/users/<user>/secrets.yaml
- **No standalone homeConfiguration**: User configs embedded in darwin system, not standalone

[Source: docs/notes/development/work-items/2-13-rosegold-configuration-creation.md#Dev-Agent-Record]

### Key Differences from Story 2.13

| Aspect | Story 2.13 (rosegold) | Story 2.14 (argentum) |
|--------|----------------------|----------------------|
| Primary user | janettesmith | christophersmith |
| SSH public key | ...PSryuL7iP8WXow/SsZOIr96qnKP0 | ...kqzTEQI1lr8qTpPMxXcyxZwilVECIzAM |
| Age public key | age1mqfqck...e27dec | age1xz7gmq...fzd2fn |
| Template | blackphos | rosegold (Story 2.13) |
| Epic deployment | Epic 3 | Epic 4 |

### christophersmith Keys

```
SSH public:  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKPi1aUkaTAykqzTEQI1lr8qTpPMxXcyxZwilVECIzAM
Age public:  age1xz7gmqx7m0pn8u2nq8x05efq6dj52ym6c9gat5xj4am6x9sauq6sfzd2fn
```

### Project Structure Notes

**Files created:**
```
modules/
├── home/
│   └── users/
│       └── christophersmith/
│           └── default.nix      # NEW: Basic user module (66 lines)
└── machines/
    └── darwin/
        └── argentum/
            └── default.nix      # NEW: Darwin config (207 lines)

sops/
└── users/
    └── christophersmith/
        └── key.json             # NEW: Age key

secrets/
└── home-manager/
    └── users/
        └── christophersmith/
            └── secrets.yaml     # NEW: Encrypted secrets
```

**Files modified:**
```
.sops.yaml                                    # christophersmith rules
modules/clan/inventory/machines.nix           # argentum entry
modules/clan/machines.nix                     # argentum import
modules/clan/inventory/services/users/cameron.nix  # argentum targeting
modules/checks/nix-unit.nix                   # TC-003, TC-005 updates
```

### References

- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md) - Story 2.14 definition (lines 349-365)
- [Story 2.13 (rosegold)](docs/notes/development/work-items/2-13-rosegold-configuration-creation.md) - Template for argentum
- [rosegold darwin config](modules/machines/darwin/rosegold/default.nix) - Pattern template
- [janettesmith user module](modules/home/users/janettesmith/default.nix) - User pattern template

## Dev Agent Record

### Context Reference

<!-- Story created from workflow input with comprehensive context -->

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

(None - implementation followed Story 2.13 pattern without issues)

### Completion Notes List

- All 8 tasks completed successfully
- All 7 acceptance criteria verified
- Build: `nix build .#darwinConfigurations.argentum.system` - PASS
- Eval: `nix eval .#darwinConfigurations.argentum.config.system.build.toplevel` - PASS
- Flake check: 16/16 nix-unit tests pass, 10/10 overall checks pass
- 5 atomic commits created for implementation
- Epic 2 Phase 4 COMPLETE - all 14 stories done

### File List

**Created:**
- modules/home/users/christophersmith/default.nix (66 lines)
- modules/machines/darwin/argentum/default.nix (207 lines)
- sops/users/christophersmith/key.json (age public key)
- secrets/home-manager/users/christophersmith/secrets.yaml (encrypted secrets)

**Modified:**
- .sops.yaml (christophersmith-user key and creation rules)
- modules/clan/inventory/machines.nix (argentum entry)
- modules/clan/machines.nix (argentum import)
- modules/clan/inventory/services/users/cameron.nix (argentum targeting enabled)
- modules/checks/nix-unit.nix (TC-003, TC-005 expected lists)

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-27 | 1.0 | Story created and implementation complete |
