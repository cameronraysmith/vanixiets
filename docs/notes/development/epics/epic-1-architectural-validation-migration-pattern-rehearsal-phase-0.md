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

## Story 1.10: Integrate blackphos into test-clan zerotier network

As a system administrator,
I want to integrate the blackphos nix-darwin machine into the test-clan zerotier network with cinnabar and electrum,
So that I can validate heterogeneous networking (nixos ↔ nix-darwin) and prove multi-platform coordination before production refactoring.

**Acceptance Criteria:**
1. Blackphos zerotier peer configuration: Zerotier service configured on blackphos (investigate nix-darwin zerotier module or homebrew workaround), Blackphos joins zerotier network as peer (cinnabar remains controller), Zerotier configuration uses nix-native approach where possible
2. Blackphos deployed to physical hardware: Configuration deployed to actual blackphos laptop: `darwin-rebuild switch --flake .#blackphos`, Deployment succeeds without errors, All existing functionality validated post-deployment
3. Heterogeneous network validated: 3-machine zerotier network operational (cinnabar + electrum + blackphos), Blackphos can ping both cinnabar and electrum via zerotier IPs, Both nixos VMs can ping blackphos via zerotier IP
4. Cross-platform SSH validated: SSH from blackphos to cinnabar/electrum works, SSH from cinnabar/electrum to blackphos works, Certificate-based authentication functional across platforms
5. Clan vars deployed correctly on blackphos: /run/secrets/ populated with proper permissions (darwin-compatible), SSH host keys functional, User secrets accessible
6. Zero-regression validation: All blackphos daily workflows functional, Development environment intact, No performance degradation
7. Zerotier workarounds documented: If nix-darwin zerotier module unavailable, document approach used (homebrew, custom module, etc.), Note any platform-specific issues encountered

**Prerequisites:** Story 1.9 (VMs renamed, zerotier network established)

**Estimated Effort:** 4-6 hours (includes zerotier darwin integration investigation)

**Risk Level:** Medium-High (deploying to real physical machine, zerotier darwin support uncertain)

**Strategic Value:** Proves heterogeneous networking (nixos ↔ nix-darwin) works, validates complete multi-platform coordination pattern for production fleet

**Note:** This story may require investigating zerotier-one installation on nix-darwin. Options include: native nix-darwin module (if available), custom clan service for darwin based on nixos zerotier service, homebrew-based installation managed via nix-darwin.

---

## Story 1.11: Document integration findings and architectural decisions

As a system administrator,
I want to document all integration findings and architectural decisions from Phase 0,
So that I have comprehensive reference for production refactoring in Epic 2+.

**Acceptance Criteria:**
1. Integration findings documented (in existing docs or new docs as appropriate): Terraform/terranix + clan integration (how it works, gotchas), Dendritic flake-parts pattern evaluation (proven via Stories 1.6-1.7), Nix-darwin + clan integration patterns (learned from Story 1.8), Home-manager integration approach with dendritic + clan, Heterogeneous zerotier networking (nixos ↔ nix-darwin from Story 1.10), Nixos-unified → dendritic + clan transformation process (from Story 1.8)
2. Architectural decisions documented (in existing docs or new docs as appropriate): Why dendritic flake-parts + clan combination, Why terraform/terranix for infrastructure provisioning, Why zerotier mesh (always-on coordination, VPN), Clan inventory patterns chosen, Service instance patterns (roles, targeting), Secrets management strategy (clan vars vs sops-nix), Home-manager integration approach
3. Confidence level assessed for each pattern: proven, needs-testing, uncertain
4. Recommendations for production refactoring: Specific steps to refactor infra from nixos-unified to dendritic + clan, Machine migration sequence and approach, Risk mitigation strategies based on test-clan learnings
5. Known limitations documented: Darwin-specific challenges, Platform-specific workarounds (if any), Areas requiring additional investigation

**Prerequisites:** Story 1.10 (blackphos integrated, heterogeneous networking validated)

**Estimated Effort:** 3-4 hours

**Risk Level:** Low (documentation only)

**Strategic Value:** Provides comprehensive blueprint for Epic 2+ production refactoring based on complete validation (nixos + nix-darwin + transformation pattern)

---

## Story 1.12: Execute go/no-go decision framework for production refactoring

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

**Prerequisites:** Story 1.11 (findings documented)

**Estimated Effort:** 1-2 hours

**Risk Level:** Low (decision only)

**Decision Criteria - GO if:** Hetzner VMs deployed and operational, Dendritic flake-parts pattern proven with zero regressions, Blackphos successfully migrated from nixos-unified to dendritic + clan, Heterogeneous zerotier network operational (nixos + darwin), Transformation pattern documented and reusable, High confidence in applying patterns to production

**Decision Criteria - CONDITIONAL GO if:** Minor platform-specific issues discovered but workarounds documented, Some manual steps required but acceptable, Partial automation acceptable with documented procedures, Medium-high confidence in production refactoring

**Decision Criteria - NO-GO if:** Critical failures in darwin integration, Transformation pattern unclear or too complex, Heterogeneous networking unreliable, Patterns not reusable for production, Major gaps in validation coverage

---
