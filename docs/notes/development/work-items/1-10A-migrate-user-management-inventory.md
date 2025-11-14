# Story 1.10A: Migrate User Management to Clan Inventory Pattern

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.10 (done): cameron user exists on cinnabar via direct NixOS configuration, working baseline established

**Strategic Value:** Validates clan-core inventory users service pattern before Epic 2-6 scaling (6 machines × 4+ users), establishes fleet-wide user management architecture, proves vars system scalability, demonstrates dendritic + inventory compatibility, saves 6-12 hours in Epic 2-6 deployment time.

**⚠️ DISCOVERED STORY - Architectural Validation Enhancement**

This story was discovered during Story 1.10 party-mode architectural review (2025-11-14). Separates architectural pattern validation from user creation baseline. Story 1.10 establishes "user works", Story 1.10A validates "clan inventory pattern works".

---

## Story Description

As a system administrator,
I want to refactor cinnabar user configuration from direct NixOS to clan inventory users service with vars-based password management,
So that I validate the clan-core recommended pattern before Epic 2-6 scaling and establish the fleet-wide user management architecture.

**Context:**

Story 1.10 COMPLETE: cameron user exists on cinnabar via direct NixOS configuration (`users.users.cameron` in `modules/machines/nixos/cinnabar/default.nix` lines 109-145).

Party-mode architectural review (2025-11-14) revealed clan-core provides official inventory users service pattern that offers 5-10x productivity improvement for multi-machine/multi-user deployments.

Current direct NixOS pattern works but doesn't scale optimally for Epic 2-6 (6 machines × 4+ users). Test-clan's purpose is to validate clan-core patterns before infra migration.

**Architectural Investigation Findings:**

Three parallel investigations conducted during party-mode review:

1. **Clan-Core Provides Official Users Service:**
   - `clanServices/users/` implements declarative user management
   - Automatic password generation via vars system (xkcdpass)
   - `share = true` enables identical passwords across machines
   - `extraModules` pattern integrates home-manager

2. **Proven Developer Patterns:**
   - pinpox-clan-nixos: 8 machines × 3 users via 2 inventory declarations
   - mic92-clan-dotfiles: 9 machines, 128 secrets managed declaratively
   - qubasa-clan-infra: Complex multi-file generators (nextcloud, vaultwarden, matrix)

3. **Dendritic + Inventory Compatibility:**
   - Fully compatible (validated in test-clan, nixpkgs.molybdenum.software-dendritic-clan)
   - Clan-core provides native flake-parts integration
   - Import-tree auto-discovers inventory modules

4. **Vars vs Direct sops-nix:**
   - Vars: Declarative generation, automatic encryption, dependency composition
   - Epic 2-6 scaling: 30 min vs 2-4 hours for adding 4 machines
   - Incremental migration: Use vars for user passwords, keep sops.secrets for services

**Strategic Rationale:**
- Refactor cost is constant (same effort now or later)
- Easier with 1 machine (cinnabar) than 5 machines later
- Epic 2-6 will save 6-12 hours with inventory pattern
- Test-clan validates clan-core patterns (mission alignment)

---

## Acceptance Criteria

### A. Inventory User Instances Definition

**AC1: User Inventory Instance Created**
- [ ] Create `modules/clan/inventory/services/users.nix` in test-clan repository
- [ ] Define `user-cameron` inventory instance
- [ ] Module specification: `{ name = "users"; input = "clan-core"; }`
- [ ] Role targeting: `roles.default.tags.all = { };` (deploys to all machines)
- [ ] Settings configured:
  - `user = "cameron"`
  - `groups = ["wheel" "networkmanager"]`
  - `share = true` (same password across machines)
  - `prompt = false` (automatic password generation)
- [ ] extraModules: Reference user overlay file

**AC2: User Overlay Created**
- [ ] Create `modules/clan/inventory/services/users/cameron.nix` in test-clan repository
- [ ] Shell preference: `users.users.cameron.shell = pkgs.zsh`
- [ ] Home-manager integration via extraModules pattern
- [ ] Platform-specific configuration not handled by users service

