---
title: "infra - Epic Breakdown"
---

**Author:** Dev
**Date:** 2025-11-03
**Project Level:** Level 3 (brownfield infrastructure migration)
**Target Scale:** 5 machines (1 VPS + 4 darwin workstations)

---

## Overview

This document provides the detailed epic breakdown for the nix-config infrastructure migration from nixos-unified to dendritic flake-parts pattern with clan-core integration.

The migration follows a validation-first, 6-phase progressive rollout strategy with explicit go/no-go decision gates and 1-2 week stability validation windows between phases.

Each epic includes:

- Expanded goal and value proposition
- Complete story breakdown with user stories
- Acceptance criteria for each story
- Story sequencing and dependencies

**Epic Sequencing Principles:**

- Epic 1 (Phase 0) validates architectural combination in test environment before infrastructure commitment
- Epic 2 (Phase 1) deploys VPS foundation using validated patterns
- Epics 3-6 (Phases 2-5) progressively migrate darwin hosts with stability gates
- Epic 7 (Phase 6) removes legacy infrastructure after complete migration
- Stories within epics are vertically sliced and sequentially ordered
- No forward dependencies - each story builds only on previous work

---

## Epic 1: Architectural Validation + Migration Pattern Rehearsal (Phase 0)

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

### Story 1.1: Setup test-clan repository with terraform/terranix infrastructure

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

### Story 1.2: Implement dendritic flake-parts pattern in test-clan (OPTIONAL)

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

### Story 1.3: Configure clan inventory with Hetzner and GCP VM definitions

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

### Story 1.4: Create Hetzner VM terraform configuration and host modules

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

### Story 1.5: Deploy Hetzner VM and validate infrastructure stack

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

### Story 1.6: Implement comprehensive test harness for test-clan infrastructure validation

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

### Story 1.7: Execute dendritic flake-parts refactoring in test-clan using test harness

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

### Story 1.8: Migrate blackphos from infra to test-clan management

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

### Story 1.8A: Extract Portable Home-Manager Modules for Cross-Platform User Config Sharing

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

**Prerequisites:** Story 1.8 (configuration builds, inline configs identified as gap)

**Blocks:** Story 1.9 (cinnabar needs crs58 module), Story 1.10 (network validation needs shared config)

**Estimated Effort:** 2-3 hours (well-scoped, pattern proven in infra)

**Risk Level:** Low (refactoring only, builds already validated)

**Strategic Value:** Restores proven capability from infra, unblocks Epic 1-6 progression, enables DRY principle for 6 machines

---

### Story 1.9: Rename Hetzner VMs to cinnabar/electrum and establish zerotier network

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

### Story 1.10: Integrate blackphos into test-clan zerotier network

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

### Story 1.11: Document integration findings and architectural decisions

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

### Story 1.12: Execute go/no-go decision framework for production refactoring

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

## Epic 2: VPS Infrastructure Foundation (Phase 1 - cinnabar)

**Goal:** Deploy always-on Hetzner Cloud VPS infrastructure using validated patterns from Phase 0, establishing foundation for darwin host coordination

**Strategic Value:** Validates complete stack (dendritic + clan + terraform + infrastructure) on NixOS before darwin, provides stable zerotier controller independent of workstation power state, proves patterns on clan's native platform

**Timeline:** 1-2 weeks deployment + 1-2 weeks stability validation

**Success Criteria:**
- Hetzner Cloud VPS deployed and operational
- Complete infrastructure stack validated (terraform, disko, LUKS, zerotier, NixOS)
- Zerotier controller functional and reachable
- SSH access working with certificate-based authentication
- Clan vars deployed correctly to /run/secrets/
- Stable for 1-2 weeks minimum before Phase 2

**Note:** This phase transitions from test-clan (experimental) to production nix-config repository on clan branch.

---

### Story 2.1: Apply Phase 0 patterns to nix-config and setup terraform/terranix

As a system administrator,
I want to apply validated patterns from test-clan to production nix-config repository,
So that I can begin deploying real infrastructure with proven architectural patterns.

**Acceptance Criteria:**
1. nix-config repository on clan branch has flake inputs added: clan-core, import-tree, terranix, disko, srvos (following clan-core, flake-parts, nixpkgs)
2. modules/ directory created with dendritic structure: modules/base/, modules/hosts/, modules/flake-parts/, modules/terranix/
3. modules/flake-parts/clan.nix created with clan.meta.name = "nix-config"
4. Terranix flake module imported in flake.nix
5. modules/terranix/base.nix created with Hetzner Cloud provider configuration
6. Hetzner API token secret prepared for terraform authentication
7. Flake evaluates successfully: `nix flake check`

