---
title: easykubenix module patterns
---

# easykubenix module patterns

easykubenix generates Kubernetes manifests from Nix modules using the kubenix library underneath.
These manifests deploy via kluctl with discriminator-based tracking that enables incremental updates and drift detection.
The reference implementation lives at `~/projects/sciops-workspace/hetzkube`.

## Module structure

Every easykubenix module follows a standard skeleton pattern with options and configuration sections.
The module name serves as the option namespace and can enable cross-module dependencies.

```nix
{
  config,
  lib,
  ...
}:
let
  moduleName = "mymodule";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.str;
      default = "1.0.0";
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    # Configuration when module is enabled
  };
}
```

The `enable` option pattern gates all configuration behind `lib.mkIf cfg.enable`, ensuring modules only produce manifests when explicitly enabled.
The `helmValues` option allows consuming modules to override Helm values without modifying the base configuration.

## Integration patterns

easykubenix supports three primary patterns for integrating upstream Kubernetes components: Helm releases, YAML imports, and native Nix resource definitions.

### Helm releases pattern

Helm charts deploy via the `helm.releases` option, supporting both fetched charts and local paths.
This pattern suits components distributed primarily as Helm charts.

```nix
{
  config,
  lib,
  ...
}:
let
  moduleName = "metrics-server";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.str;
      default = "0.8.0";
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };

  config =
    let
      src = builtins.fetchTree {
        type = "github";
        owner = "kubernetes-sigs";
        repo = "metrics-server";
        ref = "v${cfg.version}";
      };
    in
    lib.mkIf cfg.enable {
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${src}/charts/metrics-server";
        values = lib.recursiveUpdate {
          args = [ "--kubelet-insecure-tls" ];
        } cfg.helmValues;
      };
    };
}
```

The `chart` attribute accepts either a path to a local chart directory (as shown with `builtins.fetchTree`) or a derivation from `fetchHelm`.
Using `lib.recursiveUpdate` with a base values attrset and `cfg.helmValues` allows callers to override specific values while preserving defaults.

For larger components like Cilium, the chart often lives inside a subdirectory of the fetched source.

```nix
let
  src = builtins.fetchTree {
    type = "github";
    owner = "cilium";
    repo = "cilium";
    ref = "v${cfg.version}";
  };
in
{
  helm.releases.cilium = {
    namespace = "kube-system";
    chart = "${src}/install/kubernetes/cilium";
    values = { /* ... */ };
  };
}
```

### importyaml pattern

The `importyaml` option imports upstream YAML manifests directly from URLs or local paths.
This pattern suits components that distribute pre-rendered YAML rather than Helm charts.

```nix
{
  config,
  lib,
  ...
}:
let
  moduleName = "cert-manager";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    url = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml";
    };
  };

  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = cfg.url;
    };
  };
}
```

During evaluation, easykubenix converts the YAML to JSON and merges it with other resources.
Version pinning happens through the URL itself, making upgrades explicit.

For components with CRDs distributed separately from the main manifests, import multiple YAML sources.

```nix
importyaml.${moduleName} = {
  src = "https://raw.githubusercontent.com/kubernetes-sigs/external-dns/v${cfg.version}/config/crd/standard/dnsendpoints.externaldns.k8s.io.yaml";
};
```

### Native Nix resources

Beyond Helm and YAML imports, modules can define Kubernetes resources directly as Nix attribute sets.
This pattern enables fine-grained control and cross-module resource composition.

```nix
kubernetes.resources.${cfg.namespace} = {
  ServiceAccount.external-dns = { };
  Secret.api-token.stringData.token = "{{ token }}";
  Deployment.external-dns = {
    spec = {
      strategy.type = "Recreate";
      selector.matchLabels.app = "external-dns";
      template = {
        metadata.labels.app = "external-dns";
        spec = {
          serviceAccountName = "external-dns";
          containers = lib.mkNamedList {
            external-dns = {
              image = "registry.k8s.io/external-dns/external-dns:v${cfg.version}";
              args = [
                "--source=service"
                "--provider=cloudflare"
              ];
            };
          };
        };
      };
    };
  };
};
```