### B. Direct NixOS Configuration Removal

**AC3: Remove Direct User Configuration**
- [ ] Remove `users.users.cameron` from `modules/machines/nixos/cinnabar/default.nix`
- [ ] Remove home-manager.users.cameron from machine config (now in overlay)
- [ ] Verify no duplicate user definitions remain
- [ ] Verify build succeeds after removal

### C. Vars System Validation

**AC4: Vars Generation and Encryption**
- [ ] Generate vars: `clan vars generate cinnabar` (or automatic during deployment)
- [ ] User password vars created in `vars/shared/user-password-cameron/`:
  - `user-password/secret` (encrypted password)
  - `user-password-hash/secret` (encrypted hash for NixOS)
- [ ] SOPS encryption validated: `file vars/shared/user-password-cameron/user-password/secret` shows JSON data
- [ ] Verify vars are properly encrypted (not plaintext)

**AC5: Deployment Validation**
- [ ] Deploy to cinnabar: `clan machines update cinnabar` succeeds
- [ ] Verify `/run/secrets/vars/user-password-cameron/user-password-hash` exists on cinnabar
- [ ] Verify vars properly populated in runtime secrets
- **Note:** Story 1.10 noted "VPS deployment pending" - clarify during implementation whether actual Hetzner VPS deployment is required for vars validation or if local VM testing is sufficient for pattern validation.

### D. Functional Validation

**AC6: User Login and Access**
- [ ] SSH login works: `ssh cameron@cinnabar` (via zerotier or public IP)
- [ ] Home-manager activated: `ssh cameron@cinnabar "echo $SHELL"` shows zsh
- [ ] Sudo access works: cameron in wheel group, passwordless sudo configured
- [ ] User identity preserved: git config, SSH keys, development environment intact

**AC7: Home-Manager Integration**
- [ ] Verify crs58 home module correctly applied to cameron user
- [ ] Verify shell configuration active (zsh + oh-my-zsh)
- [ ] Verify development tools available
- [ ] Verify no home-manager service conflicts or errors

### E. Test Coverage

**AC8: Regression Testing**
- [ ] All 14 existing regression tests from Story 1.9/1.10 continue passing
- [ ] No build regressions introduced
- [ ] No deployment regressions introduced

**AC9: New Vars Validation Tests (TC-024)**
- [ ] Vars list test: `clan vars list cinnabar | grep user-password-cameron`
- [ ] SOPS encryption test: Verify secret files are encrypted JSON
- [ ] Deployment test: Verify /run/secrets populated correctly
- [ ] Home-manager integration test: Verify shell, configs activated
- [ ] Add tests to test harness in `modules/checks/validation.nix`

### F. Documentation

**AC10: Architecture Decision Documentation**
- [ ] Create or update `docs/notes/architecture/user-management.md` in test-clan:
  - Inventory users service pattern (how it works)
  - Vars system for password management (automatic generation, encryption)
  - Party-mode investigation findings summary
  - Rationale for inventory adoption (scalability for Epic 2-6)

**AC11: Operational Guide**
- [ ] Create `docs/guides/adding-users.md` in test-clan:
  - How to add new user to inventory (define instance, create overlay)
  - How to generate vars for new machines
  - How to deploy user configuration
  - Examples for Epic 2-6 (argentum, rosegold, stibnite)

---

## Tasks / Subtasks

### Task 1: Create Inventory User Instance (AC1, AC2)
- [ ] Create `modules/clan/inventory/services/users.nix`
  - [ ] Define user-cameron inventory instance
  - [ ] Configure module reference (clan-core users service)
  - [ ] Set role targeting (all machines)
  - [ ] Configure user settings (groups, share, prompt)
  - [ ] Reference user overlay via extraModules
- [ ] Create `modules/clan/inventory/services/users/cameron.nix`
  - [ ] Configure shell preference (zsh)
  - [ ] Set up home-manager integration
  - [ ] Add platform-specific overrides if needed
