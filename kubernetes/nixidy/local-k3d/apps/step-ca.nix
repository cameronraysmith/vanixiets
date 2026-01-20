# step-ca ACME server adoption Application for Phase 4 bootstrap
#
# Adopts existing step-ca deployment from Phase 3b (kluctl/easykubenix).
# ArgoCD takes ownership via ServerSideApply without recreating resources.
#
# The Helm values MUST match what easykubenix deployed exactly.
# Uses flake input for chart source (not available in nixhelm).
#
# Note: This Application only manages the Helm release. The ConfigMaps
# (step-ca-step-certificates-certs, step-ca-step-certificates-config) and
# SopsSecret (step-ca-secrets) were created by easykubenix and are not
# managed by this nixidy Application. They remain in place from kluctl.
{
  lib,
  config,
  charts,
  step-ca-src,
  ...
}:
let
  namespace = "step-ca";
in
{
  applications.step-ca = {
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

    # Sync wave: CA infrastructure at -1 (before cert-manager at 0)
    annotations."argocd.argoproj.io/sync-wave" = "-1";

    # Use flake input for chart source (not in nixhelm)
    helm.releases.step-ca = {
      chart = "${step-ca-src}/step-certificates";

      # Values MUST match easykubenix kubernetes/modules/step-ca/default.nix
      values = {
        # Disable bootstrap and inject modes
        bootstrap.enabled = false;
        inject.enabled = false;

        # Use existingSecrets mode - helm creates nothing, mounts pre-existing resources
        existingSecrets = {
          enabled = true;
          ca = true; # Mount ca-password secret for --password-file flag
        };

        # Service configuration
        service = {
          type = "ClusterIP";
          port = 443;
          targetPort = 9000;
        };

        # Persistence for badger database
        ca = {
          db = {
            enabled = true;
            persistent = true;
            accessModes = [ "ReadWriteOnce" ];
            size = "1Gi";
          };
        };

        # Resource limits for local dev
        resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "500m";
            memory = "256Mi";
          };
        };

        # Single replica for local dev
        replicaCount = 1;
      };
    };

    # Ignore controller-managed fields and externally-managed resources
    ignoreDifferences = {
      # step-ca deployment
      Deployment-step-ca = {
        group = "apps";
        kind = "Deployment";
        name = "step-ca-step-certificates";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # CA password secret (managed by SopsSecret, not ArgoCD)
      Secret-ca-password = {
        group = "";
        kind = "Secret";
        name = "step-ca-step-certificates-ca-password";
        inherit namespace;
        jsonPointers = [ "/data" ];
      };
      # CA secrets (managed by SopsSecret, not ArgoCD)
      Secret-ca-secrets = {
        group = "";
        kind = "Secret";
        name = "step-ca-step-certificates-secrets";
        inherit namespace;
        jsonPointers = [ "/data" ];
      };
      # PVC may have storage class defaults applied
      PersistentVolumeClaim-db = {
        group = "";
        kind = "PersistentVolumeClaim";
        name = "step-ca-step-certificates";
        inherit namespace;
        jsonPointers = [
          "/spec/storageClassName"
          "/spec/volumeMode"
        ];
      };
    };
  };
}
