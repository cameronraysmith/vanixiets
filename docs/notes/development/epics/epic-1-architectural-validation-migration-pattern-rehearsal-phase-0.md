# Epic 1: Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Goal:** Validate dendritic flake-parts + clan architecture for both nixos VMs and nix-darwin hosts, validate cross-platform user config sharing, and document nixos-unified → dendritic + clan transformation pattern through blackphos migration rehearsal

**Strategic Value:** Validates complete stack (dendritic + clan + terraform + infrastructure) on real VMs and darwin machines before production refactoring, proves both target architecture AND transformation process, validates cross-platform home-manager modularity (Epic 1 architectural requirement), provides reusable migration blueprint for Epic 2+ by rehearsing complete nixos-unified → dendritic + clan conversion

**Timeline:** 4-5 weeks
- Phase 0 (Stories 1.1-1.10A): ✅ COMPLETE (3 weeks actual)
- Phase 1 (Stories 1.10B-1.10C): 16-22 hours (home-manager + secrets migration)
- Phase 2 (Party Mode Checkpoint): 1-2 hours (evidence-based Story 1.11 decision)
- Phase 3 (Story 1.11 conditional): 0-16 hours (depends on checkpoint)
- Phase 4 (Stories 1.12-1.14): 8-12 hours (deployment + validation + GO/NO-GO)
- **Total remaining:** 25-52 hours (1-2 weeks depending on Story 1.11 decision)

**Success Criteria:**
- Hetzner VMs deployed and operational (minimum requirement achieved)
- Dendritic flake-parts pattern proven with zero regressions (achieved via Stories 1.6-1.7)
- Nix-darwin machine (blackphos) migrated from infra to test-clan management
- **Complete home-manager ecosystem migrated (Story 1.10B - 51 modules, all priorities)**
- **Secrets migrated to clan vars (Story 1.10C - Pattern B validated)**
- **Cross-platform user config sharing validated (Story 1.8A - portable home modules)**
- **Evidence-based architectural decisions (Party Mode checkpoint validates patterns)**
- Heterogeneous zerotier network operational (nixos VMs + nix-darwin host)
- Nixos-unified → dendritic + clan transformation pattern documented
- Migration patterns documented for production refactoring in Epic 2+
- GO/CONDITIONAL GO/NO-GO decision made with explicit rationale

**Risk Level:** Medium (infrastructure deployment costs money, operational risk)

**Architectural Gap Identified (2025-11-12):**
Story 1.8 revealed inline home-manager configs (feature regression from infra). Story 1.8A inserted to restore modular pattern before Story 1.9. This validates cross-platform user config sharing as part of Epic 1 architectural requirements.

---

## Story 1.1: Setup test-clan repository with terraform/terranix infrastructure

As a system administrator,
I want to prepare test-clan repository with both clan-core and terranix/terraform infrastructure,
So that I can deploy real VMs (Hetzner + GCP) using proven patterns from clan-infra.

**Acceptance Criteria:**
1. test-clan repository at ~/projects/nix-workspace/test-clan/ has working branch created
2. flake.nix updated with inputs: nixpkgs (unstable), flake-parts, clan-core (main branch), terranix (for terraform generation), disko (for declarative disk partitioning), srvos (for server hardening)
3. Terranix flake module imported: `inputs.terranix.flakeModule`
4. modules/ directory structure created: modules/base/, modules/hosts/, modules/flake-parts/, modules/terranix/
5. modules/terranix/base.nix created with provider configuration: Hetzner Cloud provider (hcloud), GCP provider (google), Secrets retrieval via clan secrets (API tokens)
6. modules/flake-parts/clan.nix created with clan.meta.name = "test-clan"
7. Flake evaluates: `nix flake check`
8. Terraform inputs available: `nix eval .#terranix --apply builtins.attrNames`
9. README.md documents Phase 0 infrastructure deployment purpose

**Prerequisites:** None (first story)

**Estimated Effort:** 2-4 hours

**Risk Level:** Low (setup only, no deployment yet)

---

## Story 1.2: Implement dendritic flake-parts pattern in test-clan (OPTIONAL)

As a system administrator,
I want to apply dendritic flake-parts organizational patterns to test-clan,
So that I can evaluate whether dendritic optimization adds value alongside clan functionality.

**⚠️ OPTIONAL STORY - Can skip if conflicts with infrastructure deployment**