**Prerequisites:** Story 1.6 (Phase 0 GO/CONDITIONAL GO decision)

---

### Story 2.2: Create cinnabar host configuration with disko and LUKS

As a system administrator,
I want to create cinnabar NixOS configuration with declarative disk partitioning and encryption,
So that the VPS has secure storage and reproducible disk layout.

**Acceptance Criteria:**
1. modules/hosts/cinnabar/default.nix created using validated dendritic patterns from Phase 0
2. modules/hosts/cinnabar/disko.nix created with LUKS encryption configuration for root partition
3. Cinnabar added to clan inventory: tags = ["nixos" "vps" "cloud"], machineClass = "nixos"
4. Base system configuration applied: networking.hostName = "cinnabar", nix settings, state version
5. srvos hardening modules imported for server security baseline
6. Configuration builds successfully: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
7. Disko configuration validates: able to generate partitioning commands

**Prerequisites:** Story 2.1 (nix-config setup with terraform)

---

### Story 2.3: Configure zerotier controller and essential clan services for cinnabar

As a system administrator,
I want to configure zerotier controller role and essential services on cinnabar,
So that the VPS provides always-on network coordination and core infrastructure services.

**Acceptance Criteria:**
1. Clan service instance zerotier-local configured with controller role on cinnabar machine
2. Clan service instance sshd-clan configured with server role on cinnabar, client role on all machines
3. Clan service instance emergency-access configured with default role (not on VPS, workstations only)
4. Clan service instance users-root configured for cinnabar root user access
5. Zerotier network ID prepared/documented for use across all machines
6. SSH CA certificate configuration included in sshd-clan instance
7. Service instance configuration validates in clan inventory: `nix eval .#clan.inventory.instances --json | jq .`

**Prerequisites:** Story 2.2 (cinnabar host configuration)

---

### Story 2.4: Initialize clan secrets and generate vars for cinnabar

As a system administrator,
I want to initialize clan secrets infrastructure and generate vars for cinnabar,
So that the VPS has properly encrypted secrets deployed via clan vars system.

**Acceptance Criteria:**
1. Clan secrets initialized in nix-config: age keys generated for admins group
2. User age key added to admins group: `clan secrets groups add-user admins <username>`
3. Hetzner API token added as clan secret for terraform authentication
4. Clan vars generated for cinnabar: `nix run nixpkgs#clan-cli -- vars generate cinnabar`
5. SSH host keys generated in sops/machines/cinnabar/secrets/sshd.* (encrypted)
6. Zerotier identity generated if needed
7. All vars generation succeeds without errors
8. Vars structure validated: sops/machines/cinnabar/{secrets,facts}/ populated

**Prerequisites:** Story 2.3 (clan services configured)

---

### Story 2.5: Deploy cinnabar VPS via terraform and clan machines install

As a system administrator,
I want to provision cinnabar on Hetzner Cloud and install NixOS,
So that the VPS infrastructure is operational and ready for validation.

**Acceptance Criteria:**
1. Terraform configuration generated: `nix run .#terraform.terraform -- init`
2. Terraform plan reviewed: `nix run .#terraform.terraform -- plan`
3. VPS provisioned on Hetzner Cloud CX53: `nix run .#terraform.terraform -- apply`
4. SSH access confirmed to fresh VPS with terraform-provided credentials
5. NixOS installed via clan: `clan machines install cinnabar` (automated installation with disko partitioning)
6. System boots successfully with LUKS encryption
7. Able to SSH into cinnabar post-installation with clan-managed SSH keys
8. Initial system activation successful

**Prerequisites:** Story 2.4 (secrets and vars initialized)

---

### Story 2.6: Validate cinnabar infrastructure and zerotier controller

As a system administrator,
I want to validate all cinnabar infrastructure components are operational,
So that I can confirm the VPS foundation is stable before darwin host migration.

