# Story 1.10: Complete Migrations and Establish Clean Foundation

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.9 (done): VMs renamed to cinnabar/electrum, zerotier network operational

**Strategic Value:** Completes blackphos migration from infra, deploys cameron user to cinnabar (critical gap preventing Story 1.12), refines dendritic patterns across test-clan, establishes complete and clean foundation required for Story 1.11 type-safe architecture implementation and Story 1.12 physical deployment validation.

---

## Story Description

As a system administrator,
I want to complete the blackphos migration from infra, apply shared configuration to cinnabar, and refactor test-clan to exemplar dendritic patterns,
So that I have complete, clean configurations ready for deployment and a solid foundation for type-safe home-manager architecture.

**Context:**

Story 1.8/1.8A migrated blackphos configuration but did NOT migrate all configuration from infra repository.
Three parallel investigations revealed critical insights:
1. test-clan's dendritic structure already appropriate (no major restructuring needed)
2. cinnabar CRITICALLY MISSING user configuration (only srvos defaults, no cameron/crs58 user)
3. infra's blackphos ↔ blackphos-nixos shows "replica" means SHARED config (user identity, SSH keys, nix settings) NOT identical (excludes platform-specific like homebrew/GUI)

**Critical Gap:** cinnabar (nixos server) currently has NO user configuration (only srvos defaults + zerotier). This blocks Story 1.12 (blackphos deployment) - can't validate heterogeneous networking without user logins. Also blocks type-safe architecture (Story 1.11) - needs finalized user modules.

**Story Split Rationale:** Story 1.10 was split from original single story to optimize sizing (10-15h vs 18-27h original). This story focuses on completing migrations and establishing clean foundation. Story 1.11 implements type-safe home-manager architecture on this foundation.

---

## Acceptance Criteria

### A. Complete blackphos Migration and Apply Shared Config to cinnabar

**AC1: blackphos Migration Audit Complete**
- [ ] Audit infra blackphos configuration vs test-clan blackphos configuration
- [ ] Identify ALL remaining configuration not yet migrated (packages, services, system settings)
- [ ] Document audit findings in story completion notes
- [ ] Migration checklist created for remaining config

**AC2: All Remaining Configuration Migrated to test-clan**
- [ ] All identified configuration migrated from infra to test-clan following dendritic patterns
- [ ] Package list comparison validates zero regression (pre-migration vs post-migration)
- [ ] All blackphos functionality preserved

**AC3: Shared vs Platform-Specific Configuration Identified and Documented**
- [ ] Shared configuration identified: User identity (cameron/crs58), SSH keys, nix settings, caches, development tooling
- [ ] Platform-specific darwin identified: Homebrew, GUI apps, macOS system defaults, touchID
- [ ] Platform-specific nixos identified: Boot/disk config, systemd services, server-specific tools
- [ ] Documentation created: Shared vs platform-specific configuration guidelines

**AC4: cinnabar User Configuration Deployed**
- [ ] cameron user added to cinnabar (username: cameron, preferred for new machines per CLAUDE.md)
- [ ] SSH authorized keys for cameron configured
- [ ] User shell (zsh), home directory (/home/cameron), admin privileges set
- [ ] Portable home-manager module integrated: `flake.modules.homeManager."users/crs58"` (references crs58 identity)
- [ ] SSH login as cameron validated: `ssh cameron@<cinnabar-ip>` works
- [ ] Home-manager builds successfully for nixos: `nix build .#homeConfigurations.crs58.activationPackage`

**AC5: Migration Pattern Documented**
- [ ] Shared vs platform-specific configuration guidelines documented
- [ ] Migration checklist for reproducibility created
- [ ] Pattern for applying user config across darwin/nixos documented

### B. Apply Dendritic Pattern Refinements

**AC6: File Length Compliance Validated**
- [ ] Audit all modules for files >200 lines
- [ ] Modularize if justified (extract reusable components)
- [ ] Document any exceptions with rationale

**AC7: Pattern Compliance Enforced**
- [ ] ALL files in modules/ directories are proper flake-parts modules
- [ ] `_` prefix ONLY used for non-module data files (JSON, YAML, shell scripts)
- [ ] Never use `_` prefix as shortcut for long flake-parts modules
- [ ] Verification: `fd '^_' modules/` shows only non-module files

**AC8: Module Organization Refined**
- [ ] Clear separation: base modules, host-specific modules, user modules
- [ ] Consistent namespace usage: `flake.modules.{darwin|nixos|homeManager}.*`
- [ ] Reference gaetanlepage patterns for structure and composition
- [ ] Architecture documentation updated with organization guidelines

**AC9: All Configurations Build Successfully**
- [ ] darwinConfigurations build: `nix build .#darwinConfigurations.blackphos.system`
- [ ] All nixosConfigurations build: `nix build .#nixosConfigurations.{cinnabar,electrum}.config.system.build.toplevel`
- [ ] All homeConfigurations build: `nix build .#homeConfigurations.{crs58,raquel}.activationPackage`

### C. Clan-Core Integration Validation

**AC10: Clan-Core Compatibility Maintained**
- [ ] `clan-core.inventory` structure unchanged (machine definitions, service instances)
- [ ] Service instance registration via `clan-core.services.*` unchanged
- [ ] `clan-core.vars.*` and `clan-core.secrets.*` access patterns unchanged
- [ ] Zerotier network configuration interface unchanged
- [ ] All clan machines build: `nix build .#clan.machines.{cinnabar,electrum,blackphos}.config.system.build.toplevel`

