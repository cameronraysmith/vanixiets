# Architecture Decision Records (ADRs)

## ADR-001: Adopt Dendritic Flake-Parts + Clan-Core Integration

**Status**: Accepted (validated in test-clan Stories 1.1-1.7)

**Context**: Current nixos-unified architecture lacks type safety, has unclear module boundaries, and doesn't support multi-machine coordination. Dendritic flake-parts provides type-safe namespace organization, clan-core provides multi-machine inventory system, but no production examples combine them.

**Decision**: Adopt dendritic flake-parts pattern with clan-core integration, validated through test-clan Phase 0 before production deployment.

**Consequences**:
- ✅ Maximum type safety via module system option declarations
- ✅ Clear module namespace (`flake.modules.*`)
- ✅ Multi-machine coordination via clan inventory
- ✅ Zero-regression validation (17 test cases in test-clan)
- ⚠️ Minimal specialArgs required (framework values only)
- ⚠️ Auto-merge base modules (pragmatic dendritic adaptation)
- ❌ No pure dendritic orthodoxy (clan functionality takes precedence)

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

## ADR-004: Darwin Networking via Multiple Options (Deferred to Story 1.8)

**Status**: Proposed (decision deferred to Story 1.8 experimental validation)

**Context**: Clan zerotier service is NixOS-only (systemd dependencies). Darwin requires alternative approach. Three options identified: Homebrew Zerotier, Custom Launchd, Hybrid Clan Vars + Manual. Tailscale eliminated due to incompatibility with darwin machines serving as VPN mesh servers.

**Decision**: Test hybrid approach (Option 3) in Story 1.8, defer final decision based on validation findings.

**Consequences**:
- ✅ Validates clan vars integration with darwin
- ✅ Proves controller auto-accept works with darwin peers
- ✅ Multiple fallback options (homebrew, custom launchd)
- ⚠️ Partially manual (not fully declarative initially)
- ⏭️ Architecture refinement after Story 1.8 data collection

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
