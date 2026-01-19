# sops-secrets-operator module for easykubenix
#
# Deploys sops-secrets-operator for Kubernetes-native secret management.
# Decrypts SopsSecret CRs into native Kubernetes Secrets using age encryption.
#
# Receives sops-secrets-operator-src from flake inputs via specialArgs to avoid
# impure fetchTree calls during pure evaluation.
#
# This module demonstrates the canonical easykubenix pattern for operators with CRDs:
# 1. importyaml for CRD deployment (helm includeCRDs=false by default)
# 2. apiMappings to register custom resource types with API group/version
# 3. namespacedMappings to declare scope (namespaced vs cluster-scoped)
# 4. overrideNamespace to fix charts that don't template metadata.namespace
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
      default = "0.16.0";
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

    # Import CRD via importyaml (helm includeCRDs=false by default)
    # This ensures the SopsSecret CRD is deployed before operator starts
    importyaml."${moduleName}-crd" = {
      src = "${sops-secrets-operator-src}/config/crd/bases/isindir.github.com_sopssecrets.yaml";
    };

    # Register SopsSecret custom resource type with easykubenix
    # Required for overrideNamespace and proper resource handling
    kubernetes.apiMappings.SopsSecret = "isindir.github.com/v1alpha3";
    kubernetes.namespacedMappings.SopsSecret = true;

    helm.releases.${moduleName} = {
      namespace = cfg.namespace;
      chart = "${sops-secrets-operator-src}/chart/helm3/sops-secrets-operator";

      # Fix namespace for resources - the upstream Helm chart doesn't template
      # metadata.namespace in Deployment/ServiceAccount, causing them to render
      # without namespace and fall into "none" (cluster-scoped) in easykubenix.
      # overrideNamespace applies metadata.namespace to all namespaced resources.
      overrideNamespace = cfg.namespace;

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
            name = "sops-age-key-file";
            secretName = cfg.ageKeySecret;
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
