# ADR-002: Bootstrap Architecture Independence

## Status

Accepted (supersedes ADR-001 Decision 1)

## Context

The vanixiets infrastructure requires a local Kubernetes development environment on Apple Silicon (aarch64-darwin) hosts.
Production Hetzner clusters target x86_64-linux for server availability and cost optimization.
ClusterAPI bootstrap pattern requires a local management cluster to provision and manage remote cloud clusters.

ADR-001 Decision 1 specified x86_64-linux via Rosetta 2 emulation for production parity.
During implementation, practical constraints emerged: incus and Colima cannot run x86_64-linux VMs on aarch64 hosts.
Apple's Virtualization.framework only supports same-architecture guests; Rosetta provides userspace binary translation within an aarch64-linux guest, not full x86_64 VM emulation.

This ADR revises the architecture strategy based on these implementation discoveries and ClusterAPI's actual operational model.

## Decisions

### Decision 1: Native aarch64-linux for Local Development

**Context**: Local development requires Linux VMs on Apple Silicon hosts.
ADR-001 assumed x86_64-linux VMs via Rosetta were possible; they are not.

**Decision**: Use native aarch64-linux for the local bootstrap and development cluster.

**Rationale**: This is the only viable option for full VM virtualization on Apple Silicon.
Native execution provides optimal performance without emulation overhead.
ClusterAPI functionality does not require architecture matching between management and workload clusters.

### Decision 2: Architecture Independence for ClusterAPI

**Context**: ClusterAPI operates as a control plane that provisions infrastructure via cloud provider APIs.
The management cluster runs controllers that create and manage remote cluster nodes.

**Decision**: ClusterAPI controllers on the local aarch64-linux cluster provision and manage x86_64-linux nodes on Hetzner.

**Rationale**: ClusterAPI is purely a control plane operation.
Controllers call Hetzner cloud APIs to provision x86_64 servers; they do not execute workloads on target nodes.
The architecture of the management cluster has no bearing on the architecture of managed clusters.
Container images for ClusterAPI, cert-manager, and ArgoCD are published as multi-architecture manifests.

### Decision 3: Production Parity via CI/CD

**Context**: ADR-001 sought production parity through local x86_64 emulation.
This goal remains valid but the mechanism changes.

**Decision**: Achieve production architecture parity through CI/CD pipelines rather than local emulation.
Local development validates logic and configuration; CI validates architecture-specific behavior.

**Rationale**: Architecture-specific issues (binary compatibility, platform-dependent optimizations) are legitimate concerns.
However, these issues are better caught by automated testing on actual x86_64 infrastructure than by emulated local development.
CI pipelines on x86_64 runners provide higher-fidelity architecture testing than Rosetta userspace translation.

## Consequences

### Enabled

- Native performance for local development without emulation overhead
- Simplified local tooling: incus and Colima work without architecture workarounds
- Faster iteration cycles during development
- ClusterAPI transfer point flexibility: management can move between clusters at various lifecycle phases

### Constrained

- Architecture-specific bugs must be caught in CI or staging, not local development
- Local and production container images may differ at the binary level despite identical configuration
- Developers must understand that local success does not guarantee x86_64 compatibility

### Trade-offs vs ADR-001

ADR-001 Decision 1 prioritized production parity through local architecture matching.
ADR-002 revises this balance: local development prioritizes iteration speed; production parity is enforced through CI/CD.

This evolution reflects practical constraints discovered during implementation.
The underlying goal of catching architecture issues before production remains; only the mechanism changes.

## ClusterAPI Transfer Point

The optimal timing for `clusterctl move` (transferring cluster management from bootstrap to workload cluster) is experimental.
The expected transfer point is between Phase 3b (ArgoCD installation) and Phase 4 (nixidy applications).

The goal state is a fully self-managed cluster where:
- The workload cluster runs its own ClusterAPI controllers
- ArgoCD manages itself and all applications via nixidy-generated manifests
- The local bootstrap cluster can be destroyed after pivot completes

Transfer point refinement will be documented as operational experience accumulates.

## Related Decisions

- ADR-001: Local Development Architecture (partially superseded by this document)
- See `reference-architecture.md` for the four-phase architecture including nixidy/ArgoCD patterns
