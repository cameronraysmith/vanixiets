# cert-manager Application for Phase 4 native deployment
#
# First Phase 4 native application: ArgoCD deploys cert-manager from scratch.
# Unlike Phase 3 adoption apps, this creates a fresh deployment with new namespace.
#
# Uses nixhelm chart source (jetstack/cert-manager).
# Sync wave 0: after Phase 3 infrastructure (-1), before ClusterIssuers (1).
{
  lib,
  config,
  charts,
  ...
}:
let
  namespace = "cert-manager";
in
{
  applications.cert-manager = {
    inherit namespace;

    # Phase 4 native: fresh deployment, ArgoCD creates namespace
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        # Native deployment: no server-side apply needed
        createNamespace = true;
      };
    };

    # Sync wave 0: after Phase 3 operators (-1), before ClusterIssuers (1)
    annotations."argocd.argoproj.io/sync-wave" = "0";

    # Use nixhelm chart (jetstack namespace)
    helm.releases.cert-manager = {
      chart = charts.jetstack.cert-manager;

      values = {
        # Install CRDs via Helm (Phase 4 native)
        installCRDs = true;

        # Single replica for local dev
        replicaCount = 1;

        # Webhook configuration
        webhook = {
          replicaCount = 1;
          timeoutSeconds = 30;
        };

        # CA injector for webhook certificates
        cainjector = {
          replicaCount = 1;
        };

        # Extra args for cluster resource namespace
        extraArgs = [
          "--cluster-resource-namespace=${namespace}"
        ];

        # Resource limits for local dev
        resources = {
          requests = {
            cpu = "50m";
            memory = "64Mi";
          };
          limits = {
            cpu = "200m";
            memory = "256Mi";
          };
        };
      };
    };

    # Ignore controller-managed fields
    ignoreDifferences = {
      # cert-manager controller deployment
      Deployment-cert-manager = {
        group = "apps";
        kind = "Deployment";
        name = "cert-manager";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # cert-manager webhook deployment
      Deployment-cert-manager-webhook = {
        group = "apps";
        kind = "Deployment";
        name = "cert-manager-webhook";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # cert-manager cainjector deployment
      Deployment-cert-manager-cainjector = {
        group = "apps";
        kind = "Deployment";
        name = "cert-manager-cainjector";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # Webhook secrets are generated at runtime
      Secret-webhook-ca = {
        group = "";
        kind = "Secret";
        name = "cert-manager-webhook-ca";
        inherit namespace;
        jsonPointers = [ "/data" ];
      };
    };
  };
}
