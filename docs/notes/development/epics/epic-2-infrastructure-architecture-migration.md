# Epic 2: Infrastructure Architecture Migration (Apply test-clan patterns to infra)

**Status:** Contexted (ready for Phase 1 story drafting)
**Dependencies:** Epic 1 complete ✅
**Strategy:** "Rip the Band-Aid" - copy validated patterns from test-clan → infra
**Timeline:** 4 phases, 14 stories (13 required + 1 optional), estimated 80-120 hours

---

## Epic Goal

Migrate the infra repository from nixos-unified architecture to dendritic flake-parts + clan-core architecture by applying all validated patterns from Epic 1's test-clan repository.

**Key Outcomes:**
- Home-manager migrated to Pattern A (dendritic aggregates) for all users
- Blackphos and stibnite configs migrated to dendritic+clan architecture
- Cinnabar and electrum VPS configs migrated from test-clan to infra
- Future machine configs created (rosegold, argentum)
- All infra-specific components preserved (CI/CD, TypeScript monorepo, Cloudflare)

---

## Migration Strategy: "Rip the Band-Aid"

**Approach:**
1. Create fresh `clan-01` branch in infra repository
2. Copy relevant files from test-clan → infra using `cp` (filesystem operations)
3. Modify/refactor additional files as needed
4. Validate at each phase boundary

**Preserve from infra:**
- GitHub Actions CI/CD workflows
- TypeScript monorepo (docs website at docs.cameronraysmith.com)
- Cloudflare deployment setup

**Replace from test-clan:**
- All nix configurations (flake.nix, modules/, hosts/, home-manager/)
- Dendritic flake-parts structure
- Clan inventory and service instances
- Sops-nix secrets architecture

**Philosophy:** Fast and pragmatic > slow and careful.
Epic 1 was discovery/validation, Epic 2 is application of proven patterns.
Trust git branch/diff/history as safety net.

---

## Phase 1: Home-Manager Migration Foundation (3-4 stories)

**Goal:** Migrate home-manager configuration to dendritic+clan Pattern A

**Affects:** ALL hosts (foundation layer for everything else)

### Story 2.1: Identify infra-specific components to preserve

As a system administrator,
I want to identify all infra-specific components that must be preserved during migration,
So that I ensure GitHub Actions, TypeScript monorepo, and Cloudflare deployment remain intact.

**Acceptance Criteria:**
1. Scan `.github/workflows/` and document all CI/CD workflows with descriptions
2. Document TypeScript monorepo structure: package locations, build scripts, dependencies
3. Document Cloudflare deployment configuration: wrangler.toml location, deployment targets
4. Identify any other infra-unique infrastructure (scripts, tooling, documentation)
5. Create preservation checklist mapping component → file paths → migration action (preserve/adapt/replace)
6. Document which files in infra must NOT be overwritten by test-clan files
7. Checklist reviewed and approved for use in Story 2.3 branch creation

**Prerequisites:** Epic 1 complete

---

### Story 2.2: Prepare clan-01 branch for migration

As a system administrator,
I want to create and prepare the `clan-01` branch for Epic 2 wholesale migration execution,
So that I have a clean, documented checkpoint before applying destructive config replacement from test-clan.

**Context:**

Epic 2 uses a "rip the band-aid" migration strategy: create fresh `clan-01` branch, copy validated nix configs from test-clan → infra, preserve infra-specific components per Story 2.1 checklist.

**Acceptance Criteria:**
1. Create clan-01 branch from clan HEAD with clean working directory
2. Verify branch created successfully with zero divergence from parent
3. Document branch purpose and Epic 2 migration strategy
4. Confirm Story 2.1 preservation checklist available for Story 2.3 reference
5. Prepare Story 2.3 execution readiness (git status clean, branch documented)

**Prerequisites:** Story 2.1 (preservation checklist complete)

---

### Story 2.3: Home-manager Pattern A migration

As a system administrator,
I want to migrate infra home-manager configuration to dendritic+clan Pattern A,
So that all hosts use the validated architectural pattern from Epic 1.

