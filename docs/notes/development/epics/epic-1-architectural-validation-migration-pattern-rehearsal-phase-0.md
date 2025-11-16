# Epic 1: Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Goal:** Validate dendritic flake-parts + clan architecture for both nixos VMs and nix-darwin hosts, validate cross-platform user config sharing, and document nixos-unified → dendritic + clan transformation pattern through blackphos migration rehearsal

**Strategic Value:** Validates complete stack (dendritic + clan + terraform + infrastructure) on real VMs and darwin machines before production refactoring, proves both target architecture AND transformation process, validates cross-platform home-manager modularity (Epic 1 architectural requirement), provides reusable migration blueprint for Epic 2+ by rehearsing complete nixos-unified → dendritic + clan conversion

**Timeline:** 4-5 weeks
- Phase 0 (Stories 1.1-1.10A): ✅ COMPLETE (3 weeks actual)
- Phase 1A (Story 1.10B): ✅ COMPLETE (16 hours, Pattern B limitations discovered)
- Phase 1B (Story 1.10BA): 8-10 hours (refactor to Pattern A, restore functionality)
- Phase 1C (Story 1.10C): 4-6 hours (secrets migration with working modules)
- Phase 2 (Party Mode Checkpoint): 1-2 hours (evidence-based Story 1.11 decision based on Pattern A)
- Phase 3 (Story 1.11 conditional): 0-16 hours (depends on checkpoint)
- Phase 4 (Stories 1.12-1.14): 8-12 hours (deployment + validation + GO/NO-GO)
- **Total remaining:** 21-46 hours (1-2 weeks depending on Story 1.11 decision)

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

## Story 1.10BA: Refactor Home-Manager Modules from Pattern B to Pattern A (Drupol Multi-Aggregate)

**✅ STATUS: DONE (2025-11-14) - Structural Pattern A Validated**

**⚠️ SCOPE ADJUSTED:** Feature restoration (original AC17-AC20) moved to Story 1.10D (depends on Story 1.10C clan vars infrastructure)

As a system administrator,
I want to refactor the 17 migrated home-manager modules from Pattern B (underscore directories, plain modules) to Pattern A (drupol multi-aggregate dendritic),
So that the dendritic Pattern A architecture is validated at scale and provides the foundation for secrets migration (Story 1.10C) and feature enablement (Story 1.10D).

**Context:**

Story 1.10B migration (Session 2, 2025-11-14) discovered **CRITICAL ARCHITECTURAL LIMITATIONS** of Pattern B that block 11 features and break darwinConfigurations builds:

**Pattern B Failures (Documented in Story 1.10B Dev Notes lines 767-1031):**
- No flake context access (plain modules signature: `{ config, pkgs, lib }` only - missing `flake` parameter)
- sops-nix DISABLED (requires `flake.config` lookups, incompatible with plain modules)
- Flake inputs DISABLED (nix-ai-tools, lazyvim, catppuccin-nix unreachable)
- darwinConfigurations.blackphos.system **FAILS TO BUILD** (lazyvim integration broken)
- 11 features disabled with Story 1.10C TODOs (SSH signing, MCP API keys, GLM wrapper, ccstatusline, tmux theme)

**Party Mode Investigation (2025-11-14):**
- Both reference implementations use Pattern A (gaetanlepage: single `core` aggregate, drupol: multi-aggregate `base`/`shell`/`desktop`)
- Zero references use Pattern B (underscore workaround is test-clan invention)
- Team unanimous (9/9 agents): Refactor to Pattern A immediately
- Validation experiment recommended (1 hour) to prove Pattern A works in test-clan before full refactoring

**Strategic Rationale:**
- Refactoring cost ~8 hours (same as finishing Pattern B migrations would have been)
- Restores full functionality (11 disabled features re-enabled)
- Aligns with industry-standard pattern (both gaetanlepage and drupol references)
- Unblocks Story 1.10C (secrets need modules with flake context for clan vars)
- Fixes darwinConfigurations build failure (lazyvim accessible via flake.inputs)

**Acceptance Criteria:**

