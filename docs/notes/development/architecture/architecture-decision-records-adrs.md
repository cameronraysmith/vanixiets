# Architecture Decision Records (ADRs)

## ADR-001: Adopt Dendritic Flake-Parts + Clan-Core Integration

**Status**: VALIDATED (Epic 1 complete - 21/22 stories, 7/7 HIGH confidence patterns, GO decision rendered)
**Date**: 2025-11-11 (Updated: 2025-11-21 post-Epic 1 validation)
**Deciders**: Dev (original), Winston/Architect (Epic 1 validation update)
**Epic 1 Validation**: Stories 1.1-1.7 (dendritic), 1.3-1.12 (clan), comprehensive validation

**Context**: Current nixos-unified architecture lacks type safety, has unclear module boundaries, and doesn't support multi-machine coordination. Dendritic flake-parts provides type-safe namespace organization, clan-core provides multi-machine inventory system, but no production examples combined them before Epic 1.

**Decision**: Adopt dendritic flake-parts pattern with clan-core integration, validated through test-clan Phase 0 before production deployment.

**Epic 1 Validation Evidence** (60-80 hours, 3+ weeks, 21 stories):

**Dendritic Flake-Parts** (Stories 1.1-1.7, 1.10BA-1.10E):
- ✅ Import-tree auto-discovery: 83 modules, zero manual imports (test-clan/flake.nix:4-6)
- ✅ Namespace merging via eval-modules: Automatic attribute deep-merge + list concatenation
- ✅ Zero regressions: 18 tests passing across all Epic 1 stories
- ✅ Module size heuristic validated: >7 line granularity pattern proven (Story 1.7 refactoring)
- ✅ Production deployment: blackphos physical deployment (270 packages preserved)
- **Reference**: `~/projects/nix-workspace/test-clan/docs/architecture/dendritic-pattern.md` (475 lines, comprehensive guide)

**Clan-Core Integration** (Stories 1.3, 1.9, 1.12):
- ✅ Inventory + service instances: zerotier, users, emergency-access roles validated
- ✅ Tag-based targeting: Heterogeneous fleet coordination (cinnabar, electrum, blackphos)
- ✅ Cross-platform proven: nixos VMs + nix-darwin workstations coordinated via zerotier mesh
- ⚠️ **Architectural limitation discovered**: Clan inventory cannot reference flake module namespaces directly - must use relative imports to home-manager modules (epic-1-retro-2025-11-20.md:342-344)

**Production Infrastructure Deployed**:
- Hetzner VMs operational: cinnabar (CX43), electrum (CCX23) with LUKS encryption
- Physical darwin deployment: blackphos running test-clan config (Story 1.12)
- Zerotier network: db4344343b14b903 (heterogeneous nixos ↔ darwin coordination, 1-12ms latency)

**Consequences** (Updated with Epic 1 evidence):
- ✅ Maximum type safety via module system option declarations (validated across 83 modules)
- ✅ Clear module namespace (`flake.modules.*`) - proven at scale
- ✅ Multi-machine coordination via clan inventory - heterogeneous fleet operational
- ✅ Zero-regression validation maintained (18 tests passing, zero regressions across 21 stories)
- ✅ **NEW**: Five-layer overlay architecture validated (Stories 1.10D-1.10DB)
- ✅ **NEW**: Home-Manager Pattern A cross-platform portability (4+ users, 17 modules, 270 packages)
- ✅ **NEW**: Two-tier secrets architecture (clan vars + sops-nix, multi-user encryption proven)
- ⚠️ Minimal specialArgs required (framework values only) - principle maintained
- ⚠️ Auto-merge base modules (pragmatic dendritic adaptation) - proven effective
- ⚠️ **NEW**: Clan inventory limitation requires relative imports pattern (documented workaround)
- ❌ No pure dendritic orthodoxy (clan functionality takes precedence) - validated in production

**Epic 1 GO Decision**: 7/7 decision criteria PASS, 0 CRITICAL/0 MAJOR blockers, all patterns HIGH confidence for production use. Epic 2-6 migration (~200+ hours) AUTHORIZED.

