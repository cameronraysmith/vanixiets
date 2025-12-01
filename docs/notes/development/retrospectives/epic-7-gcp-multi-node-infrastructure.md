# Epic 7 Retrospective: GCP Multi-Node Infrastructure

**Date**: 2025-12-01
**Epic**: 7 - GCP Multi-Node Infrastructure (Post-MVP Phase 6)
**Status**: COMPLETE - All 4 stories DONE and APPROVED
**Facilitator**: Retrospective generated post-completion

---

## Executive Summary

Epic 7 successfully delivered togglable CPU-only and GPU-capable compute nodes on GCP using terranix, fully integrated with clan infrastructure and zerotier mesh network.
The implementation spanned 2 days of intensive work (~12-18 hours, ~60-70 commits), achieving all business objectives with zero regressions to existing infrastructure.

**Key Outcomes:**
- galena (e2-standard-8, CPU-only) - operational with zerotier mesh integration
- scheelite (n1-standard-8 + Tesla T4 GPU) - datacenter-optimized NVIDIA configuration validated
- 10 reusable patterns established for future GCP and GPU deployments
- Comprehensive GPU documentation created (nvidia-module-analysis.md, 671 lines)

**Business Objective Achievement:** GCP contract obligations met, GPU compute capability established, multi-cloud infrastructure expanded from Hetzner-only to Hetzner+GCP.

---

## Achievements and Metrics

### Story Completion

| Story | Description | ACs | Outcome |
|-------|-------------|-----|---------|
| 7.1 | Terranix GCP Provider and Base Configuration | 11/11 | APPROVED |
| 7.2 | CPU-Only Togglable Node Definition and Deployment | 10/10 | APPROVED |
| 7.3 | Clan Integration and Zerotier Mesh for GCP Nodes | 7/7 | APPROVED |
| 7.4 | GPU-Capable Togglable Node Definition and Deployment | 11/11 | APPROVED |

**Total: 39 acceptance criteria, 39 satisfied (100%)**

### Deliverables

| Artifact | Lines | Purpose |
|----------|-------|---------|
| `modules/terranix/gcp.nix` | 172 | Foundation for all GCP deployment |
| `modules/nixos/nvidia.nix` | 113 | Reusable datacenter NVIDIA config |
| `modules/machines/nixos/galena/` | 155 | Template for GCP NixOS nodes |
| `modules/machines/nixos/scheelite/` | 159 | Template for GPU nodes |
| `docs/notes/development/nvidia-module-analysis.md` | 671 | GPU configuration reference |
| Story 7.4 Work Item | 858 | Comprehensive GPU documentation |

### Infrastructure Deployed

| Machine | Type | Status | Cost Control |
|---------|------|--------|--------------|
| galena | e2-standard-8 (CPU) | Active for development | Toggle: `enabled = true/false` |
| scheelite | n1-standard-8 + T4 GPU | Validated, ready for workloads | Toggle: `enabled = true/false` |

### Network Integration

- Zerotier network: `db4344343b14b903`
- galena.zt: Integrated, SSH working
- scheelite.zt: Integrated, SSH working
- Full mesh: 6 machines (cinnabar, electrum, stibnite, blackphos, galena, scheelite)

---

## Patterns Established

### 1. Terranix GCP Module Pattern

Provider, firewall, instance template with cost-control toggle.
Follows hetzner.nix structure for consistency across cloud providers.

**Location:** `modules/terranix/gcp.nix`

### 2. GCP NixOS Machine Configuration

UEFI pattern with systemd-boot, GPT+ESP+ZFS.
Consistent with Hetzner NixOS patterns for deployment uniformity.

**Pattern:** `modules/machines/nixos/{galena,scheelite}/`

### 3. Startup Script for Root SSH

Enables nixos-anywhere provisioning on GCP Debian base images which block root SSH by default.

```nix
metadata_startup_script = ''
  mkdir -p /root/.ssh
  echo "<ssh-key>" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
'';
```

### 4. Zerotier Peer Integration with Clan

Inventory tags + controller authorization flow.
Pattern: Add to inventory → `clan machines install` → `clan machines update [controller]`

**Tags:** `["nixos", "cloud", "gcp", "peer"]` triggers zerotier peer role

### 5. Datacenter-Optimized NVIDIA Module