**Acceptance Criteria:**
1. Create `clan-01` branch in infra repository
2. Copy home-manager configuration from test-clan → infra: `modules/homeManager/` directory structure (Pattern A aggregates)
3. Migrate LazyVim-module → lazyvim-nix: Replace custom LazyVim module with upstream flake input (Epic 1 improvement)
4. Migrate user modules: crs58, cameron, raquel, christophersmith, janettesmith to Pattern A structure
5. Preserve infra-specific components per Story 2.1 checklist: `.github/`, TypeScript monorepo, Cloudflare config
6. Validate home-manager builds for all users across all platforms: `nix build .#homeConfigurations.<user>@<platform>.activationPackage`
7. Compare package counts: pre-migration vs post-migration (zero-regression validation)

**Prerequisites:** Story 2.2 (diff analysis complete)

---

### Story 2.4: Home-manager secrets migration

As a system administrator,
I want to migrate home-manager secrets to the two-tier sops-nix architecture,
So that user secrets are properly encrypted and independently managed per user.

**Acceptance Criteria:**
1. Copy sops-nix two-tier architecture from test-clan → infra: System-level (clan vars) + user-level (sops-nix)
2. Migrate user secrets: crs58, raquel independent age keypairs and secret definitions
3. Validate age key reuse pattern: Same keypair for clan vars + sops-nix (Epic 1 pattern)
4. Test secrets decryption on darwin platforms: `sops -d sops/users/<user>/secrets.yaml`
5. Test secrets decryption on nixos platforms: Validate deployment to /run/secrets/
6. Document secret migration process for future users (christophersmith, janettesmith)
7. Validate all existing secrets preserved: SSH keys, API tokens, credentials

**Prerequisites:** Story 2.3 (Pattern A migration complete)

---

## Phase 2: Active Darwin Workstations - blackphos + stibnite (4-5 stories)

**Goal:** Migrate blackphos and stibnite to dendritic+clan architecture

**Affects:** Primary development workstations (crs58, raquel)

### Story 2.5: Blackphos config migration to infra

As a system administrator,
I want to migrate blackphos configuration from test-clan to infra,
So that blackphos can be managed from production infra repository with full feature parity.

**Acceptance Criteria:**
1. Copy blackphos configuration from test-clan → infra: `modules/hosts/blackphos/` and darwin-specific modules
2. Ensure 270 packages preserved: Compare package list from test-clan blackphos vs infra blackphos (zero-regression)
3. Validate zerotier darwin integration: Homebrew cask + activation script pattern from Epic 1
4. Test nix-darwin build success: `nix build .#darwinConfigurations.blackphos.system`
5. Validate raquel user configuration: Home-manager modules, secrets, overlays all present
6. Test configuration evaluation: `nix eval .#darwinConfigurations.blackphos.config.system.build.toplevel --json`
7. Document any infra-specific adaptations needed for blackphos

**Prerequisites:** Story 2.4 (secrets migration complete)

---

### Story 2.6: Stibnite config migration

**Note:** This story includes configuration diff analysis between stibnite and blackphos as Task 1 (originally planned as separate Story 2.2 "diff analysis", now absorbed here as preparatory work for stibnite migration).

As a system administrator,
I want to migrate stibnite configuration to dendritic+clan architecture,
So that stibnite uses validated patterns while preserving all unique configuration.

**Acceptance Criteria:**
1. Apply dendritic+clan architecture to stibnite: Use blackphos as structural template
2. Apply configuration differences from Story 2.2 analysis: Packages, services, hardware, user settings
3. Preserve all stibnite-specific packages and services: Validate against pre-migration package list
4. Validate nix-darwin build success: `nix build .#darwinConfigurations.stibnite.system`
5. Validate crs58 user configuration: Primary workstation packages, development environment, secrets
6. Test configuration evaluation: `nix eval .#darwinConfigurations.stibnite.config.system.build.toplevel --json`
7. Document stibnite-specific patterns and distinctions for future reference

**Prerequisites:** Story 2.5 (blackphos migration complete)

---

### Story 2.7: Activate blackphos and stibnite from infra

As a system administrator,
I want to deploy blackphos and stibnite from infra `clan-01` branch,
So that both workstations are operational under production infra management.

