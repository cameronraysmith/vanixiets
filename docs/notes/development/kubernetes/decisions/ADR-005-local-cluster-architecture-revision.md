# ADR-005: Local Cluster Architecture Revision

## Status

Accepted (2026-01-19)

Supersedes ADR-001 Decision 8 (NixOS VM via nixos-generators) for local development.
ADR-001 remains valid for Hetzner production deployments.

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
- Native ARM64 support without emulation
- Team configuration sharing via config files
- Cilium support via `K3D_FIX_MOUNTS=1` (fixes `/sys/fs/bpf` mount propagation)
- Multi-node clusters supported (`servers: N, agents: M`)
- OrbStack as container runtime provides additional performance benefits

**Verdict:** Recommended approach.
k3d uses k3s which matches Hetzner production exactly.
Combined with OrbStack container runtime, provides optimal local development experience.

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

**Verdict:** Viable alternative.
Combines architecture parity with container-based simplicity.
Avoids nested virtualization issues entirely.
However, k3d is preferred for k3s distribution parity with production.

## Production Parity Analysis

| Aspect | Current (Incus VM) | k3d native aarch64 | Production |
|--------|-------------------|---------------------|------------|
| Architecture | aarch64-linux | aarch64-linux | x86_64-linux |
| Kubernetes | k3s | k3s | k3s |
| CNI | Cilium (broken) | Cilium | Cilium |
| Container runtime | containerd | containerd (OrbStack) | containerd |
| Networking | Overlay VM | Docker bridge | Overlay |
| eBPF support | Broken | Limited | Full |
| Node isolation | Full VM | Container | Full VM |

Key insight: No local approach provides full eBPF parity with production VMs.
The choice is between broken eBPF (current) and limited eBPF (container-based).
Limited eBPF is functional; broken eBPF is not.

k3d provides **Kubernetes distribution parity** (k3s) which is more valuable than architecture parity (x86_64) for most development workflows.
Architecture-specific issues are rare and better caught in CI on actual x86_64 infrastructure.

## Recommendation

Adopt Option C: k3d with native aarch64 as the primary local development approach.

**Rationale for k3d over kind:**
- k3d uses k3s, matching Hetzner production exactly
- Native aarch64 avoids Rosetta overhead (20% performance cost)
- OrbStack container runtime provides 10x faster startup than Docker Desktop
- Container images for k3s ecosystem are consistently multi-arch

**Implementation path:**

1. Create k3d cluster configuration with:
   - `K3D_FIX_MOUNTS=1` environment variable for Cilium BPF mount propagation
   - `--flannel-backend=none` to disable default CNI
   - `--disable-network-policy`, `--disable-kube-proxy` for Cilium replacement
   - `--disable=traefik`, `--disable=servicelb` for custom ingress
   - Port mappings for API server, ingress, and services

2. Integrate ctlptl for declarative cluster lifecycle:
   - YAML-based cluster definitions (following Kargo patterns)
   - Version-controlled configuration
   - Team-shareable development environments

3. Deploy Cilium via existing easykubenix modules:
   - Same Helm values as production
   - Accept limited eBPF (container constraints)
   - Test full eBPF stack in CI on x86_64 infrastructure

4. Preserve VM-based approach for specific scenarios:
   - Full eBPF testing when required
   - ClusterAPI development with nested VMs
   - Architecture-specific debugging

**Custom node images assessment:**
nix2container is not practical for k3d node images because:
- k3d overrides container entrypoints with its own orchestration scripts
- Node images require full k3s distribution, not application containers
- Default `rancher/k3s` images are well-maintained and sufficient
- nix2container remains valuable for application containers only

**Trade-offs accepted:**

- Architecture difference: local aarch64 vs production x86_64
- eBPF features limited by container runtime
- Full eBPF validation requires CI/CD on actual VMs
- Docker bridge networking differs from production overlay

**Trade-offs avoided (vs current approach):**

- Nested virtualization eBPF failures (eliminated)
- Total Cilium non-functionality (resolved)
- Rosetta emulation overhead (eliminated)

## Migration Path

1. **Preserve current incus infrastructure** for non-Cilium workloads or future testing
2. **Add k3d + ctlptl as primary option** in development workflow
3. **Update ADR-001/ADR-002** to document the evolution
4. **Create `02b-local-development-k3d.md`** workflow documentation
5. **Update all kubernetes documentation** to reflect k3d as primary approach
6. **Evaluate after usage** whether to deprecate incus path entirely

## Consequences

### Enabled

- Functional Cilium networking for local development
- Kubernetes distribution parity with production (k3s)
- Fast iteration cycles (k3d startup under 10 seconds with OrbStack)
- Simpler tooling (no nested virtualization debugging)
- Team-shareable cluster configurations via ctlptl
- Multi-node cluster testing capability

### Constrained

- eBPF features limited by container runtime
- Node isolation weaker than VM-based approach
- Architecture difference (aarch64 local vs x86_64 production)
- OrbStack/Docker dependency for container runtime

## Related Decisions

- ADR-001: Local Development Architecture (partially superseded for local development)
- ADR-002: Bootstrap Architecture Independence (validates aarch64 for ClusterAPI control plane)
- ADR-004: Local Cluster Networking (port forwarding patterns simplified with Docker bridge)
- nix-2hd: Cilium pod-to-host networking investigation (motivating issue)
- nix-50f: Local Development Cluster epic (scope expansion)
- nix-tv8: k3d + ctlptl implementation issue

## Decision Trail

This ADR evolved through systematic investigation:

1. **nix-2hd investigation** (2026-01-18/19): Identified Cilium eBPF failure in Incus/Colima nested virtualization
2. **Root cause analysis**: macOS Hypervisor.framework lacks nested virtualization support
3. **Alternative evaluation**: OrbStack (no CNI), kind (viable), k3d (recommended), native without Cilium (fallback)
4. **k3d selection rationale**: Production k3s parity outweighs x86_64 architecture parity
5. **OrbStack integration**: Existing user setup provides optimal container runtime performance

Investigation artifacts:
- Kernel tests: 6.12 LTS and 6.18 latest (both failed)
- Cilium configuration tests: TCX, Tunnel, Native routing (all failed in nested virt)
- Community research: GitHub issues #39930 (OrbStack), #742 (OrbStack CNI), CVE-2025-37959
