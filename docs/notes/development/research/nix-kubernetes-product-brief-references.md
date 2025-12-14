# Nix-Native Kubernetes Platform: Architecture Reference Document

This document captures architectural patterns, file paths, and integration points from the exploratory analysis of hetzcube, nixidy, terranix, and the existing infra repository.
It serves as the foundation for planning an experimental development cluster configuration.

## Source Repository Locations

| Repository | Path | Purpose |
|------------|------|---------|
| hetzcube | `~/projects/sciops-workspace/hetzkube/` | Hetzner CAPI + NixOS node images |
| nixidy | `~/projects/sciops-workspace/nixidy/` | GitOps manifest generation |
| terranix | `~/projects/sciops-workspace/terranix/` | Nix-to-Terraform bridge |
| infra | `~/projects/nix-workspace/infra/` | Target repo with deferred module composition patterns |

---

## Architectural Layering Model

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 5: Application Workloads (nixidy)                             │
│ - ArgoCD Applications, Helm releases, typed K8s resources           │
│ - Rendered manifests committed to Git                               │
└─────────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 4: Cluster Services (nixidy + easykubenix patterns)           │
│ - CNI (Cilium), DNS (CoreDNS), Ingress, cert-manager               │
│ - MetalLB, external-dns, monitoring stack                          │
└─────────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 3: Cluster Lifecycle (ClusterAPI + kubeadm)                   │
│ - KubeadmControlPlane, MachineDeployments                          │
│ - Custom IPAM/CCM (cheapam pattern), multi-arch node pools         │
└─────────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 2: Node OS (NixOS + nixos-anywhere)                           │
│ - Immutable NixOS images, kubelet, containerd                      │
│ - Declarative disk partitioning (disko)                            │
└─────────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 1: Infrastructure Bootstrap (terranix)                        │
│ - Hetzner VMs, networks, floating IPs, DNS                         │
│ - Thin Nix wrapper → Terraform execution                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Hetzcube Key Patterns and File Paths

### Directory Structure

```
~/projects/sciops-workspace/hetzkube/
├── flake.nix                  # Flake entry point with easykubenix, terranix inputs
├── default.nix                # Root evaluation entry
├── deploy.py                  # Rolling node update script (drain→rebuild→reboot)
│
├── nixos/                     # NixOS node image configuration
│   ├── default.nix            # Primary module (imports all sub-modules)
│   ├── kubernetes.nix         # Kubelet, containerd, CNI setup
│   ├── networking.nix         # Network config, firewall
│   ├── disko.nix              # Btrfs disk partitioning
│   ├── cloud-init.nix         # Cloud-init integration
│   └── installscript.nix      # nixos-anywhere installation scripts
│
├── kubenix/                   # Kubernetes resource definitions
│   ├── default.nix            # Main kubenix loader with stage option
│   ├── configuration/
│   │   └── default.nix        # Cluster-wide config (CIDRs, domains, etc.)
│   ├── capi/
│   │   └── default.nix        # CAPI stage enabler
│   ├── full/
│   │   └── default.nix        # Full deployment stage enabler
│   └── modules/               # Individual K8s components
│       ├── capi.nix           # ClusterAPI control-plane/worker definitions
│       ├── cilium.nix         # CNI with kube-proxy replacement
│       ├── metallb.nix        # L2 load balancer IP announcement
│       ├── cheapam.nix        # Custom IPAM/CCM deployment
│       ├── external-dns.nix   # Cloudflare DNS management
│       ├── cert-manager.nix   # Let's Encrypt certificates
│       ├── hcsi.nix           # Hetzner Cloud Storage CSI
│       ├── cnpg.nix           # CloudNative PostgreSQL
│       ├── coredns.nix        # Cluster DNS
│       └── keycloak.nix       # OIDC provider
│
├── cheapam/                   # Custom Python IPAM/CCM controller
│   └── cheapam/
│       ├── main.py            # Async reconciliation loop
│       ├── config.py          # Constants (pool names, CIDRs)
│       ├── ipam.py            # Node initialization, pod CIDR allocation
│       ├── external_resources.py  # MetalLB/external-dns updates
│       └── hetzner.py         # Hetzner Cloud API client
│
├── tf/                        # Terranix for Keycloak OIDC provisioning
│   ├── default.nix
│   └── terranix.nix
│
└── secrets/                   # SOPS-encrypted secrets
    └── all.yaml
```

