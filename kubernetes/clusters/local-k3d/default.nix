# Local k3d development cluster configuration
#
# Cilium CNI and step-ca ACME server for k3d-dev cluster.
# Cluster runs in k3d containers via OrbStack container runtime.
{ lib, ... }:
{
  # Deploy resources in dependency order via kluctl priority phases.
  # Priority values create barrier phases: all resources in prio-N complete before prio-N+1 starts.
  #
  # Phase ordering:
  # - prio-10: Namespaces (must exist before namespaced resources)
  # - prio-10: CustomResourceDefinitions (must register before CRs can be applied)
  # - prio-15: SopsSecret CRs (depends on CRD from prio-10)
  # - prio-18: RBAC resources (ServiceAccount, Role, RoleBinding, etc. must exist before workloads)
  # - prio-20: DaemonSets (Cilium Agent needs CNI ready before other workloads)
  # - default: All other resources (Deployments, Services, etc.)
  #
  # The prio-18 barrier ensures RBAC resources exist before workloads reference them.
  # The prio-20 barrier deploys the Cilium Agent DaemonSet before other workloads.
  # Deployments (including Cilium Operator and ArgoCD) deploy in default phase together.
  # Using Deployment = 20 would deadlock: ArgoCD needs CNI but would be in the same
  # barrier phase waiting for Cilium Agent to be Ready.
  #
  # NOTE: Must use lib.mkOptionDefault to merge with easykubenix defaults,
  # otherwise this assignment replaces the entire default attrset.
  kluctl.resourcePriority = lib.mkOptionDefault {
    # RBAC resources must exist before workloads reference them
    ServiceAccount = 18;
    ClusterRole = 18;
    ClusterRoleBinding = 18;
    Role = 18;
    RoleBinding = 18;
    # SopsSecret depends on CRD
    SopsSecret = 15;
    # Cilium Agent DaemonSet in prio-20 to establish CNI before other workloads
    # NOTE: Do NOT add Deployment = 20 here - it affects ALL Deployments (ArgoCD,
    # sops-secrets-operator, Cilium Operator) causing scheduling deadlock
    DaemonSet = 20;
  };

  # Cluster identification
  clusterName = "k3d-dev";
  clusterHost = "127.0.0.1"; # k3d API server listens on loopback

  # CIDRs matching k3s defaults
  clusterPodCIDR = "10.42.0.0/16";
  clusterServiceCIDR = "10.43.0.0/16";

  # Enable Cilium CNI
  cilium.enable = true;
  cilium.version = "1.18.6";
  # k3d/OrbStack eBPF accommodations:
  # - Disable kube-proxy replacement (use k3s native kube-proxy)
  # - Disable BPF masquerade (use iptables masquerade instead)
  cilium.helmValues = {
    kubeProxyReplacement = false;
    bpf.masquerade = false;
    enableIPv4Masquerade = true;
  };

  # Enable step-ca ACME server for local TLS
  step-ca.enable = true;
  step-ca.caCerts = {
    rootCert = ../local/pki/root_ca.crt;
    intermediateCert = ../local/pki/intermediate_ca.crt;
  };
  # SopsSecret for CA private keys (processed by sops-secrets-operator)
  step-ca.sopsSecretFile = ../../../secrets/clusters/local/step-ca-sopssecret.enc.yaml;

  # Enable sops-secrets-operator for secret management
  sops-secrets-operator.enable = true;

  # Enable ArgoCD for GitOps (Phase 3b)
  # Insecure mode for local dev - access via kubectl port-forward
  argocd.enable = true;
}