Headless compute focus, avoiding desktop anti-patterns.
Key settings: `nvidiaPersistenced = true`, `nvidiaSettings = false`, `modesetting.enable = false`

**Location:** `modules/nixos/nvidia.nix`

### 6. Scoped CUDA via Overlays

Uses `pythonPackagesExtensions` to preserve cache hits.
Avoids global `nixpkgs.config.cudaSupport = true` which causes mass rebuilds.

```nix
nixpkgs.overlays = [
  (final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (python-final: python-prev: {
        torch = python-prev.torch.override { cudaSupport = true; };
        jax = python-prev.jax.override { cudaSupport = true; };
      })
    ];
  })
];
```

### 7. CUDA Binary Cache Integration

Added cuda-maintainers.cachix.org to `lib/caches.nix` following existing DRY pattern.

### 8. GCP Cost Control Toggle

Default `enabled = false` with prominent cost documentation in terranix module.
Cost table at top of gcp.nix for visibility.

### 9. SSH Config for Zerotier Mesh

`.zt` hostnames + declarative known_hosts pattern.

**Files:**
- `modules/home/core/ssh.nix` - SSH config entries
- `modules/system/ssh-known-hosts.nix` - Known hosts with clan vars

### 10. Dendritic Module Auto-Discovery

import-tree pattern for hardware modules (nvidia.nix auto-discovered).
Outer config capture in machine configs for module access.

---

## Lessons Learned

### Technical Discoveries

| Discovery | Impact | Resolution |
|-----------|--------|------------|
| GCP Debian Root SSH Limitation | Blocked nixos-anywhere provisioning | startup-script workaround |
| Zerotier Authorization Flow | New peers not authorized automatically | Explicit `clan machines update [controller]` |
| Home-Manager Race Condition | File conflicts on fresh GCP instances | `backupFileExtension` mitigation |
| NVIDIA Datacenter Bug #454772 | `hardware.nvidia.datacenter.enable` broken | Avoid datacenter.enable, use standard driver |
| nvidiaPersistenced Critical | GPU state teardown on headless servers | Always enable for headless compute |
| Global cudaSupport Cache Miss | ALL packages rebuild from source | Scoped overlays solution |
| GCP GPU Zone Availability | L4 limited availability, T4 widely available | Switched to T4, documented zone constraints |
| Dendritic Module Import Pattern | Module access requires outer config capture | Document pattern in architecture |
| User Service Dependency | Must add user before deployment | Include in pre-deployment checklist |

### Process Insights

**What Went Well:**

1. **Efficient Story Sequencing** - Story 7.1 foundation enabled rapid iteration in 7.2-7.4
2. **Party Mode Reordering Decision** - Moving zerotier (7.3) before GPU (7.4) tested on cheap CPU node first, saving debugging costs
3. **Pattern Reuse** - Adapted hetzner.nix to GCP with minimal changes
4. **Comprehensive Documentation** - nvidia-module-analysis.md (671 lines) prevented known pitfalls
5. **Zero Regressions** - Zerotier mesh stable throughout all 4 stories
6. **Cost Management Discipline** - Default disabled, prominent cost documentation

**What Could Be Improved:**

1. **Startup-Script Pattern Discovery** - Discovered during implementation, not research phase; should have been identified in Story 7.1 research
2. **Datacenter.enable Bug Discovery** - Bug #454772 should have been found in initial GPU research before Story 7.4 drafting
3. **CUDA Cache Configuration** - Initial global cudaSupport required mid-story refactoring; pattern should be documented
4. **L4 GPU Availability** - Zone availability constraints were a surprise; should verify quota before defining machine type
5. **Zerotier Authorization Flow** - Not obvious from clan documentation; add to architecture docs
6. **Home-Manager Race Condition** - Discovered during Story 7.3; affects all new GCP deployments

---

## Action Items

### Code Changes Required

| Priority | Action | Owner | Location |
|----------|--------|-------|----------|
| LOW | Update inventory description "g2-standard-4, L4" → "n1-standard-8, T4" | Dev | `modules/clan/inventory/machines.nix:45` |
| LOW | Consider adding cudaPackages.cudatoolkit to systemPackages | Dev | `modules/nixos/nvidia.nix` |

### Documentation Updates