### Critical Code Patterns

Kubernetes node configuration (`nixos/kubernetes.nix:18-35`):
```nix
virtualisation.containerd = {
  enable = true;
  settings = {
    plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
    plugins."io.containerd.grpc.v1.cri".cni.bin_dir = "/opt/cni/bin";
  };
};
```

Cluster configuration (`kubenix/configuration/default.nix`):
```nix
config = {
  clusterName = "hetzkube";
  clusterHost = "kubernetes.lillecarl.com";
  clusterPodCIDR4 = "10.133.0.0/16";
  clusterServiceCIDR4 = "10.134.0.0/16";
  clusterDNS = ["10.134.0.10"];
};
```

CAPI control plane definition (`kubenix/modules/capi.nix:77-141`):
```nix
KubeadmControlPlane.hetzkube = {
  spec = {
    replicas = 3;
    machineTemplate.infrastructureRef = {
      apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
      kind = "HCloudMachineTemplate";
      name = "hetzkube-controlplane";
    };
    kubeadmConfigSpec = {
      clusterConfiguration = {
        controllerManager.extraArgs."bind-address" = "0.0.0.0";
        scheduler.extraArgs."bind-address" = "0.0.0.0";
        apiServer.extraArgs = {
          "oidc-issuer-url" = "https://keycloak.lillecarl.com/realms/master";
          "oidc-client-id" = "kubernetes";
        };
      };
      preKubeadmCommands = [
        "git clone https://github.com/lillecarl/hetzkube.git /etc/hetzkube"
        "nix run --file /etc/hetzkube pkgs.hetzInfo"
        "nixos-rebuild switch --file /etc/hetzkube/"
      ];
    };
  };
};
```

Deployment stages (`kubenix/default.nix`):
```nix
stage = lib.mkOption {
  type = lib.types.enum ["capi" "full"];
  default = "full";
};
```

Cheapam IPAM reconciliation (`cheapam/cheapam/ipam.py` pattern):
1. Watch for nodes with `node.cloudprovider.kubernetes.io/uninitialized` taint
2. Fetch node metadata from Hetzner API
3. Set `providerID = hcloud://{server_id}`
4. Allocate `/24` subnet from cluster pod CIDR
5. Update node status with ExternalIP addresses
6. Remove uninitialized taint

---

## Nixidy Key Patterns and File Paths

### Directory Structure

```
~/projects/sciops-workspace/nixidy/
├── flake.nix                      # Flake entry with nix-kube-generators input
├── make-env.nix                   # Core API: mkEnv and mkEnvs functions
│
├── lib/
│   ├── default.nix                # Main lib export
│   ├── helm.nix                   # Helm chart downloading/templating
│   ├── kustomize.nix              # Kustomize rendering
│   └── kube.nix                   # K8s utilities (YAML parsing)
│
├── modules/
│   ├── default.nix                # Module system evaluation
│   ├── nixidy.nix                 # Global nixidy.* options
│   ├── applications.nix           # applications.* option definition
│   ├── build.nix                  # Build logic (YAML generation)
│   ├── templates.nix              # Reusable application patterns
│   ├── applications/
│   │   ├── default.nix            # Core application options
│   │   ├── helm.nix               # Helm release rendering
│   │   ├── kustomize.nix          # Kustomize application rendering
│   │   └── yamls.nix              # Raw YAML parsing
│   └── generated/
│       ├── k8s/v1.30-1.34.nix     # Auto-generated K8s resource types
│       └── argocd.nix             # ArgoCD CRD definitions
│
├── nixidy/
│   └── nixidy                     # CLI bash script (build/switch/info/bootstrap)
│
└── pkgs/generators/
    └── generator.nix              # CRD-to-Nix code generator
```

