# Story 1.3: Configure clan inventory and service instances for test VMs

Status: drafted

## Story

As a system administrator,
I want to define clan inventory with real VM machine definitions (Hetzner + GCP) and configure service instances (admin, zerotier, tor),
So that I have infrastructure targets for terraform deployment and clan coordination.

## Context

Story 1.3 configures the clan inventory and service instances in test-clan to support infrastructure deployment in Stories 1.4-1.8.
This is a **required prerequisite** - terraform configurations in Story 1.4 (Hetzner) and Story 1.7 (GCP) reference machines defined in the inventory.

**Strategic decision (2025-11-03)**: Infrastructure-first approach - Story 1.2 (dendritic pattern) has been deferred.
Flow: Story 1.1 (complete) → **Story 1.3 (inventory)** → Story 1.4-1.8 (infrastructure deployment).

**Current state after Story 1.1**:
- flake-parts.lib.mkFlake + clan-core + terranix integration complete
- Module structure in place: base/, hosts/, flake-parts/, terranix/
- Clan inventory has placeholder values that need to be populated
- Following clan-infra's proven patterns exactly

## Acceptance Criteria

1. **Machine definitions populated in inventory.machines**:
   - `hetzner-vm` defined with tags = ["nixos" "cloud" "hetzner"], machineClass = "nixos"
   - `gcp-vm` defined with tags = ["nixos" "cloud" "gcp"], machineClass = "nixos"

2. **Admin service instance configured**:
   - Replace `__YOUR_PUBLIC_KEY__` placeholder with actual SSH public key
   - Admin service configured for both VMs

3. **Zerotier service instance configured**:
   - Replace `__YOUR_CONTROLLER__` placeholder with actual controller machine name (hetzner-vm)
   - Controller role assigned to hetzner-vm
   - Peer role assigned to gcp-vm via tags

4. **Tor service instance configured**:
   - Tor server role configured for fallback connectivity
   - Targeted at nixos machines via tags

5. **Inventory validates**:
   - `nix eval .#clan.inventory --json | jq .machines` shows both machines
   - Machine tags properly configured for service targeting

6. **NixOS configurations created for both machines**:
   - Minimal configurations (will expand in Story 1.4 and 1.7)
   - `nix build .#nixosConfigurations.{hetzner-vm,gcp-vm}.config.system.build.toplevel` succeeds

7. **Git working state clean and ready for Story 1.4** (Hetzner terraform config)

## Acceptance Criteria

