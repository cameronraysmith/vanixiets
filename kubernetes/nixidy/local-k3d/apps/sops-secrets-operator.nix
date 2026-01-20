# sops-secrets-operator adoption Application for Phase 4 bootstrap
#
# Adopts existing sops-secrets-operator deployment from Phase 3b (kluctl/easykubenix).
# ArgoCD takes ownership via ServerSideApply without recreating resources.
#
# The Helm values MUST match what easykubenix deployed exactly.
# Uses flake input for chart source to ensure version alignment.
{
  lib,
  config,
  charts,
  sops-secrets-operator-src,
  ...
}:
let
  namespace = "sops-secrets-operator";
  ageKeySecret = "sops-age-key";
  version = "0.16.0";
in
{
  applications.sops-secrets-operator = {
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

    # Sync wave: operators at -1 (after CRDs at -2)
    annotations."argocd.argoproj.io/sync-wave" = "-1";

    # Use flake input for chart source (same as easykubenix)
    helm.releases.sops-secrets-operator = {
      chart = "${sops-secrets-operator-src}/chart/helm3/sops-secrets-operator";

      # Values MUST match easykubenix kubernetes/modules/sops-secrets-operator/default.nix
      values = {
        # Single replica for simplicity
        replicaCount = 1;

        # Watch all namespaces (cluster-wide secret management)
        namespaced = false;

        # Image version
        image.tag = version;

        # Mount age key secret as file
        secretsAsFiles = [
          {
            name = "sops-age-key-file";
            secretName = ageKeySecret;
            mountPath = "/etc/sops-age";
          }
        ];

        # Configure SOPS to use age key file
        extraEnv = [
          {
            name = "SOPS_AGE_KEY_FILE";
            value = "/etc/sops-age/age.key";
          }
        ];

        # RBAC for cluster-wide secret management
        rbac.enabled = true;

        # Service account for RBAC binding
        serviceAccount.enabled = true;
      };
    };

    # Ignore controller-managed fields
    ignoreDifferences = {
      # Operator deployment
      Deployment-sops-secrets-operator = {
        group = "apps";
        kind = "Deployment";
        name = "sops-secrets-operator";
        inherit namespace;
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # Secrets may have generated or reconciled content
      Secret-age-key = {
        group = "";
        kind = "Secret";
        name = ageKeySecret;
        inherit namespace;
        # Secret data is managed externally, not by ArgoCD
        jsonPointers = [ "/data" ];
      };
    };
  };
}
