# Story 1.9: Rename Hetzner VMs to cinnabar/electrum and establish zerotier network

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.8A (done): Portable home-manager modules extracted and validated

**Strategic Value:** Aligns test-clan infrastructure with production topology naming, establishes heterogeneous zerotier network foundation for Story 1.10 (darwin integration), prepares for migration of validated cinnabar/electrum configurations to infra repository in Epic 2+.

---

## Story Description

As a system administrator,
I want to rename the test Hetzner VMs to their intended production names (cinnabar and electrum) and establish a zerotier network between them,
So that the test-clan infrastructure mirrors the production topology that will be deployed in Epic 2+ and heterogeneous networking is validated.

**Context:**
Story 1.5 deployed hetzner-cx43 with zerotier controller configuration.
Story 1.8A extracted portable home-manager modules ready for cross-platform reuse.
This story renames test VMs to production names (cinnabar = primary VPS, electrum = secondary test VM) and establishes proper zerotier networking between them.
Story does NOT deploy crs58 user to cinnabar yet (that's future work - this story focuses on VM renaming and zerotier network establishment).

**Current Machine State (from test-clan/modules/terranix/hetzner.nix):**
- `hetzner-cx43`: **enabled = true** (actively deployed, has zerotier controller from Story 1.5) → will become **cinnabar**
- `hetzner-ccx23`: **enabled = false** (configuration exists but NOT deployed) → will become **electrum**

**Story 1.9 Scope:**
1. **Rename configurations**: hetzner-cx43 → cinnabar, hetzner-ccx23 → electrum
2. **Enable electrum in terranix**: Change `enabled = false` to `enabled = true` for electrum machine
3. **Deploy electrum VM**: Run terraform apply to provision electrum on Hetzner Cloud
4. **Configure zerotier on electrum**: Join cinnabar's zerotier network as peer
5. **Validate network**: Test nixos ↔ nixos zerotier connectivity (prepares for Story 1.10 darwin integration)
6. **Update all references**: Inventory, tests, docs to use production names

**Key Distinction:**
This story DOES deploy infrastructure (electrum VM) but does NOT deploy user configurations (no crs58 on cinnabar).
The zerotier foundation (controller on cinnabar) was laid in Story 1.5 - this story deploys the peer (electrum) and validates the network.

---

## Acceptance Criteria

### AC1: VMs renamed in test-clan configuration

- [ ] hetzner-cx43 → cinnabar (currently deployed, primary VPS, zerotier controller)
- [ ] hetzner-ccx23 → electrum (currently disabled, will be deployed, zerotier peer)
- [ ] All module paths updated to reflect new names
- [ ] Machine definitions use production names consistently
- [ ] No references to old names (hetzner-cx43, hetzner-ccx23) remain in configuration

**Files to update:**
- `modules/machines/nixos/hetzner-cx43/` → `modules/machines/nixos/cinnabar/`
- `modules/machines/nixos/hetzner-ccx23/` → `modules/machines/nixos/electrum/`
- `modules/clan/inventory/machines.nix` inventory machine keys
- `modules/clan/machines.nix` machine registration
- `modules/terranix/hetzner.nix` machine definitions

### AC2: Clan inventory updated with new machine names

- [ ] cinnabar machine definition:
  - `tags = ["nixos" "cloud" "hetzner" "controller"]`
  - `machineClass = "nixos"`
  - Role: zerotier controller
- [ ] electrum machine definition:
  - `tags = ["nixos" "cloud" "hetzner" "peer"]` or appropriate tags
  - `machineClass = "nixos"`
  - Role: zerotier peer
- [ ] Service instances updated:
  - `zerotier-local` roles reflect cinnabar as controller, electrum as peer
  - Other services (emergency-access, sshd-clan, users-root) target new names
- [ ] Inventory validates: `nix eval .#clan.inventory --json | jq '.machines | keys'` shows cinnabar and electrum

### AC3: Zerotier network established and documented

- [ ] Cinnabar configured as zerotier controller (from Story 1.5)
- [ ] Electrum configured as zerotier peer
- [ ] Both machines join the same zerotier network
- [ ] Network ID documented in README or relevant docs
- [ ] Zerotier configuration files reference production names

**Note:** Story 1.5 established zerotier controller on hetzner-vm.
This AC validates network still works after rename and electrum peer joins properly.

### AC4: Network connectivity validated between cinnabar and electrum

- [ ] Bidirectional ping: cinnabar → electrum via zerotier IPs
- [ ] Bidirectional ping: electrum → cinnabar via zerotier IPs
- [ ] SSH via zerotier: `ssh root@<cinnabar-zerotier-ip>` from electrum
- [ ] SSH via zerotier: `ssh root@<electrum-zerotier-ip>` from cinnabar
- [ ] Network latency acceptable (< 100ms for Hetzner-to-Hetzner)
- [ ] Zerotier status: `zerotier-cli info` shows online on both machines

### AC5: Configuration rebuilds successful with new names

- [ ] cinnabar builds: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
- [ ] electrum builds: `nix build .#nixosConfigurations.electrum.config.system.build.toplevel`
- [ ] No errors or warnings about missing references
- [ ] Clan vars regenerated for renamed machines if needed: `clan vars generate cinnabar`, `clan vars generate electrum`
- [ ] Configurations deployable (dry-run or actual deployment based on operational status)

### AC6: Test harness updated to reference new machine names

- [ ] All test files updated: cinnabar, electrum (no hetzner-vm, test-vm references)
- [ ] Regression tests passing: RT-1 (Terraform equivalence), RT-2 (NixOS closure), RT-3 (machine builds)
- [ ] Invariant tests passing: IT-1 (inventory structure), IT-2 (service targeting)
- [ ] Feature tests status unchanged: FT-1, FT-2 (dendritic features)
- [ ] Integration tests updated: VT-1 (VM boot tests) reference cinnabar and electrum
- [ ] Test runner handles new names: `./tests/run-all.sh` or `nix flake check`

### AC7: Documentation updated to reflect production topology

- [ ] README.md updated: cinnabar/electrum as test infrastructure names
- [ ] Architecture docs reference production topology
- [ ] Zerotier network ID documented
- [ ] Any troubleshooting guides updated with new names
- [ ] Story 1.5 zerotier deployment context preserved

---

## Implementation Tasks

### Task 1: Identify and catalog all files requiring rename updates (30 minutes)

**Objective:** Create comprehensive list of files referencing old VM names

**Actions:**
1. Search test-clan for old machine names:
   ```bash
   cd ~/projects/nix-workspace/test-clan
   rg "hetzner-vm" --files-with-matches
   rg "test-vm" --files-with-matches  # Or appropriate old name
   rg "hetzner-ccx23" --files-with-matches  # Check alternate naming
   ```
2. Create checklist of files to update:
   - Module directories in `modules/machines/nixos/`
   - `modules/flake-parts/clan.nix` inventory
   - Terranix configuration files
   - Test files in `modules/checks/`
   - Documentation files (README.md, architecture docs)
   - Any hardcoded references in module imports
3. Document current zerotier network configuration from Story 1.5
4. Verify no operational VMs at risk (check Story 1.7 notes about 162.55.175.87 and 49.13.140.183)

**Success Criteria:**
- Complete file list captured
- No files missed in search
- Zerotier configuration understood

### Task 2: Rename machine module directories (15 minutes)

**Objective:** Rename physical directories for machine modules

**Actions:**
1. Rename directories:
   ```bash
   cd ~/projects/nix-workspace/test-clan
   git mv modules/machines/nixos/hetzner-vm modules/machines/nixos/cinnabar
   git mv modules/machines/nixos/test-vm modules/machines/nixos/electrum  # Or appropriate old name
   ```
2. Update module `default.nix` files:
   - cinnabar: `networking.hostName = "cinnabar";`
   - electrum: `networking.hostName = "electrum";`
3. Verify no broken imports after directory rename

**Success Criteria:**
- Directories renamed
- Hostname configuration updated
- Git tracks rename properly

### Task 3: Update clan inventory with new machine names (30 minutes)

**Objective:** Update `modules/flake-parts/clan.nix` with production names

**Actions:**
1. Edit `modules/flake-parts/clan.nix`:
   - Replace `machines.hetzner-vm` with `machines.cinnabar`
   - Replace `machines.test-vm` with `machines.electrum`
   - Update tags: cinnabar gets `["nixos" "cloud" "hetzner" "controller"]`
   - Update tags: electrum gets `["nixos" "cloud" "hetzner" "peer"]`
2. Update service instances:
   - `zerotier-local.roles.controller.machines = [ "cinnabar" ];`
   - `zerotier-local.roles.peer.machines = [ "electrum" ];`
   - Update emergency-access, sshd-clan, users-root to reference new names
3. Validate inventory: `nix eval .#clan.inventory --json | jq '.machines | keys'`
4. Build configurations: `nix build .#nixosConfigurations.{cinnabar,electrum}.config.system.build.toplevel`

**Success Criteria:**
- Inventory references new names
- Service targeting uses new names
- Configurations build successfully

### Task 4: Update terranix configuration for new machine names (30 minutes)

**Objective:** Update terraform generation to reference production names and enable electrum

**Actions:**
1. Edit `modules/terranix/hetzner.nix`:
   - Rename machine keys: `hetzner-cx43` → `cinnabar`, `hetzner-ccx23` → `electrum`
   - **Enable electrum**: Change `electrum = { enabled = false; ...}` to `enabled = true;`
   - Update any resource references to use new names
2. Update terraform-generated identifiers if needed
3. Regenerate terraform: `nix build .#terranix.terraform`
4. Review generated `terraform.tf.json`:
   - Both cinnabar and electrum resources present
   - Resource names use production names
   - Provisioners reference new machine names

**Success Criteria:**
- Terranix configuration uses production names
- Electrum enabled for deployment
- Terraform regenerates without errors
- Both machines in generated config

### Task 5: Regenerate clan vars for renamed machines (20 minutes)

**Objective:** Ensure clan secrets/vars aligned with new machine names

**Actions:**
1. Check if vars need regeneration:
   ```bash
   cd ~/projects/nix-workspace/test-clan
   ls -la .clan/vars/  # Check for old machine name directories
   ```
2. If needed, regenerate vars:
   ```bash
   clan vars generate cinnabar
   clan vars generate electrum
   ```
3. Verify secrets properly named in `.clan/secrets/` or sops files
4. Test vars available in configuration builds

**Success Criteria:**
- Vars generated for new machine names
- No orphaned vars for old names
- Secrets accessible in configuration

### Task 6: Update all test files to reference new machine names (45 minutes)

**Objective:** Fix test harness to validate renamed machines

**Actions:**
1. Update regression tests (`modules/checks/regression.nix`):
   - RT-1 (Terraform output): Reference cinnabar/electrum
   - RT-2 (NixOS closure): Reference cinnabar/electrum
   - RT-3 (Machine builds): Reference cinnabar/electrum
2. Update invariant tests (`modules/checks/invariants.nix`):
   - IT-1 (Inventory structure): Assert cinnabar/electrum in machines
   - IT-2 (Service targeting): Validate services target new names
3. Update integration tests (`modules/checks/integration.nix`):
   - VT-1 (VM boot): Reference cinnabar/electrum
4. Update any snapshot files with new machine names
5. Run full test suite: `nix flake check` or `./tests/run-all.sh`

**Success Criteria:**
- All tests updated
- Regression tests passing
- Invariant tests passing
- Integration tests passing (or status unchanged)

### Task 7: Deploy electrum and validate zerotier network (60 minutes)

**Objective:** Deploy electrum VM and confirm zerotier mesh network operational

**Actions:**
1. **Deploy electrum VM** (first time deployment):
   ```bash
   cd ~/projects/nix-workspace/test-clan

   # Generate vars for electrum (if not already done in Task 5)
   clan vars generate electrum

   # Deploy electrum via terraform (enabled=true from Task 4)
   nix run .#terraform
   # This will provision electrum on Hetzner Cloud and run clan machines install
   ```

2. Verify cinnabar zerotier controller status (should already be running from Story 1.5):
   ```bash
   ssh root@<cinnabar-ip> "zerotier-cli info"
   ssh root@<cinnabar-ip> "zerotier-cli listnetworks"
   ```

3. Verify electrum zerotier peer status (should auto-join network via clan service):
   ```bash
   ssh root@<electrum-ip> "zerotier-cli info"
   ssh root@<electrum-ip> "zerotier-cli listpeers"
   ```

4. Get zerotier IPs from both machines:
   ```bash
   ssh root@<cinnabar-ip> "ip addr show zt+"
   ssh root@<electrum-ip> "ip addr show zt+"
   ```

5. Test bidirectional connectivity:
   ```bash
   # From cinnabar to electrum
   ssh root@<cinnabar-ip> "ping -c 3 <electrum-zerotier-ip>"

   # From electrum to cinnabar
   ssh root@<electrum-ip> "ping -c 3 <cinnabar-zerotier-ip>"
   ```

6. Test SSH via zerotier:
   ```bash
   # From local machine via zerotier IPs (if joined to network)
   ssh root@<cinnabar-zerotier-ip>
   ssh root@<electrum-zerotier-ip>
   ```

7. Document zerotier network ID and IPs in README or architecture docs

**Success Criteria:**
- Electrum VM deployed successfully to Hetzner Cloud
- Both machines show zerotier online
- Bidirectional ping successful
- SSH via zerotier working
- Network latency acceptable (< 100ms for Hetzner-to-Hetzner)
- Network ID documented
- NixOS ↔ NixOS zerotier networking validated (prepares for Story 1.10 darwin integration)

### Task 8: Update documentation with production topology (30 minutes)

**Objective:** Ensure docs reflect cinnabar/electrum as test infrastructure

**Actions:**
1. Update `README.md`:
   - Replace hetzner-vm with cinnabar
   - Replace test-vm with electrum
   - Document zerotier network ID
   - Update any deployment instructions
2. Update architecture docs if they reference specific machine names
3. Update any troubleshooting guides
4. Add note about Story 1.5 zerotier foundation
5. Document cinnabar/electrum roles:
   - cinnabar: Primary VPS, zerotier controller, permanent infrastructure
   - electrum: Secondary test VM, zerotier peer, may be ephemeral

**Success Criteria:**
- All documentation consistent
- Zerotier network documented
- Production topology clear
- No references to old names

### Task 9: Commit changes with atomic commits per category (30 minutes)

**Objective:** Create clean git history for VM rename refactoring

**Actions:**
1. Commit machine module rename:
   ```bash
   git add modules/machines/nixos/cinnabar modules/machines/nixos/electrum
   git commit -m "refactor(machines): rename hetzner-vm → cinnabar, test-vm → electrum

   Production topology alignment for Epic 2+ migration"
   ```
2. Commit inventory updates:
   ```bash
   git add modules/flake-parts/clan.nix
   git commit -m "refactor(inventory): update clan inventory with production machine names

   cinnabar (controller), electrum (peer)"
   ```
3. Commit test updates:
   ```bash
   git add modules/checks/
   git commit -m "test: update test harness to reference cinnabar/electrum"
   ```
4. Commit terranix updates (if applicable):
   ```bash
   git add modules/terranix/
   git commit -m "refactor(terranix): update terraform config for production names"
   ```
5. Commit documentation:
   ```bash
   git add README.md docs/
   git commit -m "docs: update documentation with production topology (cinnabar/electrum)"
   ```

**Success Criteria:**
- Clean atomic commits
- Each commit category isolated
- Commit messages follow conventional format
- Git history readable

---

## Dev Notes

### Implementation Approach - Critical Guidance

**⚠️ This story involves a triple-stack of esoteric/cutting-edge technologies:**

1. **Nix language** - Esoteric functional language with lazy evaluation, complex module system
2. **Dendritic flake-parts pattern** - Novel architectural pattern with limited real-world adoption
3. **Clan-core integration** - Very new system (2024) with small user base, evolving patterns

**Due to this complexity stack, the following approach is ESSENTIAL:**

**A. Anchor ALL code changes to working examples:**
- **Never guess** Nix syntax, module patterns, or clan integration points
- **Always inspect source code** from reference projects before implementing
- **Priority order for reference inspection:**
  1. **test-clan working code** (modules/clan/*, modules/checks/*, proven in Stories 1.1-1.8A)
  2. **External clan examples** (clan-infra, mic92-clan-dotfiles, qubasa-clan-infra for clan patterns)
  3. **External dendritic examples** (gaetanlepage-dendritic-nix-config, dendrix-dendritic-nix for module organization)
  4. **Upstream source** (clan-core, flake-parts, import-tree for authoritative patterns)
- **Verify example quality** before copying: Does it work? Is it maintained? Does it match our architecture?

**B. Design test cases with extreme care:**
- **Test harness is your safety net** - 18 tests validate zero-regression
- **Before changing code**: Understand which tests will validate the change
- **After changing code**: Run full test suite immediately (`just test`)
- **Test failures are design feedback** - don't bypass tests, understand why they fail
- **Add new tests** if rename operation exposes gaps in coverage
- **Nix-unit test design**: Use working tests as templates (TC-001 through TC-021 in modules/checks/nix-unit.nix)

**C. When uncertain:**
1. Read the working example code in reference projects
2. Search upstream source code for similar patterns
3. Run `nix repl` to test expressions before committing
4. Ask for clarification rather than guessing

**D. Red flags that indicate you're guessing:**
- "This should work..." without checking an example
- Copying from ChatGPT/LLM output without verifying against real code
- Skipping test execution because "it's just a rename"
- Using Nix syntax you haven't seen in a working example

**This story is primarily search-and-replace refactoring, but the STACK COMPLEXITY means every change must be validated against working examples and tests.**

### Learnings from Previous Story (Story 1.8A)

**From Story 1.8A completion notes (Status: done):**

**New Services/Patterns Created:**
- Portable home-manager modules pattern: `modules/home/users/{username}/`
- Cross-platform homeDirectory pattern: `pkgs.stdenv.isDarwin` conditional
- Three integration modes: darwin integrated, NixOS integrated, standalone
- Dendritic namespace exports: `flake.modules.homeManager."users/{username}"`

**Files Available for Reuse:**
- `modules/home/users/crs58/default.nix` - Ready for cinnabar NixOS integration (FUTURE, not this story)
- `modules/home/users/raquel/default.nix` - Cross-platform raquel config
- `modules/home/configurations.nix` - Standalone homeConfigurations

**Architectural Decisions from 1.8A:**
- User modules self-contained with platform detection
- Username-only naming strategy for portability
- Single homeConfiguration per user (not per platform)
- Preserve infra's modular pattern adapted to dendritic + clan

**Warnings/Recommendations:**
- Inline configs are anti-pattern - always modularize
- Zero-regression validation via package diff essential
- Test coverage for architectural patterns prevents regressions
- Cross-platform portability requires platform-aware conditionals

**Story 1.8A Unblocked:**
- Story 1.9 (this story): VM renaming and zerotier network
- Story 1.10: blackphos can integrate with renamed cinnabar/electrum
- Future: cinnabar NixOS config can import crs58 module when deploying users

**Technical Debt from 1.8A:**
- None blocking this story
- Future: Consider profile-based modules if user config sharing needs grow

**Review Findings:**
- Zero-regression validated: 270 packages preserved
- Test coverage exemplary: TC-018, TC-019 validate architectural invariants
- Cross-platform portability achieved via conditional homeDirectory

### Architecture Context from Epic 1

**Dendritic Pattern (Stories 1.6-1.7):**
- Validated with zero regressions
- 17 test cases proving pattern correctness
- Auto-discovery via import-tree
- Self-composition via `config.flake.modules.*`

**Zerotier Foundation (Story 1.5):**
- Zerotier controller deployed on hetzner-vm
- Basic networking validated
- Network ID exists (to be documented in this story)
- Ready for electrum peer addition

**Test Harness (Story 1.6):**
- 18 tests: 12 nix-unit + 4 validation + 2 integration
- Regression, invariant, feature, integration categories
- Validates zero-regression during refactoring
- Must update for new machine names

### Files Requiring Updates (Preliminary)

**Machine Modules:**
- `modules/machines/nixos/hetzner-vm/` → `modules/machines/nixos/cinnabar/`
- `modules/machines/nixos/test-vm/` (or similar) → `modules/machines/nixos/electrum/`

**Clan Configuration:**
- `modules/flake-parts/clan.nix` - inventory.machines keys, service instances

**Terranix Configuration:**
- `modules/terranix/hetzner.nix` (if references machine names)
- Any terraform resource definitions

**Test Files:**
- `modules/checks/regression.nix` - RT-1, RT-2, RT-3 tests
- `modules/checks/invariants.nix` - IT-1, IT-2 tests
- `modules/checks/integration.nix` - VT-1 test
- Any snapshot files

**Documentation:**
- `README.md` - deployment instructions, topology description
- Architecture docs - machine name references
- Troubleshooting guides - SSH/deployment examples

### Zerotier Network Context

**From Story 1.5 (AC9):**
- Zerotier controller operational on hetzner-vm (now cinnabar)
- `zerotier-cli info` shows controller running
- Network created during Story 1.5 deployment

**This Story's Zerotier Scope:**
1. Validate controller still operational after rename
2. Configure electrum as zerotier peer
3. Establish network connectivity between cinnabar and electrum
4. Document network ID for Story 1.10 (blackphos integration)

**Story 1.10 Preparation:**
- Network ID documented → blackphos can join as peer
- Heterogeneous networking proven (nixos ↔ nixos) → validates pattern for nixos ↔ darwin

### Project Structure Alignment

**Dendritic Namespace Usage:**
- Machines: `config.flake.modules.nixos.*` for system modules
- Home: `config.flake.modules.homeManager.*` for user configs (Story 1.8A)
- Self-composition working via outer config capture

**Clan Inventory Pattern:**
- `modules/flake-parts/clan.nix` - central inventory definition
- Machines defined with tags for service targeting
- Service instances use roles to target specific machines

**Test Organization:**
- `modules/checks/` - auto-discovered test modules
- Categories: regression, invariants, features, integration
- Run via `nix flake check`

### Testing Strategy for Rename

**Regression Prevention:**
1. Capture pre-rename state:
   - Machine builds: Store closure hashes
   - Terraform output: Capture current terraform.tf.json
   - Inventory structure: Snapshot machine list
2. Perform rename operations
3. Validate post-rename:
   - Builds produce equivalent closures (ignoring machine name in paths)
   - Terraform output structurally equivalent
   - Inventory has same number of machines/services
4. Run full test suite: All tests passing

**Zero-Regression Validation:**
- Configuration refactoring only (no functional changes)
- Machine closures may have different paths (name embedded) but same packages
- Test harness must validate structural equivalence

### References

**Test-Clan Validation (Stories 1.1-1.7):**
- Dendritic pattern proven with 17 test cases
- Zero-regression refactoring validated in Story 1.7
- Test harness established in Story 1.6

**Story 1.5 Zerotier Deployment:**
- `docs/notes/development/work-items/1-5-deploy-hetzner-vm-and-validate-stack.md`
- AC9: Zerotier controller operational
- Network ID created (to be retrieved and documented)

**Story 1.8A Portable Home Modules:**
- `docs/notes/development/work-items/1-8a-extract-portable-home-manager-modules.md`
- crs58 module ready for NixOS integration (future)
- Pattern documented in architecture.md

**Epic 1 Acceptance Criteria Mapping:**
This story contributes to Epic 1 success criteria:
1. ✅ Hetzner VMs deployed and operational (Story 1.5, preserved in rename)
2. ✅ Dendritic pattern proven (Stories 1.6-1.7, validated during rename)
3. ⏳ Heterogeneous zerotier network (this story: nixos ↔ nixos, Story 1.10: + darwin)
4. ⏳ Migration patterns documented (Story 1.11 will synthesize)
5. ⏳ GO/CONDITIONAL GO/NO-GO decision (Story 1.12)

---

## Risk Mitigation

### Refactoring Risks

**Risk:** Breaking operational VMs during rename
**Mitigation:**
- Configuration-only changes (no deployments unless needed)
- Test harness validates equivalence
- Git history preserves rollback path
- Story 1.7 notes mention operational IPs (162.55.175.87, 49.13.140.183) - avoid accidental deployment

**Risk:** Missed references to old machine names
**Mitigation:**
- Comprehensive grep search (Task 1)
- Test harness validates inventory structure (IT-1)
- Build all configurations to catch broken imports
- Code review of commits before deployment

**Risk:** Zerotier network disrupted by rename
**Mitigation:**
- Zerotier controller uses network ID, not machine hostname
- Configuration rename doesn't affect running services
- Validate network connectivity after rename (Task 7)
- Document network ID for reference

### Test Coverage Risks

**Risk:** Test harness has hardcoded machine names
**Mitigation:**
- Task 6 systematically updates all test categories
- Run test suite multiple times during rename
- Validate regression tests catch breaking changes

**Risk:** Terraform regeneration changes infrastructure
**Mitigation:**
- Review generated terraform.tf.json manually
- Do not run `terraform apply` without explicit intent
- Terranix outputs declarative config (rename should be safe)

### Documentation Risks

**Risk:** Documentation out of sync with code
**Mitigation:**
- Task 8 updates all documentation
- Search for old names in markdown files
- Update README.md, architecture docs, troubleshooting guides

---

## Definition of Done

- [ ] VMs renamed: hetzner-vm → cinnabar, test-vm → electrum (AC1)
- [ ] Clan inventory updated with production names (AC2)
- [ ] Zerotier network operational between cinnabar and electrum (AC3)
- [ ] Network connectivity validated bidirectionally (AC4)
- [ ] Configurations build successfully with new names (AC5)
- [ ] Test harness updated and all tests passing (AC6)
- [ ] Documentation reflects production topology (AC7)
- [ ] All 9 implementation tasks completed
- [ ] Atomic commits created per category
- [ ] Story 1.10 unblocked (heterogeneous network ready for darwin integration)

---

## Dev Agent Record

### Context Reference

- `docs/notes/development/work-items/1-9-rename-vms-cinnabar-electrum-establish-zerotier.context.xml` (generated 2025-11-13)

### Agent Model Used

claude-sonnet-4-5-20250929

### Debug Log References

**Task 1 Catalog (2025-11-13):**

**Critical Finding:** Zerotier service configuration error discovered in `modules/clan/inventory/services/zerotier.nix`:
- Current config shows `hetzner-ccx23` as controller
- Story 1.5 and terranix show `hetzner-cx43` (enabled=true) is deployed controller
- Correcting: cx43 (deployed) → cinnabar (controller), ccx23 (will deploy) → electrum (peer)

**Files requiring updates (comprehensive catalog):**

Machine modules (rename directories + update hostnames):
- `modules/machines/nixos/hetzner-cx43/default.nix` → cinnabar (line 90: networking.hostName, line 8: flake.modules path)
- `modules/machines/nixos/hetzner-ccx23/default.nix` → electrum (line 87: networking.hostName, line 8: flake.modules path)

Clan configuration:
- `modules/clan/inventory/machines.nix` - machine keys for both (lines 3-19)
- `modules/clan/machines.nix` - registration with import paths
- `modules/clan/inventory/services/zerotier.nix` - **FIX controller to cx43** then rename (line 10)

Terranix configuration:
- `modules/terranix/hetzner.nix` - machine keys (lines 10-23), enable electrum (line 11: enabled=false→true)

Test files:
- `modules/checks/nix-unit.nix` - machine name assertions
- `modules/checks/integration.nix` - VM boot tests
- `modules/checks/validation.nix` - may reference machine names (need to verify)

Documentation:
- `README.md` - deployment instructions, topology description
- `docs/notes/development/architecture.md` - machine references
- `docs/notes/development/project-overview.md` - machine references
- `docs/notes/development/index.md` - machine references
- `docs/notes/development/source-tree-analysis.md` - machine references
- `docs/notes/development/development-guide.md` - ccx23 references only
- `docs/notes/development/technology-stack.md` - ccx23 references only

Generated/cache files (auto-updated, low priority):
- `inventory.json` - generated from clan inventory
- `justfile` - may have machine-specific commands

**Implementation plan adjustment:**
1. ✅ First fix zerotier controller config (cx43, not ccx23) BEFORE rename
2. ✅ Disable hetzner-cx43 in terranix (commit d08d118)
3. ⏸️ **PAUSED**: Awaiting user execution of `nix run .#terranix` to destroy cx43
4. Then proceed with rename operations
5. Enable both cinnabar + electrum in terranix
6. Deploy both machines and validate zerotier network

**Workflow Decision (2025-11-13):**
- Destroy → Rename → Deploy approach to avoid terraform state confusion
- Accept new zerotier network creation (test-clan is disposable infrastructure)
- Clean slate deployment with correct names from the start

### Completion Notes List

### File List