**References**:
- Epic 1 Retrospective: `docs/notes/development/epic-1-retro-2025-11-20.md` (lines 242-362: seven validated patterns)
- Test-clan dendritic pattern guide: `~/projects/nix-workspace/test-clan/docs/architecture/dendritic-pattern.md`
- Test-clan flake.nix: `~/projects/nix-workspace/test-clan/flake.nix` (lines 4-6: entire pattern in 3 lines)
- Story 1.7: Dendritic refactoring with zero regressions
- Story 1.12: Blackphos physical deployment validation

## ADR-002: Storage Encryption Strategy - Use LUKS Encryption

**Status**: ACCEPTED (Updated 2025-11-20 based on Epic 1 Story 1.5 findings)
**Date**: 2025-11-11 (Updated: 2025-11-20)
**Deciders**: Dev (original), Dev (update)
**Epic 1 Validation**: Story 1.5 (Hetzner VPS deployment)

**Context**: Original plan evaluated encryption options for VPS deployment. ZFS provides compression, snapshots, and integrity checking. LUKS provides encryption at rest. Initial decision favored unencrypted ZFS to defer complexity.

**Decision**: **Use LUKS encryption for VPS root filesystems** (changed from original ZFS unencrypted decision).

**Rationale**:
- Epic 1 Story 1.5 discovered ZFS encryption bug during cinnabar/electrum deployment
- LUKS encryption proven reliable across Hetzner VPS deployments
- Both cinnabar (49.13.68.78) and electrum operational with LUKS
- Zero encryption-related issues during Epic 1 validation

**Original Decision (Superseded)**: "Use ZFS Unencrypted"
- ZFS encryption encountered implementation issues during Story 1.5
- LUKS provides equivalent security with better stability

**Consequences**:

**Positive**:
- ✅ Encryption at rest for all VPS instances
- ✅ Proven reliable in Epic 1 deployment (cinnabar, electrum)
- ✅ No performance impact observed

**Negative**:
- ⚠️ LUKS requires boot-time passphrase entry (acceptable for manual VPS provisioning)
- ⚠️ Cannot use ZFS native encryption features

**Migration Notes**:
- All Epic 2+ VPS deployments should use LUKS encryption
- Cinnabar and electrum (Epic 1) already using LUKS - no migration needed

**Epic 1 Validation Evidence**:
- **Story 1.5**: Cinnabar + electrum deployed with LUKS encryption
- **Infrastructure**: Both VMs operational on Hetzner Cloud with encrypted root filesystems
- **Test Results**: Zero encryption-related issues during 3+ weeks Epic 1 validation
- **Production Readiness**: HIGH confidence for Epic 2+ deployments

**References**:
- Epic 1 Retrospective: `docs/notes/development/epic-1-retro-2025-11-20.md` (lines 278-281)
- Story 1.5: Hetzner VPS deployment with LUKS

## ADR-003: Progressive Migration with Stability Gates

**Status**: Accepted (defined in PRD, validated in test-clan)

**Context**: Brownfield migration across 5 heterogeneous machines (1 VPS + 4 darwin) with unproven architectural combination. Primary workstation (stibnite) is daily productivity critical.

**Decision**: Migrate progressively (test-clan validation → cinnabar → blackphos → rosegold → argentum → stibnite) with 1-2 week stability gates between phases, primary workstation last.

**Consequences**:
- ✅ Risk mitigation (each phase validates before next)
- ✅ Rollback capability (per-host, independent)
- ✅ Pattern refinement (learnings from early phases improve later phases)
- ✅ Primary workstation protected (only migrated after 4-6 weeks cumulative stability)
- ⚠️ Extended timeline (13-15 weeks conservative, 4-6 weeks aggressive)
- ⚠️ Dual architecture maintenance (nixos-unified + dendritic during migration)

## ADR-004: Darwin Zerotier via Homebrew Cask + Activation Script

**Status**: VALIDATED (Epic 1 Story 1.12 - production deployment proven)
**Date**: 2025-11-11 (Updated: 2025-11-21 post-Story 1.12 validation)
**Deciders**: Dev (original), Charlie/Senior Dev (Story 1.12 validation update)
**Epic 1 Validation**: Story 1.12 (blackphos physical deployment)

**Context**: Clan zerotier service is NixOS-only (systemd dependencies). Darwin requires alternative approach. Three options identified: (1) Homebrew Zerotier, (2) Custom Launchd, (3) Hybrid Clan Vars + Manual. Tailscale eliminated due to incompatibility with darwin machines serving as VPN mesh servers.