**Acceptance Criteria:**
1. SSH access functional: `ssh root@<cinnabar-zerotier-ip>` works with certificate-based auth
2. Zerotier controller operational: `ssh root@<cinnabar-ip> "zerotier-cli info"` shows controller status
3. Zerotier network created and accessible: `zerotier-cli listnetworks` shows network ID
4. Clan vars deployed correctly: `ssh root@<cinnabar-ip> "ls -la /run/secrets/"` shows sshd keys, proper permissions
5. Emergency access working if needed: root access recovery mechanism validated
6. System stable: no critical errors in journalctl logs
7. Terraform state preserved: able to run `terraform plan` and see no changes
8. Complete infrastructure stack validated: dendritic + clan + terraform + hetzner + disko + LUKS + zerotier + NixOS all operational

**Stability gate:** Monitor cinnabar for 1-2 weeks. No critical issues → proceed to Phase 2 (blackphos migration)

**Prerequisites:** Story 2.5 (cinnabar deployed)

---

## Epic 3: First Darwin Migration (Phase 2 - blackphos)

**Goal:** Establish darwin migration patterns by converting blackphos to dendritic + clan, connecting to cinnabar zerotier network

**Strategic Value:** Proves darwin + clan integration works, creates reusable patterns for remaining hosts, validates multi-machine coordination between NixOS (cinnabar) and darwin (blackphos)

**Timeline:** 1 week migration + 1-2 weeks stability validation

**Success Criteria:**
- blackphos builds with dendritic + clan patterns
- All existing functionality preserved (zero-regression requirement)
- Zerotier peer connects to cinnabar controller
- SSH via zerotier network functional
- Clan vars deployed correctly
- Darwin patterns documented for reuse
- Stable for 1-2 weeks minimum before Phase 3

---

### Story 3.1: Convert darwin modules to dendritic flake-parts pattern for blackphos

As a system administrator,
I want to convert existing blackphos darwin modules to dendritic flake-parts organization,
So that blackphos uses the validated architectural pattern with proper module namespace.

**Acceptance Criteria:**
1. modules/darwin/ directory created with darwin-specific base modules (system settings, homebrew if used)
2. modules/homeManager/ directory created with home-manager modules (shell, dev tools) reusing patterns from test-clan
3. modules/hosts/blackphos/default.nix created defining blackphos-specific configuration
4. Host imports modules via config.flake.modules namespace: `imports = with config.flake.modules; [ darwin.base homeManager.shell ];`
5. All existing functionality from configurations/darwin/blackphos.nix preserved in new structure
6. Package lists compared: pre-migration vs post-migration identical
7. Configuration builds successfully: `nix build .#darwinConfigurations.blackphos.system`

**Prerequisites:** Story 2.6 (cinnabar stable for 1-2 weeks)

---

### Story 3.2: Add blackphos to clan inventory with zerotier peer role

As a system administrator,
I want to add blackphos to clan inventory and configure zerotier peer role,
So that blackphos connects to cinnabar controller and joins the zerotier network.

**Acceptance Criteria:**
1. blackphos added to clan inventory in modules/flake-parts/clan.nix: tags = ["darwin" "workstation"], machineClass = "darwin"
2. Zerotier service instance zerotier-local includes blackphos with peer role (cinnabar remains controller)
3. sshd-clan service instance includes blackphos with server + client roles
4. emergency-access service instance includes blackphos with default role
5. users-crs58 service instance includes blackphos with default role for user configuration
6. Clan inventory evaluates successfully: `nix eval .#clan.inventory.machines.blackphos --json`
7. Zerotier network ID from cinnabar configured for peer connection

**Prerequisites:** Story 3.1 (darwin modules converted)

---

### Story 3.3: Generate clan vars and deploy blackphos configuration

As a system administrator,
I want to generate clan vars for blackphos and deploy the configuration,
So that blackphos is operational with clan-managed secrets and joined to the zerotier network.

**Acceptance Criteria:**
1. Clan vars generated for blackphos: `clan vars generate blackphos`
2. SSH host keys generated in sops/machines/blackphos/secrets/
3. User secrets generated if configured
4. Configuration deployed: `darwin-rebuild switch --flake .#blackphos`
5. Deployment succeeds without errors
6. Zerotier service starts and joins network automatically
7. Vars deployed to /run/secrets/ with correct darwin-compatible permissions
8. System activation successful, all services operational

**Prerequisites:** Story 3.2 (inventory configured)

---

### Story 3.4: Validate blackphos functionality and network connectivity

As a system administrator,
I want to validate all blackphos functionality and network connectivity to cinnabar,
So that I can confirm the darwin migration pattern works end-to-end.