### Critical Code Patterns

Environment creation (`make-env.nix`):
```nix
mkEnv = { pkgs, modules ? [], extraSpecialArgs ? {} }:
  let
    evaluated = lib.evalModules {
      modules = [ ./modules ] ++ modules;
      specialArgs = { inherit pkgs; } // extraSpecialArgs;
    };
  in {
    inherit (evaluated) config;
    environmentPackage = evaluated.config.build.environmentPackage;
    activationPackage = evaluated.config.build.activationPackage;
    bootstrapPackage = evaluated.config.build.bootstrapPackage;
  };

mkEnvs = { pkgs, envs }:
  lib.mapAttrs (name: env: mkEnv {
    inherit pkgs;
    modules = env.modules or [];
  }) envs;
```

Application definition (`modules/applications/default.nix:97-200`):
```nix
applications.<name> = {
  namespace = lib.mkOption { type = lib.types.str; };
  createNamespace = lib.mkOption { type = lib.types.bool; default = true; };

  resources = {
    deployments.<name>.spec = { ... };
    services.<name>.spec = { ... };
    configMaps.<name>.data = { ... };
  };

  helm.releases.<name> = {
    chart = lib.helm.downloadHelmChart { ... };
    values = { ... };
  };

  syncPolicy = {
    autoSync.enable = true;
    autoSync.prune = true;
    autoSync.selfHeal = true;
  };
};
```

GitOps target configuration (`modules/nixidy.nix:30-80`):
```nix
nixidy.target = {
  repository = "https://github.com/org/cluster-config";
  branch = "main";
  rootPath = "./manifests";
};

nixidy.appOfApps = {
  name = "apps";
  namespace = "argocd";
  project = "default";
};
```

Helm chart integration (`lib/helm.nix`):
```nix
downloadHelmChart = { repo, chart, version, chartHash }:
  # Fetches chart with integrity verification

buildHelmChart = { chart, values ? {}, includeCRDs ? true, ... }:
  # Runs helm template with values
```

CLI commands (`nixidy/nixidy`):
- `nixidy build .#env` - Build manifests to ./result
- `nixidy switch .#env` - Build + sync to filesystem
- `nixidy bootstrap .#env` - Print app-of-apps manifest
- `nixidy info .#env` - Show target repo/branch

Build outputs (`modules/build.nix:82-244`):
- `environmentPackage` - All rendered manifests by app
- `bootstrapPackage` - App-of-Apps manifest only
- `activationPackage` - environmentPackage + activate script
- `declarativePackage` - Grouped manifests + kubectl apply script

---

## Terranix Key Patterns and File Paths

### Directory Structure

```
~/projects/sciops-workspace/terranix/
├── flake.nix
├── flake-module.nix               # Flake-parts integration
│
├── core/
│   ├── default.nix                # Main configuration evaluator
│   ├── terraform-options.nix      # Terraform schema mapping
│   ├── terraform-invocs.nix       # Script generation (apply/destroy)
│   └── helpers.nix                # lib.tf.ref, lib.tf.template
│
├── modules/
│   ├── default.nix                # Module registry
│   ├── terraform/
│   │   └── backends.nix           # S3/etcd/local backend config
│   └── provider/
│       ├── github.nix
│       └── cloudflare.nix
│
└── bin/
    └── terranix                   # CLI script
```

### Critical Code Patterns

Flake-parts integration (`flake-module.nix`):
```nix
perSystem.terranix.terranixConfigurations = {
  default = {
    modules = [ ./config.nix ];
    terraformWrapper.package = pkgs.opentofu;

    # Read-only outputs:
    result = {
      terraformConfiguration  # Generated config.tf.json
      terraformWrapper        # Configured terraform binary
      scripts = { init, apply, plan, destroy }
      devShell               # Shell with tools
    };
  };
};
```