**Decision**: Use Option 1 (Homebrew Zerotier cask + activation script) for all darwin machines.

**Epic 1 Validation Evidence** (Story 1.12):
- ✅ Physical deployment: blackphos operational with zerotier via homebrew cask
- ✅ Heterogeneous coordination: nixos VMs (cinnabar, electrum) ↔ darwin (blackphos) bidirectional SSH
- ✅ Network performance: 1-12ms latency across zerotier network db4344343b14b903
- ✅ Production stability: Zero zerotier-related issues during 3+ weeks Epic 1 validation
- ✅ Documented solution: `~/projects/nix-workspace/test-clan/docs/guides/darwin-zerotier-integration.md`

**Implementation Pattern**:
```nix
# nix-darwin activation script
system.activationScripts.postUserActivation.text = ''
  # Install zerotier via homebrew if not present
  if ! command -v zerotier-cli &> /dev/null; then
    brew install --cask zerotier-one
  fi
  # Join network if not already member
  zerotier-cli join db4344343b14b903
'';
```

**Consequences** (Updated with Story 1.12 evidence):
- ✅ Validates clan vars integration with darwin (clan inventory users service functional)
- ✅ Proves controller auto-accept works with darwin peers (cinnabar zerotier controller)
- ✅ **VALIDATED**: Homebrew dependency acceptable for production use
- ⚠️ **MINOR limitation**: Not pure nix (homebrew external dependency), documented and acceptable
- ⚠️ Partially manual (not fully declarative), but pragmatic and proven
- ✅ **NEW**: Cross-platform zerotier mesh validated (nixos + darwin heterogeneous fleet)

**Alternative Options** (Deferred):
- Option 2 (Custom Launchd): More nix-native, but untested - defer unless homebrew causes issues
- Option 3 (Hybrid Manual): More manual, less desirable - Option 1 proven sufficient

**Production Readiness**: HIGH confidence for Epic 2+ darwin deployments (blackphos, stibnite, rosegold, argentum).

**References**:
- Epic 1 Retrospective: `docs/notes/development/epic-1-retro-2025-11-20.md` (lines 307-322: Zerotier pattern validation)
- Darwin zerotier guide: `~/projects/nix-workspace/test-clan/docs/guides/darwin-zerotier-integration.md`
- Story 1.12: Blackphos deployment with zerotier validation
- darwin-networking-options.md: Option 1 marked VALIDATED

## ADR-005: Multi-User via Standard NixOS Patterns (No Clan Magic)

**Status**: Accepted (validated via source code analysis of production examples)

**Context**: Multi-user darwin machines (blackphos: raquel + crs58, rosegold: janettesmith + crs58, argentum: christophersmith + crs58) require per-user secrets and home-manager configs. Clan has no built-in user management.

**Decision**: Use standard NixOS `users.users` for user definitions, per-user vars generator naming convention (`ssh-key-{username}`), separate home-manager modules per user.

**Consequences**:
- ✅ Standard patterns (no clan lock-in)
- ✅ Validated in production (clan-infra admins.nix, mic92 bernie machine)
- ✅ Clear admin/non-admin separation via `extraGroups = ["wheel"]`
- ✅ Home-manager scales independently
- ⚠️ Per-user secrets via naming convention (not first-class clan feature)
- ✅ No special clan user management needed

## ADR-006: Remove nixos-unified (Post-Migration Only)

**Status**: Accepted (cleanup in Epic 7 after all hosts migrated)

**Context**: nixos-unified uses specialArgs + directory autowire, incompatible with dendritic pattern (config.flake.*). Both cannot coexist cleanly.

**Decision**: Maintain nixos-unified during migration (Epics 1-6), remove completely in Epic 7 cleanup after all hosts migrated.

**Consequences**:
- ✅ Rollback safety (can revert to nixos-unified during migration)
- ✅ Progressive elimination (per-host migration reduces nixos-unified footprint)
- ✅ Clean final architecture (no legacy after Epic 7)
- ⚠️ Dual architecture maintenance (temporary complexity)
- ⚠️ Explicit removal step required (Epic 7, Story 7.1)

---

_Generated by BMAD Decision Architecture Workflow v1.3.2_
_Date: 2025-11-11_
_For: Dev_
