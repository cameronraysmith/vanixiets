# sops-secrets-operator module for easykubenix
#
# Deploys sops-secrets-operator for Kubernetes-native secret management.
# Decrypts SopsSecret CRs into native Kubernetes Secrets using age encryption.
#
# Receives sops-secrets-operator-src from flake inputs via specialArgs to avoid
# impure fetchTree calls during pure evaluation.
#
# Prerequisites - create age key secret before deploying:
#   kubectl create namespace sops-secrets-operator
#   kubectl create secret generic sops-age-key \
#     --namespace=sops-secrets-operator \
#     --from-file=age.key=$HOME/.config/sops/age/keys.txt
#
# Production bootstrap (Hetzner) handled separately via clan secrets.
{
  config,
  lib,
  pkgs,
  sops-secrets-operator-src,
  ...
}:
let
  moduleName = "sops-secrets-operator";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.17.3";
      description = "sops-secrets-operator version to deploy (compatible with k8s 1.34.x)";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "sops-secrets-operator";
      description = "Namespace for sops-secrets-operator deployment";
    };

    ageKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "sops-age-key";
      description = "Name of Kubernetes Secret containing age private key";
    };

    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
      description = "Additional Helm values to merge";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create namespace using kubernetes.resources (easykubenix pattern)
    # "none" namespace means cluster-scoped resource
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };

    helm.releases.${moduleName} = {
      namespace = cfg.namespace;
      chart = "${sops-secrets-operator-src}/chart/helm3/sops-secrets-operator";

      values = lib.recursiveUpdate {
        # Single replica for simplicity
        replicaCount = 1;

        # Watch all namespaces (cluster-wide secret management)
        namespaced = false;

        # Image version
        image.tag = cfg.version;

        # Mount age key secret as file
        secretsAsFiles = [
          {
            name = cfg.ageKeySecret;
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
      } cfg.helmValues;
    };
  };
}
