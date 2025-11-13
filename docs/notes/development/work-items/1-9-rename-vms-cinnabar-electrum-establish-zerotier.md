# Story 1.9: Rename Hetzner VMs to cinnabar/electrum and establish zerotier network

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** drafted

**Dependencies:**
- Story 1.8A (done): Portable home-manager modules extracted and validated

**Strategic Value:** Aligns test-clan infrastructure with production topology naming, establishes heterogeneous zerotier network foundation for Story 1.10 (darwin integration), prepares for migration of validated cinnabar/electrum configurations to infra repository in Epic 2+.

---

## Story Description

As a system administrator,
I want to rename the test Hetzner VMs to their intended production names (cinnabar and electrum) and establish a zerotier network between them,
So that the test-clan infrastructure mirrors the production topology that will be deployed in Epic 2+ and heterogeneous networking is validated.

**Context:**
Story 1.5 deployed hetzner-vm with basic zerotier controller configuration.
Story 1.8A extracted portable home-manager modules ready for cross-platform reuse.
This story renames test VMs to production names (cinnabar = primary VPS, electrum = secondary test VM) and establishes proper zerotier networking between them.
Story does NOT deploy crs58 user to cinnabar yet (that's future work - this story focuses on VM renaming and zerotier network establishment).

**Key Distinction:**
This is primarily a configuration refactoring story (renaming machines, updating inventory, fixing tests) with zerotier network validation.
The zerotier foundation was laid in Story 1.5 - this story formalizes the network between renamed machines.

---

## Acceptance Criteria

### AC1: VMs renamed in test-clan configuration

- [ ] hetzner-vm → cinnabar (primary VPS, zerotier controller)
- [ ] test-vm → electrum (secondary test VM, zerotier peer) OR hetzner-ccx23 → electrum if different naming
- [ ] All module paths updated to reflect new names
- [ ] Machine definitions use production names consistently
- [ ] No references to old names (hetzner-vm, test-vm) remain in configuration

**Files to update:**
- `modules/machines/nixos/hetzner-vm/` → `modules/machines/nixos/cinnabar/`
- `modules/machines/nixos/test-vm/` or similar → `modules/machines/nixos/electrum/`
- `modules/flake-parts/clan.nix` inventory machine keys
- Any terranix configuration files referencing old names

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

**Objective:** Update terraform generation to reference production names

**Actions:**
1. Identify terranix files from Task 1 search
2. Update terraform resource names:
   - Hetzner server resource names: `hetzner-vm` → `cinnabar`
   - Any null_resource provisioners reference new names
3. Update terraform-generated identifiers if needed
4. Regenerate terraform: `nix build .#terranix.terraform`
5. Review generated `terraform.tf.json` for consistency

**Success Criteria:**
- Terranix configuration uses production names
- Terraform regenerates without errors
- Resource names aligned with inventory

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

### Task 7: Validate zerotier network between cinnabar and electrum (45 minutes)

**Objective:** Confirm zerotier mesh network operational with renamed machines

**Actions:**
1. Verify cinnabar zerotier controller status:
   ```bash
   ssh root@<cinnabar-ip> "zerotier-cli info"
   ssh root@<cinnabar-ip> "zerotier-cli listnetworks"
   ```
2. Verify electrum zerotier peer status:
   ```bash
   ssh root@<electrum-ip> "zerotier-cli info"
   ssh root@<electrum-ip> "zerotier-cli listpeers"
   ```
3. Get zerotier IPs from both machines:
   ```bash
   ssh root@<cinnabar-ip> "ip addr show zt+"
   ssh root@<electrum-ip> "ip addr show zt+"
   ```
4. Test bidirectional connectivity:
   ```bash
   # From cinnabar to electrum
   ssh root@<cinnabar-ip> "ping -c 3 <electrum-zerotier-ip>"

   # From electrum to cinnabar
   ssh root@<electrum-ip> "ping -c 3 <cinnabar-zerotier-ip>"
   ```
5. Test SSH via zerotier:
   ```bash
   # From local machine via zerotier IPs (if joined to network)
   ssh root@<cinnabar-zerotier-ip>
   ssh root@<electrum-zerotier-ip>
   ```
6. Document zerotier network ID and IPs

**Success Criteria:**
- Both machines show zerotier online
- Bidirectional ping successful
- SSH via zerotier working
- Network latency acceptable
- Network ID documented

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

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
