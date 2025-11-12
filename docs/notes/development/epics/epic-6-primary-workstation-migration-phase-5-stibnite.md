# Epic 6: Primary Workstation Migration (Phase 5 - stibnite)

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

## Story 6.1: Validate pre-migration readiness and create stibnite configuration

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

## Story 6.2: Deploy stibnite and validate all daily workflows

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

## Story 6.3: Complete 5-machine network and monitor productivity

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
