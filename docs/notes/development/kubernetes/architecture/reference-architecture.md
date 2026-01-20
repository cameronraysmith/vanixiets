---
title: Reference architecture
---

# Reference architecture

This document provides the comprehensive reference architecture for the vanixiets Kubernetes + Nix development platform.
It synthesizes all component and workflow documentation into an authoritative reference for the entire system.

## Table of contents

1. [Executive summary](#executive-summary)
2. [System overview](#system-overview)
3. [Architecture layers](#architecture-layers)
4. [Local development environment](#local-development-environment)
5. [Production environment (Hetzner)](#production-environment-hetzner)
6. [Component summary table](#component-summary-table)
7. [Tool boundaries](#tool-boundaries)
8. [Code reuse strategy](#code-reuse-strategy)
9. [Local to production parity matrix](#local-to-production-parity-matrix)
10. [Migration path](#migration-path)
11. [Future considerations](#future-considerations)
12. [Quick reference](#quick-reference)

## Executive summary

### Architecture diagram

```text
+-----------------------------------------------------------------------------------+
|                              vanixiets Platform                                   |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  LOCAL (aarch64-darwin)                    PRODUCTION (x86_64-linux)              |
|  ========================                  ============================           |
|                                                                                   |
|  +----------------------+                  +---------------------------+          |
|  | macOS Host           |                  | Hetzner Cloud             |          |
|  | (stibnite/blackphos) |                  |                           |          |
|  +----------+-----------+                  |  +---------------------+  |          |
|             |                              |  | terranix/opentofu   |  |          |
|             v                              |  | (VM provisioning)   |  |          |
|  +----------+-----------+                  |  +----------+----------+  |          |
|  | OrbStack             |                  |             |             |          |
|  | (container runtime)  |                  |             v             |          |
|  +----------+-----------+                  |  +----------+----------+  |          |
|             |                              |  | clan/NixOS          |  |          |
|             v                              |  | (OS configuration)  |  |          |
|  +----------+-----------+                  |  +----------+----------+  |          |
|  | k3d (k3s-in-docker)  |                  |             |             |          |
|  |  +----------------+  |                  |             v             |          |
|  |  | k3s server     |  |                  |  +----------+----------+  |          |
|  |  +----------------+  |                  |  | k3s / ClusterAPI    |  |          |
|  +----------+-----------+                  |  | (cluster lifecycle) |  |          |
|             |                              |  +----------+----------+  |          |
|             v                              |             |             |          |
|  +----------+-----------+                  |             v             |          |
|  | easykubenix/kluctl   |                  |  +----------+----------+  |          |
|  | (manifests/deploy)   |                  |  | easykubenix/kluctl  |  |          |
|  +----------+-----------+                  |  | (manifests/deploy)  |  |          |
|             |                              |  +----------+----------+  |          |
|             v                              |             |             |          |
|  +----------+-----------+                  |             v             |          |
|  | Cluster Stack (3b)   |                  |  +----------+----------+  |          |
|  | - Cilium CNI         |                  |  | Cluster Stack (3b)  |  |          |
|  | - step-ca (TLS)      |                  |  | - Cilium CNI        |  |          |
|  | - cert-manager       |                  |  | - Let's Encrypt     |  |          |
|  | - sops-secrets-op    |                  |  | - cert-manager      |  |          |
|  | - nix-csi            |                  |  | - sops-secrets-op   |  |          |
|  | - ArgoCD             |                  |  | - nix-csi           |  |          |
|  +----------------------+                  |  | - external-dns      |  |          |
|                                            |  | - ArgoCD            |  |          |
|                                            |  +---------------------+  |          |
|  +----------------------+                  +---------------------------+          |
|  | k3d (ephemeral)      |                                                         |
|  | ClusterAPI bootstrap |-------> pivot -------> self-managing cluster            |
|  +----------------------+                                                         |
|                                                                                   |
+-----------------------------------------------------------------------------------+
|                              Shared Nix Modules                                   |
|  +-----------------------------------------------------------------------------+  |
|  | modules/nixos/k3s-server/ | modules/k8s/* | .sops.yaml | flake.nix         |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

### Key design principles

The architecture follows these foundational principles.

*Production parity*: Local development environments run the identical Kubernetes distribution (k3s) as production.
While architecture differs (aarch64 local vs x86_64 production), the k3s and Cilium configuration catches most configuration errors, networking issues, and compatibility problems before deployment.

*Declarative configuration*: All infrastructure, cluster state, and application deployments are defined in Nix modules.
Changes flow through version control with reproducible builds.

*Self-managing clusters*: After bootstrap, production clusters own their ClusterAPI resources.
Infrastructure changes do not require an external management plane.

*GitOps-native secrets*: SOPS-encrypted secrets live in git.
The sops-secrets-operator decrypts at runtime using age keys, creating a unified secret management workflow across NixOS hosts and Kubernetes.

*Layered responsibility*: Each tool handles a specific layer (terranix for VMs, clan for OS, ClusterAPI for cluster lifecycle, easykubenix for manifests).
Clear boundaries prevent overlap and simplify debugging.

### Target audience

This document serves operators managing vanixiets Kubernetes clusters, developers deploying applications to the platform, and contributors extending the Nix module infrastructure.
It assumes familiarity with Nix, Kubernetes, and the concept of infrastructure as code.

## System overview

### Problem statement: Why Nix + Kubernetes?

Traditional Kubernetes deployments suffer from configuration drift, environment inconsistencies, and opaque dependency management.
Combining Nix with Kubernetes addresses these challenges.

*Reproducibility*: Nix evaluation produces byte-identical outputs given the same inputs.
Kubernetes manifests generated from Nix are deterministic and auditable.

*Environment parity*: The same NixOS modules configure both local VMs and production servers.
Differences are explicit and intentional rather than accidental.

*Unified tooling*: Nix manages the entire stack from host OS configuration through container images to Kubernetes manifests.
A single language and ecosystem replaces disparate tools.

*Atomic updates*: NixOS generations and ClusterAPI machine rollouts provide atomic, rollback-capable updates.
Failed deployments revert to known-good states.

### Goals

The platform achieves the following objectives.

*Production-parity local development*: Run the complete production stack locally with identical configuration.
Catch issues during development rather than after deployment.

*Declarative cluster lifecycle*: Define clusters in Nix, provision via ClusterAPI, and manage through GitOps.
No manual kubectl operations in steady state.

*Reproducible infrastructure*: Given a Nix flake lock, rebuild the exact same infrastructure.
Time-travel debugging by checking out historical commits.

*Unified secret management*: SOPS with age keys handles secrets for NixOS hosts, CI pipelines, and Kubernetes clusters.
One workflow, one set of keys.

### Non-goals

The architecture explicitly does not address these concerns.

*Multi-cloud abstraction*: The platform targets Hetzner production deployments.
GCP, AWS, and other providers are future considerations, not current scope.

*General-purpose Kubernetes distribution*: This is not a Kubernetes distribution.
It is a specific architecture for the vanixiets project using k3s.

*Zero-touch GitOps during infrastructure bootstrap*: The current prototype implements Phases 1-3b using kluctl for explicit infrastructure deployments.
ArgoCD is installed by easykubenix (Phase 3b); application management via nixidy/ArgoCD (Phase 4) is part of the committed four-phase architecture.

*Managed Kubernetes compatibility*: The architecture uses k3s with ClusterAPI.
GKE, EKS, and AKS patterns differ significantly.

## Architecture layers

The platform consists of four distinct phases, each with clear responsibilities and boundaries.
Phase 3 subdivides into 3a (ClusterAPI) and 3b (cluster infrastructure via easykubenix), reflecting the dependency between cluster lifecycle and infrastructure deployment.

### Layer 1: Base infrastructure (terranix/opentofu)

terranix generates OpenTofu configuration from Nix modules, provisioning cloud resources.

*Scope*: Virtual machines, networks, firewalls, DNS records, volumes, SSH keys.

*Input*: Nix modules in `modules/terranix/`.

*Output*: Terraform JSON consumed by `tofu apply`.

*Persistence*: Terraform state files (local or remote backend).

The terranix layer handles the lowest-level cloud primitives.
It creates VMs that become cluster nodes but does not configure them beyond network bootstrapping.

```text
+-------------------+
| Nix modules       |
| (terranix/*.nix)  |
+--------+----------+
         |
         v
+--------+----------+
| terranix generate |
+--------+----------+
         |
         v
+--------+----------+
| main.tf.json      |
+--------+----------+
         |
         v
+--------+----------+
| tofu apply        |
+--------+----------+
         |
         v
+--------+----------+
| Hetzner VMs       |
| (bare Debian)     |
+-------------------+
```

### Layer 2: OS configuration (clan/NixOS)

Clan provisions NixOS configurations to machines, transforming bare VMs into configured hosts.

*Scope*: System packages, services, users, networking, firewall, k3s prerequisites.

*Input*: Machine modules in `modules/machines/nixos/`.

*Output*: NixOS system closures deployed via `clan machines install`.

*Persistence*: NixOS generations on target machines.

The clan layer installs and configures the operating system.
It prepares machines for Kubernetes by configuring kernel modules, sysctl settings, and k3s with appropriate flags.

```text
+-------------------+
| Machine modules   |
| (machines/nixos/) |
+--------+----------+
         |
         v
+--------+----------+
| clan machines     |
| build/install     |
+--------+----------+
         |
         v (SSH + nixos-install)
+--------+----------+
| NixOS hosts       |
| (k3s running)     |
+-------------------+
```

### Layer 3a: Cluster lifecycle (ClusterAPI)

ClusterAPI manages Kubernetes cluster infrastructure through declarative resources.

*Scope*: Control plane nodes, worker pools, machine health checks, node replacement.

*Input*: ClusterAPI CRDs (Cluster, MachineDeployment, HCloudMachineTemplate).

*Output*: Kubernetes cluster with managed node lifecycle.

*Persistence*: ClusterAPI resources in the workload cluster (after pivot).

ClusterAPI handles machine provisioning within Kubernetes.
After initial bootstrap from a temporary management cluster, the production cluster assumes self-management responsibility.

```text
+-------------------+
| Local k3s-capi    |
| (bootstrap only)  |
+--------+----------+
         |
         | clusterctl init
         v
+--------+----------+
| ClusterAPI        |
| controllers       |
+--------+----------+
         |
         | provision via Hetzner API
         v
+--------+----------+
| Workload cluster  |
| (kubeadm nodes)   |
+--------+----------+
         |
         | clusterctl move (pivot)
         v
+--------+----------+
| Self-managing     |
| cluster           |
+-------------------+
```

### Layer 3b: Cluster infrastructure (easykubenix/kluctl)

easykubenix generates Kubernetes manifests from Nix modules; kluctl deploys them with discriminator-based tracking.
This phase installs ArgoCD as cluster infrastructure, enabling Phase 4.

*Scope*: CNI (Cilium), certificate management, secrets operator, storage provisioner, ArgoCD, core addons.

*Input*: Kubernetes modules in `modules/k8s/`.

*Output*: YAML manifests deployed via `kluctl deploy`.

*Persistence*: Kubernetes resources with discriminator labels.

This layer deploys everything needed to run workloads on the cluster, including ArgoCD itself.
Cilium provides networking, cert-manager handles TLS, sops-secrets-operator decrypts secrets, and ArgoCD enables GitOps for Phase 4 applications.

```text
+-------------------+
| easykubenix       |
| modules (k8s/*.nix)|
+--------+----------+
         |
         v
+--------+----------+
| nix build         |
| .#kubenix...      |
+--------+----------+
         |
         v
+--------+----------+
| YAML manifests    |
+--------+----------+
         |
         v
+--------+----------+
| kluctl deploy     |
| --discriminator   |
+--------+----------+
         |
         v
+--------+----------+
| Kubernetes cluster|
| (infra running)   |
+-------------------+
```

### Layer 4: Applications (nixidy/ArgoCD)

nixidy generates ArgoCD Application resources from Nix modules for application workloads.
This phase depends on ArgoCD being installed by Phase 3b; nixidy does not install ArgoCD.

*Scope*: Application Deployments, Services, Ingresses, ConfigMaps, application-specific secrets.

*Input*: Application modules with Helm chart references.

*Output*: ArgoCD Applications with rendered manifest paths.

*Persistence*: GitOps-managed resources with continuous reconciliation.

Phase 4 can only begin after easykubenix deploys ArgoCD in Phase 3b.
The current prototype demonstrates Phases 1-3b; Phase 4 application examples follow the same nixidy patterns documented in the nixidy-cluster reference (`~/projects/sciops-workspace/nixidy-cluster`).

```text
+-------------------+
| nixidy modules    |
+--------+----------+
         |
         v
+--------+----------+
| nixidy build      |
+--------+----------+
         |
         v
+--------+----------+
| ArgoCD Apps +     |
| rendered YAML     |
+--------+----------+
         |
         v
+--------+----------+
| ArgoCD sync       |
+--------+----------+
         |
         v
+--------+----------+
| Application pods  |
+-------------------+
```

### Phase 3b to Phase 4 handoff

The transition from infrastructure deployment (Phase 3b) to application management (Phase 4) requires ArgoCD to be operational.

Phase 3b (easykubenix/kluctl) deploys:
- Cilium CNI (networking foundation)
- cert-manager and ClusterIssuers
- sops-secrets-operator with age key
- local-path-provisioner and nix-csi
- ArgoCD itself (required for Phase 4)
- metrics-server and external-dns

Phase 4 (nixidy/ArgoCD) takes over after ArgoCD exists:
- nixidy generates ArgoCD Application CRs from Nix modules
- Application CRs reference git repositories containing rendered manifests
- ArgoCD continuously reconciles application state

After initial bootstrap, ArgoCD can manage its own configuration through nixidy (self-updating pattern).
Infrastructure changes still flow through easykubenix/kluctl to maintain separation of concerns.

### ClusterAPI transfer point

The optimal timing for `clusterctl move` (pivoting ClusterAPI resources to the workload cluster) remains experimental.
The likely sequence:

1. Phase 3b infrastructure deployment completes on workload cluster
2. Verify ArgoCD operational and cluster stable
3. Execute `clusterctl move --to-kubeconfig ./workload.kubeconfig`
4. Delete local k3s-capi bootstrap cluster
5. Phase 4 application deployment begins via nixidy

After pivot, the production cluster is fully self-managed: ClusterAPI handles node lifecycle, ArgoCD handles applications, and nixidy generates all Application CRs.
Local development validates this entire sequence before production deployment.

## Local development environment

### k3d architecture

Local development uses k3d (k3s-in-docker) running on OrbStack per ADR-005.
This approach supersedes the previous Colima + NixOS VM architecture due to nested virtualization issues with Cilium eBPF.

*local-k3d*: Development workloads and day-to-day iteration.
This cluster runs continuously during development sessions.

| Setting | Value | Rationale |
|---------|-------|-----------|
| Servers | 1 | Single control-plane node |
| Agents | 0 | No dedicated worker nodes |
| Architecture | arm64 | Native Apple Silicon |
| Container runtime | OrbStack | Superior macOS performance |
| CNI | Cilium | Production parity |

*capi-bootstrap*: ClusterAPI bootstrap operations.
This cluster is ephemeral, created when bootstrapping Hetzner clusters and destroyed after pivot.

| Setting | Value | Rationale |
|---------|-------|-----------|
| Servers | 1 | Minimal management cluster |
| Agents | 0 | ClusterAPI controllers only |
| Architecture | arm64 | Native performance |
| Lifecycle | Ephemeral | Destroyed after pivot |

### Architecture difference rationale

ADR-005 documents the decision to use native arm64 locally rather than x86_64 emulation.

*Kubernetes distribution parity*: k3d uses k3s, matching Hetzner production exactly.
Distribution-level compatibility is more valuable than architecture parity for most development workflows.

*Container image availability*: Modern container images (including Cilium) provide multi-arch support.
arm64 variants work seamlessly.

*Performance*: Native arm64 execution avoids Rosetta overhead (20% performance cost).
OrbStack container runtime provides 10x faster startup than Docker Desktop.

*eBPF compatibility*: Nested virtualization (Colima VM inside macOS) broke Cilium eBPF networking.
Container-based k3d provides functional (though limited) eBPF support.

Architecture-specific issues are rare and better caught in CI on actual x86_64 infrastructure.

### k3d cluster configuration

k3d clusters are configured via YAML files with Cilium-compatible flags.

Key configuration:

- `K3D_FIX_MOUNTS=1` for BPF mount propagation
- `--flannel-backend=none` for external CNI
- `--disable-network-policy` for Cilium replacement
- `--disable-kube-proxy` for Cilium kube-proxy replacement
- Port mappings for localhost access (80, 443, 6443)

### k3s configuration

k3s runs with bundled components disabled to enable Cilium CNI.

Disabled components:

- `flannel` - Cilium replaces flannel
- `local-storage` - External storage provisioner
- `metrics-server` - Deploy via Helm
- `servicelb` - Cilium provides load balancing
- `traefik` - External ingress controller

Extra flags:

- `--flannel-backend=none` - Required for external CNI
- `--disable-network-policy` - Cilium handles NetworkPolicy
- `--disable-kube-proxy` - Cilium replaces kube-proxy
- `--disable-cloud-controller` - No cloud provider

## Production environment (Hetzner)

### VM provisioning via terranix

terranix defines Hetzner Cloud resources in Nix modules.

```nix
machines = {
  kube-control = {
    enabled = true;
    serverType = "cpx31";  # 4 vCPU, 8GB RAM
    location = "fsn1";
    image = "debian-12";
  };
};
```

Workflow:

1. Generate terraform JSON: `nix run .#terraform-generate`
2. Initialize providers: `cd terraform && tofu init`
3. Apply infrastructure: `tofu apply`

The terraform configuration triggers `clan machines install` via provisioner to bootstrap NixOS.

### NixOS configuration via clan

Clan deploys NixOS configurations to provisioned VMs.

Machine modules import shared NixOS modules for k3s prerequisites.

```nix
imports = [
  inputs.srvos.nixosModules.server
  inputs.srvos.nixosModules.hardware-hetzner-cloud
  flakeModules.k3s-server  # Kernel modules, sysctl, k3s config
];
```

Deployment:

```sh
clan machines build kube-control
clan machines install kube-control --target-host root@<ip>
```

### ClusterAPI bootstrap and pivot

Production clusters use ClusterAPI for node lifecycle management.

Bootstrap sequence:

1. Start local k3s-capi profile
2. Initialize ClusterAPI: `clusterctl init --infrastructure hetzner`
3. Apply cluster definition via easykubenix
4. Monitor machine provisioning
5. Update DNS for control plane endpoint
6. Extract workload cluster kubeconfig
7. Initialize ClusterAPI on workload cluster
8. Pivot resources: `clusterctl move --to-kubeconfig ./workload.kubeconfig`
9. Delete local k3s-capi profile

After pivot, the workload cluster manages its own infrastructure.

### Full stack deployment

Deploy the complete infrastructure stack via easykubenix and kluctl.

Deployment order (dependencies dictate sequence):

1. Cilium CNI - enables pod networking
2. CoreDNS - cluster DNS resolution
3. cert-manager - certificate lifecycle
4. ClusterIssuers - Let's Encrypt staging/production
5. sops-secrets-operator + age key - secret decryption
6. local-path-provisioner - dynamic PV provisioning
7. nix-csi - Nix store volumes
8. external-dns - automatic DNS records
9. metrics-server - resource metrics

Deployment command:

```sh
nix build .#k8s-manifests-full
kluctl deploy --discriminator vanixiets-full -y
```

## Component summary table

| Component | Purpose | Local configuration | Production configuration |
|-----------|---------|---------------------|--------------------------|
| OrbStack | Container runtime | Docker API for k3d | N/A |
| k3d | k3s-in-docker | Single-node cluster | N/A |
| NixOS | Operating system | N/A (container-based) | clan deployment |
| k3s | Kubernetes distribution | Single node, sqlite | Multi-node, etcd |
| Cilium | CNI + kube-proxy replacement | k8sServiceHost=127.0.0.1, limited eBPF | k8sServiceHost=VIP, full eBPF |
| step-ca | Local TLS CA | In-cluster ACME server | N/A |
| cert-manager | Certificate lifecycle | step-ca ClusterIssuer | Let's Encrypt ClusterIssuer |
| sops-secrets-operator | Secret decryption | dev age key | ci age key |
| nix-csi | Nix store volumes | Single-node, no cache | Multi-node with cache |
| external-dns | DNS automation | N/A | Cloudflare integration |
| local-path-provisioner | Storage | Default storage class | Default storage class |
| ClusterAPI | Cluster lifecycle | k3d bootstrap only | Self-managing after pivot |

## Tool boundaries

### terranix/opentofu

*Does*: Provision cloud VMs, networks, firewalls, DNS records, volumes.
Manage infrastructure state via terraform state files.

*Does not*: Configure operating systems, install software, manage Kubernetes resources.

*Handoff*: Creates VMs with network access; triggers clan installation via provisioner.

### clan

*Does*: Deploy NixOS configurations, manage host-level services, configure k3s prerequisites.

*Does not*: Manage Kubernetes resources, handle cluster scaling, provision cloud infrastructure.

*Handoff*: Produces running k3s nodes ready for Kubernetes workloads.

### ClusterAPI

*Does*: Manage Kubernetes node lifecycle, provision machines, handle rolling updates.

*Does not*: Deploy applications, manage cluster add-ons, handle day-2 Kubernetes operations.

*Handoff*: Provides healthy Kubernetes nodes; easykubenix deploys cluster infrastructure.

### easykubenix

*Does*: Generate Kubernetes manifests from Nix modules, manage Helm chart values.

*Does not*: Apply manifests to clusters, track deployment state, handle rollbacks.

*Handoff*: Produces YAML manifests; kluctl applies them to clusters.

### kluctl

*Does*: Apply manifests with discriminator tracking, prune orphaned resources, provide deployment diffs.

*Does not*: Generate manifests, manage secrets encryption, handle GitOps sync.

*Handoff*: Deploys resources to cluster; cluster runs workloads.

### sops-secrets-operator

*Does*: Decrypt SopsSecret resources, create Kubernetes Secrets.

*Does not*: Encrypt secrets, manage age keys, handle key rotation.

*Handoff*: Provides decrypted Secrets for application consumption.

### Phase 4: nixidy/ArgoCD

*Does*: Generate ArgoCD Applications, enable continuous reconciliation, provide drift detection.

*Does not*: Replace easykubenix for infrastructure, manage ClusterAPI resources.

*Handoff boundary*: easykubenix manages infrastructure up to and including ArgoCD installation (Phases 1-3b); nixidy manages applications after ArgoCD exists (Phase 4).

## Code reuse strategy

### Shared NixOS modules

NixOS modules in `modules/nixos/` are shared between local VMs and production hosts.

The k3s-server module configures kernel requirements, sysctl settings, firewall rules, and k3s with Cilium prerequisites.
Both local and production configurations import this module.

```nix
# Shared module
# modules/nixos/k3s-server/default.nix
{
  boot.kernelModules = [ "br_netfilter" "nf_conntrack" "overlay" ... ];
  boot.kernel.sysctl = { "net.ipv4.ip_forward" = 1; ... };
  services.k3s = { enable = true; ... };
}

# Local VM imports shared module
# Local NixOS configuration
{ imports = [ ./modules/nixos/k3s-server ]; }

# Production host imports shared module
# modules/machines/nixos/kube-control/default.nix
{ imports = [ flakeModules.k3s-server ]; }
```

### Stage-based easykubenix configuration

easykubenix uses stages to separate concerns.

```nix
config = lib.mkIf (config.stage == "full") {
  cilium.enable = true;
  cert-manager.enable = true;
  # ... full stack
};

config = lib.mkIf (config.stage == "capi") {
  # ClusterAPI resources only
};
```

Build with stage argument:

```sh
nix build .#kubenix.manifestYAMLFile --argstr stage full
nix build .#kubenix.manifestYAMLFile --argstr stage capi
```

### Environment-specific overrides

Configuration differences between local and production use conditional logic.

```nix
{
  cilium = {
    enable = true;
    k8sServiceHost = if config.stage == "local" then "127.0.0.1" else config.clusterHost;
    hubble.relay.enabled = config.stage != "local";
    hubble.ui.enabled = config.stage != "local";
  };
}
```

Shared defaults with environment overrides minimize duplication while preserving flexibility.

## Local to production parity matrix

| Aspect | Local (k3d) | Production (Hetzner) | Intentional difference |
|--------|-------------|----------------------|------------------------|
| Architecture | aarch64-linux (native) | x86_64-linux | Yes: native performance, CI catches arch issues |
| Kubernetes | k3s v1.31 | k3s v1.31 | No |
| CNI | Cilium (tunnel mode) | Cilium (tunnel mode) | No |
| kube-proxy | Cilium replacement | Cilium replacement | No |
| eBPF support | Limited (container runtime) | Full | Yes: container constraints |
| TLS CA | step-ca (local ACME) | Let's Encrypt | Yes: external CA requires public DNS |
| DNS | sslip.io | Cloudflare + external-dns | Yes: local lacks DNS management |
| Secrets | dev age key | ci age key | Yes: key separation for security |
| Storage | local-path-provisioner | local-path-provisioner | No |
| Node count | 1 | 3+ | Yes: HA unnecessary locally |
| ClusterAPI | Not used (direct k3d) | Self-managing | Yes: local uses simpler bootstrap |
| Hubble | Disabled | Full stack | Yes: resource savings locally |
| Networking | Docker bridge | Overlay | Yes: container-based vs VM-based |

## Migration path

### Current state: vanixiets prototype

The vanixiets repository implements the architecture described in this document.

Completed components:

- NixOS k3s server module with Cilium prerequisites
- Cilium CNI configuration for local and production
- cert-manager with step-ca (local) and Let's Encrypt (production)
- sops-secrets-operator integration
- nix-csi for Nix store volumes
- terranix Hetzner Cloud provisioning
- clan NixOS deployment
- easykubenix manifest generation
- kluctl deployment workflow

### Target state: sciops migration

The sciops workspace will migrate to this architecture, replacing:

- `test-cluster`: GKE bootstrap via terraform (replaced by terranix + ClusterAPI + Hetzner)
- `test-cluster-ops`: argocd-autopilot GitOps (replaced by easykubenix + kluctl for infrastructure, nixidy + ArgoCD for applications)

### Transition steps

1. Validate vanixiets prototype with production Hetzner cluster
2. Document and stabilize module interfaces
3. Create sciops-specific machine modules (GPU workers, data pipelines)
4. Migrate application definitions to easykubenix modules
5. Deploy sciops workloads to Hetzner cluster
6. Deprecate GKE infrastructure
7. Implement Phase 4 nixidy/ArgoCD for application layer

## Future considerations

### Phase 4 implementation notes

The four-phase architecture separates infrastructure (Phases 1-3b via easykubenix/kluctl) from applications (Phase 4 via nixidy/ArgoCD).
The current prototype implements Phases 1-3b; Phase 4 patterns are documented here for implementation reference.

ArgoCD benefits for application management:

- Continuous reconciliation (self-healing)
- Drift detection UI
- Sync policies and approval gates
- Multi-cluster ApplicationSets

Tool boundary:

- easykubenix/kluctl: ClusterAPI, CNI, CSI, core addons, ArgoCD itself (infrastructure)
- nixidy/ArgoCD: Application workloads, application secrets, ingress configuration (applications)

### Multi-node local clusters

Current local development uses single-node k3d.
k3d supports multi-node clusters for testing HA configurations.

Approach:

- Configure `servers: 3, agents: 2` in k3d config
- Test HA configurations and node failure scenarios
- Note: Multi-node k3d still uses container-based networking, not true VM isolation

### Additional cloud providers

The architecture targets Hetzner for production.
Future providers may include:

- *GCP*: GPU workloads via L4/A100 instances
- *AWS*: Ecosystem compatibility, managed services integration

Each provider requires:

- terranix modules for VM provisioning
- ClusterAPI infrastructure provider
- Provider-specific CSI drivers

## Quick reference

### Common commands table

| Task | Command |
|------|---------|
| Start local cluster | `just k3d-full` |
| Stop local cluster | `just k3d-down` |
| Build local manifests | `nix build .#k8s-manifests-local` |
| Deploy to local | `kluctl deploy --discriminator local -y` |
| Preview changes | `kluctl deploy --discriminator local --dry-run` |
| Check Cilium status | `kubectl exec -n kube-system ds/cilium -- cilium status` |
| View certificates | `kubectl get certificates -A` |
| Decrypt secret for editing | `sops k8s/secrets/local/secret.enc.yaml` |
| Exec into k3d server | `docker exec -it k3d-local-k3d-server-0 sh` |
| Build production manifests | `nix build .#k8s-manifests-full` |
| Deploy to production | `kluctl deploy --discriminator vanixiets-full -y` |
| Check cluster nodes | `kubectl get nodes -o wide` |
| View pod logs | `kubectl logs -f <pod> -n <namespace>` |

### File locations table

| File/Directory | Purpose |
|----------------|---------|
| `modules/nixos/k3s-server/` | Shared k3s NixOS module |
| `modules/terranix/hetzner.nix` | Hetzner VM definitions |
| `modules/machines/nixos/` | Machine-specific NixOS configs |
| `modules/k8s/` | easykubenix Kubernetes modules |
| `k8s/secrets/` | SOPS-encrypted SopsSecret files |
| `.sops.yaml` | SOPS key configuration |
| `terraform/` | Generated terraform files |
| `k3d/` | k3d cluster configuration files |
| `~/.kube/config` | kubectl configuration with k3d context |
| `result/` | Nix build output (manifests) |

### Troubleshooting decision tree

```text
Problem: Pods stuck in Pending
  |
  +-- CNI not running?
  |     +-- Check: kubectl get pods -n kube-system -l k8s-app=cilium
  |     +-- Fix: Deploy Cilium first
  |
  +-- Insufficient resources?
  |     +-- Check: kubectl describe pod <pod>
  |     +-- Fix: Increase VM resources or scale nodes
  |
  +-- PVC not bound?
        +-- Check: kubectl get pvc
        +-- Fix: Verify storage class exists

Problem: Service unreachable
  |
  +-- Endpoint exists?
  |     +-- Check: kubectl get endpoints <svc>
  |     +-- Fix: Verify pod labels match selector
  |
  +-- Cilium service routing?
  |     +-- Check: kubectl exec ds/cilium -- cilium service list
  |     +-- Fix: Verify kube-proxy replacement active
  |
  +-- Network policy blocking?
        +-- Check: hubble observe --verdict DROPPED
        +-- Fix: Adjust CiliumNetworkPolicy

Problem: Certificate not issued
  |
  +-- ClusterIssuer ready?
  |     +-- Check: kubectl describe clusterissuer <name>
  |     +-- Fix: Verify ACME account registration
  |
  +-- Challenge failing?
  |     +-- Check: kubectl get challenges -A
  |     +-- Fix: HTTP01: verify ingress; DNS01: verify API token
  |
  +-- cert-manager logs?
        +-- Check: kubectl logs -n cert-manager -l app=cert-manager
        +-- Fix: Address specific error message

Problem: Secrets not created
  |
  +-- SopsSecret exists?
  |     +-- Check: kubectl get sopssecret -A
  |     +-- Fix: Apply encrypted SopsSecret file
  |
  +-- Operator running?
  |     +-- Check: kubectl get pods -n sops-secrets-operator
  |     +-- Fix: Deploy sops-secrets-operator
  |
  +-- Age key accessible?
        +-- Check: kubectl logs deployment/sops-secrets-operator
        +-- Fix: Create sops-age-key-file secret with correct key
```

## Related documentation

### Architectural decisions

- [ADR-001: Local development architecture](../decisions/ADR-001-local-dev-architecture.md)
- [ADR-002: ArgoCD and nixidy responsibilities](../decisions/ADR-002-argocd-nixidy-responsibilities.md)

### Component documentation

- [NixOS k3s server module](../components/nixos-k3s-server.md)
- [Cilium CNI](../components/cilium-cni.md)
- [step-ca TLS](../components/step-ca-tls.md)
- [cert-manager](../components/cert-manager.md)
- [sops-secrets-operator](../components/sops-secrets-operator.md)
- [nix-csi](../components/nix-csi.md)

### Workflow documentation

- [Environment setup](../workflows/01-environment-setup.md)
- [Local development](../workflows/02-local-development.md)
- [ClusterAPI bootstrap](../workflows/03-clusterapi-bootstrap.md)
- [Hetzner deployment](../workflows/04-hetzner-deployment.md)
- [GitOps operations](../workflows/05-gitops-operations.md)

### External references

- k3s documentation: https://docs.k3s.io/
- k3d documentation: https://k3d.io/
- Cilium documentation: https://docs.cilium.io/
- cert-manager documentation: https://cert-manager.io/docs/
- ClusterAPI documentation: https://cluster-api.sigs.k8s.io/
- OrbStack documentation: https://docs.orbstack.dev/
- easykubenix repository: `~/projects/sciops-workspace/easykubenix`
- hetzkube reference: `~/projects/sciops-workspace/hetzkube`
