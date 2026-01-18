# ADR-003: Kubernetes module organization with flake-parts boundary

## Status

Proposed

## Context

The vanixiets infrastructure uses deferred module composition via flake-parts with import-tree auto-discovery:

```nix
flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules)
```

This pattern requires that all files under `modules/` be valid flake-parts modules with the signature:

```nix
{ inputs, config, lib, ... }: { flake = { ... }; perSystem = { ... }; }
```

Import-tree recursively discovers `.nix` files and passes them to `mkFlake`.
Files that don't conform to this signature cause evaluation failures.

The Kubernetes infrastructure uses easykubenix for manifest generation.
easykubenix uses the NixOS module system (`lib.evalModules`) with a different signature:

```nix
{ config, lib, pkgs, ... }: { options.component = { ... }; config = { ... }; }
```

These two module systems are fundamentally incompatible.
Placing kubenix modules under `modules/` causes import-tree to treat them as flake-parts modules, resulting in evaluation errors.

This ADR establishes the directory structure and bridging pattern for Kubernetes infrastructure while respecting the deferred module composition architecture.

## Decision

### Directory structure

Kubernetes-related code is organized into three locations at the repository root:

```
kubernetes/                        # kubenix modules (shared library)
├── cilium/
│   ├── default.nix               # Cilium CNI module
│   └── network-policies.nix      # Default network policies
├── cert-manager/
│   └── default.nix               # cert-manager module
├── step-ca/
│   └── default.nix               # Local ACME server module
├── sops-secrets-operator/
│   └── default.nix               # Secret management module
├── storage/
│   ├── local-path-provisioner.nix
│   └── nix-csi.nix
├── argocd/
│   └── default.nix               # ArgoCD GitOps module
└── external-dns/
    └── default.nix               # Production DNS automation

clusters/                          # Stage compositions + deployment configs
├── local/
│   ├── default.nix               # Local stage: module selection + overrides
│   └── .kluctl.yaml              # kluctl deployment target
└── production/
    ├── default.nix               # Production stage: module selection + overrides
    └── .kluctl.yaml

secrets/kubernetes/clusters/       # Per-cluster encrypted secrets
├── local/
│   └── secrets.yaml
└── production/
    └── secrets.yaml

modules/kubernetes.nix             # flake-parts wrapper (bridge)
```

### Boundary rules

| Directory | Module system | Purpose |
|-----------|--------------|---------|
| `modules/` | flake-parts | System configurations, home-manager, NixOS modules, flake output wiring |
| `kubernetes/` | kubenix (NixOS-style) | Kubernetes manifest generation modules |
| `clusters/` | kubenix (NixOS-style) | Stage-specific module composition and configuration |

### Bridging pattern

The `modules/kubernetes.nix` file is the only flake-parts module that interacts with Kubernetes infrastructure.
It imports easykubenix, evaluates cluster configurations, and exposes manifest outputs:

```nix
# modules/kubernetes.nix
{ inputs, ... }:
{
  perSystem = { pkgs, system, ... }:
    let
      evalCluster = stage: import inputs.easykubenix {
        inherit pkgs;
        modules = [
          ../kubernetes          # Shared kubenix modules
          ../clusters/${stage}   # Stage-specific composition
        ];
      };
      
      localCluster = evalCluster "local";
      productionCluster = evalCluster "production";
    in
    {
      packages = {
        k8s-manifests-local = localCluster.manifestYAMLFile;
        k8s-manifests-production = productionCluster.manifestYAMLFile;
      };
    };
}
```

### Module composition pattern

Kubenix modules in `kubernetes/` define options and default configurations:

```nix
# kubernetes/cilium/default.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.cilium;
in
{
  options.cilium = {
    enable = lib.mkEnableOption "Cilium CNI";
    version = lib.mkOption {
      type = lib.types.str;
      default = "1.16.5";
    };
    k8sServiceHost = lib.mkOption {
      type = lib.types.str;
      description = "Kubernetes API server host";
    };
  };

  config = lib.mkIf cfg.enable {
    helm.releases.cilium = { /* ... */ };
    kubernetes.apiMappings = { /* CRD registrations */ };
  };
}
```

Stage compositions in `clusters/` select modules and provide environment-specific overrides:

```nix
# clusters/local/default.nix
{ config, lib, ... }:
{
  imports = [
    ../../kubernetes/cilium
    ../../kubernetes/cert-manager
    ../../kubernetes/step-ca
    ../../kubernetes/sops-secrets-operator
    ../../kubernetes/argocd
  ];

  cilium = {
    enable = true;
    k8sServiceHost = "127.0.0.1";
    hubble.enabled = false;
  };

  cert-manager.enable = true;
  step-ca.enable = true;
  sops-secrets-operator.enable = true;
  argocd.enable = true;
}
```

### kluctl integration

Each cluster directory contains a `.kluctl.yaml` that references the manifest outputs:

```yaml
# clusters/local/.kluctl.yaml
discriminator: vanixiets-local

targets:
  - name: local
    context: k3s-dev
    
deployments:
  - path: .
    include:
      - manifests/
```

Deployment workflow:

1. Build manifests: `nix build .#k8s-manifests-local`
2. Deploy via kluctl: `kluctl deploy -t local`

## Consequences

### Positive

Clear separation of concerns keeps Kubernetes manifest generation isolated from flake-parts composition.
Each system operates in its native module format.

The deferred composition pattern is preserved.
The `modules/` directory remains purely flake-parts modules, and import-tree continues to work correctly.

Components in `kubernetes/` form a shared module library reusable across stages.
Configuration duplication is minimized.

Each cluster can independently select modules and override configurations without affecting others.

Developers familiar with kubenix/easykubenix can work in `kubernetes/` using familiar patterns.

### Negative

Developers must understand which module system applies in which directory.
Documentation and onboarding must address this distinction.

The `modules/kubernetes.nix` wrapper adds indirection.
Changes to kubenix evaluation patterns require updates to the bridge.

Stage compositions use relative imports (`../../kubernetes/cilium`).
Directory restructuring requires updating these paths.

## Alternatives considered

### Wrap each kubenix module as flake-parts

Each kubenix module could be wrapped in a flake-parts module that exports to `flake.modules.kubernetes.*`.
This was rejected because it adds boilerplate to every module, obscures the kubenix module structure, and evaluation would still require a separate entry point.

### Exclude kubernetes/ from import-tree

Import-tree could be configured to skip certain directories.
This was rejected because import-tree's filtering is path-based rather than content-based, would require explicit exclusion patterns that could drift, and the bridging pattern is more explicit and self-documenting.

### Use nixidy exclusively

nixidy provides flake-parts integration for ArgoCD-managed deployments.
However, Phase 3b (kluctl bootstrap) requires manifest generation before ArgoCD exists.
nixidy is optimal for Phase 4 (application deployment), while easykubenix handles the bootstrap phase that nixidy cannot.

## References

- [ADR-001: Local development architecture](./ADR-001-local-dev-architecture.md)
- [ADR-002: Bootstrap architecture independence](./ADR-002-bootstrap-architecture-independence.md)
- [easykubenix](https://github.com/Lillecarl/easykubenix)
- [flake-parts](https://flake.parts/)
- [import-tree](https://github.com/ryantm/import-tree)