- [ ] Verify build: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`

### Task 2: Remove Direct NixOS Configuration (AC3)
- [ ] Edit `modules/machines/nixos/cinnabar/default.nix`
  - [ ] Remove `users.users.cameron` block
  - [ ] Remove home-manager.users.cameron configuration
  - [ ] Remove home-manager module imports (now in overlay)
  - [ ] Preserve other machine-specific config
- [ ] Verify no duplicate user definitions
- [ ] Verify build succeeds after removal
- [ ] Compare build outputs (pre vs post) for equivalence

### Task 3: Generate and Validate Vars (AC4, AC5)
- [ ] Generate vars: `clan vars generate cinnabar`
- [ ] Verify vars directory structure created
- [ ] Verify SOPS encryption applied
- [ ] Inspect encrypted secrets (JSON format validation)
- [ ] Deploy to cinnabar: `clan machines update cinnabar`
- [ ] SSH to cinnabar and verify `/run/secrets/vars/user-password-cameron/` populated

### Task 4: Functional Validation (AC6, AC7)
- [ ] Test SSH login: `ssh cameron@cinnabar`
- [ ] Verify shell: `ssh cameron@cinnabar "echo $SHELL"` → /run/current-system/sw/bin/zsh
- [ ] Verify sudo: `ssh cameron@cinnabar "sudo -n true"` (passwordless)
- [ ] Verify home-manager activated:
  - [ ] Check git config
  - [ ] Check SSH keys
  - [ ] Check development tools (nix, git, etc.)
- [ ] Verify no service conflicts: `systemctl --user status home-manager-cameron.service`

### Task 5: Test Harness Updates (AC8, AC9)
- [ ] Run existing test suite: `nix flake check`
- [ ] Verify all 14 existing tests passing
- [ ] Add TC-024 vars validation tests to `modules/checks/validation.nix`:
  - [ ] TC-024-1: Vars list test (clan vars list)
  - [ ] TC-024-2: SOPS encryption test (file format validation)
  - [ ] TC-024-3: Deployment test (runtime secrets)
  - [ ] TC-024-4: Home-manager integration test
  - **Note:** Confirm test numbering convention during implementation - should these be TC-024 (single test with 4 assertions) OR TC-024-1 through TC-024-4 (four separate test cases)? Follow existing test harness patterns in `modules/checks/validation.nix`.
- [ ] Run updated test suite: `nix flake check`

### Task 6: Documentation (AC10, AC11)
- [ ] Create `docs/notes/architecture/user-management.md`:
  - [ ] Document inventory users service pattern
  - [ ] Document vars system for passwords
  - [ ] Include party-mode investigation findings
  - [ ] Explain scalability rationale
- [ ] Create `docs/guides/adding-users.md`:
  - [ ] Step-by-step user addition guide
  - [ ] Vars generation workflow
  - [ ] Deployment workflow
  - [ ] Epic 2-6 examples (argentum, rosegold, stibnite)

---

## Dev Notes

### Implementation Context

**Target Repository:** `~/projects/nix-workspace/test-clan/`
**Management Repository:** `~/projects/nix-workspace/infra/` (this story file location)

**Current State (Story 1.10 Baseline):**
- cameron user exists via direct NixOS configuration
- Location: `test-clan/modules/machines/nixos/cinnabar/default.nix` (lines 109-145)
- Configuration includes: user definition, SSH keys, home-manager integration
- SSH login works, home-manager activated (zsh shell)
- 14 regression tests passing

**Target State (Story 1.10A):**
- cameron user managed via clan inventory users service
- User instance: `test-clan/modules/clan/inventory/services/users.nix`
- User overlay: `test-clan/modules/clan/inventory/services/users/cameron.nix`
- Password management via vars system (automatic generation + SOPS encryption)
- Direct NixOS config removed from machine module
- Zero regression + new vars validation tests

### Architectural Context

**Clan Inventory Users Service Pattern:**

Reference implementation from clan-core:
```nix
# Example inventory instance
services.user-cameron = {
  module = {
    name = "users";
    input = "clan-core";
  };
  roles.default = {
    tags.all = { }; # Deploy to all machines
  };
  settings = {
    user = "cameron";
    groups = ["wheel" "networkmanager"];
    share = true;  # Same password across machines
    prompt = false; # Auto-generate password
    extraModules = [
      # User overlay for shell, home-manager, etc.
    ];
  };
};
```

**Vars System:**
- Automatic password generation (xkcdpass)
- SOPS encryption of secrets
- Structured storage: `vars/shared/user-password-{user}/`
- Runtime deployment: `/run/secrets/vars/user-password-{user}/`

**Home-Manager Integration:**
- Use extraModules in inventory instance to reference overlay
- Overlay imports portable home module (crs58 module with username override)
- Maintains separation: inventory defines user, overlay defines environment

### Testing Standards

**Zero Regression Requirement:**
All existing functionality must be preserved:
- SSH login works (same as Story 1.10 baseline)
- Home-manager activated (same shell, packages, configs)
- Sudo access works (same permissions)
- User identity preserved (same SSH keys, git config)

**New Test Coverage (TC-024):**
1. **Vars List Test:** Verify user-password-cameron in vars list
2. **SOPS Encryption Test:** Verify encrypted JSON format
3. **Deployment Test:** Verify runtime secrets populated
4. **Home-Manager Integration Test:** Verify shell, configs active

**Test Execution:**
```bash
# Build validation
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Test suite
nix flake check