**Acceptance Criteria:**
1. Deploy blackphos from infra `clan-01` branch: `darwin-rebuild switch --flake .#blackphos` (switch from test-clan → infra)
2. Deploy stibnite from infra `clan-01` branch: `darwin-rebuild switch --flake .#stibnite`
3. Validate raquel's workflow on blackphos: 270 packages functional, development environment operational, no regressions
4. Validate crs58's workflow on stibnite: Primary workstation operational, all tools accessible, no regressions
5. Confirm zerotier mesh VPN connectivity: All machines (cinnabar, electrum, blackphos, stibnite) reachable via zerotier
6. Test SSH access: Bidirectional SSH between all machines via zerotier network
7. Monitor stability for 24-48 hours: No critical errors, all workflows functional

**Prerequisites:** Story 2.6 (stibnite migration complete)

---

### Story 2.8: Cleanup unused darwin configs

As a system administrator,
I want to remove obsolete darwin configurations from infra,
So that the repository contains only active, maintained configurations.

**Acceptance Criteria:**
1. Remove `blackphos-nixos` configuration: Obsolete (blackphos is darwin, not nixos)
2. Remove `stibnite-nixos` configuration: Obsolete (stibnite is darwin, not nixos)
3. Remove `rosegold-old` configuration: Obsolete (will be recreated in Phase 4 with dendritic+clan architecture)
4. Update flake.nix to remove obsolete outputs: Clean up nixosConfigurations entries
5. Validate flake evaluation after cleanup: `nix flake check` succeeds
6. Update documentation: Remove references to obsolete configurations
7. Commit cleanup changes: Atomic commit with clear rationale

**Prerequisites:** Story 2.7 (blackphos + stibnite activated)

---

## Phase 3: VPS Migration - cinnabar + electrum (2-3 stories)

**Goal:** Migrate cinnabar and electrum configs from test-clan to infra

**Note:** VMs already deployed and operational in test-clan - this is config migration only

### Story 2.9: Cinnabar config migration

As a system administrator,
I want to migrate cinnabar configuration from test-clan to infra,
So that cinnabar VPS is managed from production infra repository.

**Acceptance Criteria:**
1. Copy cinnabar configuration from test-clan → infra: `modules/hosts/cinnabar/` and nixos-specific modules
2. Preserve zerotier controller configuration: Network ID db4344343b14b903, controller role
3. Validate nixos build success: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
4. Test SSH access from darwin workstations: `ssh root@<cinnabar-zerotier-ip>` succeeds
5. Validate clan vars deployment: `/run/secrets/` contains SSH keys, proper permissions
6. Test zerotier controller status: `zerotier-cli info` shows controller operational
7. Document cinnabar-specific infrastructure: Hetzner Cloud, LUKS encryption, disko layout

**Prerequisites:** Story 2.8 (cleanup complete)

---

### Story 2.10: Electrum config migration

As a system administrator,
I want to migrate electrum configuration from test-clan to infra,
So that electrum VPS is managed from production infra repository.

**Acceptance Criteria:**
1. Copy electrum configuration from test-clan → infra: `modules/hosts/electrum/` and nixos-specific modules
2. Preserve zerotier peer configuration: Network ID db4344343b14b903, peer role
3. Validate nixos build success: `nix build .#nixosConfigurations.electrum.config.system.build.toplevel`
4. Test zerotier mesh connectivity: Cinnabar controller ↔ electrum peer ↔ darwin peers (blackphos, stibnite)
5. Validate bidirectional SSH access: All machines can SSH to each other via zerotier
6. Test clan vars deployment: `/run/secrets/` contains SSH keys, proper permissions
7. Document electrum-specific infrastructure: Hetzner Cloud, LUKS encryption, disko layout

**Prerequisites:** Story 2.9 (cinnabar migration complete)

---

## Phase 4: Infrastructure Validation and Future Machines (4 stories)

**Goal:** Validate test harness, consolidate technical debt, then create rosegold and argentum configurations in infra