1. Machine definitions populated: hetzner-vm and gcp-vm with proper tags (AC: #1)
2. Admin service configured with real SSH public key (AC: #2)
3. Zerotier controller assigned to hetzner-vm, peer role to gcp-vm (AC: #3)
4. Tor service configured for fallback connectivity (AC: #4)
5. Inventory evaluates and shows both machines correctly (AC: #5)
6. Both nixosConfigurations build successfully (AC: #6)
7. Git working tree clean and ready for next story (AC: #7)

## Tasks / Subtasks

- [ ] Define machine inventory in modules/flake-parts/clan.nix (AC: #1)
  - [ ] Add hetzner-vm to inventory.machines with tags ["nixos" "cloud" "hetzner"]
  - [ ] Add gcp-vm to inventory.machines with tags ["nixos" "cloud" "gcp"]
  - [ ] Set machineClass = "nixos" for both machines
  - [ ] Reference clan-infra inventory patterns from docs/notes/implementation/clan-infra-terranix-pattern.md

- [ ] Configure admin service instance (AC: #2)
  - [ ] Identify current user's SSH public key (from ~/.ssh/id_ed25519.pub or similar)
  - [ ] Replace `__YOUR_PUBLIC_KEY__` placeholder with actual key
  - [ ] Verify admin service targets both machines via tags.all

- [ ] Configure zerotier service instance (AC: #3)
  - [ ] Replace `__YOUR_CONTROLLER__` with "hetzner-vm"
  - [ ] Verify controller role assigned to hetzner-vm
  - [ ] Verify peer role targets both machines via tags.all (includes controller)
  - [ ] Reference zerotier pattern from clan-infra

- [ ] Configure tor service instance (AC: #4)
  - [ ] Verify tor server role targets nixos machines via tags.nixos
  - [ ] Document tor as fallback connectivity method

- [ ] Validate inventory configuration (AC: #5)
  - [ ] Run: `nix eval .#clan.inventory --json | jq .machines`
  - [ ] Verify both machines appear in output
  - [ ] Run: `nix eval .#clan.inventory --json | jq .instances`
  - [ ] Verify service instances configured correctly

- [ ] Create minimal NixOS configurations (AC: #6)
  - [ ] Create modules/hosts/hetzner-vm/default.nix with minimal config
  - [ ] Create modules/hosts/gcp-vm/default.nix with minimal config
  - [ ] Both configs import base modules (nix-settings)
  - [ ] Set networking.hostName for each machine
  - [ ] Set system.stateVersion = "25.05" for both
  - [ ] Build both configs: `nix build .#nixosConfigurations.hetzner-vm.config.system.build.toplevel`
  - [ ] Build both configs: `nix build .#nixosConfigurations.gcp-vm.config.system.build.toplevel`

- [ ] Test flake evaluation (AC: #5, #6)
  - [ ] Run: `nix flake check --all-systems`
  - [ ] Fix any evaluation errors
  - [ ] Verify no regressions from Story 1.1

- [ ] Commit changes atomically (AC: #7)
  - [ ] Create atomic commits for each logical change
  - [ ] Verify working tree clean: `git status`
  - [ ] Ready for Story 1.4 (Hetzner terraform configuration)

## Dev Notes

### Learnings from Previous Story

**From Story 1.1 (Status: done)**

Story 1.1 successfully prepared test-clan for Phase 0 validation by migrating from vanilla clan pattern to flake-parts.lib.mkFlake structure following clan-infra's proven terranix + flake-parts pattern exactly.

**New files created - infrastructure foundation**:
- `modules/flake-parts/clan.nix` - Clan configuration with terranix.flakeModule import (THIS FILE WILL BE MODIFIED IN STORY 1.3)
- `modules/flake-parts/nixpkgs.nix` - Nixpkgs configuration for all systems
- `modules/base/nix-settings.nix` - Base nix settings for all machines (REUSE IN MACHINE CONFIGS)
- `modules/hosts/.gitkeep` - Placeholder for machine-specific configurations (STORY 1.3 CREATES FIRST MACHINES HERE)
- `modules/terranix/.gitkeep` - Placeholder for terraform modules (Story 1.4 will populate)

**Key patterns established**:
- Imported terranix.flakeModule in modules/flake-parts/clan.nix (following clan-infra pattern exactly)
- All input follows configured to prevent version conflicts
- Placeholder structures created for terranix modules (Story 1.4 will implement)
- Removed deprecated root-level clan.nix to avoid services→instances migration issues

**Validation results**:
- `nix flake check --all-systems`: PASSED (all 4 systems)
- Clan CLI working in dev shell: `nix develop -c clan --help`
- Git working tree: CLEAN (5 atomic commits on phase-0-validation branch)

**Infrastructure-first decision**:
- Story 1.2 (dendritic pattern) DEFERRED - infrastructure deployment is primary objective
- Story 1.3 (THIS STORY) is required prerequisite for Story 1.4 (terraform needs inventory)
- Dendritic pattern can be refactored later after infrastructure works

**Critical files for Story 1.3**:
- `modules/flake-parts/clan.nix` - Contains inventory placeholders to populate
- `modules/base/nix-settings.nix` - Base settings to import in new machine configs

[Source: stories/1-1-prepare-existing-test-clan-repository-for-validation.md#Dev-Agent-Record]

### Project Structure Notes

**Test-clan location**: `~/projects/nix-workspace/test-clan/` (experimental repository, separate from production nix-config)

**Target structure for Story 1.3**:
```
test-clan/
├── flake.nix                          # Already configured with clan-core + terranix
├── modules/
│   ├── base/
│   │   └── nix-settings.nix           # EXISTS - import in machine configs
│   ├── hosts/                          # STORY 1.3 CREATES FIRST MACHINES HERE
│   │   ├── hetzner-vm/
│   │   │   └── default.nix            # NEW - minimal NixOS config
│   │   └── gcp-vm/
│   │       └── default.nix            # NEW - minimal NixOS config
│   ├── flake-parts/
│   │   ├── clan.nix                   # MODIFY - populate inventory
│   │   └── nixpkgs.nix                # EXISTS - no changes
│   └── terranix/                       # Story 1.4 will populate
└── README.md
```

**Inventory location**: `modules/flake-parts/clan.nix` lines 14-65 (from Story 1.1 file list)

**Placeholder values to replace** (from command args and current clan.nix):
- `__YOUR_PUBLIC_KEY__` in admin service → actual SSH public key from ~/.ssh/
- `__YOUR_CONTROLLER__` in zerotier service → "hetzner-vm"

### Architectural Context

**Following clan-infra patterns exactly**:
- Machine inventory with tags for service targeting
- Service instances with roles (controller, peer, server, default)
- Tags-based assignment (tags.all, tags.nixos) for bulk machine selection
- Role-based service configuration hierarchy

**Zerotier network topology**:
- hetzner-vm: controller role (always-on VPS provides stable controller)
- gcp-vm: peer role (connects to hetzner-vm controller)
- Both machines join the same zerotier network

**Service instance patterns** (from clan-infra reference):
- `admin`: Root access and SSH keys for emergency access
- `zerotier`: Network coordination via controller + peers
- `tor`: Fallback connectivity method (server role on nixos machines)

### References

- [Source: docs/notes/development/epics.md#Story-1.3]
- [Source: docs/notes/implementation/clan-infra-terranix-pattern.md#Inventory-patterns]
- [Source: docs/notes/clan/integration-plan.md#Clan-inventory-system]
- [Source: modules/flake-parts/clan.nix (current state with placeholders)]

### Important Constraints

**Zero-regression mandate does NOT apply to test-clan**: This is experimental.
Regression here is expected and informative.
The zero-regression mandate applies to production hosts (Phases 1-6), not Phase 0 validation.

**Solo project considerations**:
- No team coordination required
- All work sequential
- Manual validation only (no CI for Phase 0)
- Validation findings documented for Story 1.4 (Hetzner deployment)

**Required for Story 1.4**: Terraform configurations reference machines defined in inventory.
Story 1.3 MUST complete successfully before Story 1.4 can proceed.

## Change Log

**2025-11-03**:
- Story status: backlog → drafted
- Story created via create-story workflow
- Version: Story 1.3 draft ready for review

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Will be filled by dev agent -->

### Debug Log References

<!-- Will be filled by dev agent -->

### Completion Notes List

<!-- Will be filled by dev agent during implementation -->

### File List

<!-- Will be filled by dev agent during implementation -->