**A. Validation Experiment (Murat's 1-Hour Test):**
1. Convert ONE module (git.nix) to Pattern A (drupol multi-aggregate dendritic)
2. Create `development` aggregate namespace: `flake.modules.homeManager.development`
3. Wrap git.nix in dendritic export: `flake.modules.homeManager.development = { config, pkgs, lib, flake, ... }: { programs.git = { ... }; }`
4. Move `modules/home/_development/git.nix` → `modules/home/development/git.nix` (remove underscore)
5. Import in crs58 user module: `config.flake.modules.homeManager.development`
6. Build validation: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` succeeds
7. If successful: Proceed with full refactoring (AC B-F)
8. If fails: Analyze root cause (infinite recursion, evaluation errors), adjust approach

**B. Aggregate Namespace Organization:**
1. Define aggregate structure for 17 modules (following drupol pattern):
   - `homeManager.development` (7 modules: git, jujutsu, neovim, wezterm, zed, starship, zsh)
   - `homeManager.ai` (4 modules: claude-code, mcp-servers, wrappers, ccstatusline-settings)
   - `homeManager.shell` (6 modules: atuin, yazi, zellij, tmux, bash, nushell)
2. Remove underscore prefixes: `_development/` → `development/`, `_tools/` → `ai/` and `shell/`
3. All modules auto-discovered by import-tree (no underscore prevention needed)
4. Each module merges into aggregate namespace (multiple files → one namespace)

**C. Refactor Existing Modules to Pattern A:**

**Priority 1 modules (7 modules → development aggregate):**
1. Wrap each module in dendritic export wrapper:
   - Before: `{ config, pkgs, lib, ... }: { programs.git = { ... }; }`
   - After: `{ flake.modules.homeManager.development = { config, pkgs, lib, flake, ... }: { programs.git = { ... }; }; }`
2. Move modules: `_development/git.nix` → `development/git.nix` (all 7 modules)
3. Preserve module content (move inside wrapper, no functional changes yet)
4. Verify individual builds after each module refactoring

**Priority 2 modules (4 modules → ai aggregate):**
1. Wrap in `flake.modules.homeManager.ai = { ... }`
2. Move: `_tools/claude-code/*.nix` → `ai/claude-code/*.nix`
3. Restore disabled features (AC E) during refactoring

**Priority 3 modules (6 modules → shell aggregate):**
1. Wrap in `flake.modules.homeManager.shell = { ... }`
2. Move: `_tools/atuin.nix`, `_tools/yazi.nix`, etc. → `shell/`
3. Restore catppuccin-nix tmux integration (flake input now accessible)

**D. Update User Modules to Import Aggregates:**

**crs58 user module** (`modules/home/users/crs58/default.nix`):
1. Change from relative imports to aggregate imports
2. Before (Pattern B):
   ```nix
   imports = [
     ../../_development/git.nix
     ../../_development/jujutsu.nix
     # ... 17 relative paths
   ];
   ```
3. After (Pattern A):
   ```nix
   imports = with config.flake.modules.homeManager; [
     development  # All 7 Priority 1 modules
     ai           # All 4 Priority 2 modules
     shell        # All 6 Priority 3 modules
   ];
   ```

**raquel user module** (`modules/home/users/raquel/default.nix`):
1. Selective aggregate imports (raquel doesn't need ai tools):
   ```nix
   imports = with config.flake.modules.homeManager; [
     development  # git, starship, zsh, neovim
     shell        # atuin, yazi, tmux, bash
   ];
   ```
2. Verify raquel gets appropriate subset (no claude-code)

**E. ~~Restore Disabled Features~~ → DEFERRED TO STORY 1.10D**

**⚠️ SCOPE CHANGE:** Feature restoration moved to Story 1.10D (depends on Story 1.10C clan vars).

**Rationale:** test-clan uses clan vars (not sops-nix). Features can only be enabled AFTER clan vars infrastructure exists (Story 1.10C). Story 1.10BA validates Pattern A structure; Story 1.10D validates features work with clan vars.

**Original AC17-AC20 (feature restoration) replaced with:**
- Story 1.10C: Establish clan vars infrastructure
- Story 1.10D: Enable features using clan vars + flake.inputs patterns

**F. Build Validation:**

**homeConfigurations validation:**
1. `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` SUCCEEDS
2. `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` SUCCEEDS
3. Verify all 17 modules integrated for crs58
4. Verify 7 module subset for raquel (development + shell, no ai)

**darwinConfigurations validation (CRITICAL FIX):**
1. `nix build .#darwinConfigurations.blackphos.system` SUCCEEDS
2. Lazyvim integration functional (flake.inputs.lazyvim accessible)
3. Previous Pattern B failure: "option 'programs.lazyvim' does not exist" RESOLVED

**~~Feature validation~~ → DEFERRED TO STORY 1.10D:**
- Feature enablement depends on clan vars infrastructure (Story 1.10C)
- Story 1.10BA validates structure; Story 1.10D validates features

**G. Zero-Regression Validation:**
1. Compare Pattern B vs Pattern A package lists:
   - homeConfigurations.crs58: all Pattern B packages present + restored features
   - No functionality lost from Pattern B
   - All 11 disabled features restored (or documented if blocked by external factors)
2. darwinConfigurations.blackphos: build succeeds (was failing in Pattern B)
3. Test harness: All existing tests continue passing

**H. Documentation:**

**Refactoring documentation:**
1. Pattern B → Pattern A transformation documented in work item
2. Why Pattern B failed (11 limitations from Story 1.10B dev notes)
3. How Pattern A solves issues (flake context access, aggregate namespaces)
4. Aggregate organization rationale (development, ai, shell following drupol pattern)

**Architecture updates:**
1. Update `docs/notes/architecture/home-manager-architecture.md` with Pattern A as standard
2. Document aggregate namespace pattern (multi-aggregate like drupol, not monolithic like gaetanlepage)
3. Remove Pattern B references (underscore workaround was dead end)

**Story 1.10B lessons learned:**
1. Underscore workaround prevented import-tree discovery but blocked flake context
2. Both reference implementations (gaetanlepage, drupol) use Pattern A for good reason
3. Party Mode architectural review validated empirically (11 failures documented)
4. Evidence-based decision-making prevented wasted effort on Pattern B migrations

**Prerequisites:** Story 1.10B (done-with-limitations - provided empirical evidence of Pattern B architectural failures)

**Blocks:** Story 1.10C (secrets migration needs working modules with flake context for clan vars integration)

**Estimated Effort:** 8-10 hours (Actual: ~4 hours - structural work only)
- Validation experiment (AC A): 1 hour ✅
- Refactor Priority 1-3 modules to Pattern A (AC C): 2-3 hours ✅
- Update user modules (AC D): 30 min ✅
- Build validation + documentation (AC F-H): 30 min ✅

**Risk Level:** Low (validation experiment de-risked, proven pattern from references)

**Strategic Value (ACHIEVED):**
- ✅ Validates Pattern A dendritic structure scales to 17 modules
- ✅ Fixes darwinConfigurations.blackphos.system build failure (lazyvim integration)
- ✅ Aligns with industry-standard pattern (gaetanlepage + drupol validated)
- ✅ Unblocks Story 1.10C (modules have flake context for clan vars)
- ✅ Provides migration pattern for Epic 2-6 (4 more machines will use Pattern A)
- ✅ Demonstrates evidence-based decision-making (Pattern B tried, limitations documented, corrected)
- ⏳ Feature restoration deferred to Story 1.10D (depends on Story 1.10C clan vars)

**Completion Notes:**
- Structural Pattern A migration completed successfully (4 hours actual vs 8-10 estimated)
- All 16 modules converted to explicit `flake.modules = { ... }` pattern
- All 3 critical builds passing (crs58, raquel, blackphos)
- darwinConfigurations.blackphos.system build fixed (was failing in Pattern B)
- Feature restoration scope moved to Story 1.10D (cleaner separation of concerns)
- Party Mode architectural review validated empirically

**Next:** Story 1.10C (clan vars infrastructure) → Story 1.10D (feature enablement)

---

## Story 1.10C: Establish sops-nix Secrets for Home-Manager

**⚠️ ARCHITECTURAL PIVOT - Two-Tier Secrets Pattern Validated**

As a system administrator,
I want to establish sops-nix secrets management for home-manager user configurations,
So that test-clan users have secure access to personal secrets (API keys, git signing keys, tokens) using proven sops-nix pattern validated from infra repository and clan reference implementations.

**Context:**
Initial investigation (2025-11-14) revealed secrets management gap.
Implementation attempt with clan vars approach (8/12 tasks, 11 commits) discovered CRITICAL architectural incompatibility.

**Architectural Discovery (2025-11-15):**

Investigation 1 - Clan vars + Home-Manager Compatibility:
- Explored ALL 8 clan reference repositories (mic92, qubasa, pinpox, jfly, enzime, clan-infra, onix, clan-core)
- Finding: ZERO instances of clan vars in home-manager modules across all reference repos
- Evidence: Clan vars module requires NixOS-specific `_class` parameter, incompatible with home-manager context
- Conclusion: Clan vars designed for SYSTEM-level (NixOS/darwin) secrets, NOT home-manager user secrets

Investigation 2 - User Age Key Management:
- Explored clan's user management architecture (sops/users/*/key.json)
- Finding: Clan user age keys for SYSTEM/deployment secrets, NOT home-manager user secrets
- Finding: sops-nix home-manager uses SEPARATE .sops.yaml configuration
- Finding: BOTH can reuse SAME age keypair (one per user, simpler)
- Conclusion: Two-tier architecture (system vs user secrets) with shared age keys

**Validated Two-Tier Secrets Architecture:**

```
System-Level Secrets (Machine/NixOS/Darwin)
├─ Tool: clan vars (clan.core.vars.generators)
├─ Layer: NixOS/darwin configuration modules
├─ Use cases: SSH host keys, zerotier, system services
└─ Future: When test-clan adds machines (Epic 2+)

User-Level Secrets (Home-Manager)
├─ Tool: sops-nix home-manager module
├─ Layer: Home-manager user configuration
├─ Use cases: API keys, git signing, personal tokens
└─ Story 1.10C: Establish for test-clan validation
```

**Age Key Reuse Pattern:**
- Same age private key (`~/.config/sops/age/keys.txt`) used by BOTH systems
- Public keys: Extract from `sops/users/*/key.json` (clan) → Reference in `.sops.yaml` (sops-nix)
- One keypair per user (simpler, consistent)