The resource path follows the pattern `kubernetes.resources.<namespace>.<Kind>.<name>`.
For cluster-scoped resources, use `none` as the namespace: `kubernetes.resources.none.ClusterRole.my-role`.

## CRD registration

Modules introducing custom resources must register API version mappings and namespace scope.
Without these mappings, kubenix cannot determine the correct API version or whether resources are namespaced.

```nix
kubernetes.apiMappings = {
  Certificate = "cert-manager.io/v1";
  CertificateRequest = "cert-manager.io/v1";
  ClusterIssuer = "cert-manager.io/v1";
  Issuer = "cert-manager.io/v1";
};

kubernetes.namespacedMappings = {
  Certificate = true;
  CertificateRequest = true;
  ClusterIssuer = false;  # cluster-scoped
  Issuer = true;
};
```

Place API mappings outside the `lib.mkIf cfg.enable` block when other modules may reference these CRDs regardless of whether this module is enabled.
This pattern appears in cert-manager where other modules create Certificate resources.

```nix
config = lib.mkMerge [
  # Always register CRD mappings
  {
    kubernetes.apiMappings = {
      Certificate = "cert-manager.io/v1";
      ClusterIssuer = "cert-manager.io/v1";
    };
    kubernetes.namespacedMappings = {
      Certificate = true;
      ClusterIssuer = false;
    };
  }
  # Only create resources when enabled
  (lib.mkIf cfg.enable {
    importyaml.${moduleName}.src = cfg.url;
  })
];
```

For Cilium CRDs bundled in the source repository, import them dynamically.

```nix
importyaml = lib.pipe (builtins.readDir "${src}/pkg/k8s/apis/cilium.io/client/crds/v2") [
  (lib.mapAttrs' (
    filename: type: {
      name = filename;
      value.src = "${src}/pkg/k8s/apis/cilium.io/client/crds/v2/${filename}";
    }
  ))
];
```

## Stage-based deployment

hetzkube uses stages to separate ClusterAPI bootstrap from full infrastructure deployment.
The `stage` option controls which modules activate at each deployment phase.

The root kubenix configuration accepts a stage argument and propagates it to all modules.

```nix
# kubenix/default.nix
import easykubenix {
  inherit pkgs;
  modules = [
    ./modules
    ./capi
    ./full
    {
      config = {
        kluctl.discriminator = stage;
        inherit stage;
      };
    }
  ];
}
```

Stage-specific configuration files gate module enablement.

```nix
# kubenix/capi/default.nix
{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "capi") {
    capi.enable = true;
  };
}

# kubenix/full/default.nix
{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    bitwarden.enable = true;
    capi.enable = true;
    cert-manager.enable = true;
    cilium.enable = true;
    coredns.enable = true;
    external-dns.enable = true;
    metrics-server.enable = true;
    # ... additional modules
  };
}
```

Deploy specific stages via the `--argstr stage` argument.

```bash
# Bootstrap ClusterAPI only
nix-build -A kubenix --argstr stage capi

# Full infrastructure stack
nix-build -A kubenix --argstr stage full
```

The kluctl discriminator tracks resources per stage, enabling stage-specific pruning without affecting resources from other stages.

## ArgoCD module example

This example demonstrates how ArgoCD would be structured as an easykubenix module following the patterns above.
ArgoCD serves as the Phase 3b infrastructure component managing GitOps application deployments.

