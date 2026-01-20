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
  lib,
  deploymentLayer ? "all",
  ...
}:
let
  isFoundation = deploymentLayer == "foundation" || deploymentLayer == "all";
  isInfrastructure = deploymentLayer == "infrastructure" || deploymentLayer == "all";
in
{
  # Deploy resources in dependency order via kluctl priority phases.
  # Priority values create barrier phases: all resources in prio-N complete before prio-N+1 starts.
  #
  # Phase ordering (easykubenix defaults + local overrides):
  # - prio-10: Namespaces, CustomResourceDefinitions (easykubenix defaults)
  # - prio-15: SopsSecret CRs (local override, depends on CRD from prio-10)
  # - default: All workloads (DaemonSets, Deployments, Services, etc.)
  #
  # Cilium Agent (DaemonSet) and Operator (Deployment) must deploy together in
  # the same phase. Separating them (e.g., DaemonSet = 20) creates circular
  # dependencies: Agent waits for Operator CRDs, but Operator can't schedule
  # until Agent provides CNI.
  #
  # NOTE: Must use lib.mkOptionDefault to merge with easykubenix defaults,
  # otherwise this assignment replaces the entire default attrset.
  kluctl.resourcePriority = lib.mkOptionDefault {
    SopsSecret = 15;
  };

  # Cluster identification
  clusterName = "k3d-dev";
  clusterHost = "127.0.0.1"; # k3d API server listens on loopback

  # CIDRs matching k3s defaults
  clusterPodCIDR = "10.42.0.0/16";
  clusterServiceCIDR = "10.43.0.0/16";

  # ==========================================================================
  # Foundation layer (CNI) - must be deployed and ready before infrastructure
  # ==========================================================================

  # Enable Cilium CNI
  cilium.enable = isFoundation;
  cilium.version = "1.18.6";
  # k3d/OrbStack eBPF accommodations:
  # - Disable kube-proxy replacement (use k3s native kube-proxy)
  # - Disable BPF masquerade (use iptables masquerade instead)
  cilium.helmValues = {
    kubeProxyReplacement = false;
    bpf.masquerade = false;
    enableIPv4Masquerade = true;
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
}
