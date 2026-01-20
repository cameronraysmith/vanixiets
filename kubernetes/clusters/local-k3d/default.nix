# Local k3d development cluster configuration
#
# Cilium CNI with Gateway API and step-ca ACME server for k3d-dev cluster.
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
  # - prio-20: DaemonSet (Cilium CNI agents must be running before other pods can schedule)
  # - default: All other resources (Deployments, Services, etc.)
  #
  # The prio-18 barrier ensures RBAC resources exist before DaemonSets reference them.
  # The prio-20 barrier ensures Cilium DaemonSets are applied before services like
  # ArgoCD, step-ca, and sops-secrets-operator attempt to schedule pods.
  # Without CNI readiness, pods fail with "network plugin is not ready".
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
    # CNI DaemonSets must run before other pods can schedule
    DaemonSet = 20;
  };

  # Cluster identification
  clusterName = "k3d-dev";
  clusterHost = "127.0.0.1"; # k3d API server listens on loopback

  # CIDRs matching k3s defaults
  clusterPodCIDR = "10.42.0.0/16";
  clusterServiceCIDR = "10.43.0.0/16";

  # Enable Gateway API CRDs (must be installed before Cilium gatewayAPI)
  gateway-api.enable = true;
  gateway-api.version = "1.4.1";

  # Enable Cilium CNI with Gateway API
  cilium.enable = true;
  cilium.version = "1.18.6";
  # k3d/OrbStack eBPF accommodations:
  # - Disable kube-proxy replacement (use k3s native kube-proxy)
  # - Disable BPF masquerade (use iptables masquerade instead)
  # Gateway API enablement for ingress via Cilium
  cilium.helmValues = {
    kubeProxyReplacement = false;
    bpf.masquerade = false;
    enableIPv4Masquerade = true;

    # Gateway API support
    gatewayAPI.enabled = true;

    # Host network mode for gateway pods in k3d (no cloud LoadBalancer)
    # Allows external access via node ports
    gatewayAPI.hostNetwork.enabled = true;
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
