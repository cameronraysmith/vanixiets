# Epic 1: Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Goal:** Validate dendritic flake-parts + clan architecture for both nixos VMs and nix-darwin hosts, validate cross-platform user config sharing, and document nixos-unified → dendritic + clan transformation pattern through blackphos migration rehearsal

**Strategic Value:** Validates complete stack (dendritic + clan + terraform + infrastructure) on real VMs and darwin machines before production refactoring, proves both target architecture AND transformation process, validates cross-platform home-manager modularity (Epic 1 architectural requirement), provides reusable migration blueprint for Epic 2+ by rehearsing complete nixos-unified → dendritic + clan conversion

**Timeline:** 3-4 weeks (2 weeks nixos validation complete + 1-2 weeks darwin migration rehearsal + home-manager modularity)

**Success Criteria:**
- Hetzner VMs deployed and operational (minimum requirement achieved)
- Dendritic flake-parts pattern proven with zero regressions (achieved via Stories 1.6-1.7)
- Nix-darwin machine (blackphos) migrated from infra to test-clan management
- **Cross-platform user config sharing validated (Story 1.8A - portable home modules)**
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

**Note:** This story completes migrations and establishes clean foundation. Story 1.11 implements type-safe home-manager architecture on this foundation.

---

## Story 1.11: Implement Type-Safe Home-Manager Architecture

As a system administrator,
I want to implement type-safe home-manager architecture with smart resolution and machine-specific configurations,
So that I have a production-ready, maintainable home-manager pattern for the entire fleet (Epic 2-6) with compile-time validation and intelligent deployment.

**Context:**
- Story 1.10 completed migrations and established clean foundation (user modules finalized, clean codebase)
- Current home-manager uses static generator (`configurations.nix`) - no type safety, no machine-specific configs
- Need gaetanlepage-level type safety with mic92-style clan integration for production fleet (6 machines)
- Must support three integration modes: darwin-integrated, nixos-integrated, standalone homeConfigurations

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

**Prerequisites:** Story 1.10 (migrations complete, clean foundation established, user modules finalized)

**Blocks:** None (Story 1.12 blackphos deployment can proceed without this, but benefits from it)

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
- Story 1.10 completed blackphos migration, cinnabar user configuration, and dendritic pattern refinements
- Story 1.11 implemented type-safe home-manager architecture (optional but recommended)
- Configuration is now complete, well-architected, and ready for deployment
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

**Prerequisites:** Story 1.10 (blackphos migration complete, cinnabar user configured, dendritic patterns established)

**Optional Prerequisites:** Story 1.11 (type-safe home-manager architecture - enhances but not required for deployment)

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