| Priority | Section | Content | Target File |
|----------|---------|---------|-------------|
| HIGH | GCP Deployment Patterns | Startup-script workaround, zone availability | `docs/notes/development/architecture/` |
| HIGH | Zerotier Authorization Flow | Controller update requirement after adding peers | `docs/notes/development/architecture/` |
| HIGH | NVIDIA Datacenter Anti-Patterns | Bug #454772, global cudaSupport, nvidiaPersistenced | `docs/notes/development/architecture/` |
| MEDIUM | GPU Onboarding Guide | CUDA cache, scoped overlays, driver selection | New document or architecture section |
| MEDIUM | Cost Control Toggle Pattern | Default disabled, cost documentation | `docs/notes/development/architecture/` |

### Test Harness Expansion

| Priority | Test | Description |
|----------|------|-------------|
| MEDIUM | galena configuration test | Validate GCP NixOS machine builds |
| MEDIUM | scheelite configuration test | Validate GPU node builds with nvidia module |
| LOW | Zerotier integration test | Validate peer configuration |

---

## Process Assessment: Party Mode Orchestration

### Effectiveness

The Party Mode orchestration approach used in Epic 7 demonstrated strong results:

1. **Reordering Decision (7.3/7.4 swap)** - Unanimous agent consensus to test zerotier on cheap CPU node before expensive GPU proved correct; caught zerotier authorization flow issue without incurring GPU costs

2. **Pattern Discovery** - Multi-agent discussion identified datacenter.enable bug and scoped CUDA overlay pattern that single-agent implementation might have missed

3. **Documentation Quality** - Party Mode generated comprehensive nvidia-module-analysis.md (671 lines) covering all edge cases

### Recommendations

- Continue Party Mode for complex infrastructure stories with multiple integration points
- Use Party Mode ultrathink for GPU/accelerator work specifically (many anti-patterns to avoid)
- Consider Party Mode less necessary for straightforward pattern-following stories

---

## Follow-Up Work

### Epic 8 Preparation

Epic 8 (Documentation Alignment) should incorporate Epic 7 learnings:

- Add GCP deployment patterns to architecture documentation
- Document NVIDIA datacenter configuration patterns
- Add zerotier authorization flow to operational guides
- Include cost control toggle pattern in infrastructure section

### Future GPU Work

If additional GPU nodes are needed:

1. L4 GPU configuration preserved in comments in gcp.nix (activate when availability improves)
2. A100 GPU cost documented in gcp.nix cost table
3. Multi-GPU patterns documented in nvidia-module-analysis.md (NVLink, MIG)

### Cost Control

Current state:
- galena: Active (development)
- scheelite: Active (validation)

Before Epic 8:
- Consider disabling both GCP nodes if not actively needed
- `enabled = false` + `nix run .#terraform` to destroy and stop costs

---

## Key Reference Files

**Epic Definition:**
- `docs/notes/development/epics/epic-7-gcp-multi-node-infrastructure.md`

**Story Work Items:**
- `docs/notes/development/work-items/7-1-terranix-gcp-provider-base-config.md`
- `docs/notes/development/work-items/7-2-cpu-only-togglable-node-definition-deployment.md`
- `docs/notes/development/work-items/7-3-clan-integration-zerotier-mesh-gcp-nodes.md`
- `docs/notes/development/work-items/7-4-gpu-capable-togglable-node-definition-deployment.md`

**Key Artifacts:**
- `docs/notes/development/nvidia-module-analysis.md`
- `docs/notes/development/sprint-status.yaml`
- `modules/terranix/gcp.nix`
- `modules/nixos/nvidia.nix`

---

## Retrospective Summary

Epic 7 successfully expanded infrastructure from single-cloud (Hetzner) to multi-cloud (Hetzner + GCP) with GPU compute capability.
The 2-day intensive implementation delivered all 4 stories with 100% acceptance criteria satisfaction.
10 reusable patterns were established that will accelerate future cloud and GPU deployments.
Key learnings around GCP-specific quirks, NVIDIA datacenter configuration, and zerotier authorization flows have been documented for future reference.

The epic demonstrates the maturity of the dendritic flake-parts + clan architecture, successfully extending proven patterns to new cloud providers and hardware configurations with minimal friction.

**Epic 7 Status: COMPLETE**
**Next Epic: 8 - Documentation Alignment**
