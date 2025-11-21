# Epic 4: Third Darwin Host (Phase 3 - argentum)

**Goal:** Final validation before primary workstation by migrating argentum

**Strategic Value:** Confirms patterns scale to 4 machines, validates 4-machine network stability, final validation before stibnite migration

**Timeline:** 1 week migration + 1-2 weeks stability validation

**Success Criteria:**
- argentum configuration builds using established patterns
- Zerotier peer connects to cinnabar controller
- 4-machine network operational
- No new issues discovered
- Stable for 1-2 weeks minimum, cumulative 4-6 weeks across all darwin hosts before Epic 5

---

## Story 4.1: Create argentum configuration and deploy to 4-machine network

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

**Prerequisites:** Story 3.3 (rosegold stable for 1-2 weeks)

---

## Story 4.2: Validate 4-machine network and assess stibnite readiness

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
8. Readiness assessment for stibnite migration: all criteria met for Epic 5

**Stability gate:** argentum stable for 1-2 weeks, cumulative stability across all darwin hosts sufficient → stibnite migration approved

**Prerequisites:** Story 4.1 (argentum deployed)

---
