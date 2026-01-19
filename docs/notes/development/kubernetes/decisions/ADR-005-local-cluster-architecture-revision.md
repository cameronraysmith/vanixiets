# ADR-005: Local Cluster Architecture Revision

## Status

Proposed (pending review)

## Context

Investigation of beads issue nix-2hd revealed that Cilium eBPF networking is fundamentally broken in the current local development architecture: NixOS VMs running in Incus inside Colima on Apple Silicon.

The specific symptom is BPF stack delivery failure where packets sent to the kernel "stack" never reach the kernel.
Debug traces consistently show `flow 0x0, ifindex 0, orig-ip 0.0.0.0` - indicating packet metadata corruption or loss.
Extensive testing ruled out configuration issues:
- Kernel versions tested: 6.12 LTS, 6.18 latest (identical behavior)
- Attachment modes: TCX vs Legacy TC (identical behavior)
- Routing modes: Tunnel vs Native (identical behavior)
- Host routing: BPF vs Legacy (identical behavior)

Root cause analysis identified fundamental platform constraints:
1. macOS Hypervisor.framework does not support hardware-assisted nested virtualization
2. Cilium eBPF in nested virtualization on ARM64 is an unsupported edge case
3. The `bpf_redirect_peer` namespace scrubbing bug (CVE-2025-37959) affects cross-namespace packet handling

ADR-002 superseded ADR-001's x86_64 mandate because "incus and Colima cannot run x86_64-linux VMs on aarch64 hosts."
This constraint is accurate for full VMs but does not apply to container-based approaches like kind or k3d.

This ADR evaluates alternative architectures to restore functional Cilium networking for local development.

## Alternatives Evaluated

### Option A: OrbStack Kubernetes

OrbStack provides a lightweight Kubernetes environment with superior performance on Apple Silicon.