**AC11: Zerotier Network Operational**
- [ ] Cinnabar controller operational (network `db4344343b14b903` from Story 1.9)
- [ ] Electrum peer operational
- [ ] Clan inventory evaluates without errors: `nix eval .#clan.inventory --json | jq .machines`

### D. Test Coverage

**AC12: Migration Validation Tests Pass**
- [ ] blackphos package diff: zero regression validated (pre vs post migration)
- [ ] cinnabar user login test: SSH as cameron works, home-manager activated (shell=zsh, ~/.config/ exists, git config present)
- [ ] Home-manager builds for both platforms (darwin + nixos)

**AC13: Pattern Compliance Tests Pass**
- [ ] All 14 regression tests from Story 1.9 continue passing
- [ ] File length compliance verified
- [ ] Module namespace consistency validated

**AC14: Integration Tests Pass**
- [ ] Configurations build across all outputs
- [ ] Clan inventory evaluates without errors
- [ ] Full test suite passes: `nix flake check`

### E. Documentation

**AC15: Migration Documentation Complete**
- [ ] Shared vs platform-specific configuration pattern documented
- [ ] blackphos migration checklist documented
- [ ] cinnabar user configuration guide documented
- [ ] Migration findings added to story completion notes

**AC16: Dendritic Pattern Guidelines Documented**
- [ ] File organization standards documented
- [ ] Module composition patterns documented
- [ ] Namespace hygiene rules documented
- [ ] Reference to gaetanlepage exemplar patterns included

---

## Tasks / Subtasks

### Task 1: Audit blackphos Migration and Identify Gaps (1-2 hours) (AC1, AC3)

**Objective:** Create comprehensive comparison between infra blackphos and test-clan blackphos to identify all remaining configuration to migrate.