```nix
{
  config,
  lib,
  ...
}:
let
  moduleName = "argocd";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "argocd";
    };
    version = lib.mkOption {
      type = lib.types.str;
      default = "7.8.0";
    };
    hostname = lib.mkOption {
      type = lib.types.str;
      description = "ArgoCD server hostname for ingress";
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };

  config = lib.mkMerge [
    # Register ArgoCD CRDs for other modules
    {
      kubernetes.apiMappings = {
        Application = "argoproj.io/v1alpha1";
        ApplicationSet = "argoproj.io/v1alpha1";
        AppProject = "argoproj.io/v1alpha1";
      };
      kubernetes.namespacedMappings = {
        Application = true;
        ApplicationSet = true;
        AppProject = true;
      };
    }

    (lib.mkIf cfg.enable (
      let
        src = builtins.fetchTree {
          type = "github";
          owner = "argoproj";
          repo = "argo-helm";
          ref = "argo-cd-${cfg.version}";
        };
      in
      {
        # Create namespace
        kubernetes.resources.none.Namespace.${cfg.namespace} = { };

        # Deploy ArgoCD via Helm
        helm.releases.${moduleName} = {
          namespace = cfg.namespace;
          chart = "${src}/charts/argo-cd";
          values = lib.recursiveUpdate {
            # Server configuration
            server = {
              extraArgs = [ "--insecure" ];  # TLS termination at ingress
              ingress = {
                enabled = true;
                ingressClassName = "cilium";
                hostname = cfg.hostname;
                tls = true;
                annotations = {
                  "cert-manager.io/cluster-issuer" = "step-ca";
                };
              };
            };

            # Redis HA for production
            redis-ha.enabled = true;

            # Controller configuration
            controller = {
              replicas = 1;
              metrics.enabled = true;
            };

            # Repo server configuration
            repoServer = {
              replicas = 1;
              metrics.enabled = true;
            };

            # Application controller
            applicationSet.enabled = true;

            # Notifications controller
            notifications.enabled = true;
          } cfg.helmValues;
        };

        # Default AppProject allowing all sources
        kubernetes.resources.${cfg.namespace}.AppProject.default.spec = {
          description = "Default project";
          sourceRepos = [ "*" ];
          destinations = [
            {
              namespace = "*";
              server = "https://kubernetes.default.svc";
            }
          ];
          clusterResourceWhitelist = [
            {
              group = "*";
              kind = "*";
            }
          ];
        };

        # Root Application for app-of-apps pattern (nixidy integration point)
        kubernetes.resources.${cfg.namespace}.Application.root = {
          metadata.finalizers = [ "resources-finalizer.argocd.argoproj.io" ];
          spec = {
            project = "default";
            source = {
              repoURL = config.gitops.repoURL or "https://github.com/org/repo";
              targetRevision = config.gitops.targetRevision or "HEAD";
              path = config.gitops.manifestsPath or "manifests";
            };
            destination = {
              server = "https://kubernetes.default.svc";
              namespace = cfg.namespace;
            };
            syncPolicy = {
              automated = {
                prune = true;
                selfHeal = true;
              };
              syncOptions = [
                "CreateNamespace=true"
                "PrunePropagationPolicy=foreground"
              ];
            };
          };
        };
      }
    ))
  ];
}
```

This module demonstrates several patterns in combination.
CRD mappings register outside the enable guard for cross-module reference support.
The Helm release uses `lib.recursiveUpdate` for value overrides.
Native resources create the namespace, default project, and root application.
The root Application establishes the app-of-apps pattern where nixidy-generated manifests deploy via GitOps.

## Validation

easykubenix uses an ephemeral kube-apiserver during evaluation to validate generated manifests.
This approach eliminates the need for external schema files while catching type errors at build time.

The validation process spins up a temporary API server, applies CRD definitions, and validates all resources against the live API.
Errors surface during `nix build` rather than at deploy time.

```bash
# Validation happens automatically during build
nix build .#kubenix --argstr stage full

# Errors appear as Nix evaluation failures with API validation messages
error: ... Invalid value: "wrong-type": spec.replicas must be an integer
```

This validation catches common errors including incorrect field types, missing required fields, invalid enum values, and malformed resource structures.
The ephemeral server approach means validation stays current with the Kubernetes version used in the cluster.

## kluctl deployment

Generated manifests deploy via kluctl with discriminator-based resource tracking.

```bash
# Render manifests
result=$(nix build .#kubenix --argstr stage full --print-out-paths)

# Deploy with kluctl
kluctl deploy -t $result

# Diff before deploying
kluctl diff -t $result

# Prune orphaned resources
kluctl prune -t $result
```

The discriminator (set from the stage name) identifies resources belonging to each deployment.
Pruning removes only resources with matching discriminators, preserving resources from other stages or external deployments.

## Related documentation

- easykubenix source: `~/projects/sciops-workspace/easykubenix`
- hetzkube reference implementation: `~/projects/sciops-workspace/hetzkube`
- kluctl documentation: https://kluctl.io/docs/
- kubenix library: https://github.com/hall/kubenix