**Acceptance Criteria:**
1. All existing functionality preserved: development tools, shell configuration, system services, homebrew if used
2. Zero-regression validation: compare package lists, test all workflows
3. Zerotier peer connected: `zerotier-cli status` shows network membership
4. Network communication functional: `ping <cinnabar-zerotier-ip>` succeeds
5. SSH via zerotier works: `ssh root@<cinnabar-zerotier-ip>` succeeds with certificate-based auth
6. From cinnabar, can SSH to blackphos: `ssh crs58@<blackphos-zerotier-ip>`
7. Clan vars accessible: `ls -la /run/secrets/` shows deployed secrets
8. No regressions in daily development workflow on blackphos

**Prerequisites:** Story 3.3 (blackphos deployed)

---

### Story 3.5: Document darwin patterns and monitor stability

As a system administrator,
I want to document the darwin migration patterns and monitor blackphos stability,
So that I have reusable patterns for rosegold and argentum migrations.

**Acceptance Criteria:**
1. DARWIN-PATTERNS.md created in docs/notes/development/ documenting:
   - Darwin module structure and organization
   - Clan inventory patterns for darwin machines
   - Zerotier peer role configuration for darwin
   - Vars generation and deployment for darwin
   - Common issues and solutions discovered
2. Module templates extracted showing reusable patterns
3. Host-specific vs. reusable patterns clearly distinguished
4. Stability monitoring checklist created for darwin hosts
5. blackphos monitored for 1-2 weeks with daily checks (system logs, zerotier connectivity, functionality)
6. No critical issues discovered during monitoring period
7. Patterns confirmed ready for rosegold migration

**Stability gate:** blackphos stable for 1-2 weeks with no critical issues → proceed to Phase 3 (rosegold)

**Prerequisites:** Story 3.4 (blackphos validated)

---

## Epic 4: Multi-Darwin Validation (Phase 3 - rosegold)

**Goal:** Validate darwin pattern reusability by migrating rosegold with minimal customization

**Strategic Value:** Confirms blackphos patterns are reusable, validates 3-machine zerotier network (cinnabar + 2 darwin hosts), tests multi-machine coordination

**Timeline:** 1 week migration + 1-2 weeks stability validation

**Success Criteria:**
- rosegold configuration builds using blackphos patterns with minimal changes
- Zerotier peer connects to cinnabar controller
- 3-machine network operational with full mesh connectivity
- Patterns validated as reusable
- Stable for 1-2 weeks minimum before Phase 4

---

### Story 4.1: Create rosegold configuration using blackphos patterns

As a system administrator,
I want to create rosegold configuration by reusing blackphos patterns,
So that I can validate pattern reusability with minimal customization.

**Acceptance Criteria:**
1. modules/hosts/rosegold/default.nix created by copying blackphos pattern
2. Only host-specific values changed: networking.hostName = "rosegold"
3. Module imports identical to blackphos (reusing darwin and homeManager modules)
4. Package lists copied from blackphos as baseline
5. Configuration builds successfully: `nix build .#darwinConfigurations.rosegold.system`
6. Diff between blackphos and rosegold configs minimal (only hostname and machine-specific values)
7. Pattern reusability confirmed: <10% customization needed beyond hostname

**Prerequisites:** Story 3.5 (blackphos stable, patterns documented)

---

### Story 4.2: Add rosegold to clan inventory and deploy

As a system administrator,
I want to add rosegold to clan inventory and deploy the configuration,
So that rosegold joins the multi-machine network.

**Acceptance Criteria:**
1. rosegold added to clan inventory: tags = ["darwin" "workstation"], machineClass = "darwin"
2. Zerotier peer role assigned to rosegold in zerotier-local instance
3. All service instances include rosegold (sshd-clan, emergency-access, users-crs58)
4. Clan vars generated for rosegold: `clan vars generate rosegold`
5. Configuration deployed: `darwin-rebuild switch --flake .#rosegold`
6. Deployment succeeds without errors
7. Zerotier peer connects to cinnabar controller automatically

**Prerequisites:** Story 4.1 (rosegold configuration created)

---

### Story 4.3: Validate 3-machine network and multi-darwin coordination

As a system administrator,
I want to validate the 3-machine zerotier network and coordination,
So that I can confirm multi-machine patterns work correctly.

