# Epic 3: Multi-Darwin Validation (Phase 2 - rosegold)

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

## Story 3.1: Create rosegold configuration using blackphos patterns

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

**Prerequisites:** Epic 2 complete (blackphos stable, patterns documented)

---

## Story 3.2: Add rosegold to clan inventory and deploy

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

**Prerequisites:** Story 3.1 (rosegold configuration created)

---

## Story 3.3: Validate 3-machine network and multi-darwin coordination

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

**Stability gate:** rosegold stable for 1-2 weeks, 3-machine network stable → proceed to Epic 4 (argentum)

**Prerequisites:** Story 3.2 (rosegold deployed)

---
