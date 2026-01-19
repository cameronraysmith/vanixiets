# Local k3d development cluster configuration
#
# Cilium CNI and step-ca ACME server for k3d-dev cluster.
# Cluster runs in k3d containers via OrbStack container runtime.
{ ... }:
{
  # Deploy SopsSecret CRs in prio-10 phase (before helm releases in default phase)
  # This ensures sops-secrets-operator can create Kubernetes Secrets before
  # helm charts try to create conflicting secrets with the same names
  kluctl.resourcePriority.SopsSecret = 10;

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
}