**Acceptance Criteria:**
1. 3-machine network operational: cinnabar (controller) + blackphos (peer) + rosegold (peer)
2. Full mesh connectivity from rosegold: can ping cinnabar and blackphos via zerotier IPs
3. SSH works in all directions: rosegold ↔ blackphos, rosegold ↔ cinnabar, blackphos ↔ cinnabar
4. From cinnabar: `zerotier-cli listpeers | grep -E '(blackphos|rosegold)'` shows both peers
5. Clan vars deployed correctly on rosegold: /run/secrets/ populated
6. Multi-machine coordination validated: services deployed across machines via clan inventory
7. Network latency acceptable for development use
8. No new issues discovered compared to 2-machine network

**Stability gate:** rosegold stable for 1-2 weeks, 3-machine network stable → proceed to Phase 4 (argentum)

**Prerequisites:** Story 4.2 (rosegold deployed)

---

## Epic 5: Third Darwin Host (Phase 4 - argentum)

**Goal:** Final validation before primary workstation by migrating argentum

**Strategic Value:** Confirms patterns scale to 4 machines, validates 4-machine network stability, final validation before stibnite migration

**Timeline:** 1 week migration + 1-2 weeks stability validation

**Success Criteria:**
- argentum configuration builds using established patterns
- Zerotier peer connects to cinnabar controller
- 4-machine network operational
- No new issues discovered
- Stable for 1-2 weeks minimum, cumulative 4-6 weeks across all darwin hosts before Phase 5

---

### Story 5.1: Create argentum configuration and deploy to 4-machine network

As a system administrator,
I want to create argentum configuration and deploy to complete the 4-machine network,
So that I can perform final validation before primary workstation migration.

**Acceptance Criteria:**
1. modules/hosts/argentum/default.nix created using proven blackphos/rosegold pattern
2. Only hostname changed: networking.hostName = "argentum"
3. argentum added to clan inventory: tags = ["darwin" "workstation"], machineClass = "darwin"
4. All service instances include argentum (zerotier peer, sshd, emergency-access, users)
5. Clan vars generated: `clan vars generate argentum`
6. Configuration builds: `nix build .#darwinConfigurations.argentum.system`
7. Deployment succeeds: `darwin-rebuild switch --flake .#argentum`
8. Zerotier peer connects to network automatically

**Prerequisites:** Story 4.3 (rosegold stable for 1-2 weeks)

---

### Story 5.2: Validate 4-machine network and assess stibnite readiness

As a system administrator,
I want to validate the 4-machine network and assess readiness for stibnite migration,
So that I can confirm the infrastructure is stable before migrating the primary workstation.

**Acceptance Criteria:**
1. 4-machine network operational: cinnabar + blackphos + rosegold + argentum
2. Full mesh connectivity from all machines: each machine can ping all others via zerotier
3. SSH functional in all directions with certificate-based authentication
4. From cinnabar: `zerotier-cli listpeers` shows 3 darwin peers connected
5. No new issues discovered with 4-machine network (patterns proven stable)
6. Network performance acceptable across all machines
7. Cumulative stability: blackphos 4-6+ weeks, rosegold 2-4+ weeks, argentum 1-2+ weeks
8. Readiness assessment for stibnite migration: all criteria met for Phase 5

**Stability gate:** argentum stable for 1-2 weeks, cumulative stability across all darwin hosts sufficient → stibnite migration approved

**Prerequisites:** Story 5.1 (argentum deployed)

---

## Epic 6: Primary Workstation Migration (Phase 5 - stibnite)

**Goal:** Migrate primary daily workstation to dendritic + clan after proven stability across all other hosts

**Strategic Value:** Completes 5-machine infrastructure with all productivity workflows intact, enables full multi-machine coordination

**Timeline:** 1 week preparation + 1 week migration + 1-2 weeks stability validation

**Success Criteria:**
- Pre-migration readiness checklist 100% complete
- stibnite operational with all daily workflows functional
- 5-machine zerotier network complete
- Productivity maintained or improved
- Stable for 1-2 weeks before Phase 6 cleanup

**Risk Level:** High (primary workstation, daily productivity critical)

---

### Story 6.1: Validate pre-migration readiness and create stibnite configuration

As a system administrator,
I want to validate all pre-migration readiness criteria and create stibnite configuration,
So that I can migrate the primary workstation with confidence and rollback capability.

**Acceptance Criteria:**
1. Pre-migration checklist validated:
   - blackphos stable for 4-6+ weeks (no issues)
   - rosegold stable for 2-4+ weeks (no issues)
   - argentum stable for 2-4+ weeks (no issues)
   - No outstanding bugs or pattern issues
   - All workflows tested on other hosts successfully