Resource definition with references (`core/terraform-options.nix`):
```nix
# Resources become callable functors for references:
resource.aws_instance.server "public_ip"
# Generates: "${resource.aws_instance.server.public_ip}"
```

Thin wrapper CLI (`bin/terranix`):
```bash
terranix ./config.nix > config.tf.json
terraform init && terraform apply
```

---

## Infra Repository Deferred Module Composition Patterns

### Directory Structure

```
~/projects/nix-workspace/infra/
├── flake.nix                      # import-tree ./modules entry
├── lib/
│   └── caches.nix                 # DRY shared configuration
│
├── modules/
│   ├── clan/
│   │   ├── core.nix               # Clan + terranix imports
│   │   ├── machines.nix           # Machine definitions
│   │   └── inventory/
│   │       ├── machines.nix       # Machine inventory with tags
│   │       └── services/
│   │           ├── zerotier.nix   # Role-based service deployment
│   │           └── users/         # Per-user inventory modules
│   │
│   ├── machines/
│   │   ├── nixos/
│   │   │   ├── cinnabar/
│   │   │   │   ├── default.nix    # Machine module
│   │   │   │   └── disko.nix      # Disk config (auto-merges)
│   │   │   └── electrum/
│   │   └── darwin/
│   │
│   ├── system/                    # Shared NixOS modules
│   │   ├── nix-settings.nix
│   │   └── caches.nix
│   │
│   ├── home/                      # Home-manager aggregates
│   │   ├── configurations.nix     # mkHomeConfig function
│   │   ├── core/
│   │   ├── development/
│   │   ├── ai/
│   │   └── shell/
│   │
│   ├── nixpkgs/
│   │   ├── compose.nix            # Overlay composition
│   │   └── overlays/
│   │
│   └── terranix/
│       └── base.nix               # Hetzner provider + secrets
│
├── secrets/
│   ├── cluster/                   # Tier 1: Clan vars
│   └── users/                     # Tier 2: sops-nix
│
└── docs/
    └── architecture/
        ├── deferred-module-composition.md
        ├── secrets-and-vars-architecture.md
        └── evaluation-flow-diagram.md
```

### Critical Code Patterns

Flake entry with import-tree (`flake.nix`):
```nix
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
```

Deferred module composition auto-merge pattern (multiple files → same namespace):
```nix
# modules/system/nix-settings.nix
{ ... }: {
  flake.modules.nixos.base = { ... }: {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  };
}

# modules/system/caches.nix (SAME namespace, auto-merged)
{ ... }: {
  flake.modules.nixos.base = { ... }: {
    nix.settings.substituters = [ /* ... */ ];
  };
}
```

Clan machine definitions (`modules/clan/machines.nix`):
```nix
{
  clan.machines = {
    cinnabar = {
      imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
    };
    electrum = {
      imports = [ config.flake.modules.nixos."machines/nixos/electrum" ];
    };
  };
}
```

Machine inventory with tags (`modules/clan/inventory/machines.nix`):
```nix
{
  clan.inventory.machines = {
    cinnabar = {
      tags = [ "nixos" "cloud" "hetzner" "controller" ];
      machineClass = "nixos";
      description = "Primary VPS, zerotier controller";
    };
    electrum = {
      tags = [ "nixos" "cloud" "hetzner" "peer" ];
      machineClass = "nixos";
    };
  };
}
```

Role-based service deployment (`modules/clan/inventory/services/zerotier.nix`):
```nix
{
  clan.inventory.instances.zerotier = {
    module = { name = "zerotier"; input = "clan-core"; };
    roles.controller.machines."cinnabar" = { };
    roles.peer.tags."peer" = { };  # Auto-deploys to tagged machines
  };
}
```

Terranix with clan secrets (`modules/terranix/base.nix`):
```nix
{
  flake.modules.terranix.base = { config, pkgs, lib, ... }: {
    terraform.required_providers.hcloud.source = "hetznercloud/hcloud";

    data.external.hetzner-api-token = {
      program = [
        (lib.getExe (pkgs.writeShellApplication {
          name = "get-hetzner-secret";
          text = ''
            jq -n --arg secret "$(clan secrets get hetzner-api-token)" '{"secret":$secret}'
          '';
        }))
      ];
    };

    provider.hcloud.token = config.data.external.hetzner-api-token "result.secret";
  };
}
```

