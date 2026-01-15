---
title: Kubernetes + Nix documentation
---

# Kubernetes + Nix documentation

This documentation suite covers the vanixiets Kubernetes + Nix development platform.
It provides reference architecture, component configurations, and workflow guides for local development through production deployment.

Target audience: developers working with vanixiets infrastructure who need to understand, configure, or deploy the Kubernetes stack.

## Quick start

For local development:
1. [Environment setup](workflows/01-environment-setup.md) - Install and configure local tools
2. [Local development](workflows/02-local-development.md) - Start k3s in Colima VM

For production deployment:
1. [ClusterAPI bootstrap](workflows/03-clusterapi-bootstrap.md) - Prepare management cluster
2. [Hetzner deployment](workflows/04-hetzner-deployment.md) - Deploy to Hetzner Cloud

## Documentation map

| Document | Path | Description |
|----------|------|-------------|
| Reference architecture | [architecture/reference-architecture.md](architecture/reference-architecture.md) | Comprehensive system architecture with diagrams and design principles |
| NixOS k3s server | [components/nixos-k3s-server.md](components/nixos-k3s-server.md) | k3s NixOS module configuration |
| Cilium CNI | [components/cilium-cni.md](components/cilium-cni.md) | Cilium container networking setup |
| step-ca TLS | [components/step-ca-tls.md](components/step-ca-tls.md) | Local certificate authority for development |
| cert-manager | [components/cert-manager.md](components/cert-manager.md) | Certificate lifecycle automation |
| sops-secrets-operator | [components/sops-secrets-operator.md](components/sops-secrets-operator.md) | GitOps-native secret management |
| nix-csi | [components/nix-csi.md](components/nix-csi.md) | Container storage interface with Nix integration |
| Environment setup | [workflows/01-environment-setup.md](workflows/01-environment-setup.md) | Initial local environment configuration |
| Local development | [workflows/02-local-development.md](workflows/02-local-development.md) | Running k3s locally in Colima |
| ClusterAPI bootstrap | [workflows/03-clusterapi-bootstrap.md](workflows/03-clusterapi-bootstrap.md) | Management cluster preparation |
| Hetzner deployment | [workflows/04-hetzner-deployment.md](workflows/04-hetzner-deployment.md) | Production deployment to Hetzner |
| GitOps operations | [workflows/05-gitops-operations.md](workflows/05-gitops-operations.md) | Day-2 operations and maintenance |
| ADR-001 | [decisions/ADR-001-local-dev-architecture.md](decisions/ADR-001-local-dev-architecture.md) | Local development architecture decision |

## Architecture overview

The platform follows a four-layer architecture with production parity between local and remote environments.

```text
+------------------+     +------------------+
|  LOCAL (macOS)   |     |  PRODUCTION      |
+------------------+     +------------------+
| Colima + Rosetta |     | Hetzner VMs      |
| NixOS VM (x86)   |     | NixOS + clan     |
| k3s server       |     | k3s / ClusterAPI |
| Cluster stack    |     | Cluster stack    |
+------------------+     +------------------+
           \                   /
            \                 /
             v               v
        +------------------------+
        |   Shared Nix Modules   |
        +------------------------+
```

See [reference architecture](architecture/reference-architecture.md) for the complete system diagram and detailed layer descriptions.

## Component index

- [nixos-k3s-server.md](components/nixos-k3s-server.md) - k3s NixOS module with server and agent configurations
- [cilium-cni.md](components/cilium-cni.md) - Cilium CNI for eBPF-based networking and network policies
- [step-ca-tls.md](components/step-ca-tls.md) - Smallstep CA for local development TLS certificates
- [cert-manager.md](components/cert-manager.md) - Automated certificate issuance and renewal
- [sops-secrets-operator.md](components/sops-secrets-operator.md) - In-cluster SOPS decryption for Kubernetes secrets
- [nix-csi.md](components/nix-csi.md) - CSI driver with Nix store integration

## Workflow index

- [01-environment-setup.md](workflows/01-environment-setup.md) - Install Colima, Nix tools, and configure local environment
- [02-local-development.md](workflows/02-local-development.md) - Start NixOS VM with k3s for local Kubernetes development
- [03-clusterapi-bootstrap.md](workflows/03-clusterapi-bootstrap.md) - Initialize ClusterAPI management cluster
- [04-hetzner-deployment.md](workflows/04-hetzner-deployment.md) - Deploy workload clusters to Hetzner Cloud
- [05-gitops-operations.md](workflows/05-gitops-operations.md) - Ongoing cluster operations and maintenance procedures

## Decision records

- [ADR-001: Local development architecture](decisions/ADR-001-local-dev-architecture.md) - Selection of Colima + NixOS VM approach for local k3s development

## Key commands quick reference

| Action | Command |
|--------|---------|
| Start local VM | `colima start nixos --vm-type=vz --arch=x86_64` |
| Check k3s status | `kubectl get nodes` |
| Deploy manifests | `kluctl deploy -t local` |
| View cluster info | `kubectl cluster-info` |
| Check all pods | `kubectl get pods -A` |
| Validate secrets | `kubectl get secrets -A` |

## Related resources

### Reference repositories

- [hetzkube](https://github.com/Lillecarl/hetzkube) - easykubenix Hetzner example
- [easykubenix](https://github.com/Lillecarl/easykubenix) - Nix-based Kubernetes manifests
- [nixidy](https://github.com/arnarg/nixidy) - ArgoCD rendered manifests pattern

### Project context

See [vanixiets CLAUDE.md](/CLAUDE.md) for complete project context including:
- Machine fleet details
- Related local repositories in `~/projects/nix-workspace/` and `~/projects/sciops-workspace/`
- Current task overview for IaC GitOps Kubernetes deployment
