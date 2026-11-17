# Local k3d development cluster configuration
#
# Cilium CNI and step-ca ACME server for k3d-dev cluster.
# Cluster runs in k3d containers via OrbStack container runtime.
#
# Supports staged deployment via deploymentLayer parameter:
# - "foundation": CNI only (Cilium) - must be ready before infrastructure
# - "infrastructure": Platform services (ArgoCD, cert-manager, secrets)
# - "all" (default): Everything - use only after foundation is ready
#
# This mirrors the kargo pattern of sequential helm --wait installs but in
# declarative Nix. Foundation must be deployed first because infrastructure
# pods cannot schedule until CNI is ready.
{
  deploymentLayer ? "all",
  ...
}:
let
  isFoundation = deploymentLayer == "foundation" || deploymentLayer == "all";
  isInfrastructure = deploymentLayer == "infrastructure" || deploymentLayer == "all";
in
{
  # Deploy resources in dependency order via kluctl priority phases.
  # Priority values create barrier phases: all resources in prio-N are applied
  # before prio-N+1 starts.
  #
  # easykubenix numbers Helm's InstallOrder in steps of ten
  # (`ekn.resourcePriority`: Namespace = 20, CustomResourceDefinition = 150,
  # DaemonSet = 250, Deployment = 290, ...); unlisted kinds go to `default`.
  # SopsSecret CRs sit at 155: after their CRD, before the workloads that
  # mount the Secrets they decrypt into.
  #
  # Set per entry, never as `mkDefault`/`mkOptionDefault` of an attrset:
  # upstream defines the defaults as a plain attrset of `mkDefault` leaves, so
  # a lower-priority attrset definition is discarded whole, silently.
  ekn.resourcePriority.SopsSecret = 155;

  # Cluster identification
  clusterName = "k3d-dev";
  clusterHost = "127.0.0.1"; # k3d API server listens on loopback

  # CIDRs matching k3s defaults
  clusterPodCIDR = "10.42.0.0/16";
  clusterServiceCIDR = "10.43.0.0/16";

  # ==========================================================================
  # Foundation layer (CNI) - must be deployed and ready before infrastructure
  # ==========================================================================

  # Gateway API CRDs ship with the CNI: cilium-operator starts its Gateway
  # controller only if they exist when it starts (kubernetes/modules/gateway-api).
  gateway-api.enable = isFoundation;

  # Enable Cilium CNI
  cilium.enable = isFoundation;
  cilium.version = "1.20.2";
  # k3d/OrbStack eBPF accommodations:
  # - Kube-proxy replacement on, as in the production module: cilium >= 1.19
  #   runs its Gateway API controller only with kube-proxy replacement
  #   (operator/pkg/gateway-api/cell.go), and ctlptl.nix disables the k3s
  #   kube-proxy to match. BPF masquerade is left at the module default.
  cilium.helmValues = {
    kubeProxyReplacement = true;
    # Disable sysctlfix init container - fails in k3d/kind containers
    # because /proc/sys is read-only
    sysctlfix.enabled = false;
    # Gateway API support for ingress
    # hostNetwork disabled - use k3s servicelb for LoadBalancer IP assignment
    gatewayAPI.enabled = true;
    gatewayAPI.hostNetwork.enabled = false;
  };

  # ==========================================================================
  # Infrastructure layer (platform services) - requires CNI to be ready
  # ==========================================================================

  # Enable sops-secrets-operator for secret management
  sops-secrets-operator.enable = isInfrastructure;

  # Enable step-ca ACME server for local TLS
  step-ca.enable = isInfrastructure;
  step-ca.caCerts = {
    rootCert = ../local/pki/root_ca.crt;
    intermediateCert = ../local/pki/intermediate_ca.crt;
  };
  # SopsSecret for CA private keys (processed by sops-secrets-operator)
  step-ca.sopsSecretFile = ../../../secrets/clusters/local/step-ca-sopssecret.enc.yaml;

  # Enable ArgoCD for GitOps (Phase 3b)
  # Insecure mode for local dev - access via kubectl port-forward
  argocd.enable = isInfrastructure;
  # Repository credentials for private local-k3d manifest repo (ADR-006)
  # SopsSecret decrypted by sops-secrets-operator, discovered by ArgoCD via label
  argocd.repoCredentialsSopsSecretFile = ../../../secrets/clusters/local/argocd-repo-credentials.enc.yaml;
}