**Note:** Test harness and consolidation prepare infrastructure before new machine configs (rosegold/argentum don't exist in test-clan - will be created based on validated patterns)

### Story 2.11: Test harness and CI validation

As a system administrator,
I want to validate and update the test harness and CI workflow for the dendritic flake-parts + clan architecture,
So that infra repository has continuous validation aligned with the 4-host fleet (stibnite, blackphos, cinnabar, electrum).

**Acceptance Criteria:**
1. Validate existing checks (modules/checks/): Confirm 20+ implemented checks pass with `nix flake check`
2. Add stibnite to explicit validation: Ensure stibnite darwin config has check coverage (not just via clan inventory)
3. Fix CI matrix orphans: Remove non-existent `blackphos-nixos`, `stibnite-nixos`, `orb-nixos` from ci.yaml matrix
4. Add VPS builds to CI: Add cinnabar and electrum nixosConfigurations to CI build matrix
5. Update home config testing: Align CI home config expectations with actual users (cameron, raquel, crs58)
6. Preserve content-addressed job caching: Ensure new/modified jobs follow the `cached-ci-job` pattern with accurate `hash-sources` closures (see `.github/actions/cached-ci-job/`)
7. Execute CI validation: Run `gh workflow run ci.yaml --ref clan-01` and verify all jobs pass
8. Document test execution: Update or create testing documentation with current check inventory

**Prerequisites:** Story 2.10 (electrum migration complete)

**Estimated Effort:** 4-6 hours

**Risk Level:** MEDIUM (CI changes could break main branch if not careful)

**Key Files:**
- modules/checks/nix-unit.nix (11 tests)
- modules/checks/validation.nix (7 checks)
- modules/checks/integration.nix (2 tests)
- .github/workflows/ci.yaml (13 jobs, 1105 lines)

**Critical Pattern: Content-Addressed Job Caching**

The CI uses `.github/actions/cached-ci-job` for job-level result caching based on input file closures. New/modified jobs MUST:
- Call `cached-ci-job` early (before expensive setup)
- Specify accurate `hash-sources` globs (only files affecting job outcome)
- Include matrix values in `check-name` for matrix jobs
- Gate expensive steps with `if: steps.cache.outputs.should-run == 'true'`
- Create result markers and save to cache on success

---

### Story 2.12: Consolidate agents-md module duplication

As a system administrator,
I want to consolidate agents-md module duplication in infra home-manager configuration,
So that the codebase maintains single source of truth for module definitions.

**Acceptance Criteria:**
1. Replace cameron.nix inline module (lines 93-126) with `../../../home/modules/_agents-md.nix` import: Follow blackphos pattern (raquel user already uses relative import)
2. Replace crs58.nix inline module (lines 91-124) with `../../../home/modules/_agents-md.nix` import: Same consolidation pattern
3. Validate home-manager builds for cameron and crs58 users: Zero regressions (`nix build .#homeConfigurations.cameron.activationPackage`, `nix build .#homeConfigurations.crs58.activationPackage`)
4. Test functionality: CLAUDE.md, AGENTS.md, GEMINI.md, CRUSH.md, OPENCODE.md files generated correctly in home directories
5. Verify pattern matches blackphos: Raquel user already uses relative import pattern, cameron and crs58 should match
6. Result: 68 lines eliminated (34 per user), single source of truth maintained
7. Document consolidation in commit message: Explain why duplication existed (clan inventory limitation during initial migration) and why consolidation is safe now

**Prerequisites:** Story 2.11 (test harness migration complete)

**Priority:** LOW (technical debt cleanup, not blocking functionality)
**Effort:** 1-2 hours
**Risk:** VERY LOW (blackphos proves pattern works, test harness validates zero regressions)

**Note:** This story addresses technical debt inherited from test-clan where cameron.nix and crs58.nix users duplicated the agents-md option module inline instead of importing it like blackphos (raquel) does. Epic 1 validated the pattern works; this story cleans up the duplication post-migration.

---

### Story 2.13: Rosegold configuration creation

As a system administrator,
I want to create rosegold darwin configuration in infra,
So that rosegold is ready for deployment in Epic 3.

**Acceptance Criteria:**
1. Create rosegold darwin configuration: Use blackphos/stibnite as structural template
2. Configure for user janettesmith: Home-manager modules, user secrets, appropriate packages
3. Apply dendritic+clan architecture patterns: Modules, clan inventory, service instances
4. Validate nix-darwin build success: `nix build .#darwinConfigurations.rosegold.system` (deployment deferred to Epic 3)
5. Configure zerotier peer role: Network ID db4344343b14b903, peer role for rosegold
6. Test configuration evaluation: `nix eval .#darwinConfigurations.rosegold.config.system.build.toplevel --json`
7. Document rosegold-specific configuration: User preferences, package selections, hardware details

**Prerequisites:** Story 2.12 (consolidation complete)

---

### Story 2.14: Argentum configuration creation

As a system administrator,
I want to create argentum darwin configuration in infra,
So that argentum is ready for deployment in Epic 4.

**Acceptance Criteria:**
1. Create argentum darwin configuration: Use blackphos/stibnite as structural template
2. Configure for user christophersmith: Home-manager modules, user secrets, appropriate packages
3. Apply dendritic+clan architecture patterns: Modules, clan inventory, service instances
4. Validate nix-darwin build success: `nix build .#darwinConfigurations.argentum.system` (deployment deferred to Epic 4)
5. Configure zerotier peer role: Network ID db4344343b14b903, peer role for argentum
6. Test configuration evaluation: `nix eval .#darwinConfigurations.argentum.config.system.build.toplevel --json`
7. Document argentum-specific configuration: User preferences, package selections, hardware details

**Prerequisites:** Story 2.13 (rosegold creation complete)

---

## Dependencies

**Depends on Epic 1:**
- ✅ Dendritic flake-parts patterns validated (Stories 1.1-1.7)
- ✅ Clan-core inventory and service instances proven (Stories 1.3, 1.9, 1.12)
- ✅ Home-manager Pattern A at scale (Stories 1.8A, 1.10BA-1.10E)
- ✅ Sops-nix two-tier secrets architecture (Stories 1.10A, 1.10C)
- ✅ Five-layer overlay architecture (Stories 1.10D-1.10DB)
- ✅ Zerotier heterogeneous networking (Stories 1.9, 1.12)
- ✅ Comprehensive documentation (Story 1.13, 3,000+ lines)

**Enables:**
- Epic 3: Rosegold deployment and multi-darwin validation
- Epic 4: Argentum deployment
- Epic 5: Extended stibnite validation [OPTIONAL - execute if Epic 2 Phase 2 shows instability]
- Epic 6: Legacy cleanup

---

## Success Criteria

- ✅ All 14 stories completed with acceptance criteria met (13 required + 1 optional)
- ✅ Infra repository using dendritic+clan architecture across all machines
- ✅ Blackphos and stibnite operational from infra (switched from test-clan)
- ✅ Cinnabar and electrum configs migrated to infra
- ✅ Rosegold and argentum configs created and validated
- ✅ All infra-specific components preserved (CI/CD, TypeScript, Cloudflare)
- ✅ Test harness passing (zero regressions)
- ✅ `clan-01` branch ready for merge to main

---

## Risk Mitigation

- **Git safety net:** `clan-01` branch isolation, can abandon if issues
- **Incremental validation:** Phase boundaries with validation gates
- **Zero-regression principle:** Test harness validates after each story
- **Proven patterns:** All architecture from Epic 1 HIGH confidence validation
- **Preservation checklist:** Story 2.1 ensures infra-unique components safe

---

## Estimated Effort

- Phase 1 (Home-manager foundation): 20-30 hours
- Phase 2 (Darwin workstations): 25-35 hours
- Phase 3 (VPS migration): 15-20 hours
- Phase 4 (Future machines): 20-35 hours

**Total:** 80-120 hours across 12-15 stories

---

**References:**
- Epic 1 Retrospective: `docs/notes/development/epic-1-retro-2025-11-20.md`
- Sprint Change Proposal: `docs/notes/development/sprint-change-proposal-2025-11-20.md`
- Test-clan patterns: `~/projects/nix-workspace/test-clan/docs/guides/`
- Architecture docs: `docs/notes/development/architecture/`
