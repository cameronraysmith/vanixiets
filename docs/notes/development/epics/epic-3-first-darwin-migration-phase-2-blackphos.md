# Epic 3: First Darwin Migration (Phase 2 - blackphos)

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

## Story 3.1: Convert darwin modules to dendritic flake-parts pattern for blackphos

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

## Story 3.2: Add blackphos to clan inventory with zerotier peer role

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

## Story 3.3: Generate clan vars and deploy blackphos configuration

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

## Story 3.4: Validate blackphos functionality and network connectivity

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

## Story 3.5: Document darwin patterns and monitor stability

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
