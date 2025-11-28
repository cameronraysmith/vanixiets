# Epic 3: Multi-Darwin Validation (Phase 2 - rosegold)

**Goal:** Deploy rosegold and validate multi-darwin zerotier network

**Status:** Ready for execution
**Dependencies:** Epic 2 complete ✅ (rosegold config created in Story 2.13)
**Timeline:** 1 session deployment + 1-2 weeks stability validation

**Strategic Value:**
- First deployment of Epic 2's new machine configs
- Validates 4-machine zerotier network (cinnabar + stibnite + blackphos + rosegold)
- Confirms janettesmith (basic user) + cameron (admin) dual-user pattern works in production

---

## Story 3.1: Rosegold configuration creation [COMPLETED IN EPIC 2]

**Status:** ✅ Completed in Epic 2 Story 2.13

This story was completed during Epic 2 Phase 4.
The following were created:
- modules/machines/darwin/rosegold/default.nix
- modules/home/users/janettesmith/
- sops/users/janettesmith/key.json
- secrets/home-manager/users/janettesmith/secrets.yaml
- Clan inventory entries
- nix-unit test coverage (TC-003, TC-005)

**No work required** - proceed to Story 3.2.

---

## Story 3.2: Deploy rosegold and validate zerotier integration

As a system administrator,
I want to deploy rosegold from infra clan-01 branch and integrate into the zerotier network,
So that rosegold is operational with full mesh connectivity to all clan machines.

**Execution Model:** HYBRID (physical access required on rosegold)
- [USER] tasks: Physical login, clone repo, run deployment commands
- [AI] tasks: Review diffs, debug issues, update configs, commit changes

**Acceptance Criteria:**

### Prerequisites (AC0)
0. Verify Nix and Homebrew installed and infra repo cloned on rosegold, OR bootstrap fresh machine:
   - Clone infra: `git clone https://github.com/cameronraysmith/infra.git && cd infra && git checkout clan-01`
   - Install darwin prerequisites: `make bootstrap-prep-darwin` (Xcode CLI tools + Homebrew)
   - Bootstrap Nix: `make bootstrap`

### Deployment (Steps 1-6)
1. Cameron admin user logged in physically on rosegold
2. infra repo on clan-01 branch with latest changes: `git pull origin clan-01`
3. Dry-run successful: `just clan-darwin-dry rosegold` completes without errors
4. Dry-run diff reviewed and approved (no unexpected changes)
5. Deployment successful: `just clan-darwin-switch rosegold` completes
6. System boots correctly after deployment, cameron and janettesmith users functional

### Zerotier Integration (Steps 7-9)
7. Rosegold joins zerotier network db4344343b14b903 via zerotier-join script
8. Rosegold IPv6 obtained and added to cinnabar's allowedIps configuration
9. Cinnabar updated: `clan machines update cinnabar` from stibnite
10. Zerotier mesh verified: rosegold can reach all peers (cinnabar, stibnite, blackphos)

### User Validation (Steps 10-11)
11. janettesmith user functional: shell, home-manager packages, secrets decryption
12. cameron admin user functional: sudo, homebrew, full aggregate packages
13. rosegold.zt added to SSH client configs in infra (modules/home/tools/ssh.nix or similar)
14. SSH connectivity verified: can SSH to/from rosegold.zt over zerotier network

**Estimated Effort:** 2-3 hours

**Risk Level:** LOW (patterns validated on stibnite/blackphos in Epic 2 Story 2.7)

**Prerequisites:**
- Epic 2 complete ✅
- Physical access to rosegold machine
- rosegold connected to internet

**Stability Gate:** rosegold stable 1-2 weeks → proceed to Epic 4 (argentum deployment)

---

## Success Criteria

- [ ] rosegold deployed from infra clan-01 branch
- [ ] 4-machine zerotier network operational (cinnabar, stibnite, blackphos, rosegold)
- [ ] Full mesh SSH connectivity verified
- [ ] janettesmith and cameron users functional
- [ ] rosegold.zt hostname configured across fleet
- [ ] No regressions on existing machines

---

## References

- Epic 2 Story 2.13: docs/notes/development/work-items/2-13-rosegold-configuration-creation.md
- Epic 2 Story 2.7: docs/notes/development/work-items/2-7-activate-blackphos-and-stibnite-from-infra.md (deployment pattern reference)
- Zerotier network: db4344343b14b903