# Functional validation (post-deployment)
ssh cameron@cinnabar "echo $SHELL"
ssh cameron@cinnabar "sudo -n true"
```

### Quick Reference Commands

**Build Validation:**
```bash
# Build cinnabar configuration
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Run full test suite
nix flake check
```

**Vars Operations:**
```bash
# Generate vars for cinnabar
clan vars generate cinnabar

# List generated vars
clan vars list cinnabar

# Check specific user password vars
clan vars list cinnabar | grep user-password-cameron
```

**Deployment:**
```bash
# Deploy to cinnabar
clan machines update cinnabar
```

**Functional Validation (post-deployment):**
```bash
# Test SSH login
ssh cameron@cinnabar

# Verify shell
ssh cameron@cinnabar "echo \$SHELL"

# Verify sudo access
ssh cameron@cinnabar "sudo -n true"

# Check home-manager service
ssh cameron@cinnabar "systemctl --user status home-manager-cameron.service"
```

### Learnings from Previous Story (Story 1.10)

**From Story 1.10 (Status: done)**

**Key Achievements:**
- cameron user deployed to cinnabar via direct NixOS configuration
- Home-manager integration working (crs58 module with username override)
- SSH login validated, zsh shell active, sudo access configured
- Build successful: `/nix/store/bac91ljb08f6kqb69al0g3774ig5skhk-nixos-system-cinnabar-25.11.20251102.b3d51a0`

**Configuration Pattern Established:**
- Location: `test-clan/modules/machines/nixos/cinnabar/default.nix`
- User definition: `users.users.cameron` with wheel group, zsh shell, SSH key
- Home-manager integration: Used outer config capture pattern to avoid infinite recursion
- Portable module reuse: `flake.modules.homeManager."users/crs58"` with username override

**Critical Patterns to Reuse:**
- **Username override pattern:** `modules/home/users/crs58/default.nix` uses `lib.mkDefault` for username/homeDirectory configurability
- **Config capture pattern:** Avoid infinite recursion when integrating home-manager in NixOS
- **Build validation workflow:** Test builds locally before deployment

**Technical Debt/Gaps:**
- VPS deployment pending (AC4 in Story 1.10 deferred to separate infrastructure task)
- SSH validation pending actual deployment to VPS

**Unblocking Achieved:**
- Story 1.12 unblocked (heterogeneous networking validation requires user SSH access)
- cameron username pattern established (per CLAUDE.md preference for new machines)

**Testing Context:**
- 14 regression tests passing (from Story 1.9/1.10 baseline)
- Test harness location: `modules/checks/validation.nix`
- Pattern: Add new tests as TC-XXX numbered test cases

[Source: work-items/1-10-complete-migrations-establish-clean-foundation.md#Dev-Agent-Record]

### External References

**Clan-Core Documentation:**
- `~/projects/nix-workspace/clan-core/` - clan source
- Inventory users service: `clan-core/clanModules/clanServices/users/`
- Vars system: `clan-core/nixosModules/clanCore/vars/`

**Developer Examples (Inventory Pattern):**
- `~/projects/nix-workspace/pinpox-clan-nixos/` - 8 machines × 3 users
- `~/projects/nix-workspace/mic92-clan-dotfiles/` - 9 machines, 128 secrets
- `~/projects/nix-workspace/qubasa-clan-infra/` - complex multi-file generators

**Dendritic Pattern References:**
- `~/projects/nix-workspace/dendritic-flake-parts/` - pattern source
- `~/projects/nix-workspace/nixpkgs.molybdenum.software-dendritic-clan/` - dendritic + clan combination

### Project Structure Notes

**Test-Clan Repository Structure:**
```
test-clan/
├── modules/
│   ├── clan/
│   │   └── inventory/
│   │       └── services/
│   │           ├── users.nix          # NEW: Inventory instance
│   │           └── users/
│   │               └── cameron.nix    # NEW: User overlay
│   ├── machines/
│   │   └── nixos/
│   │       └── cinnabar/
│   │           └── default.nix        # MODIFIED: Remove users.users.cameron
│   ├── checks/
│   │   └── validation.nix             # MODIFIED: Add TC-024 tests
│   └── home/
│       └── users/
│           └── crs58/
│               └── default.nix        # Already portable (Story 1.8A)
├── vars/
│   └── shared/
│       └── user-password-cameron/     # NEW: Generated by vars system
│           ├── user-password/
│           │   └── secret             # Encrypted password
│           └── user-password-hash/
│               └── secret             # Encrypted hash
└── docs/
    ├── notes/architecture/
    │   └── user-management.md         # NEW: Architecture decision
    └── guides/
        └── adding-users.md            # NEW: Operational guide
