# ArgoCD self-management adoption Application for Phase 4 bootstrap
#
# Adopts existing ArgoCD deployment from Phase 3b (kluctl/easykubenix).
# ArgoCD takes ownership of itself via ServerSideApply without recreating resources.
#
# The Helm values MUST match what easykubenix deployed exactly.
# Uses flake input for chart source to ensure version alignment.
#
# Self-management pattern: ArgoCD manages its own Application CR, enabling
# GitOps updates to ArgoCD itself through the same workflow as other apps.
{
  lib,
  config,
  pkgs,
  charts,
  argocd-src,
  argocd-helm-src,
  ...
}:
let
  namespace = "argocd";

  # Pre-process Helm chart to remove external dependency (same as easykubenix)
  # The argo-cd chart has a conditional dependency on redis-ha that helm checks for
  # even when disabled. Since we're disabling redis-ha for local dev, we patch
  # Chart.yaml to remove the dependency entirely.
  chartWithDeps =
    pkgs.runCommand "argocd-helm-chart"
      {
        nativeBuildInputs = [ pkgs.yq-go ];
      }
      ''
        cp -r ${argocd-helm-src}/charts/argo-cd $out
        chmod -R u+w $out
        # Remove the redis-ha dependency from Chart.yaml
        yq -i 'del(.dependencies)' $out/Chart.yaml
        # Also remove Chart.lock to avoid dependency check
        rm -f $out/Chart.lock
      '';
in
{
  applications.argocd = {
    inherit namespace;

    # Adoption-safe sync options
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
        applyOutOfSyncOnly = true;
        # Namespace exists from kluctl deployment
        createNamespace = false;
      };
    };

    # Sync wave: ArgoCD at -1 (infrastructure component)
    # Must be operational before managing other applications
    annotations."argocd.argoproj.io/sync-wave" = "-1";

    # Use pre-processed chart (same as easykubenix)
    helm.releases.argocd = {
      chart = chartWithDeps;

      # Values MUST match easykubenix kubernetes/modules/argocd/default.nix
      values = {
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

        # CRDs managed separately (already deployed by kluctl)
        crds = {
          install = false;
          keep = true;
        };
      };
    };

    # Ignore controller-managed fields
    ignoreDifferences = {
      # Application controller statefulset
      StatefulSet-application-controller = {
        group = "apps";
        kind = "StatefulSet";
        name = "argocd-application-controller";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # API server deployment
      Deployment-server = {
        group = "apps";
        kind = "Deployment";
        name = "argocd-server";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # Repo server deployment
      Deployment-repo-server = {
        group = "apps";
        kind = "Deployment";
        name = "argocd-repo-server";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # Redis deployment
      Deployment-redis = {
        group = "apps";
        kind = "Deployment";
        name = "argocd-redis";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # ApplicationSet controller deployment
      Deployment-applicationset = {
        group = "apps";
        kind = "Deployment";
        name = "argocd-applicationset-controller";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # ArgoCD secrets (admin password, TLS certs generated at runtime)
      Secret-argocd-secret = {
        group = "";
        kind = "Secret";
        name = "argocd-secret";
        inherit namespace;
        jsonPointers = [ "/data" ];
      };
      # ConfigMaps may have runtime modifications
      ConfigMap-argocd-cm = {
        group = "";
        kind = "ConfigMap";
        name = "argocd-cm";
        inherit namespace;
        jsonPointers = [
          "/data/url"
          "/data/application.instanceLabelKey"
        ];
      };
    };
  };
}