**Reference Pattern Validation:**
- infra repository: ALREADY uses sops-nix for home-manager (proven, working)
- All clan repos: System secrets (clan vars) vs User secrets (sops-nix OR runtime tools)
- Zero counter-examples: No clan reference repo uses clan vars in home-manager

**Secrets Inventory (7 secrets - from infra, corrected 2025-11-15):**

| Secret | Source | Usage | Type | Users | sops-nix Implementation |
|--------|--------|-------|------|-------|------------------------|
| github-token | shared.yaml | Git operations, gh CLI | API token | All | YAML value in secrets.yaml |
| ssh-signing-key | admin-user/signing-key.yaml | Git/jujutsu SSH signing | SSH private key | All | Multi-line YAML value |
| glm-api-key | admin-user/llm-api-keys.yaml | GLM alternative LLM | API token | crs58/cameron | YAML value (AI aggregate) |
| firecrawl-api-key | admin-user/mcp-api-keys.yaml | Firecrawl MCP server | API token | crs58/cameron | YAML value (AI aggregate) |
| huggingface-token | admin-user/mcp-api-keys.yaml | HuggingFace MCP | API token | crs58/cameron | YAML value (AI aggregate) |
| bitwarden-email | shared.yaml | Bitwarden config | Email | All | YAML value |
| atuin-key | Runtime extraction | Shell history sync | Encryption key | All | Base64 YAML value |

**User Distribution:**
- crs58/cameron: All 7 secrets (development + ai + shell aggregates)
- raquel: 4 secrets (github, ssh-signing, bitwarden, atuin) - development + shell only, NO AI

**Acceptance Criteria:**

**A. Infrastructure (AC1-AC3) - ✅ SKIP (Already Complete):**
- AC1: ~~Generate admin keypair~~ - Exists from Stories 1.1-1.10A
- AC2: ~~Add users to clan~~ - Exists (sops/users/crs58/, sops/users/raquel/)
- AC3: ~~Create vars directory~~ - Exists (vars/shared/, vars/per-machine/)

**B. sops-nix Configuration (AC4-AC6):**
- AC4: Create .sops.yaml with multi-user encryption
  - Extract age public keys from `sops/users/*/key.json`
  - Define creation_rules for per-user secrets and shared secrets
  - Configure admin recovery key

- AC5: Create sops-nix home-manager module infrastructure
  - Import `sops-nix.homeManagerModules.sops` in base module
  - Configure `sops.age.keyFile` pointing to `~/.config/sops/age/keys.txt`
  - Create base/sops.nix for common configuration

- AC6: Define user-specific sops secrets declarations
  - crs58: 7 secrets in users/crs58/sops.nix
  - raquel: 4 secrets in users/raquel/sops.nix
  - Set defaultSopsFile per user

**C. Secret Files Creation (AC7-AC9):**
- AC7: Create crs58 secrets file
  - Path: `secrets/home-manager/users/crs58/secrets.yaml`
  - Contents: All 7 secrets in YAML format
  - Encryption: `sops -e` (encrypted for crs58 + admin per .sops.yaml rules)

- AC8: Create raquel secrets file
  - Path: `secrets/home-manager/users/raquel/secrets.yaml`
  - Contents: 4 secrets subset (github, ssh-signing, bitwarden, atuin)
  - Encryption: `sops -e` (encrypted for raquel + admin)

- AC9: Verify secrets encryption
  - Test decryption: `sops -d secrets/home-manager/users/*/secrets.yaml`
  - Verify age keys work for respective users
  - Confirm multi-user isolation (raquel cannot decrypt crs58 AI keys)

**D. Module Access Pattern Updates (AC10-AC15):**
- AC10: Update modules/home/development/git.nix (all users)
  - SSH signing: `config.sops.secrets.ssh-signing-key.path`
  - GitHub token: `config.sops.secrets.github-token.path`

- AC11: Update modules/home/development/jujutsu.nix (all users)
  - SSH signing: `config.sops.secrets.ssh-signing-key.path`

- AC12: Update modules/home/ai/claude-code/mcp-servers.nix (crs58/cameron only)
  - Firecrawl: `config.sops.secrets.firecrawl-api-key.path`
  - HuggingFace: `config.sops.secrets.huggingface-token.path`

- AC13: Update modules/home/ai/claude-code/wrappers.nix (crs58/cameron only)
  - GLM: `config.sops.secrets.glm-api-key.path`

- AC14: Update modules/home/shell/atuin.nix (all users)
  - Atuin: `config.sops.secrets.atuin-key.path`

- AC15: Update/create bitwarden module (all users)
  - Bitwarden: `config.sops.secrets.bitwarden-email.path`

**E. Build Validation (AC16-AC18):**
- AC16: Nix build validation
  - `nix flake check` passes
  - `nix build .#darwinConfigurations.blackphos.system` succeeds
  - `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` succeeds
  - `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` succeeds

- AC17: sops-nix deployment validation
  - Secrets deployed to `$XDG_RUNTIME_DIR/secrets.d/`
  - Symlinks created in `~/.config/sops-nix/secrets/`
  - File permissions correct (secret files mode 0400)

- AC18: Multi-user isolation validation
  - crs58 can access all 7 secrets
  - raquel can access only 4 secrets (NO AI API keys)
  - Build verification: raquel homeConfiguration doesn't reference AI secrets

**F. Integration Validation (AC19-AC21):**
- AC19: sops-nix works with Pattern A modules
  - Pattern A home-manager modules access sops secrets cleanly
  - No conflicts between dendritic imports and sops access
  - Flake context (from Pattern A) enables sops usage