```

**Dendritic Auto-Discovery:**
- `modules/clan/inventory/services/users.nix` → Auto-discovered by import-tree
- Inventory instance automatically registered with clan-core
- No manual flake-level imports required

### References

**Epic Definition:**
- [Source: docs/notes/development/epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md, lines 432-560]

**Architecture Documentation:**
- [Source: docs/notes/development/architecture/index.md] - Architecture index (note: some docs may be outdated)
- [Relevant: docs/notes/development/architecture/architectural-decisions.md#user-management-decision] - User management decision section (to be created in AC10)

**Previous Story Context:**
- [Source: docs/notes/development/work-items/1-10-complete-migrations-establish-clean-foundation.md] - Story 1.10 completion

**Test-Clan Architecture:**
- [Source: docs/notes/development/test-clan-validated-architecture.md] - Validated architecture patterns

**Party-Mode Investigation Evidence:**
- Clan-core docs investigation: Official users service architecture
- clan-infra pattern analysis: Direct NixOS (pragmatic) vs inventory (recommended)
- Developer repos analysis: Proven inventory patterns at scale
- Vars vs sops-nix comparison: 5-10x productivity improvement
- Dendritic compatibility validation: Full compatibility confirmed

---

## Dev Agent Record

### Context Reference

- [Story Context XML](story-contexts/1-10A-migrate-user-management-inventory.context.xml) - Generated 2025-11-14

### Agent Model Used

<!-- Will be populated during story implementation -->

### Debug Log References

<!-- Will be populated during story implementation -->

### Completion Notes List

<!-- Will be populated during story implementation -->

### File List

<!-- Will be populated during story implementation -->

---

## Change Log

### 2025-11-14 - Story Created
- Story 1.10A drafted based on party-mode architectural review findings
- Complete story definition extracted from epic file (lines 432-560)
- All acceptance criteria sections (A-F) preserved from epic definition
- Learnings from Story 1.10 incorporated (cameron user baseline, testing patterns)
- Estimated effort: 3-4 hours (1h instances + 1h removal + 1h vars + 0.5h tests + 0.5h docs)
- Risk level: Low (refactoring only, Story 1.10 baseline working, test harness safety net)
- Strategic value: Validates clan inventory pattern before Epic 2-6 scaling (6-12 hour savings)