Overlay composition (`modules/nixpkgs/compose.nix`):
```nix
flake.overlays.default = final: prev:
  let
    internalOverlays = lib.composeManyExtensions config.flake.nixpkgsOverlays;
    customPackages = withSystem prev.stdenv.hostPlatform.system (
      { config, ... }: config.packages or { }
    );
  in
  (internalOverlays final prev) // customPackages;
```

---

## Existing Infra Machines (Deployment Targets)

| Hostname | Type | Tags | Description |
|----------|------|------|-------------|
| cinnabar | NixOS VPS | nixos, cloud, hetzner, controller | Primary Hetzner VM |
| electrum | NixOS VPS | nixos, cloud, hetzner, peer | Secondary test VM |
| blackphos | nix-darwin | darwin, workstation | macOS workstation |
| stibnite | nix-darwin | darwin, workstation | macOS workstation |

Current infrastructure supports single-VM deployment via terranix.
The experimental cluster will extend this to multi-node Kubernetes.

---

## Integration Points for Unified Architecture

### Terranix → NixOS Nodes

Terranix provisions VMs, outputs IP addresses and server IDs.
NixOS configuration consumes these via nixos-anywhere installation.

Connection: `terranix output → nixos-anywhere --target-host`

### NixOS Nodes → ClusterAPI

NixOS images include kubelet, containerd, CNI binaries.
ClusterAPI's KubeadmConfigSpec runs preKubeadmCommands to complete setup.

Connection: `NixOS image snapshot ID → HCloudMachineTemplate.spec.image`

### ClusterAPI → Nixidy

CAPI provisions cluster control plane and workers.
Nixidy generates manifests for cluster services and applications.

Connection: `clusterctl get kubeconfig → KUBECONFIG for nixidy apply`

### Nixidy → ArgoCD

Nixidy generates ArgoCD Application resources.
ArgoCD syncs from Git repository containing rendered manifests.

Connection: `nixidy.target.repository → ArgoCD Application.spec.source.repoURL`

### Clan → All Layers

Clan provides secrets management across all layers.
Machine inventory enables role-based deployment targeting.

Connection: `clan secrets get <name> → provider tokens, TLS certs, etc.`

---

## Proposed Module Structure for Infra Repository

```
~/projects/nix-workspace/infra/modules/
├── k8s/                           # New: Kubernetes cluster configuration
│   ├── core.nix                   # Flake module imports (nixidy, etc.)
│   │
│   ├── nixos/                     # Layer 2: Node OS configuration
│   │   ├── base/
│   │   │   ├── kubernetes.nix     # kubelet, containerd, CNI
│   │   │   ├── networking.nix     # Node networking
│   │   │   └── disko.nix          # Disk partitioning
│   │   └── images/
│   │       ├── x86_64.nix
│   │       └── aarch64.nix
│   │
│   ├── capi/                      # Layer 3: Cluster lifecycle
│   │   ├── cluster.nix            # Cluster resource definition
│   │   ├── control-plane.nix      # KubeadmControlPlane
│   │   ├── workers/
│   │   │   └── general.nix        # MachineDeployment
│   │   └── ipam/                  # IPAM controller (cheapam pattern)
│   │
│   ├── cluster/                   # Layer 4: Cluster services
│   │   ├── networking/
│   │   │   ├── cilium.nix
│   │   │   └── coredns.nix
│   │   ├── ingress/
│   │   │   └── gateway-api.nix
│   │   ├── security/
│   │   │   └── cert-manager.nix
│   │   └── storage/
│   │       └── hcloud-csi.nix
│   │
│   └── applications/              # Layer 5: Workloads (nixidy)
│       └── argocd/
│           └── default.nix
│
├── clan/
│   └── inventory/
│       ├── machines.nix           # Add k8s node tags
│       └── services/
│           └── k8s/               # New: K8s service instances
│               ├── control-plane.nix
│               └── workers.nix
│
└── terranix/
    └── k8s/                       # New: K8s infrastructure
        ├── vms.nix                # Control plane + worker VMs
        └── network.nix            # Private network, firewall rules
```

