# Epic 2: Infrastructure Architecture Migration (Apply test-clan patterns to infra)

**Status:** Contexted (ready for Phase 1 story drafting)
**Dependencies:** Epic 1 complete ✅
**Strategy:** "Rip the Band-Aid" - copy validated patterns from test-clan → infra
**Timeline:** 4 phases, 12-15 stories, estimated 80-120 hours

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

### Story 2.2: Stibnite vs blackphos configuration diff analysis

As a system administrator,
I want to understand all configuration differences between stibnite and blackphos,
So that I can accurately migrate stibnite while preserving its unique characteristics.

**Acceptance Criteria:**
1. Document package differences: Compare `environment.systemPackages` and home-manager packages between stibnite and blackphos
2. Document service/daemon differences: Compare system services, launchd agents, user services
3. Document hardware-specific configuration differences: Platform-specific settings, drivers, hardware configuration
4. Document user-specific settings: crs58 workflow differences (stibnite primary workstation vs blackphos raquel's workstation)
5. Create stibnite migration checklist highlighting critical distinctions that must be preserved
6. Identify any stibnite-specific modules or configurations not present in blackphos
7. Document findings in `docs/notes/development/stibnite-blackphos-diff-analysis.md`

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

## Phase 4: Future Machines - rosegold + argentum (3-4 stories)

**Goal:** Create rosegold and argentum configurations in infra

**Note:** These machines don't exist in test-clan - new configs based on validated patterns

### Story 2.11: Rosegold configuration creation

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

**Prerequisites:** Story 2.10 (electrum migration complete)

---

### Story 2.12: Argentum configuration creation

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

**Prerequisites:** Story 2.11 (rosegold creation complete)

---

### Story 2.13: Test harness migration and validation

As a system administrator,
I want to migrate test-clan test harness to infra and validate zero regressions,
So that infra repository has continuous validation for architectural invariants.

**Acceptance Criteria:**
1. Migrate test-clan test harness (18 tests) to infra: Copy test structure and nix-unit tests
2. Adapt tests for infra-specific structure: Update paths, machine names, module references
3. Validate all tests passing: `nix-unit --flake .#tests` shows zero failures
4. Test categories validated: Regression tests (12), invariant tests (2), feature tests (2), integration tests (2)
5. Document test execution: Create `docs/notes/development/testing.md` with test running instructions
6. Establish test as validation gate: Tests must pass before Epic 3+ progression
7. CI/CD integration: Add test execution to GitHub Actions workflow

**Prerequisites:** Story 2.12 (argentum creation complete)

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
- Epic 3 (was Epic 4): Rosegold deployment and multi-darwin validation
- Epic 4 (was Epic 5): Argentum deployment
- Epic 5 (was Epic 6): Extended stibnite validation [OPTIONAL]
- Epic 6 (was Epic 7): Legacy cleanup

---

## Success Criteria

- ✅ All 12-15 stories completed with acceptance criteria met
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