**Acceptance Criteria:**
1. import-tree configured in flake.nix for automatic module discovery (if using dendritic)
2. Base module created contributing to flake.modules.nixos.base namespace
3. Test host module using config.flake.modules namespace imports
4. Module namespace evaluates: `nix eval .#flake.modules.nixos --apply builtins.attrNames`
5. No additional specialArgs beyond minimal framework values
6. Dendritic pattern documented in DENDRITIC-NOTES.md (what worked, what didn't)

**Prerequisites:** Story 1.1 (test-clan infrastructure setup)

**Estimated Effort:** 2-4 hours (only if pursuing dendritic)

**Risk Level:** Low (can abandon if conflicts discovered)

**Decision Point:** If dendritic conflicts with terranix or clan integration: SKIP and proceed to Story 1.3. Infrastructure deployment is non-negotiable, dendritic optimization is nice-to-have.

---

## Story 1.3: Configure clan inventory with Hetzner and GCP VM definitions

As a system administrator,
I want to define clan inventory with real VM machine definitions (Hetzner + GCP),
So that I have infrastructure targets for terraform deployment and clan coordination.

**Acceptance Criteria:**
1. modules/flake-parts/clan.nix expanded with inventory.machines: `hetzner-vm`: tags = ["nixos" "cloud" "hetzner"], machineClass = "nixos"; `gcp-vm`: tags = ["nixos" "cloud" "gcp"], machineClass = "nixos"
2. Service instances configured: `emergency-access`: roles.default.tags."all" (both VMs), `sshd-clan`: roles.server.tags."all" + roles.client.tags."all", `zerotier-local`: roles.controller.machines.hetzner-vm + roles.peer.machines.gcp-vm, `users-root`: roles.default.tags."all" (root access both VMs)
3. Inventory evaluates: `nix eval .#clan.inventory --json | jq .machines`
4. Machine definitions include proper tags for service targeting
5. nixosConfigurations created for both machines (minimal, will expand later)
6. Configurations build: `nix build .#nixosConfigurations.{hetzner-vm,gcp-vm}.config.system.build.toplevel`

**Prerequisites:** Story 1.1 (infrastructure setup), Story 1.2 OPTIONAL (dendritic pattern, only if completed)

**Estimated Effort:** 2-4 hours

**Risk Level:** Low (configuration only, no deployment)

---

## Story 1.4: Create Hetzner VM terraform configuration and host modules

As a system administrator,
I want to create terraform configuration for Hetzner Cloud VM provisioning,
So that I can deploy hetzner-vm using proven patterns from clan-infra.

**Acceptance Criteria:**
1. modules/terranix/hetzner.nix created with: hcloud provider configuration, SSH key resource for terraform deployment key, Hetzner Cloud server resource (CX22 or CX32, 2-4 vCPU for testing), null_resource for `clan machines install` provisioning
2. modules/hosts/hetzner-vm/default.nix created with: Base NixOS configuration (hostname, state version, nix settings), srvos hardening modules imported, Networking configuration
3. modules/hosts/hetzner-vm/disko.nix created with: LUKS encryption for root partition, Standard partition layout (EFI + LUKS root)
4. Hetzner API token stored as clan secret: `clan secrets set hetzner-api-token` **(REQUIRES USER: obtain real API token from Hetzner Cloud console, agent must pause and coordinate)**
5. Terraform configuration generates: `nix build .#terranix.terraform`
6. Generated terraform valid: manual review of terraform.tf.json
7. Host configuration builds: `nix build .#nixosConfigurations.hetzner-vm.config.system.build.toplevel`
8. Disko configuration generates partition commands: `nix eval .#nixosConfigurations.hetzner-vm.config.disko.disks --apply toString`

**Prerequisites:** Story 1.3 (inventory configured)

**Note:** Story 1.4 requires manual user intervention to configure cloud provider credentials. Agent must pause before terraform validation commands.

**Estimated Effort:** 4-6 hours

**Risk Level:** Medium (first terraform configuration, pattern learning)

---

## Story 1.5: Deploy Hetzner VM and validate infrastructure stack

As a system administrator,
I want to provision and deploy hetzner-vm to Hetzner Cloud,
So that I can validate the complete infrastructure stack (terraform + clan + disko + NixOS) works end-to-end.

**Acceptance Criteria:**
1. Terraform initialized: `nix run .#terranix.terraform -- init`
2. Terraform plan reviewed: `nix run .#terranix.terraform -- plan` (check resource creation)
3. Hetzner VM provisioned: `nix run .#terranix.terraform -- apply`
4. VM accessible via SSH with terraform deploy key
5. Clan vars generated for hetzner-vm: `clan vars generate hetzner-vm`
6. NixOS installed via clan: `clan machines install hetzner-vm --target-host root@<ip> --update-hardware-config nixos-facter --yes`
7. System boots successfully with LUKS encryption
8. Post-installation SSH access works: `ssh root@<hetzner-ip>` (using clan-managed keys)
9. Zerotier controller operational: `ssh root@<hetzner-ip> "zerotier-cli info"` shows controller
10. Clan vars deployed: `ssh root@<hetzner-ip> "ls -la /run/secrets/"` shows sshd keys
11. No critical errors in journalctl logs

**Prerequisites:** Story 1.4 (Hetzner terraform + host config)

**Estimated Effort:** 4-8 hours (deployment + validation + troubleshooting)

**Risk Level:** High (real infrastructure deployment, costs money, operational risk)

**Cost:** ~€5-8/month for Hetzner CX22/CX32 (acceptable testing cost)

---

## Story 1.6: Implement comprehensive test harness for test-clan infrastructure validation

As a system administrator,
I want to implement a comprehensive test suite for test-clan that validates infrastructure functionality,
So that I can confidently refactor the codebase with zero-regression guarantees.

**Acceptance Criteria:**
1. Test infrastructure setup: nix-unit added, test directories created (regression, invariant, feature, integration, snapshots), test runner script operational
2. Regression tests implemented and passing: RT-1 (Terraform output equivalence), RT-2 (NixOS closure equivalence), RT-3 (Machine builds)
3. Invariant tests implemented and passing: IT-1 (Clan inventory structure), IT-2 (Service targeting), IT-3 (specialArgs propagation)
4. Feature tests implemented (expected to fail): FT-1 (import-tree discovery), FT-2 (Namespace exports), FT-3 (Self-composition)
5. Integration tests implemented and passing: VT-1 (VM boot tests for all 3 machines)
6. Baseline snapshots captured: terraform.json, nixos-configs.json, clan-inventory.json
7. Full test suite runs successfully via ./tests/run-all.sh
8. Test categories behave as expected: regression PASS, invariant PASS, feature FAIL (expected), integration PASS

**Prerequisites:** Story 1.5 (Hetzner deployed - operational VMs provide test targets)

**Estimated Effort:** 6-8 hours (test infrastructure + implementation + validation)

**Risk Level:** Low (testing infrastructure, no deployment changes)

**Related Documents:** docs/notes/development/dendritic-refactor-test-strategy.md

---

## Story 1.7: Execute dendritic flake-parts refactoring in test-clan using test harness

As a system administrator,
I want to refactor test-clan to full dendritic compliance using the test harness for validation,
So that the architectural pattern is proven and validated for future phases.

**Acceptance Criteria:**
1. All refactoring steps completed with test validation: Step 2.1 (import-tree added), Step 2.2 (base modules exported), Step 2.3 (one host refactored), Step 2.4 (remaining hosts refactored), Step 2.5 (automatic host collection assessed)
2. All regression tests passing: Terraform output equivalent, NixOS closures equivalent, all machines build
3. All invariant tests passing: Inventory preserved, service targeting preserved, specialArgs propagation maintained
4. All feature tests passing: import-tree discovery works, namespace exports functional, self-composition enabled
5. All integration tests passing: All 3 machines boot successfully in VMs
6. Git workflow complete: Feature branch with per-step commits, merged to main after validation
7. Operational VMs protected: No accidental deployment to 162.55.175.87 or 49.13.140.183
8. Zero regressions confirmed via comprehensive test suite

**Prerequisites:** Story 1.6 (test harness operational with all baseline tests passing)

**Estimated Effort:** 8-10 hours (incremental refactoring + validation per step)

**Risk Level:** Medium (refactoring code, but test harness provides safety net)

**Related Documents:** docs/notes/development/dendritic-flake-parts-assessment.md (defines gaps), docs/notes/development/dendritic-refactor-test-strategy.md (defines approach)

---

## Story 1.8: Migrate blackphos from infra to test-clan management

As a system administrator,
I want to migrate blackphos nix-darwin configuration from infra's nixos-unified pattern to test-clan's dendritic + clan pattern,
So that I can validate the complete transformation process and document the migration pattern for refactoring infra in Epic 2+.

**Status Update (2025-11-12):** Configuration build complete, CRITICAL GAP IDENTIFIED - home-manager configs are inline (not reusable across platforms). This blocks Epic 1 progression. Course correction: Insert Story 1.8A to extract portable home modules before Story 1.9.

**Acceptance Criteria:**
1. Blackphos configuration migrated from infra to test-clan: Nix-darwin host configuration created in modules/hosts/blackphos/, Home-manager user configuration (crs58) migrated and functional, All existing functionality preserved (packages, services, shell config)
2. Configuration uses dendritic flake-parts pattern: Module imports via config.flake.modules namespace, Proper module organization (darwin base, homeManager, host-specific), Reference clan-core home-manager integration patterns, Reference dendritic flake-parts home-manager usage from examples in CLAUDE.md (clan-infra, qubasa-clan-infra, mic92-clan-dotfiles, dendrix-dendritic-nix, gaetanlepage-dendritic-nix-config)
3. Blackphos added to clan inventory: tags = ["darwin" "workstation" "backup"], machineClass = "darwin"
4. Clan secrets/vars configured for blackphos: Age key for user crs58 added to admins group, SSH host keys generated via clan vars, User secrets configured if needed
5. Configuration builds successfully: `nix build .#darwinConfigurations.blackphos.system` ✅ COMPLETE
6. Transformation documented if needed: nixos-unified-to-clan-migration.md created (if valuable) documenting step-by-step conversion process, Module organization patterns (what goes where), Secrets migration approach (sops-nix → clan vars), Common issues and solutions discovered
7. Package list comparison: Pre-migration vs post-migration packages identical (zero-regression validation)

**Prerequisites:** Story 1.7 (dendritic refactoring complete)

**Estimated Effort:** 6-8 hours (investigation + transformation + documentation)

**Risk Level:** Medium (converting real production machine, but not deploying yet)

**Strategic Value:** Provides concrete migration pattern for refactoring all 4 other machines in infra during Epic 2+

**Outcome:** Configuration builds successfully, multi-user pattern validated, BUT home configs are inline (feature regression from infra). Story 1.8A required to restore modular pattern.

---

## Story 1.8A: Extract Portable Home-Manager Modules for Cross-Platform User Config Sharing

**⚠️ CRITICAL PATH - Blocks Story 1.9 and Epic 1 Progression**

As a system administrator,
I want to extract crs58 and raquel home-manager configurations from blackphos into portable, reusable modules,
So that user configs can be shared across platforms (darwin + NixOS) without duplication and support three integration modes (darwin integrated, NixOS integrated, standalone).

**Context:** Story 1.8 successfully validated dendritic + clan pattern but implemented home configs inline in machine module. This is a **feature regression** from infra's proven modular pattern. Blocks:
- Story 1.9: cinnabar needs crs58 config → would require duplication
- Story 1.10: Network validation needs crs58 on both platforms
- Epic 2+: 4 more machines need crs58 → 6 duplicate configs total

**Epic 1 Goal:** Architectural validation must prove cross-platform user config sharing works.

**Acceptance Criteria:**
1. crs58 home module created: `modules/home/users/crs58/default.nix` exported to `flake.modules.homeManager."users/crs58"` namespace
2. raquel home module created: `modules/home/users/raquel/default.nix` exported to namespace
3. Standalone homeConfigurations exposed: `flake.homeConfigurations.{crs58,raquel}` for `nh home switch` workflow
4. blackphos refactored to import shared modules: Zero regression validated via package diff
5. Standalone activation validated: `nh home switch . -c crs58` works
6. Pattern documented in architecture.md for Story 1.9 reuse (cinnabar NixOS)
7. Test harness updated with validation coverage
8. Architectural decisions documented: Clan-core investigation findings (users clanService analysis, home-manager pattern divergence, alignment assessment), justification for traditional `users.users.*` approach (darwin compatibility + UID control), user-based vs profile-based modules rationale, preservation of infra features validated

**Prerequisites:** Story 1.8 (configuration builds, inline configs identified as gap)

**Blocks:** Story 1.9 (cinnabar needs crs58 module), Story 1.10 (network validation needs shared config)

**Estimated Effort:** 2-3 hours (well-scoped, pattern proven in infra)

**Risk Level:** Low (refactoring only, builds already validated)

**Strategic Value:** Restores proven capability from infra, unblocks Epic 1-6 progression, enables DRY principle for 6 machines

---

## Story 1.9: Rename Hetzner VMs to cinnabar/electrum and establish zerotier network

As a system administrator,
I want to rename the test Hetzner VMs to their intended production names (cinnabar and electrum) and establish a zerotier network between them,
So that the test-clan infrastructure mirrors the production topology that will be deployed in Epic 2+.

**Acceptance Criteria:**
1. VMs renamed in test-clan configuration: hetzner-vm → cinnabar (primary VPS), test-vm → electrum (secondary test VM)
2. Clan inventory updated: Machine definitions reflect new names (cinnabar, electrum), Tags and roles preserved from original configuration
3. Zerotier network established: Cinnabar configured as zerotier controller, Electrum configured as zerotier peer, Network ID documented for future machine additions
4. Network connectivity validated: Bidirectional ping between cinnabar and electrum via zerotier IPs, SSH via zerotier works in both directions, Network latency acceptable for coordination
5. Configuration rebuilds successful: Both VMs rebuild with new names without errors, Clan vars regenerated for renamed machines if needed
6. Test harness updated: Tests reference new machine names (cinnabar, electrum), All regression tests passing after rename
7. Documentation updated: README or relevant docs reflect cinnabar/electrum as test infrastructure names

**Prerequisites:** Story 1.8 (blackphos configuration migrated)

**Estimated Effort:** 2-3 hours

**Risk Level:** Low (rename operation, zerotier already working from Story 1.5)

**Note:** This prepares test-clan to mirror production topology where cinnabar and electrum will be migrated from test-clan to infra during the production refactoring.

---

## Story 1.10: Complete Migrations and Establish Clean Foundation

As a system administrator,
I want to complete the blackphos migration from infra, apply shared configuration to cinnabar, and refactor test-clan to exemplar dendritic patterns,
So that I have complete, clean configurations ready for deployment and a solid foundation for type-safe home-manager architecture.

**Context:**
- Story 1.8/1.8A migrated blackphos configuration but did NOT migrate all configuration from infra repository
- cinnabar (nixos server) currently has NO user configuration (only srvos defaults + zerotier)
- Some configuration files growing too long without proper modularization
- Dendritic pattern not consistently applied in all areas
- Must complete migrations and establish clean foundation BEFORE implementing type-safe architecture (Story 1.11)

**Critical Insight from Architecture Investigation:**
infra's blackphos ↔ blackphos-nixos relationship shows "replica" means SHARED configuration (caches, nix settings, user identity, SSH keys) NOT identical configuration. cinnabar should share user configuration with blackphos (cameron/crs58 identity) but exclude platform-specific settings (homebrew, GUI, macOS defaults).

**Architectural Reference:**
- `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config` - exemplar dendritic pattern
- `docs/notes/architecture/dendritic-organization-patterns.md` - investigation findings
- Maintain clan-core compatibility throughout (inventory, services, vars/secrets access)

**Acceptance Criteria:**

**A. Complete blackphos Migration and Apply Shared Config to cinnabar:**

1. **blackphos Migration Audit:**
   - Audit infra blackphos configuration vs test-clan blackphos configuration
   - Identify ALL remaining configuration not yet migrated (packages, services, system settings, etc.)
   - Migrate all remaining configuration to test-clan following dendritic patterns
   - Validate zero regression: Package list comparison (pre vs post migration)

2. **Identify Shared vs Platform-Specific Configuration:**
   - Shared: User identity (cameron/crs58), SSH keys, nix settings, caches, development tooling
   - Platform-specific darwin: Homebrew, GUI apps, macOS system defaults, touchID
   - Platform-specific nixos: Boot/disk config, systemd services, server-specific tools

3. **Configure cinnabar with Shared User Configuration:**
   - Add cameron user to cinnabar (username: crs58 or cameron per platform convention)
   - Configure SSH authorized keys for cameron
   - Set user shell (zsh), home directory, admin privileges
   - Integrate portable home-manager module: `flake.modules.homeManager."users/crs58"`
   - Validate: SSH login as cameron works, home-manager builds for nixos

4. **Document Migration Pattern:**
   - Shared vs platform-specific configuration guidelines
   - Migration checklist for reproducibility
   - Pattern for applying user config across darwin/nixos

**B. Apply Dendritic Pattern Refinements:**

1. **File Length Compliance:**
   - Audit all modules for files >200 lines
   - Modularize if justified (extract reusable components)
   - Document any exceptions (with rationale)

2. **Pattern Compliance:**
   - ALL files in modules/ directories are proper flake-parts modules
   - Use `_` prefix ONLY for non-module data files (JSON, YAML, shell scripts)
   - Never use `_` prefix as shortcut for long flake-parts modules

3. **Module Organization:**
   - Clear separation: base modules, host-specific modules, user modules
   - Consistent namespace usage: `flake.modules.{darwin|nixos|homeManager}.*`
   - Reference gaetanlepage patterns for structure and composition

4. **Validation:**
   - All configurations build: `nix build .#darwinConfigurations.blackphos.system`
   - All nixosConfigurations build: `nix build .#nixosConfigurations.{cinnabar,electrum}.config.system.build.toplevel`
   - All homeConfigurations build successfully

**C. Clan-Core Integration Validation:**

1. **Verify Compatibility Maintained:**
   - `clan-core.inventory` structure unchanged (machine definitions, service instances)
   - Service instance registration via `clan-core.services.*` unchanged
   - `clan-core.vars.*` and `clan-core.secrets.*` access patterns unchanged
   - Zerotier network configuration interface unchanged

2. **Validate Configurations:**
   - All clan machines build successfully
   - Zerotier network operational (cinnabar controller, electrum peer)
   - Clan inventory evaluates correctly

**D. Test Coverage:**

1. **Migration Validation:**
   - blackphos package diff: zero regression validated
   - cinnabar user login test: SSH as cameron works
   - Home-manager builds for both platforms (darwin + nixos)

2. **Pattern Compliance:**
   - All 14 regression tests from Story 1.9 continue passing
   - File length compliance verified
   - Module namespace consistency validated

3. **Integration Tests:**
   - Configurations build across all outputs
   - Clan inventory evaluates without errors

**E. Documentation:**

1. **Migration Documentation:**
   - Shared vs platform-specific configuration pattern
   - blackphos migration checklist
   - cinnabar user configuration guide

2. **Dendritic Pattern Guidelines:**
   - File organization standards
   - Module composition patterns
   - Namespace hygiene rules
   - Reference to gaetanlepage exemplar patterns

**Prerequisites:** Story 1.9 (VMs renamed cinnabar/electrum, zerotier network established)

**Blocks:** Story 1.11 (type-safe home-manager architecture), Story 1.12 (blackphos deployment)

**Estimated Effort:** 8-11 hours
- 5-8 hours: Complete blackphos migration + cinnabar user configuration
- 4-6 hours: Apply dendritic pattern refinements
- Test coverage and validation included in above
- 1 hour: Documentation

**Risk Level:** Low (migration and refinement only, no physical deployment, test harness provides safety net)

**Strategic Value:**
- Unblocks Story 1.12 (blackphos deployment) with complete, clean configuration
- Establishes shared configuration pattern for Epic 2-6 (4 more machines)
- Provides clean foundation for Story 1.11 (type-safe home-manager architecture)
- Validates cross-platform user configuration sharing (darwin ↔ nixos)
- Proves dendritic pattern refinement approach before production infra migration

**Note:** This story completes migrations and establishes clean foundation. Story 1.10A validates clan inventory pattern. Story 1.11 implements type-safe home-manager architecture on this foundation.

---

## Story 1.10A: Migrate User Management to Clan Inventory Pattern

**⚠️ DISCOVERED STORY - Architectural Validation Enhancement**

As a system administrator,
I want to refactor cinnabar user configuration from direct NixOS to clan inventory users service with vars-based password management,
So that I validate the clan-core recommended pattern before Epic 2-6 scaling and establish the fleet-wide user management architecture.

**Context:**
- Story 1.10 COMPLETE: cameron user exists on cinnabar via direct NixOS configuration (users.users.cameron)
- Party-mode architectural review (2025-11-14) revealed clan-core provides official inventory users service pattern
- Investigation findings show clan inventory + vars provides 5-10x productivity improvement for multi-machine/multi-user deployments
- Current direct NixOS pattern works but doesn't scale optimally for Epic 2-6 (6 machines × 4+ users)
- Test-clan's purpose is to validate clan-core patterns before infra migration

**Architectural Investigation Findings:**

1. **Clan-Core Provides Official Users Service:**
   - `clanServices/users/` implements declarative user management
   - Automatic password generation via vars system (xkcdpass)
   - `share = true` enables identical passwords across machines
   - `extraModules` pattern integrates home-manager

2. **Proven Developer Patterns:**
   - pinpox-clan-nixos: 8 machines × 3 users via 2 inventory declarations
   - mic92-clan-dotfiles: 9 machines, 128 secrets managed declaratively
   - qubasa-clan-infra: Complex multi-file generators (nextcloud, vaultwarden)

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

**Acceptance Criteria:**

**A. Inventory User Instances Definition:**
1. Create `modules/clan/inventory/services/users.nix`:
   - Define `user-cameron` inventory instance
   - Module: `{ name = "users"; input = "clan-core"; }`
   - Role targeting: `roles.default.tags.all = { };` (all machines)
   - Settings: `user = "cameron"`, `groups = ["wheel" "networkmanager"]`, `share = true`, `prompt = false`
   - extraModules: Reference user overlay file

2. User overlay created in `modules/clan/inventory/services/users/cameron.nix`:
   - Shell preference (users.users.cameron.shell = pkgs.zsh)
   - Home-manager integration via extraModules pattern
   - Platform-specific configuration not handled by users service

**B. Direct NixOS Configuration Removal:**
1. Remove `users.users.cameron` from `modules/machines/nixos/cinnabar/default.nix`
2. Remove home-manager.users.cameron from machine config (now in overlay)
3. Verify no duplicate user definitions remain

**C. Vars System Validation:**
1. Vars generated: `clan vars generate cinnabar` (or automatic during deployment)
2. User password vars created in `vars/shared/user-password-cameron/`:
   - `user-password/secret` (encrypted password)
   - `user-password-hash/secret` (encrypted hash for NixOS)
3. SOPS encryption validated: `file vars/shared/user-password-cameron/user-password/secret` shows JSON data
4. Deployment test: `/run/secrets/vars/user-password-cameron/user-password-hash` exists on cinnabar

**D. Functional Validation:**
1. SSH login works: `ssh cameron@cinnabar` (via zerotier or public IP)
2. Home-manager activated: `ssh cameron@cinnabar "echo \$SHELL"` shows zsh
3. Sudo access works: cameron in wheel group, passwordless sudo configured
4. User identity preserved: git config, SSH keys, development environment intact

**E. Test Coverage:**
1. All 14 existing regression tests from Story 1.9/1.10 continue passing
2. New vars validation tests (TC-024):
   - Vars list test: `clan vars list cinnabar | grep user-password-cameron`
   - SOPS encryption test: Verify secret files are encrypted JSON
   - Deployment test: Verify /run/secrets populated correctly
   - Home-manager integration test: Verify shell, configs activated

**F. Documentation:**
1. Architecture decision documented in `docs/notes/architecture/user-management.md`:
   - Inventory users service pattern (how it works)
   - Vars system for password management (automatic generation, encryption)
   - Party-mode investigation findings summary
   - Rationale for inventory adoption (scalability for Epic 2-6)

2. Operational guide in `docs/guides/adding-users.md`:
   - How to add new user to inventory (define instance, create overlay)
   - How to generate vars for new machines
   - How to deploy user configuration
   - Examples for Epic 2-6 (argentum, rosegold, stibnite)

**Prerequisites:** Story 1.10 (cameron user exists via direct NixOS, working baseline established)

**Blocks:** None (Story 1.11 can proceed, but benefits from this foundation)

**Estimated Effort:** 3-4 hours
- 1 hour: Create inventory instances and user overlay files
- 1 hour: Remove direct NixOS config, validate builds
- 1 hour: Generate vars, test deployment, validate SSH/home-manager
- 0.5 hour: Update test harness with vars validation tests
- 0.5 hour: Documentation (architecture decision, operational guide)

**Risk Level:** Low (refactoring only, Story 1.10 baseline working, test harness provides safety net)

**Strategic Value:**
- Validates clan-core inventory pattern before Epic 2-6 (4 more machines)
- Establishes fleet-wide user management architecture (6 machines × 4+ users)
- Proves vars system scalability for password management
- Demonstrates dendritic + inventory compatibility (test-clan mission)
- Saves 6-12 hours in Epic 2-6 deployment time
- Provides concrete example for infra migration (Epic 2+ reference)

**Party-Mode Investigation Evidence:**
- Clan-core docs investigation: Official users service architecture
- clan-infra pattern analysis: Direct NixOS (pragmatic) vs inventory (recommended)
- Developer repos analysis: Proven inventory patterns at scale
- Vars vs sops-nix comparison: 5-10x productivity improvement
- Dendritic compatibility validation: Full compatibility confirmed

**Note:** This story discovered during Story 1.10 party-mode review (2025-11-14). Separates architectural pattern validation from user creation baseline. Story 1.10 establishes "user works", Story 1.10A validates "clan inventory pattern works".

---

## Story 1.10B: Migrate Home-Manager Module Ecosystem from infra to test-clan

**⚠️ DISCOVERED STORY - Configuration Completeness Gap**

As a system administrator,
I want to migrate the remaining 51 home-manager modules from infra to test-clan,
So that blackphos configuration is complete and ready for physical deployment validation.

**Context:**
Comprehensive investigation (2025-11-14) revealed Story 1.10 audit was incomplete:
- Claimed "no additional packages/services needed" but only compared top-level darwin configs
- Missed 51 home-manager modules (2,500+ lines) auto-wired via nixos-unified
- Current coverage: ~15% (basic git/gh/zsh only)
- Missing: Development environment (neovim, wezterm, editors), AI tooling (claude-code, 11 MCP servers), shell environment (atuin, yazi, zellij), utilities (bat, gpg, awscli, k9s, rbw)
- Physical deployment risk: Severe productivity regression

**Investigation Findings:**
infra uses nixos-unified auto-wiring (`self.homeModules.default` aggregates all 51 modules), test-clan uses dendritic explicit imports.
Story 1.10 audit compared surface configs, missed deep module composition.

**Module Categories (Priority-Based Migration):**

**Priority 1: Critical Development Environment (MUST HAVE)**
- git.nix - Git with SSH signing, delta diff, lazygit, allowed_signers
- jujutsu.nix - Modern VCS with SSH signing, git colocate mode
- neovim/ - LazyVim editor framework
- wezterm/ - Terminal emulator with GPU acceleration
- zed/ - Zed editor configuration
- starship.nix - Enhanced prompt (basic already migrated, enhance)
- zsh.nix - Enhanced shell (basic already migrated, enhance)

**Priority 2: AI-Assisted Development (HIGH VALUE)**
- claude-code/default.nix - Claude Code CLI configuration
- claude-code/mcp-servers.nix - 11 MCP server configs (firecrawl, huggingface, chrome, cloudflare, duckdb, historian, mcp-prompt-server, nixos, playwright, terraform, gcloud, gcs)
- claude-code-wrappers.nix - GLM alternative LLM backend
- claude-code/ccstatusline-settings.nix - Status line configuration

**Priority 3: Shell & Terminal Environment (HIGH VALUE)**
- atuin.nix - Shell history with sync
- yazi.nix - Terminal file manager
- zellij.nix - Terminal multiplexer
- tmux.nix - Alternative multiplexer
- bash.nix - Bash shell setup
- nushell/ - Modern structured shell

**Priority 4: Development Tools (MEDIUM VALUE)**
- radicle.nix - Decentralized code collaboration
- commands/ - 6 command helper modules (dev-tools, nix-tools, git-tools, system-tools, file-tools, descriptions)
- bat.nix - Syntax highlighting cat replacement
- bottom.nix - System monitor
- gpg.nix - GPG/PGP encryption
- pandoc.nix - Document conversion

**Priority 5: Platform Tools (MEDIUM VALUE)**
- awscli.nix - AWS CLI tools
- k9s.nix - Kubernetes TUI
- rbw.nix - Bitwarden CLI password manager
- texlive.nix - LaTeX environment

**Priority 6: Core System & Utilities (LOW VALUE)**
- profile.nix, xdg.nix, bitwarden.nix, tealdeer.nix, macchina.nix, nixpkgs.nix, agents-md.nix

**Acceptance Criteria:**

**A. Priority 1-3 Module Migration (Critical Path):**
1. All Priority 1 modules migrated following dendritic pattern (explicit namespace exports)
2. All Priority 2 modules migrated (AI tooling ecosystem)
3. All Priority 3 modules migrated (shell/terminal environment)
4. Each module exported to `flake.modules.homeManager.*` namespace
5. User modules (crs58, raquel) import migrated modules explicitly
6. Build validation: `nix build .#homeConfigurations.crs58.activationPackage` succeeds

**B. Module Access Pattern Updates:**
1. Update git.nix to reference clan vars for signing keys (coordinate with Story 1.10C)
2. Update jujutsu.nix to reference clan vars for signing keys
3. Update mcp-servers.nix to reference clan vars for API keys (coordinate with Story 1.10C)
4. Update claude-code-wrappers.nix to reference clan vars for GLM API key
5. All sops-nix references replaced with clan vars equivalents

**C. Dendritic Pattern Compliance:**
1. All modules use explicit imports (`config.flake.modules.homeManager.*`)
2. No auto-aggregation patterns (infra's `self.homeModules.default` not replicated)
3. Module organization: `modules/home/users/crs58/` contains user-specific imports
4. Tool modules: `modules/home/tools/` contains reusable tool configs
5. Development modules: `modules/home/development/` contains dev environment configs

**D. Build Validation:**
1. All homeConfigurations build: `nix build .#homeConfigurations.{crs58,raquel}.activationPackage`
2. All darwinConfigurations build: `nix build .#darwinConfigurations.blackphos.system`
3. Zero evaluation errors
4. Configuration coverage: ~15% → ~100% (all critical functionality migrated)

**E. Zero-Regression Validation:**
1. Package diff comparison: infra blackphos vs test-clan blackphos
2. Target: <10% package delta (mostly clan vars additions)
3. Document any regressions and justification for differences
4. Validate all Priority 1-3 functionality present

**F. Documentation:**
1. Migration checklist documented (Priority 1-3 completion)
2. Dendritic pattern notes (explicit imports, no auto-aggregation)
3. Module organization documented (users/, tools/, development/ structure)
4. Learnings captured for Party Mode checkpoint discussion

**Prerequisites:** Story 1.10A (clan inventory pattern migration complete)

**Blocks:** Story 1.10C (secrets migration needs home modules migrated first for access pattern updates), Story 1.12 (physical deployment needs complete config)

**Estimated Effort:** 12-16 hours
- Priority 1 migration: 6-8 hours
- Priority 2 migration: 3-4 hours
- Priority 3 migration: 2-3 hours
- Build validation + documentation: 1-2 hours

**Risk Level:** Medium (extensive refactoring, but proven patterns from infra, clear migration path)

**Strategic Value:**
- Completes blackphos configuration migration (15% → 100% coverage)
- Validates dendritic pattern at scale (51 modules, not just 2-3)
- Unblocks Story 1.12 physical deployment (complete config required)
- Provides empirical data for Party Mode checkpoint (Story 1.11 assessment)
- Establishes home-manager migration pattern for Epic 2-6 (4 more machines)

**Investigation Reference:** Comprehensive blackphos audit (2025-11-14) identified 51 modules across 6 categories, current coverage ~15%, deployment risk HIGH without migration.

---

## Story 1.10C: Migrate Secrets from sops-nix to Clan Vars

**⚠️ DISCOVERED STORY - Secrets Management Gap**

As a system administrator,
I want to migrate sops-nix secrets to clan vars system following Pattern B (vars in user modules),
So that blackphos uses clan-core's recommended secrets pattern and enables scalable multi-machine secret management.

**Context:**
Investigation (2025-11-14) revealed:
- Story 1.8 AC4 deferred secrets migration ("Future work: Migrate to clan vars")
- Story 1.10 never addressed secrets (0% secrets coverage)
- infra has 6 sops-nix encrypted files (signing keys, API keys)
- No clan vars generators defined in test-clan
- Physical deployment would fail (no SSH signing keys, no MCP API keys)

**Clan Vars Architecture Understanding:**
- Clan vars IS sops-nix (with declarative interface)
- `clan.core.vars.generators` wraps sops-nix encryption
- macOS explicitly supported (darwin-compatible)
- Pattern B (vars in user modules) aligns with dendritic philosophy

**Reference Implementations:**
- mic92-clan-dotfiles: Uses raw sops-nix (128 secrets, 9 machines) - legacy pattern
- clan-core docs: Recommends vars over raw sops-nix
- Pattern B: Vars generators defined in user modules, reusable across machines

**Secrets Inventory (from infra):**

| Secret File | Usage | Type | Migration Strategy |
|------------|-------|------|-------------------|
| `admin-user/signing-key.yaml` | Git/jujutsu SSH signing | SSH private key | **Generate new** (ssh-keygen generator) |
| `admin-user/llm-api-keys.yaml` (glm) | GLM alternative LLM backend | API token | **Import existing** (prompt for value) |
| `admin-user/mcp-api-keys.yaml` (firecrawl, context7, huggingface) | 3 MCP server API keys | API tokens | **Import existing** (prompts) |
| `shared.yaml` (BITWARDEN_EMAIL) | Bitwarden password manager | Email address | **Prompt** (user input) |
| `raquel-user/*` | raquel's signing keys, API keys | Same as admin-user | **Same strategies** |

**Acceptance Criteria:**

**A. Clan Vars Setup:**
1. Clan admin keypair generated: `clan secrets key generate`
2. Cameron user added to clan secrets: `clan secrets users add cameron --age-key <public-key>`
3. Age keys configured for encryption/decryption
4. Vars directory structure created: `vars/shared/`, `vars/machines/`

**B. Vars Generators Defined (Pattern B - in user modules):**
1. Create `modules/home/users/crs58/vars.nix` with generators:
   - `ssh-signing-key`: SSH key generator (regenerable via ssh-keygen)
   - `llm-api-keys`: Prompt-based generator (GLM API key)
   - `mcp-api-keys`: Multi-prompt generator (firecrawl, context7, huggingface)
   - `bitwarden-config`: Prompt for email
2. Create `modules/home/users/raquel/vars.nix` with equivalent generators
3. Generators export to `flake.modules.homeManager."users/*/vars"` namespace
4. User modules import vars modules via `config.flake.modules.homeManager.*`

**C. Module Access Pattern Updates:**
1. `modules/home/users/crs58/git.nix`: Update signing key access
   - Before: `config.sops.secrets."admin-user/signing-key".path`
   - After: `config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path`
2. `modules/home/users/crs58/jujutsu.nix`: Update signing key access (same as git)
3. `modules/home/users/crs58/mcp-servers.nix`: Update API key access
   - Before: `config.sops.secrets."mcp-firecrawl-api-key".path`
   - After: `config.clan.core.vars.generators.mcp-api-keys.files.firecrawl.path`
4. `modules/home/users/crs58/claude-code-wrappers.nix`: Update GLM API key access
5. `modules/home/users/crs58/rbw.nix`: Update Bitwarden email access
6. Same updates for raquel's modules

**D. Vars Generation and Validation:**
1. Generate vars: `clan vars generate blackphos` (prompts for imported secrets)
2. Verify encryption: `file vars/shared/ssh-signing-key/ed25519_priv/secret` shows JSON (sops-encrypted)
3. Build validation: `nix build .#darwinConfigurations.blackphos.system` succeeds
4. Secrets accessible in build: Verify `/run/secrets/vars/*` paths resolve
5. SSH signing validated: `git log --show-signature` shows verified commits in build

**E. GitHub Signing Key Update (Post-Deployment):**
1. Document new SSH signing public key location
2. Instructions for adding to GitHub settings (Settings → SSH and GPG keys → Signing keys)
3. Verify commits signed with new key after deployment

**F. Dendritic + Clan Vars Integration Validation:**
1. Vars generators work with dendritic namespace pattern
2. No conflicts between dendritic imports and clan vars access
3. Pattern B (vars in user modules) enables reuse: crs58 vars work on blackphos (darwin) and cinnabar (nixos)
4. Import-tree discovers vars modules correctly

**G. Documentation:**
1. Secrets migration guide: sops-nix → clan vars conversion
2. Pattern B documentation: Vars in user modules, dendritic integration
3. Operational guide: How to add new secrets, regenerate vars, update GitHub keys
4. Access pattern examples: Before/after comparisons

**Prerequisites:** Story 1.10B (home-manager modules migrated, access patterns ready for update)

**Blocks:** Story 1.12 (physical deployment needs functional secrets for SSH signing, API access)

**Estimated Effort:** 4-6 hours
- Clan vars setup + generators: 2 hours
- Module access pattern updates: 1-2 hours
- Vars generation + validation: 1 hour
- Documentation: 1 hour

**Risk Level:** Medium-High (encryption concerns, new pattern, must preserve API keys)

**Risk Mitigation:**
- Backup `~/.config/sops/age/keys.txt` before migration
- Test vars generation in separate branch first
- Validate encryption before committing to git
- Keep infra sops-nix secrets accessible for rollback

**Strategic Value:**
- Adopts clan-core recommended pattern (vars over raw sops-nix)
- Validates Pattern B at scale (multiple secret types, multiple users)
- Enables Epic 2-6 scalability (vars shared across 6 machines)
- Proves dendritic + clan vars compatibility
- Provides empirical data for Party Mode checkpoint (secrets at scale)

**Investigation Reference:** Comprehensive secrets audit (2025-11-14) identified 6 sops-nix files, 0% clan vars coverage, Pattern B recommended for dendritic compatibility.

---

## Party Mode Checkpoint: Story 1.11 Evidence-Based Assessment

**⚠️ ADAPTIVE DECISION POINT**

After completing Stories 1.10B (51 home-manager modules) and 1.10C (secrets migration), reconvene Party Mode team to make evidence-based decision about Story 1.11 (Type-Safe Home-Manager Architecture) execution.

**Rationale:**
Story 1.11 proposes specific architectural pattern (homeHosts with type safety, smart resolution, machine-specific configs).
This pattern was designed before implementing dendritic + clan synthesis at scale (51 modules + clan vars).
After real implementation, we'll have empirical evidence to assess whether Story 1.11:
- Improves established patterns (GO)
- Needs adjustment to fit actual patterns (MODIFY)
- Adds unnecessary complexity (SKIP)

**Assessment Framework:**

**Evidence to Collect from Stories 1.10B + 1.10C:**
1. **Type safety value:** Count typos/errors encountered during migration that homeHosts types would catch
2. **Machine-specific configs:** Assess whether crs58@blackphos needs different home config than crs58@cinnabar
3. **Pattern quality:** Evaluate whether dendritic + clan synthesis feels elegant or clunky
4. **CI check value:** Determine if activation script validation would have caught issues
5. **Smart resolution:** Assess whether auto-detection adds value or explicit names sufficient

**Story 1.11 Decision Criteria:**

**GO (Execute Story 1.11 as planned):**
- ✅ Encountered typos/errors that homeHosts type validation would catch
- ✅ Need machine-specific home configs (blackphos ≠ cinnabar user configs)
- ✅ homeHosts pattern clearly improves on current dendritic approach
- ✅ CI activation checks would have caught real issues from 1.10B/1.10C
- ✅ Story 1.11 aligns with dendritic + clan philosophy (no conflicts)

**MODIFY (Adjust Story 1.11 scope):**
- 🔶 Some elements valuable (e.g., CI checks) but not full homeHosts pattern
- 🔶 Need lighter-weight type safety (not full submodule types)
- 🔶 Smart resolution valuable but machine-specific configs unnecessary
- 🔶 Story 1.11 has valuable goals but approach needs adaptation

**SKIP (Proceed directly to Story 1.12):**
- ❌ No significant typos/errors (nix eval catches everything needed)
- ❌ Generic user configs work everywhere (no machine-specific overrides needed)
- ❌ Current dendritic + clan pattern elegant and maintainable
- ❌ Story 1.11 adds complexity without clear benefit
- ❌ homeHosts conflicts with established dendritic patterns

**Party Mode Agenda:**
1. Review Stories 1.10B + 1.10C implementation learnings (what worked, what didn't)
2. Assess dendritic + clan synthesis patterns that emerged
3. Evaluate Story 1.11 value proposition against actual implementation evidence
4. Discuss alternative approaches if MODIFY decision (lighter-weight solutions)
5. Make decision: GO / MODIFY / SKIP with explicit rationale
6. If GO or MODIFY: Update Story 1.11 scope and acceptance criteria accordingly
7. Update Story 1.12 dependencies based on decision

**Documentation Requirement:**
Party Mode session outcome documented in Story 1.13 (integration findings) with:
- Evidence collected from Stories 1.10B + 1.10C
- Decision rationale (GO/MODIFY/SKIP)
- If MODIFY: Adjusted Story 1.11 scope
- If SKIP: Explanation of why dendritic + clan synthesis is sufficient

**Strategic Value:**
- Evidence-based decision-making (not theoretical speculation)
- Prevents premature optimization (implements only what's proven valuable)
- Validates architectural patterns empirically (real code, real issues)
- Aligns with Epic 1 goal: Validate patterns, don't over-engineer

---

## Story 1.11: Implement Type-Safe Home-Manager Architecture **[CONDITIONAL - Pending Party Mode Checkpoint]**

As a system administrator,
I want to implement type-safe home-manager architecture with smart resolution and machine-specific configurations,
So that I have a production-ready, maintainable home-manager pattern for the entire fleet (Epic 2-6) with compile-time validation and intelligent deployment.

**Context:**
- Story 1.10 completed migrations and established clean foundation (user modules finalized, clean codebase)
- Story 1.10B migrated 51 home-manager modules using dendritic pattern
- Story 1.10C migrated secrets to clan vars using Pattern B
- **Party Mode Checkpoint after 1.10B/1.10C:** Evidence-based decision on Story 1.11 execution
- Current home-manager uses static generator (`configurations.nix`) - no type safety, no machine-specific configs
- Need gaetanlepage-level type safety with mic92-style clan integration for production fleet (6 machines)
- Must support three integration modes: darwin-integrated, nixos-integrated, standalone homeConfigurations
- **NOTE:** This story is CONDITIONAL on Party Mode checkpoint GO decision

**Architectural Reference:**
- `docs/notes/development/home-manager-type-safe-architecture.md` - complete design and migration phases
- `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/flake/hosts.nix` - exemplar homeHosts pattern
- `~/projects/nix-workspace/mic92-clan-dotfiles/home-manager/` - clan integration + CI checks pattern

**Acceptance Criteria:**

**A. Phase 1 - Type-Safe Layer (Non-Breaking):**

1. **Create Type-Safe Options:**
   - `modules/flake/home-hosts.nix` created with homeHosts option definition
   - Submodule types: user, system, machine (optional), unstable, modules, pkgs (computed)
   - Machine reference validation: asserts machine exists in clan.inventory if specified
   - System auto-inheritance from machine if machine reference provided

2. **Create Core Base Module:**
   - `modules/home/core/default.nix` provides base home-manager config
   - Exports to `flake.modules.homeManager.core` namespace
   - Sets home.stateVersion, home.homeDirectory (platform-aware), programs.home-manager.enable

3. **Create Generic Configurations:**
   - `modules/home/generic-configs.nix` with system-generic homeHosts declarations
   - Declares: crs58-x86_64-linux, crs58-aarch64-darwin, raquel-aarch64-darwin
   - No machine references (portable for standalone usage)

4. **Parallel Operation:**
   - Keep existing `modules/home/configurations.nix` (non-breaking)
   - Both old and new systems generate homeConfigurations simultaneously

5. **Validation:**
   - Declare one homeHost, verify homeConfiguration generated correctly
   - Type checks pass: `nix flake check`
   - Test homeConfiguration builds successfully

**B. Phase 2 - Smart Resolution App:**

1. **Enhance app.nix:**
   - Implement smart resolution logic: tries machine-specific (user-hostname) → generic (user-system) fallback
   - Use `nix flake show --json` for fast metadata query (checks available configs without building)
   - Clear error messages showing what was tried, what's available

2. **Update Help Text:**
   - Document smart resolution strategy
   - Examples: auto-detection, explicit config name, different user
   - Show current context (user, host, system)

3. **Validation:**
   - App works with generic configs (backward compatibility tested)
   - Machine-specific config preferred when both exist
   - Fallback to generic works gracefully
   - Error messages clear and actionable

**C. Phase 3 - Migrate to Typed Declarations:**

1. **Restructure User Modules:**
   - `modules/home/users/crs58/default.nix` exports to `flake.modules.homeManager.user-crs58`
   - `modules/home/users/raquel/default.nix` exports to `flake.modules.homeManager.user-raquel`
   - User modules contain only cross-platform user identity config

2. **Create Machine-Specific Home Configs:**
   - `modules/machines/darwin/blackphos/home/crs58.nix` - declares homeHosts.crs58-blackphos
   - `modules/machines/darwin/blackphos/home/raquel.nix` - declares homeHosts.raquel-blackphos
   - `modules/machines/nixos/cinnabar/home/crs58.nix` - declares homeHosts.crs58-cinnabar
   - Optional: electrum, other machines as needed

3. **homeHosts Declarations:**
   - crs58-cinnabar: user = "crs58", machine = "cinnabar", modules = [machine-specific overrides]
   - crs58-blackphos: user = "crs58", machine = "blackphos", modules = [admin config]
   - raquel-blackphos: user = "raquel", machine = "blackphos", modules = [primary user config]

4. **Validation:**
   - `nix flake check` passes all type checks
   - App resolution chain works: auto-detects hostname, falls back gracefully
   - All homeConfigurations build successfully

**D. Phase 4 - Remove Legacy Generator:**

1. **Delete Legacy:**
   - Remove `modules/home/configurations.nix` (replaced by homeHosts)
   - Verify no references remain in codebase

2. **Update Documentation:**
   - README.md updated with smart resolution examples
   - Migration guide for adding new users/machines
   - All usage examples verified working

3. **Validation:**
   - All homeConfigurations still available (via homeHosts)
   - App continues working (uses new typed system)
   - Zero regressions in functionality

**E. Phase 5 - Advanced Features:**

1. **CI Checks (following mic92 pattern):**
   - Add checks for homeConfiguration activation scripts
   - Validates configs build and activate without runtime testing
   - Integrated into `modules/checks/validation.nix`

2. **Optional Profile Modules:**
   - Create `flake.modules.homeManager.profile-desktop` if valuable
   - Create `flake.modules.homeManager.profile-server` if valuable
   - Enable composition: user module + profile module + machine overrides

3. **Optional Tag-Based Conditional Application:**
   - If useful, enable conditional module application based on clan machine tags
   - Example: desktop tag → auto-apply desktop profile

**F. Test Coverage:**

1. **Type Validation (TC-020):**
   - Typo in username → compile error (undefined user-* module)
   - Invalid machine reference → assertion failure with clear message
   - Missing required options → evaluation error

2. **Smart Resolution Logic (TC-021):**
   - Machine-specific preferred when available
   - System-generic fallback works correctly
   - Error messages clear when no match found
   - Shows tried candidates and available options

3. **Build Validation (TC-022):**
   - All homeConfigurations build successfully
   - Generic configs work (crs58-x86_64-linux, etc.)
   - Machine-specific configs work (crs58-cinnabar, crs58-blackphos, raquel-blackphos)

4. **Activation Scripts (TC-023):**
   - CI checks pass for all homeConfigurations
   - Activation scripts valid (mic92 pattern)

5. **Regression:**
   - All 14 existing tests from Story 1.9/1.10 continue passing
   - Zero regressions in functionality

**G. Documentation:**

1. **Architecture Documentation:**
   - Type-safe home-manager rationale (why homeHosts pattern)
   - gaetanlepage influence (type safety) + mic92 influence (clan integration)
   - Benefits for fleet management (6 machines)

2. **Migration Guide:**
   - How to add new user (create user module, declare homeHosts)
   - How to add new machine (create machine-specific home config)
   - How to add profile modules (shared configurations)

3. **Usage Examples:**
   - Auto-detection workflow: `nix run .`
   - Explicit config: `nix run . -- crs58-cinnabar`
   - Different user: `nix run . -- raquel`
   - Development workflow: `nix run . -- crs58 . --dry`

**Prerequisites:**
- Story 1.10B (home-manager modules migrated - provides empirical evidence)
- Story 1.10C (secrets migrated - completes configuration)
- Party Mode Checkpoint (GO decision required to execute this story)

**Blocks:** None (Story 1.12 blackphos deployment can proceed without this, but benefits from it)

**Conditional Execution:**
This story executes ONLY if Party Mode checkpoint (after Stories 1.10B + 1.10C) determines:
- Story 1.11 provides clear value over established dendritic + clan patterns
- homeHosts architecture aligns with (not conflicts with) proven patterns
- Type safety, smart resolution, or CI checks address real issues encountered

If checkpoint determines SKIP, proceed directly to Story 1.12 with current home-manager pattern.
If checkpoint determines MODIFY, adjust scope/approach based on empirical evidence.

**Estimated Effort:** 10-16 hours
- Phase 1: Type-safe layer (3 hours)
- Phase 2: Smart resolution app (2 hours)
- Phase 3: Migrate to typed declarations (5 hours)
- Phase 4: Remove legacy generator (1 hour)
- Phase 5: Advanced features (2-3 hours)
- Test coverage: 2-3 hours (distributed across phases)
- Documentation: 2-3 hours

**Risk Level:** Low-Medium (refactoring home-manager architecture, but test harness + phase 1 parallel operation provides safety net)

**Strategic Value:**
- Establishes production-ready type-safe home-manager pattern for Epic 2-6 (all 6 machines)
- Compile-time validation prevents typos and configuration errors
- Smart resolution improves deployment UX across entire fleet
- Machine-specific configs enable per-machine customization without duplication
- gaetanlepage-level type safety with mic92-style clan integration
- Sets pattern quality baseline for production infra refactoring

**Note:** Phases 1-2 are non-breaking (parallel operation). Phase 3 migrates to typed system. Phase 4 removes legacy. Phase 5 adds advanced features.

---

## Story 1.12: Deploy blackphos and Integrate into Zerotier Network

As a system administrator,
I want to deploy the fully-migrated, well-architected blackphos configuration to physical hardware and integrate into the test-clan zerotier network,
So that I validate heterogeneous networking (nixos ↔ nix-darwin), prove multi-platform coordination, and complete Epic 1 architectural validation.

**Context:**
- Story 1.10B completed home-manager migration (51 modules, complete dev environment)
- Story 1.10C completed secrets migration (clan vars functional)
- Story 1.11 MAY have implemented type-safe architecture (if Party Mode checkpoint GO)
- Configuration is now complete, secrets functional, ready for physical deployment
- This story is streamlined deployment + integration test (no refactoring, minimal rework)

**Acceptance Criteria:**

**A. Blackphos Deployment to Physical Hardware:**
1. Configuration deployed to actual blackphos laptop: `darwin-rebuild switch --flake .#blackphos`
2. Deployment succeeds without errors
3. All existing functionality validated post-deployment
4. Zero-regression validation: All blackphos daily workflows functional, development environment intact, no performance degradation

**B. Zerotier Peer Configuration:**
1. Zerotier service configured on blackphos (investigate nix-darwin zerotier module or homebrew workaround)
2. Blackphos joins zerotier network as peer (cinnabar remains controller)
3. Zerotier configuration uses nix-native approach where possible
4. If nix-darwin zerotier module unavailable, document approach used (homebrew, custom module, etc.)
5. Note any platform-specific issues encountered

**C. Heterogeneous Network Validation:**
1. 3-machine zerotier network operational (cinnabar + electrum + blackphos)
2. Blackphos can ping both cinnabar and electrum via zerotier IPs
3. Both nixos VMs can ping blackphos via zerotier IP
4. Network latency acceptable for coordination (<50ms typical)

**D. Cross-Platform SSH Validation:**
1. SSH from blackphos to cinnabar/electrum works
2. SSH from cinnabar/electrum to blackphos works
3. Certificate-based authentication functional across platforms
4. Clan-managed SSH keys operational

**E. Clan Vars/Secrets Validation on Darwin:**
1. `/run/secrets/` populated with proper permissions (darwin-compatible)
2. SSH host keys functional
3. User secrets accessible
4. No permission issues on darwin platform

**F. Integration Findings Documentation:**
1. Deployment process documented (commands, sequence, any manual steps)
2. Zerotier darwin integration approach documented (what worked, what didn't)
3. Platform-specific challenges captured (if any)
4. Heterogeneous networking validation results (latency, reliability, any issues)

**Prerequisites:**
- Story 1.10B (home-manager modules migrated - REQUIRED for complete configuration)
- Story 1.10C (secrets migrated - REQUIRED for SSH signing, API keys functional)
- Story 1.11 (type-safe architecture - OPTIONAL, depends on Party Mode checkpoint decision)

**Hard Dependencies:** Stories 1.10B + 1.10C must be complete (full config + secrets)
**Soft Dependency:** Story 1.11 improves deployment quality but not required for validation

**Estimated Effort:** 4-6 hours
- 1-2 hours: Physical deployment and validation
- 2-3 hours: Zerotier darwin integration investigation and configuration
- 1 hour: Network validation and documentation

**Risk Level:** Medium (deploying to real physical machine, zerotier darwin support uncertain)

**Strategic Value:**
- Proves heterogeneous networking (nixos ↔ nix-darwin) works with complete configurations
- Validates multi-platform coordination pattern for production fleet
- Demonstrates dendritic pattern + clan-core works seamlessly across platforms
- Completes Epic 1 architectural validation with real darwin hardware

**Note:** Story 1.10 established complete, well-architected configuration. This story focuses purely on deployment and integration testing. Minimal rework expected.

---

## Story 1.13: Document Integration Findings and Architectural Patterns

As a system administrator,
I want to document all integration findings, architectural patterns, and lessons learned from Epic 1 Phase 0 validation,
So that I have a comprehensive reference and decision framework for production refactoring in Epic 2+.

**Context:**
- Epic 1 validation complete: nixos VMs deployed, dendritic patterns proven, darwin integration validated
- Story 1.10: Migrations complete, dendritic patterns refined, cinnabar user configured
- Story 1.11: Type-safe home-manager architecture implemented (if completed)
- Story 1.12: blackphos deployed, heterogeneous zerotier networking operational
- Now consolidate findings into actionable documentation for production refactoring

**Acceptance Criteria:**

**A. Integration Findings Documentation:**
1. Terraform/terranix + clan integration patterns documented (how it works, gotchas, best practices)
2. Dendritic flake-parts pattern evaluation documented (proven via Stories 1.6-1.7, refined in Story 1.10)
3. Nix-darwin + clan integration patterns documented (learned from Stories 1.8, 1.10, 1.12)
4. Type-safe home-manager architecture documented (implemented Story 1.11 if completed, or future work)
5. Heterogeneous zerotier networking documented (nixos ↔ nix-darwin from Story 1.12)
6. Nixos-unified → dendritic + clan transformation process documented (from Stories 1.8, 1.10)

**B. Architectural Decisions Documentation:**
1. Why dendritic flake-parts + clan combination (rationale, benefits, trade-offs)
2. Why terraform/terranix for infrastructure provisioning (compared to alternatives)
3. Why zerotier mesh (always-on coordination, VPN, compared to tailscale/wireguard)
4. Why type-safe homeHosts pattern (gaetanlepage influence, benefits for fleet management)
5. Clan inventory patterns chosen (machines, services, roles, targeting)
6. Service instance patterns (how roles work, targeting strategies)
7. Secrets management strategy (clan vars vs sops-nix, when to use each)
8. Home-manager integration approach evolution (1.8 → 1.8A → 1.10 journey)

**C. Pattern Confidence Assessment:**
For each pattern, assess confidence level and evidence:
1. **Proven:** Validated in test-clan with zero regressions, ready for production
2. **Needs-testing:** Conceptually sound but requires additional validation
3. **Uncertain:** Potential issues identified, needs investigation or alternative

**D. Production Refactoring Recommendations:**
1. Specific steps to refactor infra from nixos-unified to dendritic + clan
2. Machine migration sequence and approach (which machines first, why)
3. Risk mitigation strategies based on test-clan learnings
4. Type-safe home-manager adoption strategy for production (phased rollout)
5. Testing strategy for production migration (leverage test harness patterns)

**E. Known Limitations and Gaps:**
1. Darwin-specific challenges documented
2. Platform-specific workarounds captured (if any)
3. Areas requiring additional investigation identified
4. Technical debt or pattern violations noted (to address in Epic 2+)

**Prerequisites:** Story 1.12 (blackphos deployed, heterogeneous networking validated)

**Optional Prerequisites:** Story 1.11 (type-safe home-manager architecture - if completed, document it)

**Estimated Effort:** 3-4 hours (documentation consolidation and review)

**Risk Level:** Low (documentation only)

**Strategic Value:**
- Provides comprehensive blueprint for production refactoring based on complete validation
- Captures institutional knowledge from Phase 0 experimentation
- De-risks Epic 2-6 by documenting proven patterns and known limitations
- Enables informed go/no-go decision in Story 1.14

---

## Story 1.14: Execute go/no-go decision framework for production refactoring

As a system administrator,
I want to evaluate Phase 0 results against go/no-go criteria,
So that I can make an informed decision about proceeding to production refactoring in Epic 2+.

**Acceptance Criteria:**
1. Decision framework evaluation documented (go-no-go-decision.md or integrated into existing docs): Infrastructure deployment success (Hetzner VMs operational: PASS/FAIL), Dendritic flake-parts pattern validated (Stories 1.6-1.7: PASS/FAIL), Nix-darwin + clan integration proven (Story 1.8: PASS/FAIL), Heterogeneous networking validated (nixos ↔ darwin zerotier: PASS/FAIL), Transformation pattern documented (nixos-unified → dendritic + clan: PASS/FAIL), Home-manager integration proven (PASS/FAIL), Pattern confidence (reusable for production refactoring: HIGH/MEDIUM/LOW)
2. Blockers identified (if any): Critical: must resolve before production refactoring, Major: can work around but risky, Minor: document and monitor
3. Decision rendered: **GO**: All criteria passed, high confidence, proceed to Epic 2+ production refactoring; **CONDITIONAL GO**: Some issues but manageable, proceed with specific cautions documented; **NO-GO**: Critical blockers, resolve or pivot strategy
4. If GO/CONDITIONAL GO: Production refactoring plan confirmed for Epic 2+, Migration pattern ready to apply to infra repository, Test-clan cinnabar/electrum configurations ready to migrate into infra, Blackphos can be reverted to infra management or kept in test-clan as ongoing validation
5. If NO-GO: Alternative approaches documented, Issues requiring resolution identified, Timeline for retry or pivot strategy, Specific validation gaps that need addressing
6. Next steps clearly defined based on decision outcome

**Context:**
- Epic 1 Phase 0 validation complete (Stories 1.1-1.13)
- Documentation consolidated in Story 1.13
- Ready to assess results against decision criteria

**Prerequisites:** Story 1.13 (integration findings and patterns documented)

**Estimated Effort:** 1-2 hours

**Risk Level:** Low (decision only)

**Decision Criteria - GO if:** Hetzner VMs deployed and operational, Dendritic flake-parts pattern proven with zero regressions (Stories 1.6-1.7, 1.10), Blackphos successfully migrated with complete configuration (Stories 1.8, 1.10, 1.12), cinnabar configured with shared user configuration (Story 1.10), Heterogeneous zerotier network operational (nixos + darwin, Story 1.12), Transformation pattern documented and reusable (Story 1.13), Type-safe home-manager architecture validated (Story 1.11 if completed, or acceptable to defer), High confidence in applying patterns to production

**Decision Criteria - CONDITIONAL GO if:** Minor platform-specific issues discovered but workarounds documented, Some manual steps required but acceptable, Partial automation acceptable with documented procedures, Medium-high confidence in production refactoring

**Decision Criteria - NO-GO if:** Critical failures in darwin integration, Transformation pattern unclear or too complex, Heterogeneous networking unreliable, Patterns not reusable for production, Major gaps in validation coverage

---