2. Full backup created: current stibnite configuration saved
3. Rollback procedure documented and tested on another host
4. Low-stakes timing confirmed: no important deadlines imminent
5. modules/hosts/stibnite/default.nix created using proven patterns
6. stibnite added to clan inventory: tags = ["darwin" "workstation" "primary"], machineClass = "darwin"
7. Configuration builds: `nix build .#darwinConfigurations.stibnite.system`

**Prerequisites:** Story 5.2 (argentum stable, readiness assessed)

---

### Story 6.2: Deploy stibnite and validate all daily workflows

As a system administrator,
I want to deploy stibnite configuration and validate all daily workflows immediately,
So that I can confirm the primary workstation is fully operational.

**Acceptance Criteria:**
1. Clan vars generated for stibnite: `clan vars generate stibnite`
2. Staged deployment executed: `darwin-rebuild switch --flake .#stibnite` (don't reboot immediately, test first)
3. Critical workflows validated immediately post-deployment:
   - Development environment: editors, IDEs, language environments, version control
   - Communication tools: browsers, chat applications if managed via nix
   - System services: essential background services operational
   - Shell configuration: fish, starship, aliases, functions
   - Performance: system responsiveness, build times acceptable
4. All existing functionality preserved (zero-regression validation)
5. Zerotier peer connects to cinnabar controller
6. SSH via zerotier works to all other machines
7. No critical issues discovered during initial validation
8. Reboot if needed, revalidate all workflows post-reboot

**Prerequisites:** Story 6.1 (readiness validated, configuration created)

---

### Story 6.3: Complete 5-machine network and monitor productivity

As a system administrator,
I want to validate the complete 5-machine network and monitor daily productivity on stibnite,
So that I can confirm the migration is successful before proceeding to cleanup.

**Acceptance Criteria:**
1. 5-machine zerotier network complete: cinnabar + blackphos + rosegold + argentum + stibnite
2. Full mesh connectivity from stibnite: can reach all 4 other machines via zerotier
3. SSH functional from/to stibnite across entire network
4. From cinnabar: `zerotier-cli listpeers` shows all 4 darwin peers connected
5. Multi-machine coordination operational: clan services deployed correctly across all 5 machines
6. Daily productivity monitoring (1-2 weeks):
   - All daily workflows functional every day
   - No regressions compared to pre-migration
   - Performance maintained or improved
   - Subjective productivity assessment: positive
7. System stable: no critical errors in logs
8. Complete migration validated: all hosts operational, patterns proven, ready for cleanup

**Stability gate:** stibnite stable for 1-2 weeks with productivity maintained → proceed to Phase 6 (cleanup)

**Prerequisites:** Story 6.2 (stibnite deployed and validated)

---

## Epic 7: Legacy Cleanup (Phase 6)

**Goal:** Remove nixos-unified infrastructure and finalize migration

**Strategic Value:** Clean dendritic + clan architecture, improved maintainability, migration complete

**Timeline:** 1 week cleanup + documentation

**Success Criteria:**
- nixos-unified completely removed
- Secrets migration strategy finalized (full or hybrid)
- Documentation updated and accurate
- Clean architecture with no legacy dependencies

---

### Story 7.1: Remove nixos-unified infrastructure

As a system administrator,
I want to remove all nixos-unified infrastructure from nix-config,
So that the codebase reflects clean dendritic + clan architecture.

**Acceptance Criteria:**
1. configurations/ directory deleted (host-specific nixos-unified configs no longer needed)
2. nixos-unified flake input removed from flake.nix
3. nixos-unified flakeModules imports removed from modules
4. All hosts verified building without nixos-unified: `nix flake check`
5. Git history preserved: commits clearly show removal with rationale
6. No references to nixos-unified remain in codebase
7. All 5 machines rebuild successfully after removal

**Prerequisites:** Story 6.3 (stibnite stable for 1-2 weeks, all hosts proven)

---

### Story 7.2: Finalize secrets migration strategy

As a system administrator,
I want to finalize the secrets migration strategy (full clan vars or hybrid),
So that secrets management is clean and well-documented.

**Acceptance Criteria:**
1. Secrets inventory completed: all secrets categorized (generated vs external)
2. Migration decision made: full clan vars or hybrid sops-nix + clan vars
3. If full migration: all remaining secrets migrated to clan vars, sops-nix removed
4. If hybrid approach: rationale documented, sops-nix configuration cleaned up for only external secrets
5. SECRETS-STRATEGY.md created documenting:
   - What secrets are managed where (clan vars vs sops-nix)
   - Rationale for approach chosen
   - Procedures for adding new secrets
   - Recovery procedures if secrets lost
6. All machines validated with final secrets configuration
7. Secrets management clean and maintainable

**Prerequisites:** Story 7.1 (nixos-unified removed)

---

### Story 7.3: Update documentation and finalize migration

As a system administrator,
I want to update all documentation to reflect completed migration,
So that the repository accurately represents the dendritic + clan architecture.

**Acceptance Criteria:**
1. README.md updated to reflect dendritic + clan architecture (remove nixos-unified references)
2. Migration experience documented in docs/notes/development/MIGRATION-RETROSPECTIVE.md:
   - What went well
   - Challenges encountered
   - Lessons learned
   - Time spent vs. estimates
   - Final assessment of dendritic + clan combination
3. Architectural decisions captured in docs/notes/development/ARCHITECTURE-DECISIONS.md:
   - Why dendritic + clan
   - Compromises made
   - Patterns adopted
   - Future considerations
4. Patterns documented for maintainability (reference for future work)
5. All 5 machines operational with no legacy dependencies
6. Migration declared complete, clan branch merged to main if appropriate
7. Retrospective completed: extract insights for future infrastructure work

**Prerequisites:** Story 7.2 (secrets finalized)

---

## Story Guidelines Reference

**Story Format:**

```
**Story [EPIC.N]: [Story Title]**

As a [user type],
I want [goal/desire],
So that [benefit/value].

**Acceptance Criteria:**
1. [Specific testable criterion]
2. [Another specific criterion]
3. [etc.]

**Prerequisites:** [Dependencies on previous stories, if any]
```

**Story Requirements:**

- **Vertical slices** - Complete, testable functionality delivery
- **Sequential ordering** - Logical progression within epic
- **No forward dependencies** - Only depend on previous work
- **AI-agent sized** - Completable in 2-4 hour focused session
- **Value-focused** - Integrate technical enablers into value-delivering stories
- **Zero-regression mandate** - All functionality must be preserved during migration

---

## Summary Statistics

**Total Epics:** 7 (aligned to 6 migration phases + cleanup)

**Total Stories:** 34 stories across all epics

**Story Distribution:**
- Epic 1 (Phase 0 - Architectural Validation + Migration Pattern Rehearsal): 12 stories
- Epic 2 (Phase 1 - cinnabar): 6 stories
- Epic 3 (Phase 2 - blackphos): 5 stories
- Epic 4 (Phase 3 - rosegold): 3 stories
- Epic 5 (Phase 4 - argentum): 2 stories
- Epic 6 (Phase 5 - stibnite): 3 stories
- Epic 7 (Phase 6 - cleanup): 3 stories

**Parallelization Opportunities:**
- Within Phase 0: Stories 1.1-1.3 must be sequential (foundation), Stories 1.4-1.6 must be sequential (Hetzner), Stories 1.7-1.9 must be sequential (GCP, depends on Hetzner), Story 1.10 blocks on calendar time (1 week) but can do documentation (1.11) in parallel, Stories 1.11-1.12 must be sequential
- Within Phase 1: Stories 2.1-2.5 must be sequential, documentation in 2.6 can be concurrent with stability monitoring
- Across phases: Each phase must complete before next begins (stability gates enforce sequencing)

**Estimated Timeline:**
- Conservative: 17-19 weeks (3-4 weeks Phase 0 + 1-2 weeks per remaining phase + stability gates)
- Aggressive: 7-9 weeks (if all phases proceed smoothly without issues)
- Realistic: 13-15 weeks (accounting for some issues but not major blockers)

**Critical Success Factors:**
- Phase 0 infrastructure deployment success (Epic 1, Stories 1.5 + 1.8)
- Phase 0 GO/CONDITIONAL GO decision (Epic 1, Story 1.12)
- Cinnabar VPS stability validation (Epic 2, Story 2.6)
- Darwin patterns proven reusable (Epic 3, Story 3.5)
- Pre-migration readiness for stibnite (Epic 6, Story 6.1)
- Zero-regression validation at every phase

---

**For implementation:** Use the `create-story` workflow to generate individual story implementation plans from this epic breakdown.