**Findings:**
- Uses a proprietary k3s-like implementation (unconfirmed if k3s-based)
- Custom CNI support is not officially supported (GitHub issue #742 open since October 2023)
- Nested virtualization is not supported (GitHub issue #1504 - waiting on Apple)
- Networking constraints: no bridged networking, limited topology options
- x86_64 containers supported via Rosetta

**Verdict:** Not viable for Cilium-based development.
The lack of custom CNI support is a blocking constraint.

### Option B: kind + ctlptl (Docker-based Kubernetes)

kind (Kubernetes in Docker) runs Kubernetes nodes as Docker containers rather than VMs.
ctlptl provides declarative cluster management.

**Findings:**
- Official darwin-arm64 support with native binaries
- Cilium is fully compatible with kind (requires disabling kindnet)
- Works with Docker Desktop, Colima, OrbStack, or Podman as container runtime
- x86_64 images supported via Rosetta (20% overhead vs 85% for QEMU)
- Networking is Docker-based (bridge network) not overlay
- Some ARM64 stability issues reported with specific versions

**Verdict:** Viable primary candidate.
Cilium works but eBPF features may be limited in container runtime.
Docker-based networking differs from VM-based production topology.

### Option C: k3d (k3s in Docker)

k3d wraps k3s in Docker containers, providing lighter weight than kind.

**Findings:**
- 80% faster startup than kind
- Lower memory footprint (423-502 MiB vs kind's higher usage)
- Same eBPF limitations as kind (container runtime constraints)
- Better for resource-constrained development
- Team configuration sharing via config files

**Verdict:** Viable alternative to kind.
Choose k3d if production uses k3s (exact parity); choose kind for upstream Kubernetes parity.

### Option D: Native aarch64 without Cilium

Accept that local development cannot match production CNI and use simpler networking.

**Findings:**
- Flannel or kube-proxy-based networking works in nested virtualization
- Validates application logic and Kubernetes configuration
- Does not validate Cilium network policies or eBPF-based features
- Requires CI/CD for full production parity testing

**Verdict:** Fallback option with reduced production parity.
Acceptable if Cilium-specific testing can be deferred to CI.

### Option E: x86_64 kind with Rosetta translation

Combine kind with x86_64 node images running under Rosetta userspace translation.

**Findings:**
- Provides architecture parity with Hetzner x86_64-linux
- Rosetta translation is efficient (20% overhead)
- Container images match production exactly
- Cilium x86_64 images avoid ARM64-specific issues
- Still subject to container runtime eBPF constraints

**Verdict:** Recommended approach.
Combines architecture parity with container-based simplicity.
Avoids nested virtualization issues entirely.

## Production Parity Analysis

| Aspect | Current (Incus VM) | kind x86_64 Rosetta | Production |
|--------|-------------------|---------------------|------------|
| Architecture | aarch64-linux | x86_64-linux | x86_64-linux |
| Kubernetes | k3s | kind (upstream) | k3s |
| CNI | Cilium (broken) | Cilium | Cilium |
| Container runtime | containerd | containerd | containerd |
| Networking | Overlay VM | Docker bridge | Overlay |
| eBPF support | Broken | Limited | Full |
| Node isolation | Full VM | Container | Full VM |

Key insight: No local approach provides full eBPF parity with production VMs.
The choice is between broken eBPF (current) and limited eBPF (container-based).
Limited eBPF is functional; broken eBPF is not.

## Recommendation

Adopt Option E: x86_64 kind with Rosetta translation as the primary local development approach.

**Implementation path:**

1. Create kind cluster configuration with:
   - `disableDefaultCNI: true` for Cilium
   - x86_64 node images via multi-arch manifests or explicit platform selection
   - Port mappings for API server, ingress, and services

2. Integrate ctlptl for declarative cluster lifecycle:
   - YAML-based cluster definitions
   - Version-controlled configuration
   - Team-shareable development environments

3. Deploy Cilium via existing easykubenix modules:
   - Same Helm values as production
   - Accept limited eBPF (container constraints)
   - Test full eBPF stack in CI on x86_64 infrastructure

4. Optionally integrate nix2container for custom node images:
   - Existing patterns in `modules/containers/`
   - Multi-arch build capability already implemented
   - Could create custom kindest/node images with Nix tooling pre-installed

**Trade-offs accepted:**

- Local development uses kind (upstream k8s) while production uses k3s
- eBPF features are limited in container runtime
- Full eBPF validation requires CI/CD on actual VMs
- Docker bridge networking differs from production overlay

**Trade-offs avoided (vs current approach):**

- Nested virtualization eBPF failures (eliminated)
- ARM64-specific BPF issues (eliminated via x86_64 architecture)
- Total Cilium non-functionality (resolved)

## Migration Path

1. **Preserve current incus infrastructure** for non-Cilium workloads or future testing
2. **Add kind + ctlptl as parallel option** in development workflow
3. **Update ADR-001/ADR-002** to document the evolution
4. **Create `02b-local-development-kind.md`** workflow documentation
5. **Evaluate after usage** whether to deprecate incus path entirely

## Consequences

### Enabled

- Functional Cilium networking for local development
- Architecture parity with production (x86_64-linux)
- Faster iteration cycles (kind startup 2-10 seconds)
- Simpler tooling (no nested virtualization debugging)
- Team-shareable cluster configurations via ctlptl

### Constrained

- eBPF features limited by container runtime
- Node isolation weaker than VM-based approach
- Kubernetes distribution difference (kind vs k3s)
- Docker/Podman dependency for container runtime

## Related Decisions

- ADR-001: Local Development Architecture (partial supersession of Colima VM approach)
- ADR-002: Bootstrap Architecture Independence (validates aarch64 for ClusterAPI control plane)
- ADR-004: Local Cluster Networking (port forwarding patterns may need revision for kind)
- nix-2hd: Cilium pod-to-host networking investigation (motivating issue)
- nix-50f: Local Development Cluster epic (scope expansion)