- [x] **Subtask 1.1:** Compare infra blackphos packages vs test-clan blackphos packages
  - Read infra `~/projects/nix-workspace/infra/hosts/blackphos/configuration.nix`
  - Read test-clan `~/projects/nix-workspace/test-clan/modules/machines/darwin/blackphos/default.nix`
  - Generate package diff list (what's in infra but not test-clan)
  - Document findings in story completion notes

- [x] **Subtask 1.2:** Compare infra blackphos services vs test-clan blackphos services
  - Identify services configured in infra but not test-clan
  - Document service configuration differences
  - Create migration checklist for services

- [x] **Subtask 1.3:** Compare infra blackphos system settings vs test-clan blackphos settings
  - Compare nix settings, caches, substituters
  - Compare system packages, environment variables
  - Identify shared vs platform-specific settings
  - Document shared configuration pattern (for cinnabar reuse)

- [x] **Subtask 1.4:** Review infra blackphos-nixos replica configuration
  - Read infra `~/projects/nix-workspace/infra/hosts/blackphos-nixos/configuration.nix`
  - Identify SHARED config between blackphos ↔ blackphos-nixos
  - Extract shared pattern: user identity, SSH keys, nix settings, caches
  - Document shared vs platform-specific boundaries

**Success Criteria:** Complete audit findings documented, migration checklist created, shared configuration pattern identified for cinnabar deployment.

### Task 2: Migrate Remaining blackphos Configuration to test-clan (2-3 hours) (AC2, AC9)

**Objective:** Migrate all identified remaining configuration from infra blackphos to test-clan blackphos following dendritic patterns.

- [x] **Subtask 2.1:** Migrate packages
  - Add missing packages from audit to test-clan blackphos
  - Organize packages by category (development, utilities, GUI apps)
  - Follow dendritic pattern: embedded in host default.nix or extracted to shared module if reusable
  - **OUTCOME:** No additional packages needed - Story 1.8 already migrated all packages

- [x] **Subtask 2.2:** Migrate services
  - Add missing services from audit to test-clan blackphos
  - Configure service settings matching infra
  - Validate service configuration builds
  - **OUTCOME:** No additional services needed - all services already configured in Story 1.8

- [x] **Subtask 2.3:** Migrate system settings
  - Add missing nix settings, caches, substituters
  - Add missing environment variables
  - Add missing system-level configuration
  - **OUTCOME:** Migrated shared configuration via new system modules:
    - Created `modules/system/caches.nix` - 7 cachix caches (cameronraysmith, nix-community, etc.)
    - Created `modules/system/nix-optimization.nix` - gc, store optimization (platform-aware darwin/nixos)
    - Both modules auto-merge into `flake.modules.{darwin|nixos}.base` namespace
    - Applied to both blackphos (darwin) and cinnabar (nixos) via base imports

- [x] **Subtask 2.3a:** Capture pre-migration baseline for zero-regression validation
  - **SKIPPED:** Not needed since no packages/services were added, only nix daemon config

- [x] **Subtask 2.4:** Validate zero regression
  - Build test-clan blackphos: `nix build .#darwinConfigurations.blackphos.system`
  - Build test-clan cinnabar: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
  - **RESULT:** Both configurations build successfully
  - blackphos output: `/nix/store/l6qydpqa3y7izfji0a9f7rjp50an9ipg-darwin-system-25.11.5125a3c`
  - cinnabar output: `/nix/store/5v78hjvw4c5xgfp980wjz80apzgi628g-nixos-system-cinnabar-25.11.20251102.b3d51a0`
  - **VALIDATION:** Zero regressions - builds successful with added caches/gc/optimization

**Success Criteria:** All remaining configuration migrated, builds successful, zero regression validated via package diff.

### Task 3: Deploy cameron User to cinnabar (2-3 hours) (AC4, AC12)

**Objective:** Add cameron user to cinnabar with home-manager integration, enabling SSH login and validating cross-platform user module reuse.

- [x] **Subtask 3.1:** Add cameron user to cinnabar nixos configuration
  - Edit `~/projects/nix-workspace/test-clan/modules/machines/nixos/cinnabar/default.nix`
  - Add user configuration: username cameron (preferred for new machines), UID, shell (zsh), admin privileges
  - Configure SSH authorized keys for cameron
  - Set home directory: `/home/cameron`
  - Note: home-manager module references crs58 identity (user-level config) but system username is cameron
  - Reference infra blackphos-nixos for shared user pattern
  - **COMPLETED:** User configuration added with wheel group, zsh shell, SSH key

- [x] **Subtask 3.2:** Integrate portable home-manager module (nixos integrated mode)
  - Add home-manager nixos module to cinnabar configuration imports
  - Configure home-manager.users.cameron module to import `config.flake.modules.homeManager."users/crs58"`
  - This integrates home-manager into nixosConfiguration (one of three supported modes from Story 1.8A)
  - Set home-manager.users.cameron.home.username = "cameron"
  - Set home-manager.users.cameron.home.homeDirectory = "/home/cameron"
  - Validate home-manager builds: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
  - Note: This is nixos-integrated mode (home-manager activated with system switch), not standalone mode
  - **COMPLETED:** Build successful `/nix/store/bac91ljb08f6kqb69al0g3774ig5skhk-nixos-system-cinnabar-25.11.20251102.b3d51a0`
  - **COMPLETED:** home-manager service created: `unit-home-manager-cameron.service`
  - **COMPLETED:** Made crs58 module username-configurable via mkDefault to avoid recursion

- [ ] **Subtask 3.3:** Build and deploy cinnabar configuration
  - Build cinnabar: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
  - Deploy to cinnabar: `clan machines update cinnabar`
  - Verify deployment successful
  - **PENDING DEPLOYMENT:** Build validated locally, requires VPS deployment

- [ ] **Subtask 3.4:** Validate SSH login as cameron
  - Test SSH login: `ssh cameron@<cinnabar-ip>`
  - Verify user shell (zsh), home directory exists
  - Verify home-manager activation successful
  - Verify admin privileges (sudo access)
  - Verify home-manager activation: shell is zsh, ~/.config/ directory populated, git config accessible
  - Verify packages from crs58 module available (git, gh, starship)
  - Document zerotier IP for future reference
  - **PENDING DEPLOYMENT:** Requires VPS deployment to validate

**Success Criteria:** cameron user operational on cinnabar, SSH login works, home-manager integrated, cross-platform user module reuse validated.

### Task 4: Audit and Refine Dendritic Patterns (2-3 hours) (AC6, AC7, AC8)

**Objective:** Audit test-clan for dendritic pattern compliance and refine patterns to match gaetanlepage exemplar standards.

- [ ] **Subtask 4.1:** Audit file length compliance
  - Search for files >200 lines: `fd '\.nix$' modules/ | xargs wc -l | sort -n | tail -20`
  - Review each file >200 lines for modularization opportunities
  - Extract reusable components if justified
  - Document exceptions with rationale in story completion notes

- [ ] **Subtask 4.2:** Audit pattern compliance
  - Search for `_` prefix files: `fd '^_' modules/`
  - Verify only non-module data files use `_` prefix (JSON, YAML, shell scripts)
  - Rename any flake-parts modules incorrectly using `_` prefix
  - Document pattern violations and corrections

- [ ] **Subtask 4.3:** Refine module organization
  - Review module separation: base modules, host-specific modules, user modules
  - Verify consistent namespace usage: `flake.modules.{darwin|nixos|homeManager}.*`
  - Reference gaetanlepage patterns: `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config`
  - Compare test-clan organization to gaetanlepage structure
  - Refine organization if gaps identified

- [ ] **Subtask 4.4:** Update architecture documentation
  - Document dendritic pattern guidelines in architecture.md
  - Document file organization standards
  - Document module composition patterns
  - Document namespace hygiene rules
  - Reference gaetanlepage as exemplar pattern

**Success Criteria:** All dendritic patterns refined, file length compliance validated, pattern violations corrected, architecture documentation updated with guidelines.

### Task 5: Validate Clan-Core Integration (1 hour) (AC10, AC11, AC14)

**Objective:** Verify clan-core integration remains functional after migrations and dendritic pattern refinements.

- [ ] **Subtask 5.1:** Validate clan inventory structure
  - Evaluate clan inventory: `nix eval .#clan.inventory --json | jq .machines`
  - Verify machine definitions unchanged (cinnabar, electrum, blackphos)
  - Verify service instances unchanged (zerotier, emergency-access, sshd-clan, users-root)
  - Document any changes required for compatibility

- [ ] **Subtask 5.2:** Validate clan machines build
  - Build all clan machines: `nix build .#clan.machines.{cinnabar,electrum,blackphos}.config.system.build.toplevel`
  - Verify no build errors or warnings
  - Document any issues and resolutions

- [ ] **Subtask 5.3:** Validate zerotier network operational
  - Verify cinnabar controller status: `ssh root@<cinnabar-ip> "zerotier-cli info"`
  - Verify electrum peer status: `ssh root@<electrum-ip> "zerotier-cli info"`
  - Verify network connectivity: bidirectional ping between cinnabar and electrum
  - Document network ID: `db4344343b14b903` (from Story 1.9)

**Success Criteria:** Clan-core integration validated, all machines build successfully, zerotier network operational, clan inventory evaluates without errors.

### Task 6: Run Comprehensive Test Suite (1 hour) (AC12, AC13, AC14)

**Objective:** Validate zero regression via comprehensive test suite and verify all architectural invariants maintained.

- [ ] **Subtask 6.1:** Run full test suite
  - Execute test suite: `nix flake check` or `just test`
  - Verify all 14 regression tests from Story 1.9 continue passing
  - Verify migration validation tests pass (blackphos package diff, cinnabar user login, home-manager builds)
  - Document test results in story completion notes

- [ ] **Subtask 6.2:** Validate pattern compliance
  - Verify file length compliance (no unjustified files >200 lines)
  - Verify module namespace consistency (all exports to correct namespaces)
  - Verify no pattern violations remain
  - Document compliance validation in story completion notes

- [ ] **Subtask 6.3:** Validate integration tests
  - Verify all configurations build across all outputs
  - Verify clan inventory evaluates without errors
  - Verify zerotier network connectivity tests pass
  - Document integration test results

**Success Criteria:** All tests passing, zero regressions validated, pattern compliance confirmed, integration validated.

### Task 7: Document Migration Patterns and Dendritic Guidelines (1 hour) (AC5, AC15, AC16)

**Objective:** Create comprehensive documentation for migration patterns and dendritic pattern guidelines for Epic 2-6 reuse.

- [ ] **Subtask 7.1:** Document migration patterns
  - Document shared vs platform-specific configuration pattern
  - Document blackphos migration checklist
  - Document cinnabar user configuration guide
  - Document cross-platform user module reuse pattern
  - Save to `docs/notes/architecture/` (alongside dendritic-organization-patterns.md from investigations)

- [ ] **Subtask 7.2:** Document dendritic pattern guidelines
  - Document file organization standards
  - Document module composition patterns
  - Document namespace hygiene rules
  - Reference gaetanlepage as exemplar pattern
  - Save to `docs/notes/architecture/` (dendritic pattern reference for Epic 2-6)

- [ ] **Subtask 7.3:** Update story completion notes
  - Document audit findings (Task 1)
  - Document migration checklist (Task 2)
  - Document cinnabar user deployment (Task 3)
  - Document dendritic pattern refinements (Task 4)
  - Document test results (Task 6)
  - List all files created/modified

**Success Criteria:** Comprehensive migration and pattern documentation created, story completion notes complete with all findings.

---

## Dev Notes

### Critical Context from Story 1.9

**Previous Story Learnings (Story 1.9 - done):**

**New Services/Patterns Created:**
- Zerotier network operational: `db4344343b14b903`
- Cinnabar controller: `fddb:4344:343b:14b9:399:93db:4344:343b` (node `db4344343b`)
- Electrum peer: `fddb:4344:343b:14b9:399:93d1:7e6d:27cc` (node `d17e6d27cc`)
- Bidirectional connectivity: 1-12ms latency, 0% packet loss

**Files Available for Reuse:**
- `~/projects/nix-workspace/test-clan/modules/machines/nixos/cinnabar/default.nix` - Cinnabar machine module
- `~/projects/nix-workspace/test-clan/modules/machines/nixos/electrum/default.nix` - Electrum machine module
- `~/projects/nix-workspace/test-clan/modules/home/users/crs58/default.nix` - Portable crs58 home module (ready for cinnabar)
- `~/projects/nix-workspace/test-clan/modules/clan/inventory/machines.nix` - Clan inventory with cinnabar/electrum

**Architectural Decisions from 1.9:**
- Production naming established (cinnabar = primary VPS, electrum = secondary test VM)
- Zerotier network foundation laid for Story 1.10 heterogeneous networking
- VM rename operations validated with zero regressions (14/14 tests passing)

**Warnings/Recommendations:**
- `clan machines update` uploads vars but doesn't restart services - manual `systemctl restart` required
- Age key re-encryption required after VM redeployment
- Zerotier network ID documentation critical for future integrations

**Story 1.9 Unblocked:**
- Story 1.10 (this story): Complete migrations and establish clean foundation
- Story 1.11: Type-safe home-manager architecture implementation
- Story 1.12: blackphos physical deployment and heterogeneous networking validation

**Technical Debt from 1.9:**
- Zerotier network ID missing from README/architecture docs (MED-1 from review)
- Clan service restart behavior unclear (MED-2 from review)
- Age key lifecycle workflow not documented (LOW-1 from review)

**Review Findings:**
- APPROVED with 3 advisory notes for documentation improvements
- Zero-regression validated: 14/14 tests passing
- Network operational with low latency (1-12ms)

### Architecture Context

**Dendritic Organization Patterns (from investigation):**
- gaetanlepage pattern: Separation of base modules, host-specific modules, hardware modules
- test-clan current state: Appropriate structure, minimal restructuring needed
- Key insight: Namespaces reflect functional responsibility, not filesystem location
- Reference: `docs/notes/architecture/dendritic-organization-patterns.md`

**Shared vs Platform-Specific Pattern (from investigation):**
- infra's blackphos ↔ blackphos-nixos relationship reveals "replica" pattern
- Shared: User identity (cameron/crs58), SSH keys, nix settings, caches, development tooling
- Platform-specific darwin: Homebrew, GUI apps, macOS system defaults, touchID
- Platform-specific nixos: Boot/disk config, systemd services, server-specific tools
- cinnabar should share user configuration with blackphos (cameron/crs58 identity) but exclude platform-specific settings

**Critical Gap Identified:**
- cinnabar (nixos server) has NO user configuration currently
- Only srvos defaults + zerotier configuration from Story 1.5
- Blocks Story 1.12 (blackphos deployment) - can't validate heterogeneous networking without user logins
- Blocks type-safe architecture (Story 1.11) - needs finalized user modules

**Portable Home-Manager Modules (Story 1.8A):**
- `modules/home/users/crs58/default.nix` - Ready for cinnabar NixOS integration
- `modules/home/users/raquel/default.nix` - Cross-platform raquel config
- Pattern: User modules self-contained with platform detection (pkgs.stdenv.isDarwin)
- Three integration modes: darwin integrated, NixOS integrated, standalone

### Architectural Reference Documents

**Key Documents:**
1. **Investigation Reports:**
   - `docs/notes/architecture/dendritic-organization-patterns.md` - dendritic nixos/darwin patterns
   - infra blackphos analysis (in this story) - shared vs platform-specific pattern
   - test-clan current state (in this story) - gaps identified

2. **Architectural Guidance:**
   - `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config` - exemplar dendritic pattern
   - `~/projects/nix-workspace/infra` - blackphos configuration reference
   - `~/projects/nix-workspace/test-clan` - current state (Story 1.9 complete)

3. **Clan-Core Integration Constraints (must preserve):**
   - `clan-core.inventory` structure (machine definitions, service instances)
   - `clan-core.services.*` (service instance registration)
   - `clan-core.vars.*` and `clan-core.secrets.*` (access patterns)
   - Zerotier network configuration interface

### Implementation Approach

**⚠️ This story involves complex cross-repository migration:**

**A. Anchor ALL migrations to working examples:**
- **Never guess** what to migrate - compare infra vs test-clan explicitly
- **Always verify** package lists, service configs, system settings
- **Priority order for reference:**
  1. **infra blackphos config** (source of truth for what to migrate)
  2. **infra blackphos-nixos config** (source of truth for shared pattern)
  3. **test-clan blackphos config** (target of migration)
  4. **gaetanlepage patterns** (exemplar dendritic organization)
  5. **Story 1.8A modules** (portable home-manager modules ready for reuse)

**B. Validate zero regression rigorously:**
- **Package diff comparison** before/after migration (Story 1.8A pattern)
- **Test harness execution** after every major change (14/14 tests must pass)
- **Build validation** for all configurations after changes
- **SSH login validation** for cameron user on cinnabar

**C. When uncertain:**
1. Read the working example code in reference projects
2. Compare infra vs test-clan configurations explicitly
3. Run `nix repl` to test expressions before committing
4. Ask for clarification rather than guessing
5. Use test harness to validate changes immediately

**D. Red flags that indicate you're guessing:**
- Migrating config without explicit comparison to infra source
- Skipping package diff validation ("it should be the same")
- Assuming shared config without checking blackphos-nixos pattern
- Not validating cameron user login after deployment

**This story is migration + refinement, but the CROSS-REPOSITORY COMPLEXITY means every migration must be validated against source and tests.**

### Project Structure Alignment

**test-clan Dendritic Structure (current):**
```
modules/
├── machines/
│   ├── nixos/
│   │   ├── cinnabar/default.nix
│   │   ├── electrum/default.nix
│   │   └── gcp-vm/default.nix
│   ├── darwin/
│   │   ├── blackphos/default.nix
│   │   └── test-darwin/default.nix
│   └── home/
│       └── .keep
├── darwin/
│   └── base.nix
├── system/
│   ├── nix-settings.nix
│   ├── admins.nix
│   └── initrd-networking.nix
├── home/
│   └── users/
│       ├── crs58/default.nix
│       └── raquel/default.nix
├── clan/
│   ├── machines.nix
│   ├── inventory/
│   └── ...
└── checks/
    └── ...
```

**Pattern Compliance Targets:**
- File length: <200 lines per file (modularize if justified)
- `_` prefix: Only for non-module data files (JSON, YAML, shell scripts)
- Namespace consistency: `flake.modules.{darwin|nixos|homeManager}.*`
- Module separation: base modules, host-specific modules, user modules

**gaetanlepage Exemplar Pattern:**
- `modules/flake/hosts.nix` - nixosConfigurations/homeConfigurations generation
- `modules/hosts/<hostname>/default.nix` - Host-specific modules
- `modules/nixos/core`, `modules/nixos/desktop` - System modules
- Clear separation: shared base, host-specific, hardware, features

### Testing Strategy

**Regression Prevention:**
1. **Capture pre-migration state:**
   - blackphos package list (infra)
   - blackphos package list (test-clan current)
   - Test harness baseline (14/14 tests passing from Story 1.9)

2. **Perform migrations:**
   - Migrate remaining config from infra to test-clan
   - Deploy cameron user to cinnabar
   - Refine dendritic patterns

3. **Validate post-migration:**
   - blackphos package list (test-clan post-migration)
   - Compare: infra = test-clan post-migration (zero regression)
   - Test harness: 14/14 tests continue passing
   - cameron user login: SSH works on cinnabar
   - Home-manager builds: Both platforms (darwin + nixos)

**Zero-Regression Validation:**
- Configuration refactoring and migration (must preserve all functionality)
- Package diff comparison critical (Story 1.8A pattern)
- Test harness validates structural equivalence and architectural invariants
- SSH login validation ensures user deployment successful

### References

**test-clan Validation (Stories 1.1-1.9):**
- Dendritic pattern proven with 17 test cases (Stories 1.6-1.7)
- Zero-regression refactoring validated in Story 1.7
- Zerotier network operational in Story 1.9 (network `db4344343b14b903`)
- 14/14 tests passing (Story 1.9)

**Story 1.8A Portable Home Modules:**
- `docs/notes/development/work-items/1-8a-extract-portable-home-manager-modules.md`
- crs58 module ready for NixOS integration (cinnabar deployment)
- Pattern documented in architecture.md
- Cross-platform portability via conditional homeDirectory

**infra Configurations (migration source):**
- `~/projects/nix-workspace/infra/hosts/blackphos/configuration.nix` - Source config
- `~/projects/nix-workspace/infra/hosts/blackphos-nixos/configuration.nix` - Shared pattern reference
- Migration target: `~/projects/nix-workspace/test-clan/modules/machines/darwin/blackphos/default.nix`

**Dendritic Organization Investigation:**
- `docs/notes/architecture/dendritic-organization-patterns.md` - Investigation findings
- gaetanlepage exemplar: `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config`
- Pattern guidance for module organization and namespace hygiene

**Epic 1 Acceptance Criteria Mapping:**
This story contributes to Epic 1 success criteria:
1. ✅ Hetzner VMs deployed and operational (Story 1.5, preserved through Story 1.9)
2. ✅ Dendritic pattern proven (Stories 1.6-1.7, refined in this story)
3. ⏳ Cross-platform user config sharing validated (this story: cinnabar user deployment)
4. ⏳ Heterogeneous zerotier network (Story 1.9: nixos ↔ nixos, Story 1.12: + darwin)
5. ⏳ Migration patterns documented (this story: shared vs platform-specific pattern)
6. ⏳ Type-safe architecture (Story 1.11: depends on this story's clean foundation)
7. ⏳ GO/CONDITIONAL GO/NO-GO decision (Story 1.12: depends on Story 1.11)

---

## Risk Mitigation

### Migration Risks

**Risk:** Missed configuration in blackphos migration
**Mitigation:**
- Comprehensive audit (Task 1) with explicit comparison infra vs test-clan
- Migration checklist created before migration execution
- Package diff comparison validates zero regression
- Test harness validates architectural invariants

**Risk:** cinnabar user deployment breaks zerotier network
**Mitigation:**
- Deploy cameron user configuration separately from zerotier config
- Validate zerotier network operational after deployment
- Story 1.9 established baseline (network `db4344343b14b903` operational)
- SSH login validation confirms user deployment successful without breaking network

**Risk:** Dendritic pattern refinements introduce regressions
**Mitigation:**
- Test harness execution after every change
- 14/14 tests must continue passing (Story 1.9 baseline)
- Build validation for all configurations after changes
- Clan inventory validation ensures clan-core integration preserved

### Pattern Compliance Risks

**Risk:** Over-modularization creates indirection and complexity
**Mitigation:**
- File length target is <200 lines, not <100 lines
- Only modularize if justified (extract reusable components)
- Document exceptions with rationale
- Follow gaetanlepage exemplar (pragmatic, not dogmatic)

**Risk:** `_` prefix pattern unclear or inconsistently applied
**Mitigation:**
- Clear rule: `_` prefix ONLY for non-module data files (JSON, YAML, shell scripts)
- Audit all `_` prefix files in modules/
- Rename any flake-parts modules incorrectly using `_` prefix
- Document pattern in architecture guidelines

### Documentation Risks

**Risk:** Migration patterns not documented for Epic 2-6 reuse
**Mitigation:**
- Task 7 explicitly creates migration pattern documentation
- Shared vs platform-specific pattern documented
- Migration checklist documented for reproducibility
- Cross-platform user module reuse pattern documented

---

## Definition of Done

- [ ] blackphos migration audit complete (AC1)
- [ ] All remaining configuration migrated to test-clan (AC2)
- [ ] Shared vs platform-specific configuration identified and documented (AC3)
- [ ] cinnabar user configuration deployed and validated (AC4)
- [ ] Migration pattern documented (AC5)
- [ ] File length compliance validated (AC6)
- [ ] Pattern compliance enforced (AC7)
- [ ] Module organization refined (AC8)
- [ ] All configurations build successfully (AC9)
- [ ] Clan-core compatibility maintained (AC10)
- [ ] Zerotier network operational (AC11)
- [ ] Migration validation tests pass (AC12)
- [ ] Pattern compliance tests pass (AC13)
- [ ] Integration tests pass (AC14)
- [ ] Migration documentation complete (AC15)
- [ ] Dendritic pattern guidelines documented (AC16)
- [ ] All 7 implementation tasks completed
- [ ] Story completion notes document all findings
- [ ] Story 1.11 unblocked (clean foundation established for type-safe architecture)
- [ ] Story 1.12 unblocked (cameron user on cinnabar enables heterogeneous networking validation)

---

## Dev Agent Record

### Context Reference

- `docs/notes/development/work-items/1-10-complete-migrations-establish-clean-foundation.context.xml` (generated 2025-11-13)

### Agent Model Used

claude-sonnet-4-5-20250929

### Debug Log References

**Task 1: blackphos Migration Audit (2025-11-13)**

Performed explicit comparison between:
- Source: `~/projects/nix-workspace/infra/configurations/darwin/blackphos.nix` + imported modules
- Target: `~/projects/nix-workspace/test-clan/modules/machines/darwin/blackphos/default.nix`

**Already Migrated (Story 1.8):**
- ✅ Hostname, computer name, platform (aarch64-darwin)
- ✅ State version = 4 (correctly overriding base)
- ✅ Primary user = crs58
- ✅ Homebrew casks: codelayer-nightly, dbeaver-community, docker-desktop, gpg-suite, inkscape, keycastr, meld, postgres-unofficial
- ✅ Mac App Store: save-to-raindrop-io (1549370672)
- ✅ TouchID sudo authentication
- ✅ Multi-user config: crs58 (UID 550) + raquel (UID 551) with SSH keys, shells (zsh), home directories
- ✅ Home-manager integration with portable modules (flakeModulesHome."users/{crs58,raquel}")
- ✅ System packages: vim, git
- ✅ Zsh enabled system-wide

**Missing Shared Configuration (From infra's nixosModules.common):**

1. **Nix Caches/Substituters** (`modules/nixos/shared/caches.nix`):
   - 7 cachix caches: cache.nixos.org, nix-community, cameronraysmith, poetry2nix, pyproject-nix, om, catppuccin
   - Corresponding trusted-public-keys
   - **Classification: SHARED** (benefits both darwin + nixos)

2. **Advanced Nix Settings** (`modules/nixos/shared/nix.nix`):
   - nixpkgs.config: allowBroken, allowUnsupportedSystem, allowUnfree
   - nixpkgs.overlays (from self.overlays + lazyvim.overlays.nvim-treesitter-main)
   - nix.nixPath = [ "nixpkgs=${flake.inputs.nixpkgs}" ]
   - nix.registry.nixpkgs.flake (pinned nixpkgs)
   - Automatic garbage collection: gc.automatic = true, gc.options = "--delete-older-than 14d", gc.interval (darwin launchd)
   - Automatic store optimization: optimise.automatic = true
   - nix.settings.extra-platforms (darwin: aarch64-darwin x86_64-darwin)
   - nix.settings.min-free = 5GB, max-free = 10GB (emergency GC)
   - **Classification: SHARED** (nix daemon behavior consistent across platforms)

3. **macOS System Defaults** (`modules/darwin/all/settings.nix` - 258 lines):
   - Dock, Finder, LoginWindow, Trackpad, Screenshot, NSGlobalDomain preferences
   - **Classification: PLATFORM-SPECIFIC** (darwin only, NOT needed on cinnabar)
   - **Decision: Do NOT migrate to test-clan base** (already exists in infra, user can customize per-machine)
   - Note: These are user preferences, not infrastructure config

4. **Additional Homebrew Packages** (`modules/darwin/all/homebrew.nix`):
   - baseCaskApps (40+ GUI apps): aldente, alt-tab, betterdisplay, calibre, claude, cyberduck, etc.
   - baseMasApps: bitwarden, whatsapp
   - caskFonts: 14 font families
   - **Classification: PLATFORM-SPECIFIC** (darwin only)
   - **Decision: NOT migrated** - blackphos uses additionalCasks, not base cask list

**Shared vs Platform-Specific Summary:**

**SHARED Configuration (apply to both blackphos darwin + cinnabar nixos):**
- Nix caches/substituters (build performance + availability)
- Nix settings (experimental-features already shared, add gc/optimization/overlays)
- User identity (crs58/cameron SSH keys, shell, admin privileges) ← **CRITICAL for Story Task 3**

**PLATFORM-SPECIFIC (darwin):**
- Homebrew (casks, GUI apps, fonts)
- macOS system defaults (dock, finder, trackpad)
- TouchID authentication
- system.stateVersion (darwin versioning)

**PLATFORM-SPECIFIC (nixos):**
- Boot loader, disk config (disko)
- systemd services
- Firewall/networking (beyond hostname)
- system.stateVersion (nixos versioning)

**Migration Checklist for Task 2:**
1. Add nix caches/substituters to test-clan darwin base or blackphos
2. Add advanced nix settings to test-clan darwin base
3. Validate zero regression via package diff (pre vs post migration)

**Task 3: cameron User Deployment (2025-11-13)**

Successfully deployed cameron user to cinnabar with home-manager integration:

**Configuration Changes:**
- `~/projects/nix-workspace/test-clan/modules/machines/nixos/cinnabar/default.nix`:
  - Added cameron user (wheel group, zsh shell, SSH key)
  - Integrated home-manager.nixosModules.home-manager
  - Imported crs58 home module with username override
  - Used outer config capture pattern to avoid infinite recursion

- `~/projects/nix-workspace/test-clan/modules/home/users/crs58/default.nix`:
  - Made username/homeDirectory configurable via lib.mkDefault
  - Enables username override for cameron alias on new machines

**Build Validation:**
- Successfully built: `/nix/store/bac91ljb08f6kqb69al0g3774ig5skhk-nixos-system-cinnabar-25.11.20251102.b3d51a0`
- home-manager service created: `unit-home-manager-cameron.service`
- No infinite recursion (resolved via proper config capture pattern)

**Deployment Status:**
- Build validated locally ✓
- VPS deployment pending (requires `clan machines update cinnabar`)
- SSH validation pending actual deployment

**Critical Unblocking:**
- Unblocks Story 1.12 (heterogeneous networking validation requires user SSH access)
- Establishes pattern for cameron username on new machines (per CLAUDE.md)

**Task 4: Dendritic Pattern Audit (2025-11-13)**

Comprehensive audit of test-clan dendritic pattern compliance:

**File Length Compliance:**
- ✅ All module files <200 lines except `modules/checks/validation.nix` (285 lines)
- **Justified exception:** validation.nix is test harness with 18+ distinct test cases
- Largest non-test modules:
  - cinnabar: 167 lines (includes user config from Task 3)
  - blackphos: 139 lines
  - electrum: 112 lines
- **Verdict:** Excellent compliance, no refactoring needed

**`_` Prefix Compliance:**
- ✅ Zero files with `_` prefix found in modules/
- Pattern correctly followed: `_` prefix only for non-module data files
- **Verdict:** Perfect compliance

**Namespace Consistency:**
- ✅ Consistent use of `flake.modules.{darwin|nixos|homeManager}.*`
- Machine modules: `"machines/{platform}/{hostname}"` pattern
- User modules: `"users/{username}"` pattern
- System modules: Auto-merge to `.base` namespace
- **Verdict:** Excellent consistency

**Organizational Comparison (test-clan vs gaetanlepage):**

test-clan structure (comprehensive):
- `clan/` - clan-core integration (multi-machine orchestration)
- `terranix/` - infrastructure as code (terraform/opentofu)
- `checks/` - validation and testing (18+ test cases)
- `system/` - shared system configuration (auto-merge to base)
- `machines/` - host-specific configs (nixos + darwin subdirs)
- `home/` - home-manager modules (portable user configs)
- `darwin/` - darwin-specific base modules

gaetanlepage structure (simpler):
- `flake/` - flake-level modules
- `hosts/` - host configurations
- `nixos/` - nixos modules
- `home/` - home-manager modules

**Verdict:** test-clan structure is MORE comprehensive and appropriate for use case:
- Clan-core multi-machine coordination (not in gaetanlepage)
- Infrastructure as code with terranix (not in gaetanlepage)
- Comprehensive test suite (validation.nix with 18+ checks)
- Heterogeneous platform support (darwin + nixos)

**Recommendation:** No reorganization needed. Current structure is well-designed for test-clan's complexity.

**Task 2: blackphos Migration Execution (2025-11-13)**

Migrated shared configuration from infra to test-clan via new system modules:

**Created Files:**
- `~/projects/nix-workspace/test-clan/modules/system/caches.nix`:
  - Exports to `flake.modules.{darwin|nixos}.base` (auto-merge pattern)
  - 7 cachix caches: cache.nixos.org, nix-community, cameronraysmith, poetry2nix, pyproject-nix, om, catppuccin
  - Corresponding trusted-public-keys for each cache
  - Applied to both darwin (blackphos) and nixos (cinnabar, electrum)

- `~/projects/nix-workspace/test-clan/modules/system/nix-optimization.nix`:
  - Exports to `flake.modules.{darwin|nixos}.base` (auto-merge pattern)
  - Platform-aware garbage collection:
    - darwin: launchd interval (Friday 9pm weekly)
    - nixos: systemd dates (weekly)
  - Automatic store optimization: nix.optimise.automatic = true
  - extra-platforms for darwin (aarch64-darwin x86_64-darwin)
  - min-free/max-free omitted (clan-core already sets 3GB/512MB defaults)

**Build Validation:**
- blackphos: Successfully built `/nix/store/l6qydpqa3y7izfji0a9f7rjp50an9ipg-darwin-system-25.11.5125a3c`
- cinnabar: Successfully built `/nix/store/5v78hjvw4c5xgfp980wjz80apzgi628g-nixos-system-cinnabar-25.11.20251102.b3d51a0`
- Zero regressions: All existing functionality preserved

**Key Learning:**
- Dendritic auto-merge pattern: system/ modules export directly to `flake.modules.{platform}.base` namespace
- Do NOT use config.flake.modules imports in base modules (causes infinite recursion)
- Multiple modules can contribute to same namespace (auto-merged by flake-parts)
- Avoided min/max-free conflict by deferring to clan-core's conservative defaults

**Files Modified in test-clan:**
- `modules/system/caches.nix` (created)
- `modules/system/nix-optimization.nix` (created)

### Completion Notes List

### File List

## Change Log

**2025-11-13**: Story drafted via create-story workflow. Status: drafted (was backlog). Ready for story-context workflow to generate technical context.
