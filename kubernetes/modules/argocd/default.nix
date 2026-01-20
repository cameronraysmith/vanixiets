# ArgoCD module for easykubenix
#
# Deploys ArgoCD for GitOps continuous delivery.
# Phase 3b infrastructure component - enables Phase 4 nixidy Application management.
#
# Local development: insecure mode enabled for kubectl port-forward access.
# Production: should use proper TLS via cert-manager/step-ca ACME.
#
# Receives argocd-src and argocd-helm-src from flake inputs via specialArgs.
# - argocd-src: CRD definitions from argoproj/argo-cd
# - argocd-helm-src: Helm chart from argoproj/argo-helm
{
  config,
  lib,
  pkgs,
  argocd-src,
  argocd-helm-src,
  ...
}:
let
  moduleName = "argocd";
  cfg = config.${moduleName};

  # CRD source paths from argocd-src flake input
  crdDir = "${argocd-src}/manifests/crds";

  # Create derivation for each CRD file (required for importyaml)
  # importyaml expects either a derivation or URL, not a store path string
  mkCrdDrv =
    filename:
    pkgs.runCommand "argocd-crd-${filename}" { } ''
      cp ${crdDir}/${filename} $out
    '';

  # Pre-process Helm chart to remove external dependency
  # The argo-cd chart has a conditional dependency on redis-ha that helm checks for
  # even when disabled. Since we're disabling redis-ha for local dev, we patch
  # Chart.yaml to remove the dependency entirely (avoids network fetch in sandbox).
  chartWithDeps =
    pkgs.runCommand "argocd-helm-chart"
      {
        nativeBuildInputs = [ pkgs.yq-go ];
      }
      ''
        cp -r ${argocd-helm-src}/charts/argo-cd $out
        chmod -R u+w $out
        # Remove the redis-ha dependency from Chart.yaml
        # This is safe because we're disabling redis-ha in our values anyway
        yq -i 'del(.dependencies)' $out/Chart.yaml
        # Also remove Chart.lock to avoid dependency check
        rm -f $out/Chart.lock
      '';
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;

    version = lib.mkOption {
      type = lib.types.str;
      default = "3.2.5";
      description = "ArgoCD version (must match argocd-src flake input)";
    };

    chartVersion = lib.mkOption {
      type = lib.types.str;
      default = "9.3.4";
      description = "ArgoCD Helm chart version (must match argocd-helm-src flake input)";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "argocd";
      description = "Namespace for ArgoCD deployment";
    };

    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
      description = "Additional Helm values to merge";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # Create namespace using kubernetes.resources (easykubenix pattern)
      # "none" namespace means cluster-scoped resource
      kubernetes.resources.none.Namespace.${cfg.namespace} = { };

      # Import ArgoCD CRDs from source
      # Helm chart includeCRDs=false by default, so we import them separately
      # This ensures CRDs are deployed before ArgoCD controller starts
      # Filter out kustomization.yaml which is not a Kubernetes resource
      importyaml = lib.pipe (builtins.readDir crdDir) [
        (lib.filterAttrs (_name: type: type == "regular"))
        (lib.filterAttrs (name: _type: lib.hasSuffix ".yaml" name))
        (lib.filterAttrs (name: _type: name != "kustomization.yaml"))
        (lib.mapAttrs' (
          filename: _type: {
            name = "argocd-${filename}";
            value.src = mkCrdDrv filename;
          }
        ))
      ];

      helm.releases.${moduleName} = {
        namespace = cfg.namespace;
        chart = chartWithDeps;

        # Fix namespace for resources - some Helm charts don't template
        # metadata.namespace in all resources
        overrideNamespace = cfg.namespace;

        values = lib.recursiveUpdate {
          # Global settings
          global = {
            # Local dev: single replica for all components
            revisionHistoryLimit = 3;
          };

          # Application Controller
          controller = {
            replicas = 1;
          };

          # API Server - insecure mode for kubectl port-forward
          server = {
            replicas = 1;
            # Disable TLS on server (use port-forward for local dev)
            insecure = true;
            # DNS config for proper resolution
            dnsConfig.options = [
              {
                name = "ndots";
                value = "1";
              }
            ];
          };

          # Repository Server
          repoServer = {
            replicas = 1;
            # DNS config for proper resolution
            dnsConfig.options = [
              {
                name = "ndots";
                value = "1";
              }
            ];
          };

          # Redis (for caching)
          redis = {
            enabled = true;
          };

          # Disable HA redis for local dev
          redis-ha.enabled = false;

          # ApplicationSet Controller
          applicationSet = {
            replicas = 1;
          };

          # Notifications Controller
          notifications = {
            enabled = false; # Disable for local dev
          };

          # Dex (OIDC) - disable for local dev
          dex.enabled = false;

          # Server config params (alternative to server.insecure)
          configs = {
            params = {
              "server.insecure" = true;
            };
            # RBAC: allow admin to do everything
            rbac = {
              "policy.default" = "role:admin";
            };
          };

          # CRDs managed separately via importyaml
          crds = {
            install = false;
            keep = true;
          };
        } cfg.helmValues;
      };

      # Default AppProject for cluster-wide access
      # Allows applications to deploy to any namespace and use any source
      kubernetes.resources.${cfg.namespace}.AppProject.default = {
        spec = {
          description = "Default project for all applications";
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
          namespaceResourceWhitelist = [
            {
              group = "*";
              kind = "*";
            }
          ];
        };
      };
    })

    # API mappings always defined (allows other modules to reference ArgoCD types)
    {
      kubernetes.apiMappings = {
        Application = "argoproj.io/v1alpha1";
        AppProject = "argoproj.io/v1alpha1";
        ApplicationSet = "argoproj.io/v1alpha1";
      };
      kubernetes.namespacedMappings = {
        Application = true;
        AppProject = true;
        ApplicationSet = true;
      };
    }
  ];
}