- AC20: Age key reuse validated
  - Same age private key used by clan secrets AND sops-nix
  - Key location: `~/.config/sops/age/keys.txt`
  - Public keys in .sops.yaml match sops/users/*/key.json

- AC21: Import-tree discovers sops modules
  - sops-nix modules auto-discovered correctly
  - Dendritic namespace export works with sops config

**G. Documentation (AC22-AC24):**
- AC22: Two-tier secrets architecture documentation
  - Document: System secrets (clan vars, future) vs User secrets (sops-nix, now)
  - Location: Architecture doc Section 12
  - Include: Age key reuse pattern, .sops.yaml structure

- AC23: sops-nix operational guide
  - Adding new secrets (edit + encrypt workflow)
  - Multi-user encryption (creation_rules examples)
  - Secret rotation (re-encryption procedure)
  - Troubleshooting (common errors, solutions)

- AC24: Access pattern examples
  - sops-nix patterns (module configuration, secret access)
  - Code examples: git.nix, mcp-servers.nix, atuin.nix
  - Multi-user examples: crs58 vs raquel sops configuration

**Prerequisites:** Story 1.10BA (Pattern A modules complete, flake context access ready for sops-nix)

**Blocks:**
- Story 1.10D (feature enablement requires secrets access)
- Story 1.12 (physical deployment needs functional secrets)

**Estimated Effort:** 4.5 hours (within original 3-5h range)
- sops-nix infrastructure setup (.sops.yaml, base modules): 1 hour
- Secret files creation and encryption: 45 minutes
- Module access pattern updates (6 modules): 1 hour
- Build validation and testing: 30 minutes
- Integration validation: 30 minutes
- Documentation: 45 minutes

**Work Salvaged from Clan Vars Attempt:** 66% (8/12 tasks)
- Module updates (git, jujutsu, mcp-servers, wrappers, atuin, rbw): Structure correct, change access pattern only
- Conditional user logic (crs58/cameron vs raquel): Valid, just different implementation
- Atomic commits: Easy to modify for sops-nix approach

**Risk Level:** Low (proven pattern from infra, sops-nix well-documented)

**Risk Mitigation:**
- Use infra's proven .sops.yaml structure (copy and adapt)
- Reuse existing age keys from `sops/users/*/key.json` (no new key generation)
- Test sops decryption before nix builds (`sops -d secrets.yaml`)
- Keep infra sops-nix secrets as reference (same pattern)

**Strategic Value - Epic 1 ARCHITECTURAL FINDING:**

**Two-Tier Secrets Architecture Validated:**
- ✅ **System-level secrets**: clan vars (NixOS/darwin modules) - Future use when test-clan adds machines
- ✅ **User-level secrets**: sops-nix (home-manager modules) - Story 1.10C implementation
- ✅ **Age key reuse**: Same keypair for both systems (simpler, consistent)
- ✅ **Reference validation**: 8 clan repos examined, ZERO counter-examples

**Epic 1 Goals Achieved:**
1. Validated clan vars correct usage (system-level, not home-manager)
2. Prevented architectural error propagation to Epic 2-6 (6 machines)
3. Established sops-nix for home-manager (proven pattern from infra)
4. Documented secrets boundary (system vs user)
5. Savings: 8-12 hours prevented rework across infra migration

**Investigation Impact:**
- 2 Explore agent investigations (clan vars compatibility, age key management)
- 30-45 minutes investigation time
- 12-18 hours saved (wrong pattern prevention across 6 machines)
- Epic 1 ROI: Architectural clarity worth more than time investment

**Pattern for Epic 2-6:**
- nix-darwin machines (stibnite, blackphos, argentum, rosegold): sops-nix for home-manager secrets
- NixOS machines (cinnabar, ephemeral VMs): clan vars for system secrets, sops-nix for user secrets
- Hybrid approach validated: Clear separation, shared age keys

---

## Story 1.10D: Validate Custom Package Overlays with pkgs-by-name Pattern

**⚠️ NEW STORY - Infrastructure Validation (Blocks Story 1.10E)**

As a system administrator,
I want to validate that infra's custom package overlays work with dendritic flake-parts + clan architecture using the pkgs-by-name pattern,
So that Epic 2-6 migration can proceed confidently knowing all 4 infra custom packages will migrate successfully.

**Context:**

Epic 1 validation mission requires proving ALL infra architectural patterns work with dendritic + clan, not just modules and secrets.

infra has 4 production custom packages (ccstatusline, atuin-format, markdown-tree-parser, starship-jj) currently in `overlays/packages/` using `lib.packagesFromDirectoryRecursive` for auto-discovery.
These packages must migrate to dendritic flake-parts structure in Epic 2-6.

**Critical Discovery:** Dendritic Overlay Pattern Review (2025-11-16) identified pkgs-by-name-for-flake-parts (drupol) as optimal pattern:
- Uses SAME underlying function as infra (`lib.packagesFromDirectoryRecursive`)
- Follows nixpkgs RFC 140 convention (`pkgs/by-name/` directory structure)
- Zero boilerplate (just set `pkgsDirectory` option in perSystem)
- Proven in production: drupol-dendritic-infra (9 packages), compatible with gaetanlepage comprehensive dendritic usage

**Migration Assessment:** infra overlay system is ✅ COMPATIBLE with dendritic pattern.
Migration requires directory restructuring (`overlays/packages/` → `pkgs/by-name/`) but NO code changes to package derivations.
Estimated effort: 2.5-3 hours for all 4 packages.

**Story 1.10D validates:** Create pkgs-by-name infrastructure in test-clan, implement ccstatusline as proof-of-concept, prove pattern works end-to-end (package build → module consumption → activation).
Success means Epic 2-6 can migrate infra's 4 packages with confidence.

**Blocks Story 1.10E:** ccstatusline feature enablement requires ccstatusline package (created in this story).

**Test Case: ccstatusline**

ccstatusline chosen as proof-of-concept because:
- Production-ready derivation exists in infra (copy directly, no development needed)
- Settings pre-configured in test-clan: ccstatusline-settings.nix (175 lines, waiting for package)
- Full workflow validation: package build → perSystem export → pkgs.* consumption → home-manager activation
- Represents real infra need (Claude Code status line feature)

**Acceptance Criteria:**

**A. Add pkgs-by-name-for-flake-parts Infrastructure:**
1. Add flake input to flake.nix:
   ```nix
   inputs.pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";
   ```
2. Import flake module in modules/nixpkgs.nix:
   ```nix
   imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];
   ```
3. Configure pkgsDirectory in perSystem:
   ```nix
   perSystem = { ... }: {
     pkgsDirectory = ../../pkgs/by-name;
   };
   ```
4. Verify flake module loads without errors

**Estimated effort:** 15 min

**B. Create pkgs/by-name Directory Structure:**
1. Create directory following nixpkgs convention:
   ```bash
   mkdir -p pkgs/by-name/cc/ccstatusline
   ```
2. Structure follows RFC 140: `pkgs/by-name/<first-2-chars>/<package-name>/package.nix`
3. Directory accessible from flake root
4. Matches drupol-dendritic-infra pattern

**Estimated effort:** 5 min

**C. Implement ccstatusline Package:**
1. Copy production-ready derivation from infra:
   ```bash
   cp ~/projects/nix-workspace/infra/overlays/packages/ccstatusline.nix \
      pkgs/by-name/cc/ccstatusline/package.nix
   ```
2. Verify package.nix uses standard callPackage signature:
   ```nix
   { lib, buildNpmPackage, fetchzip, jq, nix-update-script }:
   buildNpmPackage (finalAttrs: { ... })
   ```
3. No modifications needed (derivation is production-validated)
4. Package follows npm tarball pattern (pre-built dist/, no compilation)

**Estimated effort:** 10 min (copy + verify)

**D. Validate Package Auto-Discovery:**
1. Build ccstatusline package:
   ```bash
   nix build .#packages.aarch64-darwin.ccstatusline
   # OR
   nix build .#ccstatusline  # Short form
   ```
2. Verify package exports:
   - `packages.<system>.ccstatusline` (flat output)
   - `legacyPackages.<system>.<nested>` (if applicable)
3. Check package accessible via pkgs namespace:
   ```bash
   nix eval .#packages.aarch64-darwin.ccstatusline.meta.description
   # Expected: "Highly customizable status line formatter for Claude Code CLI"
   ```
4. Verify auto-discovery worked (no manual package list needed)

**Estimated effort:** 15 min

**E. Validate Package Build Quality:**
1. Inspect package contents:
   ```bash
   ls -la result/bin/
   ls -la result/lib/node_modules/ccstatusline/
   ```
2. Verify executable exists and is executable:
   ```bash
   file result/bin/ccstatusline
   test -x result/bin/ccstatusline && echo "✓ Executable"
   ```
3. Check runtime dependencies:
   ```bash
   nix-store -q --references result/
   # Expected: nodejs, ccstatusline package
   ```
4. Verify package metadata complete (description, homepage, license, mainProgram)

**Estimated effort:** 15 min

**F. Test Module Consumption:**
1. Create temporary test module to verify pkgs.ccstatusline accessible:
   ```nix
   # modules/home/ai/claude-code/default.nix (UPDATE - uncomment ccstatusline)
   { pkgs, ... }:
   {
     programs.claude-code.settings.statusLine = {
       type = "command";
       command = "${pkgs.ccstatusline}/bin/ccstatusline";
       padding = 0;
     };
   }
   ```
2. Verify pkgs.ccstatusline resolves (no infinite recursion, no eval errors)
3. Build home-manager configuration:
   ```bash
   nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
   ```
4. Verify ccstatusline in activation closure:
   ```bash
   nix-store -q --references result/ | grep ccstatusline
   ```

**Estimated effort:** 30 min

**G. Validate Dendritic Compatibility:**
1. Verify package definition is NOT a flake-parts module (just derivation)
2. Verify package EXPORT via flake module (modules/nixpkgs.nix)
3. Verify package CONSUMPTION in dendritic module (claude-code/default.nix)
4. Confirm NO specialArgs pass-thru needed (pkgs available in all modules)
5. Check import-tree auto-discovery doesn't conflict with pkgs-by-name
6. Verify pattern matches drupol-dendritic-infra architecture

**Estimated effort:** 15 min

**H. Validate infra Migration Readiness:**
1. Document infra's 4 packages and migration path:
   - ccstatusline: `overlays/packages/ccstatusline.nix` → `pkgs/by-name/cc/ccstatusline/package.nix` ✅ (validated)
   - atuin-format: `overlays/packages/atuin-format/` → `pkgs/by-name/at/atuin-format/package.nix`
   - markdown-tree-parser: `overlays/packages/markdown-tree-parser.nix` → `pkgs/by-name/ma/markdown-tree-parser/package.nix`
   - starship-jj: `overlays/packages/starship-jj.nix` → `pkgs/by-name/st/starship-jj/package.nix`
2. Verify all use standard callPackage signatures (no custom overlayArgs needed)
3. Confirm lib.packagesFromDirectoryRecursive pattern matches pkgs-by-name-for-flake-parts
4. Assessment: ✅ SAFE TO MIGRATE (directory restructuring only, no code changes)

**Estimated effort:** 30 min (documentation + verification)

**I. Documentation - Section 13.1 (Custom Package Overlays):**
1. Create "13.1 Custom Package Overlays" subsection in test-clan-validated-architecture.md
2. Document pkgs-by-name-for-flake-parts pattern:
   - Directory structure (pkgs/by-name/<first-2-chars>/<package-name>/)
   - flake.nix integration (add flake input)
   - modules/nixpkgs.nix configuration (import module, set pkgsDirectory)
   - Package auto-discovery mechanism
   - Module consumption (pkgs.* namespace)
3. Provide ccstatusline complete working example:
   - package.nix derivation (85 lines, npm tarball pattern)
   - Build commands
   - Integration test commands
4. Document infra migration path (4 packages, directory restructuring)
5. Reference drupol-dendritic-infra and gaetanlepage compatibility proof

**Estimated effort:** 45 min

**Prerequisites:**
- Story 1.10C (sops-nix infrastructure, validates secrets work with dendritic)
- Dendritic Overlay Pattern Review (completed 2025-11-16, provides architectural guidance)

**Blocks:**
- Story 1.10E (ccstatusline feature enablement requires package from this story)
- Epic 1 checkpoint (overlay validation critical for Epic 2-6 GO decision)

**Estimated Effort:** 2-3 hours
- flake input + module configuration (AC A-B): 20 min
- ccstatusline package implementation (AC C): 10 min
- Build validation (AC D-E): 30 min
- Module consumption test (AC F): 30 min
- Dendritic compatibility verification (AC G): 15 min
- infra migration assessment (AC H): 30 min
- Documentation Section 13.1 (AC I): 45 min

**Risk Level:** Low (proven pattern in drupol-dendritic-infra, infra compatibility confirmed, production-ready derivation)

**Strategic Value:**
- Completes Epic 1 architectural validation (modules ✅, secrets ✅, **overlays ✅**)
- Validates infra's 4 custom packages will migrate to dendritic + clan successfully
- Removes last Epic 2-6 migration blocker (overlay pattern uncertainty)
- Provides reusable pattern template for Epic 2-6 package migration
- Proves dendritic pattern is comprehensive (handles all infra architectural components)
- De-risks Epic 2-6 timeline (no overlay emergency fixes needed)
- Documents migration path for 4 infra packages (2.5-3h effort in Epic 2)

**Success Metrics:**
- pkgs-by-name-for-flake-parts integrated (flake input + module import)
- pkgs/by-name/ directory created following RFC 140 convention
- ccstatusline package builds successfully (nix build .#ccstatusline)
- ccstatusline accessible via pkgs.ccstatusline in modules
- home-manager activation includes ccstatusline package
- Zero dendritic pattern conflicts (import-tree + pkgs-by-name coexist)
- Section 13.1 documentation complete (pattern + example + migration guide)
- infra migration path documented (4 packages, directory restructuring)
- Epic 1 architectural coverage: 95% (all critical infra components validated)

**References:**
- drupol-dendritic-infra: ~/projects/nix-workspace/drupol-dendritic-infra/ (PRIMARY pattern reference)
- gaetanlepage-dendritic-nix-config: ~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/ (compatibility proof)
- infra overlays: ~/projects/nix-workspace/infra/overlays/ (migration source)
- pkgs-by-name-for-flake-parts: https://github.com/drupol/pkgs-by-name-for-flake-parts (flake module)
- nixpkgs RFC 140: https://github.com/NixOS/rfcs/pull/140 (pkgs/by-name convention)

---

## Story 1.10DA: Validate Overlay Architecture Preservation with pkgs-by-name Integration

**Dependencies:** Story 1.10D (done) - pkgs-by-name pattern validated for custom packages

**Blocks:** Epic 1 completion checkpoint (ensures ALL 5 overlay layers validated before Epic 2-6)

As a system administrator,
I want to validate that infra's overlay architecture (multi-channel access, hotfixes, overrides, flake input overlays) is preserved when integrating with pkgs-by-name pattern,
So that Epic 2-6 migration maintains ALL infra overlay features (stable fallbacks, hotfixes, build customizations) while gaining pkgs-by-name benefits.

**Context:**

Story 1.10D validated Layer 3 (custom packages) migration to pkgs-by-name-for-flake-parts. This story validates Layers 1, 2, 4, 5 (overlay architecture) are preserved and functional alongside pkgs-by-name.

infra's 5-Layer Overlay Architecture (from `overlays/default.nix`):

1. **inputs** (`overlays/inputs.nix`) - Multi-channel nixpkgs access (stable, patched, unstable)
2. **hotfixes** (`overlays/infra/hotfixes.nix`) - Platform-specific stable fallbacks for broken unstable packages
3. **packages** (`overlays/packages/`) - Custom derivations [MIGRATED TO pkgs-by-name in Story 1.10D]
4. **overrides** (`overlays/overrides/`) - Per-package build modifications
5. **flakeInputs** - Overlays from flake inputs (nuenv, jujutsu, etc.)

drupol-dendritic-infra proves overlays + pkgs-by-name coexist (see `modules/flake-parts/nixpkgs.nix` lines 19-37 showing traditional overlays array + pkgsDirectory for custom packages in the same perSystem configuration).

This story validates the hybrid architecture works in test-clan, ensuring Epic 2-6 migration can confidently preserve ALL infra overlay functionality while adopting pkgs-by-name for custom packages.

**Acceptance Criteria:**

**A. Validate Multi-Channel Access (Layer 1) - 30 min:**

1. Document `overlays/inputs.nix` pattern providing multi-channel access (stable, patched, unstable)
2. Test stable channel access in test-clan context (`pkgs.stable.*` references)
3. Test unstable channel access in test-clan context (`pkgs.unstable.*` explicit references)
4. Confirm multi-channel access works alongside pkgs-by-name packages (no conflicts)
5. Document multi-channel access pattern in Section 13.2 of test-clan-validated-architecture.md

**B. Validate Hotfixes Layer (Layer 2) - 20 min:**

1. Review `overlays/infra/hotfixes.nix` pattern (platform-specific stable fallbacks)
2. Document hotfix pattern: when unstable breaks, fallback to `pkgs.stable.*` version
3. Verify hotfix pattern is compatible with pkgs-by-name integration (no conflicts)
4. Document hotfix preservation strategy in Section 13.2

**C. Validate Overrides Layer (Layer 4) - 20 min:**

1. Review `overlays/overrides/` pattern (per-package build modifications using overrideAttrs)
2. Document override pattern examples (build flags, test disabling, dependency patches)
3. Verify override pattern is compatible with pkgs-by-name integration (no conflicts)
4. Document override preservation strategy in Section 13.2

**D. Validate Flake Input Overlays (Layer 5) - 20 min:**

1. Review flakeInputs overlay pattern (overlays from `inputs.nuenv`, `inputs.jj`, etc.)
2. Document flake input overlay examples (nuenv devshell overlay, jujutsu VCS overlay)
3. Verify flake input overlays are compatible with pkgs-by-name integration (no conflicts)
4. Document flake input overlay preservation strategy in Section 13.2

**E. Integration Validation (Hybrid Architecture) - 20 min:**

1. Verify drupol hybrid pattern (overlays array + pkgsDirectory) applicable to test-clan
2. Document how overlays array and pkgsDirectory coexist in same perSystem configuration
3. Test no conflicts between overlay merging and pkgs-by-name auto-discovery
4. Confirm ALL 5 layers functional in test-clan (multi-channel, hotfixes, custom packages, overrides, flake inputs)
5. Document hybrid architecture integration in Section 13.2

**F. Documentation - Section 13.2: Overlay Architecture Preservation - 30 min:**

1. Create Section 13.2 "Overlay Architecture Preservation" in test-clan-validated-architecture.md
2. Document 5-layer architecture model with descriptions (inputs, hotfixes, packages, overrides, flakeInputs)
3. Explain overlay + pkgs-by-name coexistence using drupol hybrid pattern
4. Provide code examples for each overlay layer:
   - Multi-channel access: `pkgs.stable.packageName` vs `pkgs.unstable.packageName`
   - Hotfixes: `stable.packageName` fallback when unstable breaks
   - Overrides: `overrideAttrs` pattern for build modifications
   - Flake input overlays: nuenv devshell overlay, jujutsu VCS overlay
5. Document Epic 2-6 migration strategy: overlays preserved as-is, custom packages migrate to pkgs-by-name
6. Link to drupol reference implementation and infra overlay architecture files

**Prerequisites:**
- Story 1.10D (done): pkgs-by-name pattern validated, ccstatusline working in test-clan

**Blocks:**
- Epic 1 checkpoint: Complete overlay architecture validation required for Epic 2-6 GO decision

**Estimated Effort:** 1.5-2 hours

**Risk Level:** Low (overlays already working in infra, validating preservation only, drupol proves pattern viable)

**Strategic Value:**

- **Architectural Completeness**: Achieves 95% Epic 1 coverage by validating ALL 5 overlay layers
- **Migration Confidence**: Proves Epic 2-6 migration retains ALL infra features (stable fallbacks, hotfixes, customizations)
- **Hybrid Architecture Validation**: Confirms overlays + pkgs-by-name coexist per drupol reference
- **Documentation**: Creates comprehensive Section 13.2 overlay preservation guide for Epic 2-6 teams
- **Risk Reduction**: Removes last architectural uncertainty before Epic 2-6 (no feature loss)

**Success Metrics:**

- All 5 overlay layers documented in test-clan context with code examples
- Multi-channel access pattern explained (`pkgs.stable.*`, `pkgs.unstable.*`)
- Hotfixes, overrides, flake input overlays preservation strategies documented
- Section 13.2 provides comprehensive overlay architecture guide (5-layer model + hybrid pattern)
- drupol hybrid pattern (overlays + pkgs-by-name) validated applicable to test-clan
- Epic 1 complete: 95% architectural coverage achieved (ALL infra patterns validated)

**References:**

- **Primary**: `~/projects/nix-workspace/drupol-dendritic-infra/modules/flake-parts/nixpkgs.nix` (hybrid pattern, lines 19-37)
- **infra overlays**: `~/projects/nix-workspace/infra/overlays/` (5-layer architecture source)
  - `overlays/default.nix` - Architecture documentation and layer composition (lines 1-77)
  - `overlays/inputs.nix` - Multi-channel access implementation (Layer 1)
  - `overlays/infra/hotfixes.nix` - Platform-specific stable fallbacks (Layer 2)
  - `overlays/overrides/` - Per-package build modifications (Layer 4)
- **test-clan target**: `~/projects/nix-workspace/test-clan/` (validation environment)

---

## Story 1.10E: Enable Features Using sops-nix Secrets and Flake Inputs

**⚠️ UPDATED STORY - Feature Enablement (Unblocked by Story 1.10D)**

As a system administrator,
I want to enable the remaining disabled home-manager features using sops-nix (for secrets) and flake.inputs (for packages/themes),
So that all production features are functional in test-clan using the validated Pattern A + sops-nix architecture.

**Context:**

Story 1.10BA completed Pattern A structural migration but deferred feature enablement (original AC17-AC20) pending secrets infrastructure establishment.

Story 1.10C establishes sops-nix user-level secrets infrastructure (age encryption, multi-user support, sops.templates patterns). During implementation (61 commits, 2025-11-15 to 2025-11-16), **9/11 Story 1.10E features were enabled using sops-nix patterns**, leaving only flake.inputs-dependent features (claude-code package, catppuccin theme, ccstatusline package) for Story 1.10E completion.

Story 1.10D validates custom package overlays with pkgs-by-name pattern, implementing ccstatusline package infrastructure (blocks Story 1.10E AC F).

Story 1.10E completes feature enablement by configuring flake.inputs, enabling remaining features (including ccstatusline from Story 1.10D), and documenting all feature enablement patterns in Section 13 of test-clan-validated-architecture.md.

**Features Status (from Story 1.10B disabled features):**

**Category A: Secrets via sops-nix (5 features - ✅ COMPLETED IN STORY 1.10C):**
1. ✅ SSH signing in git.nix - `config.sops.secrets.ssh-signing-key.path` (Story 1.10C, commit f9e9e92)
2. ✅ SSH signing in jujutsu.nix - `config.sops.secrets.ssh-signing-key.path` (Story 1.10C, commit 04c1617)
3. ✅ MCP firecrawl API key - `config.sops.placeholder."firecrawl-api-key"` in sops.templates (Story 1.10C, commit c63b61e)
4. ✅ MCP huggingface token - `config.sops.placeholder."huggingface-token"` in sops.templates (Story 1.10C, commit c63b61e)
5. ⚠️ MCP context7 - NOT in test-clan scope (implementation documents "Only 2 MCP servers")

**Category B: Packages via flake.inputs (3 features - 1 ENABLED, 2 REMAINING):**
6. ✅ GLM wrapper in wrappers.nix - Custom `pkgs.writeShellApplication` + sops-nix API key (Story 1.10C, commit f6b01e3, production-ready)
7. ❌ claude-code package in default.nix - Blocked: nix-ai-tools flake input not configured ← **Story 1.10E scope**
8. ❌ ccstatusline package - Blocked: Package created in Story 1.10D. Note: ccstatusline-settings.nix ✅ ENABLED (175 lines) ← **Story 1.10E scope (enable feature)**

**Category C: Themes via flake.inputs (3 features - 0 ENABLED, BLOCKED):**
9-11. ❌ catppuccin-nix tmux theme - Blocked: catppuccin-nix flake input not configured. Note: Status bar placeholders configured (15/36 lines) ← **Story 1.10E scope**

**Bonus Features (✅ ENABLED IN STORY 1.10C, undocumented in original epic):**
- ✅ Atuin encryption key deployment via activation script
- ✅ Bitwarden (rbw) email config via sops.templates
- ✅ Git allowed_signers file generation via sops.templates

**Acceptance Criteria:**

**A. COMPLETED IN STORY 1.10C - Document Implementation:**
1. ✅ Git SSH signing enabled (git.nix:24-28):
   ```nix
   signing = lib.mkDefault {
     key = config.sops.secrets.ssh-signing-key.path;
     format = "ssh";
     signByDefault = true;
   };
   ```
2. ✅ Jujutsu SSH signing enabled (jujutsu.nix:41):
   ```nix
   key = lib.mkDefault config.sops.secrets.ssh-signing-key.path;
   ```
3. ✅ Build validation: PASS (Story 1.10C comprehensive review, 4/4 builds)
4. ✅ Signing key accessible: Validated via sops.secrets module

**Story 1.10D scope:** Document pattern in Section 13 of test-clan-validated-architecture.md

**B. COMPLETED IN STORY 1.10C - Document Implementation:**
1. ✅ Firecrawl API key enabled (mcp-servers.nix:34-52 via sops.templates):
   ```nix
   sops.templates.mcp-firecrawl = {
     content = builtins.toJSON {
       mcpServers.firecrawl.env = {
         FIRECRAWL_API_KEY = config.sops.placeholder."firecrawl-api-key";
       };
     };
   };
   ```
2. ✅ HuggingFace token enabled (mcp-servers.nix:56-73 via sops.templates):
   ```nix
   args = [
     "--header"
     "Authorization: Bearer ${config.sops.placeholder."huggingface-token"}"
   ];
   ```
3. ⚠️ Context7 not in test-clan scope (implementation documents "Only 2 MCP servers")

**Story 1.10D scope:** Document sops.templates pattern in Section 13

**C. COMPLETED IN STORY 1.10C - Document Implementation:**
1. ✅ GLM wrapper enabled (wrappers.nix:23-44 custom implementation):
   ```nix
   home.packages = [
     (pkgs.writeShellApplication {
       name = "claude-glm";
       text = ''
         GLM_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
         export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
         exec claude "$@"
       '';
     })
   ];
   ```
2. ✅ Runtime secret access verified (production-ready pattern)

**Story 1.10D scope:** Document runtime cat pattern for shell wrappers in Section 13

**D. Enable claude-code Package Override (REMAINING WORK):**
1. Add nix-ai-tools flake input to flake.nix:
   ```nix
   inputs.nix-ai-tools.url = "github:cameronraysmith/nix-ai-tools";
   ```
2. Uncomment in default.nix (line 24):
   ```nix
   programs.claude-code.package = flake.inputs.nix-ai-tools.packages.${pkgs.system}.claude-code;
   ```
3. Verify package builds and is accessible

**Estimated effort:** 30 min (15 min flake.nix + 15 min build test)

**E. Enable catppuccin tmux Theme (REMAINING WORK):**
1. Add catppuccin-nix flake input to flake.nix:
   ```nix
   inputs.catppuccin-nix.url = "github:catppuccin/nix";
   ```
2. Import module in tmux.nix (replace line 40 TODO):
   ```nix
   imports = [ flake.inputs.catppuccin-nix.homeManagerModules.catppuccin ];

   programs.tmux.catppuccin = {
     enable = true;
     flavor = "mocha";
     # ... 36-line configuration (reference infra implementation)
   };
   ```
3. Verify theme renders correctly (visual check)

**Estimated effort:** 45 min (15 min flake.nix + 30 min config + test)

**F. Enable ccstatusline Feature:**
1. ✅ Package available: pkgs.ccstatusline (Story 1.10D)
2. ✅ Settings configured: ccstatusline-settings.nix (175 lines, production-ready)
3. Uncomment statusLine config in claude-code/default.nix:
   ```nix
   programs.claude-code.settings.statusLine = {
     type = "command";
     command = "${pkgs.ccstatusline}/bin/ccstatusline";
     padding = 0;
   };
   ```
4. Verify ccstatusline renders in Claude Code CLI status line
5. Validate against ccstatusline-settings.nix configuration (3-line powerline style)

**Estimated effort:** 15 min (uncomment + validation)

**G. Build Validation:**
1. ✅ Story 1.10C builds validated (comprehensive review report, 4/4 builds PASS)
2. After flake.inputs changes: Re-validate all builds
   - crs58 homeConfiguration
   - raquel homeConfiguration
   - blackphos darwinConfiguration
   - cinnabar nixosConfiguration
3. Verify new features functional (claude-code package override, catppuccin theme rendering)
4. No build errors or evaluation failures

**Estimated effort:** 30 min (build + smoke test)

**H. Documentation - Feature Enablement Patterns:**
1. Create Section 13 in test-clan-validated-architecture.md: "Feature Enablement with sops-nix"
2. Document sops-nix access patterns:
   - Direct path: `config.sops.secrets.X.path` (git, jujutsu signing)
   - sops.placeholder: `config.sops.placeholder."X"` in sops.templates (MCP servers, rbw)
   - Runtime cat: Shell scripts reading `$(cat ${config.sops.secrets.X.path})` (GLM wrapper)
   - Activation scripts: Non-XDG secret deployment (atuin)
3. Document flake.inputs patterns:
   - Module imports: `flake.inputs.X.homeManagerModules.Y`
   - Package overrides: `flake.inputs.X.packages.${pkgs.system}.Y`
4. List enabled features with implementation notes:
   - ccstatusline: Custom package from Story 1.10D (pkgs-by-name pattern)
   - claude-code: Package override from nix-ai-tools flake input
   - catppuccin: Theme from catppuccin-nix flake input

**Estimated effort:** 30 min

**Prerequisites:**
- Story 1.10C (sops-nix infrastructure established, 9/11 features already enabled)
- Story 1.10D (custom packages overlay infrastructure, ccstatusline package available)

**Blocks:** Story 1.12 (physical deployment benefits from claude-code package override, but not blocked)

**Estimated Effort:** 1.5-2 hours (reduced from 2-3 hours due to Story 1.10C overlap)
- Review Story 1.10C implementations (AC A-C): 15 min (already complete)
- Add flake.inputs (nix-ai-tools, catppuccin-nix): 30 min
- Enable claude-code package (AC D): 15 min
- Enable catppuccin theme (AC E): 45 min
- Enable ccstatusline feature (AC F): 15 min
- Build validation (AC G): 30 min
- Documentation Section 13 (AC H): 30 min

**Risk Level:** Low (9/11 features validated in Story 1.10C, only flake.inputs configuration remaining)

**Strategic Value:**
- Proves sops-nix works for production features across 4 distinct patterns (direct path, sops.placeholder, runtime cat, activation scripts)
- Validates flake.inputs access pattern for external packages/themes
- Completes the Pattern A + sops-nix validation (structure + secrets + features + flake.inputs)
- Provides complete reference for Epic 2-6 (all architectural layers working together)
- Demonstrates test-clan is production-ready architecture with comprehensive feature coverage
- Documents reusable feature enablement patterns for future migration

**Success Metrics:**
- 11/11 features ENABLED (all functional, none just documented)
  - 9/11 from Story 1.10C (sops-nix patterns)
  - 2/11 in Story 1.10E (flake.inputs: claude-code, catppuccin)
  - 1 bonus from Story 1.10D (custom package: ccstatusline)
- All builds passing (4/4 validated)
- All secrets accessible via sops-nix (8 secrets for crs58, 5 for raquel)
- Flake.inputs packages accessible (nix-ai-tools, catppuccin-nix configured)
- Custom packages accessible (ccstatusline from Story 1.10D)
- ccstatusline feature working (status line renders correctly)
- Section 13 documentation complete (4 sops-nix patterns + 2 flake.inputs patterns + custom packages)
- Zero regressions from Story 1.10BA, Story 1.10C, or Story 1.10D

---

## Party Mode Checkpoint: Story 1.11 Evidence-Based Assessment

**⚠️ ADAPTIVE DECISION POINT**

After completing Stories 1.10BA (Pattern A refactoring), 1.10C (secrets migration), and 1.10D (feature enablement), reconvene Party Mode team to make evidence-based decision about Story 1.11 (Type-Safe Home-Manager Architecture) execution.

**UPDATE (2025-11-14): Story 1.10B Empirical Evidence Validates Pattern A Decision**

Story 1.10B implementation discovered **CRITICAL ARCHITECTURAL LIMITATIONS** of Pattern B (documented in dev notes lines 767-1031):
- 11 features disabled (SSH signing, MCP API keys, themes, custom packages)
- darwinConfigurations.blackphos.system **FAILS TO BUILD**
- No flake context access (plain modules cannot access flake.inputs, overlays, or home-manager modules from flake inputs)
- sops-nix completely incompatible (requires flake.config lookups)

**Evidence-Based Decision:** Story 1.10BA inserted to refactor Pattern B → Pattern A before Story 1.10C.

**Party Mode Checkpoint Updated:**
After Stories 1.10BA + 1.10C + 1.10D complete, reconvene Party Mode to assess Story 1.11 (type-safe architecture) based on Pattern A + clan vars implementation evidence at scale.

**Rationale:**
Story 1.11 proposes specific architectural pattern (homeHosts with type safety, smart resolution, machine-specific configs).
This pattern was designed before implementing dendritic + clan synthesis at scale (Pattern A multi-aggregate + clan vars).
After real Pattern A implementation, we'll have empirical evidence to assess whether Story 1.11:
- Improves established patterns (GO)
- Needs adjustment to fit actual patterns (MODIFY)
- Adds unnecessary complexity (SKIP)

**Assessment Framework:**

**Evidence to Collect from Stories 1.10BA + 1.10C + 1.10D:**
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
1. Review Stories 1.10BA + 1.10C + 1.10D implementation learnings (what worked, what didn't)
2. Assess dendritic + clan vars synthesis patterns that emerged at scale
3. Evaluate Story 1.11 value proposition against actual implementation evidence (17 modules, clan vars, 11 features)
4. Discuss alternative approaches if MODIFY decision (lighter-weight solutions)
5. Make decision: GO / MODIFY / SKIP with explicit rationale
6. If GO or MODIFY: Update Story 1.11 scope and acceptance criteria accordingly
7. Update Story 1.12 dependencies based on decision

**Documentation Requirement:**
Party Mode session outcome documented in Story 1.13 (integration findings) with:
- Evidence collected from Stories 1.10BA + 1.10C + 1.10D (structure + secrets + features)
- Decision rationale (GO/MODIFY/SKIP)
- If MODIFY: Adjusted Story 1.11 scope
- If SKIP: Explanation of why Pattern A + clan vars is sufficient

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
- Story 1.10BA (home-manager modules refactored to Pattern A - provides working baseline with aggregate namespaces)
- Story 1.10C (secrets migrated - completes configuration)
- Party Mode Checkpoint (GO decision required to execute this story - assesses Pattern A implementation)

**Blocks:** None (Story 1.12 blackphos deployment can proceed without this, but benefits from it)

**Conditional Execution:**
This story executes ONLY if Party Mode checkpoint (after Stories 1.10BA + 1.10C) determines:
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
- Story 1.10BA completed Pattern A refactoring (17 modules in multi-aggregate dendritic, full functionality restored)
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
- Story 1.10BA (home-manager modules refactored to Pattern A - REQUIRED for complete functional configuration)
- Story 1.10C (secrets migrated - REQUIRED for SSH signing, API keys functional)
- Story 1.11 (type-safe architecture - OPTIONAL, depends on Party Mode checkpoint decision)

**Hard Dependencies:** Stories 1.10BA + 1.10C must be complete (full config + secrets + working features)
**Soft Dependency:** Story 1.11 improves deployment quality but not required for validation

**Estimated Effort:** 4-6 hours
- 1-2 hours: Physical deployment and validation
- 2-3 hours: Zerotier darwin integration investigation and configuration
- 1 hour: Network validation and documentation

**Risk Level:** Medium (deploying to real physical machine, zerotier darwin support uncertain)

**Strategic Value:**
- Proves heterogeneous networking (nixos ↔ nix-darwin) works with complete configurations
- Validates multi-platform coordination pattern for production fleet
- Demonstrates dendritic Pattern A + clan-core works seamlessly across platforms
- Completes Epic 1 architectural validation with real darwin hardware

**Note:** Story 1.10BA established complete, well-architected configuration with Pattern A. This story focuses purely on deployment and integration testing. Minimal rework expected.

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
