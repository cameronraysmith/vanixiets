# ADR-001: Local Development Architecture

## Status

Accepted

## Context

The vanixiets infrastructure requires a local Kubernetes development environment that provides high-fidelity parity with production Hetzner deployment.
This environment must support the full GitOps workflow including ClusterAPI bootstrap, secret management, TLS certificate issuance, and application deployment.
The host platform is macOS on Apple Silicon (aarch64-darwin), while production targets are Hetzner cloud instances running x86_64-linux.

This ADR captures the foundational architectural decisions for the local development environment.

## Decisions

### Decision 1: x86_64-linux via Rosetta Emulation

**Context**: The development host is macOS aarch64-darwin (Apple Silicon), but production Hetzner nodes run x86_64-linux.

**Decision**: Use x86_64-linux NixOS VMs via Apple's Rosetta 2 emulation rather than native aarch64-linux.

**Rationale**: Exact architecture parity with production catches compatibility issues early in the development cycle.
Binary compatibility problems, architecture-specific optimizations, and platform-dependent behavior are detected locally rather than during production deployment.
Rosetta 2 provides acceptable performance for development workloads while maintaining this parity.

**Alternatives Considered**:
- Native aarch64-linux VMs would provide better performance but sacrifice production parity.
  Architecture-specific issues would only surface during production deployment.

### Decision 2: Dual Colima Profiles

**Context**: The development workflow requires both a persistent development environment for iterative work and an ephemeral ClusterAPI management cluster for bootstrap operations.

**Decision**: Maintain two separate Colima VM profiles: `k3s-dev` for persistent development and `k3s-capi` for ephemeral ClusterAPI bootstrap.

**Rationale**: Clean separation of concerns prevents resource conflicts and state contamination between the persistent development environment and the ephemeral bootstrap cluster.
The `k3s-capi` profile is created for ClusterAPI pivot operations and destroyed after the workload cluster becomes self-managing.
This mirrors the production bootstrap pattern where the management cluster is temporary.

**Alternatives Considered**:
- A single VM for both purposes would create resource conflicts and complicate lifecycle management.
- kind for bootstrap would introduce Docker as an additional dependency and diverge from the Colima-based workflow.

### Decision 3: sslip.io for Local DNS

**Context**: Local development requires hostname-based routing for services including ArgoCD, Grafana, and application endpoints.

**Decision**: Use sslip.io wildcard DNS service for local hostname resolution.

**Rationale**: sslip.io provides zero-configuration wildcard DNS that works immediately without local infrastructure.
Hostnames like `argocd.192.168.64.10.sslip.io` resolve to the embedded IP address.
For development purposes, reliance on an external service is acceptable given the simplicity benefit.

**Alternatives Considered**:
- Local CoreDNS would provide self-contained DNS but requires additional setup and maintenance.
- Manual `/etc/hosts` management does not scale and requires constant updates as services change.

### Decision 4: step-ca for Local TLS

**Context**: Development requires TLS certificates to validate cert-manager workflows and test secure service communication.

**Decision**: Run step-ca as a local ACME server for certificate issuance.

**Rationale**: step-ca provides the same ACME protocol used by Let's Encrypt in production.
The cert-manager configuration is identical between local and production environments except for the issuer URL.
This validates the complete certificate lifecycle including issuance, renewal, and revocation workflows.

**Alternatives Considered**:
- Self-signed certificates would not exercise the ACME workflow that production uses.
- mkcert provides easy local certificates but is not Kubernetes-native and does not integrate with cert-manager.

### Decision 5: sops-secrets-operator for Secret Management

**Context**: Kubernetes workloads require secrets that must be stored encrypted in git following GitOps principles.

**Decision**: Use sops-secrets-operator with age encryption keys for Kubernetes secret management.

**Rationale**: This aligns with the existing sops-nix patterns used throughout vanixiets infrastructure.
Secrets remain encrypted in the git repository and are decrypted only within the cluster.
No external secret store is required, reducing operational complexity and external dependencies.

**Alternatives Considered**:
- External Secrets Operator (ESO) does not have a SOPS provider, which would break alignment with existing patterns.
- HashiCorp Vault provides robust secret management but introduces significant operational overhead inappropriate for this scale.

### Decision 6: Cilium CNI

**Context**: Pod networking requires a Container Network Interface (CNI) plugin.

**Decision**: Use Cilium with kube-proxy replacement as the CNI.

**Rationale**: Cilium provides eBPF-based networking with superior performance and observability.
Native Gateway API support enables modern ingress patterns.
This maintains production parity with hetzkube which uses Cilium.

**Alternatives Considered**:
- k3s default flannel is simpler but lacks advanced features like Gateway API and eBPF observability.
- Calico provides similar features but is more complex to configure with k3s.

### Decision 7: easykubenix/kluctl for Infrastructure, nixidy/ArgoCD for Applications

**Context**: GitOps deployment requires a mechanism to render and apply Kubernetes manifests from Nix expressions.
The architecture must cleanly separate infrastructure concerns from application workload management.

**Decision**: Use easykubenix for manifest generation with kluctl for infrastructure deployment (Phases 1-3).
Use nixidy with ArgoCD for application-level GitOps (Phase 4).
easykubenix installs ArgoCD as cluster infrastructure; nixidy generates Application resources for ArgoCD to manage.

**Rationale**: kluctl provides simpler deployment semantics for infrastructure components where the reconciliation loop of ArgoCD adds complexity without benefit.
ArgoCD becomes valuable for applications where self-healing, automatic sync, and the application catalog provide operational benefits.
The boundary is infrastructure versus applications, not now versus later.
easykubenix handles everything up to and including ArgoCD installation; nixidy handles everything after ArgoCD exists.

**Alternatives Considered**:
- ArgoCD for everything would complicate the bootstrap sequence and add overhead for infrastructure components.
- Flux provides native SOPS integration but diverges from the ArgoCD ecosystem used in related projects.

### Decision 8: NixOS VM via nixos-generators

**Context**: The local Kubernetes environment requires a virtualized NixOS instance on macOS.

**Decision**: Generate NixOS qcow2-efi images using nixos-generators and run them via Colima's vz (Virtualization.framework) backend.

**Rationale**: This approach provides a single virtualization layer with declarative image generation.
NixOS configuration defines the complete VM state, enabling reproducible development environments.
Full VM isolation provides stronger security boundaries than container-based approaches.

**Alternatives Considered**:
- Incus containers would provide less isolation and introduce a declarative lifecycle management gap.
- microvm would introduce nested virtualization overhead and additional complexity.

## Consequences

### Enabled

- High-fidelity local development with production architecture parity
- Reproducible development environments via NixOS declarations
- GitOps workflow validation before production deployment
- Secret management consistent with existing sops-nix patterns
- Modern networking features via Cilium eBPF

### Constrained

- Development performance reduced by Rosetta emulation overhead
- External dependency on sslip.io for DNS (acceptable for development)
- Two-VM resource overhead for ClusterAPI bootstrap operations
- Two deployment mechanisms reflect the infrastructure/application boundary (easykubenix/kluctl for infrastructure, nixidy/ArgoCD for applications)

## Related Decisions

- See `reference-architecture.md` for the complete local development environment specification and the four-phase architecture including nixidy/ArgoCD patterns.