---

## Deployment Flow for Experimental Cluster

```
Phase 1: Infrastructure (terranix)
├── Provision 1 control-plane VM (cx22 or similar)
├── Provision 1-2 worker VMs
├── Create private network
└── Configure firewall rules

Phase 2: Node OS (nixos-anywhere)
├── Build NixOS image with k8s components
├── Install to control-plane VM
└── Install to worker VMs

Phase 3: Cluster Bootstrap (ClusterAPI)
├── Create local kind cluster
├── Initialize CAPI with Hetzner provider
├── Apply KubeadmControlPlane resources
├── Apply MachineDeployment for workers
└── Move CAPI to production cluster

Phase 4: Cluster Services (nixidy)
├── Deploy Cilium CNI
├── Deploy CoreDNS
├── Deploy cert-manager
├── Deploy ArgoCD
└── Deploy Hetzner CSI

Phase 5: GitOps Activation (nixidy + ArgoCD)
├── nixidy build .#dev-cluster
├── Commit manifests to Git
├── ArgoCD syncs from Git
└── Cluster fully operational
```

---

## Key Technical Decisions

### Use nixidy over easykubenix

Nixidy provides:
- Stronger typing via auto-generated CRD modules
- Built-in ArgoCD integration
- Active maintenance and documentation
- Multi-environment support

### Retain hetzcube's cheapam pattern

The custom IPAM/CCM eliminates Hetzner load balancer costs and handles:
- Node IP allocation
- Pod CIDR assignment
- MetalLB pool updates
- External-DNS synchronization

### Terranix as thin bootstrap only

Terranix manages pre-Kubernetes resources only:
- VM provisioning
- Network setup
- DNS base configuration

Post-bootstrap, Kubernetes-native tools manage cluster state.

### Clan for unified secrets

Two-tier secrets architecture:
- Tier 1 (Clan vars): Cluster-level secrets (API tokens, TLS keys)
- Tier 2 (sops-nix): User credentials for cluster access

### Deferred module composition throughout

All new modules follow the import-tree auto-discovery pattern.
No manual module registration required.

---

## Risk Factors and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Complexity of multi-tool integration | High | Start with minimal viable cluster, iterate |
| CAPI learning curve | Medium | Document bootstrap process thoroughly |
| Nixidy version compatibility | Medium | Pin nixidy input, test upgrades |
| Hetzner-specific assumptions | Low | Abstract provider-specific code |
| Secrets management complexity | Medium | Use proven patterns from infra repo |

---

## Success Criteria for Experimental Cluster

1. Single control-plane node running via CAPI
2. At least one worker node joined to cluster
3. Cilium CNI operational with pod networking
4. CoreDNS resolving cluster DNS
5. ArgoCD deployed and syncing from Git
6. nixidy workflow functional (build → commit → sync)
7. Secrets properly managed via Clan
8. Rolling node updates functional

---

## References

### Documentation

- Hetzcube README: `~/projects/sciops-workspace/hetzkube/README.md`
- Nixidy user guide: `~/projects/sciops-workspace/nixidy/docs/user_guide/`
- Terranix documentation: `~/projects/sciops-workspace/terranix/doc/`
- Infra architecture docs: `~/projects/nix-workspace/infra/docs/architecture/`

### Key External Resources

- ClusterAPI: https://cluster-api.sigs.k8s.io/
- Hetzner CAPI provider: https://github.com/syself/cluster-api-provider-hetzner
- ArgoCD: https://argo-cd.readthedocs.io/
- Cilium: https://docs.cilium.io/
- nixos-anywhere: https://github.com/nix-community/nixos-anywhere
